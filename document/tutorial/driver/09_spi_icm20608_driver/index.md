---
title: ICM-20608 SPI 驱动教程
---

<PageHeader icon="📡" title="ICM-20608 SPI 驱动" description="用 6.12 / 7.1 现代 SPI API，从 spi_controller 到字符设备，完整重写一颗六轴传感器的驱动" />

## 版本说明

本教程基于以下内核版本，SPI **设备驱动**的公共 API 在两边完全一致，写出来的 `.ko` 两边都能跑：

- **linux-imx** 6.12.49 <Badge type="tip" text="推荐" />
- **mainline** 7.1.0 <Badge type="info" text="进阶" />

唯一要注意的差异在**控制器侧**命名：`spi_alloc_master` / `spi_register_master` 这批带 "master" 的老 API，在 6.12 还作为兼容别名存在，到了 7.1 已经被彻底删除，统一成 `spi_alloc_host` / `spi_register_controller`。我们写设备驱动用不到它们，但分析 `spi-imx.c` 时会碰到，到时候会讲清楚。

## 这一篇要解决什么问题

老 SPI 教程的"时代眼泪"比 I2C 还多：满屏幕的 `spi_master`、`spi_alloc_master`、`spi_register_master`，传输结构体里还在用 `.delay_usecs`，`remove` 还在 `return 0`。这套代码搬到 6.12 / 7.1 上：`spi_master` 在新内核里其实早就该叫 `spi_controller`，`.delay_usecs` 字段被换成了 `struct spi_delay delay`，老写法要么编不过要么报警告。所以这一篇我们照例把 ICM-20608 的 SPI 驱动整个重写——从控制器框架、设备驱动、设备树到上板测试，全程现代 API。

## 学习路径

我们和 I2C 那篇一样，按"先理框架、再写代码、最后上板"推进。

### 🎯 推荐学习路径

#### **阶段一：框架理解**

1. **[02_spi_framework](02_spi_framework.md)** - SPI 驱动框架：`spi_controller`、`spi_driver`、`spi_device`
2. **[03_spi_master_analysis](03_spi_master_analysis.md)** - I.MX6U 的 SPI 主机驱动 `spi-imx.c` 拆解

#### **阶段二：驱动实现**

3. **[04_driver_layer](04_driver_layer.md)** - ICM-20608 驱动层：`spi_write_then_read`、`probe`/`remove`、字符设备
4. **[05_device_tree](05_device_tree.md)** - 设备树配置：启用 ECSPI3、片选、ICM-20608 子节点

#### **阶段三：实战验证**

5. **[06_build_and_test](06_build_and_test.md)** - 编译、上板、读六轴数据

## 章节目录

<ChapterNav>
  <ChapterLink num="02" href="02_spi_framework.md">SPI 驱动框架</ChapterLink>
  <ChapterLink num="03" href="03_spi_master_analysis.md">I.MX6U 主机驱动分析</ChapterLink>
  <ChapterLink num="04" href="04_driver_layer.md">ICM-20608 驱动层实现</ChapterLink>
  <ChapterLink num="05" href="05_device_tree.md">设备树配置</ChapterLink>
  <ChapterLink num="06" href="06_build_and_test.md">编译与上板测试</ChapterLink>
</ChapterNav>

::: tip 学习目标
搞懂 SPI "主机驱动 / 设备驱动"的分层，理解 `spi_master` 为何改名 `spi_controller`、主机驱动为何实现 `transfer_one` 而非 `transfer`；能用 `spi_write_then_read` / `spi_transfer` 完成寄存器读写，写出符合 6.12 / 7.1 规范的 SPI 设备驱动，最终把 ICM-20608 的六轴 + 温度数据读到用户空间。
:::

::: info 前置知识
- 字符设备驱动基础
- 设备树基本语法
- 建议先读完 [08 AP3216C I2C 驱动](../08_i2c_ap3216c_driver/)——SPI 框架和 I2C 哲学一致，先吃透 I2C 能事半功倍
:::

::: details 延伸阅读
- [Linux SPI 子系统文档](https://www.kernel.org/doc/html/latest/spi/)
- [spi-summary](https://www.kernel.org/doc/html/latest/spi/spi-summary.html)
- ICM-20608 数据手册（TDK InvenSense）
:::

## 常见问题

### Q: `spi_master` 和 `spi_controller` 是什么关系？

A: 真正的结构体名是 `spi_controller`。`spi_master` 是历史遗留的名字——早期 SPI 只能做主机，结构体就叫 master；后来内核支持了从机（target）角色，于是改名 `spi_controller`，并按"host / target"重新命名角色。现在写代码应该统一用 `spi_controller` 和 `spi_alloc_host`。

### Q: 为什么 `probe` 里设了 `spi->mode` 还要调 `spi_setup`？

A: 设 `spi->mode` 只是改了软件层面的字段值，硬件控制器还没更新。`spi_setup` 会把 mode、时钟频率、字宽这些固化到控制器寄存器里（算分频、配时序）。漏了这一步，控制器可能还停在复位默认态，通信必败。

### Q: 主机驱动到底该实现 `transfer` 还是 `transfer_one`？

A: 现代队列化驱动实现 `transfer_one`（处理单个 `spi_transfer`），通用的 `transfer_one_message` 由 SPI 核心提供。只有老式的 bitbang 驱动才实现 `transfer`。I.MX6U 的 `spi-imx.c` 就是 `transfer_one` 路线。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../08_i2c_ap3216c_driver/" variant="sub">← AP3216C I2C 驱动</ChapterLink>
  <ChapterLink href="../modules/" variant="sub">模块开发 →</ChapterLink>
</ChapterNav>
