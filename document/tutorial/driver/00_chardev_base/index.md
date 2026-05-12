---
title: 字符设备驱动教程
---

<PageHeader icon="💻" title="字符设备驱动" description="从零开始系统学习 Linux 字符设备驱动开发，覆盖老 API 到新 API 的完整演进" />

## 阶段一：基础理论

<ChapterNav>
  <ChapterLink num="01" href="01_introduction">字符设备驱动简介</ChapterLink>
  <ChapterLink num="02" href="02_kernel_space_basics">内核空间基础与硬件访问</ChapterLink>
  <ChapterLink num="03" href="03_kernel_module_mechanism">内核模块机制</ChapterLink>
  <ChapterLink num="04" href="04_kernel_print_guide">内核打印详解</ChapterLink>
  <ChapterLink num="05" href="05_kernel_debug_techniques">内核调试技术</ChapterLink>
</ChapterNav>

## 阶段二：API 演进与实战

<ChapterNav>
  <ChapterLink num="06" href="06_legacy_chardev">老 API：虚拟字符设备</ChapterLink>
  <ChapterLink num="06p" href="06p_ide_setup">IDE 配置指南</ChapterLink>
  <ChapterLink num="07" href="07_hardware_overview">LED 硬件基础</ChapterLink>
  <ChapterLink num="08" href="08_memory_mapped_io">内存映射 I/O 深度解析</ChapterLink>
  <ChapterLink num="09" href="09_hardware_abstraction_layer">硬件抽象层设计</ChapterLink>
  <ChapterLink num="10" href="10_chardev_implementation">字符设备驱动实现</ChapterLink>
  <ChapterLink num="11" href="11_build_test_deploy">构建、测试与部署</ChapterLink>
</ChapterNav>

## 阶段三：新 API 专题

<ChapterNav>
  <ChapterLink num="12" href="12_new_chardev_api_overview">新 API 概览与设计理念</ChapterLink>
  <ChapterLink num="13" href="13_cdev_and_device_number">cdev 与设备号管理</ChapterLink>
  <ChapterLink num="14" href="14_class_device_model">class 和 device 模型</ChapterLink>
  <ChapterLink num="15" href="15_error_handling_patterns">驱动错误处理模式</ChapterLink>
  <ChapterLink num="16" href="16_device_structure_in_new_api">新 API 设备结构体</ChapterLink>
  <ChapterLink num="17" href="17_new_api_driver_analysis">新 API 驱动代码深度解析</ChapterLink>
  <ChapterLink num="18" href="18_app_development_and_testing">应用开发与真实测试</ChapterLink>
</ChapterNav>

## 双轨内核支持

| 轨道 | 版本 | 说明 |
|------|------|------|
| **linux-imx** | 6.12.49 <Badge type="tip" text="推荐" /> | NXP BSP，针对 i.MX 优化 |
| **mainline** | 7.0.0-rc4 <Badge type="info" text="进阶" /> | 上游主线，最新特性 |

::: tip 学习目标
掌握字符设备驱动的完整开发流程：从 `file_operations` 到新 API 的"三步走"机制，独立编写生产级驱动代码。
:::

::: info 前置知识
C 语言高级特性 · Linux 内核基础 · 硬件基础知识
:::

::: details 延伸阅读
- [Linux 设备驱动（LDD3）](https://lwn.net/Kernel/LDD3/)
- [内核驱动 API](https://www.kernel.org/doc/html/latest/driver-api/)
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回驱动开发</ChapterLink>
  <ChapterLink href="../01_device_tree_base/" variant="sub">设备树基础教程 →</ChapterLink>
</ChapterNav>
