---
title: 架构概览
---

# RTC 驱动（SNVS）—— 架构概览

## 前言：成熟到「不用自己写」的驱动，我们读什么

前面 AP3216C、ICM-20608 两章，我们干的是「推倒重写」的活儿——老教程停在 4.1.15 内核的写法，搬到 6.12 / 7.1 上要么编不过、要么满屏警告，所以我们用现代 API 从头重写了一遍。RTC 这一章画风要变了：**这一颗驱动我们不写，只读。**

原因很直白。i.MX6U 的内部 RTC 驱动 `drivers/rtc/rtc-snvs.c`（全仓库就 446 行），是 NXP 原厂工程师写的、主线内核老早就收录的成熟代码。它把 SNVS 这块硬件的每一个犄角旮旯——47 位计数器的撕裂读、syscon 寄存器复用、alarm 闹钟的一次性中断——都收拾得干干净净。你硬要从零写一个，最好的结局是「和它差不多」，大概率还踩一遍它早就踩过的坑。所以与其重复造一个更差的轮子，不如把它的设计吃透。

这一章的任务，就是带你**像拆黑盒一样**把 `rtc-snvs.c` 拆开：从最顶层的 `ioctl` 一路下钻，穿过 RTC 子系统的通用层，落到 regmap 的寄存器读写和那个 47 位计数器的双读循环上。读完了，你不仅会用 RTC，更会理解「一颗工业级 Linux 驱动是怎么分层、怎么抽象硬件差异的」——这套东西，后面触摸、音频、网卡，处处都用得上。

::: tip 学习目标
理清 RTC 子系统「通用层 + 底层」的分层；看懂 `rtc-snvs.c` 用 regmap 操作 SNVS、用双读规避计数器撕裂、用一次性中断做 alarm 的设计；在 alpha 板上用 `hwclock`/`date`/alarm 把主线 RTC 跑通。
:::

## I.MX6U 的 RTC 不叫 RTC：藏在 SNVS 里

如果你是从 STM32 转过来的，第一次在 I.MX6U 上找 RTC 会怀疑人生——翻手册搜「RTC」，搜不到。这是因为在这颗芯片上，**RTC 不叫 RTC，它被塞进了一个叫 SNVS 的模块里**。

SNVS 全称 Secure Non-Volatile Storage（安全非易失性存储）。一个管时间的东西，被扔进了「存储」模块——这名字起得反直觉，但这就是 NXP 的架构。想看完整的寄存器描述，得翻《I.MX6UL 参考手册》第 46 章；注意别拿《I.MX6ULL 参考手册》硬刚，那本里 SNVS 的寄存器描述缺斤少两。

SNVS 在物理上分成两个电源域：

- **SNVS_HP（High-Power）**：高功耗域，只靠系统主电源 `VDD_HIGH_IN` 供电。一断电就挂。
- **SNVS_LP（Low-Power）**：低功耗域，这才是 RTC 的家。它有**两路供电**：主电源 + 板子上的纽扣电池（`VDD_SNVS_IN`）。

这就是为什么核心板上要焊一颗纽扣电池：主电源断了，SNVS_HP 瞬间去世，但 SNVS_LP 靠纽扣电池续命，时钟接着走。我们要用的「实时时钟」，学名叫 **SRTC**（Secure Real Time Counter），就位于 SNVS_LP 里。

本质上，SRTC 就是一个**一直在跑的定时器**：

- **时钟源**：32.768kHz 晶振（$2^{15}$ Hz，分频出秒信号，核心板上已焊好）。
- **计数方式**：不停地把秒数累加。机器眼里的「时间」不是「2026 年 6 月 23 日」，而是一个冷冰冰的数字——**距离 1970-01-01 00:00:00 经过的秒数**（Unix 时间戳）。

::: warning ⚠️ 踩坑预警：手册在 47 位计数器上「撒了谎」
SRTC 的秒计数器是个 **47 位** 的硬件计数器，被拆在两个 32 位寄存器里：`SNVS_LPSRTCMR`（高位）和 `SNVS_LPSRTCLR`（低位）。NXP 手册信誓旦旦地写着「高位存高 15 位、低位存低 32 位」，你照着拼会读出乱码——**手册这里描述有误**。真相要去看内核源码：实际有效的是 32 位秒计数，分布在这 47 位的 bit\[15..46\] 上（`CNTR_TO_SECS_SH = 15`）。我们会在 [04_driver_layer](04_driver_layer.md) 用 `rtc-snvs.c` 的 `set_time` 给你验证这个位布局。别跟手册较劲，信源码。
:::

## 先认认环境

这一章跑在两套内核上，主线 `rtc-snvs.c` 两边都默认编译进内核：

- **板子**：I.MX6U-ALPHA，片内 SNVS SRTC，核心板带纽扣电池 + 32.768kHz 晶振
- **内核**：`linux-imx` 6.12.49（NXP BSP，主开发环境）/ `mainline` 7.1.0（进阶验证）
- **源码**：仓库 `third_party/linux-imx/drivers/rtc/rtc-snvs.c`、`third_party/linux_mainline/drivers/rtc/rtc-snvs.c`
- **用户空间工具**：`hwclock`、`date`（busybox 或 util-linux 版均可）

::: info 主线默认就启用了
`rtc-snvs.c` 不像前面 AP3216C 那样要你 `insmod`——它默认就编进内核、开机自动 probe。你只要设备树里 `snvs-rtc-lp` 节点在（i.MX6UL 的基础 dtsi 里自带，alpha 板不用额外加），开机就会有 `/dev/rtc0`。这也是「分析型」章节省心的地方：不用编译 `.ko`，重点是把它读懂、把验证做透。
:::

## 分析型 vs 从零写：这一篇的打开方式

为了让你心里有数，我们把这一篇和前面两章的差别摆清楚：

| 维度 | 08/09 章（从零写） | 本章（分析型） |
|------|-------------------|----------------|
| 驱动代码 | 我们自己写 `.c`，编译成 `.ko` | 复用主线 `rtc-snvs.c`，**不写驱动** |
| 学习重点 | 怎么用现代 API 写驱动 | 怎么读懂一颗工业级驱动 |
| 配套产物 | 驱动 `.ko` + 测试 app | alarm demo app + 设备树说明 |
| 验证手段 | `insmod` + 自写 app 读数据 | `hwclock`/`date` + alarm demo |

配套代码这一章会轻很多：一个用户空间的 alarm 闹钟 demo（`rtc_alarm_demo.c`，演示 `ioctl` 设/等闹钟），外加一个说明性的设备树片段。**驱动本体一行都不用你敲**——这恰恰说明它成熟。

## 小结

这一节我们理清了三件事：为什么 RTC 这一章改走「分析型」（原厂 `rtc-snvs.c` 太成熟，重写没意义）、i.MX6U 的 RTC 藏在 SNVS 的 LP 域里靠纽扣电池续命、以及 47 位计数器那个手册坑。接下来我们先钻进 RTC 子系统的分层框架，看看内核是怎么用一套通用接口把「时间」这件事抽象出来的。

---

<ChapterNav variant="sub">
  <ChapterLink href="index.md" variant="sub">← 返回目录</ChapterLink>
  <ChapterLink href="02_rtc_framework.md" variant="sub">RTC 子系统分层框架 →</ChapterLink>
</ChapterNav>
