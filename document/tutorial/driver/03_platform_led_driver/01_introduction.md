# Platform LED 驱动 - 架构概览

## 前言：为什么这是第一个实战驱动

在之前的字符设备基础教程里，我们已经学会了如何写一个最小化的字符设备驱动——注册设备号、实现 `file_operations`、创建设备节点。但说实话，那些都是"硬编码"的驱动，设备和驱动的绑定关系不清晰，代码结构也比较粗糙。

现在我们要进入真实的嵌入式驱动开发世界。这个教程会带你完成一个**生产级别**的 Platform LED 驱动，完整展示从框架设计到代码实现的全过程。

::: tip 学习目标
掌握 Platform 驱动框架的完整开发流程：从设备树匹配到 probe/remove 函数，从 HAL 层设计到用户接口实现。学会用 `devm_gpiod_get()` 等 GPIO Descriptor API 操作硬件，理解设备树和驱动的严格对齐关系。
:::

## 教程结构

本教程分为六个章节：

### 第一阶段：框架理解

1. **[02_platform_framework](02_platform_framework)** - Platform 驱动框架详解
   - Platform 总线的工作原理
   - platform_driver 结构体解析
   - probe/remove 函数的工作流程

2. **[03_hal_layer](03_hal_layer)** - HAL 层设计思想
   - 为什么需要硬件抽象层
   - HAL 接口设计
   - GPIO Descriptor API 使用

### 第二阶段：实现与集成

3. **[04_driver_layer](04_driver_layer)** - 驱动层实现
   - 设备结构体设计
   - file_operations 实现
   - 驱动层与 HAL 层的协作

4. **[05_device_tree](05_device_tree)** - 设备树配置
   - 设备树语法
   - compatible 属性匹配
   - GPIO 配置与极性

### 第三阶段：实战验证

5. **[06_build_and_test](06_build_and_test)** - 编译测试
   - 驱动编译
   - 设备树编译
   - 功能测试与调试

## 硬件抽象层（HAL）设计思想

LED 驱动的代码被分成了两个文件：`platform_led_13_driver_main.c` 是驱动层，`led_hw.c` 和 `led_hw.h` 是硬件抽象层。为什么要这样拆分？

假设你的系统里有多个 LED：一个是板载的电源指示灯，一个是用户可编程的状态灯，还有一个通过 GPIO 扩展芯片控制的灯。这三个 LED 的控制方式可能不同：第一个直接用 GPIO 控制，第二个也是 GPIO 但有特殊初始化要求，第三个需要通过 I2C 扩展芯片。如果在每个地方都写一遍 GPIO 操作代码，会有大量重复。

HAL 的思路是：**定义一套统一的接口，把硬件相关的细节封装起来**。

```c
int led_hw_init(struct device *dev, struct led_hw_ctx *ctx);
void led_hw_deinit(struct led_hw_ctx *ctx);
void led_set_status(struct led_hw_ctx *ctx, bool status);
bool led_get_status(struct led_hw_ctx *ctx);
```

驱动层只调用这些接口，不需要知道底层是 GPIO 还是 I2C 扩展芯片。如果以后要支持 PWM 调光，只需要修改 `led_hw.c` 的实现，驱动层的代码完全不用动。

::: tip HAL 设计的价值
HAL 层的核心价值在于"隔离变化"。硬件变了，改 HAL 层；接口变了，才需要改驱动层。大部分硬件改动都发生在 HAL 层，驱动代码可以保持稳定。
:::

## 代码结构

```
driver/16_tutorial_platform_led/
├── platform_led_13_driver_main.c  # 驱动层
│   ├── platform_driver 定义
│   ├── probe/remove 函数
│   └── file_operations 实现
│
└── led_hw.c / led_hw.h            # HAL 层
    ├── GPIO 获取/释放
    └── LED 状态控制
```

## 小结

本节介绍了教程的整体结构和 HAL 设计思想。接下来我们将深入 Platform 框架，理解设备和驱动是如何匹配的。

---

<ChapterNav variant="sub">
  <ChapterLink href="index.md" variant="sub">← 返回目录</ChapterLink>
  <ChapterLink href="02_platform_framework.md" variant="sub">Platform 驱动框架 →</ChapterLink>
</ChapterNav>
