---
title: I.MX6U 主机驱动分析
---

# 拆开 spi-imx.c：I.MX6U 的 SPI 主机驱动长什么样

上一节我们讲了 SPI 框架，也特意点名了那次"master → controller"的改名、以及"transfer → transfer_one"的迁移。光说不练假把式，这一节我们直接钻进 `drivers/spi/spi-imx.c`，看看 NXP 的工程师是怎么用现代 API 写一个 SPI 主机驱动的——它正好是我们讲的那些"新写法"的活样本。我们把注意力放在四处：怎么申请 controller、怎么填它的能力、挂哪些回调、怎么注册。

## 申请 controller：spi_alloc_host，不是 spi_alloc_master

主机驱动注册成 platform 驱动，`probe` 里第一件事就是申请一个 `spi_controller`。看 `spi-imx.c` 的 `spi_imx_probe`，`1855` 行附近：

```c
/* drivers/spi/spi-imx.c，spi_imx_probe() 内 */
target_mode = of_property_read_bool(np, "spi-slave");

if (target_mode)
    controller = spi_alloc_target(&pdev->dev, sizeof(struct spi_imx_data));
else
    controller = spi_alloc_host(&pdev->dev, sizeof(struct spi_imx_data));

if (!controller)
    return -ENOMEM;
```

看到没有，它用的是 **`spi_alloc_host`**，而不是老教程里那个 `spi_alloc_master`。`spi_alloc_host` 的第二个参数 `sizeof(struct spi_imx_data)` 是"顺带申请的私有数据大小"——它不光分配 `spi_controller` 本身，还额外给你留一段内存存驱动私有状态（寄存器基址、时钟、当前配置等），回头用 `spi_controller_get_devdata` 能取回来。这段代码还顺手展示了 host/target 双角色的处理：读设备树里的 `spi-slave` 属性，有就当从机（target）申请、没有就当主机（host）申请。我们做主机，走 `spi_alloc_host` 这条分支。

::: tip 6.12 和 7.1 在这里的差别
6.12 的 `spi-imx.c` 用的是 `spi_alloc_host` + `spi_register_controller`（非 devm，`probe` 出错要手动 `spi_controller_put` 回收）。到了 7.1，这份驱动升级成了 `devm_spi_alloc_host`——托管版，`probe` 失败或设备移除时内核自动回收，省掉了手动清理。两版都只实现 `transfer_one`、都不用 bitbang。对我们写设备驱动没影响，但你读 7.1 的源码会看到 `devm_` 前缀。
:::

## 给 controller 填能力：它支持什么、挂在哪

controller 申请下来是空的，得告诉它"我是谁、我能干什么"。`spi-imx.c` 在 `1873` 行附近填了一组能力字段：

```c
/* drivers/spi/spi-imx.c */
controller->bits_per_word_mask = SPI_BPW_RANGE_MASK(1, 32);  /* 支持 1~32 位字宽 */
controller->bus_num            = np ? -1 : pdev->id;          /* 设备树下让核心自动分配 */
controller->use_gpio_descriptors = true;                      /* 片选走设备树 cs-gpios */
/* ...... */
controller->mode_bits          = SPI_CPOL | SPI_CPHA | SPI_CS_HIGH | SPI_NO_CS
                                 | SPI_MOSI_IDLE_LOW;
```

这几行信息量不小，我们一条条看。`bits_per_word_mask = SPI_BPW_RANGE_MASK(1, 32)` 告诉核心：这个控制器能传 1 到 32 位字宽的任何值。`bus_num = np ? -1 : pdev->id`：有设备树节点（`np` 非空）时填 `-1`，意思是"总线号你来分配"，SPI 核心会按设备树出现顺序给控制器编上号；没设备树的老平台才用 `pdev->id` 指定。

最值得说的一句是 `use_gpio_descriptors = true`。它把"片选怎么拉"这件事交给了 SPI 核心代劳——核心会去读设备树控制器节点上的 `cs-gpios`，把那些 GPIO 取成描述符、在每次传输前后自动拉低/拉高。所以我们这个主机驱动**没有实现 `set_cs` 回调**，片选全是核心用 GPIO 描述符管的。这也解释了为什么下一节设备树里 `cs-gpios` 那一行那么关键：配错了或漏了，核心就不知道拿哪个 GPIO 当片选，设备永远等不到 CS 拉低。`mode_bits` 那行声明控制器支持的时钟模式：`SPI_CPOL`/`SPI_CPHA` 是四种 CPOL/CPHA 组合，`SPI_CS_HIGH` 是高电平有效片选，这些是给上面设备驱动的 `spi->mode` 做合法性校验用的。

## 挂回调：transfer_one 是主角

能力填完，挂上传输回调。`spi-imx.c` 在 `1895` 行附近挂的是这么一组：

```c
/* drivers/spi/spi-imx.c */
controller->transfer_one       = spi_imx_transfer_one;
controller->setup              = spi_imx_setup;
controller->prepare_message    = spi_imx_prepare_message;
controller->unprepare_message  = spi_imx_unprepare_message;
controller->target_abort       = spi_imx_target_abort;
```

注意这里挂的是 **`transfer_one`**，不是老教程说的那个 `transfer`。这正是上一节强调的"现代队列化驱动"的标志：主机驱动只负责"处理单个 `spi_transfer`"（`transfer_one`），而把"把多个 transfer 串成 message、按队列调度"的活儿（`transfer_one_message`）交给 SPI 核心的通用实现。所以你看不到 `controller->transfer = ...` 这一行——一旦设了 `transfer`，核心反而会退回老路径。

`setup` 在设备驱动调 `spi_setup` 时被回调，负责把 mode、时钟、字宽写进硬件。`prepare_message` / `unprepare_message` 在一整条 `spi_message` 发送前后被调用，给主机驱动一个"准备/收尾整条消息"的机会（比如配置寄存器基址、切时钟）。`target_abort` 是从机模式用的，主机模式用不到。这套回调组合，就是现代 SPI 主机驱动的标配。

## 注册：spi_register_controller

一切就绪，最后注册进 SPI 核心。`spi-imx.c:1995`：

```c
/* drivers/spi/spi-imx.c */
controller->dev.of_node = pdev->dev.of_node;
ret = spi_register_controller(controller);
if (ret) {
    dev_err_probe(&pdev->dev, ret, "register controller failed\n");
    /* ...... 出错清理 ...... */
}
```

注册前先把 `dev.of_node` 指好，让 controller 和设备树节点关联起来。`spi_register_controller` 成功后，这条 SPI 总线就算通了，挂在下面的设备节点（设备树里 `&ecspi3` 的子节点）会被逐一实例化成 `spi_device`，再去找匹配的 `spi_driver`。出错的 `dev_err_probe` 是现代写法，它会顺便把 `-EPROBE_DEFER` 之类的情况打印得更友好。

## of_match_table + platform_driver：和 i2c-imx 同构

最后这套老套路和 [I2C 那篇拆 i2c-imx.c](../08_i2c_ap3216c_driver/03_i2c_adapter_analysis.md) 完全一样。`spi-imx.c` 通过 of_match 表声明自己支持哪些 SoC，`1187` 行：

```c
/* drivers/spi/spi-imx.c */
static const struct of_device_id spi_imx_dt_ids[] = {
    /* ...... */
    { .compatible = "fsl,imx51-ecspi",  .data = &imx51_ecspi_devtype_data,  },
    /* ...... */
    { .compatible = "fsl,imx6ul-ecspi", .data = &imx6ul_ecspi_devtype_data, },
    /* ...... */
};

static struct platform_driver spi_imx_driver = { /* ...... */ };
module_platform_driver(spi_imx_driver);    /* 2104 行 */
```

`fsl,imx6ul-ecspi` 正是我们板子 ECSPI 控制器的 compatible，`spi-imx.c` 靠它和设备树里的 `&ecspi3` 节点匹配。整个驱动以 `module_platform_driver` 注册成 platform 驱动（`2104` 行）——和 `i2c-imx.c` 一样，I.MX6U 的 SPI 控制器先以 platform 设备身份上车、拿内存/中断/时钟资源，再在 `probe` 里把自己注册成 SPI controller，向 SPI 核心报到。两层身份、各司其职，这套设计在两条总线上完全对称。

## 小结

这一节我们拆开了 `spi-imx.c`，看清了四件事：它用 `spi_alloc_host`（7.1 是 `devm_spi_alloc_host`）申请 controller，用 `use_gpio_descriptors=true` 把片选交给核心管、所以不设 `set_cs`，挂的是现代的 `transfer_one` 而非老的 `transfer`，最后以 platform 驱动身份注册、再向 SPI 核心报到。这些认知直接决定了下一节设备树该怎么写——尤其 `cs-gpios` 那行，现在你知道它为什么是必须的了。

---

<ChapterNav variant="sub">
  <ChapterLink href="02_spi_framework.md" variant="sub">← SPI 驱动框架</ChapterLink>
  <ChapterLink href="04_driver_layer.md" variant="sub">ICM-20608 驱动层实现 →</ChapterLink>
</ChapterNav>
