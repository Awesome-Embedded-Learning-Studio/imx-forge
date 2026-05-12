---
title: 设备树基础教程
---

<PageHeader icon="🌳" title="设备树基础" description="掌握设备树原理、语法和 OF API，从硬编码驱动迈向现代 Linux 驱动架构" />

## 阶段一：基础理论

<ChapterNav>
  <ChapterLink num="01" href="01_device_tree_introduction">设备树简介</ChapterLink>
  <ChapterLink num="02" href="02_dtc_deep_dive">DTC 深入讲解</ChapterLink>
  <ChapterLink num="03" href="03_device_tree_syntax">设备树语法详解</ChapterLink>
  <ChapterLink num="04" href="04_device_tree_history">设备树历史演进</ChapterLink>
</ChapterNav>

## 阶段二：API 学习与验证

<ChapterNav>
  <ChapterLink num="05" href="05_of_api_basics">OF API 基础</ChapterLink>
  <ChapterLink num="06" href="06_of_api_verification">OF API 验证</ChapterLink>
</ChapterNav>

## 阶段三：实战应用

<ChapterNav>
  <ChapterLink num="07" href="07_driver_comparison">驱动代码对比</ChapterLink>
  <ChapterLink num="08" href="08_device_tree_driver">设备树驱动改造</ChapterLink>
  <ChapterLink num="09" href="09_board_dts_modification">板级 DTS 修改实操</ChapterLink>
  <ChapterLink num="10" href="10_complete_practice">完整实战演练</ChapterLink>
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

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../00_chardev_base/" variant="sub">← 字符设备驱动教程</ChapterLink>
  <ChapterLink href="../../" variant="sub">返回驱动开发 →</ChapterLink>
</ChapterNav>
