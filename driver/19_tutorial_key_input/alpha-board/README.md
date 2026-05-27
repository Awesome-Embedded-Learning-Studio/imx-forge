# 教程 19: Input 子系统按键驱动

## 概述

本驱动使用 **Linux Input 子系统**实现按键驱动 - 这是 Linux 中推荐的标准输入设备驱动方式。

## 主要特性

- **Input 设备接口** `/dev/input/eventX`
- **标准 evdev API**：兼容所有 Linux 输入工具
- **中断驱动** + 工作队列消抖
- **事件报告**：使用 `input_report_key()` + `input_sync()`
- **即插即用**：兼容 `evtest`、`xev` 等工具
- **标准化**：完全集成到 Linux Input 子系统

## 硬件连接

- **GPIO**: GPIO1_IO18 (UART1_CTS_B 引脚)
- **有效电平**: 低电平（按键按下拉低 GPIO）
- **按键码**: KEY_ENTER (28)

## 设备树

```dts
pinctrl_key: keygrp {
    fsl,pins = <
        MX6UL_PAD_UART1_CTS_B__GPIO1_IO18  0x1b0b0
    >;
};

imxaes_key_input: key-input {
    compatible = "imxaes-input-key";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_key>;
    gpios = <&gpio1 18 GPIO_ACTIVE_LOW>;
    label = "imxaes-key";
    linux,code = <28>;  /* KEY_ENTER */
    status = "okay";
};
```

## 编译

```bash
cd driver/19_tutorial_key_input/alpha-board
make
```

输出: `out/driver_artifacts/19_tutorial_key_input/19_tutorial_key_input_driver.ko`

## 使用方法

### 加载驱动
```bash
insmod 19_tutorial_key_input_driver.ko
```

### 查看输入设备
```bash
cat /proc/bus/input/devices | grep imxaes
```

### 使用 evtest 测试
```bash
evtest /dev/input/eventX
```

### 使用自定义应用测试
```bash
./input_key_demo
```

### 卸载驱动
```bash
rmmod 19_tutorial_key_input_driver
```

## 文件结构

```
19_tutorial_key_input/
├── alpha-board/
│   ├── 19_tutorial_key_input_driver.c    # 主驱动
│   ├── Makefile                          # 构建配置
│   └── README.md                         # 本文件
```

## 代码架构

```
┌─────────────────────────────────────┐
│     用户空间应用程序                   │
│     - evtest                         │
│     - input_key_demo                 │
│     - 任何 X11/Wayland 应用           │
└──────────────┬──────────────────────┘
               │ evdev API
               ▼
┌─────────────────────────────────────┐
│     Input 子系统核心                   │
│     - /dev/input/eventX              │
│     - 事件处理                        │
└──────────────┬──────────────────────┘
               │ input_report_key()
               ▼
┌─────────────────────────────────────┐
│     Input 设备驱动                    │
│     - input_register_device()        │
│     - 工作队列消抖                    │
└──────────────┬──────────────────────┘
               │ 中断处理函数
               ▼
┌─────────────────────────────────────┐
│     GPIO 子系统                       │
│     (GPIO1_IO18)                     │
└─────────────────────────────────────┘
```

## Input 事件格式

事件以标准的 `struct input_event` 格式报告：

```c
struct input_event {
    struct timeval time;
    __u16 type;      // EV_KEY (0x01)
    __u16 code;      // KEY_ENTER (28)
    __s32 value;     // 0=释放, 1=按下, 2=重复
};
```

## 与前序教程对比

| 特性 | 教程 17 | 教程 18 | 教程 19 |
|------|---------|---------|---------|
| 接口类型 | 自定义字符设备 | 自定义字符设备 | 标准 input 设备 |
| 设备节点 | `/dev/imxaes_key` | `/dev/imxaes_key_debounce` | `/dev/input/eventX` |
| 用户空间 API | 自定义 `read()` | 自定义 `read()` | 标准 evdev |
| 兼容工具 | 仅自定义应用 | 仅自定义应用 | `evtest`、`xev` 等 |
| 系统集成 | 无 | 无 | 完整桌面支持 |
| 消抖 | 无 | 工作队列 | 工作队列 |

## 为什么使用 Input 子系统？

Linux Input 子系统提供：

1. **标准化**：所有输入设备以相同方式工作
2. **兼容性**：兼容现有工具和应用
3. **功能丰富**：自动重复、grab、事件转发等
4. **集成性**：无缝集成 X11/Wayland/console
5. **调试友好**：丰富的调试工具（`evtest`、`input-events`）

## 相关教程

- **教程 17**: 基础 GPIO 按键驱动（无消抖）
- **教程 18**: 带消抖的自定义接口按键驱动
- **Linux Input 文档**: `Documentation/input/input.rst`
