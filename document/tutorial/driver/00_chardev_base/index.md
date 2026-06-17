---
title: 字符设备驱动教程
---

<PageHeader icon="💻" title="字符设备驱动" description="从零开始系统学习 Linux 字符设备驱动开发，覆盖老 API 到新 API 的完整演进" />

## 版本说明

本教程提供多个内核版本的实现：

- **老内核版本**（Linux 4.1.15）：仅供参考，标记为"历史版本"
- **新内核版本**（Linux 6.12.49 / 7.1.0）：推荐学习，包含最新特性

## 学习路径

本教程采用渐进式学习路径，从基础概念到实际开发，系统性地掌握字符设备驱动开发技能。

### 🎯 推荐学习路径（完整版）

适合初学者，按顺序学习建立完整的知识体系：

#### **阶段一：基础理论**（1-5）

1. **[01_introduction.md](01_introduction)** - 字符设备驱动简介
2. **[02_kernel_space_basics.md](02_kernel_space_basics)** - 内核空间基础与硬件访问
3. **[03_kernel_module_mechanism.md](03_kernel_module_mechanism)** - 内核模块机制
4. **[04_kernel_print_guide.md](04_kernel_print_guide)** - 内核打印详解
5. **[05_kernel_debug_techniques.md](05_kernel_debug_techniques)** - 内核调试技术

#### **阶段二：API 演进与实战**（6-11）

6. **[06_legacy_chardev.md](06_legacy_chardev)** - 老API：虚拟字符设备 💻
7. **[06p_ide_setup.md](06p_ide_setup)** - IDE 配置指南 🛠️
8. **[07_hardware_overview.md](07_hardware_overview)** - LED 硬件基础 🔥
9. **[08_memory_mapped_io.md](08_memory_mapped_io)** - 内存映射 I/O 深度解析 ⭐⭐⭐
10. **[09_hardware_abstraction_layer.md](09_hardware_abstraction_layer)** - 硬件抽象层设计 🔧
11. **[10_chardev_implementation.md](10_chardev_implementation)** - 字符设备驱动实现 💻
12. **[11_build_test_deploy.md](11_build_test_deploy)** - 构建、测试与部署实战 🚀

#### **阶段三：新 API 专题**（12-18）

12. **[12_new_chardev_api_overview.md](12_new_chardev_api_overview)** - 新 API 概览与设计理念 ⭐⭐⭐
13. **[13_cdev_and_device_number.md](13_cdev_and_device_number)** - cdev 与设备号管理 ⭐⭐⭐
14. **[14_class_device_model.md](14_class_device_model)** - class 和 device 模型 ⭐⭐⭐
15. **[15_error_handling_patterns.md](15_error_handling_patterns)** - 驱动错误处理模式 ⭐⭐
16. **[16_device_structure_in_new_api.md](16_device_structure_in_new_api)** - 新 API 设备结构体 ⭐⭐
17. **[17_new_api_driver_analysis.md](17_new_api_driver_analysis)** - 新 API 驱动代码深度解析 ⭐⭐⭐
18. **[18_app_development_and_testing.md](18_app_development_and_testing)** - 应用开发与真实测试 ⭐

### 🚀 快速路径（有经验开发者）

如果你已经有内核开发经验：

1. 直接阅读 **[12_new_chardev_api_overview.md](12_new_chardev_api_overview)** 了解新API概览
2. 跟随 **[13_cdev_and_device_number.md](13_cdev_and_device_number)** 深入学习 cdev 和设备号
3. 跟随 **[14_class_device_model.md](14_class_device_model)** 了解 class 和 device 模型
4. 跟随 **[17_new_api_driver_analysis.md](17_new_api_driver_analysis)** 深入分析驱动代码
5. 跟随 **[18_app_development_and_testing.md](18_app_development_and_testing)** 了解应用开发和测试

## 章节目录

### 阶段一：基础理论

<ChapterNav>
  <ChapterLink num="01" href="01_introduction">字符设备驱动简介</ChapterLink>
  <ChapterLink num="02" href="02_kernel_space_basics">内核空间基础与硬件访问</ChapterLink>
  <ChapterLink num="03" href="03_kernel_module_mechanism">内核模块机制</ChapterLink>
  <ChapterLink num="04" href="04_kernel_print_guide">内核打印详解</ChapterLink>
  <ChapterLink num="05" href="05_kernel_debug_techniques">内核调试技术</ChapterLink>
</ChapterNav>

### 阶段二：API 演进与实战

<ChapterNav>
  <ChapterLink num="06" href="06_legacy_chardev">老 API：虚拟字符设备</ChapterLink>
  <ChapterLink num="06p" href="06p_ide_setup">IDE 配置指南</ChapterLink>
  <ChapterLink num="07" href="07_hardware_overview">LED 硬件基础</ChapterLink>
  <ChapterLink num="08" href="08_memory_mapped_io">内存映射 I/O 深度解析</ChapterLink>
  <ChapterLink num="09" href="09_hardware_abstraction_layer">硬件抽象层设计</ChapterLink>
  <ChapterLink num="10" href="10_chardev_implementation">字符设备驱动实现</ChapterLink>
  <ChapterLink num="11" href="11_build_test_deploy">构建、测试与部署</ChapterLink>
</ChapterNav>

### 阶段三：新 API 专题

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
| **mainline** | 7.1.0 <Badge type="info" text="进阶" /> | 上游主线，最新特性 |

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

## 常见问题

### Q: 新老内核的 API 兼容吗？
A: 核心字符设备 API 保持兼容，老代码在新内核上也能运行，但不推荐新驱动使用老 API。

### Q: 如何选择动态分配还是静态分配设备号？
A: 推荐使用动态分配（`alloc_chrdev_region`），避免设备号冲突。

### Q: 必须使用 `class_create` 和 `device_create` 吗？
A: 不是强制的，但强烈推荐，可以自动创建设备节点。

### Q: 为什么要学习 02-05 基础教程？
A: 这些教程建立了必要的内核基础概念，理解这些内容会让后续的驱动开发事半功倍。如果你已经有内核开发经验，可以跳过。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回驱动开发</ChapterLink>
  <ChapterLink href="../01_device_tree_base/" variant="sub">设备树基础教程 →</ChapterLink>
</ChapterNav>
