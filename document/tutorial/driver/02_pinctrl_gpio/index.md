---
title: Pinctrl 与 GPIO 子系统教程
---

<PageHeader icon="📌" title="Pinctrl 与 GPIO 子系统" description="从 IOMUXC 引脚复用到 pinctrl/gpio 子系统，掌握 Linux 引脚管理的标准方式" />

## 版本说明

本教程基于以下内核版本：
- **linux-imx** 6.12.49 <Badge type="tip" text="推荐" />
- **mainline** 7.1.0 <Badge type="info" text="进阶" />

## 学习路径

本教程从 i.MX6ULL 的 IOMUXC 硬件原理讲起，逐步拆解 pinctrl（引脚复用/电气配置）和 gpio（电平读写）两大子系统，最后落到驱动实现与 imx/mainline 双轨对比。

### 🎯 推荐学习路径

#### **阶段一：硬件基础**

1. **[01_introduction](01_introduction.md)** - 为什么需要 pinctrl/gpio 子系统
2. **[02_hardware_foundation](02_hardware_foundation.md)** - IOMUXC 与引脚复用原理

#### **阶段二：pinctrl 子系统**

3. **[03_pinctrl_subsystem_arch](03_pinctrl_subsystem_arch.md)** - pinctrl 子系统架构
4. **[04_pinctrl_device_tree](04_pinctrl_device_tree.md)** - pinctrl 设备树绑定

#### **阶段三：gpio 子系统**

5. **[05_gpio_subsystem_arch](05_gpio_subsystem_arch.md)** - gpio 子系统架构
6. **[06_gpio_device_tree](06_gpio_device_tree.md)** - gpio 设备树绑定

#### **阶段四：驱动实战**

7. **[07_driver_implementation](07_driver_implementation.md)** - 驱动实现
8. **[08_build_and_test](08_build_and_test.md)** - 编译测试与验证
9. **[09_kernel_comparison](09_kernel_comparison.md)** - imx 与 mainline 对比

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_introduction.md">引言：为什么需要子系统</ChapterLink>
  <ChapterLink num="02" href="02_hardware_foundation.md">硬件基础：IOMUXC</ChapterLink>
  <ChapterLink num="03" href="03_pinctrl_subsystem_arch.md">pinctrl 子系统架构</ChapterLink>
  <ChapterLink num="04" href="04_pinctrl_device_tree.md">pinctrl 设备树</ChapterLink>
  <ChapterLink num="05" href="05_gpio_subsystem_arch.md">gpio 子系统架构</ChapterLink>
  <ChapterLink num="06" href="06_gpio_device_tree.md">gpio 设备树</ChapterLink>
  <ChapterLink num="07" href="07_driver_implementation.md">驱动实现</ChapterLink>
  <ChapterLink num="08" href="08_build_and_test.md">编译测试与验证</ChapterLink>
  <ChapterLink num="09" href="09_kernel_comparison.md">imx vs mainline 对比</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解 pinctrl 与 gpio 两大子系统的分工：pinctrl 负责**引脚复用与电气配置**（IOMUXC），gpio 负责**电平读写与中断**。学会用设备树描述引脚（`pinctrl` 节点 + `gpio` 属性），用 `gpiod_get()` / `gpiod_direction_output()` 等 Descriptor API 操作硬件，告别直接读写寄存器。
:::

::: info 前置知识
- 字符设备驱动基础
- 设备树基本语法（见 [01_device_tree_base](../01_device_tree_base/)）
- i.MX6ULL 内存映射 IO 概念
:::

::: details 延伸阅读
- [Pinctrl 子系统文档](https://www.kernel.org/doc/html/latest/driver-api/pinctl.html)
- [GPIO Descriptor API](https://www.kernel.org/doc/html/latest/driver-api/gpio/)
- i.MX6ULL IOMUXC 寄存器见 [参考资源索引](../../../reference/index.md)
:::

## 常见问题

### Q: pinctrl 和 gpio 子系统什么关系？

A: 分工不同。**pinctrl** 管引脚"干什么用"——复用成 GPIO / I2C / UART 还是其他功能，以及上下拉、驱动强度等电气配置；**gpio** 管引脚"作为 GPIO 时"的电平读写和中断。一个引脚先经 pinctrl 配成 GPIO 功能，再由 gpio 子系统操作。

### Q: mainline 为什么删了 of_gpio.h 旧 API？

A: 主线推动 **GPIO Descriptor API**（`gpiod_*`），旧的 `of_get_gpio()` 返回全局 GPIO 号的 number-based API 被废弃。imx 内核还保留旧头文件，所以同一份驱动在 imx 能编、mainline 编不过。本项目已统一迁移到 gpiod API，详见 [09_kernel_comparison](09_kernel_comparison.md)。

### Q: MX6UL_PAD_GPIO1_IO03__GPIO1_IO03 这个宏是什么？

A: 它展开成 5 个整数：`mux_reg conf_reg input_reg mux_val input_val`，告诉 pinctrl 把某个 PAD 的复用寄存器和配置寄存器写成特定值。由内核 `arch/arm/boot/dts/nxp/imx/imx6ul-pinfunc.h` 定义。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../01_device_tree_base/" variant="sub">← 设备树基础</ChapterLink>
  <ChapterLink href="../03_platform_led_driver/" variant="sub">Platform LED 驱动 →</ChapterLink>
</ChapterNav>
