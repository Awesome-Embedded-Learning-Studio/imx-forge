---
title: 内核配置：读懂一份 defconfig
---

# 内核配置：读懂一份 defconfig

> 树在手（[取源码：从 stable 树拉下 v7.2.9](./03_source_fetch.md)），架构差异心里有数（[BSP vs 主线对比](./04_bsp_vs_mainline.md)），从这一篇起咱们在自己的树里回答一个实在问题：一份能点亮这块板子的 defconfig 从哪来。答案的骨架是三层：先铺一条 NXP 全家桶基线，再盘清楚基线离这块板差多远，最后把差的那一小撮亲手补上、收进一份属于您自己的配置文件。本篇读懂配置机制、铺好基线并盘清差距，也就是前两层；动手制作放在下一篇 [内核配置：动手做出自己的 defconfig](./06_defconfig_customize.md)，设备树与编译首启再往后，分别在 [设备树：从参考板改出 AES 板](./07_dts_writing.md) 与 [编译、外挂模块与 QEMU 首启验收](./08_dts_build_boot.md)。

::: tip 前置知识 · 环境
- 编译环境与工具链：[从零开始搭建主线内核编译环境](./02_env_setup.md)
- 主线源码树：[取源码：从 stable 树拉下 v7.2.9](./03_source_fetch.md)
- 架构差异背景：[BSP vs 主线对比](./04_bsp_vs_mainline.md)

从本篇起，咱们的 make 命令一律在源码树顶层 ~/experiments/linux-mainline 执行，但都带 O= 参数指向另一个目录 ~/experiments/linux-build：源码树只放源码，编译产物（.config、zImage、dtb）全部落进构建目录。这样有两个好处：源码树随时能 git status 出一个干净状态；您到 08 篇编外挂模块时还会看到，这个构建目录更是唯一的合法姿势。交叉工具链前缀 arm-none-linux-gnueabihf-（Arm GNU Toolchain 15.2.Rel1）。
:::

## 一、先把基线铺出来：一条命令

咱们先把要改的东西看清楚。内核源码同一份，编出来的镜像能小到几兆也能大到上百兆，行为更是天差地别，分水岭就一个文件：.config。它的本体是一张巨大的三选一问卷：=y 把驱动编进内核镜像，=m 编成独立的 .ko 模块，not set 就是不要。桌面发行版的思路是不确定的硬件全编成模块，插上什么现场加载什么；嵌入式板子反着来，盘子里就那么几样外设，该在的必须在。

铺基线是条命令的事：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx_v6_v7_defconfig
```

```text
#
# configuration written to .config
#
```

kbuild 到 arch/arm/configs/ 目录下找同名文件，找到了 imx_v6_v7_defconfig，把配置写进 O= 指定的构建目录里的 .config（您注意，不是源码树根，两目录制之后 .config 一直住在构建目录里）。这份基线什么规模？咱们拿两条计数命令找找感觉：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -c '^CONFIG' ~/experiments/linux-build/.config
grep -c 'is not set' ~/experiments/linux-build/.config
```

```text
2019
4136
```

2019 行生效的赋值，再算上 4136 行显式的 is not set，整张问卷六千多个决定。为什么挑 imx_v6_v7_defconfig 当底：它是 NXP 系 SoC 的通用基线，咱们这块阿尔法板的近亲 imx6ul-14x14-evk 就在它的覆盖范围里，CPU 频控、串口、uSDHC、DMA 这类 SoC 级配置九成能直接复用。文件本身实测 481 行，SOC_IMX6UL=y 就在第 27 行：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
wc -l arch/arm/configs/imx_v6_v7_defconfig
grep -n 'SOC_IMX6UL' arch/arm/configs/imx_v6_v7_defconfig
```

```text
481 arch/arm/configs/imx_v6_v7_defconfig
27:CONFIG_SOC_IMX6UL=y
```

::: warning 坑：O= 的路径要写绝对路径
O=~/experiments/linux-build 这种波浪号写法在 bash 里能展开，在 zsh 里不会——zsh 只展开词首的波浪号，跟在等号后面的不展开，make 就拿到一个字面的 ~/experiments/linux-build 当相对路径，跑到源码树里去找这个不存在的目录。O= 一律写全 /home/您/… 或 ~/… 前面不带等号直接 cd 过去的形式，别赌手气。
:::

## 二、make xxx_defconfig 那一下发生了什么

空口讲机制没意思，拿证据说话。CONFIG_FEC 是 i.MX 系列网卡驱动的开关，咱们在两个地方分别找它的下落：基线文件、最终产物。

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -c 'CONFIG_FEC=' arch/arm/configs/imx_v6_v7_defconfig
grep -n 'CONFIG_FEC=' ~/experiments/linux-build/.config
```

```text
0
1901:CONFIG_FEC=y
```

基线文件里一行都没有，.config 里却端端正正躺着 CONFIG_FEC=y。网卡驱动总不会是天上下来的吧？把两边一摆，defconfig 的机制就清楚了：这份基线文件并不是全量清单，它是一份精简差异，kbuild 拿它跟全量 Kconfig 合并——清单里写了的项按清单来，没写的项逐个回退到各 Kconfig 文件里声明的默认值。FEC 的谜底就埋在默认值里：drivers/net/ethernet/freescale/Kconfig 的 FEC 条目写着 default ARCH_MXC || SOC_IMX28 if ARM，而 ARCH_MXC=y 恰好由 imx_v6_v7_defconfig 提供。于是没有任何一方提名 FEC，kbuild 合并时照样替咱们把它开了。

这也解释了基线凭什么可以只有 481 行：咱们想想，全量六千多项要是都得手写，这份文件就没法维护了。

## 三、盘基线：原生配置离这块板有多远

基线铺好了，先别急着动手改，盘一盘它离这块板还差多少。咱们拿验收清单当探针，把板子的关键驱动逐个点名：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -E '^CONFIG_(SOC_IMX6UL|DRM_MXSFB|DRM_PANEL_SIMPLE|BACKLIGHT_PWM|PWM_IMX27|SND_SOC_WM8960|SND_IMX_SOC|FEC|MICREL_PHY|MMC_SDHCI_ESDHC_IMX|SERIAL_IMX_CONSOLE|CAN_FLEXCAN|SPI_IMX|TOUCHSCREEN_GOODIX|ROOT_NFS|USB_CHIPIDEA|RTC_DRV_SNVS|REGULATOR_FIXED_VOLTAGE)=' ~/experiments/linux-build/.config
```

```text
CONFIG_SOC_IMX6UL=y
CONFIG_FEC=y
CONFIG_MICREL_PHY=y
CONFIG_CAN_FLEXCAN=y
CONFIG_TOUCHSCREEN_GOODIX=y
CONFIG_SERIAL_IMX_CONSOLE=y
CONFIG_SPI_IMX=y
CONFIG_REGULATOR_FIXED_VOLTAGE=y
CONFIG_DRM_MXSFB=y
CONFIG_DRM_PANEL_SIMPLE=y
CONFIG_BACKLIGHT_PWM=y
CONFIG_SND_IMX_SOC=y
CONFIG_SND_SOC_WM8960=y
CONFIG_USB_CHIPIDEA=y
CONFIG_MMC_SDHCI_ESDHC_IMX=y
CONFIG_RTC_DRV_SNVS=y
CONFIG_PWM_IMX27=y
CONFIG_ROOT_NFS=y
```

十八条逐项命中，一个不缺。SoC 总开关、双网口的 FEC 与 KSZ8081 PHY、DRM 显示与背光、WM8960 codec、GT9147 触摸、ECSPI、FlexCAN、eMMC、串口控制台、SNVS RTC、NFS 根文件系统，全部是 =y。原生基线已经答完了九成的卷子，这是本篇最想让您带走的一个事实：**从零做板子的内核配置，大头是继承，不是重写。**

那差的一成在哪？咱们把音频链单独点名：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -E '^CONFIG_(IMX_SDMA|SND_SOC_FSL_ASOC_CARD|SND_SOC_FSL_SAI)=' ~/experiments/linux-build/.config
```

```text
CONFIG_SND_SOC_FSL_SAI=m
CONFIG_SND_SOC_FSL_ASOC_CARD=m
CONFIG_IMX_SDMA=m
```

三项全是 =m。这三个 =m 就是下一篇要处理的对象：它为什么是这块板子上真正的坑、怎么翻、翻了之后怎么收进文件，咱们到了那边逐个动手。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| make 报找不到 imx_v6_v7_defconfig | 拼写或目录不对，文件在 arch/arm/configs/ 下 | `ls arch/arm/configs/` 核对实名 |
| grep 某配置恒为空 | 搜错了符号实名（FLEXCAN、MMC_USDHC 都是错的） | 用 CAN_FLEXCAN、MMC_SDHCI_ESDHC_IMX |

## 继续学习

- 上一篇：[BSP vs 主线对比](./04_bsp_vs_mainline.md)
- 下一篇：[内核配置：动手做出自己的 defconfig](./06_defconfig_customize.md)，基线盘清了，下一篇动手把差的那一撮补上、收进自己的配置文件
- 跨卷深读：[DRM 显示系统移植](./09_display_drm.md)
