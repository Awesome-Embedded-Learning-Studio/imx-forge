---
title: 设备树基础教程
---

<PageHeader icon="🌳" title="设备树基础" description="在本仓把设备树真正用起来：读懂自家 dts、改造驱动、独立走完从改树到点灯的闭环" />

## 前言：这一卷管什么

在字符设备教程里，咱们写驱动用的是硬编码——寄存器地址一个个从芯片手册抄进 C 代码。教程里工作得很好，可地址一换就得重新翻手册、改宏、重编内核，这套做法没法带进真实项目。

设备树就是解这个问题的：把硬件描述搬进一份文本文件，驱动运行时自己来取。这一卷咱们不追求把设备树讲全，只管一件事——**在这个仓库里把设备树真正用起来**。读懂本仓的 dts，把硬编码驱动改造成吃设备树的驱动，再独立走一次板级修改，最后从一份接近空白的树起步，自己走通上板点灯的完整闭环。

深度原理内容（DTB 二进制格式、内核怎么展开设备树、语法全解、bindings 规范）不在本卷展开，各章文末的“深读”块给您留了路线指引。

## 与 00_chardev_base 教程的关系

这一卷是字符设备教程的直接续篇：

- **00_chardev_base**：教您怎么写一个字符设备驱动——file_operations、设备号、内核模块机制。为了让问题聚焦，那个阶段硬件信息全部硬编码。
- **01_device_tree_base**：教您怎么用设备树替换硬编码。硬件信息进 dts，驱动用 OF API 运行时读取，这是现代 Linux 驱动的标准做法。

建议按顺序走：先有字符设备的基础，再来这一卷。您手上已经有驱动开发经验的话，也可以直接进本卷，卡住了回前卷补对应概念。

## 本卷五章

五章是一条单向依赖线：先认门，再读树，然后动驱动、动树，最后独立走全程。这条线咱们一章一章走。

1. **[01 设备树与本仓的学习地图](01_device_tree_introduction)**——先带您认门：为什么有设备树、本仓 dts→dtb→板子的产物链 ⭐
2. **[02 语法速览：读懂本仓的 dts](02_device_tree_syntax)**——节点、属性、phandle、引用覆盖，读到能独立读懂 `imx6ull-aes.dtsi`
3. **[03 从硬编码到设备树驱动](03_device_tree_driver)**——拿仓库里真实的 `led_hw.c` 六步改造，编译部署上板点灯 ⭐
4. **[04 板级 dts 修改与部署](04_board_dts_modification)**——加节点→编译→部署→验证全流程，三脚本全程陪同
5. **[05 毕业项目：完整闭环](05_complete_practice)**——从接近空白的 dts 起步，加节点、写驱动、上板亮灯，独立走通才算毕业 ⭐

时间紧、您手上已经有设备树经验的话，可以从第 3 章直接开干，语法卡住再回第 2 章。

<ChapterNav>
  <ChapterLink num="01" href="01_device_tree_introduction">设备树与本仓的学习地图</ChapterLink>
  <ChapterLink num="02" href="02_device_tree_syntax">语法速览：读懂本仓的 dts</ChapterLink>
  <ChapterLink num="03" href="03_device_tree_driver">从硬编码到设备树驱动</ChapterLink>
  <ChapterLink num="04" href="04_board_dts_modification">板级 dts 修改与部署</ChapterLink>
  <ChapterLink num="05" href="05_complete_practice">毕业项目：完整闭环</ChapterLink>
</ChapterNav>

::: tip 学习目标
您将在本仓真实文件上完成四件事：读懂 `imx6ull-aes.dtsi`、把硬编码 LED 驱动改造成从设备树取地址、独立完成一次板级 dts 修改并部署验证、从空白树起步走通上板点灯闭环。
:::

::: info 前置知识
建议先完成 [字符设备驱动教程](../00_chardev_base/) · C 语言基础 · Linux 内核模块概念。动手环节您需要先初始化 `third_party/linux_mainline` 与 `third_party/uboot-imx` 两个 submodule。
:::

::: details 延伸阅读
- [设备树规范](https://www.devicetree.org/)
- [内核设备树文档](https://www.kernel.org/doc/html/latest/devicetree/)
- 本卷各章文末的“深读”块：DTB 格式、内核消费链、语法全解等深度内容的路线指引
:::

## 实验环境

### 硬件要求

- i.MX 6ULL 开发板（本仓硬件参考正点原子 Alpha 开发板，软件身份为 aes，目录名 `alpha-board`）

### 软件环境

- **操作系统**：Linux（推荐 Ubuntu 20.04 或更高版本）
- **内核版本**：Linux 7.1.0（mainline）—— 项目唯一内核轨
- **交叉编译工具链**：arm-linux-gnueabihf-gcc
- **源码前提**：`third_party/linux_mainline`、`third_party/uboot-imx` 两个 submodule 初始化检出（dts 编译要取 include 片段）

## 常见问题

### Q: 设备树文件必须从零开始写吗？
A: 实际开发中您几乎不用，通常是改芯片厂商或项目里现成的 dts。本卷第 5 章的毕业项目让您从接近空白的树起步，那是练习；真实工作里“读懂和修改”才是日常，这也是本卷把语法线划在“读懂本仓 dts”的原因。

### Q: 设备树和 DTS、DTB 是什么关系？
A: DTS 是设备树源文件（文本格式），DTB 是编译后的二进制文件。内核启动时读取的是 DTB，而咱们编辑的是 DTS，dtc 负责把 DTS 转成 DTB。

### Q: 为什么有些属性名前面有井号，比如 #address-cells？
A: 井号开头的属性是“元属性”，您可以把它们理解成“描述怎么解析其他属性”的属性，而不是设备本身的属性。#address-cells 告诉解析器 reg 属性的地址部分占几个单元格，#size-cells 告诉它大小部分占几个。

### Q: compatible 属性到底有什么用？
A: 它是驱动和设备配对的关键。内核拿设备树节点里的 compatible 和驱动代码里注册的字符串比对，两边对得上，才决定给这个设备加载哪个驱动，您眼下混个脸熟就行。命名通常是“厂商,型号”，如 `fsl,imx6ull`。

### Q: 改了设备树文件但是没生效怎么办？
A: 您先确认 DTB 重新编译了，再确认板子加载的是新 DTB（dtb 走 TFTP 部署后要重启板子才生效），最后用 `/proc/device-tree` 看内核实际用的树。第 4 章有完整的排查流程。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../00_chardev_base/" variant="sub">← 字符设备驱动教程</ChapterLink>
  <ChapterLink href="../02_pinctrl_gpio/" variant="sub">引脚复用与 GPIO 教程 →</ChapterLink>
</ChapterNav>
