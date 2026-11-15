---
title: SPL 旁栏：别的平台为什么多一层
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# SPL 旁栏：别的平台为什么多一层

> Boot ROM 那三篇把咱们这条启动链讲成了一条直线：ROM 认镜像、替咱们执行初始化清单、把完整 U-Boot 装进 DDR。可翻开别家板子的资料，多半会先冒出来一个 MLO 或者 u-boot-spl.bin，链条凭空多出一层。本篇兑现链接地址那篇开头立的对照牌，讲清楚这层叫 SPL 的东西是什么、哪些平台才需要它、它跟完整 U-Boot 怎么分工，末了把本卷为什么不写 SPL 实操交代明白。旁栏读完，咱们照旧回到正篇那条两级链上。

## 一、什么是 SPL（Secondary Program Loader）

咱们这条链上从来没有 SPL 这个角色，别家的资料里它却是常客。全名 Secondary Program Loader，次级程序加载器，名字里那个 secondary 说的就是它的处境：排在 Boot ROM 后面、完整 U-Boot 前面，当第二棒。它要接的问题，咱们头一篇就见过：Boot ROM 只会从介质上按固定偏移读一小块固定大小的裸数据，搬进片上 SRAM 就交棒，读文件系统、管 NAND 坏块、认网口协议这些事它一概不会，DDR 的初始化也只认写死在镜像里的清单。介质一复杂，或者芯片压根没有 DCD 这类清单机制，ROM 就交不下去了。SPL 垫在中间——自己小到塞得进片上 SRAM，进门先把 DDR 张罗活，再从介质把完整 U-Boot 装进 DDR，跳过去。链条从两级变三级，ROM 交给 SPL，SPL 交给完整 U-Boot。

这套机制在咱们这棵树里住得清清楚楚，ls 一下。

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/common/spl/ | head -8
ls third_party/uboot-mainline/common/spl/ | wc -l
```

```text
Kconfig
Kconfig.nxp
Kconfig.tpl
Kconfig.vpl
Makefile
spl.c
spl_atf.c
spl_blk_fs.c
36
```

框架本体 spl.c 就在咱们刚列出来的这份清单里，每种介质各配一个加载器，spl_mmc.c 管 MMC，spl_nand.c 管 NAND，spl_net.c 管网口，一路排下去，36 个文件把各种介质收齐了。顶层 Makefile 第 1226 行写着 `INPUTS-$(CONFIG_SPL) += spl/u-boot-spl.bin`，主线构建出来的 SPL 产物就叫这个名字。还有一层垫法值得咱们知道：SPL 之前还能再垫 TPL（Tertiary Program Loader），ROM 交给 TPL，TPL 把 SPL 张罗进来，SPL 再交给完整 U-Boot，树内 doc/develop/init.rst 给的顺序是 TPL->VPL->SPL->U-Boot proper，用在连 SPL 都装不下的场合，common/spl/Kconfig.tpl 为它备着选项。顶层 Makefile 第 816 行把 u-boot.cfg、spl/u-boot.cfg、tpl/u-boot.cfg、vpl/u-boot.cfg（这一档是 VPL，Verifying Program Loader，排在 TPL 之后、SPL 之前的验证加载器）并排写在同一行，这几档共用一套构建路数。

产物名咱们在资料里最常见的是两个。u-boot-spl.bin 是主线构建的正式产物——上面那行 Makefile 就是它的出处。MLO 是 TI 平台的惯用叫法，顶层 Makefile 第 2553 行的清理清单里它跟 u-boot*、SPL、System.map 并排露过一面，这层来历算笔者带进来的常识，树里能指认的就这一面。名字怎么叫各有各的来历，角色都一样：小的那份交给 ROM，大的那份交给 SPL。

## 二、哪些平台走这条路

咱们拿探针把自己的地盘查清楚。

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/spl/ | head -8
ls third_party/uboot-mainline/spl/Makefile
```

```text
ls: cannot access 'third_party/uboot-mainline/spl/': No such file or directory
ls: cannot access 'third_party/uboot-mainline/spl/Makefile': No such file or directory
```

两个 ls 都报 cannot access，咱们翻遍顶层也找不到 spl/ 这个目录。这份报错本身没有冤枉谁，第四节有一段专门交代它为什么不能当证据使。

```bash
# 主机 ~/imx-forge
grep -rn "CONFIG_SPL" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig third_party/uboot-mainline/configs/mx6ull_14x14_evk_defconfig || echo 两配置均无 SPL
```

```text
third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig:102:CONFIG_SPLASH_SCREEN=y
third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig:103:CONFIG_SPLASH_SCREEN_ALIGN=y
```

grep 命中的两行跟 SPL 没有关系，咱们把两行读细一点：CONFIG_SPLASH_SCREEN 是开机展示画面的开关，符号名恰好以 CONFIG_SPL 打头，被这个不带词边界的 grep 一把抓了进来。命中非零，`||` 后面那句 echo 两配置均无 SPL 就没轮到跑。照实说，两份 defconfig 里真正的 SPL 开关一个都没有。

::: warning 别拿 grep CONFIG_SPL 的命中行当 SPL 开关读
后果是认错链路：照着命中行以为板子编了 SPL，跑去产物目录找 MLO 或 u-boot-spl.bin，一个都没有，白折腾一圈。根因是 CONFIG_SPL 这个串恰好是 CONFIG_SPLASH_SCREEN 的开头，不带词边界的 grep 把两码事的符号混进同一份名单。解法是换 `grep -w "CONFIG_SPL"` 查开关本身，笔者替咱们试过，两份 defconfig 上它一行都不命中，退出码 1。
:::

咱们这块 6ULL 为什么用不着 SPL，Boot ROM 那三篇已经把底气备齐了。咱们在第一篇看过 ROM 只按扇区读介质开头的裸区，第二篇的 IVT 是它认镜像的格式，第三篇的 DCD 是它替咱们执行的 DDR 初始化清单。plugin 那条备胎路把 DDR 前置换成一小段可执行代码，ROM 搬 64 KiB 进 OCRAM，插件把 DDR 带活，ROM 再把完整镜像搬进 DDR。整条链上从头到尾只有两个角色，Boot ROM 与完整 U-Boot，插不进第三个。头一篇还留过一句：有的方案垫一层 SPL，本仓库这条链没有垫。本篇就是那句话的展开。

机制上需要 SPL 的情况咱们数一数。介质驱动复杂算一类，NAND 的坏块与纠错、FAT 文件系统、网口协议都要真驱动才读得动，ROM 里塞不下，common/spl/ 那份清单里每种介质一个文件就是给它们备的。BootROM 不懂 DDR 是另一类，i.MX 家族好歹有 DCD 这类清单机制，别家未必有，树里的文档 doc/SPL/README.omap3 把 OMAP3 的内存地图摊开给咱们看：SPL 的代码与栈挤在 SRAM 的 0x40200800 到 0x4020FFFC，BSS 与 malloc 池排进 DDR，底下还跟着一句硬话，DDR1 里那些区段在 s_init() 完成之前不能用。镜像尺寸受限最要命，咱们编出的完整 u-boot 有 7,041,816 字节——片上 SRAM 通常几十 KiB 到一两百 KiB，塞不下，common/spl/Kconfig 给 SPL_MAX_SIZE 排的默认值多数在几十 KiB 一档，咱们这条 MX6ULL 支是 0x10000（64 KiB），也有上到一两百 KiB 的档，最高的给到 0x30000（192 KiB），超出直接报链接错误。

咱们拿真配置对照一把，TI 的 AM335x 走的就是这条路。

```bash
# 主机 ~/imx-forge
grep -n "CONFIG_SPL" third_party/uboot-mainline/configs/am335x_evm_defconfig | head -12
```

```text
8:CONFIG_SPL_ETH=y
9:CONFIG_SPL_FS_LOAD_PAYLOAD_NAME="u-boot.img"
10:CONFIG_SPL_MUSB_NEW=y
11:CONFIG_SPL_NAND_DRIVERS=y
12:CONFIG_SPL_NAND_ECC=y
13:CONFIG_SPL_NAND_BASE=y
14:CONFIG_SPL_NET=y
15:CONFIG_SPL_NET_VCI_STRING="AM335x U-Boot SPL"
16:CONFIG_SPL_OS_BOOT=y
18:CONFIG_SPL_FALCON_BOOT_MMCSD=y
28:CONFIG_SPL_ENV_IS_NOWHERE=y
47:CONFIG_SPL_DM_USB_GADGET=y
```

同一块板子的文档 doc/SPL/README.am335x-network 把网络启动讲得更直白，咱们对一遍：Boot ROM 的加载器（文档里叫 RBL）和 SPL 在 BOOTP 里各自报不同的身份标识，RBL 只收一份裸的 SPL 镜像（u-boot-spl-restore.bin），SPL 起来之后再取完整的 U-Boot 镜像。defconfig 第 15 行那个 `CONFIG_SPL_NET_VCI_STRING="AM335x U-Boot SPL"`，跟文档里让 DHCP 服务器区分两级加载器的字符串一字不差。

哪些情况要垫层、两级怎么分工，咱们拢成一张表。

| 对比项 | 咱们的 6ULL 路线 | 走 SPL 的平台 |
|---|---|---|
| DDR 由谁带活 | Boot ROM 照 DCD 清单或 plugin 执行 | SPL 的 board_init_f |
| ROM 之后的第一段代码 | 完整 U-Boot，直接进 DDR | SPL，几十 KiB，住片上 SRAM |
| 介质怎么读 | ROM 只按固定偏移搬裸区 | SPL 自带介质驱动去取下一棒 |
| 完整 U-Boot 的角色 | 第二棒，也是最后一棒 | 第三棒，被 SPL 装进 DDR |

至于别家 BootROM 到底认什么格式、读哪个偏移、给多长的搬运窗口，那是各芯片参考手册的地盘，笔者不在这篇里替别家的手册代言，树内可查的就是 doc/SPL/ 下这几份文档。

咱们这块芯片所在的 MX6 家族自己也备着一整套 SPL 默认值，只等哪块板真去走这条路，咱们把它们捞出来看。

```bash
# 主机 ~/imx-forge
grep -n "default 0x00908000\|default 0x91ffb8\|default 0x88200000\|default 0x100000 if ARCH_MX6\|default 0x10000 if ARCH_MX6" third_party/uboot-mainline/common/spl/Kconfig
```

```text
74:	default 0x10000 if ARCH_MX6 && !MX6_OCRAM_256KB
113:	default 0x88200000 if (ARCH_MX6 && (MX6SX || MX6SL || MX6UL || MX6ULL)) || ARCH_MX7
150:	default 0x100000 if ARCH_MX6 || RISCV
269:	default 0x00908000 if ARCH_MX6
424:	default 0x91ffb8 if ARCH_MX6 && !MX6_OCRAM_256KB
```

咱们这块芯片 OCRAM 是 128 KiB，落不进 MX6_OCRAM_256KB 那一支，咱们按这份默认值对号入座：代码从 SPL_TEXT_BASE 排的 0x00908000 跑起，栈顶落在 SPL_STACK 给的 0x91ffb8，BSS 起点 0x88200000 归 SPL_BSS_START_ADDR 管，长度上限 0x100000 归 SPL_BSS_MAX_SIZE 管。头两个数都在 OCRAM 里。0x88200000 这个起点落在 DDR 区间，顶格的 0x100000 是个尺寸上限，不是地址。BSS 排在 DDR 意味着 SPL 前半程还动不了它，先后的讲究下一节展开。

## 三、SPL 与完整 U-Boot 的分工

### 各平台自己写的精简 board_init_f

board_init_f 这个名字两边都叫，干的活完全两样，咱们把所有定义抓出来看。

```bash
# 主机 ~/imx-forge
grep -rn "void board_init_f" third_party/uboot-mainline/common/ third_party/uboot-mainline/arch/arm/ | head -6
```

```text
third_party/uboot-mainline/common/board_f.c:1073:void board_init_f(ulong boot_flags)
third_party/uboot-mainline/common/board_f.c:1116:void board_init_f_r(void)
third_party/uboot-mainline/common/init/board_init.c:31:__weak void board_init_f_init_stack_protection_addr(ulong base)
third_party/uboot-mainline/common/init/board_init.c:45:__weak void board_init_f_init_stack_protection(void)
third_party/uboot-mainline/common/init/board_init.c:137:void board_init_f_init_reserve(ulong base)
third_party/uboot-mainline/arch/arm/mach-mvebu/spl.c:343:void board_init_f(ulong dummy)
```

common/board_f.c 里那个是完整 U-Boot 的，链接地址那篇咱们跟着它排过座次：早期堆、gd、搬家目的地全在它手里。往后翻，mvebu、zynqmp、stm32mp1 各有一个 `void board_init_f(ulong dummy)`，全住在各自平台的 spl.c 里。挑 ZynqMP 的翻开看有多精简。

```bash
# 主机 ~/imx-forge
sed -n '29,39p' third_party/uboot-mainline/arch/arm/mach-zynqmp/spl.c
```

```text
void board_init_f(ulong dummy)
{
#if !defined(CONFIG_DEBUG_UART_BOARD_INIT)
	psu_uboot_init();
#endif

	board_early_init_r();
#ifdef CONFIG_SPL_ZYNQMP_DRAM_ECC_INIT
	zynqmp_ecc_init();
#endif
}
```

十一行，三件事：平台电源与时钟初始化、板级早期初始化、可选的 DDR ECC。没有座次表，没有搬家预算，因为它不搬家。crt0.S 文件头那段注释把分工写得明明白白，咱们把相关两段原样翻出来。

```bash
# 主机 ~/imx-forge
sed -n '40,52p' third_party/uboot-mainline/arch/arm/lib/crt0.S
```

```text
 * 4a.For U-Boot proper (not SPL), call relocate_code(). This function
 *    relocates U-Boot from its current location into the relocation
 *    destination computed by board_init_f().
 *
 * 4b.For SPL, board_init_f() just returns (to crt0). There is no
 *    code relocation in SPL.
 *
 * 5. Set up final environment for calling board_init_r(). This
 *    environment has BSS (initialized to 0), initialized non-const
 *    data (initialized to their intended value), and stack in system
 *    RAM (for SPL moving the stack and GD into RAM is optional - see
 *    CONFIG_SPL_STACK_R). GD has retained values set by board_init_f().
 *
```

U-Boot proper 调 relocate_code 搬家，SPL 里 board_init_f 直接返回，没有代码重定位这一说。链接地址那篇咱们追的搬家功夫是完整 U-Boot 的看家本领，SPL 的一生都在自己那点 SRAM 里过，跳去 DDR 的下一棒早在链接时就排好了地址。对照牌到这里兑现了。

### 栈与 BSS 的特殊安排

SPL 的栈分两段，这是它跟完整 U-Boot 差别最大的地方。第一段在 SRAM，SPL_STACK 给它排地址——上面第二节探针里那行 0x91ffb8 就是 MX6 家族的默认栈顶，链接地址那篇咱们算过预留区的顶 0x0091ff00（进门那一刻 sp 立的数），board_init_f 把早期堆与 gd 归置完，栈顶落到 0x0091de00。两代进门栈顶挤在 OCRAM 顶上同一小段，谁都没往外挪。第二段可选进 DDR：SPL_STACK_R 打开之后，crt0.S 调 spl_relocate_stack_gd 把栈和 gd 一起搬进 DDR，common/spl/spl.c 第 903 行的注释把缘由直说了，board_init_f 阶段常常只有 SRAM 里的栈可用，board_init_r 想要 SDRAM。README.omap3 那张地图里 SRAM 顶上 0x4020E000 到 0x4020FFFC 那块，就是第一段栈的地皮。

BSS 的讲究更多，三组选项各管一头。时机归 SPL_EARLY_BSS：开了它，crt0.S 在进 board_init_f 之前就清 BSS（第 120 行那支 `#if defined(CONFIG_XPL_BUILD) && defined(CONFIG_SPL_EARLY_BSS)` 守着），内存紧的平台不敢这么早，默认次序是进 board_init_r 之前清。住址归 SPL_SEPARATE_BSS 与 SPL_BSS_START_ADDR：前者允许把 BSS 搬去另一块内存，理由是那时 RAM 已经活了，后者给它排地址，MX6ULL 那支默认 0x88200000。上限归 SPL_BSS_MAX_SIZE，MX6 家族顶格 0x100000。链接地址那篇咱们看过自己链路上的 BSS：Boot ROM 只搬 boot data 写明的尺寸，BSS 没人搬也没人清，清的动作排在搬家落地之后。SPL 这边把 BSS 的时机、住址、上限全写进 Kconfig，因为它要在自己那点内存里把生命周期排明白，README.omap3 里 BSS 排进 DDR、DDR 区段 s_init() 完成前不能碰，就是这份排程的实物。

### 两阶段镜像怎么排

顶层 Makefile 里 SPL_PAYLOAD 默认取 u-boot.bin，u-boot-with-spl.bin 这条规则拿 SPL 镜像和 payload 用 pad_cat 拼在一起，`--pad-to=$(CONFIG_SPL_PAD_TO)` 把 SPL 占的长度垫齐。拼出来的是一个文件，SPL 在前、完整 U-Boot 在后，ROM 认头一段，读完跳进 SPL，SPL 一低头就看见紧挨在自己后面的完整 U-Boot，搬进 DDR 完事。另一条路是 SPL 现场去介质取：AM335x 那份配置里 `CONFIG_SPL_FS_LOAD_PAYLOAD_NAME="u-boot.img"` 指名道姓，u-boot.img 由 Makefile 用 mkimage 包好，CONFIG_SPL_FRAMEWORK 开着时它被排进产物清单。FIT（U-Boot 的一种镜像打包格式，把多份镜像连描述表包成一个文件）那一路走 common/spl/spl_fit.c，CONFIG_SPL_LOAD_FIT 开着才编进来。咱们把两条路并排放一眼，差别只在下一棒怎么到手，布局的形状一样，小的在前当门面，大的在后当家底。

## 四、为什么本卷不写 SPL 实操

理由在链路本身，咱们已经很熟了：咱们这块 AES 板的启动路线，DDR 前置 Boot ROM 全包了。DCD 表或 plugin 二选一，DCD 逐条读那篇验过 11 月 14 日那轮参考产物的镜像头，插件位为零、Mode 是 DCD，两块板都留在 DCD 道上，那轮产物的来历记在 01 与 03 两篇的前置环境里。Boot ROM 搬完镜像直接跳 0x87800000，链接地址那篇从那个地址接手讲搬家。链上没有第三个位置，SPL 插不进来，给这条链写 SPL 实操，等于给不需要中转的班车硬加一站。

产物这一头的证据本篇补齐，咱们拿 out/uboot 那份 .config 查一遍。

```bash
# 主机 ~/imx-forge
grep -n "CONFIG_SPL" out/uboot/.config
```

```text
49:# CONFIG_SPL_USE_SEPARATE_FAULT_HANDLERS is not set
71:# CONFIG_SPL_SYS_L2_PL310 is not set
478:# CONFIG_SPL_SILENT_CONSOLE is not set
489:# CONFIG_SPL_SYS_STDIO_DEREGISTER is not set
509:# CONFIG_SPL_CYCLIC is not set
1186:# CONFIG_SPL_NVMEM is not set
1352:# CONFIG_SPL_PHY_ATHEROS is not set
1375:# CONFIG_SPL_PHY_TI_DP83867 is not set
1753:CONFIG_SPLASH_SCREEN=y
1754:CONFIG_SPLASH_SCREEN_ALIGN=y
1756:# CONFIG_SPLASH_SOURCE is not set
1895:# CONFIG_SPL_LZMA_SIZE_OPTIMIZATION is not set
1897:# CONFIG_SPL_GZIP is not set
```

十三处命中，十处是 is not set 的 SPL 系选项，三处还是 SPLASH，一个开着的 SPL 开关都没有。构建目录咱们也看过。

```bash
# 主机 ~/imx-forge
ls -la out/uboot/spl/
```

```text
total 8
drwxr-xr-x  2 charliechen charliechen 4096 Oct 17 15:04 .
drwxr-xr-x 19 charliechen charliechen 4096 Oct 20 10:06 ..
```

目录是构建时建出来的空壳，里面只有 . 和 ..，没有一个产物。Boot ROM 那篇点过产物清单里没有任何 SPL 文件，咱们拿这两件实物把那句话接实在了。

::: warning 这棵树里找不到 spl/ 目录，别当成 U-Boot 没有 SPL 的证据
后果是拿一张残缺的地图去配别家的板：以为 SPL 的构建体系不存在，照错误结论给真需要 SPL 的平台写链路，一步就偏了。根因不在裁剪：spl/ 不是源码目录，是构建输出目录，.gitignore 第 74 行把它连同 /tpl/、/vpl/ 一起挂在 Generated files 名下，所以哪棵源码树里都不会有它，构建时才在输出目录生成，out/uboot/spl/ 那个空壳就是这么来的。框架代码 common/spl/ 与 scripts/ 下的构建脚本（scripts/Makefile.xpl）都好好地在这棵树里。解法是不用换树，构建入口就在本树，顶层 Makefile 第 2448 行会调 scripts/Makefile.xpl 把 spl 编出来，真编起来是否全通咱们没试过，别打包票，机制照旧回这棵树里读 common/spl/ 与 doc/SPL/。
:::

以后真碰上走 SPL 的板子，源码这一头从 common/spl/ 进门，36 个文件里 spl.c 是框架，每种介质一个 spl_*.c，common/spl/Kconfig 里栈、BSS、尺寸三组选项各归各位，第二节那五个默认值就是从它里面捞的。手册那一头，别家 BootROM 认什么格式、给多长窗口，手册说了算，这篇不越界代劳。configs 里现成的样例 am335x 那份，CONFIG_SPL_ 系选项从头排到尾，咱们照着认符号比背文档快。

回头咱们把自己这块板再对一遍：镜像照旧躺在 DCD 道上，Boot ROM 搬完直接跳 0x87800000，搬家是完整 U-Boot 自己的活，启动链两级，产物目录里一个 SPL 文件都没有，这就是咱们这条链和那些多一层平台的分岔。

## 继续学习

- [上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像](01_boot_rom_boot_media.md)：ROM 只认固定偏移、只搬裸数据，咱们靠这份底子判断哪些平台得垫 SPL。
- [DCD 逐条读：BootROM 替咱们执行的初始化清单](03_dcd_walkthrough.md)：DCD 与 plugin 两条 DDR 前置路，咱们本卷不写 SPL 实操的底气在那篇。
- [链接地址与运行地址对不上的日子](07_relocation_limits.md)：搬家的功夫归完整 U-Boot，SPL 没有这一说，咱们对照着读正好。
