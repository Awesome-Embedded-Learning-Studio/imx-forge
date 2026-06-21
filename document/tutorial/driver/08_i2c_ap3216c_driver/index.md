---
title: AP3216C I2C 驱动教程
---

<PageHeader icon="🔌" title="AP3216C I2C 驱动" description="用 6.12 / 7.1 现代 I2C API，从设备树到字符设备，完整重写一颗光照 / 距离 / 红外三合一传感器的驱动" />

## 版本说明

本教程基于以下内核版本，两套内核的 I2C 设备驱动公共 API 完全一致，写出来的 `.ko` 在两边都能直接跑：

- **linux-imx** 6.12.49 <Badge type="tip" text="推荐" />
- **mainline** 7.1.0 <Badge type="info" text="进阶" />

源码就躺在仓库的 `third_party/linux-imx` 与 `third_party/linux_mainline` 下，文中所有结构体定义、函数签名都对着这两棵树核对过，可以随时翻。

## 这一篇要解决什么问题

网上流传的 I2C 驱动教程，绝大多数还停在 4.1.15 那套老写法上：`probe` 拖着个 `const struct i2c_device_id *id` 参数，`remove` 还在老老实实 `return 0`，连 `class_create` 都要你手写一个 `THIS_MODULE`。这些代码原封不动抄到 6.12 / 7.1 上，要么直接编不过（`class_create` 从 6.4 起只剩一个参数），要么满屏 `incompatible pointer type` 警告。所以这一篇我们干脆把 AP3216C 的驱动整个推倒重写——从设备树到驱动主体再到测试程序，一行老代码都不照抄，全程用现代内核的 API。

## 学习路径

我们按"先理框架、再写代码、最后上板"的顺序推进。

### 🎯 推荐学习路径

#### **阶段一：框架理解**

1. **[02_i2c_framework](02_i2c_framework.md)** - I2C 驱动框架：适配器、设备、驱动是怎么扣在一起的
2. **[03_i2c_adapter_analysis](03_i2c_adapter_analysis.md)** - I.MX6U 的 I2C 适配器驱动 `i2c-imx.c` 拆解

#### **阶段二：驱动实现**

3. **[04_driver_layer](04_driver_layer.md)** - AP3216C 驱动层：寄存器读写、`probe`/`remove`、字符设备
4. **[05_device_tree](05_device_tree.md)** - 设备树配置：把硬件画进内核的地图

#### **阶段三：实战验证**

5. **[06_build_and_test](06_build_and_test.md)** - 编译、上板、拿真实数据

## 章节目录

<ChapterNav>
  <ChapterLink num="02" href="02_i2c_framework.md">I2C 驱动框架</ChapterLink>
  <ChapterLink num="03" href="03_i2c_adapter_analysis.md">I.MX6U 适配器分析</ChapterLink>
  <ChapterLink num="04" href="04_driver_layer.md">AP3216C 驱动层实现</ChapterLink>
  <ChapterLink num="05" href="05_device_tree.md">设备树配置</ChapterLink>
  <ChapterLink num="06" href="06_build_and_test.md">编译与上板测试</ChapterLink>
</ChapterNav>

::: tip 学习目标
搞懂 Linux I2C 驱动"总线驱动 / 设备驱动"的分层契约，能用 `module_i2c_driver()` + 单参数 `probe` + `void remove` 写出符合 6.12 / 7.1 规范的设备驱动，并通过 `i2c_transfer` / `i2c_smbus_*` 完成寄存器读写，最终把 AP3216C 的 IR / ALS / PS 三路真实数据读到用户空间。
:::

::: info 前置知识
- 字符设备驱动基础（`file_operations`、`cdev`、`class_create`）
- 设备树基本语法
- Platform 驱动模型（[03_platform_led_driver](../03_platform_led_driver/) 是很好的前置）
:::

::: details 延伸阅读
- [Linux I2C 子系统文档](https://www.kernel.org/doc/html/latest/i2c/)
- [instantiating-i2c-devices](https://www.kernel.org/doc/html/latest/i2c/instantiating-devices.html)
- AP3216C 数据手册（Lite-On）
:::

## 常见问题

### Q: 为什么 `probe` 只有一个参数了，老教程里还有个 `id`？

A: 那是给"非设备树时代"传匹配 ID 用的。现代驱动靠设备树 `compatible` 取数据，内核早在几个版本前就把这个参数砍了，新内核里 `i2c_driver.probe` 的签名就是 `int (*probe)(struct i2c_client *client)`，照老写法写会触发指针类型不匹配警告。

### Q: `remove` 为什么不能 `return 0`？

A: I2C 子系统的 `remove` 回调在 6.x 已经改成返回 `void`。你再写 `int` 返回类型并 `return 0`，赋给 `i2c_driver.remove` 时类型对不上，编译器会警告，而且这个返回值内核本来也不看。

### Q: `id_table` 还要不要写？

A: 纯设备树匹配的驱动可以不写——只要 `of_match_table` 能命中，`id_table` 永远轮不到被查询。留着无害，但属于历史包袱。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../07_input_subsystem_key/" variant="sub">← Input 子系统按键</ChapterLink>
  <ChapterLink href="../09_spi_icm20608_driver/" variant="sub">SPI ICM-20608 驱动 →</ChapterLink>
</ChapterNav>
