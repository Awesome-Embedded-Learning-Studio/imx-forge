---
title: SPI 驱动框架
---

# SPI 驱动框架 —— 主机、设备、驱动，和那次改名

如果你刚读完 I2C 那篇，来到 SPI 这儿会有种"似曾相识"的踏实感——因为 Linux 的 SPI 框架和 I2C 几乎是一个模子刻出来的，遵循同一套哲学：**把通用的总线控制和特定的设备逻辑剥离开**。主机驱动负责"怎么把比特发出去"，设备驱动负责"我要发什么"，中间靠 SPI 核心层粘合。所以这一节我们会讲得比 I2C 那节快一些，重点放在那些 SPI **特有**的、以及这几内核**改过名**的地方——这些恰恰是老教程最容易踩雷的所在。

## 主机驱动：spi_controller（注意，不再叫 spi_master 了）

SPI 主机驱动对应 SoC 内部的 SPI 控制器，地位等同 I2C 里的适配器驱动。内核用 `spi_controller` 结构体来表示它，定义在 `include/linux/spi/spi.h`。我们先看它的核心成员：

```c
/*
 * spi_controller 结构体（节选自 include/linux/spi/spi.h）
 * 老代码里的 spi_master，就是它
 */
struct spi_controller {
    struct device    dev;
    struct list_head list;

    s16  bus_num;            /* 总线编号，spi0/spi1...；设备树下填 -1 自动分配 */
    u16  num_chipselect;     /* 支持的片选数量 */
    u16  mode_bits;          /* 支持的 mode 标志（CPOL/CPHA/CS_HIGH...） */
    u32  bits_per_word_mask; /* 支持的字宽掩码 */
    u32  min_speed_hz;
    u32  max_speed_hz;       /* 传输速度上下限 */

    /* 设备树 cs-gpios 处理后填这里，决定片选怎么拉 */
    struct gpio_desc **cs_gpiods;
    bool              use_gpio_descriptors;

    int  (*setup)(struct spi_device *spi);          /* 固化设备参数到硬件 */

    /* 老式 bitbang 驱动才实现这个，现代驱动不要碰 */
    int  (*transfer)(struct spi_device *spi, struct spi_message *mesg);

    /* 现代队列化驱动实现这一个：处理单个 spi_transfer */
    int  (*transfer_one)(struct spi_controller *ctlr,
                         struct spi_device *spi,
                         struct spi_transfer *transfer);
    int  (*prepare_message)(struct spi_controller *ctlr, struct spi_message *message);
    void (*set_cs)(struct spi_device *spi, bool enable);   /* 片选回调（可选） */
    /* ...... */
};
```

这里有个绕不开的话题：**改名**。这份结构体在老内核里叫 `spi_master`，老教程也全程用 `spi_master`。但 SPI 后来支持了从机角色（SPI target，老叫法 slave），内核为了术语中性、也为了同时容纳主机/从机两种身份，把结构体改名 `spi_controller`，角色命名也从 master/slave 换成了 host/target。这是一次分两步走的迁移：6.12 里 `spi_alloc_master` 这类老 API 还作为**兼容别名**留着（内部转调 `spi_alloc_host`），但到了 7.1，这些带 "master" 的包装函数被**彻底删除**，只剩 `spi_alloc_host` / `spi_alloc_target`。所以你以后写控制器相关代码，统一用 `spi_controller` + `spi_alloc_host`，别再碰 master。

接下来要分清两个长得像、却分属新旧两代的回调。`.transfer` 是老式 bitbang 驱动实现的接口，现代队列化驱动**不要实现它**——只要设了 `.transfer`，SPI 核心就会走老的传输路径。现代驱动实现的是 `.transfer_one`，它一次只处理一个 `spi_transfer`，而把多个 transfer 串成 `spi_message`、统一调度的 `transfer_one_message` 由 SPI 核心层提供通用实现。这套"核心管队列、驱动管单次"的分工，正是现代 SPI 主机驱动的标志。下一节我们拆 `spi-imx.c` 时，会看到它实现的就是 `.transfer_one`。

主机驱动的注册也跟着改了名。申请用 `spi_alloc_host`（或托管版 `devm_spi_alloc_host`），注册用 `spi_register_controller`（或 `devm_spi_register_controller`）：

```c
/* 现代：申请 + 注册 */
struct spi_controller *ctlr;
ctlr = devm_spi_alloc_host(&pdev->dev, sizeof(struct spi_imx_data));
/* ...... 填 bus_num / mode_bits / transfer_one 等 ...... */
devm_spi_register_controller(&pdev->dev, ctlr);
```

不过这部分活儿 NXP 也替我们干完了，驱动就在 `drivers/spi/spi-imx.c`，下一节专门拆它。我们写设备驱动，基本不碰这套控制器 API。

## 设备驱动：spi_driver 和 spi_device

聊完主机的，轮到我们的主场——SPI 设备驱动。这一层和 `i2c_driver` / `platform_driver` 是一家子，结构体是 `spi_driver`，定义在 `spi/spi.h`：

```c
/*
 * spi_driver 结构体（include/linux/spi/spi.h）
 */
struct spi_driver {
    const struct spi_device_id *id_table;          /* 传统匹配表，可省略 */
    int  (*probe)(struct spi_device *spi);          /* 匹配成功回调 */
    void (*remove)(struct spi_device *spi);         /* 注意返回值是 void！ */
    void (*shutdown)(struct spi_device *spi);
    struct device_driver driver;                    /* 内嵌 driver，of_match_table 在这 */
};
```

你看，`probe` 的签名是 `int (*probe)(struct spi_device *spi)`——SPI 这边本来就一直只有一个参数，所以不存在 I2C 那种"砍参数"的迁移。但 `remove` 和 I2C 一样，返回值是 `void`：老教程里那个 `static int xxx_remove(...) { ...; return 0; }`，在新内核里赋给 `spi_driver.remove` 会触发指针类型不匹配警告，写新驱动记得改成 `void`。

和 `spi_driver` 配对的是 `spi_device`，它描述"挂在某条 SPI 总线、某个片选上的具体设备"。关键字段我们认一下：

```c
/*
 * spi_device 结构体（节选自 include/linux/spi/spi.h）
 */
struct spi_device {
    struct device         dev;
    struct spi_controller *controller;   /* 挂在哪个控制器上 */
    u32   max_speed_hz;                  /* 最大时钟，来自设备树 spi-max-frequency */
    u8    chip_select;                   /* 接在第几个片选上，对应设备树 reg */
    u8    bits_per_word;                 /* 字宽，默认 8 */
    u32   mode;                          /* SPI_CPOL / SPI_CPHA / SPI_CS_HIGH ... */
    int   irq;
    char  modalias[SPI_NAME_SIZE];       /* 名字，老式匹配用 */
    /* ...... */
};
```

`max_speed_hz` 来自设备树的 `spi-max-frequency`，`chip_select` 来自 `reg`，`mode` 来自 `spi-cpol`/`spi-cpha` 这些属性——这些字段大多由 SPI 核心层在解析设备树时自动填好，和 I2C 的 `i2c_client` 一样，你一般不用手动填。`spi_setup(spi)` 这个函数会把 `mode`、`max_speed_hz`、`bits_per_word` 这些固化到硬件，所以 `probe` 里改完 `spi->mode` 一定要调一次 `spi_setup`，否则配置不生效。

注册设备驱动，和 I2C 一模一样，`module_spi_driver` 宏替你包好 `module_init`/`module_exit`：

```c
/* include/linux/spi/spi.h */
#define spi_register_driver(driver)  __spi_register_driver(THIS_MODULE, driver)

#define module_spi_driver(__spi_driver) \
        module_driver(__spi_driver, spi_register_driver, spi_unregister_driver)
```

凑齐了，一个现代 SPI 设备驱动的注册骨架是这样：

```c
/*
 * 现代 spi_driver 注册骨架
 */
static int icm20608_probe(struct spi_device *spi)
{
    /* 函数具体程序 */
    return 0;
}

static void icm20608_remove(struct spi_device *spi)
{
    /* void，别 return 0 */
}

static const struct of_device_id icm20608_of_match[] = {
    { .compatible = "imxaes,icm20608" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, icm20608_of_match);

static struct spi_driver icm20608_driver = {
    .driver = {
        .name           = "icm20608",
        .of_match_table = icm20608_of_match,
    },
    .probe  = icm20608_probe,
    .remove = icm20608_remove,
};
module_spi_driver(icm20608_driver);

MODULE_AUTHOR("Charliechen114514");
MODULE_LICENSE("GPL");
```

和 I2C 那份骨架放一起看，你会发现除了 `i2c` 换成 `spi`、回调参数从 `i2c_client *` 换成 `spi_device *`，结构完全一致。这就是 Linux 驱动框架一旦学通、处处复用的好处。

## 它们是怎么"对上眼"的：spi_match_device

SPI 的匹配机制和 I2C 也是同构的，"月老"是 `spi_bus_type`：

```c
/*
 * spi_bus_type（drivers/spi/spi.c）
 * 现代内核里它也是 const struct bus_type
 */
const struct bus_type spi_bus_type = {
    .name        = "spi",
    .dev_groups  = spi_dev_groups,
    .match       = spi_match_device,    /* 匹配判断在这里 */
    .uevent      = spi_uevent,
    .probe       = spi_probe,
    .remove      = spi_remove,
    .shutdown    = spi_shutdown,
};
```

撮合逻辑在 `spi_match_device` 里，优先级链和 I2C 几乎一字不差：

```c
/*
 * spi_match_device（drivers/spi/spi.c）
 */
static int spi_match_device(struct device *dev, const struct device_driver *drv)
{
    const struct spi_device *spi = to_spi_device(dev);
    const struct spi_driver *sdrv = to_spi_driver(drv);

    /* 第一优先级：设备树（OF）匹配，比较 compatible */
    if (of_driver_match_device(dev, drv))
        return 1;

    /* 第二优先级：ACPI */
    if (acpi_driver_match_device(dev, drv))
        return 1;

    /* 第三优先级：传统 id_table 名字匹配 */
    if (sdrv->id_table)
        return !!spi_match_id(sdrv->id_table, spi);

    /* 最后兜底：直接比 spi->modalias 和 drv->name */
    return strcmp(spi->modalias, drv->name) == 0;
}
```

老规矩：设备树匹配优先，`compatible` 对上就牵手，后面三步一概不看。所以我们的 `icm20608_of_match` 里那串 `"imxaes,icm20608"`，必须和设备树里的 `compatible` 完全一致。SPI 比 I2C 多了最后一步"名字盲比"——拿 `spi->modalias` 和 `drv->name` 直接比，这是给那些极老或极简、既没设备树也没 ACPI 的配置留的兜底通道，我们用不到。

框架到这就清楚了。下一节我们去拆 `spi-imx.c`，看看 I.MX6U 的主机驱动是怎么用 `spi_alloc_host` + `transfer_one` 把自己注册进系统的；等看清主机驱动怎么把"搬运比特"封装好，再回过头写 ICM-20608 的设备驱动，每个 API 调用落在哪里就一目了然了。

---

<ChapterNav variant="sub">
  <ChapterLink href="./" variant="sub">← 教程首页</ChapterLink>
  <ChapterLink href="03_spi_master_analysis.md" variant="sub">I.MX6U 主机驱动分析 →</ChapterLink>
</ChapterNav>
