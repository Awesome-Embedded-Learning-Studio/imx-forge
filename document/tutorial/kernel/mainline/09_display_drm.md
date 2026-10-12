# DRM 显示系统移植：LCD 驱动完整迁移指南

## 前言：这是整个移植最复杂的一章

先说一句实话：从 NXP BSP 迁移到主线内核，笔者认为最难的部分就是显示系统。为什么？因为整个架构都变了：从旧的 Framebuffer 框架迁移到 DRM/KMS 框架，驱动代码位置不同、设备树写法不同、调试方法也不同。

但好消息是，一旦您理解了 DRM 的基本概念，后续的调试就会容易很多。笔者会带您完整走过 LCD 驱动的迁移过程，从设备树编写到最终验证，并且尽量解释清楚每一步的原因，而不是只丢给您一堆命令。

## 第一步——理解 DRM 架构

DRM（Direct Rendering Manager）是 Linux 内核的图形子系统，最初用于 3D 图形加速，后来扩展到所有显示设备。对嵌入式系统来说，咱们主要关心 KMS（Kernel Mode Setting）部分，也就是内核负责设置显示模式的那部分代码。

### DRM 的核心组件

```
应用程序 / GUI 框架
       ↓ (read/write /dev/fb0 或 DRM ioctl)
  DRM 核心子系统
       ↓
  mxsfb CRTC (drivers/gpu/drm/mxsfb/)
       ↓  [OF graph: lcdif port → panel port]
  panel-dpi (drivers/gpu/drm/panel/panel-dpi.c)
       ↓  [物理并行 RGB 信号]
  LCD 屏幕硬件
```

- **CRTC**：显示控制器，负责从内存读取像素数据并输出到屏幕
- **Encoder**：编码器，把 CRTC 的数字信号转换成适合传输的格式（对于 eLCDIF 这个就是直接输出）
- **Connector**：连接器，描述物理连接方式（比如 DPI、LVDS、HDMI）
- **Panel**：面板，描述屏幕的时序参数和特性

对咱们这块 i.MX6ULL 的 eLCDIF 控制器来说，架构比较简单：CRTC 直接连接 Panel，没有中间的 Encoder。

### 为什么不用 panel-simple 而是 panel-dpi

您可能见过 `panel-simple` 驱动，它支持很多常见的屏幕。但 `panel-simple` 要求屏幕在驱动代码里预定义，而 `panel-dpi` 是一个通用驱动，时序参数完全由设备树的 `panel-timing` 节点指定。

咱们这块 7 寸 1024×600 屏，用 `panel-dpi` 最合适，因为它的时序参数不是标准的。

## 第二步——编写 panel 节点

咱们先写 panel 节点。它独立于 lcdif 之外，作为根节点的子节点：

```dts
/ {
    panel: panel-dpi {
        compatible = "panel-dpi";
        backlight = <&backlight_display>;

        /* 屏幕物理尺寸 */
        width-mm = <154>;
        height-mm = <86>;

        /* 时序参数 */
        panel-timing {
            clock-frequency = <51200000>;
            hactive = <1024>;
            vactive = <600>;
            hfront-porch = <160>;
            hback-porch = <140>;
            hsync-len = <20>;
            vback-porch = <20>;
            vfront-porch = <12>;
            vsync-len = <3>;
            hsync-active = <0>;
            vsync-active = <0>;
            de-active = <1>;
            pixelclk-active = <0>;
        };

        /* OF graph 连接 */
        port {
            panel_in: endpoint {
                remote-endpoint = <&lcdif_out>;
            };
        };
    };
};
```

### 时序参数说明

每个参数的含义：

| 参数 | 含义 | 我们的值 |
|------|------|----------|
| clock-frequency | 像素时钟频率 | 51.2 MHz |
| hactive | 水平有效像素 | 1024 |
| vactive | 垂直有效像素 | 600 |
| hfront-porch | 水平前肩 | 160 像素周期 |
| hback-porch | 水平后肩 | 140 像素周期 |
| hsync-len | 水平同步长度 | 20 像素周期 |
| vfront-porch | 垂直前肩 | 12 行 |
| vback-porch | 垂直后肩 | 20 行 |
| vsync-len | 垂直同步长度 | 3 行 |
| hsync-active | 水平同步极性 | 0（低电平有效） |
| vsync-active | 垂直同步极性 | 0（低电平有效） |
| de-active | 数据使能极性 | 1（高电平有效） |
| pixelclk-active | 像素时钟极性 | 0（下降沿采样） |

这些参数来自屏幕的数据手册，不同屏幕的值不同。笔者建议您对着手册逐项核对，写错了屏幕不会正常显示，甚至可能损坏硬件。

## 第三步——配置背光

背光用 PWM 控制，节点在根节点下：

```dts
/ {
    backlight_display: backlight-display {
        compatible = "pwm-backlight";
        pwms = <&pwm1 0 5000000 0>;
        brightness-levels = <0 4 8 16 32 64 128 255>;
        default-brightness-level = <6>;
        status = "okay";
    };
};
```

然后在 panel 节点里引用：`backlight = <&backlight_display>;`。

背光驱动会在 `/sys/class/backlight/` 下创建 sysfs 接口，您可以通过修改 `brightness` 文件控制亮度：

```bash
echo 255 > /sys/class/backlight/backlight-display/brightness  # 最亮
echo 0 > /sys/class/backlight/backlight-display/brightness    # 最暗
```

## 第四步——配置 lcdif 节点

接下来咱们改 lcdif 节点：删除旧的 `display` 属性，并添加 OF graph 连接：

```dts
&lcdif {
    assigned-clocks = <&clks IMX6UL_CLK_LCDIF_PRE_SEL>;
    assigned-clock-parents = <&clks IMX6UL_CLK_PLL5_VIDEO_DIV>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lcdif_dat &pinctrl_lcdif_ctrl>;
    status = "okay";

    /* 删除基础文件里的 display 属性 */
    /delete-property/ display;

    /* OF graph 连接 */
    port {
        lcdif_out: endpoint {
            remote-endpoint = <&panel_in>;
        };
    };
};
```

### 为什么需要 /delete-property/ display

`imx6ul.dtsi` 基础文件里的 lcdif 节点定义了 `display = <&display0>` 属性，这是旧写法的遗留。但基础文件咱们不能直接修改（它是只读的）。

咱们在板级设备树里用 `/delete-property/ display;`，就能在编译时覆盖删除这个属性。如果不删除，DTB 编译会报错：

```
error: phandle_references: Reference to non-existent node display0
```

因为 `display0` 节点已经被咱们删除了（用新的 panel 节点替代），而 `display` 属性还在引用它，就成了悬空引用。

## 第五步——配置 pinctrl

lcdif 的引脚配置包括数据线和控制线两组，咱们直接看写法：

```dts
&iomuxc {
    pinctrl_lcdif_dat: lcdifdatgrp {
        fsl,pins = <
            MX6UL_PAD_LCD_DATA00__LCDIF_DATA00  0x49
            MX6UL_PAD_LCD_DATA01__LCDIF_DATA01  0x49
            MX6UL_PAD_LCD_DATA02__LCDIF_DATA02  0x49
            MX6UL_PAD_LCD_DATA03__LCDIF_DATA03  0x49
            MX6UL_PAD_LCD_DATA04__LCDIF_DATA04  0x49
            MX6UL_PAD_LCD_DATA05__LCDIF_DATA05  0x49
            MX6UL_PAD_LCD_DATA06__LCDIF_DATA06  0x49
            MX6UL_PAD_LCD_DATA07__LCDIF_DATA07  0x49
            MX6UL_PAD_LCD_DATA08__LCDIF_DATA08  0x49
            MX6UL_PAD_LCD_DATA09__LCDIF_DATA09  0x49
            MX6UL_PAD_LCD_DATA10__LCDIF_DATA10  0x49
            MX6UL_PAD_LCD_DATA11__LCDIF_DATA11  0x49
            MX6UL_PAD_LCD_DATA12__LCDIF_DATA12  0x49
            MX6UL_PAD_LCD_DATA13__LCDIF_DATA13  0x49
            MX6UL_PAD_LCD_DATA14__LCDIF_DATA14  0x49
            MX6UL_PAD_LCD_DATA15__LCDIF_DATA15  0x49
            MX6UL_PAD_LCD_DATA16__LCDIF_DATA16  0x49
            MX6UL_PAD_LCD_DATA17__LCDIF_DATA17  0x49
            MX6UL_PAD_LCD_DATA18__LCDIF_DATA18  0x49
            MX6UL_PAD_LCD_DATA19__LCDIF_DATA19  0x49
            MX6UL_PAD_LCD_DATA20__LCDIF_DATA20  0x49
            MX6UL_PAD_LCD_DATA21__LCDIF_DATA21  0x49
            MX6UL_PAD_LCD_DATA22__LCDIF_DATA22  0x49
            MX6UL_PAD_LCD_DATA23__LCDIF_DATA23  0x49
        >;
    };

    pinctrl_lcdif_ctrl: lcdifctrlgrp {
        fsl,pins = <
            MX6UL_PAD_LCD_CLK__LCDIF_CLK         0x49
            MX6UL_PAD_LCD_ENABLE__LCDIF_ENABLE   0x49
            MX6UL_PAD_LCD_HSYNC__LCDIF_HSYNC     0x49
            MX6UL_PAD_LCD_VSYNC__LCDIF_VSYNC     0x49
        >;
    };
};
```

配置值 `0x49` 的含义：
- 位 0-3：驱动强度（0x9 = 强驱动）
- 位 4：PEED（快速使能）
- 位 5：PUE（上拉/下拉使能）
- 位 6：PKE（上拉/下拉保持使能）
- 位 7：ODE（开漏使能，0=禁用）

想深究每一位的含义，您可以查 i.MX6ULL 参考手册的 IOMUX 章节。

## 第六步——编译和烧录

设备树写好后，编译 DTB：

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- dtbs
```

把生成的 `imx6ull-aes.dtb` 烧录到板子。烧录方式取决于您的启动配置（SD 卡、eMMC、NFS 等）。

## 第七步——验证 DRM 驱动加载

启动后，咱们首先检查 dmesg 里的 DRM 相关日志：

```bash
dmesg | grep -E "drm|mxsfb|panel"
```

您应该看到类似这样的输出：

```
[    0.912345] mxsfb 21c8000.lcdif: Initializing
[    0.987654] panel-dpi: panel enabled
[    1.123456] mxsfb 21c8000.lcdif: bound panel-dpi (ops panel_dpi_ops)
[    1.234567] drm drm: GMA500 GEM enabled
[    1.345678] mxsfb 21c8000.lcdif: registered panic notifier
[    1.456789] [drm] Initialized mxsfb 1.0.0 for 21c8000.lcdif on minor 0
```

关键是 `bound panel-dpi` 这一行，您看到它就说明驱动成功找到了 panel 设备。

如果您看到的却是 `Cannot connect bridge (-ENODEV)`，说明 OF graph 连接有问题，或者 panel 驱动没有加载。

### 检查 DRM 设备节点

```bash
ls /dev/dri/
# 应该看到：card0  renderD128

ls /dev/fb*
# 应该看到：fb0  （DRM 的兼容层）
```

### 检查 connector 状态

```bash
cat /sys/class/drm/card0-HDMI-A-1/status
# 应该输出：connected

cat /sys/class/drm/card0-HDMI-A-1/modes
# 应该输出：1024x600
```

如果咱们看到 connector 状态是 `disconnected`，说明 panel 驱动没有正常 probe。

## 第八步——显示测试

### 方法一：fbset 测试

```bash
# 安装 fbset
apt install fbset

# 查看 framebuffer 信息
fbset -i
```

您应该看到：

```
mode "1024x600"
    geometry 1024 600 1024 600 32
    timings 0 0 0 0 0 0 0
    accel false
    rgba 8/16,8/8,8/0,8/0,0/0
endmode
```

### 方法二：写屏幕测试

```bash
# 显示随机颜色（花屏）
cat /dev/urandom > /dev/fb0 &
sleep 2
kill %1

# 清屏（全黑）
dd if=/dev/zero of=/dev/fb0
```

如果屏幕有反应，说明显示系统工作正常。

### 方法三：modetest 测试

如果安装了 `modetest` 工具：

```bash
modetest -M mxsfb
```

这会列出所有的 DRM 设备和模式，咱们调试时可以用它。

## 常见问题排查

### 问题一：Cannot connect bridge (-ENODEV)

这是最常见的报错，原因和解决方法：

| 原因 | 解决方法 |
|------|----------|
| 设备树用旧式 `display@0` 写法 | 改成 panel + port/endpoint 写法 |
| `CONFIG_DRM_PANEL_SIMPLE` 没开启 | 开启该配置并重新编译 |
| panel 节点状态是 `disabled` | 改成 `status = "okay"` |
| OF graph 连接错误 | 检查 `remote-endpoint` 的 phandle |

### 问题二：屏幕全黑但背光亮

这种情况通常是时序参数错误。您可以用示波器测量 LCD 接口的信号，对比数据手册的时序图。常见错误：

- clock-frequency 不对
- hsync/vsync 极性反了
- 前肩后肩的值太小

### 问题三：屏幕有花屏

花屏通常是：

- 数据线引脚配置错误
- 时钟频率太高或太低
- 总线宽度不匹配（24bit vs 18bit）

### 问题四：背光不亮

检查背光驱动：

```bash
ls /sys/class/backlight/
echo 255 > /sys/class/backlight/*/brightness
```

如果这样还不亮，多半是硬件问题（PWM 信号没输出、背光电源没供电），咱们就要往硬件方向查了。

## 下一章预告

到这里，您应该已经成功让 LCD 显示了。恭喜！这一关是主线移植里最难的，咱们一起迈过来了。

下一篇文章，我们会讲触摸屏的移植：

- GT9147 驱动配置
- I2C 设备树编写
- 中断和复位引脚配置
- GPIO 冲突问题解决
- 触摸校准与测试

显示有了，触摸也有了，图形界面才能正常工作。咱们下一章见。

---

**参考命令速查**

```bash
# 检查 DRM 日志
dmesg | grep -E "drm|mxsfb|panel"

# 检查设备节点
ls /dev/dri/ /dev/fb*

# 检查 connector 状态
cat /sys/class/drm/card0-HDMI-A-1/status
cat /sys/class/drm/card0-HDMI-A-1/modes

# 显示测试
cat /dev/urandom > /dev/fb0 & sleep 2; kill %1
dd if=/dev/zero of=/dev/fb0

# 背光控制
ls /sys/class/backlight/
echo 255 > /sys/class/backlight/*/brightness
```

**延伸阅读**

- [DRM/KMS Documentation](https://www.kernel.org/doc/html/latest/gpu/drm-kms.html) - DRM 子系统文档
- [Panel Framework Documentation](https://www.kernel.org/doc/html/latest/gpu/drm/kms.html) - Panel 框架文档
- [OF Graph Documentation](https://www.kernel.org/doc/html/latest/devicetree/bindings/graph.txt) - OF graph 规范
