# Input 子系统按键驱动教程

本教程讲解使用 Linux Input 子系统的标准按键驱动实现。Input 子系统是处理输入设备的"正统"方式，支持键盘、鼠标、触摸屏、游戏手柄等各种输入设备。

## 为什么学 Input 子系统

在前面的教程中，我们实现了两种按键驱动：一种是简单的字符设备接口，另一种是用 poll 改进的版本。这两套方案都能用，但都有自己的问题：

- **自定义协议**：设备节点和数据格式都是自定义的，应用层需要专门适配
- **兼容性差**：Qt、GTK、X11 这些框架不认识自定义设备
- **扩展困难**：多按键支持、事件类型扩展都要自己实现

Input 子系统解决了这些问题：
1. **标准接口**：所有输入设备用统一的 API
2. **用户空间支持**：X11、Wayland、Qt、GTK 直接支持
3. **自动设备管理**：无需手动创建设备节点
4. **内置功能**：消抖、自动重复、多按键支持

## 目录

1. [01_introduction.md](01_introduction.md) - 前言：别重复造轮子了
2. [02_input_architecture.md](02_input_architecture.md) - Input 子系统架构
3. [03_event_reporting.md](03_event_reporting.md) - 事件报告
4. [04_delayed_debounce.md](04_delayed_debounce.md) - 延时消抖
5. [05_userspace_integration.md](05_userspace_integration.md) - 用户空间集成
6. [06_build_and_test.md](06_build_and_test.md) - 编译和测试

## 学习目标

完成本教程后，你将：
- 理解 Input 子系统的分层架构（驱动层、Input Core、Handler）
- 掌握 `input_dev` 的分配、配置和注册
- 学会使用 `input_report_key()` 和 `input_sync()` 报告事件
- 了解 `delayed_work` 实现可重新调度的消抖
- 掌握与用户空间的集成（应用程序开发）

## 教程总结

Input 子系统是 Linux 输入设备的标准做法，提供了统一的事件报告接口和用户空间 API。驱动只需要调用事件报告函数，设备节点管理、事件分发都由子系统处理。

完成本教程后，你已经掌握了：
- Platform 驱动框架
- GPIO 子系统（`gpiod_*` API）
- 中断和工作队列（`delayed_work`）
- Input 子系统事件报告
- 用户空间集成（应用程序开发）

## 相关源码

- 驱动源码：`/home/charliechen/imx-forge/driver/19_tutorial_key_input/alpha-board/`
- 设备树：`/home/charliechen/imx-forge/driver/device_tree/alpha-board/19_tutorial_key_input/`
- 内核源码：`third_party/linux_mainline/drivers/input/`

## 前置知识

建议先完成以下教程：
- [Platform LED 驱动](../03_platform_led_driver/) - Platform 框架基础
- [GPIO 按键（轮询）](../05_gpio_key_driver/) - GPIO 输入机制
- [中断消抖按键](../06_debounced_key_driver/) - 中断与工作队列
