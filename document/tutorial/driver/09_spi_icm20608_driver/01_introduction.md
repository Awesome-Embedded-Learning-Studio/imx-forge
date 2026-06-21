---
title: 架构概览
---

# ICM-20608 SPI 驱动 —— 架构概览

## 前言：SPI 的自由，与它的责任

很多人觉得 SPI 比 I2C 简单——不就四根线嘛（SCK / MOSI / MISO / CS），时钟你说了算，没有 I2C 那套地址仲裁。在裸机里确实如此，你写 `bsp_spi.c` 直接戳 ECSPI 寄存器、配引脚、拉片选，四根线尽在掌握。可一旦从裸机转进 Linux，这种"尽在掌握"的感觉就变成了最大的坑：你明明知道寄存器怎么配，但在 Linux 里就是找不到地方下手配它。

难就难在思维模式的转换。裸机里你是硬件的直接操控者，Linux 里你得学会放权——承认这条 SPI 总线不属于你，你只是借用它。而且 SPI 比 I2C 更"放手"：I2C 把寻址、仲裁都封进协议层了，你只管调 API；SPI 却把自由度全塞给你，连带责任也一起推给你——片选你要管，"消息包"你要自己凑，时序你得保证严丝合缝。所以这一篇我们不光要换 API，更要把"借总线"这套姿势练熟。

::: tip 学习目标
用 `module_spi_driver()` + `int probe(spi_device*)` + `void remove` 写出符合 6.12 / 7.1 规范的 SPI 设备驱动；通过 `spi_write_then_read` / `spi_transfer` 完成寄存器读写（搞懂 SPI 全双工下的"发地址收数据"时序）；最终把 ICM-20608 的六轴 + 温度数据读到用户空间。
:::

## 教程结构

我们沿用 I2C 那篇的节奏，"先理框架、再写代码、最后上板"，六节：

### 阶段一：框架理解

1. **[02_spi_framework](02_spi_framework.md)** —— SPI 驱动框架：`spi_controller`、`spi_driver`、`spi_device`
2. **[03_spi_master_analysis](03_spi_master_analysis.md)** —— 拆开 `spi-imx.c`，看主机驱动怎么注册

### 阶段二：驱动实现

3. **[04_driver_layer](04_driver_layer.md)** —— ICM-20608 驱动主体：寄存器读写、`probe`/`remove`、字符设备
4. **[05_device_tree](05_device_tree.md)** —— 设备树配置：启用 ECSPI3、片选、ICM-20608 节点

### 阶段三：实战验证

5. **[06_build_and_test](06_build_and_test.md)** —— 编译、上板、读六轴数据

## ICM-20608：六轴加一个温度

ICM-20608 是 TDK InvenSense 的一颗六轴传感器，把三轴陀螺仪、三轴加速度计和一颗温度传感器做到一起，对外走 SPI。在我们这块 I.MX6U-ALPHA 板上，它接在 **ECSPI3** 上，片选用 **GPIO1_IO20**（软件控制），最高时钟 **8MHz**。

它有两个贯穿整篇驱动的协议细节，先记牢。第一，**寄存器地址的最高位（bit7）决定读写**：写寄存器时地址 bit7 为 0，读寄存器时地址 bit7 置 1。第二，因为 SPI 是全双工的，要读 N 个字节数据，主机必须发 N+1 个字节——第一个字节是带读标志的地址，期间从 MISO 线上读回来的是"垃圾"（dummy），真正的数据从第二个字节才开始。这套时序在驱动实现那节会反复用到。数据寄存器从 `0x3B` 开始连续 14 个字节，正好是 ax/ay/az/temp/gx/gy/gz，我们可以一口气连读回来。

## 先认认环境

- **板子**：I.MX6U-ALPHA，ICM-20608 接 ECSPI3，CS = GPIO1_IO20
- **内核**：`linux-imx` 6.12.49（主开发）/ `mainline` 7.1.0（进阶）
- **源码**：仓库 `third_party/linux-imx`、`third_party/linux_mainline`
- **交叉工具链**：`arm-linux-gnueabihf-gcc`

设备树用项目自己的 `imx6ull-aes.dtsi`。有一点和 I2C 那篇不同：项目的 dtsi 里**默认没有启用 ECSPI3**（连节点都没挂设备），所以设备树那节我们要从零把 ECSPI3 唤醒、配片选、再挂上 ICM-20608。

## 老教程 vs 新内核：到底差在哪

SPI 这边"时代眼泪"尤其多，动手前先心里有谱。结构体层面，老教程全程的 `spi_master`，新内核里真名是 `spi_controller`，相关 API 也从 `spi_alloc_master` / `spi_register_master` 改成了 `spi_alloc_host` / `spi_register_controller`——这批带 master 的老包装在 7.1 已经删除。传输结构体层面，老教程里 `spi_transfer.delay_usecs` 这个字段没了，换成了 `struct spi_delay delay`（带 `.value` 和 `.unit`）。驱动注册层面，和老 I2C 教程一样，不再手写 `module_init`/`module_exit`，一行 `module_spi_driver()` 宏搞定，`remove` 也是 `void`。这些变化的来龙去脉，后面会一条条讲清楚。

## 配套文件

涉及的源码文件如下，源码由你自己建立、照着各节代码段敲进去：

- `icm20608.c` —— 驱动主体（SPI 框架 + 字符设备）
- `icm20608reg.h` —— ICM-20608 寄存器地址定义
- `icm20608_app.c` —— 用户空间测试程序
- 设备树片段 —— 在 `imx6ull-aes.dtsi` 里启用 `&ecspi3` 并挂 `icm20608@0`

## 小结

这一节我们理清了 SPI 的"自由与责任"、ICM-20608 的协议要点、环境配置，以及新老写法的差异。接下来钻进 SPI 框架内部，把 `spi_controller`、`spi_driver`、`spi_device` 的关系，以及那次从 `spi_master` 到 `spi_controller` 的改名讲透。

---

<ChapterNav variant="sub">
  <ChapterLink href="index.md" variant="sub">← 返回目录</ChapterLink>
  <ChapterLink href="02_spi_framework.md" variant="sub">SPI 驱动框架 →</ChapterLink>
</ChapterNav>
