---
title: 驱动与实战
---

<PageHeader title="驱动与实战" description="本教程的核心重头戏:从字符设备到板级外设,最后收口到一个可交付的产品级项目" />

## 前置要求

驱动章节默认你会:独立编内核、改设备树、烧镜像、看串口日志。没做到的话,先回 [系统构建](../system-build/) 把主线走通一次。

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="../driver/">驱动开发</ChapterLink>
  <ChapterLink num="02" href="../project/">应用项目 light-meter</ChapterLink>
</ChapterNav>

### 驱动开发

十四组章节,大致三段:

- **基础段**:字符设备基础（20 篇）、设备树基础、模块开发、固件应用。
- **子系统段**:pinctrl 与 GPIO、platform 驱动、input 子系统,以及蜂鸣器、按键、去抖按键三个递进案例。
- **板级外设段**:I2C(AP3216C)、SPI(ICM20608)、RTC(SNVS)、触摸屏(GT911)、音频(WM8960)—— 每个都是「原理 → 设备树 → 驱动 → 实测」的完整闭环。

### 应用项目 light-meter

从空目录里的第一个 `CMakeLists.txt`,到 Qt 三态 UI、真板部署与调试,把前面所有知识收口成一次交付。

## 学完往哪走

→ [模拟与调试](../emulation/) 补齐「跑不通怎么查」;
→ [烧录与进阶](../flashing/) 把产物变成可量产的镜像。
