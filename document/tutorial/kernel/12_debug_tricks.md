# 主线内核调试技巧：那些让您少走弯路的方法

## 前言：调试是嵌入式开发的日常

说实话，移植主线内核没有一次就成功的。至少笔者的经历是这样的：编译通过了 → 部署 → 启动 → 报错 → 改代码 → 再编译 → 再报错……循环好几次，直到所有问题都解决。

调试的过程其实是理解系统的过程。每解决一个问题，您就对内核的工作原理多了一分理解。这一章总结了笔者在调试主线内核时常用的方法，希望能帮您少走一些弯路。

## 第一类技巧——dmesg 日志分析

dmesg 是您最好的朋友。内核的几乎所有重要信息都会通过 printk 输出到 dmesg，咱们只要学会正确阅读 dmesg，调试就成功了一半。

### 基本用法

```bash
# 查看完整日志
dmesg

# 清空日志
dmesg -c

# 实时跟踪日志
dmesg -w

# 只看 ERROR 级别的日志
dmesg -l err

# 只看 WARN 级别的日志
dmesg -l warn

# 带时间戳查看
dmesg -T
```

### 按子系统过滤

```bash
# 显示相关
dmesg | grep -E "drm|fb|panel|lcdif|mxsfb"
# 输出：
# [    0.912345] mxsfb 21c8000.lcdif: Initializing
# [    0.987654] panel-dpi: panel enabled
# [    1.123456] mxsfb 21c8000.lcdif: bound panel-dpi

# 网络相关
dmesg | grep -E "fec|net|phy|eth"

# 触摸相关
dmesg | grep -E "touch|goodix|input"

# 设备树相关
dmesg | grep -E "of_|dtb|fdt"
```

### 理解日志级别

内核日志有 8 个级别：

| 级别 | 数值 | 说明 |
|------|------|------|
| KERN_EMERG | 0 | 系统不可用 |
| KERN_ALERT | 1 | 需要立即处理 |
| KERN_CRIT | 2 | 严重情况 |
| KERN_ERR | 3 | 错误 |
| KERN_WARNING | 4 | 警告 |
| KERN_NOTICE | 5 | 正常但需要注意 |
| KERN_INFO | 6 | 信息 |
| KERN_DEBUG | 7 | 调试信息 |

如果您觉得日志太多，可以在内核命令行加 `loglevel=4`，只显示 WARN 及以上级别的日志。

### 常见报错模式

```bash
# 驱动 probe 失败
dmesg | grep "probe.*failed"

# 资源冲突
dmesg | grep "conflict"

# 设备不存在
dmesg | grep "ENODEV"

# 内存分配失败
dmesg | grep "alloc.*failed"
```

## 第二类技巧——设备树验证

设备树写错了，驱动就 probe 不了。但问题是怎么知道是设备树的问题？以下方法可以帮您验证。

### 方法一：/proc/device-tree

内核会把设备树解析后的内容放到 `/proc/device-tree` 目录下，您可以直接查看：

```bash
# 列出所有节点
ls /proc/device-tree/

# 查看 lcdif 节点
ls /proc/device-tree/soc/bus@2100000/lcdif@21c8000/

# 读取 lcdif 的 compatible 属性
cat /proc/device-tree/soc/bus@2100000/lcdif@21c8000/compatible

# 读取 lcdif 的 status 属性
cat /proc/device-tree/soc/bus@2100000/lcdif@21c8000/status
```

咱们这样判读：如果 status 是 `okay`，说明设备已启用；如果是 `disabled`，说明设备被禁用；如果文件不存在，说明节点定义有问题。

### 方法二：dtc 反编译

您可以把运行中的设备树导出成 DTS 源文件：

```bash
# 反编译整个设备树
dtc -I fs /proc/device-tree -O dts -o /tmp/running.dts

# 查看某个节点
dtc -I fs /proc/device-tree -O dts 2>/dev/null | grep -A 20 "lcdif"
```

对比您写的 DTS 源文件和运行中的 DTS，咱们能发现很多问题。

### 方法三：检查 OF graph 连接

对于 DRM 显示系统，OF graph 的连接很重要，咱们单独检查一下：

```bash
# 查看 panel 的 remote-endpoint
cat /proc/device-tree/panel-dpi/port/panel_in/remote-endpoint

# 查看 lcdif 的 remote-endpoint
cat /proc/device-tree/soc/bus@2100000/lcdif@21c8000/port/lcdif_out/remote-endpoint
```

这两个 remote-endpoint 应该互相指向。您如果看到一个空的，说明连接有问题。

## 第三类技巧——DRM 调试接口

咱们先看 DRM 子系统的调试接口，它们都在 `/sys/kernel/debug/dri/` 下（需要 debugfs 挂载）。

### 挂载 debugfs

```bash
mount -t debugfs none /sys/kernel/debug
```

### 查看 DRM 状态

```bash
# 列出所有 DRM 设备
ls /sys/kernel/debug/dri/

# 查看 connector 状态
cat /sys/class/drm/card0-HDMI-A-1/status
# 输出：connected 或 disconnected

# 查看 connector 支持的模式
cat /sys/class/drm/card0-HDMI-A-1/modes
# 输出：1024x600 或其他分辨率

# 查看 framebuffer 信息
cat /sys/class/graphics/fb0/mode
# 输出：1024x600p-60
```

### modetest 工具

如果 rootfs 里带了 `modetest`：

```bash
# 列出所有设备
modetest

# 只测试 mxsfb 这一路
modetest -M mxsfb-drm

# 测试模式设置
modetest -M mxsfb-drm -s 1024x600@RG24
```

modetest 会显示所有 connector、encoder、CRTC 的信息，咱们还能用它直接设置模式测试显示。-M 后面跟的是 DRM 驱动名，mxsfb 注册的名字是 mxsfb-drm，写成 mxsfb 会报找不到驱动，09 篇讲过这里的来龙去脉。

## 第四类技巧——内核配置检查

有时候问题不是代码，而是配置。您需要确认内核是否开启了必要的功能。

### 检查 .config

```bash
# 查看当前配置
cat /proc/config.gz | gunzip

# 或者在源码目录
cat .config

# 搜索特定配置
cat /proc/config.gz | gunzip | grep DRM
cat /proc/config.gz | gunzip | grep PANEL
```

### 关键配置检查清单

```bash
# DRM 相关
zcat /proc/config.gz | grep -E "CONFIG_DRM|CONFIG_FB"
# 应该看到：
# CONFIG_DRM=y
# CONFIG_DRM_MXSFB=y
# CONFIG_DRM_PANEL=y
# CONFIG_DRM_PANEL_SIMPLE=y
# CONFIG_FB_MXS is not set  ← 必须是 not set

# 网络相关
zcat /proc/config.gz | grep -E "CONFIG_FEC|CONFIG_MICREL"
# 应该看到：
# CONFIG_FEC=y
# CONFIG_MICREL_PHY=y

# 触摸相关
zcat /proc/config.gz | grep -E "CONFIG_TOUCHSCREEN|CONFIG_INPUT"
# 应该看到：
# CONFIG_TOUCHSCREEN_GOODIX=y
# CONFIG_INPUT_TOUCHSCREEN=y
```

## 第五类技巧——硬件调试

有时候问题在硬件层面，咱们需要用示波器、万用表等工具。

### GPIO 状态检查

```bash
# 查看 GPIO 的 sysfs 接口
ls /sys/class/gpio/

# 导出 GPIO
echo 49 > /sys/class/gpio/export
cat /sys/class/gpio/gpio49/direction
cat /sys/class/gpio/gpio49/value

# 设置 GPIO 方向和值
echo out > /sys/class/gpio/gpio49/direction
echo 1 > /sys/class/gpio/gpio49/value
```

### I2C 设备检查

先确认 i2c-tools 在不在场：咱们这套 rootfs 不是标准发行版，没有包管理器，工具可能是编译 rootfs 时就放进去的，也可能压根没有；标准发行版上一条 `apt install i2c-tools` 就有。

```bash
# 扫描 I2C 总线
i2cdetect -y 0
i2cdetect -y 1

# 读取 I2C 寄存器（GT9147 真板地址 0x14）
i2cget -y 1 0x14 0x00

# 写入 I2C 寄存器
i2cset -y 1 0x14 0x00 0x01
```

GT9147 的 I2C 地址这里得按双轨口径说：真板上实测这颗芯片挂在总线 1 的 0x14（7 位地址）；QEMU 的 gt911 模型把地址硬编码在 0x5d，来龙去脉 07 篇战史二讲过。本节示例按真板语境写 0x14，您在 QEMU 里做同样的检查，就把命令里的 0x14 换成 0x5d。用 `i2cdetect -y 1` 在对应位置能看到设备，就说明 I2C 通信正常。

### 网络接口检查

```bash
# 查看接口状态
ip link show eth0
ethtool eth0

# 查看 PHY 寄存器
cat /sys/bus/mdio_bus/devices/2188000.ethernet:02/phy_id

# 抓包分析
tcpdump -i eth0 -w /tmp/capture.pcap
```

## 第六类技巧——trace 和 latency

如果您需要分析性能问题或时序问题，可以用 ftrace：

```bash
# 挂载 debugfs
mount -t debugfs none /sys/kernel/debug

# 查看可用的 tracer
cat /sys/kernel/debug/tracing/available_tracers

# 启用 function tracer
echo function > /sys/kernel/debug/tracing/current_tracer
cat /sys/kernel/debug/tracing/trace

# 只跟踪某个函数
echo drm_atomic_helper_commit > /sys/kernel/debug/tracing/set_ftrace_filter
cat /sys/kernel/debug/tracing/trace
```

ftrace 能帮咱们分析函数调用关系和执行时间，对理解内核行为很有帮助。

## 常见问题速查表

| 现象 | 可能原因 | 检查方法 |
|------|----------|----------|
| LCD 不亮，背光也不亮 | 背光供电问题 | 检查 `cat /sys/class/backlight/*/brightness` |
| LCD 不亮，背光亮 | 时序参数错误 | 用示波器测 LCD 接口信号 |
| 触摸没反应 | I2C 通信失败 | `i2cdetect -y 1`：真板看 0x14，QEMU 看 0x5d |
| 网口不通 | PHY 链路问题 | `ethtool eth0` 检查链接状态 |
| dmesg 里全是 defer probe | 依赖设备未就绪 | 等待几秒后检查，或检查设备树顺序 |
| 编译报头文件找不到 | 依赖没装 | 检查 `make menuconfig` 配置 |

## 完整调试流程示例

假设您遇到 LCD 不显示的问题，咱们完整的调试流程可能是：

```bash
# 1. 检查 dmesg
dmesg | grep -E "drm|panel|lcdif"
# 如果看到 "Cannot connect bridge (-ENODEV)"，说明 panel 没找到

# 2. 检查设备树
ls /proc/device-tree/panel-dpi/
# 如果目录不存在，说明 panel 节点没定义

# 3. 检查内核配置
zcat /proc/config.gz | grep PANEL_SIMPLE
# 如果是 n，说明驱动没编译进内核

# 4. 检查 DRM 状态
cat /sys/class/drm/card0-HDMI-A-1/status
# 如果是 disconnected，说明 connector 没初始化

# 5. 检查背光
cat /sys/class/backlight/*/brightness
echo 255 > /sys/class/backlight/*/brightness
# 如果屏幕变亮，说明背光是好的

# 6. 用示波器测 LCD 接口信号
# 如果信号正常，说明驱动工作正常，问题在屏幕硬件
```

## 下一章预告

到这里，您应该掌握了主线内核调试的基本方法。有了这些工具，咱们遇到问题就能快速定位。

最后一章，咱们会汇总常见问题和解决方案：

- 报错速查表
- GPIO 冲突解决
- 时钟配置问题
- 电源管理问题
- 启动失败排查

掌握了调试方法和常见问题的解决思路，您就基本具备了独立移植主线内核的能力。咱们最后一章见。

---

**参考命令速查**

```bash
# dmesg 分析
dmesg | grep -E "drm|panel"
dmesg -l err
dmesg -T

# 设备树验证
ls /proc/device-tree/panel-dpi/
dtc -I fs /proc/device-tree -O dts -o running.dts

# DRM 调试
cat /sys/class/drm/card0-HDMI-A-1/status
modetest -M mxsfb

# 内核配置检查
zcat /proc/config.gz | grep DRM
zcat /proc/config.gz | grep PANEL

# I2C 检查（GT9147 真板 0x14，QEMU 侧 0x5d）
i2cdetect -y 1
i2cget -y 1 0x14 0x00

# 网络检查
ethtool eth0
ip link show
```

**延伸阅读**

- [Linux Kernel Debugging](https://www.kernel.org/doc/html/latest/admin-guide/bug-hunting.html) - 内核调试指南
- [ftrace Documentation](https://www.kernel.org/doc/html/latest/trace/ftrace.html) - ftrace 文档
- [debugfs Documentation](https://www.kernel.org/doc/html/latest/filesystems/debugfs.html) - debugfs 文档
