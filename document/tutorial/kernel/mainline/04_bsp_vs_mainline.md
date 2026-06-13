---
title: BSP vs 主线对比
---

# BSP vs 主线深度对比：那些让你踩坑的架构差异

## 前言：这一章是整个移植的核心

说实话，这篇文章可能是整个系列里最重要的一篇。如果你只是想编译一个能跑的内核，照着网上的教程敲命令就行了。但如果你想真正理解为什么移植这么麻烦，为什么设备树要这么写，为什么 dmesg 里面全是报错，那你必须理解 BSP 内核和主线内核的根本差异。

这些差异不是某个配置项改了，或者某个函数名变了，而是整个子系统架构级别的变化。最典型的是显示系统：从旧的 Framebuffer 框架迁移到 DRM/KMS 框架。这不仅仅是代码位置不同，连设备树的写法都完全变了。

这篇文章会从几个关键子系统入手，对比 BSP 和主线的差异。理解了这些，后面的设备树迁移和驱动配置就顺理成章了。

## DRM 显示子系统：最大的架构变化

### 旧 BSP 内核：Framebuffer 框架

在 NXP BSP 内核（以及早期的主线内核）中，i.MX6ULL 的 eLCDIF 控制器使用的是旧的 Framebuffer 驱动：

```
驱动文件: drivers/video/fbdev/mxsfb.c
配置项: CONFIG_FB_MXS
设备节点: /dev/fb0
```

设备树的写法是这样的：

```dts
&lcdif {
    display = <&display0>;    /* 指向下面的子节点 */
    status = "okay";

    display0: display@0 {
        bits-per-pixel = <16>;
        bus-width = <24>;

        display-timings {
            native-mode = <&timing0>;
            timing0: timing0 {
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
        };
    };
};
```

这种写法的核心是 `display = <&display0>` 属性，它直接在 lcdif 节点下面定义了一个 `display@0` 子节点，把所有时序参数都写在里面。

### 主线内核：DRM/KMS 框架

进入主线内核（5.x 以后逐步完成迁移），eLCDIF 的驱动已经迁移到 DRM 子系统：

```
驱动文件: drivers/gpu/drm/mxsfb/mxsfb_drv.c
配置项: CONFIG_DRM_MXSFB
设备节点: /dev/dri/card0, /dev/fb0（兼容层）
```

设备树的写法完全不同：

```dts
/* panel 节点独立于 lcdif 之外 */
panel: panel-dpi {
    compatible = "panel-dpi";
    backlight = <&backlight_display>;

    /* 屏幕物理尺寸（用于计算 DPI） */
    width-mm = <154>;
    height-mm = <86>;

    /* 时序参数写在 panel 里 */
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

    /* OF graph 连接：panel 输入端 → lcdif 输出端 */
    port {
        panel_in: endpoint {
            remote-endpoint = <&lcdif_out>;
        };
    };
};

&lcdif {
    status = "okay";

    /*
     * 关键：删除 imx6ul.dtsi 基础文件里遗留的 display 属性。
     * 不加这行会导致 DTB 编译时报 phandle_references 错误。
     */
    /delete-property/ display;

    /* 新式 OF graph 连接：lcdif 输出端 → panel 输入端 */
    port {
        lcdif_out: endpoint {
            remote-endpoint = <&panel_in>;
        };
    };
};
```

这种写法的核心是 OF graph（Open Firmware 图形框架），它把 panel 作为一个独立设备，通过 `port/endpoint` 的方式连接到 lcdif。这是内核标准的设备连接方式，不仅用于显示，还用于摄像头、网络等多个子系统。

### 为什么会有这种变化

旧 Framebuffer 框架的问题在于：

1. **功能有限**：不支持多个显示器、不支持硬件加速、不支持现代显示特性
2. **接口陈旧**：ioctl 接口不灵活，难以扩展
3. **架构混乱**：每个驱动都有自己的实现方式，不统一

DRM/KMS 框架解决了这些问题：

1. **统一架构**：所有显示驱动用同样的接口
2. **模式设置**：支持多个显示器、分辨率切换
3. **硬件加速**：与 GPU 驱动集成，支持 3D 加速
4. **用户空间接口**：通过 `/dev/dri/cardX` 提供现代化的接口

### 迁移时的常见报错

当你把 BSP 的设备树直接放到主线内核里，会看到这个报错：

```
[    1.964868] mxsfb 21c8000.lcdif: error -ENODEV: Cannot connect bridge
```

`-ENODEV` 的意思是"设备不存在"。具体来说，驱动在 probe 时调用 `drm_of_find_panel_or_bridge()` 想找下游的 panel 或 bridge，但设备树里用的是旧的 `display@0` 写法，找不到 `port` 节点，所以失败了。

解决方法就是按照上面的新写法重写设备树，这一点我们后面的章节会详细讲。

## 时钟驱动差异

i.MX6ULL 的时钟系统在 BSP 和主线内核之间也有变化，但这些变化主要体现在驱动代码层面，设备树接口基本兼容。

### BSP 内核的时钟驱动

BSP 内核的时钟驱动在 `drivers/clk/imx/clk-imx6ul.c`，包含了 i.MX6ULL 特有的时钟树定义。

### 主线内核的时钟驱动

主线内核的时钟驱动也在类似的位置，但代码结构经过重构，更加模块化。设备树里的时钟引用方式基本保持兼容：

```dts
assigned-clocks = <&clks IMX6UL_CLK_LCDIF_PRE_SEL>;
assigned-clock-parents = <&clks IMX6UL_CLK_PLL5_VIDEO_DIV>;
```

这些宏定义在 `include/dt-bindings/clock/imx6ul-clock.h` 中，BSP 和主线内核基本一致。

## 设备树 binding 变化

除了显示系统，其他外设的设备树 binding 也有一些变化：

### 以太网 PHY

BSP 内核可能这样写：

```dts
&fec1 {
    phy-mode = "rmii";
    phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;
    phy-reset-duration = <26>;
};
```

主线内核的写法更规范，要求明确 PHY 节点：

```dts
&fec1 {
    phy-mode = "rmii";
    phy-handle = <&ethphy0>;
};

mdio {
    ethphy0: ethernet-phy@2 {
        compatible = "ethernet-phy-id0022.1560";
        reg = <2>;
        micrel,led-mode = <1>;
        clocks = <&clks IMX6UL_CLK_ENET_REF>;
        clock-names = "rmii-ref";
    };
};
```

### 触摸屏

Goodix GT9147 触摸屏的驱动在主线内核里已经支持，但设备树写法有一些细节变化。BSP 内核可能用 `goodix,gt9147`，主线内核推荐用 `goodix,gt9xx` 作为 fallback：

```dts
gt9147: gt9147@5d {
    compatible = "goodix,gt9147", "goodix,gt9xx";
    reg = <0x5d>;
    interrupt-parent = <&gpio1>;
    interrupts = <9 0>;
    reset-gpios = <&gpio1 5 GPIO_ACTIVE_LOW>;
    interrupt-gpios = <&gpio1 9 GPIO_ACTIVE_LOW>;
    status = "okay";
};
```

## sim2 节点：主线内核缺失的节点

这是 i.MX6ULL 特有的一个问题。NXP BSP 内核里有 sim2（SIM 卡接口）的节点定义，但主线内核的 `imx6ul.dtsi` 基础文件里缺失了这个节点。

### 缺失的定义

主线内核的 `arch/arm/boot/dts/nxp/imx/imx6ul.dtsi` 里应该有但没有：

```dts
sim2: sim@021b4000 {
    compatible = "fsl,imx6ul-sim";
    reg = <0x021b4000 0x4000>;
    interrupts = <GIC_SPI 113 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&clks IMX6UL_CLK_SIM2>;
    clock-names = "sim";
    status = "disabled";
};
```

### 补充方法

移植时需要在板级设备树里手动添加这个节点，或者打补丁到 `imx6ul.dtsi`。这个项目的移植补丁已经包含了这处修改。

## 其他子系统的差异

### 音频系统

BSP 内核和主线内核的音频驱动架构基本一致，都使用 ALSA 框架。i.MX6ULL 的 SAI（Synchronous Audio Interface）驱动在主线内核里已经支持，设备树写法也兼容。

### 电源管理

BSP 内核可能有一些 NXP 特有的电源管理代码，比如特定的 DVFS 策略。主线内核的电源管理更加通用，可能不支持某些厂商定制的功能。对于大多数应用，主线内核的电源管理已经足够。

### 存储

eMMC/SD 卡的驱动在 BSP 和主线内核之间基本一致，都使用 `drivers/mmc/host/sdhci-esdhc-imx.c`。设备树写法也兼容。

## 配置项的变化

从 BSP 迁移到主线内核时，`.config` 文件也有一些重要变化：

### 必须开启的配置

```kconfig
# DRM 显示子系统
CONFIG_DRM=y
CONFIG_DRM_MXSFB=y

# Panel 驱动
CONFIG_DRM_PANEL=y
CONFIG_DRM_PANEL_SIMPLE=y

# 背光
CONFIG_BACKLIGHT_PWM=y
CONFIG_PWM_IMX27=y
```

### 应当关闭的配置

```kconfig
# 旧 Framebuffer 驱动，与 DRM 冲突
# CONFIG_FB_MXS is not set
```

如果同时开启 DRM 和旧 Framebuffer，两个驱动会争抢同一个设备，结果就是谁都不能正常工作。

## 下一章预告

到这里，你应该理解了 BSP 内核和主线内核的核心差异。最大的变化是显示系统从 Framebuffer 迁移到 DRM，设备树写法也完全变了。

下一篇文章，我们会详细讲解如何配置主线内核：

- 从 imx_v6_v7_defconfig 开始
- 必须开启的配置项
- 应当关闭的旧驱动
- 使用 make menuconfig 调整配置
- 配置模板的使用

有了正确的配置，下一步就是编译和烧录。我们一步步来。

---

**参考速查表**

| 子系统 | BSP 内核 | 主线内核 |
|--------|----------|----------|
| 显示驱动 | drivers/video/fbdev/mxsfb.c | drivers/gpu/drm/mxsfb/mxsfb_drv.c |
| 配置项 | CONFIG_FB_MXS | CONFIG_DRM_MXSFB |
| 设备节点 | /dev/fb0 | /dev/dri/card0, /dev/fb0 |
| DT 写法 | display = <&display0> | port/endpoint OF graph |
| Panel 时序 | display@0 子节点 | panel-dpi 独立节点 |

**延伸阅读**

- [DRM/KMS Documentation](https://www.kernel.org/doc/html/latest/gpu/drm-kms.html) - DRM 子系统文档
- [OF Graph Documentation](https://www.kernel.org/doc/html/latest/devicetree/bindings/graph.txt) - OF graph 规范
- [Linux Framebuffer vs DRM](https://blog.ffwll.ch/2013/02/drm-and-fb-.html) - 为什么从 Framebuffer 迁移到 DRM
