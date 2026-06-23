---
title: rtc-snvs.c 逐段拆解
---

# rtc-snvs.c 逐段拆解 —— probe、regmap 与 ops

框架清楚了，这一节我们正式把 `drivers/rtc/rtc-snvs.c`（7.1，446 行）摊开，从匹配表到 `probe` 再到回调，一段一段拆。读完后你会发现：原厂驱动里没有任何黑魔法，它用的就是上一节那套分层契约，只是把「怎么操作 SNVS 硬件」这格填得特别讲究。

::: tip 学习目标
看懂 `rtc-snvs.c` 的 `platform_driver` 骨架与设备树匹配；跟着 `snvs_rtc_probe` 走完一遍探测流程，理解 **regmap 的 syscon + mmio 双路获取**、时钟托管、硬件初始化、中断注册、`devm_rtc_register_device` 收尾；认清 `snvs_rtc_ops` 五个回调各自的职责。
:::

## 驱动骨架：platform_driver + of_match

整颗驱动是一个标准的 `platform_driver`（设备树匹配，走 platform 总线）：

```c
/* drivers/rtc/rtc-snvs.c:428 —— 设备树匹配表 */
static const struct of_device_id snvs_dt_ids[] = {
    { .compatible = "fsl,sec-v4.0-mon-rtc-lp", },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, snvs_dt_ids);

/* :434 —— 平台驱动骨架 */
static struct platform_driver snvs_rtc_driver = {
    .driver = {
        .name           = "snvs_rtc",
        .pm             = &snvs_rtc_pm_ops,
        .of_match_table = snvs_dt_ids,
    },
    .probe = snvs_rtc_probe,
};
module_platform_driver(snvs_rtc_driver);
```

内核启动时解析设备树，看到 `compatible = "fsl,sec-v4.0-mon-rtc-lp"` 的节点（就是 `imx6ul.dtsi` 里那个 `snvs-rtc-lp`），就用这张表匹配上，触发 `snvs_rtc_probe`。`module_platform_driver` 一行宏搞定 `init/exit` 注册——这套写法和 [03_platform_led](../03_platform_led_driver/) 完全一致。

## probe 全景：六步把硬件变成 rtc_device

`snvs_rtc_probe`（`:317-403`）是整颗驱动的心脏。它要把冰冷的 SNVS 寄存器，变成内核里一个能用的 `rtc_device`。我们分六步看。

### 第 1 步：申请设备与私有数据

```c
/* rtc-snvs.c:323 */
data = devm_kzalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
if (!data->rtc)
    return -ENOMEM;

data->rtc = devm_rtc_allocate_device(&pdev->dev);   /* 领一个空 rtc_device */
if (IS_ERR(data->rtc))
    return PTR_ERR(data->rtc);
```

`snvs_rtc_data` 是这颗驱动的私有数据，装着 regmap、中断号、时钟、offset。注意这里先 `devm_rtc_allocate_device` 领了一个**还没注册**的 `rtc_device`——上一节讲的两步法第一步。它要到 probe 最后才 `register`。

### 第 2 步：拿到寄存器的「手」——regmap（重头戏）

这是整个 probe 最值得讲的一段，也是现代 Linux 驱动的精髓：

```c
/* rtc-snvs.c:331 —— 先试 syscon，不行再 mmio 回退 */
data->regmap = syscon_regmap_lookup_by_phandle(pdev->dev.of_node, "regmap");

if (IS_ERR(data->regmap)) {
    dev_warn(&pdev->dev, "snvs rtc: you use old dts file, please update it\n");

    mmio = devm_platform_ioremap_resource(pdev, 0);          /* 老路：直接映射物理地址 */
    if (IS_ERR(mmio))
        return PTR_ERR(mmio);

    data->regmap = devm_regmap_init_mmio(&pdev->dev, mmio, &snvs_rtc_config);
} else {
    data->offset = SNVS_LPREGISTER_OFFSET;                   /* 0x34 */
    of_property_read_u32(pdev->dev.of_node, "offset", &data->offset);
}
```

SNVS 不是一颗「独立」的硬件——它是 SoC 里的一个**系统控制模块**（system controller），里面除了 RTC，还塞着 poweroff、pwrkey、安全寄存器等一堆东西。多个驱动要共享同一片 SNVS 寄存器，于是内核用 **syscon** 机制来管理这类「多驱动复用的寄存器块」。

所以 probe 先走 `syscon_regmap_lookup_by_phandle`，通过设备树里的 `regmap = <&snvs>` 属性，向系统「借」一张已经映射好的 regmap；如果借不到（比如用了不带 `regmap` 属性的老设备树），就回退到自己 `ioremap` 物理地址、再用 `devm_regmap_init_mmio` 造一张。

无论哪条路，最终 `data->regmap` 都指向一个能 `regmap_read`/`regmap_write` 的抽象句柄。后面所有寄存器操作，统一长这样：

```c
regmap_read(data->regmap, data->offset + SNVS_LPSRTCLR, &val);
regmap_write(data->regmap, data->offset + SNVS_LPCR, ...);
```

`data->offset` 是 RTC 在 SNVS 这块大寄存器里的偏移（`0x34`），由设备树的 `offset` 属性提供。寄存器本身（`SNVS_LPCR`/`SNVS_LPSR`/`SNVS_LPSRTCMR` 等）的偏移定义在文件开头（`:20-25`），都是相对于 LP 域的。

::: tip 什么是 regmap？一句话版
regmap 是内核提供的「统一寄存器读写抽象」。不管你的硬件挂在内存总线上（MMIO，用 `writel`/`readl`）、还是挂在 I2C/SPI 上，regmap 都给你统一的 `regmap_read`/`regmap_write` 接口。它还顺手提供缓存、位操作（`regmap_update_bits`）等能力。在 [08_i2c](../08_i2c_ap3216c_driver/) 里我们手写 I2C 寄存器读写，而 regmap 是那条路的「升华版」——snvs 用它是 MMIO 模式，换到一颗 I2C RTC（比如 rtc-pcf8560）就是 I2C 模式，上层代码几乎不动。
:::

### 第 3 步：时钟与资源托管

```c
/* rtc-snvs.c:355 */
data->clk = devm_clk_get(&pdev->dev, "snvs-rtc");
if (IS_ERR(data->clk)) {
    data->clk = NULL;                       /* 没时钟也行（很多板子 SNVS 时钟常开） */
} else {
    ret = clk_prepare_enable(data->clk);
    ...
}

ret = devm_add_action_or_reset(&pdev->dev, snvs_rtc_action, data->clk);
```

SNVS 可能有一个独立的访问时钟（`snvs-rtc`），有就 `prepare_enable`；没有（很多 i.MX6U 板子这路时钟常开）就置 `NULL`，后面 `clk_enable(NULL)` 是空操作，不会炸。`devm_add_action_or_reset` 注册了一个卸载时自动 `clk_disable_unprepare` 的回调（`snvs_rtc_action`，`:312`）——又是 `devm_` 托管思想，省得手写释放。

### 第 4 步：硬件初始化——清场与上电

```c
/* rtc-snvs.c:373 */
/* Initialize glitch detect */
regmap_write(data->regmap, data->offset + SNVS_LPPGDR, SNVS_LPPGDR_INIT);

/* Clear interrupt status */
regmap_write(data->regmap, data->offset + SNVS_LPSR, 0xffffffff);

/* Enable RTC */
ret = snvs_rtc_enable(data, true);
```

三件事：

1. **Glitch Detect**（`LPPGDR`）：配抗信号毛刺滤波器，写一个魔法值 `0x41736166`（看着像 ASCII，确实是 NXP 约定的密钥）。
2. **清中断状态**（`LPSR` 写 `0xffffffff`）：状态寄存器「写 1 清除」，一上来把残留的旧中断标志全清掉，免得刚加载就误触发。
3. **使能 RTC**（`snvs_rtc_enable`，`:134`）：把 `LPCR` 的 `SRTC_ENV` 位置 1，时钟才开始走字。这个函数里还有个自旋等待确认的循环。

### 第 5 步：唤醒能力与中断注册

```c
/* rtc-snvs.c:386 */
device_init_wakeup(&pdev->dev, true);                 /* 声明能唤醒系统 */
ret = dev_pm_set_wake_irq(&pdev->dev, data->irq);     /* 把中断设为唤醒源 */

ret = devm_request_irq(&pdev->dev, data->irq, snvs_rtc_irq_handler,
                       IRQF_SHARED, "rtc alarm", &pdev->dev);
```

RTC 闹钟的一大用途是**把系统从 suspend 唤醒**（比如定时开机），所以这里 `device_init_wakeup` + `dev_pm_set_wake_irq` 把它注册成唤醒源。

中断用的是普通的 `devm_request_irq`（不是 threaded irq），带 `IRQF_SHARED`——因为这个 GIC 中断号可能和别的 SNVS 子设备（pwrkey 等）共享。handler 是 `snvs_rtc_irq_handler`，我们在 [下一节](04_driver_layer.md) 讲 alarm 时细看。

### 第 6 步：注册 RTC 设备

```c
/* rtc-snvs.c:399 —— 两步法的第二步 */
data->rtc->ops = &snvs_rtc_ops;        /* 挂菜单 */
data->rtc->range_max = U32_MAX;        /* 32 位秒计数，最大到 2106 年 */

return devm_rtc_register_device(data->rtc);   /* 真正注册，派生 /dev/rtc0 */
```

挂上 `snvs_rtc_ops`，声明这颗 RTC 能表示的时间范围（`U32_MAX` 秒 ≈ 2106 年），然后 `devm_rtc_register_device` 一锤定音——`/dev/rtc0` 就此诞生。probe 跑完，应用层就能 `hwclock` 了。

## `rtc_class_ops` 五回调

probe 里挂的那张菜单 `snvs_rtc_ops`（`:270`），是这颗驱动的灵魂：

```c
/* drivers/rtc/rtc-snvs.c:270 */
static const struct rtc_class_ops snvs_rtc_ops = {
    .read_time        = snvs_rtc_read_time,       /* :160 */
    .set_time         = snvs_rtc_set_time,        /* :178 */
    .read_alarm       = snvs_rtc_read_alarm,      /* :205 */
    .set_alarm        = snvs_rtc_set_alarm,       /* :246 */
    .alarm_irq_enable = snvs_rtc_alarm_irq_enable,/* :226 */
};
```

五个回调，和上一节 `rtc_class_ops` 的核心字段一一对应。子系统的 `interface.c` 会在加锁后调它们。先看最常用的 `read_time`（`:160`）：

```c
/* rtc-snvs.c:160 */
static int snvs_rtc_read_time(struct device *dev, struct rtc_time *tm)
{
    struct snvs_rtc_data *data = dev_get_drvdata(dev);
    unsigned long time;
    int ret;

    ret = clk_enable(data->clk);
    if (ret)
        return ret;

    time = rtc_read_lp_counter(data);   /* ← 读 47 位计数器，转成 32 位秒 */
    rtc_time64_to_tm(time, tm);         /* 秒数 → 年月日时分秒 */

    clk_disable(data->clk);
    return 0;
}
```

干净利落：`rtc_read_lp_counter` 从硬件读出秒数（这个函数有故事，下一节详讲），`rtc_time64_to_tm` 把冷冰冰的 Unix 时间戳翻译成 `struct rtc_time`（闰年、月份天数这些恶心的换算内核都帮你做了），完事。

`set_time`（`:178`）是逆操作：`rtc_tm_to_time64` 把 `tm` 转秒数，**先关 RTC**（写计数器必须先停表）、按位写进 `LPSRTCLR`/`LPSRTCMR`、再开 RTC。剩下三个 alarm 相关回调（`read_alarm`/`set_alarm`/`alarm_irq_enable`）操作的是闹钟寄存器 `LPTAR` 和控制位，结构类似。

## 小结

这一节我们把 `rtc-snvs.c` 从头到尾拆了一遍：它是标准的 platform 驱动，`probe` 六步走（申请 → regmap → 时钟 → 硬件初始化 → 唤醒中断 → 注册），核心是 **regmap 的 syscon+mmio 双路获取**——把 SNVS 这个「多驱动共享的系统寄存器块」抽象成统一的读写句柄。最后挂上 `snvs_rtc_ops` 五个回调，一颗工业级 RTC 驱动就立起来了。

但这里留了两个最精彩的坑没填：47 位计数器到底怎么读才不会撕裂？alarm 一次性中断是怎么实现的？下一节我们专门治这两个硬骨头。

---

<ChapterNav variant="sub">
  <ChapterLink href="02_rtc_framework.md" variant="sub">← RTC 子系统分层框架</ChapterLink>
  <ChapterLink href="04_driver_layer.md" variant="sub">关键机制深挖 →</ChapterLink>
</ChapterNav>
