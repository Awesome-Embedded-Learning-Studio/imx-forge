---
title: 驱动开发
---

<PageHeader icon="⚙️" title="驱动开发" description="Linux 驱动开发是嵌入式开发的高级技能" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="00_chardev_base/">字符设备基础 —— 从 file_operations 到新字符设备 API</ChapterLink>
  <ChapterLink num="02" href="01_device_tree_base/">设备树驱动基础 —— 从节点解析到完整实践</ChapterLink>
  <ChapterLink num="03" href="02_pinctrl_gpio/01_introduction">Pin Control & GPIO —— 引脚复用与 GPIO 子系统</ChapterLink>
  <ChapterLink num="04" href="03_platform_led_driver/">Platform LED 驱动 —— 平台总线与设备树匹配</ChapterLink>
  <ChapterLink num="05" href="04_beep_driver/">蜂鸣器驱动 —— GPIO 输出设备实践</ChapterLink>
  <ChapterLink num="06" href="05_gpio_key_driver/">GPIO 按键驱动 —— 输入采样与轮询</ChapterLink>
  <ChapterLink num="07" href="06_debounced_key_driver/">按键消抖驱动 —— 中断、工作队列与同步</ChapterLink>
  <ChapterLink num="08" href="07_input_subsystem_key/">Input 子系统按键 —— 标准输入事件上报</ChapterLink>
  <ChapterLink num="09" href="08_i2c_ap3216c_driver/">AP3216C I2C 驱动 —— 现代 I2C API 完整实战</ChapterLink>
  <ChapterLink num="10" href="09_spi_icm20608_driver/">ICM-20608 SPI 驱动 —— 现代 SPI API 完整实战</ChapterLink>
  <ChapterLink num="11" href="modules/">模块开发 —— 内核模块编程</ChapterLink>
  <ChapterLink num="12" href="firmware_apply/">固件应用 —— 固件加载</ChapterLink>
</ChapterNav>

::: tip v1.0.0 状态
驱动教程已经覆盖字符设备、设备树、pinctrl/gpio、platform、beep、key/input、I2C、SPI、模块与固件等主线章节。后续章节会继续扩展，但基础学习链路已经可以按目录顺序推进。
:::

::: tip 学习目标
理解 Linux 驱动架构，能够编写字符设备驱动，掌握内核模块开发和设备-驱动匹配机制。
:::

::: info 前置知识
C 语言高级特性 · Linux 内核基础 · 硬件基础知识
:::

::: details 延伸阅读
- [Linux 设备驱动](https://lwn.net/Kernel/LDD3/)
- [内核驱动 API](https://www.kernel.org/doc/html/latest/driver-api/)
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../rootfs/" variant="sub">← 根文件系统</ChapterLink>
  <ChapterLink href="../practical/" variant="sub">实战演练 →</ChapterLink>
</ChapterNav>
