---
title: Platform LED 驱动教程
---

<PageHeader icon="💡" title="Platform LED 驱动" description="从 Platform 框架到 HAL 设计的完整实践，掌握嵌入式 Linux 驱动开发的核心技能" />

## 版本说明

本教程基于以下内核版本：
- **linux-imx** 6.12.49 <Badge type="tip" text="推荐" />
- **mainline** 7.1.0 <Badge type="info" text="进阶" />

## 学习路径

本教程从 Platform 框架基础讲起，逐步深入到 HAL 层设计，让你完整理解"生产级"驱动的开发方式。

### 🎯 推荐学习路径

#### **阶段一：框架理解**

1. **[02_platform_framework](02_platform_framework.md)** - Platform 驱动框架详解
2. **[03_hal_layer](03_hal_layer.md)** - HAL 层实现分析

#### **阶段二：驱动实现**

3. **[04_driver_layer](04_driver_layer.md)** - 驱动层实现分析
4. **[05_device_tree](05_device_tree.md)** - 设备树严格对齐

#### **阶段三：实战验证**

5. **[06_build_and_test](06_build_and_test.md)** - 编译测试与验证

## 章节目录

<ChapterNav>
  <ChapterLink num="02" href="02_platform_framework.md">Platform 驱动框架</ChapterLink>
  <ChapterLink num="03" href="03_hal_layer.md">HAL 层实现分析</ChapterLink>
  <ChapterLink num="04" href="04_driver_layer.md">驱动层实现分析</ChapterLink>
  <ChapterLink num="05" href="05_device_tree.md">设备树严格对齐</ChapterLink>
  <ChapterLink num="06" href="06_build_and_test.md">编译测试与验证</ChapterLink>
</ChapterNav>

::: tip 学习目标
掌握 Platform 驱动框架的完整开发流程：从设备树匹配到 probe/remove 函数，从 HAL 层设计到用户接口实现。学会用 `devm_gpiod_get()` 等 GPIO Descriptor API 操作硬件，理解设备树和驱动的严格对齐关系。
:::

::: info 前置知识
- 字符设备驱动基础（`file_operations`、`cdev`）
- 设备树基本语法
- C 语言结构体和指针
:::

::: details 延伸阅读
- [Platform 驱动框架文档](https://www.kernel.org/doc/html/latest/driver-api/driver-model/platform.html)
- [GPIO Descriptor API](https://www.kernel.org/doc/html/latest/driver-api/gpio/)
- [设备树绑定规范](https://www.kernel.org/doc/html/latest/devicetree/bindings/)
:::

## 常见问题

### Q: 为什么要用 HAL 层？

A: HAL 层把硬件操作封装起来，驱动层不需要知道底层是 GPIO 还是其他接口。这样如果要支持 PWM 调光，只需要修改 HAL 层，驱动层代码完全不用动。

### Q: devm_gpiod_get 和 gpiod_get 有什么区别？

A: `devm_` 版本会自动管理资源，设备卸载时自动释放，不需要手动调用 `gpiod_put()`。推荐优先使用 `devm_` 版本，代码更简洁且不容易出错。

### Q: 设备树属性名为什么是 led-gpio 而不是 led-gpios？

A: 从规范上讲应该用 `<name>-gpios`（复数），但内核有一套兼容机制，单数形式也能识别。不过建议保持一致性，统一用复数形式。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../00_chardev_base/" variant="sub">← 字符设备驱动</ChapterLink>
  <ChapterLink href="../04_beep_driver/" variant="sub">蜂鸣器驱动 →</ChapterLink>
</ChapterNav>
