# 常见问题与解决方案：移植过程中的坑

## 前言：这篇文章是你的急救包

说实话，这篇教程系列写到现在，已经涵盖了主线内核移植的主要步骤。但实际移植过程中，你一定会遇到各种奇怪的问题：有些是配置错误，有些是硬件问题，有些是版本差异。

这篇文章总结了一些最常见的问题和对应的解决方法。它更像一个"急救包"，当你卡住的时候可以翻一下，看看有没有类似的情况。如果这里没有，那就要靠你的调试能力和搜索引擎了。

## 报错速查表

| 报错信息 | 根本原因 | 解决方法 |
|----------|----------|----------|
| `Cannot connect bridge (-ENODEV)` | 设备用旧式 `display@0` 写法，缺少 `port/endpoint` | 按 06/07 章修改设备树 |
| `phandle_references: Reference to non-existent node display0` | 删了 display0 但没删 dtsi 里的 `display` 属性 | 加 `/delete-property/ display;` |
| `pin already requested by 1-005d` | GPIO 冲突，触摸和 SD 卡抢引脚 | 删除 usdhc1 的冲突引脚 |
| `Panel driver not found` | `CONFIG_DRM_PANEL_SIMPLE` 没开启 | 开启该配置并重新编译 |
| `flexcan 2090000.can: failed to get clock` | CAN 驱动 probe 失败 | 检查时钟配置和 regulator |
| `mmc0: error -110 while initialising SD card` | SD 卡超时，可能是引脚冲突 | 检查 pinctrl 配置 |
| `Failed to allocate memory for DMA` | CMA 内存不够 | 增大 `linux,cma` size |
| `Kernel panic - not syncing: VFS: Unable to mount root fs` | 根文件系统挂载失败 | 检查 root= 参数和 rootfs |

## 第一类——显示问题

### 问题：LCD 不亮，背光也不亮

**症状**：屏幕全黑，没有任何反应。

**排查步骤**：

1. 检查背光驱动：
```bash
ls /sys/class/backlight/
echo 255 > /sys/class/backlight/*/brightness
```
如果还不亮，是硬件问题：背光供电或 PWM 信号。

2. 检查 PWM 配置：
```bash
cat /sys/kernel/debug/pwm | grep pwm1
# 应该看到 pwm1 的信息
```

3. 检查 regulator：
```bash
dmesg | grep regulator
# 应该看到 backlight-display 相关的 regulator 初始化日志
```

### 问题：LCD 不亮，背光亮

**症状**：屏幕能发光，但全是黑色或白色。

**排查步骤**：

1. 检查 DRM 驱动：
```bash
dmesg | grep -E "mxsfb|panel"
# 应该看到 "bound panel-dpi"
```

2. 检查时序参数：
用示波器测量 LCD 接口的 PCLK、HSYNC、VSYNC 信号，对比数据手册的时序图。常见错误：
- clock-frequency 不对
- hsync/vsync 极性反了
- 前肩后肩太小

3. 尝试写 framebuffer：
```bash
cat /dev/urandom > /dev/fb0 & sleep 2; kill %1
```
如果屏幕有反应（花屏），说明驱动工作正常，问题在时序参数。

### 问题：屏幕有花屏

**症状**：屏幕有颜色但不正常，条纹、色块等。

**可能原因**：
1. 数据线引脚配置错误（检查 pinctrl）
2. 总线宽度不匹配（24bit vs 18bit）
3. 时钟频率太高或太低

**解决方法**：
检查 pinctrl_lcdif_dat 里的引脚配置，确认每个 DATA 引脚都正确配置。

## 第二类——触摸问题

### 问题：触摸没反应

**排查步骤**：

1. 检查 I2C 通信：
```bash
i2cdetect -y 1
# 应该在 0x5d 位置看到设备
```

2. 检查驱动加载：
```bash
dmesg | grep goodix
# 应该看到 "Touchscreen registered"
```

3. 检查输入设备：
```bash
ls /dev/input/event*
cat /proc/bus/input/devices
```

### 问题：触摸坐标偏移

**解决方法**：

1. 检查屏幕分辨率：
```bash
fbset -i
# 确认分辨率是 1024x600
```

2. 用 tslib 校准：
```bash
ts_calibrate
ts_test
```

3. 检查触摸报告范围：
```bash
evtest /dev/input/event0
# 触摸时查看 ABS_MT_POSITION_X/Y 的值范围
```

## 第三类——网络问题

### 问题：网口不通

**排查步骤**：

1. 检查接口状态：
```bash
ip link show eth0
ethtool eth0
```

2. 检查 PHY 链路：
```bash
dmesg | grep fec
# 应该看到 "Link is Up - 100Mbps/Full"
```

3. 检查 PHY 寄存器：
```bash
cat /sys/bus/mdio_bus/devices/2188000.ethernet:02/phy_id
# 应该看到 PHY 的 ID
```

### 问题：两个网口只有一个能用

**可能原因**：MDIO 总线地址冲突

**解决方法**：
检查设备树里的 PHY 地址：
- ethphy0 应该是 reg = <2>
- ethphy1 应该是 reg = <1>

这些地址由硬件决定，不能在软件里改。

## 第四类——GPIO 冲突

这是 i.MX6ULL 开发板最常见的问题之一。

### 典型报错

```
pin MX6UL_PAD_GPIO1_IO09 already requested by 1-005d; cannot claim for 2040000.touchscreen
pin MX6UL_PAD_GPIO1_IO05 already requested by 1-005d; cannot claim for 2190000.mmc
```

### 原因

GT9147 触摸屏的引脚（GPIO1_IO09 和 GPIO1_IO05）和 SD 卡（usdhc1）的引脚冲突了。两个设备都想用这两个引脚，但 GPIO 只能配置一次。

### 解决方法

如果不需要 SD 卡，删除 usdhc1 pinctrl 里冲突的引脚：

```dts
pinctrl_usdhc1: usdhc1grp {
    fsl,pins = <
        /* ... 其他引脚 ... */
        /* 删除下面两行 */
        /* MX6UL_PAD_GPIO1_IO05__USDHC1_VSELECT    0x17059 */
        /* MX6UL_PAD_GPIO1_IO09__GPIO1_IO09        0x17059 */
    >;
};
```

如果 SD 卡必须用，需要调整硬件设计，把触摸屏引脚改到其他 GPIO 上。

## 第五类——时钟问题

### 典型报错

```
mxsfb 21c8000.lcdif: failed to get clk: -517
```

### 原因

时钟源配置错误，或者时钟驱动没有正确初始化。

### 解决方法

1. 检查设备树里的时钟配置：
```dts
&lcdif {
    assigned-clocks = <&clks IMX6UL_CLK_LCDIF_PRE_SEL>;
    assigned-clock-parents = <&clks IMX6UL_CLK_PLL5_VIDEO_DIV>;
};
```

2. 检查时钟驱动：
```bash
dmesg | grep clk
# 应该看到时钟驱动初始化的日志
```

## 第六类——内存问题

### 典型报错

```
Failed to allocate memory for DMA
```

### 原因

CMA（连续内存分配器）内存不够，DRM 驱动需要大块连续内存。

### 解决方法

增大设备树里的 CMA size：

```dts
reserved-memory {
    linux,cma {
        compatible = "shared-dma-pool";
        reusable;
        size = <0x10000000>;  /* 原来是 0xa000000，增大到 256MB */
        linux,cma-default;
    };
};
```

## 第七类——编译问题

### 问题：dtc 编译报错

```
arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi:123.45: error: phandle_references
```

**原因**：设备树引用了不存在的节点

**解决方法**：
1. 检查被引用的节点是否存在
2. 如果不需要，删除引用或使用 `/delete-property/`

### 问题：内核配置冲突

```
error: 'CONFIG_FB_MXS' conflicts with 'CONFIG_DRM_MXSFB'
```

**原因**：同时开启了旧 Framebuffer 和 DRM

**解决方法**：
关掉旧 Framebuffer：
```bash
# CONFIG_FB_MXS is not set
# CONFIG_FB_MXC_SYNC_PANEL is not set
```

## 社区资源

如果这里没有你的问题，可以尝试以下资源：

1. **内核邮件列表**：linux-arm-kernel@lists.infradead.org
2. **Stack Overflow**：搜索 "linux mainline imx6ull"
3. **NXP 社区论坛**：community.nxp.com
4. **GitHub Issues**：相关项目的 issue 页面

## 写在最后

这个教程系列到这里就结束了。我们从为什么选择主线内核开始，一步步讲解了环境搭建、源码获取、配置、设备树迁移、显示系统、触摸屏、网络接口，最后是调试技巧和常见问题。

主线内核的移植不是一件轻松的事，但当你看到屏幕亮起、触摸灵敏、网络通畅的那一刻，所有的辛苦都是值得的。更重要的是，通过这个过程，你真正理解了 Linux 内核的工作原理，这是用厂商 BSP 永远学不到的。

祝你移植顺利！

---

**完整检查清单**

移植完成后，用这个清单验证你的系统：

```bash
# 1. 内核版本
uname -r
# 应该显示 7.1.0 或类似

# 2. DRM 设备
ls /dev/dri/card0
cat /sys/class/drm/card0-HDMI-A-1/status
# 应该显示 connected

# 3. 触摸设备
ls /dev/input/event*
evtest /dev/input/event0
# 触摸应该有反应

# 4. 网络接口
ip link show eth0 eth1
ping -c 4 192.168.1.100
# 网络应该正常

# 5. 内核配置
zcat /proc/config.gz | grep -E "DRM_MXSFB|PANEL_SIMPLE|FEC|MICREL|GOODIX"
# 应该都是 y
```

**参考资源**

- [Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/) - 内核官方文档
- [i.MX 6ULL Reference Manual](https://www.nxp.com/docs/en/reference-manual/IMX6ULLRM.pdf) - 芯片参考手册
- [Device Tree Specification](https://www.devicetree.org/specifications/) - 设备树规范
- [DRM/KMS Documentation](https://www.kernel.org/doc/html/latest/gpu/drm-kms.html) - DRM 文档
