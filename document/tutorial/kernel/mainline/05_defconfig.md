---
title: 主线内核配置
---

# 主线内核配置：从 imx_v6_v7_defconfig 到 i.MX6ULL 专用配置

## 前言：配置不是一次性的事情

说实话，第一次配置主线内核的时候，我是真的有点懵。`make menuconfig` 打开之后，密密麻麻的配置选项，成千上万个。你根本不知道哪些是必须的，哪些是可选的，哪些开了会冲突。

这篇文章的目标是帮你理清思路：我们从 i.MX 系列的通用配置开始，逐步调整成适合 i.MX6ULL 主线移植的配置。这个项目已经提供了一个配置模板 `driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template`，我会解释每个关键配置的作用，让你知道为什么要这样配。

## 第一步——选择基础配置

主线内核为不同架构提供了基础配置文件（defconfig），对于 i.MX6ULL 这种 ARMv7 平台，我们用的是 `imx_v6_v7_defconfig`：

```bash
cd ~/linux-kernel/linux-mainline
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx_v6_v7_defconfig
```

这个配置文件在 `arch/arm/configs/imx_v6_v7_defconfig`，包含了 i.MX6 系列处理器的基本支持。但它是通用配置，需要针对 i.MX6ULL 做一些调整。

## 第二步——理解配置文件结构

内核配置本质上是一个巨大的键值对列表，每个配置项控制一个功能模块的编译方式：

- `=y`：编译进内核（vmlinux），启动时自动加载
- `=m`：编译成模块（.ko 文件），需要时手动加载
- `is not set`：不编译

对于嵌入式系统，通常把必需的功能编译进内核（`=y`），可选功能编译成模块（`=m`），不需要的功能关掉（`is not set`）。

## 第三步——必须开启的配置项

我们按照子系统分类，逐个看关键配置。

### 显示子系统（DRM）

这是主线内核和 BSP 内核差异最大的地方。你必须开启 DRM，关掉旧的 Framebuffer：

```kconfig
# DRM 子系统核心
CONFIG_DRM=y

# eLCDIF DRM 驱动
CONFIG_DRM_MXSFB=y

# Panel 驱动框架
CONFIG_DRM_PANEL=y
CONFIG_DRM_PANEL_BRIDGE=y

# panel-dpi 通用驱动（重要！）
CONFIG_DRM_PANEL_SIMPLE=y

# 背光支持
CONFIG_BACKLIGHT_CLASS_DEVICE=y
CONFIG_BACKLIGHT_PWM=y

# PWM 控制器（i.MX6ULL 用 PWM1 控制背光）
CONFIG_PWM=y
CONFIG_PWM_IMX27=y
```

如果你不开 `CONFIG_DRM_PANEL_SIMPLE`，后续设备树里的 `panel-dpi` 节点就不会被识别，LCD 不会亮。

### 应当关闭的旧驱动

为了避免冲突，必须关掉旧的 Framebuffer 驱动：

```kconfig
# CONFIG_FB_MXS is not set
# CONFIG_FB_MXC_SYNC_PANEL is not set
```

这两个配置如果开了，会和 DRM 驱动争抢设备，结果就是两个都不能正常工作。

### 网络支持

i.MX6ULL 有两个以太网控制器，需要开启 FEC 驱动和 PHY 驱动：

```kconfig
# FEC 以太网控制器
CONFIG_FEC=y

# PHY 驱动（KSZ8081 是 Micrel PHY）
CONFIG_NET_PHY=y
CONFIG_MICREL_PHY=y
CONFIG_AT803X_PHY=y
CONFIG_DP83867_PHY=y

# CAN 总线（如果需要）
CONFIG_CAN=y
CONFIG_CAN_FLEXCAN=y
```

### 触摸屏支持

Goodix GT9147 触摸屏驱动：

```kconfig
CONFIG_INPUT_TOUCHSCREEN=y
CONFIG_TOUCHSCREEN_GOODIX=y
```

### 其他外设

```kconfig
# 串口（调试必需）
CONFIG_SERIAL_IMX=y
CONFIG_SERIAL_IMX_CONSOLE=y

# I2C
CONFIG_I2C=y
CONFIG_I2C_IMX=y

# SPI
CONFIG_SPI=y
CONFIG_SPI_IMX=y

# SD/eMMC
CONFIG_MMC=y
CONFIG_MMC_SDHCI=y
CONFIG_MMC_SDHCI_ESDHC_IMX=y

# USB
CONFIG_USB=y
CONFIG_USB_CHIPIDEA=y
CONFIG_USB_MXS_PHY=y
```

## 第四步——使用配置模板

这个项目提供了一个完整的配置模板 `driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template`。构建脚本会用这个模板生成最终的 defconfig。

模板里有一个特殊的变量 `${FIRMWARE_DIR}`，用于指定固件文件的路径：

```kconfig
CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"
CONFIG_EXTRA_FIRMWARE_DIR="${FIRMWARE_DIR}"
```

构建脚本会用实际的路径替换这个变量：

```bash
# build-mainline-linux.sh 中的处理
FIRMWARE_DIR=$(realpath "${FIRMWARE_DIR}")
sed "s|\${FIRMWARE_DIR}|${FIRMWARE_DIR}|g" "${TEMPLATE_FILE}" > "${TARGET_FILE}"
```

## 第五步——调整配置

如果你需要修改配置，有两种方式：直接编辑 defconfig 文件，或者用 `make menuconfig`。

### 使用 menuconfig

`make menuconfig` 提供了一个图形化的配置界面，你可以搜索、导航、修改配置：

```bash
cd ~/linux-kernel/linux-mainline
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
```

常用操作：

- `/`：搜索配置项（比如搜索 "DRM_MXSFB"）
- 空格：切换 `y/m/n` 状态
- Enter：进入子菜单
- Esc Esc：返回上级菜单
- `/` 搜索后按数字键跳转到对应位置

修改完成后保存退出，会生成 `.config` 文件。

### 保存为 defconfig

如果你想把当前的配置保存为 defconfig：

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- savedefconfig
```

这会生成 `defconfig` 文件，你可以把它复制到 `arch/arm/configs/` 目录下，作为新的板级配置：

```bash
cp defconfig arch/arm/configs/imx6ull_mainline_defconfig
```

## 第六步——验证配置

配置完成后，验证一下关键配置是否正确：

```bash
# 检查 DRM 相关配置
grep -E "DRM|FB" .config

# 应该看到：
# CONFIG_DRM=y
# CONFIG_DRM_MXSFB=y
# CONFIG_DRM_PANEL_SIMPLE=y
# CONFIG_FB_MXS is not set  ← 这个必须是 not set

# 检查网络配置
grep -E "FEC|MICREL" .config

# 检查触摸屏配置
grep "GOODIX" .config
```

如果有关键配置缺失，回到 menuconfig 重新配置。

## 第七步——编译测试

配置验证通过后，可以尝试编译：

```bash
cd ~/linux-kernel/linux-mainline
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
```

如果配置有错误（比如依赖关系不对），编译时会报错。根据错误信息调整配置，然后重新编译。

## 常见问题排查

### 问题一：配置项找不到

如果你在 menuconfig 里找不到某个配置项，可能是因为：

1. **依赖不满足**：该配置依赖的其他配置没有开启
2. **架构不对**：该配置只支持特定架构
3. **名字改了**：新版本内核可能改了配置项名字

解决方法是搜索相关的依赖配置，先开启依赖，再找目标配置。

### 问题二：编译时提示冲突

比如同时开启了 DRM 和旧的 Framebuffer，会报错类似：

```
error: 'CONFIG_FB_MXS' conflicts with 'CONFIG_DRM_MXSFB'
```

解决方法是关掉冲突的配置，保留一个。

### 问题三：模块加载失败

如果某个功能编译成模块（`=m`），但启动时没有自动加载，可能需要在 initramfs 或 rootfs 里手动加载：

```bash
modprobe mxsfb
```

或者直接编译进内核（`=y`）。

## 完整的 i.MX6ULL 主线 defconfig

这个项目的移植补丁里包含了完整的 `imx_aes_mainline_defconfig`，你可以直接参考。下面列出一些关键配置的完整清单：

```kconfig
# 架构和 CPU
CONFIG_ARCH_MXC=y
CONFIG_SOC_IMX6UL=y
CONFIG_ARCH_MULTI_V6=y

# DRM 显示
CONFIG_DRM=y
CONFIG_DRM_MXSFB=y
CONFIG_DRM_PANEL=y
CONFIG_DRM_PANEL_SIMPLE=y
CONFIG_BACKLIGHT_PWM=y
CONFIG_PWM_IMX27=y

# 网络
CONFIG_FEC=y
CONFIG_MICREL_PHY=y
CONFIG_CAN_FLEXCAN=y

# 触摸屏
CONFIG_TOUCHSCREEN_GOODIX=y

# 存储
CONFIG_MMC_SDHCI_ESDHC_IMX=y

# 串口
CONFIG_SERIAL_IMX=y
CONFIG_SERIAL_IMX_CONSOLE=y
```

## 下一章预告

到这里，你应该知道了如何配置主线内核。配置文件准备好了，下一步就是设备树迁移。

下一篇文章，我们会详细讲解设备树迁移：

- BSP DTS vs 主线 DTS 的结构差异
- 如何重写 lcdif 和 panel 节点
- sim2 节点的添加方法
- OF graph 连接方式
- 编译和验证 DTB

设备树是硬件描述的核心，写错了驱动就 probe 不了。我们下一章见。

---

**参考命令速查**

```bash
# 从基础配置开始
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx_v6_v7_defconfig

# 打开 menuconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig

# 保存为 defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- savedefconfig
cp defconfig arch/arm/configs/imx6ull_mainline_defconfig

# 验证配置
grep -E "DRM|FB" .config

# 编译测试
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
```

**延伸阅读**

- [Kconfig Language Documentation](https://www.kernel.org/doc/html/latest/kbuild/kconfig-language.html) - Kconfig 配置语言文档
- [Linux Kernel Configuration Guide](https://www.kernel.org/doc/html/latest/admin-guide/README.html) - 内核配置指南
