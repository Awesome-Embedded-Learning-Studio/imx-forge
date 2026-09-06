---
title: 串口工具使用（minicom）
---

# 串口工具使用（minicom）

> i.MX6ULL 的 debug 口是 UART1，板载 USB 转串口，咱们全程靠它看板子的输出。上电后所有启动日志（U-Boot → 内核 → rootfs）都从串口输出。本篇讲 minicom 的安装、配置与使用，并对比 picocom / screen。

## 一、为什么需要串口

嵌入式开发没有显示器，对咱们来说**串口就是眼睛**。U-Boot 启动、内核解压、驱动加载、rootfs 挂载、登录提示符——全在串口日志里。没有串口，板子起不来您都不知道卡在哪。

## 二、安装 minicom

```bash
sudo apt install minicom
```

## 三、配置串口

板载 USB 转串口插上后，您在 Linux 侧会看到它识别为 `/dev/ttyUSB0`（或 `ttyACM0`，用 `ls /dev/tty*` 确认）。

### 串口参数

| 参数 | 值 |
|------|------|
| 设备 | /dev/ttyUSB0 |
| 波特率 | 115200 |
| 数据位 | 8 |
| 停止位 | 1 |
| 校验 | 无 |
| 流控 | 无 |

### minicom 配置

```bash
sudo minicom -s
```

进入菜单 → `Serial port setup`：

```
A -    Serial Device : /dev/ttyUSB0
E -    Bps/Par/Bits  : 115200 8N1
F - Hardware Flow Control : No
G - Software Flow Control : No
```

您按 `A` 改设备，按 `E` 改波特率（115200），按 `F`/`G` 关流控。回车保存，选 `Save setup as dfl` 存为默认，再 `Exit` 退出。

## 四、使用

```bash
minicom
```

您会进入串口终端。常用快捷键（先按 `Ctrl+A` 松开再按）：

| 快捷键 | 作用 |
|--------|------|
| Ctrl+A → Z | 帮助菜单 |
| Ctrl+A → X | 退出 minicom |
| Ctrl+A → E | 开关本地回显 |
| Ctrl+A → C | 清屏 |

::: tip 想看启动日志就别开流控
硬件流控（RTS/CTS）默认开启会导致板子输出显示不出来，咱们务必把它设为 No。务必把 Hardware Flow Control 设为 No。
:::

## 五、权限问题

`/dev/ttyUSB0` 默认属 `dialout` 组，普通用户没权限访问：

```bash
# 把当前用户加入 dialout 组，免 sudo
sudo usermod -aG dialout $USER
# 重新登录或 newgrp dialout 生效
```

或者临时用 `sudo minicom`（不推荐长期）。

## 六、与 picocom / screen 对比

| 工具 | 优点 | 缺点 |
|------|------|------|
| minicom | 菜单配置直观、功能全 | 退出快捷键略繁琐 |
| picocom | 轻量、退出干净（Ctrl+A Ctrl+X） | 无菜单，全命令行参数 |
| screen | 系统自带、最简单 | 退出易残留会话 |

picocom 一行启动，咱们项目里 [practical/03](../practical/03_boot_and_debug.md) 即用此）：

```bash
picocom -b 115200 /dev/ttyUSB0
```

退出：`Ctrl+A` → `Ctrl+X`。

screen：

```bash
screen /dev/ttyUSB0 115200
```

退出：`Ctrl+A` → `K` → `y`。

## 七、常见问题

| 现象 | 根因 | 解法 |
|------|------|------|
| minicom 打不开设备 | 无权限 | 加入 dialout 组 |
| 连上没输出 | 流控没关 / TX/RX 接反 | 关 Hardware Flow Control；检查 TX↔RX 交叉 |
| 输出乱码 | 波特率错 | 确认 115200 |
| 设备是 ttyACM0 不是 ttyUSB0 | USB 转串口芯片不同 | `ls /dev/tty*` 看实际名 |
| 退出后串口被占用 | screen 残留会话 | `screen -ls` 找到并 `screen -X -S <id> quit` |

## 继续学习

- 硬件接口速查：[板子硬件接口速查表](03_hardware_quick_reference.md)
- 首次上电流程：[第一次上电与串口检查](05_first_boot_check.md)
- 启动日志解读：[practical/03 启动与调试](../practical/03_boot_and_debug.md)
- 开发台串口策略：Windows 直连与 usbipd 透传怎么选，见 [串口终端：开发台的第二块屏幕](../workflow/03_serial_terminal.md)
- 日志怎么读：[串口日志阅读路线](../debug/03_serial_log_reading.md)
