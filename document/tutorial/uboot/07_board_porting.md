---
title: 七步造出咱们的板卡：从参考配置到 AES 入册
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 七步造出咱们的板卡：从参考配置到 AES 入册

> 上一篇定了路线，U-Boot 咱们只走 mainline v2026.10 单轨，整体流程图也铺完了。本篇动手，把 AES 这块上游不存在的板子按七步注册进源码树，每一步咱们都写清改什么、为什么改、怎么验证，唯一真相源是仓库里那份补丁，旧稿里 NXP 分支时代的说法凡跟补丁对不上的，一律照补丁修。设备树本体的逐节点展开归下一篇，本篇只把它们的名字登记进构建系统并完成主机侧验收。

敲 `make mx6ull_aes_emmc_defconfig` 之前，上游 configs/ 目录里躺着一千五百多份板卡配置，没有一份叫这个名字，board/ 目录里也没有它的落脚处，那 Kconfig 系统凭什么认它？笔者把 patches/uboot-mainline/charlies_board.patch 从头到尾读了一遍，这段 1839 行的补丁就是全部答案。目标名先进 SoC 的 Kconfig，板级目录挂上构建系统，头文件、镜像头配置、板级 C 代码、defconfig、设备树逐件补齐，七步走完，一块新板子就住进了源码树。咱们顺着补丁的 diff 顺序往下走，每一步都到源码树里核一遍。

## 一、在 mx6 的 Kconfig 里登记新板型

入口只有两处改动，都在 arch/arm/mach-imx/mx6/Kconfig 里，补丁的 diff 显示两处都是纯追加，夹在中间的官方目标（TARGET_MX6ULL_14X14_EVK、TARGET_MX6ULZ_SMM_M2）一行没动。头一处咱们插在 TARGET_MX6ULL_14X14_EVK 块后面，就这几行：

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

逐行看。`depends on MX6ULL` 是门槛，MX6ULL 本身是这个文件里 “i.MX6 SoC select” 那个 choice 的成员，咱们在 defconfig 里写 `CONFIG_MX6ULL=y` 等于在单选题里挑了 i.MX6ULL 这颗芯片，目标选项只在挑中它的时候才露面。`select` 是强制拉进来，被选中的选项没有讨价还价的余地。`BOARD_LATE_INIT` 对应第五节的 board_late_init：common/board_r.c 的初始化序列里，这条调用被 `#if CONFIG_IS_ENABLED(BOARD_LATE_INIT)` 包着，第五节那个函数全靠这行才有出场机会。`DM` 是驱动模型框架，GPIO、串口、网卡这些驱动都挂在它脚下。`DM_THERMAL` 撑着片内温度传感器，defconfig 里的 `CONFIG_IMX_THERMAL=y` 走的就是 drivers/thermal/imx_thermal.c 这条路。`IOMUX_LPSR` 服务 SNVS 域引脚：i.MX6ULL 的第二组 pad 挂在独立的 0x02290000 控制器上（imx6ull-aes.dtsi 里那行注释说的就是它），`&iomuxc_snvs` 名下那批以太网复位、热插拔检测引脚组全指望它。`imply CMD_DM` 只把 dm 命令设成默认，menuconfig 里随时可以关——这一点是 select 做不到的。

第二处追加在文件尾部那列 source 行里，mx6ullevk 之后多了一行 `source "board/nxp/mx6ull_aes_emmc/Kconfig"`，板级目录的 Kconfig 就靠这行进入配置树。漏了它会怎样？那个 TARGET 选项根本不存在，menuconfig 里翻不到，defconfig 里的赋值跟着落空。咱们拿 grep 到补丁上核对过，输出贴在这里：

```bash
# 主机 ~/imx-forge
grep -n "TARGET_MX6ULL_AES_EMMC\|checkboard" patches/uboot-mainline/charlies_board.patch | head -8
```

```text
819:+config TARGET_MX6ULL_AES_EMMC
845:+if TARGET_MX6ULL_AES_EMMC
1300:+int checkboard(void) {
1596:+CONFIG_TARGET_MX6ULL_AES_EMMC=y
```

四处命中把七步要动的文件串了起来：819 行是本节的目标块，845 行是板级目录 Kconfig 的包裹行，1300 行是第五节的署名函数，1596 行是第六节的 defconfig 开关，后面每一节都会回到这几行。旧稿在这一节还写了 `select IMX_MODULE_FUSE` 和 `select OF_SYSTEM_SETUP` 两行，笔者逐行对过补丁，这两行并不存在，本篇照补丁删去。

## 二、新建板级目录

板级目录起在 board/nxp/mx6ull_aes_emmc/，蓝本是官方的 board/nxp/mx6ul_14x14_evk/。咱们把两个目录各自 ls 了一遍，真实输出在这里：

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/board/nxp/mx6ul_14x14_evk
ls third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc
```

```text
Kconfig
MAINTAINERS
Makefile
mx6ul_14x14_evk.c
```

```text
Kconfig
MAINTAINERS
Makefile
imximage.cfg
imximage_lpddr2.cfg
mx6ull_aes_emmc.c
plugin.S
```

官方目录只带四件，AES 的目录是七件，多出来的三件（imximage.cfg、imximage_lpddr2.cfg、plugin.S）是镜像头配置那一组。逐件对照咱们列成一张表：

| 文件 | EVK 蓝本 | AES 新目录 | 咱们改了什么 |
|---|---|---|---|
| Kconfig | 只有 SYS_BOARD/SYS_VENDOR/SYS_CONFIG_NAME 三项 | 同三项，另加 IMX_CONFIG 与 TEXT_BASE | 挂上自家镜像头配置路径与链接地址 |
| MAINTAINERS | NXP 的 Peng Fan 维护 | CharlieChen 维护，S: Maintained | 换维护者，F 行列板级目录、头文件、defconfig 三个路径 |
| Makefile | `obj-y := mx6ul_14x14_evk.o` | `obj-y := mx6ull_aes_emmc.o` | 换编译对象 |
| 板级 C 代码 | 471 行，带 pfuze3000 PMIC 与大段引脚表 | 165 行 | 按板子实际用的外设裁剪，细节在第五节 |
| imximage.cfg | 不在这个官方目录里 | 120 行 | DDR3 那套 DCD 清单，第四节展开 |
| imximage_lpddr2.cfg | 不在这个官方目录里 | 125 行 | 换 LPDDR2 内存才启用的备用配置 |
| plugin.S | 不在这个官方目录里 | 263 行 | DDR 初始化插件的汇编版 |

官方目录不带这三件，不代表无处可学。隔壁 board/nxp/mx6ullevk/ 是带镜像头配置的另一个 EVK 板卡目录，它家 Kconfig 里就挂着 IMX_CONFIG。AES 的 Kconfig 咱们照这个样式写，全份贴出来也不过 17 行：

```text
if TARGET_MX6ULL_AES_EMMC

config SYS_BOARD
	default "mx6ull_aes_emmc"

config SYS_VENDOR
	default "nxp"

config SYS_CONFIG_NAME
	default "mx6ull_aes_emmc"

config IMX_CONFIG
	default "board/nxp/mx6ull_aes_emmc/imximage.cfg"

config TEXT_BASE
	default 0x87800000
endif
```

SYS_CONFIG_NAME 决定头文件叫什么（include/configs/mx6ull_aes_emmc.h），IMX_CONFIG 决定镜像头配置走哪份文件，TEXT_BASE 是链接地址。蓝本 mx6ul_14x14_evk 把 TEXT_BASE 放在 defconfig 里（configs/mx6ul_14x14_evk_defconfig 第 3 行写着 `CONFIG_TEXT_BASE=0x87800000`），AES 把它挪进板级 Kconfig，落点是同一个地址，两条路都通。那六行咱们照补丁抄进去就行，改动只在 M 行的名字与邮箱，加上三个 F 行把自家文件的路径报给社区。

## 三、板级头文件

include/configs/mx6ull_aes_emmc.h 共 142 行，咱们分三段读。头一段是外设基址：

```c
#define CFG_MXC_UART_BASE		UART1_BASE

#ifdef CONFIG_FSL_USDHC
#define CFG_SYS_FSL_ESDHC_ADDR	USDHC2_BASE_ADDR
#define CFG_SYS_FSL_USDHC_NUM	2
#endif
```

串口控制台落在 UART1 上，UART1_BASE 在 arch 头文件里解析成片内外设总线上的一个地址。两个 USDHC 控制器都开，环境变量缺省里 emmc_dev=1、sd_dev=0，编号 0 是 SD 卡槽，1 是 eMMC。这些宏跟 EVK 头文件是同款写法，笔者 grep 对照过，mx6ul_14x14_evk.h 里同样的 CFG_MXC_UART_BASE、CFG_SYS_FSL_ESDHC_ADDR 一行不差，数量上 EVK 的 USDHC_NUM 在条件编译里给出 1 或 2，AES 直接写死 2。

中段是环境变量缺省，这一节的大头。CFG_MFG_ENV_SETTINGS 开头有四行作者注释，笔者原样引来：

```c
// Notings: These places are we specified the
// bonus settings in uboot
// 	1. set the splashimage addr to boot the logo in uboot
//	2. set the ethernet addr to make the ethernet accessible everytime we remark one
```

注释说的两件事都在下面的字符串里。splashimage 给 Logo 备了加载地址，MFG 段里写 0x83800000，后面的 CFG_EXTRA_ENV_SETTINGS 又写了一份 0x8c000000。eth0addr、eth1addr、ethaddr 三个 MAC 缺省落在 b8:ae:1d:01:00:00、:04、:08 三支上。启动路径也备了好几条：mmcboot 走 FAT 分区取 zImage 与设备树，emmcbootaes 与 sdbootaes 用 ext4load 直接从各自分区的根目录取同名文件，netboot 走 dhcp 或 tftp，串口里手工 run 哪条都行。fdt_file 的缺省值咱们照补丁写成 imx6ull-aes.dtb，旧稿那份 imx6ull-14x14-evk-emmc.dtb 是 NXP 分支时代的名字，咱们在这棵树的 arch/arm/dts/ 里 ls 过，连对应的 dts 文件都不存在，不改就是一条死路。

尾段是物理内存图。PHYS_SDRAM 取 MMDC0_ARB_BASE_ADDR，arch 头文件里这个宏在 MX6UL/MX6ULL 的条件分支下是 0x80000000，设备树的 memory 节点也写着 `reg = <0x80000000 0x20000000>`，512 MiB DDR 从这里起。TEXT_BASE 是 0x87800000，跟 DDR 起址一减，0x07800000，正好 120 MiB，也就是说 U-Boot 本体被咱们链在低 120 MiB 之上的位置，让出来的这段空间给内核、设备树、initrd 与 Logo 这些搬运物落脚，谁也不压着谁。构建日志尾部的 hexdump 给了旁证，IVT 头偏移 0x04 的字读到 0x87800000，跟链接地址对上，这套判读法 03 章在 EVK 那张头上用过。

eMMC 的接线有一处咱们要照实交代。usdhc2 节点在 imx6ull-aes.dtsi 里配的是 pinctrl-names 与 pinctrl-0（指向 pinctrl_usdhc2 这组 4 位引脚），加上 non-removable、keep-power-in-suspend、wakeup-source 与 `status = "okay"`，bus-width 一个字没写，于是它按 SoC 基线继承 4 位总线。8 位引脚组 pinctrl_usdhc2_8bit 连同 100mhz、200mhz 两个变频组都在 dtsi 的 iomuxc 段里备好了，节点还没有引用它们，这是留给后续的扩展点。咱们拿 grep 到 dtsi 上核过：

```bash
# 主机 ~/imx-forge
grep -n "bus-width\|usdhc2" third_party/uboot-mainline/arch/arm/dts/imx6ull-aes.dtsi | head -6
```

```text
269:		bus-width = <24>;
314:		spi-rx-bus-width = <4>;
315:		spi-tx-bus-width = <1>;
398:&usdhc2 {
400:	pinctrl-0 = <&pinctrl_usdhc2>;
639:	pinctrl_usdhc2: usdhc2grp {
```

usdhc2 节点在 398 行，它引用的正是 639 行那组 4 位引脚。总线宽度的另一个去处是顶层 imx6ull-aes.dts 里那层覆盖（它把 8 位引脚组与 `bus-width = <8>` 盖上去），设备树文件之间的关系归下一篇细讲，本篇咱们只认 dtsi 基线。输出里 269 行的 `bus-width = <24>` 属于 LCD 接口，314、315 两行属于 QSPI flash，都跟 eMMC 无关，顺手说明免得误读。

## 四、imximage.cfg 与 DCD

imximage.cfg 是给 tools/mkimage 看的说明书，咱们把这份文件分三段看。头一段 `IMAGE_VERSION 2` 声明镜像版本。第二段 BOOT_FROM 是三岔口：定义了 `CONFIG_QSPI_BOOT` 走 qspi，定义了 `CONFIG_NOR_BOOT` 走 nor，两个都没定义就落到 sd。AES 从 eMMC 启动走的就是 sd 这条分支，镜像落在介质偏移 1 KiB 起的位置，这 1 KiB 的来历在 04 章的烧录核对里讲过。第三段是插件开关，`CONFIG_USE_IMXIMG_PLUGIN` 打开时走 PLUGIN 分支，第 33 行指向 board/nxp/mx6ull_aes_emmc/plugin.bin，起始地址 0x00907000。

没开插件时，BootROM 替咱们执行的初始化清单就来自下面的 DCD 段。DCD（Device Configuration Data，设备配置数据）是一串寄存器地址、宽度、值的三元组，BootROM 跳进 U-Boot 之前照单执行。AES 这份清单 61 条 DATA，开头 7 条写在 0x020c4068 到 0x020c4080，把 CCM 的七组时钟门全开。接下来一批 0x020E 开头的地址落在引脚控制器上，是 DDR 引脚的电气配置，plugin.S 里那套 ldr/str 与它们一一对应，偏移 0x4B4 正对着 DCD 里的 0x020E04B4。最后一批 0x021B 开头写在 MMDC 存储控制器上，是 DDR3 的时序与初始化序列，DDRC 与 PHY 的寄存器一个个喂到位。

::: warning 动 DCD 之前想清楚后果
DCD 是 BootROM 在 DDR 还没起来时执行的清单，时钟门、引脚电气、MMDC 时序全在里面。咱们手一滑改错一个值，后果是板子连串口都不会出字，因为要出串口字的那段代码自己就住在 DDR 里，DDR 没起来谁也跑不了。根因在于这份清单的执行者是最不聪明的 BootROM，它不会重试也不会报错，只会停在那儿。逐字段的深读归 boot-chain 扩展卷头一段（BootROM 与镜像格式），已经落成的文本是 [第一章那张地图](./01_what_is_uboot.md) 第一节，字段级的展开随那一卷成文补齐。
:::

AES 与参考板的 DDR 配置差异，咱们逐行 diff 过：把 AES 这 61 条 DATA 与 board/nxp/mx6ullevk/imximage.cfg 的 DATA 行并排比，60 条同值同序，唯一的增量是第 62 行那条挂在 `CONFIG_IMX_OPTEE` 条件里的 0x20e4024 写入。也就是说 DDR3 这套时序表是从 mx6ullevk 蓝本搬过来的，一个值没改。目录里另有一份 imximage_lpddr2.cfg，那是换 LPDDR2 内存才启用的备用配置，pad 值另有一套（同一个 0x020E04B4，它里面写 0x00080000，DDR3 版写 0x000C0000）。笔者对这份备用文件时还读到一处残留：它的第 34 行 PLUGIN 仍指向 board/freescale/mx6ullevk/plugin.bin，而 mainline 的板卡目录已经住在 board/nxp/ 下，这条旧路是从蓝本复制过来没改的。好在板级 Kconfig 把 IMX_CONFIG 指到了 imximage.cfg，DDR3 那份才是默认走的一条，这处残留不碍本轮构建，真要动 LPDDR2 之前得记得改它。

## 五、板级 C 代码的核心函数

板级 C 代码 165 行，蓝本同位置的 mx6ul_14x14_evk.c 有 471 行，差出来的三百多行主要是 PMIC（pfuze3000 的读写）与成片的引脚表。AES 板不用那颗电源芯片，引脚配置也全交给了设备树，所以裁得只剩实际要用的逻辑，文件头注释里那句 “keeps only what the AES board actually uses (dual FEC, QSPI, LCD)” 就是裁剪的口径。咱们把几个核心函数挨个过。

dram_init 只有两行：

```c
int dram_init(void) {
  gd->ram_size = imx_ddr_size();

  return 0;
}
```

内存大小不写死在板级代码里。imx_ddr_size() 去问 MMDC 控制器实际配置了多少，arch/arm/mach-imx/mmdc_size.c 的注释原话是 return size in bytes of DRAM according MMDC config，DCD 把 MMDC 配成多大，这里就报多大。将来换内存，咱们只改 DCD 那份清单，这个函数一个字不动。

board_early_init_f 是个空壳，返回 0 就完事，咱们在 defconfig 里把钩子挂上了（`CONFIG_BOARD_EARLY_INIT_F=y`），但 AES 在串口初始化之前确实无事可做。board_init 干三件事：

```c
int board_init(void) {
  /* Address of boot parameters */
  gd->bd->bi_boot_params = PHYS_SDRAM + 0x100;

#ifdef CONFIG_FEC_MXC
  setup_fec();
#endif

#ifdef CONFIG_FSL_QSPI
  board_qspi_init();
#endif

  return 0;
}
```

咱们挨个认。bi_boot_params 告诉内核启动参数放在 DDR 起址加 0x100 处。setup_fec() 给两颗以太网控制器配时钟：clrsetbits_le32 改 IOMUXC 的 gpr[1] 选时钟源，enable_fec_anatop_clock 给两路各开 50 MHz，board_phy_config 再给 PHY（Micrel KSZ8081，设备树里的 compatible 写 ethernet-phy-id0022.1560）补一组寄存器写入，0x1f 写 0x8190。board_qspi_init() 把 QSPI 时钟打开，引脚电气按设备树走，函数注释里 pads come from the device tree 一句原话。

board_late_init 咱们在第一节给它留过出场券，它在 core 初始化序列的末尾被调（就是第一节那个 `CONFIG_IS_ENABLED(BOARD_LATE_INIT)` 条件）。它把 sd1、sd2、qspi1 三个启动模式登记进 bmode 命令的表，再往环境里写 board_name=AES 与 board_rev=14X14，defconfig 里 `CONFIG_ENV_VARS_UBOOT_RUNTIME_CONFIG=y` 给 env_set 开了权限，最后调 setup_lcd() 打开 LCDIF 时钟、把 GPIO1_IO08 的背光拉高。checkboard 更简单：

```c
int checkboard(void) {
  puts("Awesome Embedded Studio Authored\n");
  return 0;
}
```

启动时串口里那行署名就从这里出来，补丁 1300 行的 grep 命中咱们在第一节贴过，源码树里同一段落在 board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c 的 154 行。

还有两个小函数值得点名。board_mmc_get_env_dev 直接返回 devno，环境变量落在哪块 MMC 上就跟着设备号走，defconfig 里 `CONFIG_ENV_MMC_DEVICE_INDEX=1` 对应 eMMC。board_quiesce_devices 是个空函数，注释却写得认真：bootm_final() 会在 dm_remove_devices_active() 之前调它，LCDIF 的时钟要等 mxs_video_remove() 把控制器停稳再关，提前在这里断掉时钟，驱动剩下的 MMIO 访问就不安全了，所以咱们什么都不做，让时钟多活一会儿。

## 六、defconfig 落定

新文件 configs/mx6ull_aes_emmc_defconfig 共 105 行，头一段是骨架，咱们摘几行关键的：

```text
CONFIG_ARM=y
CONFIG_ARCH_MX6=y
CONFIG_MX6ULL=y
CONFIG_TARGET_MX6ULL_AES_EMMC=y
CONFIG_DEFAULT_DEVICE_TREE="imx6ull-aes"
CONFIG_BOOTDELAY=-1
CONFIG_USE_BOOTCOMMAND=y
CONFIG_BOOTCOMMAND="echo Current do not autoboot"
```

TARGET 那行连着第一节登记的 Kconfig 块，DEFAULT_DEVICE_TREE 指到 imx6ull-aes，设备树文件在这里第一次挂进构建系统（名字在第三节 fdt_file 里露过面，编译验收在第七节）。BOOTDELAY 写成 -1，上电后 U-Boot 不倒计时、直接停在命令行，BOOTCOMMAND 也换成了一句 echo，自动启动这条路被咱们主动关掉，开发阶段停在提示符上比自动跑飞安全得多。

环境变量区的偏移是这份 defconfig 里最讲究的一行：

```text
# Keep the environment beyond the U-Boot image (including the built-in logo).
CONFIG_ENV_OFFSET=0x400000
CONFIG_ENV_SIZE=0x2000
```

注释自己把理由写了：让环境区落在 U-Boot 镜像（连同内嵌 Logo）之外。对照官方的 mx6ull_14x14_evk_defconfig，那份的 CONFIG_ENV_OFFSET 是 0xC0000，紧贴镜像尾。AES 板的镜像连 Logo 一起烧，头部占的空间比 EVK 大，环境区要是贴着镜像放，保存环境时就有把 Logo 盖掉的风险，挪到 0x400000（4 MiB）之后，咱们保存环境写的就是另一片区域，两边互不打扰。ENV_SIZE 0x2000（8 KiB）跟 EVK 一样，存储位置在 MMC 上，设备号由 CONFIG_ENV_MMC_DEVICE_INDEX 指到 1。

旧稿这一节让咱们复制 configs/mx6ull_14x14_evk_emmc_defconfig 当起点，笔者在 v2026.10 的 configs/ 里 ls 过，没有这个文件，只有 mx6ull_14x14_evk_defconfig 和一个 plugin 变体，所以 AES 的 105 行是按板子需求重新写的。剩下的行数里还有几处值得记住的选择：`CONFIG_DM_MDIO=y` 旁边挂着注释 `Both FECs share the MDIO bus; let DM manage its lifetime during OS handoff`（两颗 FEC 共用一条 MDIO 总线，交接内核时把总线的生命周期交给 DM 管），PHY 库选了 Micrel 的 KSZ8XXX，VIDEO_LOGO 与 SPLASH_SCREEN 给 Logo 留了入口，FASTBOOT 与 UUU 支持让烧录工具链照旧能用。

## 七、设备树登记与编译验收

设备树部分，补丁带两份新文件进 arch/arm/dts/：imx6ull-aes.dts（44 行）与 imx6ull-aes.dtsi（735 行）。节点怎么写归下一篇，本篇只管登记。惯例动作是往 arch/arm/dts/Makefile 里加一行编译目标，官方板卡就是这么办的，imx6ull-14x14-evk.dtb 等 i.MX6ULL 一类板卡列在 805 行附近。咱们 grep 过这棵树的 Makefile，imx6ull-aes.dtb 不在清单里，补丁也没带这一行，但构建照样把这份 dtb 编了出来，构建日志 1360 行写着 `DTC arch/arm/dts/imx6ull-aes.dtb`。原因在 dts/Makefile 的机制里：第 8 行把 DEVICE_TREE 直接取自 CONFIG_DEFAULT_DEVICE_TREE，第 36 行按 `arch/arm/dts/$(DEVICE_TREE).dtb` 定位，模式规则认文件名，不要求先进 dtb-y 清单。要不要把这行补进清单属于工程习惯（按清单批量编 dtb 的目标只认清单），咱们这轮没补，验收结果不受影响。

配置能不能被认出来，咱们真跑了一遍：

```bash
# 主机 ~/imx-forge
make -C third_party/uboot-mainline O=/tmp/uboot-batch6-aes ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- mx6ull_aes_emmc_defconfig 2>&1 | tail -5 && rm -rf /tmp/uboot-batch6-aes
```

```text
#
# configuration written to .config
#
make[1]: Leaving directory '/tmp/uboot-batch6-aes'
make: Leaving directory '/home/charliechen/imx-forge/third_party/uboot-mainline'
```

configuration written to .config 说明 Kconfig 把这 105 行完整解析成了配置，TARGET_MX6ULL_AES_EMMC、MX6ULL 这些符号都有了着落。咱们跑完随手删掉 O= 目录，这轮只验配置，不留中间产物。

产物尺寸引用的是 11 月 14 日 14:01 那轮构建的真实数字，咱们 grep 构建日志里的两个产物名：

```bash
# 主机 ~/imx-forge
grep -n "u-boot-dtb.imx\|u-boot.bin" /tmp/uboot-ref-build.log | tail -6
```

```text
643:-rw-r--r-- 1 charliechen charliechen  431144 Nov 14 14:01 /tmp/uboot-ref-evk/u-boot.bin
1364:  COPY    u-boot.bin
1366:  MKIMAGE u-boot-dtb.imx
1374:-rw-r--r-- 1 charliechen charliechen 1702912 Nov 14 14:01 /tmp/uboot-ref-aes/u-boot-dtb.imx
1375:-rw-r--r-- 1 charliechen charliechen     196 Nov 14 14:01 /tmp/uboot-ref-aes/u-boot-dtb.imx.log
1377:-rw-r--r-- 1 charliechen charliechen 1696688 Nov 14 14:01 /tmp/uboot-ref-aes/u-boot.bin
```

咱们把两个数放一起看：AES 的 u-boot-dtb.imx 是 1702912 字节，同轮日志 642 行里 EVK 的 u-boot-dtb.imx 只有 437248 字节，差出来的近四倍主要是 AES 的 defconfig 把 VIDEO、fastboot、USB 存储、EXT4 这些功能开齐了，EVK 那份精简得多。日志尾部还留着 AES imx 头的 64 字节 hexdump，偏移 0x04 的字读到 0x87800000，跟 TEXT_BASE 对上，与第三节推的内存图咬合。

到这儿，咱们为 AES 备下的材料就齐了：两份设备树共 779 行（44 加 735，wc 可查），105 行 defconfig，165 行板级 C 代码，外加 SoC Kconfig 里那 9 行登记。下一篇从 imx6ull-aes.dtsi 开讲，398 行那个 usdhc2 节点周围的世界，逐段读出来。

## 继续学习

- [设备树](./08_device_tree_aes.md)：本篇登记的两份设备树文件在那篇逐节点展开，imx6ull-aes.dtsi 是正主。
