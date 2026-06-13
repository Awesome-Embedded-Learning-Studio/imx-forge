---
title: 设备树基础教程
---

<PageHeader icon="🌳" title="设备树基础" description="掌握设备树原理、语法和 OF API，从硬编码驱动迈向现代 Linux 驱动架构" />

## 前言：为什么我们必须学习设备树

说实话，在嵌入式Linux驱动开发这条路上，设备树是一道绕不过去的坎。我见过不少朋友在字符设备驱动教程里摸爬滚打了几个月，觉得自己已经掌握了驱动开发的核心技能，结果一上手真实项目就傻眼了——人家代码里全是 `of_find_node_by_path`、`of_property_read_u32` 这种函数，设备树文件一大堆，完全不知道从哪里下手。

这其实不是你的问题，而是学习路径的问题。传统的驱动教程往往把设备树当成一个"高级话题"，放在后面讲，或者干脆不讲。但在实际工程中，设备树是基础中的基础——你不理解设备树，就没法真正理解现代Linux驱动的架构设计。

所以我们在完成字符设备驱动基础教程之后，紧接着就推出了这套设备树基础教程。它的目标非常明确：让你从零开始，系统性地掌握设备树的原理、语法、API和实战应用。当你学完这套教程，再去看那些厂商的驱动代码，你会发现它们其实没那么神秘。

## 与00_chardev_base教程的关系

这套教程是00_chardev_base教程的延续和深化。在字符设备驱动教程里，我们主要关注的是"怎么写一个字符设备驱动"，而设备树教程关注的是"怎么用设备树来描述硬件信息"。

- **00_chardev_base**：教你如何实现一个字符设备驱动，包括file_operations、设备号管理、内核模块机制等基础内容。在这个阶段，我们为了让问题聚焦，采用了硬编码的方式来描述硬件信息——直接把寄存器地址写在代码里。

- **01_device_tree_base**：教你如何用设备树来替代硬编码。你会学习如何把硬件信息从驱动代码中剥离出来，放到设备树文件中，然后通过OF API在运行时读取这些信息。这是现代Linux驱动的标准做法。

建议的学习顺序是：先完成00_chardev_base教程，再进入这套设备树教程。如果你已经有了一定的驱动开发经验，也可以直接从这套教程开始，但需要确保你已经理解了字符设备驱动的基础概念。

## 学习路径规划

这套教程的设计思路是"从理论到实践，从基础到应用"。

### 完整学习路径（推荐新手）

如果你是第一次接触设备树，建议按顺序学习所有章节：

#### **阶段一：基础理论**（01-04章）

这个阶段的目标是建立对设备树的完整认知，理解它是什么、为什么需要它、语法怎么写。

1. **[01_device_tree_introduction.md](01_device_tree_introduction)** - 设备树简介（30分钟）⭐
2. **[02_dtc_deep_dive.md](02_dtc_deep_dive)** - DTC深入讲解（40分钟）
3. **[03_device_tree_syntax.md](03_device_tree_syntax)** - 设备树语法详解（50分钟）⭐
4. **[04_device_tree_history.md](04_device_tree_history)** - 设备树历史演进（25分钟）

#### **阶段二：API学习与验证**（05-06章）

5. **[05_of_api_basics.md](05_of_api_basics)** - OF API基础（60分钟）⭐
6. **[06_of_api_verification.md](06_of_api_verification)** - OF API验证（35分钟）

#### **阶段三：实战应用**（07-10章）

7. **[07_driver_comparison.md](07_driver_comparison)** - 驱动代码对比（45分钟）
8. **[08_device_tree_driver.md](08_device_tree_driver)** - 设备树驱动改造（70分钟）⭐
9. **[09_board_dts_modification.md](09_board_dts_modification)** - 板级DTS修改实操（50分钟）
10. **[10_complete_practice.md](10_complete_practice)** - 完整实战演练（80分钟）⭐

#### **阶段四：编译机制（进阶·可选）**

面向项目维护者和想深入理解设备树编译链路的同学，新手可跳过，需要时再回来看：

11. **[11_compile_mechanism.md](11_compile_mechanism)** - 内核设备树编译机制深度解析（高级）
12. **[12_compile_migration.md](12_compile_migration)** - 设备树编译机制迁移实践（中级）

### 快速路径（有经验开发者）

如果你已经有了一定的设备树基础，或者时间比较紧张，可以选择性地阅读重点章节：

- **必读章节**：03、05、08、10
- **选读章节**：01、02、06、07、09
- **可以跳过**：04（历史章节）

## 章节目录

### 阶段一：基础理论

<ChapterNav>
  <ChapterLink num="01" href="01_device_tree_introduction">设备树简介</ChapterLink>
  <ChapterLink num="02" href="02_dtc_deep_dive">DTC 深入讲解</ChapterLink>
  <ChapterLink num="03" href="03_device_tree_syntax">设备树语法详解</ChapterLink>
  <ChapterLink num="04" href="04_device_tree_history">设备树历史演进</ChapterLink>
</ChapterNav>

### 阶段二：API 学习与验证

<ChapterNav>
  <ChapterLink num="05" href="05_of_api_basics">OF API 基础</ChapterLink>
  <ChapterLink num="06" href="06_of_api_verification">OF API 验证</ChapterLink>
</ChapterNav>

### 阶段三：实战应用

<ChapterNav>
  <ChapterLink num="07" href="07_driver_comparison">驱动代码对比</ChapterLink>
  <ChapterLink num="08" href="08_device_tree_driver">设备树驱动改造</ChapterLink>
  <ChapterLink num="09" href="09_board_dts_modification">板级 DTS 修改实操</ChapterLink>
  <ChapterLink num="10" href="10_complete_practice">完整实战演练</ChapterLink>
</ChapterNav>

### 阶段四：编译机制（进阶 · 可选）

<ChapterNav>
  <ChapterLink num="11" href="11_compile_mechanism">内核设备树编译机制深度解析</ChapterLink>
  <ChapterLink num="12" href="12_compile_migration">设备树编译机制迁移实践</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解设备树的设计动机和语法规范，掌握 OF API 读取硬件信息，完成从硬编码驱动到设备树驱动的完整改造。
:::

::: info 前置知识
建议先完成 [字符设备驱动教程](../00_chardev_base/) · C 语言基础 · Linux 内核模块概念
:::

::: details 延伸阅读
- [设备树规范](https://www.devicetree.org/)
- [内核设备树文档](https://www.kernel.org/doc/html/latest/devicetree/)
- [Linux 设备驱动（LDD3）](https://lwn.net/Kernel/LDD3/)
:::

## 实验环境

### 硬件要求

- **推荐**：i.MX 6ULL系列开发板（如Alpha开发板）
- **兼容**：其他ARM Cortex-A系列开发板

### 软件环境

- **操作系统**：Linux（推荐Ubuntu 20.04或更高版本）
- **内核版本**：
  - Linux 6.12.49 (linux-imx)
  - Linux 7.0.0-rc4 (mainline)
- **交叉编译工具链**：arm-linux-gnueabhif-gcc

## 常见问题

### Q: 设备树文件必须从零开始写吗？
A: 完全不需要。在实际开发中，我们通常是修改芯片厂商提供的参考DTS文件。从零编写整份设备树文件的情况非常少见，除非你在设计一块全新的板子。所以本教程的重点是"读懂和修改"，而不是"从零编写"。

### Q: 设备树和DTS、DTB是什么关系？
A: DTS是设备树源文件（文本格式），DTB是编译后的二进制文件。内核启动时读取的是DTB文件，而我们编辑的是DTS文件。DTC编译器负责把DTS转换成DTB。

### Q: 为什么有些属性名前面有井号，比如#address-cells？
A: 井号开头的属性是"元属性"，它们描述的是如何解析其他属性，而不是设备本身的属性。#address-cells告诉解析器如何解析reg属性的地址部分，#size-cells告诉解析器如何解析reg属性的大小部分。

### Q: compatible属性到底有什么用？
A: compatible属性是驱动和设备匹配的关键。内核通过比较设备树中的compatible属性和驱动代码中的compatible字符串，来决定为这个设备加载哪个驱动。所以它的命名必须准确，通常格式是"厂商,型号"，如"fsl,imx6ull"。

### Q: 改了设备树文件但是没生效怎么办？
A: 这是一个常见问题。首先确认DTB文件是否重新编译了，其次确认板子加载的是不是新的DTB文件，最后可以通过/proc/device-tree查看内核实际使用的设备树内容。09_board_dts_modification.md章节有详细的排查方法。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../00_chardev_base/" variant="sub">← 字符设备驱动教程</ChapterLink>
  <ChapterLink href="../../" variant="sub">返回驱动开发 →</ChapterLink>
</ChapterNav>
