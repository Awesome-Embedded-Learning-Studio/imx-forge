# DRM 显示系统移植：LCD 驱动完整迁移指南

## 前言：这是显示链最深的一章

先说一句实话：这条从零移植的路上，笔者认为最难啃的部分就是显示系统。为什么？因为从旧 NXP BSP 的 Framebuffer 老写法到主线的 DRM/KMS 框架，整个架构都换了：驱动代码位置不同、设备树写法不同、调试方法也不同。

好在本卷把动手的部分放在了前面：您在 07 篇已经把 lcdif、panel、背光这条链的设备树亲手写进 imx6ull-aes.dtsi，08 篇也让它在 QEMU 里点了亮。本篇咱们放慢速度深读这条链：每个部件在 DRM 框架里站在哪个位置，probe 时按什么顺序咬合，验证与排障分别怎么下手。笔者会尽量解释清楚每一步的原因，而不是只丢给您一堆命令。

## 第一步：理解 DRM 架构

DRM（Direct Rendering Manager）是 Linux 内核的图形子系统，最初用于 3D 图形加速，后来扩展到所有显示设备。对嵌入式系统来说，咱们主要关心 KMS（Kernel Mode Setting）部分，也就是内核负责设置显示模式的那部分代码。

### DRM 的核心组件

```
应用程序 / GUI 框架
       ↓ (read/write /dev/fb0 或 DRM ioctl)
  DRM 核心子系统
       ↓
  mxsfb CRTC (drivers/gpu/drm/mxsfb/)
       ↓  [OF graph: lcdif port → panel port]
  panel-dpi (drivers/gpu/drm/panel/panel-simple.c 里的 panel-dpi 兼容)
       ↓  [物理并行 RGB 信号]
  LCD 屏幕硬件
```

- **CRTC**：显示控制器，负责从内存读取像素数据并输出到屏幕
- **Encoder**：编码器，把 CRTC 的数字信号转换成适合传输的格式（对于 eLCDIF 这个就是直接输出）
- **Connector**：连接器，描述物理连接方式（比如 DPI、LVDS、HDMI）
- **Panel**：面板，描述屏幕的时序参数和特性

对咱们这块 i.MX6ULL 的 eLCDIF 控制器来说，链路很短：CRTC 出来的信号经一个很薄的桥直接到 Panel，设备树里就是 lcdif 的 port 连 panel 的 port 这一条边。后面日志里会出现的 Bridge 一词，说的就是 panel 以 bridge 身份挂进链路这件事。

### 为什么不用 panel-simple 而是 panel-dpi

您可能见过 `panel-simple` 驱动，它支持很多常见的屏幕。但 `panel-simple` 要求屏幕在驱动代码里预定义，而 `panel-dpi` 是一个通用驱动，时序参数完全由设备树的 `panel-timing` 节点指定。

咱们这块 7 寸 1024×600 屏，用 `panel-dpi` 最合适，因为它的时序参数不是标准的。

## 第二步：panel 节点逐字段拆

panel 节点您在 07 篇已经写进 imx6ull-aes.dtsi 了，本节把它抄出来逐字段拆开看。它独立于 lcdif 之外，作为根节点的子节点：

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

| 参数 | 含义 | 咱们用的值 |
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
| pixelclk-active | 像素时钟极性 | 0（下降沿驱动数据、上升沿采样） |

这些参数来自屏幕的数据手册，不同屏幕的值不同。笔者建议您对着手册逐项核对，写错了屏幕不会正常显示，甚至可能损坏硬件。

## 第三步：背光节点

背光节点您在 07 篇也写过了，它挂在根节点下：

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

您在 sysfs 里看到的那个目录名，就是背光节点名 backlight-display；label backlight_display 里的下划线只在 dts 内部当 phandle 别名用，咱们起机后在 /sys/class/backlight/ 下看到的是连字符的节点名。

## 第四步：lcdif 节点与 OF graph 连线

lcdif 节点您在 07 篇写的是这样：把控制器打开、引脚和时钟配好，再用 OF graph 跟 panel 牵手：

```dts
&lcdif {
    assigned-clocks = <&clks IMX6UL_CLK_LCDIF_PRE_SEL>;
    assigned-clock-parents = <&clks IMX6UL_CLK_PLL5_VIDEO_DIV>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lcdif_dat &pinctrl_lcdif_ctrl>;
    status = "okay";

    port {
        lcdif_out: endpoint {
            remote-endpoint = <&panel_in>;
        };
    };
};
```

### 主线基础文件里没有旧式 display 属性

网上不少讲 i.MX 显示移植的资料会教您在板级里写 `/delete-property/ display;`，那是针对旧 NXP BSP 内核的：那些树的 lcdif 带着 `display = <&display0>` 这种旧式引用，display0 是一个把时序表写死在节点里的老式面板描述。主线 v7.2.9 的 `imx6ul.dtsi` 里 lcdif 节点只有寄存器、中断、时钟三样，status 默认 disabled，既没有 display 属性，display0 也无处定义，所以主线树上不需要任何 /delete-property/，旧资料里见到这类步骤可以直接跳过。

咱们在板级真正要做的只剩把链子两头接上：port 里那句 `remote-endpoint = <&panel_in>;`。接错了也不怕，dtc 在您编译时就会抓出来，报错形如 `ERROR (phandle_references): Reference to non-existent node or label "display0"`，指向不存在或没定义的引用，不用等上机才发现。

## 第五步：pinctrl 引脚配置

lcdif 的引脚配置包括数据线和控制线两组，您在 07 篇已经抄进 dtsi，咱们这里把写法和配置值拆开讲：

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

咱们把配置值 `0x49` 写成二进制是 0100 1001，按 i.MX6ULL 参考手册 IOMUXC 章的 SW_PAD_CTL_PAD 寄存器拆开读：bit0 的 SRE 为 1（快速翻转），bit5-3 的 DSE 为 001（驱动强度档位），bit7-6 的 SPEED 为 01（低带宽档），上下拉三件套 PUS、PUE、PKE 与开漏 ODE 全是 0。LCD 数据线方向单一，靠使能信号对齐时序，不需要上下拉兜底，这正是您看到那几位留 0 的原因。

想逐位深究，您可以查 i.MX6ULL 参考手册的 IOMUXC 章节。

## 第六步：编译与部署

设备树写好后，您编 DTB 还是 08 篇那条 O= 命令，目标要带 nxp/imx/ 前缀：

```bash
make O=/home/charliechen/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- nxp/imx/imx6ull-aes.dtb
```

部署咱们沿用 08 篇的 QEMU 流程：起机前 fdtput 往 dtb 副本补 MAC 那一步，记得做在新编出来的这份上，QEMU 用 -dtb 参数加载它。设备树是起机时一次性读进内核的，您换了 dtb 就得重新起机才生效，热着改没有用。

## 第七步：验证 DRM 驱动加载

起机后，咱们先看内核日志里的显示链：

```bash
dmesg | grep -E "drm|mxsfb|panel"
```

咱们在 08 篇同一套 QEMU 环境（mcimx6ul-evk 机型）里实测，输出如下：

```
[    0.112796] /soc/bus@2100000/lcdif@21c8000: Fixed dependency cycle(s) with /panel-dpi
[    0.112870] /panel-dpi: Fixed dependency cycle(s) with /soc/bus@2100000/lcdif@21c8000
[    0.296075] panel-simple panel-dpi: Specify missing bus_format
[    0.296124] panel-simple panel-dpi: Expected bpc in {6,8} but got: 0
[    0.310886] [drm] Initialized mxsfb-drm 1.0.0 for 21c8000.lcdif on minor 0
[    0.326685] mxsfb 21c8000.lcdif: Bridge does not provide bus format, assuming MEDIA_BUS_FMT_RGB888_1X24.
[    0.388288] mxsfb 21c8000.lcdif: [drm] fb0: mxsfb-drmdrmfb frame buffer device
```

成功的标志是最下面两行：Initialized mxsfb-drm 1.0.0 for 21c8000.lcdif on minor 0 说明 DRM 设备注册完成，占到了 minor 0；fb0 那行说明 fbdev 兼容层建好了。名字 mxsfb-drmdrmfb 里重复的 drm 不是笔者笔误，是内核把驱动名和 drmfb 后缀直接拼接出来的，内核源码注释自己都吐槽这个名字已经成了用户态接口，想改都改不了。

中间两条 panel-simple 的告警别当失败，也别想着把日志修饰干净。要解释它，最直接的办法是去读您自己树里的 drivers/gpu/drm/panel/panel-simple.c。panel-dpi 并不是一个独立的驱动文件，它是 panel-simple.c 里的一条 compatible（声明在文件尾部的 of_device_id 表里）：probe 时 panel_dpi_probe() 只读三样东西，panel-timing 子节点、width-mm、height-mm，装描述符的结构体用 kzalloc 分配，bus_format 和 bpc 两个成员从头到尾没人赋值，天然就是 0；随后 probe 流程给 DPI 类型的连接器做体检，bus_format 为 0 就打印 Specify missing bus_format，bpc 不在 {6,8} 里就打印 Expected bpc in {6,8} but got: 0。换句话说，这两条告警是 panel-dpi 这种写法的固有产物，您写的节点没毛病。

那格式最后怎么定的？看告警下面那行：Bridge does not provide bus format, assuming MEDIA_BUS_FMT_RGB888_1X24（出自 drivers/gpu/drm/mxsfb/mxsfb_kms.c）。panel 作为桥挂到 lcdif 上时没上报总线格式，mxsfb 就按最通用的 24 位 RGB888 兜底，恰好对上咱们 24 根数据线的接法，不影响点亮。

最上面两条 Fixed dependency cycle(s) 您也不用管：那是内核在理清 lcdif 与 panel 互相引用时的探测顺序说明，属于正常过程输出。

想顺着源码把这两条告警亲眼核一遍：

```bash
/usr/bin/grep -n 'bus_format\|bpc' drivers/gpu/drm/panel/panel-simple.c
```

您如果看到的却是 Cannot connect bridge 加 -ENODEV 这样的报错，说明 OF graph 连接有问题，或者 panel 驱动没编进内核，排障见本章末尾问题一。

### 检查 DRM 设备节点

```bash
ls /sys/class/drm/
# 实测输出：card0  card0-DPI-1  version

ls /dev/dri/
# 只有 card0。没有 renderD128 是正常的：那是带 3D 渲染能力的 GPU 才有的渲染节点，
# mxsfb 注册的驱动特性只有 GEM、MODESET、ATOMIC，不含 RENDER，所以只出 card0。

ls /dev/fb*
# 只有 fb0，就是 dmesg 里 fb0 那行建出来的 fbdev 兼容设备
```

### 检查 connector 状态

咱们这块板的连接器不是 HDMI 那类可插拔接口：屏固定接在并行 RGB 总线上，内核按 DPI 类型给它注册连接器，您看到的名字是 card0-DPI-1。DPI 这个类型是 panel-simple 替 panel-dpi 定死的，panel_dpi_probe() 里那句注释原话是不知道这个节点对应什么连接器、猜一个，猜的就是 DPI；尾巴上的 1 是 DRM 给同类型连接器的编号，从 1 起数。固定面板没有热插拔的概念，status 恒为 connected，也不存在插拔事件。

```bash
cat /sys/class/drm/card0-DPI-1/status
# 实测输出：connected

cat /sys/class/drm/card0-DPI-1/modes
# 实测输出：1024x600
```

您在 modes 里看到的 1024x600，就是 panel-timing 那串参数拼出来的唯一一条固定模式。这两个文件哪个是空的或者压根不存在，多半是 panel 没 probe 成功，咱们回头上一节看 dmesg。

## 第八步：显示测试

### 方法一：fbset 测试

```bash
fbset -i
```

::: warning 未实测标注
咱们这套环境的 rootfs 不是标准发行版，没有包管理器，fbset 不一定在场。下面这份输出是带 fbset 的系统上的典型样子，像素格式按 DRM fbdev 默认的 xrgb8888 排，供您对照字段含义用，以实际输出为准。
:::

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
# 往帧缓冲里灌随机字节，有屏的话表现为噪点花屏
cat /dev/urandom > /dev/fb0 &
sleep 2
kill %1

# 清屏（全黑）
dd if=/dev/zero of=/dev/fb0
```

咱们这套 QEMU 环境没有真屏可看，这两个命令的意义在通路验证：命令不报错，说明从用户态到 fb0 再到驱动的整条写入路径是通的；屏幕上真的出现噪点或变黑，要等您在实际的板子上看。反过来，命令报了错那就是驱动或设备节点的问题，回头查第七步。

### 方法三：modetest 测试

如果 rootfs 里带了 `modetest` 工具：

```bash
modetest -M mxsfb-drm
```

-M 后面跟的是 DRM 驱动名，mxsfb 注册的名字是 mxsfb-drm，跟您在 dmesg 里看到的 Initialized mxsfb-drm 那行同款，写成 mxsfb 会报找不到驱动。它会列出 connector、encoder、CRTC 全套信息和模式，咱们调试显示时非常好用。

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
# 实测输出：backlight-display
echo 255 > /sys/class/backlight/backlight-display/brightness
```

如果目录在、命令也不报错，咱们在 QEMU 里就别往硬件方向想了：QEMU 没有真灯可亮，背光设备在位（08 篇断言表里 BL 那一项）就说明驱动链是通的，亮度对屏的实际作用要等您在实际的板子上看；目录都不在，才是 pwm-backlight 没 probe 成功，回头查设备树。

## 下一章预告

到这里，您应该已经成功让 LCD 显示了。恭喜！这一关是主线移植里最难的，咱们一起迈过来了。

下一篇文章咱们讲触摸屏的移植：

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
ls /sys/class/drm/        # 实测：card0  card0-DPI-1  version
ls /dev/dri/ /dev/fb*     # card0 无 renderD128 属正常；fb0 是 fbdev 兼容层

# 检查 connector 状态
cat /sys/class/drm/card0-DPI-1/status    # 实测：connected
cat /sys/class/drm/card0-DPI-1/modes     # 实测：1024x600

# 显示测试
cat /dev/urandom > /dev/fb0 & sleep 2; kill %1
dd if=/dev/zero of=/dev/fb0

# 背光控制
ls /sys/class/backlight/                  # 实测：backlight-display
echo 255 > /sys/class/backlight/backlight-display/brightness
```

**延伸阅读**

- [DRM/KMS Documentation](https://www.kernel.org/doc/html/latest/gpu/drm-kms.html) - DRM 子系统文档
- [Panel Framework Documentation](https://www.kernel.org/doc/html/latest/gpu/drm/kms.html) - Panel 框架文档
- [OF Graph Documentation](https://www.kernel.org/doc/html/latest/devicetree/bindings/graph.txt) - OF graph 规范
