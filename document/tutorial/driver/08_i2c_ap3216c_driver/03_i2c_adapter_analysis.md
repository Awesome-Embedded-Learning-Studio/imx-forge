---
title: I.MX6U 适配器分析
---

# 拆开 i2c-imx.c：I.MX6U 的 I2C 适配器长什么样

上一节我们把 I2C 框架的两层关系理顺了，也强调了"总线驱动这层 NXP 已经替我们写好了"。但"写好了"不等于"不用看"——恰恰相反，我们至少得拆开看一眼这层到底是怎么把 adapter 拼起来、又是怎么注册进系统的，否则你写的设备驱动里那些 `i2c_transfer` 调用，就像是往一个黑箱里扔石子，扔进去有回声但你不知道为什么。

所以我们这一节就去翻 `drivers/i2c/busses/i2c-imx.c`。这个文件不大，但五脏俱全，正好是一个标准 I2C 适配器驱动的教科书式样本。我们把注意力放在四个地方：算法结构体怎么填、真正的传输函数是谁、`probe` 怎么把 adapter 一点点拼起来、以及它最后用什么身份注册进内核。

## 算法结构体：master_xfer 到底落在哪儿

上一节我们说过，`i2c_algorithm` 里那个 `xfer`/`master_xfer` 的 `union` 是核心中的核心——你调的所有读写 API，最终都会滑到这个函数指针上。那 I.MX6U 的适配器到底填了哪一个？答案在 `i2c-imx.c:1605`：

```c
/* drivers/i2c/busses/i2c-imx.c */
static u32 i2c_imx_func(struct i2c_adapter *adapter)
{
    return I2C_FUNC_I2C | I2C_FUNC_SMBUS_EMUL
        | I2C_FUNC_SMBUS_READ_BLOCK_DATA;
}

static const struct i2c_algorithm i2c_imx_algo = {
    .master_xfer         = i2c_imx_xfer,
    .master_xfer_atomic  = i2c_imx_xfer_atomic,
    .functionality       = i2c_imx_func,
    .reg_slave           = i2c_imx_reg_slave,
    .unreg_slave         = i2c_imx_unreg_slave,
};
```

看到没有，它填的是 **`.master_xfer`**——也就是 `union` 里的那个**老名字**，而不是新的 `.xfer`。这正是上一节提醒你留意的"新旧交替过渡期"的活样本：NXP 的工程师还没把名字迁移到 `.xfer`，但因为两者在同一个 `union` 里、偏移完全相同，内核照样认。你以后看别的厂商驱动，可能填的是 `.xfer`，别大惊小怪，它俩是一回事。

这个结构体里还藏着几个值得说道的成员。`.functionality` 指向的 `i2c_imx_func` 返回的是一张"能力位图"：`I2C_FUNC_I2C` 表示支持标准 I2C 传输，`I2C_FUNC_SMBUS_EMUL` 表示能用软件方式模拟 SMBus 协议（这点对我们后面用 `i2c_smbus_*` 系列函数很关键），`I2C_FUNC_SMBUS_READ_BLOCK_DATA` 是块读。`.master_xfer_atomic` 是给原子上下文用的版本——比如系统崩溃后的内核转储、调试器里，这时候不能睡眠，得有一套不依赖中断/调度的传输路径。`.reg_slave` / `.unreg_slave` 是把这片 I2C 控制器配置成**从机**模式的接口，我们做主机设备驱动用不到，知道有这回事就行。

## master_xfer 的真身：i2c_imx_xfer

`.master_xfer` 指向的 `i2c_imx_xfer` 定义在 `i2c-imx.c:1471`。它的函数体不长，核心就一句——把活儿转给一个叫 `i2c_imx_xfer_common` 的公共函数，最后一个参数 `false` 表示"不是原子上下文"：

```c
/* drivers/i2c/busses/i2c-imx.c */
static int i2c_imx_xfer(struct i2c_adapter *adapter,
                        struct i2c_msg *msgs, int num)
{
    /* ...... 加锁、时钟使能等准备工作 ...... */
    result = i2c_imx_xfer_common(adapter, msgs, num, false);
    /* ...... 收尾 ...... */
}
```

那个 `.master_xfer_atomic` 指向的 `i2c_imx_xfer_atomic`（`:1517`）也几乎一样，只是把最后一个参数传成 `true`。真正搬比特、写 `I2CR`/`I2SR` 这些硬件寄存器的脏活，全压在 `i2c_imx_xfer_common`（`:1311`）这一个函数里——主机模式和原子模式共用同一套寄存器操作逻辑，只是外面包裹的"能否睡眠"语义不同。这种"一个 common 内核 + 两个薄壳"的写法在内核里很常见，读懂了你就明白：你写的设备驱动调 `i2c_transfer`，最终落点就是这里那一堆 `writel`/`readl`。

## probe：把 adapter 一点点拼起来

`i2c_algorithm` 是"怎么传"的方法表，那 `i2c_adapter` 就是"我是谁"的身份。`i2c-imx.c` 的 `probe` 函数（`i2c_imx_probe`）干的就是把一个 `i2c_adapter` 实例一口一口喂饱，核心几句长这样：

```c
/* drivers/i2c/busses/i2c-imx.c，i2c_imx_probe() 内 */
/* Setup i2c_imx driver structure */
strscpy(i2c_imx->adapter.name, pdev->name, sizeof(i2c_imx->adapter.name));
i2c_imx->adapter.owner      = THIS_MODULE;
i2c_imx->adapter.algo       = &i2c_imx_algo;       /* 挂上前面那张方法表 */
i2c_imx->adapter.dev.parent = &pdev->dev;
/* ...... nr、class、retries、timeout 等等 ...... */

/* Set up adapter data */
i2c_set_adapdata(&i2c_imx->adapter, i2c_imx);
```

`strscpy` 给 adapter 起个名字（用 `pdev->name`），`.owner` 设成 `THIS_MODULE`，最关键的一句是 `.algo = &i2c_imx_algo`——把上一节那张方法表挂上去，adapter 从此就有了"动起来"的能力。`.dev.parent = &pdev->dev` 把 adapter 在设备模型里的爹指好，保证电源管理、suspend/resume 能顺着父子关系正确传递。最后 `i2c_set_adapdata` 把驱动自己的私有数据 `i2c_imx`（里面藏着寄存器基址、时钟、中断号这些）塞进 adapter，以后用 `i2c_get_adapdata` 就能取回来。这套"挂算法、认爹、藏私货"的套路，是所有适配器驱动的通用模板。

## 注册：i2c_add_numbered_adapter

adapter 喂饱了，最后一步是告诉内核"我来了"。`i2c-imx.c:1723` 这一行：

```c
ret = i2c_add_numbered_adapter(&i2c_imx->adapter);
```

我们框架节里提过，`i2c_add_numbered_adapter` 用的是**静态总线号**——也就是由驱动自己指定挂在第几号 I2C 总线上（I.MX6U 有 I2C1~I2C4，对应总线号 0~3）。注册成功后，这条虚拟的 I2C 总线就算通了车，挂在上面的设备节点（设备树里那些子节点）会被逐一实例化成 `i2c_client`，再去找匹配的 `i2c_driver`。

## 为什么它是 platform_driver：一个容易绕晕的点

读到这里你可能有个疑问：明明讲的是 I2C 驱动，怎么 `i2c-imx.c` 最后注册的不是一个 `i2c_driver`，而是个 `platform_driver`？看 `i2c-imx.c:1822`：

```c
/* drivers/i2c/busses/i2c-imx.c */
static struct platform_driver i2c_imx_driver = {
    .probe      = i2c_imx_probe,
    .remove_new = i2c_imx_remove,
    .driver = {
        .name           = DRIVER_NAME,
        .pm             = pm_ptr(&i2c_imx_pm_ops),
        .of_match_table = i2c_imx_dt_ids,
        .acpi_match_table = i2c_imx_acpi_ids,
    },
    .id_table = imx_i2c_devtype,
};

static int __init i2c_adap_imx_init(void)
{
    return platform_driver_register(&i2c_imx_driver);
}
```

这恰恰是 Linux 驱动分层最精妙的地方。I2C 控制器本身是 SoC 上的一个硬件外设，它有自己的寄存器物理地址、自己的中断号、自己的时钟——这些"平台资源"的申请和管理，是 platform 总线的拿手好戏。所以 I2C 适配器驱动**先以 `platform_driver` 的身份**上车：platform 总线帮它匹配设备树节点、做 `ioremap` 映射寄存器、`request_irq` 申请中断、`clk_prepare_enable` 开时钟。等到这些资源都就位、adapter 也拼好了，它才在 `probe` 里调用 `i2c_add_numbered_adapter`，把自己**再注册成一个 I2C 适配器**，向 I2C 核心层报到。

换句话说，I.MX6U 的 I2C 控制器同时顶着两层身份：对 platform 总线，它是个 platform 设备；对 I2C 子系统，它是个 adapter。这两层身份一点都不冲突，反而各司其职——platform 管硬件资源，I2C 管通信协议。这也是为什么我们的 AP3216C 设备驱动**完全不用碰**控制器寄存器：底层那摊事儿，`i2c-imx.c` 已经在 platform 这层料理干净了。

顺带留意一下这里的 `.remove_new`。platform 总线和 I2C 一样，在 6.x 完成了回调签名迁移：老的 `.remove`（返回 `int`）被 `.remove_new`（返回 `void`）取代。你看到的 `i2c-imx.c` 用 `.remove_new`，正是迁移完成后的现代写法。这和我们框架节强调的"I2C `remove` 是 `void`"是同一个故事，只是发生在另一条总线上。

## 小结

这一节我们拆开了 `i2c-imx.c`，看清了三件事：它用老名字 `.master_xfer` 填 `i2c_algorithm`，传输的真正脏活在 `i2c_imx_xfer_common`；它的 `probe` 把 `i2c_adapter` 拼好、挂上算法表，再用 `i2c_add_numbered_adapter` 注册；它以 `platform_driver` 身份上车、再以 adapter 身份向 I2C 核心层报到。把这些想明白，我们再回过头写自己的 AP3216C 设备驱动，就知道每一个 API 调用最终落在哪里了。

---

<ChapterNav variant="sub">
  <ChapterLink href="02_i2c_framework.md" variant="sub">← I2C 驱动框架</ChapterLink>
  <ChapterLink href="04_driver_layer.md" variant="sub">AP3216C 驱动层实现 →</ChapterLink>
</ChapterNav>
