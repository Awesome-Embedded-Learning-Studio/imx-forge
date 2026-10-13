# 常见问题与解决方案：移植过程中的坑

## 前言：这一章是您的急救包

说实话，这篇教程系列写到现在，已经涵盖了主线内核移植的主要步骤。但实际移植过程中，您一定会遇到各种奇怪的问题：有些是配置错误，有些是硬件问题，有些是版本差异。

这一章总结了一些最常见的问题和对应的解决方法。它更像一个"急救包"，当您卡住的时候可以翻一下，看看有没有类似的情况。如果这里没有，那就要靠您自己的调试能力和搜索引擎了。

## 报错速查表

| 报错信息 | 根本原因 | 解决方法 |
|----------|----------|----------|
| `Cannot connect bridge (-ENODEV)` | 设备用旧式 `display@0` 写法，缺少 `port/endpoint` | 按 07/08 章修改设备树 |
| `phandle_references: Reference to non-existent node display0` | 删了 display0 但没删 dtsi 里的 `display` 属性 | 加 `/delete-property/ display;` |
| `pin MX6UL_PAD_GPIO1_IO09 already requested by 1-0014` | GPIO 冲突，tsc 遗留节点跟触摸抢 GPIO1_IO09（真板日志形态；QEMU 里 tsc 先死在 xnur 脚上，看不到这行） | 删掉板级 dts 里的 `&tsc` 节点，见第四类 |
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
如果还不亮，就是硬件问题了：背光供电或 PWM 信号，咱们接着往下查。

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

**症状**：屏幕能发光，但您看到的全是黑色或白色。

**排查步骤**：

1. 检查 DRM 驱动：
```bash
dmesg | grep -E "mxsfb|panel"
# 应该看到 "bound panel-dpi"
```

2. 检查时序参数：
用示波器测量 LCD 接口的 PCLK、HSYNC、VSYNC 信号，咱们对照数据手册的时序图。常见错误：
- clock-frequency 不对
- hsync/vsync 极性反了
- 前肩后肩太小

3. 尝试写 framebuffer：
```bash
cat /dev/urandom > /dev/fb0 & sleep 2; kill %1
```
如果屏幕有反应（花屏），您就可以确认驱动工作正常，问题在时序参数。

### 问题：屏幕有花屏

**症状**：您能看到屏幕有颜色，但显示不正常，条纹、色块等。

**可能原因**：咱们常见这么几种：
1. 数据线引脚配置错误（检查 pinctrl）
2. 总线宽度不匹配（24bit vs 18bit）
3. 时钟频率太高或太低

**解决方法**：
检查 pinctrl_lcdif_dat 里的引脚配置，咱们确认每个 DATA 引脚都正确配置。

## 第二类——触摸问题

### 问题：触摸没反应

**排查步骤**：

1. 检查 I2C 通信：
```bash
i2cdetect -y 1
# 真板在 0x14 位置看到设备；QEMU 的 gt911 模型地址固定，在 0x5d
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

::: warning 未实测标注
咱们这套环境的 rootfs 不是标准发行版，没有包管理器，fbset 不一定在场。带 fbset 的系统上，这条命令的输出像素格式按 DRM fbdev 默认的 xrgb8888 排，分辨率按 1024x600 典型值给出，仅供对照字段含义，以实际输出为准。
:::

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

**可能原因**：MDIO 总线地址冲突，咱们往下核对地址。

**解决方法**：
检查设备树里的 PHY 地址，咱们逐个核对：
- ethphy0 应该是 reg = <2>
- ethphy1 应该是 reg = <1>

这些地址由硬件决定，不能在软件里改。

## 第四类——GPIO 冲突

### 典型报错

真板上实测（2026-10-13）：

```
pin MX6UL_PAD_GPIO1_IO09 already requested by 1-0014; cannot claim for 2040000.touchscreen
imx6ul-tsc 2040000.touchscreen: error -EINVAL: Error applying setting, reverse things back
```

1-0014 是先到先得的 GT9147，来抢脚的是 2040000.touchscreen——imx6ul-tsc，EVK 参考板遗留的电阻触摸控制器。QEMU 里看不到这两行：那边 probe 顺序相反，tsc 先死在 xnur 脚缺失（-2），触摸 12 秒后照常拿到脚。

### 原因与解法

板级 dtsi 里 gt9147 的 pinctrl 借用 tscgrp 这组引脚挂中断（GPIO1_IO09），遗留的 &tsc 节点引的又是同一组——一根脚两个主人，谁先 probe 谁赢。板子用不上电阻触摸，把 &tsc 节点整个删掉即可：主线 imx6ul.dtsi 里 tsc 默认就是 status = "disabled"，删掉等于回归默认，冲突随之消失；pinctrl_tsc 引脚组保留，gt9147 还要用。逐行解读在 [触摸屏移植](10_touch_gt9xx.md) 第五步；这根脚与 SD 电源调节器 reg_sd1_vmmc 的旧案在 07 篇战史三。

## 第五类——时钟问题

### 典型报错

```
mxsfb 21c8000.lcdif: failed to get clk: -517
```

### 原因

咱们遇到的情况通常是时钟源配置错误，或者时钟驱动没有正确初始化。

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

CMA（连续内存分配器）内存不够，咱们要知道 DRM 驱动需要大块连续内存。

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
2. 如果不需要，咱们删除引用或使用 `/delete-property/`

### 问题：内核配置冲突

```
error: 'CONFIG_FB_MXS' conflicts with 'CONFIG_DRM_MXSFB'
```

**原因**：咱们同时开启了旧 Framebuffer 和 DRM

**解决方法**：
咱们关掉旧 Framebuffer：
```bash
# CONFIG_FB_MXS is not set
# CONFIG_FB_MXC_SYNC_PANEL is not set
```

## 社区资源

如果这里没有您遇到的问题，咱们可以尝试以下资源：

1. **内核邮件列表**：linux-arm-kernel@lists.infradead.org，您可以直接发邮件求助
2. **Stack Overflow**：搜索 "linux mainline imx6ull"
3. **NXP 社区论坛**：community.nxp.com
4. **GitHub Issues**：相关项目的 issue 页面

## 写在最后

这个教程系列到这里就结束了。咱们从为什么选择主线内核开始，一步步讲解了环境搭建、源码获取、设备树写作、编译与 QEMU 首启验收、显示系统、触摸屏、网络接口，最后是调试技巧和常见问题。

主线内核的移植不是一件轻松的事，但当您看到屏幕亮起、触摸灵敏、网络通畅的那一刻，所有的辛苦都是值得的。更重要的是，通过这个过程，您真正理解了 Linux 内核的工作原理，这是用厂商 BSP 永远学不到的。

祝您移植顺利！

---

**完整检查清单**

移植完成后，用这个清单验证您的系统：

```bash
# 1. 内核版本
uname -r
# 应该显示 7.2.9 或类似

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
