---
title: 蜂鸣器驱动教程
---

<PageHeader icon="🔊" title="蜂鸣器驱动" description="GPIO 输出设备的实战应用，深入理解 GPIO 极性配置与驱动/设备树严格对齐" />

## 版本说明

本教程基于以下内核版本：
- **linux-imx** 6.12.49 <Badge type="tip" text="推荐" />

## 学习路径

蜂鸣器驱动和 LED 驱动类似，但重点讲解 GPIO 极性配置问题，这是一个容易踩坑的地方。假设你已经掌握了 Platform 驱动框架（在 03_platform_led_driver 中学习），本教程专注于 GPIO 极性配置。

### 🎯 推荐学习路径

1. **[02_gpio_polarity](02_gpio_polarity.md)** - GPIO 极性配置详解（核心）
2. **[03_driver_impl](03_driver_impl.md)** - 驱动实现详解
3. **[04_build_and_test](04_build_and_test.md)** - 编译测试与调试

## 章节目录

<ChapterNav>
  <ChapterLink num="02" href="02_gpio_polarity.md">GPIO 极性配置详解</ChapterLink>
  <ChapterLink num="03" href="03_driver_impl.md">驱动实现详解</ChapterLink>
  <ChapterLink num="04" href="04_build_and_test.md">编译测试与调试</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解 GPIO 极性配置的重要性，掌握 GPIO_ACTIVE_HIGH/LOW 的处理，确保驱动代码和设备树严格对齐。
:::

::: warning GPIO 极性问题
本教程会分析一个真实存在的问题：驱动代码和设备树极性声明不匹配导致的按键反应和预期相反。这是新手容易犯的错误。
:::

::: info 前置知识
- Platform 驱动框架（03_platform_led_driver）
- 字符设备基础
- 设备树基本语法
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../03_platform_led_driver/" variant="sub">← Platform LED 驱动</ChapterLink>
  <ChapterLink href="../05_gpio_key_driver/" variant="sub">GPIO 按键（轮询）→</ChapterLink>
</ChapterNav>
