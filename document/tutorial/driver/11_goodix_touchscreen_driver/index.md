---
title: 电容触摸驱动教程（goodix）
---

<PageHeader icon="👆" title="电容触摸驱动（goodix）" description="拆解 7.1 主线 goodix.c：从 input 子系统、多点触摸 MT 协议 Type B、threaded IRQ，到 GT9147 设备树与 evtest/tslib 多点验证——读懂又一颗成熟到「不用自己写」的驱动" />

## 版本说明

本教程基于以下内核版本，主线 `goodix.c` 在两边都默认编译进内核、开箱即用（alpha 板 defconfig 已开 `CONFIG_TOUCHSCREEN_GOODIX=y`）：

- **linux-imx** 6.12.49 <Badge type="tip" text="推荐" />
- **mainline** 7.1.0 <Badge type="info" text="进阶" />

源码就躺在仓库的 `third_party/linux-imx` 与 `third_party/linux_mainline` 下，文中每一处函数签名、行号都对着 `drivers/input/touchscreen/goodix.c` 核对过。

## 这一篇要解决什么问题

和 [上一章 RTC](../10_rtc_snvs_driver/) 一样，触摸这一章我们**也不写驱动**，走「分析型」路线。原因同样实在：汇顶（Goodix）的电容触摸驱动 `drivers/input/touchscreen/goodix.c`（1579 行）是主线收录、被无数平板和开发板验证过的成熟代码，支持 GT911 / GT9147 / GT9271 / GT928 等一大家子芯片。你板子上这颗 GT9147，主线驱动直接就能驱动它，自己重写一个只会更差。

所以这一章的打开方式是：**把 `goodix.c` 拆给你看**——搞懂「input 子系统怎么收事件」「多点触摸 MT 协议 Type B 是怎么回事」「为什么触摸中断要用 threaded IRQ」，再把 GT9147 在 alpha 板上用 `evtest`、`tslib` 真正多点跑通。读懂它，你就拿下了 input 子系统这块最重要的拼图——后面任何输入设备（按键、摇杆、陀螺仪），套路都一样。

::: tip 板子上到底是 GT911 还是 GT9147？
正点原子的资料里常笼统说「GT911」，但我们这块 alpha 板核心板实际焊的是 **GT9147**（挂在 I2C2，地址 `0x5d`）。好消息是：主线 `goodix.c` 一份驱动兼容 GT911/GT9147 全系列，设备树里 `compatible` 写哪个都命中同一个驱动，所以教程标题用通用的 goodix，正文以板子真实的 GT9147 为例。
:::

## 学习路径

我们按「先理框架、再拆源码、最后上板验证」的顺序推进，和 RTC 章对称。

### 🎯 推荐学习路径

#### **阶段一：硬件与框架**

1. **[01_introduction](01_introduction.md)** - 架构概览：电容屏原理、GT9147、分析型路线
2. **[02_input_framework](02_input_framework.md)** - Input 子系统 + MT 协议（Type A/B）

#### **阶段二：源码拆解**

3. **[03_goodix_driver_analysis](03_goodix_driver_analysis.md)** - `goodix.c` 逐段拆解：probe、I2C、上报
4. **[04_driver_layer](04_driver_layer.md)** - 关键机制深挖：Type B 时序、threaded IRQ、轮询回退

#### **阶段三：设备树与验证**

5. **[05_device_tree](05_device_tree.md)** - 设备树：`gt9147@5d` 节点与引脚
6. **[06_build_and_test](06_build_and_test.md)** - 启用主线 goodix + evtest/tslib 多点验证

## 章节目录

<ChapterNav>
  <ChapterLink num="02" href="02_input_framework.md">Input 子系统与 MT 协议</ChapterLink>
  <ChapterLink num="03" href="03_goodix_driver_analysis.md">goodix.c 逐段拆解</ChapterLink>
  <ChapterLink num="04" href="04_driver_layer.md">关键机制深挖</ChapterLink>
  <ChapterLink num="05" href="05_device_tree.md">设备树配置</ChapterLink>
  <ChapterLink num="06" href="06_build_and_test.md">启用主线 goodix 与验证</ChapterLink>
</ChapterNav>

::: tip 学习目标
搞懂 Linux input 子系统「设备 → 事件 → handler」的链路；理解多点触摸 MT 协议 Type A 与 Type B 的区别、`input_mt_*` 系列 API 的时序；看懂 `goodix.c` 如何用 I2C 读触摸坐标、用 threaded IRQ 在内核线程里上报 Type B 事件、用轮询做无中断回退；最终在 alpha 板上用 `evtest`、`tslib` 验证 GT9147 的多点触控。
:::

::: info 前置知识
- I2C 驱动框架（[08_i2c_ap3216c_driver](../08_i2c_ap3216c_driver/)，goodix 是 I2C 设备）
- 中断与并发（[06_debounced_key_driver](../06_debounced_key_driver/)、[07_input_subsystem_key](../07_input_subsystem_key/) 的 input 子系统按键）
- platform / 设备树模型（[03_platform_led_driver](../03_platform_led_driver/)）
:::

::: details 延伸阅读
- [Linux 多点触摸协议文档](https://www.kernel.org/doc/html/latest/input/multi-touch-protocol.html)
- [Linux input 子系统文档](https://www.kernel.org/doc/html/latest/input/input.html)
- 仓库源码：`third_party/linux_mainline/drivers/input/touchscreen/goodix.c`
- 设备树绑定：`Documentation/devicetree/bindings/input/touchscreen/goodix.yaml`
:::

## 常见问题

### Q: GT9147 和 GT911 是什么关系？驱动通用吗？

A: 它们都是汇顶（Goodix）的电容触摸 IC，协议同源。主线 `goodix.c` 一份驱动的 `of_match_table` 里列了 GT911、GT9147、GT9271、GT928……十几个 `compatible`，命中同一个 `probe`。我们这块板子是 GT9147，设备树写 `compatible = "goodix,gt9147"`，照样用这颗主线驱动。

### Q: 为什么触摸中断要用 threaded IRQ，不像 RTC 那样普通 `request_irq`？

A: 因为触摸中断极频繁（手指一划每秒上百次），而且 handler 里要做 **I2C 读取**——这是个几百微秒的慢操作。在硬中断上下文里干这事会拖死系统。threaded IRQ 把慢活儿丢到一个专属内核线程里跑，硬中断只负责「唤醒」。RTC 的 alarm 一年也响不了几次、handler 极短，所以用普通 `request_irq` 就够。详见 [04 节](04_driver_layer.md)。

### Q:多点触摸的 Type A 和 Type B 是什么？

A: 是 Linux MT 协议的两种上报方式。Type A「记流水账」，靠 `input_mt_sync` 切分触摸点，老硬件用；Type B「记账本」，每个手指占一个 slot（抽屉）、靠 `ABS_MT_TRACKING_ID` 追踪，现代硬件（包括 GT9147）都用它，效率更高。[02 节](02_input_framework.md) 会用「抽屉」的比喻讲透。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../10_rtc_snvs_driver/" variant="sub">← RTC 驱动（SNVS）</ChapterLink>
  <ChapterLink href="../modules/" variant="sub">模块开发 →</ChapterLink>
</ChapterNav>
