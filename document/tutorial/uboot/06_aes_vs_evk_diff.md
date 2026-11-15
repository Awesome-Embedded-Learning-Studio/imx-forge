---
title: 净源码里没有咱们的板卡：官方参考配置逐行对账
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 净源码里没有咱们的板卡：官方参考配置逐行对账

> 上一篇的串口验收验的是官方参考板镜像的启动现场，本篇回答紧跟着冒出来的问题，就是咱们这块 AES 板的支持到底从哪来。净的官方源码里没有这块板子，AES 全家住在 `patches/uboot-mainline/charlies_board.patch` 一个文件里，是叠在官方参考配置上的纯增量改装。咱们核三遍：补丁清单数一遍，两份 defconfig 的差异逐行对，官方文件上的登记点挨个点。下一篇做第一次板卡适配时，拿的就是这份核过的底版。

## 一、先摆事实：净源码里 AES 在哪都找不到

咱们把地基核清楚，差异才有处安放。下面的命令读的是官方提交的内容：ls-tree 跟着 HEAD，看的是提交对象，不碰工作区，configs 与 board/nxp 两个目录各搜一遍 aes：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline ls-tree HEAD configs/ | grep -ci aes || echo HEAD无aes
git -C third_party/uboot-mainline ls-tree HEAD board/nxp/ | grep -i aes || echo HEAD的board-nxp目录无aes
```

```text
0
HEAD无aes
HEAD的board-nxp目录无aes
```

configs 收着全部板卡的编译配置，board/nxp 收着 NXP 系板子的板级代码，咱们在官方提交里把这两处各搜一遍 aes，命中都是零。也就是说官方 v2026.10 里，咱们这块板子连名字都不存在，板级目录、defconfig、设备树一样都不在。

那树里这些 AES 文件是谁放进去的？咱们数 staged 的改动，末行就是总数：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline diff --cached --stat | tail -3
```

```text
 configs/mx6ull_aes_emmc_defconfig             | 102 ++++
 include/configs/mx6ull_aes_emmc.h             | 143 +++++
 13 files changed, 1734 insertions(+)
```

13 files changed, 1734 insertions(+)，没有 deletions 一列——1734 行全是插入，官方文件一行没删。咱们把这 13 份分两类：11 份全新文件，设备树两份（imx6ull-aes.dts、imx6ull-aes.dtsi），板级目录 board/nxp/mx6ull_aes_emmc/ 一套七份，defconfig 与 include/configs/ 下的板级头文件各一份。被追加的官方文件只有两份，arch/arm/mach-imx/mx6/Kconfig 加 10 行，arch/arm/include/asm/arch-mx6/imx-regs.h 加 8 行。

这份名单与磁盘上补丁文件的自报家门对得齐吗？咱们让补丁自己数：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline apply --stat ../../patches/uboot-mainline/charlies_board.patch | tail -1
```

```text
13 files changed, 1744 insertions(+)
```

同样 13 份文件，行数多出 10，这桩出入 01 篇交代过：暂存的是上一代补丁，磁盘文件是新一代。数字咱们记在这里，第四节拿它收尾。

补丁跟手头这棵树咬合得紧不紧，咱们拿反向应用来验。--check 表示只做演练、不真改文件，--reverse 表示把补丁倒着剥：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline apply --check --reverse ../../patches/uboot-mainline/charlies_board.patch && echo 反向应用检查通过
```

```text
反向应用检查通过
```

检查通过的含义是：工作区里这 13 份文件的内容与补丁逐行咬合，整张补丁能完整剥下来，剥完正好回到官方 HEAD。补丁与当前工作区严格对齐，这就是咱们拿它当真相源的底气。

边角也有一处，是笔者换了个基准跑出来的。同一条命令加上 --cached，基准从工作区换成暂存区：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline apply --cached --check --reverse ../../patches/uboot-mainline/charlies_board.patch
```

```text
error: patch failed: include/configs/mx6ull_aes_emmc.h:1
error: include/configs/mx6ull_aes_emmc.h: patch does not apply
error: patch failed: configs/mx6ull_aes_emmc_defconfig:1
error: configs/mx6ull_aes_emmc_defconfig: patch does not apply
error: patch failed: board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c:1
error: board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c: patch does not apply
error: patch failed: arch/arm/dts/imx6ull-aes.dtsi:1
error: arch/arm/dts/imx6ull-aes.dtsi: patch does not apply
```

四个板级文件对不上，咱们别急着疑心补丁坏了：基准选错了，暂存区躺的是上一代快照，磁盘补丁与工作区是新一代。前面 1734 对 1744 的差，跟这里报错的四个文件，是同一桩事的两面。

::: warning 核补丁对齐，基准认工作区
后果是拿暂存区或旧快照当底版跑反向应用，会看到四条 patch does not apply，误判成补丁与源码失配，白绕一大圈。根因是 git apply 默认对着工作区检查，加 --cached 才查暂存区，而本仓库的暂存区是上一代快照，比磁盘补丁旧一代。核对的姿势咱们固定成一条：以当前工作区为基准，跑 apply --check --reverse。
:::

## 二、两份 defconfig 并排看

defconfig 是板卡编译配置的入口，一行一个 CONFIG 选项。本卷的两份都摆在 configs/ 下：参考板用 mx6ull_14x14_evk_defconfig，03 篇第一次编译编的就是它。AES 用 mx6ull_aes_emmc_defconfig。两份文件 70 行对 105 行，咱们拿 diff 并排，前 40 行的输出贴在这里：

```bash
# 主机 ~/imx-forge
diff third_party/uboot-mainline/configs/mx6ull_14x14_evk_defconfig third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig | head -40
```

```diff
3d2
< CONFIG_TEXT_BASE=0x87800000
8c7,8
< CONFIG_ENV_OFFSET=0xC0000
---
> # Keep the environment beyond the U-Boot image (including the built-in logo).
> CONFIG_ENV_OFFSET=0x400000
10c10
< CONFIG_TARGET_MX6ULL_14X14_EVK=y
---
> CONFIG_TARGET_MX6ULL_AES_EMMC=y
12c12
< CONFIG_DEFAULT_DEVICE_TREE="imx6ull-14x14-evk"
---
> CONFIG_DEFAULT_DEVICE_TREE="imx6ull-aes"
15a16
> CONFIG_BOOTDELAY=-1
17c18
< CONFIG_BOOTCOMMAND="run findfdt;mmc dev ${mmcdev}; if mmc rescan; then if run loadbootscript; then run bootscript; else if run loadimage; then run mmcboot; else run netboot; fi; fi; else run netboot; fi"
---
> CONFIG_BOOTCOMMAND="echo Current do not autoboot"
18a20,22
> # CONFIG_CONSOLE_MUX is not set
> CONFIG_SYS_CONSOLE_IS_IN_ENV=y
> CONFIG_BOARD_EARLY_INIT_F=y
21a26
> CONFIG_CRC32_VERIFY=y
25a31,32
> CONFIG_CMD_USB=y
> CONFIG_CMD_USB_MASS_STORAGE=y
27a35
> CONFIG_CMD_BMP=y
34a43
> CONFIG_EFI_PARTITION=y
44a54,59
> CONFIG_USB_FUNCTION_FASTBOOT=y
> CONFIG_FASTBOOT_BUF_ADDR=0x83800000
> CONFIG_FASTBOOT_BUF_SIZE=0x40000000
> CONFIG_FASTBOOT_FLASH=y
> CONFIG_FASTBOOT_UUU_SUPPORT=y
```

diff 的读法说一下：小于号开头的行是左边文件（EVK）独有，大于号开头的行是右边文件（AES）独有，3d2 这样的记号是行号加动作。尾部咱们再补一段：

```bash
# 主机 ~/imx-forge
diff third_party/uboot-mainline/configs/mx6ull_14x14_evk_defconfig third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig | tail -30
```

```diff
44a54,59
> CONFIG_USB_FUNCTION_FASTBOOT=y
> CONFIG_FASTBOOT_BUF_ADDR=0x83800000
> CONFIG_FASTBOOT_BUF_SIZE=0x40000000
> CONFIG_FASTBOOT_FLASH=y
> CONFIG_FASTBOOT_UUU_SUPPORT=y
> CONFIG_FASTBOOT_FLASH_MMC_DEV=1
47a63
> CONFIG_SUPPORT_EMMC_BOOT=y
51a68,69
> # Both FECs share the MDIO bus; let DM manage its lifetime during OS handoff.
> CONFIG_DM_MDIO=y
70a89,105
> CONFIG_USB=y
> CONFIG_USB_STORAGE=y
> CONFIG_USB_HOST_ETHER=y
> CONFIG_USB_ETHER_ASIX=y
> CONFIG_USB_GADGET=y
> CONFIG_USB_GADGET_MANUFACTURER="FSL"
> CONFIG_USB_GADGET_VENDOR_NUM=0x1fc9
> CONFIG_USB_GADGET_PRODUCT_NUM=0x0152
> CONFIG_CI_UDC=y
> CONFIG_VIDEO=y
> CONFIG_VIDEO_LOGO=y
> CONFIG_SYS_WHITE_ON_BLACK=y
> CONFIG_VIDEO_MXS=y
> CONFIG_SPLASH_SCREEN=y
> CONFIG_SPLASH_SCREEN_ALIGN=y
> CONFIG_BMP_24BPP=y
> CONFIG_BMP_32BPP=y
```

### 板卡身份与加载地址

三行改动管身份，咱们挨个看。CONFIG_TARGET_MX6ULL_14X14_EVK 换成 CONFIG_TARGET_MX6ULL_AES_EMMC，这是构建系统的登记名，第三节看它牵出的手续。CONFIG_DEFAULT_DEVICE_TREE 从 imx6ull-14x14-evk 换成 imx6ull-aes，设备树跟着换名。CONFIG_TEXT_BASE=0x87800000 这行在 AES 侧消失了，它没丢，搬进了板级 Kconfig（board/nxp/mx6ull_aes_emmc/Kconfig 里 default 0x87800000 那行）。加载地址一个字节没变，变的只是它住的位置。

### 环境与引导策略

注释原话 Keep the environment beyond the U-Boot image (including the built-in logo)，翻译过来是把环境扇区挪到镜像连同内嵌 Logo 的后面，数字从 0xC0000（768 KiB）挪到 0x400000（4 MiB）。EVK 敢把环境放在 768 KiB 处，靠的是官方镜像不带大图。咱们开了 VIDEO_LOGO，一张位图整个嵌进镜像，体积上去之后，768 KiB 那个位置就可能被镜像的尾巴压住——环境变量跟镜像一重叠，saveenv 写下去的位置就是镜像自己的身体，下次启动读回来的环境变量是烂的。

上电行为那两行，咱们放一起看：CONFIG_BOOTDELAY=-1 与 CONFIG_BOOTCOMMAND 那行 echo 是一对，上电不倒计时，不自动引导，日志打完停在提示符。EVK 那边是一条从 mmc rescan 到 mmcboot、netboot 的完整引导脚本，量产形态才需要它。开发期换成一句 echo，每改一轮环境变量都从干净的提示符重新开始。

咱们把配套的杂项也过一遍。控制台走向交给环境变量说了算，# CONFIG_CONSOLE_MUX is not set 与 CONFIG_SYS_CONSOLE_IS_IN_ENV 干的就是这件事。CONFIG_BOARD_EARLY_INIT_F 挂上早期初始化钩子，板级 C 文件里空着的 board_early_init_f 就是给它的。剩下几样顺手认一认：CONFIG_CRC32_VERIFY 给 crc32 命令添校验，CONFIG_EFI_PARTITION 打开 GPT 分区表，CONFIG_SUPPORT_EMMC_BOOT 认 eMMC 的 boot 分区。带注释的 CONFIG_DM_MDIO 交代两路 FEC 共用一条 MDIO 总线（CPU 读写 PHY 寄存器的两线管理总线），由驱动模型接管它的生命周期。

### USB 与 fastboot：把板子变成可烧写的目标

新增的十几行 USB 配置，咱们分两条线看。一条线让命令行用上 USB：CONFIG_CMD_USB、CONFIG_CMD_USB_MASS_STORAGE（ums 命令把 eMMC 借给电脑当 U 盘读写）、CONFIG_USB_STORAGE、CONFIG_USB_HOST_ETHER 配 CONFIG_USB_ETHER_ASIX（认 ASIX 芯片的 USB 网卡）。另一条线把板子变成受烧写端，CONFIG_USB_FUNCTION_FASTBOOT 打头，CONFIG_FASTBOOT_FLASH_MMC_DEV=1 指明烧写目标是编号 1 的 eMMC，CONFIG_FASTBOOT_UUU_SUPPORT 让 NXP 的 UUU 烧录工具对得上话，器件侧由 CONFIG_CI_UDC 驱动片上的 USB 器件控制器，设备号沿用 NXP 的 0x1fc9:0x0152。板级头文件里 emmcums 与 bootcmd_mfg 两个变量，就是 ums 的现成入口。

### 显示与开机画面

VIDEO 一组八行加 CONFIG_CMD_BMP，咱们连配套一起看。CONFIG_VIDEO 与 CONFIG_VIDEO_MXS 打开 eLCDIF（i.MX 片上的 LCD 控制器）的驱动，CONFIG_VIDEO_LOGO 把一张位图嵌进镜像当开机图（图是哪张，tools/Makefile 里 LOGO_BMP 一行写的是 tools/logos/denx.bmp）。CONFIG_SPLASH_SCREEN 与 CONFIG_SPLASH_SCREEN_ALIGN 管画面的摆放，CONFIG_BMP_24BPP 与 CONFIG_BMP_32BPP 让 bmp 命令认两种色深。这一组还有个配套动作在第三节：imx-regs.h 里补的 8 行宏，正是这套驱动要认的控制器基地址。

### MMC 能力两边都在，差异在接线与策略

咱们把 MMC 相关的行两边各摘一份对齐：CONFIG_CMD_MMC、CONFIG_FSL_USDHC、CONFIG_ENV_IS_IN_MMC、CONFIG_ENV_MMC_DEVICE_INDEX=1，两份文件里都有。控制器、驱动、命令、环境存放位置，能力层面两边一项不缺。差别挪去了别处。EVK 默认设备树里的 usdhc2 按官方 SD 卡变体的姿态接线，AES 的设备树把 usdhc2 收拾成 8 位线加 non-removable 的 eMMC 接法（imx6ull-aes.dts 的 usdhc2 节点用的是 8bit 系列 pinctrl，文件里的注释写明这段取自 imx6ull-14x14-evk-emmc.dts、简化了一层 include 层级）。接线的事归设备树，是 08 篇的正题。环境策略的事归 defconfig，本篇已经对完。

咱们把上面的差异收成一张对照表，逐格都能回 diff 输出里对：

| 差异点 | EVK（mx6ull_14x14_evk_defconfig） | AES（mx6ull_aes_emmc_defconfig） |
|--------|--------|--------|
| 登记名 | CONFIG_TARGET_MX6ULL_14X14_EVK | CONFIG_TARGET_MX6ULL_AES_EMMC |
| 默认设备树 | imx6ull-14x14-evk | imx6ull-aes |
| 环境扇区 | 0xC0000（768 KiB） | 0x400000（4 MiB，注释写明挪到镜像与内嵌 Logo 之后） |
| 上电行为 | 一条 mmc/net 自动引导脚本 | 不倒计时不引导，停在提示符 |
| USB 与烧写 | 无 | fastboot 器件模式一整套，含 UUU 支持，目标 eMMC |
| 显示与开机画面 | 无 | VIDEO_MXS 加 VIDEO_LOGO 加 splash 一整套 |
| MMC 能力 | CMD_MMC、FSL_USDHC、环境存 eMMC | 与 EVK 相同，差异在设备树接线与环境策略 |

## 三、三个共享清单的登记点：官方文件上怎么添咱们一笔

补丁对官方已有文件的全部动作，就是第一节数出的两处追加，mx6/Kconfig 加 10 行、imx-regs.h 加 8 行，零删除。加上设备树与板级头文件的登记手续，AES 在官方清单上的登记一共三处，咱们一处一处点过去。

### 板级目录进构建系统：mx6/Kconfig 的两处追加

```bash
# 主机 ~/imx-forge
grep -n "mx6ull_aes_emmc\|mx6ul_14x14_evk" third_party/uboot-mainline/arch/arm/mach-imx/mx6/Kconfig
```

```text
425:	bool "mx6ul_14x14_evk"
462:	bool "Support mx6ull_aes_emmc"
738:source "board/nxp/mx6ul_14x14_evk/Kconfig"
740:source "board/nxp/mx6ull_aes_emmc/Kconfig"
```

462 行是登记块的位置，补丁往 EVK 的 TARGET 块后面插进了九行，咱们贴在下面：

```text
config TARGET_MX6ULL_AES_EMMC
	bool "Support mx6ull_aes_emmc"
	depends on MX6ULL
	select BOARD_LATE_INIT
	select DM
	select DM_THERMAL
	select IOMUX_LPSR
	imply CMD_DM
```

740 行是另一处。source 清单是构建系统拉取各板级 Kconfig 的依据，咱们把 AES 这一行添在了里面。旁边的官方目录也顺手认一认：6UL 系的两块 EVK（14x14 与 9x9）共用 board/nxp/mx6ul_14x14_evk 这份目录，名字比 6ULL 少一个 L。咱们参考板对着的那块 6ULL EVK，官方单独开了 mx6ullevk 这份目录，739 行登记的就是它，SYS_CONFIG_NAME 落在 include/configs/mx6ullevk.h（上面的 grep 只搜了咱们两个名字，输出里看不到 739 这一行，别把它跟 mx6ul_14x14_evk 认成同一份）。咱们给 AES 板单独开了 mx6ull_aes_emmc 这份目录，登记行插在官方 mx6ullevk（739 行）的后面，跟官方的板子互不纠缠。

### 设备树的登记：dts/Makefile 一行没动

不少移植教程会教咱们往 arch/arm/dts/Makefile 的 dtb 清单里添一行，把设备树挂到目标板的开关下面。笔者照这个思路去核这棵树：

```bash
# 主机 ~/imx-forge
grep -n "aes" third_party/uboot-mainline/arch/arm/dts/Makefile || echo dts-Makefile里没有aes
```

```text
dts-Makefile里没有aes
```

零命中，咱们反而省了一道手续：这代 U-Boot 要编哪份设备树，CONFIG_DEFAULT_DEVICE_TREE 一行说了算。刚 grep 的 arch/arm/dts/Makefile 只管列 dtb 清单，定名字的活住在仓库顶层的 dts/Makefile，它写着 `DEVICE_TREE ?= $(CONFIG_DEFAULT_DEVICE_TREE:"%"=%)`，构建时拿这个名字到 arch/arm/dts/ 下找同名源文件，编出对应的 .dtb。第二节 diff 里设备树换名的那行，就是设备树的全部登记手续，补丁要新增的只有 dts 文件本身。imx6ull-aes.dts 的开头咱们也核过：

```bash
# 主机 ~/imx-forge
head -10 third_party/uboot-mainline/arch/arm/dts/imx6ull-aes.dts
```

```text
// SPDX-License-Identifier: (GPL-2.0 OR MIT)
//
// Copyright (C) 2016 Freescale Semiconductor, Inc.

/dts-v1/;

#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"
#include "imx6ull-14x14-evk-u-boot.dtsi"

```

咱们回头数这十行：开头是 SPDX 版权注释与 /dts-v1/ 版本声明，正文从第 7 到 9 行的三行 include 起步，芯片级 imx6ull.dtsi、板级 imx6ull-aes.dtsi、官方 EVK 的 U-Boot 侧配置 imx6ull-14x14-evk-u-boot.dtsi 原样借来。往下几行的 model 字符串写着 Awesome Embedded Studio，AES 这个名字的出处就在这里，01 篇讲过来历，不再展开。

### 宏与头文件：两处登记手续

imx-regs.h 里那 8 行，咱们看它补的是什么。VIDEO_MXS 打开的显示驱动 mxsfb.c 认 MXS_LCDIF_BASE 这个宏，别的 SoC 在各自的架构头文件里定义过它，6UL 与 6ULL 的头文件恰好缺着，补丁照官方的条件编译样式补上：

```c
#if (defined(CONFIG_MX6UL) || defined(CONFIG_MX6ULL))
/*
 * Base address expected by drivers/video/mxsfb.c (VIDEO_MXS). The mx6ul(l)
 * eLCDIF register layout matches the one the driver implements; other SoCs
 * define this macro in their own arch headers.
 */
#define MXS_LCDIF_BASE              MX6ULL_LCDIF1_BASE_ADDR
#endif
```

板级头文件的登记手续，咱们到构建脚本里找。板级 Kconfig 里 SYS_CONFIG_NAME 的 default 写着 mx6ull_aes_emmc，scripts/Makefile.autoconf 照这个名字生成一行 #include <configs/mx6ull_aes_emmc.h>，环境变量脚本（emmcbootaes、sdbootaes、splashimage，还有两组网卡的硬件地址）全住在这份头文件里，逐句讲解留给后面环境变量与 bootcmd 的篇幅。

官方文件原样保留意味着什么，咱们拿状态清单照一遍：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline status --porcelain
```

```text
A  arch/arm/dts/imx6ull-aes.dts
AM arch/arm/dts/imx6ull-aes.dtsi
M  arch/arm/include/asm/arch-mx6/imx-regs.h
M  arch/arm/mach-imx/mx6/Kconfig
A  board/nxp/mx6ull_aes_emmc/Kconfig
A  board/nxp/mx6ull_aes_emmc/MAINTAINERS
A  board/nxp/mx6ull_aes_emmc/Makefile
A  board/nxp/mx6ull_aes_emmc/imximage.cfg
A  board/nxp/mx6ull_aes_emmc/imximage_lpddr2.cfg
AM board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c
A  board/nxp/mx6ull_aes_emmc/plugin.S
AM configs/mx6ull_aes_emmc_defconfig
AM include/configs/mx6ull_aes_emmc.h
 M tools/logos/denx.bmp
```

名单里的文件全部围着 AES 转，参考板的 defconfig 与设备树一个都不在。第二列的 M 表示暂存之后工作区又过了一轮改动，那层出入第一节交代过。名单末行的 denx.bmp，第四节专门说它。这份清单说明的事照实写：参考板那条路随时能走，make mx6ull_14x14_evk_defconfig 就能编一份官方参考镜像出来当对照。咱们把板子挂在补丁与它新增的文件名下，官方源码没有被污染，升版本时核一遍补丁能否重新应用，迁移的功课就做完了。

## 四、旧口径的退役与补丁纪律

01 篇第三节定的口径，咱们这里回收一遍：本卷只用官方 mainline，停在 v2026.10 标签上，NXP 的 uboot-imx 分支不采用。本篇补上这个口径的另一半，单轨净源码加一个补丁文件，就是 AES 板卡支持的完整家当。补丁里的板级 C 文件自己把来历写明白了，注释原话是 Ported from the NXP lf vendor tree to upstream U-Boot，紧跟着一句 the board file keeps only what the AES board actually uses (dual FEC, QSPI, LCD)。注释里那棵 lf vendor tree，指的就是 uboot-imx 仓库里 lf- 开头的那批 NXP 发布分支，移植当时参照过它，发布形态里却没有它的位置，板级代码只留真用得着的几样。

纪律跟着形态走，咱们把正反两条路都摆出来。正路是进子模块开分支动手，改完用 patch_maker 重新生成补丁，补丁文件住 patches/ 目录随主仓库提交，build 卷的 Patch 工作流实战指南写的就是这条路。反着走的下场也说得清楚：直接改子模块树而不回补丁的改动，风险全在 reset 这一步，CI 与 release 构建子模块时按提交重建树，工作区里那笔改动不在任何提交里，也不在补丁名单里，重建出来的树里就没有它。

活例子现在就有一个。tools/logos/denx.bmp 是 VIDEO_LOGO 嵌进镜像的那张图，tools/Makefile 里 LOGO_BMP 一行写明了它。咱们看看它在官方提交与工作区里各是多大：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline show HEAD:tools/logos/denx.bmp | wc -c
wc -c < third_party/uboot-mainline/tools/logos/denx.bmp
```

```text
15538
1152054
```

咱们把两个数摆在一起看。官方提交里 15538 字节，工作区里换成了 1152054 字节，后者是 54 字节的 BMP 头加 800×480×3 字节的像素数据，正好一张 800×480 的 24 位色位图。这笔改动伺候的是第二节那组 VIDEO_LOGO 配置，嵌进镜像的开机图就是它。环境扇区挪去 4 MiB 跟它也有关系，镜像带上大图之后，768 KiB 的老位置不够放了。可它不在补丁的 13 份名单里，也没进暂存区，如今只活在工作区。哪天 reset 按提交重建子模块，这张图回到 DENX 的原版，开机图跟着变回去。

::: warning 不进补丁的改动，reset 之后就没了
后果是直接改子模块树而补丁没带上它，CI 或 release 做 reset 重建之后改动无声消失，编译照样能过，板子上的现象却对不上号，排查时两头都拢不到一起。根因是子模块树对上游按提交重建，工作区里未提交、补丁里未收录的改动不在重建结果里。咱们防它只有一个法子：改动落回补丁，patch_maker 重新生成，内容进 patches/ 下的补丁文件。
:::

咱们收个数字上的尾。暂存区 stat 的末行是 13 files changed, 1734 insertions(+)，磁盘补丁自己的 stat 末行是 13 files changed, 1744 insertions(+)。哪天两行数字追平了，就说明新一代补丁生成过、暂存区跟了上来。本篇全部核对认的基准，在那之前都是工作区。

## 继续学习

- [从0开始认识 U-Boot：一块 i.MX6ULL 上电后的事](./01_what_is_uboot.md)：mainline 单轨口径的正本，第四节回收的那段在它的第三节。
- [七步造出咱们的板卡](./07_board_porting.md)：下一篇，Kconfig 系统与第一次板卡适配，动的就是本篇核过名单里的文件。
- [设备树](./08_device_tree_aes.md)：usdhc2 接线与设备树换名的正题，第二节留给它的那一半。
- [Patch 工作流实战指南](../build/02_patch_workflow_practice.md)：补丁生成与应用的完整流程，第四节纪律的实操版。
