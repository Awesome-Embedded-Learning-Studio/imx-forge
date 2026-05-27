# 蜂鸣器驱动 - GPIO 极性配置实战

## 前言：从 LED 到蜂鸣器

在 LED 驱动教程中，我们学习了 Platform 框架和 HAL 层设计。对于蜂鸣器驱动，Platform 框架部分你已经掌握了——它和 LED 驱动几乎一样。

蜂鸣器驱动的真正价值在于：**它暴露了一个常见的问题——GPIO 极性配置错误**。这是新手最容易踩的坑，也是本教程的核心内容。

::: tip 教学目标
通过蜂鸣器驱动，深入理解 GPIO 极性配置，掌握 `devm_gpiod_get()` 的 flags 参数和 `gpiod_set_value()` 的极性反转逻辑。
:::

## 和 LED 驱动的异同

### 相同点

- 都是 Platform 框架驱动
- 都用 `devm_gpiod_get()` 获取 GPIO
- 都用 `gpiod_set_value()` 控制状态
- 都通过字符设备暴露给用户空间

### 不同点

| 特性 | LED 驱动 | 蜂鸣器驱动 |
|------|---------|-----------|
| HAL 层 | 有（led_hw.c/h） | 无（直接操作 GPIO） |
| 初始状态 | 无所谓 | 必须静音 |
| 极性问题 | 相对简单 | 暴露经典坑 |

::: info 为什么蜂鸣器需要关注初始状态
如果驱动加载后蜂鸣器一直响，用户体验很差，还可能让人以为板子坏了。蜂鸣器驱动必须确保**默认静音**。
:::

## 教程结构

本教程简化为四个章节，专注于 GPIO 极性配置：

1. **[02_gpio_polarity](02_gpio_polarity.md)** - GPIO 极性配置详解（核心）
2. **[03_driver_impl](03_driver_impl.md)** - 驱动实现分析
3. **[04_build_and_test](04_build_and_test.md)** - 编译测试与调试

::: tip 前置知识
- Platform 驱动框架（在 03_platform_led_driver 中已讲解）
- 字符设备基础（`file_operations`、`cdev`）
- 设备树基本语法
:::

## 小结

本节介绍了蜂鸣器驱动的基本情况。接下来我们直接进入 GPIO 极性配置的详细分析，这是本教程的核心内容。

---

<ChapterNav variant="sub">
  <ChapterLink href="../03_platform_led_driver/" variant="sub">← Platform LED 驱动</ChapterLink>
  <ChapterLink href="02_gpio_polarity.md" variant="sub">GPIO 极性配置 →</ChapterLink>
</ChapterNav>
