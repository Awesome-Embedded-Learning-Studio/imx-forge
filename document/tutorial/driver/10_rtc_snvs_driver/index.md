---
title: RTC 驱动教程（SNVS）
---

<PageHeader icon="⏰" title="RTC 驱动（SNVS）" description="拆解 7.1 主线 rtc-snvs.c：从 RTC 子系统分层、regmap 寄存器抽象、47 位计数器双读乐观并发，到 alarm 闹钟与 hwclock 验证——读懂一颗成熟到「不用自己写」的驱动" />

## 版本说明

本教程基于以下内核版本，主线 `rtc-snvs.c` 在两边都默认编译进内核、开箱即用：

- **linux-imx** 6.12.49 <Badge type="tip" text="推荐" />
- **mainline** 7.1.0 <Badge type="info" text="进阶" />

源码就躺在仓库的 `third_party/linux-imx` 与 `third_party/linux_mainline` 下，文中每一处函数签名、行号都对着 `drivers/rtc/rtc-snvs.c` 核对过，可以随时翻。

## 这一篇要解决什么问题

和前面 AP3216C、ICM-20608「从零重写一颗驱动」的打法不一样，RTC 这一章我们**不写驱动**。原因很实在：i.MX6U 的内部 RTC 驱动 `drivers/rtc/rtc-snvs.c` 是 NXP 原厂维护、主线早已收录的成熟代码，稳定到没必要再造一个轮子——你硬要从零写一个，大概率写得比它差。所以这一篇换个打开方式：**把原厂驱动拆给你看**，搞懂「RTC 子系统是怎么分层的」「`rtc-snvs.c` 怎么用 regmap 操作 SNVS」「那个名声在外的 47 位计数器为什么要读两次」，最后把主线 RTC 在 alpha 板上用 `hwclock`、`date`、alarm 闹钟真正跑通。

这也是本专栏第一次走「分析型」路线：前面那些章教你**写**，这一章教你**读**。读懂一颗工业级驱动，比闷头再写一遍收获更大。

## 学习路径

我们按「先理框架、再拆源码、最后上板验证」的顺序推进。

### 🎯 推荐学习路径

#### **阶段一：框架与硬件**

1. **[01_introduction](01_introduction.md)** - 架构概览：SNVS 是什么、为什么 RTC「不叫 RTC」
2. **[02_rtc_framework](02_rtc_framework.md)** - RTC 子系统分层：通用层 `rtc-dev.c` 与底层 `rtc_class_ops`

#### **阶段二：源码拆解**

3. **[03_snvs_driver_analysis](03_snvs_driver_analysis.md)** - `rtc-snvs.c` 逐段拆解：probe、regmap、ops
4. **[04_driver_layer](04_driver_layer.md)** - 关键机制深挖：47 位计数器双读、alarm 一次性中断

#### **阶段三：设备树与验证**

5. **[05_device_tree](05_device_tree.md)** - 设备树：`snvs@20cc000` 与 `snvs-rtc-lp` 子节点
6. **[06_build_and_test](06_build_and_test.md)** - 启用主线 RTC + `hwclock`/alarm 验证

## 章节目录

<ChapterNav>
  <ChapterLink num="02" href="02_rtc_framework.md">RTC 子系统分层框架</ChapterLink>
  <ChapterLink num="03" href="03_snvs_driver_analysis.md">rtc-snvs.c 逐段拆解</ChapterLink>
  <ChapterLink num="04" href="04_driver_layer.md">关键机制深挖</ChapterLink>
  <ChapterLink num="05" href="05_device_tree.md">设备树配置</ChapterLink>
  <ChapterLink num="06" href="06_build_and_test.md">启用主线 RTC 与验证</ChapterLink>
</ChapterNav>

::: tip 学习目标
搞懂 Linux RTC 子系统「通用层 `rtc-dev.c` + 底层 `rtc_class_ops`」的分层契约；看懂 `rtc-snvs.c` 如何用 regmap 抽象 SNVS 寄存器、用「双读 + diff 判据」规避 47 位计数器的撕裂读、用一次性中断实现 alarm；最终在 alpha 板上用 `hwclock`、`date` 和一个 alarm demo 把主线 RTC 跑通，并理解断电后纽扣电池如何续命。
:::

::: info 前置知识
- 字符设备 + 设备树 + platform 驱动模型（[03_platform_led_driver](../03_platform_led_driver/)）
- I2C 驱动框架（[08_i2c_ap3216c_driver](../08_i2c_ap3216c_driver/)，regmap 概念会复用）
- 中断基础（[11 interrupt](../06_debounced_key_driver/) 那一类章节）
:::

::: details 延伸阅读
- [Linux RTC 子系统文档](https://www.kernel.org/doc/html/latest/driver-api/rtc_interface.html)
- 仓库源码：`third_party/linux_mainline/drivers/rtc/rtc-snvs.c`
- 《I.MX6UL 参考手册》Chapter 46 Secure Non-Volatile Storage (SNVS)
:::

## 常见问题

### Q: 为什么不自己从零写一个 RTC 驱动？

A: 因为没意义。`rtc-snvs.c` 是原厂维护、主线稳定收录的代码，硬件特性（47 位计数器、syscon 复用、alarm 一次性）都被它吃透了。你从零写一个，最好的结果也就是「和它一样」，多半还更糟。教学价值在于读懂它，而不是重复造一个更差的轮子——这也是触摸（GT911/goodix）那一章我们走同样「分析型」路线的原因。

### Q: 板子上没有外挂 PCF8563 一类的 RTC 芯片？

A: 没有，也不需要。i.MX6U 把 RTC 做进了芯片内部的 **SNVS** 模块里（叫 SRTC），靠核心板上的纽扣电池 + 32.768kHz 晶振维持走时，断电不丢时间。外挂 PCF8563 是另一类「总线型 RTC」方案，本专栏这块板子用的是片内 SNVS。

### Q: `/dev/rtc0` 和 `hwclock` 是什么关系？

A: `rtc-snvs.c` 把 SRTC 注册成一个 `rtc_device`，内核的通用层 `rtc-dev.c` 自动给它派生 `/dev/rtc0` 这个字符设备节点。`hwclock` 则是用户空间工具，通过 `ioctl`（`RTC_RD_TIME`/`RTC_SET_TIME`）读写 `/dev/rtc0`，对应到驱动的 `read_time`/`set_time` 回调。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../09_spi_icm20608_driver/" variant="sub">← SPI ICM-20608 驱动</ChapterLink>
  <ChapterLink href="../11_goodix_touchscreen_driver/" variant="sub">电容触摸驱动 →</ChapterLink>
</ChapterNav>
