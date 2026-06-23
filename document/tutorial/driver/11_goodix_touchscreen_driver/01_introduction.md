---
title: 架构概览
---

# 电容触摸驱动（goodix）—— 架构概览

## 前言：goodix.c 为什么也不自己写

上一章 RTC 我们开了「分析型」的头：原厂 `rtc-snvs.c` 太成熟，重写没意义，不如拆开读懂。触摸这一章我们接着走这条路——而且理由更充分。

电容触摸屏驱动 `drivers/input/touchscreen/goodix.c`（1579 行），是 Red Hat 的 Benjamin Tissoires 等人维护、主线内核收录、被无数 x86 平板和 ARM 开发板验证过的代码。它把汇鼎一大家子触摸 IC（GT911 / GT9147 / GT9271 / GT928 …）的差异、I2C 协议、多点触摸上报、电源管理、甚至手写笔支持，全收拾进了一个文件。你板子上的 GT9147，主线驱动拿来就能用，自己从零写一个只会更差、还大概率踩它踩过的坑。

所以这一章的任务和 RTC 一样：**把 `goodix.c` 拆给你看**。但触摸比 RTC 复杂一档——它横跨两个子系统：I2C（数据怎么来）和 input（数据怎么变成标准事件上报）。其中 **input 子系统下的多点触摸协议（MT 协议）** 是这一章真正的硬骨头，也是你之前学按键 input（[07_input_subsystem_key](../07_input_subsystem_key/)）时还没碰到的部分。读懂它，input 子系统这块最重要的拼图就补齐了。

::: tip 学习目标
理清电容触摸屏的硬件工作方式（I2C + 中断 + 复位三件套）；搞懂 input 子系统与多点触摸 MT 协议（Type A/B）；看懂 `goodix.c` 用 threaded IRQ + Type B 上报触摸点的设计；在 alpha 板上用 `evtest`/`tslib` 验证 GT9147 多点触控。
:::

## alpha 板的触摸芯片：GT9147（不是 GT911）

先把一个容易混淆的事说清楚。正点原子的资料、甚至我们板子的某些 README，常笼统地说「GT911」。但翻到板级设备树 `driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi`，I2C2 上挂的那个触摸节点白纸黑字写着：

```dts
gt9147: gt9147@5d {
    compatible = "goodix,gt9147", "goodix,gt9xx";
    reg = <0x5d>;
    ...
};
```

**核心板上实际焊的是 GT9147**，I2C 从机地址 `0x5d`。这无所谓——GT9147 和 GT911 是同门师兄弟，协议同源，主线 `goodix.c` 一份驱动全兼容。我们后面就以 GT9147 为例，记住它的三个关键接线：

- **I2C2 总线**，地址 `0x5d`：坐标数据从这里读。
- **中断引脚**：`gpio1` 的第 9 脚（`GPIO1_IO09`），手指一碰就拉低触发中断。
- **复位引脚**：`gpio1` 的第 5 脚（`GPIO1_IO05`），上电时复位 IC。

## 电容触摸屏到底怎么工作

没接触过电容屏的话，这里给个最简模型（细节看正点原子裸机篇第 28 章）。GT9147 这类电容触摸 IC，本质干三件事：

1. **感知**：屏幕玻璃下面布了一张透明的电极网格。手指是导体，贴近屏幕时会改变电极之间的耦合电容。IC 给网格打激励信号，测出每个交叉点的电容变化，就能算出「哪里被按了、按了多大面积」。
2. **计算**：IC 内部的 MCU 把原始电容数据算成每个触摸点的 X/Y 坐标、触摸面积（粗细）、一个唯一 ID，打包成数据帧。
3. **上报**：当有新数据时，IC 把**中断引脚（INT）拉低**通知 CPU；CPU 通过 I2C 把这帧坐标读走。

所以从软件看，电容触摸驱动就是：**等中断 → I2C 读一帧坐标 → 翻译成标准 input 事件上报**。三步而已。难点不在某一步，而在「多手指同时按」时怎么把每个手指都报清楚、还不会串——这就是 MT 协议要解决的，[02 节](02_input_framework.md) 详讲。

::: info GT9147 的「双地址」小把戏
GT9147 有个 7 位从机地址选择机制：复位时把 INT 引脚拉高，IC 进入 `0x14` 地址模式；拉低则进入 `0x5d` 模式。我们板子用 `0x5d`。`goodix.c` 在复位序列里（`goodix_reset_no_int_sync`，goodix.c:775）会按当前地址操作 INT 脚来配合这个机制——这是个硬件约定的细节，了解即可。
:::

## 先认认环境

- **板子**：I.MX6U-ALPHA，GT9147 挂 I2C2（地址 `0x5d`），中断 `GPIO1_IO09`、复位 `GPIO1_IO05`
- **内核**：`linux-imx` 6.12.49（NXP BSP）/ `mainline` 7.1.0（进阶）
- **源码**：`third_party/linux_mainline/drivers/input/touchscreen/goodix.c`（+ 同目录 `goodix.h`）
- **用户空间工具**：`evtest`（看原始 input 事件）、`tslib`（校准 + 多点测试 `ts_test_mt`）

::: info 主线默认就开了
alpha 板的 defconfig（`imx6ull_mainline_defconfig.template`）里 `CONFIG_TOUCHSCREEN_GOODIX=y` 早就是开的——和 RTC 一样，主线 goodix 默认编进内核，开机自动 probe。所以这章也不用 `insmod`，重点是读懂它、把 GT9147 的设备树配对、再用 evtest/tslib 验证。
:::

## 分析型打开方式：和 RTC 一致

| 维度 | 08/09 章（从零写） | 本章（分析型） |
|------|-------------------|----------------|
| 驱动代码 | 我们写 `.c` → `.ko` | 复用主线 `goodix.c`，**不写驱动** |
| 学习重点 | 怎么写驱动 | 怎么读懂 input 子系统 + MT 协议 |
| 配套产物 | 驱动 `.ko` + app | GT9147 设备树 + evtest/tslib 验证流程 |
| 验证手段 | `insmod` + 自写 app | `evtest`/`tslib`（现成工具） |

配套代码这一章会更轻：一个 GT9147 的设备树节点（让主线 goodix 在 alpha 板跑起来），加一份 evtest/tslib 验证说明。**驱动本体一行都不用你敲。**

## 小结

这一节我们理清了：触摸这章和 RTC 一样走分析型（`goodix.c` 太成熟）、板子上是 GT9147（不是 GT911，但同驱动兼容）、电容屏的工作三板斧（感知电容 → 算坐标 → INT 中断上报）。接下来我们先补一块前面按键 input 章没讲透的理论——多点触摸 MT 协议，这是看懂 `goodix.c` 上报逻辑的前提。

---

<ChapterNav variant="sub">
  <ChapterLink href="index.md" variant="sub">← 返回目录</ChapterLink>
  <ChapterLink href="02_input_framework.md" variant="sub">Input 子系统与 MT 协议 →</ChapterLink>
</ChapterNav>
