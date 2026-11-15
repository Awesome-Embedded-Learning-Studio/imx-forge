---
title: DCD 逐条读：BootROM 替咱们执行的初始化清单
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# DCD 逐条读：BootROM 替咱们执行的初始化清单

> IVT 这张索引卡的 0x0c 那格，第一篇认过脸，拼出了 0x877ff42c，清单的头几个字节与开头几组写入也念过了。本篇从这格指针进去，把 0x2C 处那份 488 字节的清单整份逐段走完，把 DCD 的头与两类指令认明白，再回到源头把 imximage.cfg 逐段过掉。PLUGIN 那条路第一篇只点了一句没开，本篇把它从源码到产物整个验一遍。Boot ROM 替咱们干的活到这里全部交代完，下一篇进 U-Boot 本体，从入口 _start 看起。

## 一、DCD 在镜像里的位置与形态

咱们把第一篇攒下的转储接过来，从那个指针对进去。EVK 与 AES 两份头里 0x0c 起四个字节都是 2c f4 7f 87，按第一篇练熟的小端拼法读出 0x877ff42c，这是 Boot ROM 要去找的清单地址。它旁边的 self，0x14 起四个字节，拼出 0x877ff400，IVT 自己住的地方。两个地址在同一片头区里，相减只差 0x2C，44 个字节。咱们翻 include/imximage.h 的结构体把 44 按结构体成员分开:flash_header_v2_t 是四字节的头加七个字，恰好 32 字节，跟着的 boot_data_t 三个字 12 字节，44 再往后就是 DCD 的位置。文件偏移因此不用猜，指针差值就是清单离开文件头多远，第一篇验证过 IVT 本身躺在文件偏移 0，0x2C 便是落点。

这个差值是 mkimage 算出来的，源头在 tools/imximage.c 的 set_imx_hdr_v2（329 行起）。逻辑很直白:self 写成 hdr_base，公式是入口地址减装载区尺寸加介质偏移，咱们把 AES 这份代进去，0x87800000 减 0x1000 加 0x400，恰好 0x877ff400。清单非空时 dcd_ptr 再写成 hdr_base 加 data 成员的偏移，44，正是咱们减出来的那个数。两个减数加数也不神秘，BOOT_FROM 选中的 sd 在 tools/imximage.c 第 42 行起的两张表里各查到一行，介质偏移 0x400，装载尺寸 0x1000。源码、结构体、转储，三处证据互相咬合。

咱们翻 tools/imximage.c，DCD 的构造函数都挂着 dcd 的名字:

```bash
# 主机 ~/imx-forge
grep -n "DCD\|dcd" third_party/uboot-mainline/tools/imximage.c | head -10
```

```text
18:#if !defined(CONFIG_IMX_DCD_ADDR)
19:#define CONFIG_IMX_DCD_ADDR 0x00910000
92:static set_dcd_val_t set_dcd_val;
93:static set_dcd_param_t set_dcd_param;
94:static set_dcd_rst_t set_dcd_rst;
96:static uint32_t max_dcd_entries;
124:		(hdr_v1->dcd_table.preamble.barker == DCD_BARKER))
129:		(hdr_v2->data.dcd_table.header.tag == DCD_HEADER_TAG))
147:static void set_dcd_val_v1(struct imx_header *imxhdr, char *name, int lineno,
150:	dcd_v1_t *dcd_v1 = &imxhdr->header.hdr_v1.dcd_table;
```

咱们真把 256 字节倒出来，清单就在算好的位置上等着:

```bash
# 主机 ~/imx-forge
xxd -l 256 /tmp/uboot-ref-aes/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
00000010: 20f4 7f87 00f4 7f87 0000 0000 0000 0000   ...............
00000020: 00f0 7f87 0000 1a00 0000 0000 d201 e840  ...............@
00000030: cc01 e404 020c 4068 ffff ffff 020c 406c  ......@h......@l
00000040: ffff ffff 020c 4070 ffff ffff 020c 4074  ......@p......@t
00000050: ffff ffff 020c 4078 ffff ffff 020c 407c  ......@x......@|
00000060: ffff ffff 020c 4080 ffff ffff 020e 04b4  ......@.........
00000070: 000c 0000 020e 04ac 0000 0000 020e 027c  ...............|
00000080: 0000 0030 020e 0250 0000 0030 020e 024c  ...0...P...0...L
00000090: 0000 0030 020e 0490 0000 0030 020e 0288  ...0.......0....
000000a0: 000c 0030 020e 0270 0000 0000 020e 0260  ...0.......p.......`
000000b0: 0000 0030 020e 0264 0000 0030 020e 04a0  ...0...d...0....
000000c0: 0000 0030 020e 0494 0002 0000 020e 0280  ...0............
000000d0: 0000 0030 020e 0284 0000 0030 020e 04b0  ...0.......0....
000000e0: 0002 0000 020e 0498 0000 0030 020e 04a4  ...........0....
000000f0: 0000 0030 020e 0244 0000 0030 020e 0248  ...0...D...0...H
```

00000020 那一行的尾巴上，d201 e840 四个字节出现在 0x2C，跟减法分毫不差。哪天布局变了、减法算不准，咱们也不猜，转储里搜标记字节就行:清单头以 d2 起头，跟着两字节大端长度与版本 0x40，位置紧跟在 boot data 三个字之后，在头部转储里搜到这样一串就是它。算术与搜索互为备份，两条路都通向同一个 0x2C。

### d2 开头:清单头与写、查两类指令

清单头四个字节咱们逐个认。d2 是标记，include/imximage.h 第 53 行给它起名 DCD_HEADER_TAG。01e8 是长度，大端读作 0x01E8，488 字节，清单头自己也算在内。40 是版本，跟 IVT 头里那个 0x40 同代。往下就是指令流，第一格 cc 01 e4 04:0xCC 是写指令的标记，宏名 DCD_WRITE_DATA_COMMAND_TAG。0x01E4 换算 484 字节，命令头占 4，剩下 480 装六十对地址加值，每对 8 字节。末位的 04 是参数字节，按 4 字节宽写。

两类指令的 tag 与参数，咱们拿 include/imximage.h 第 53 行起那几行宏逐个对过。写指令挂在 0xCC 名下，参数字节分三档:0x4 普通写，0xC 清位写，0x1C 置位写，后两档带位掩码，对应 cfg 语法里的 CLR_BIT 与 SET_BIT。检查指令换 0xCF 当标记，宏名 DCD_CHECK_DATA_COMMAND_TAG，参数 0x14 验掩码位置上，0x04 验位清掉，对应 CHECK_BITS_SET 与 CHECK_BITS_CLR。tools/imximage.c 第 24 行起的命令表把这五个关键字列在一处，AES 这份 cfg 里真正用到的只有 DATA，外加条件分支里一条 CHECK_BITS_SET。

同一张转储里藏着两套字节序，咱们读的时候得换读法。IVT 的字段按小端拼，0000 8087 要倒过来念 0x87800000。DCD 的载荷按大端排，020c 4068 顺着念就是 0x020c4068。根子在源码，set_dcd_val_v2（tools/imximage.c 241 行起）把地址与值用 cpu_to_be32 存进清单，IVT 那些字段却按小端落。第一篇练的小端读法只管到 0x2C 之前，进了清单就得顺着读。

连续同类写入还会合流。set_dcd_param_v2（177 行起）碰到参数字节相同的 DATA 行不再开新命令头，六十条写入在镜像里共用 0x30 处这一个头。检查类一格只放一条，177 行起的函数里那句 Check data command only supports one entry 的注释写得明白。这个合流是咱们翻 set_dcd_param_v2 读出来的，0x30 处只此一个 0xCC 头的转储也核过，所以这份清单 488 字节里只有一个 0xCC 头，拖着 480 字节载荷，排得很紧。

### 清单到哪儿收尾

清单的尾巴咱们也验证了:

```bash
# 主机 ~/imx-forge
xxd -s 496 -l 96 /tmp/uboot-ref-aes/u-boot-dtb.imx
```

```text
000001f0: 0000 0800 021b 0818 0000 0227 021b 0004  ...........'....
00000200: 0002 552d 021b 0404 0001 1006 021b 001c  ..U-............
00000210: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000220: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000230: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000240: 0000 0000 0000 0000 0000 0000 0000 0000  ................
```

0x20C 起最后一对，地址 0x021B001C 配值 0，恰好是 cfg 最后一行 DATA。0x214 起整片补零，0x2C 加 488 正好等于 0x214，清单一字节不多。补零一路垫到 0xC00，U-Boot 正文从那里开始，咱们顺手把 AES 这份的正文起点也验证了:

```bash
# 主机 ~/imx-forge
xxd -s 3072 -l 16 /tmp/uboot-ref-aes/u-boot-dtb.imx
```

```text
00000c00: b800 00ea 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
```

0xC00 起这十六个字节咱们也倒出来对过，b800 00ea 与第一篇在 EVK 上见过的完全同款，按小端拼成 0xea0000b8，ARM 的无条件跳转，异常向量表的起头。3 KiB 头区的边界在 AES 这份上同样成立，索引卡 44 字节、清单 488 字节、补零两千五百多字节，全部住在头区里，U-Boot 本体一步没占。

## 二、AES 的 DCD 源头:imximage.cfg 逐段

清单不是手编的二进制，它有源文件，mkimage 把 cfg 里的 DATA 行逐条翻成 DCD，翻译逻辑就是上一节那批函数。咱们从文件开头往下走，第一段定介质:

```bash
# 主机 ~/imx-forge
sed -n '23,34p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
```

```text
#ifdef CONFIG_QSPI_BOOT
BOOT_FROM	qspi
#elif defined(CONFIG_NOR_BOOT)
BOOT_FROM	nor
#else
BOOT_FROM	sd
#endif

#ifdef CONFIG_USE_IMXIMG_PLUGIN
/*PLUGIN    plugin-binary-file    IRAM_FREE_START_ADDR*/
PLUGIN	board/nxp/mx6ull_aes_emmc/plugin.bin 0x00907000
#else
```

BOOT_FROM 走了三岔分支，没配 QSPI 也没配 NOR，落到 sd。这一个字身后就是上一节那两张表，sd 查出 0x400 介质偏移与 0x1000 装载尺寸，第一篇讲的 1 KiB 搜索点源头在这里。分支里的宏在预处理时裁掉，mkimage 真正读到的是预处理产物 u-boot-dtb.cfgout，咱们把这份中间产物也翻过:/tmp/uboot-ref-aes/u-boot-dtb.cfgout 第 52 行 IMAGE_VERSION 2，第 54 行 BOOT_FROM sd，#ifdef 与 #endif 一个不剩。cfg 与 cfgout 对照着看，哪些行真正进了清单，一眼分明。

第 31 行一个 #ifdef 把 PLUGIN 行拦在里面，那是另一条路，第三节专门去走，这个拦截咱们在预处理产物里核过，PLUGIN 一行没进 cfgout。#else 分支里才是清单正文，第 52 行注释底下排开七条时钟写入:

```bash
# 主机 ~/imx-forge
sed -n '52,63p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
```

```text
/* Enable all clocks */
DATA 4 0x020c4068 0xffffffff
DATA 4 0x020c406c 0xffffffff
DATA 4 0x020c4070 0xffffffff
DATA 4 0x020c4074 0xffffffff
DATA 4 0x020c4078 0xffffffff
DATA 4 0x020c407c 0xffffffff
DATA 4 0x020c4080 0xffffffff

#ifdef CONFIG_IMX_OPTEE
DATA 4 0x20e4024 0x00000001
CHECK_BITS_SET 4 0x20e4024 0x1
```

这一段把时钟带活，这七条咱们跟转储 0x30 起的载荷逐条对过。0x020c4068 到 0x020c4080 是 CCM 的七个门控寄存器 CCGR0 到 CCGR6（基址 0x020C4000），全部写 0xffffffff，外设时钟一个不留全打开，后面 MMDC（6ULL 上管 DDR 的内存控制器）要动起来靠的就是这一步，注释 Enable all clocks 是文件自己标的段落名。夹在中间的 61 到 63 行是个条件分支，DATA 4 0x20e4024 0x00000001 写完跟上 CHECK_BITS_SET 4 0x20e4024 0x1 验置位。这轮构建没开 OPTEE，预处理把它剥得干净，下面数行数时看得到，可这两行是现成的检查类语法样例，值得记住。

接着 66 到 84 行是引脚段，十九条写入全打在 0x020E 开头的地址上，那是 IOMUXC 的范围，基址 0x020E0000。这十九个地址咱们扫了一遍，全部落在 0x020E0000 的范围里。第一行 DATA 4 0x020E04B4 0x000C0000 给 DDR 引脚组定全局档位，后面一串 0x00000030 逐个挪数据、地址、控制引脚的驱动强度。这一段把 DDR 引脚的电气参数配好，颗粒再好、时序再准，引脚驱动不给力也白搭。

最后一段 85 到 118 行咱们也挨条念，清单的大头，控制器与 PHY 都在这:

```bash
# 主机 ~/imx-forge
sed -n '85,120p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
```

```text
DATA 4 0x021B001C 0x00008000
DATA 4 0x021B0800 0xA1390003
DATA 4 0x021B080C 0x00000004
DATA 4 0x021B083C 0x41640158
DATA 4 0x021B0848 0x40403237
DATA 4 0x021B0850 0x40403C33
DATA 4 0x021B081C 0x33333333
DATA 4 0x021B0820 0x33333333
DATA 4 0x021B082C 0xf3333333
DATA 4 0x021B0830 0xf3333333
DATA 4 0x021B08C0 0x00944009
DATA 4 0x021B08b8 0x00000800
DATA 4 0x021B0004 0x0002002D
DATA 4 0x021B0008 0x1B333030
DATA 4 0x021B000C 0x676B52F3
DATA 4 0x021B0010 0xB66D0B63
DATA 4 0x021B0014 0x01FF00DB
DATA 4 0x021B0018 0x00201740
DATA 4 0x021B001C 0x00008000
DATA 4 0x021B002C 0x000026D2
DATA 4 0x021B0030 0x006B1023
DATA 4 0x021B0040 0x0000004F
DATA 4 0x021B0000 0x84180000
DATA 4 0x021B0890 0x00400000
DATA 4 0x021B001C 0x02008032
DATA 4 0x021B001C 0x00008033
DATA 4 0x021B001C 0x00048031
DATA 4 0x021B001C 0x15208030
DATA 4 0x021B001C 0x04008040
DATA 4 0x021B0020 0x00000800
DATA 4 0x021B0818 0x00000227
DATA 4 0x021B0004 0x0002552D
DATA 4 0x021B0404 0x00011006
DATA 4 0x021B001C 0x00000000

#endif
```

清单的最后一段把 DDR 控制器带活，也把清单带进尾声。0x021B 开头的地址分两片，0x021B0000 是 MMDC 控制器本体，0x021B0800 起是它的 PHY。0xA1390003 写进 0x021B0800，PHY 校准从这里起步。0x081C、0x082C 那几串 0x33 与 0xf3 是读写延时的档位，跟板上颗粒与布线一一相关。0x84180000 写进 0x021B0000，控制器正式发起。0x021B001C 这一个地址在整份文件里出现八次，八次是咱们挨个数出来的，它是 MDSCR，模式寄存器的命令口。85 与 103 两行各写一次 0x00008000。109 到 113 行连写五次，前四次把 DDR3 的 MR0 到 MR3 挨个写完，第五次发读校准。118 行再清一次零收工。位段怎么分，MDSCR 的定义在参考手册里，本篇不逐位展开。

行数咱们也拿真数核过:

```bash
# 主机 ~/imx-forge
grep -c '^DATA' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
grep -c '^DATA' /tmp/uboot-ref-aes/u-boot-dtb.cfgout
```

```text
61
60
```

源文件 61 条顶格 DATA，多出的那条住在 OPTEE 分支里，预处理后 mkimage 实际解析的 cfgout 只剩 60 条。60 对上镜像里的 480 字节载荷，61 减 1 对上被剥掉的分支，源文件、中间产物、镜像转储三处咬合。再细分，这 60 条里时钟段 7 条、引脚段 19 条、控制器与 PHY 段 34 条，7 加 19 加 34 正好 60，每一条咱们在上面三段里都念到了。

## 三、plugin 模式:BootROM 的二次装载

DCD 之外还有第二条路。第二节那句被 #ifdef 拦住的 PLUGIN 行铺的就是它:初始化清单换成一可执行的小段代码。PLUGIN 后头跟两样东西，插件二进制的路径与它在片内 RAM 的落点，AES 这份写的是 board/nxp/mx6ull_aes_emmc/plugin.bin 与 0x00907000。plugin.bin 从 plugin.S 编出来，咱们量过它的行数:

```bash
# 主机 ~/imx-forge
wc -l third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/plugin.S
```

```text
263 third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/plugin.S
```

263 行真实躺在仓库里。翻开来，板卡专属的部分全是汇编宏:imx6ull_ddr3_evk_setting 从第 10 行铺到 117 行，把 DCD 表里同一批地址值逐条 ldr、str 写一遍，第一个写的就是 0x000C0000 进 IOMUXC 基址加 0x4B4，跟 cfg 第 66 行一字不差。时钟段也有一份对应的宏，咱们摆出来对照:

```bash
# 主机 ~/imx-forge
sed -n '233,249p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/plugin.S
```

```text
.macro imx6_clock_gating
	ldr r0, =CCM_BASE_ADDR
	ldr r1, =0xFFFFFFFF
	str r1, [r0, #0x68]
	str r1, [r0, #0x6C]
	str r1, [r0, #0x70]
	str r1, [r0, #0x74]
	str r1, [r0, #0x78]
	str r1, [r0, #0x7C]
	str r1, [r0, #0x80]

#ifdef CONFIG_IMX_OPTEE
	ldr r0, =0x20e4024
	ldr r1, =0x1
	str r1, [r0]
#endif
.endm
```

CCM_BASE_ADDR 加 0x68 到 0x80，七个门控写满 0xFFFFFFFF，这七个数咱们跟 cfg 第 53 到 59 行摆在一起核过，一个数都不差。同一份 DDR 脚本，仓库备了两种编码:DCD 是纯数据，Boot ROM 的搬运器挨条取、挨条写，不会判断。插件是代码，宏展开成真的指令序列，DDR3 还是 LPDDR2 由宏在汇编期挑定，254 行的 imx6_ddr_setting 干的就是挑选，9X9 EVK 那个目标才走 LPDDR2。末行 include 进来的公共件才是插件真正的流程骨架。

公共件 arch/arm/include/asm/arch-mx6/mx6_plugin.S 里，plugin_start 跑完 DDR 与时钟的宏把 DDR 带活，然后查 Boot ROM 留在片内的 API 表（基址按芯片版本在 0xC0、0xC4 或 0x180 里挑），调回 ROM 的搬运函数 pu_irom_hwcnfg_setup，让它照 boot data 把数据从介质搬进 DDR，搬完把 ROM 打开的 MMU 与 cache 关回去，最后给 plugin_download(start, bytes, ivt_offset) 填好三个参数，r0 置 1，bx lr 回 ROM。这段流程执行咱们验不到，是翻公共件汇编读出来的。文件尾排着一串全零的字，那是第二张 IVT 的模板，second_ivt_offset 按 ivt2_header 加 0x2C 加 0x400 算出，连同最终地址与总长一起交回 ROM 手里。

mkimage 那头配合改布局，tools/imximage.c 361 行起的 else 分支管插件态:IVT 的 dcd_ptr 直接写 0（378 行），插件态没有清单。boot data 的 size 定成 MAX_PLUGIN_CODE_SIZE，include/imximage.h 第 11 行写明是 64 KiB，ROM 第一趟只搬这 64 KiB 进片内 RAM。第二张 IVT 写在镜像里偏移 imximage_plugin_size 的地方，entry 字段才是 U-Boot 的真入口（411 行），它自己的插件位留 0。这套布局咱们在源码里从 else 分支一路读到 411 行。整条链路是两趟搬运:ROM 搬一小段，跑插件，DDR 活，插件把第二张 IVT 的位置交回去，ROM 再把完整镜像搬进 DDR，跳真入口。

### 这轮镜像走的是哪条路

铺了路不等于走了路。开关这头，/tmp/uboot-ref-aes/.config 第 243 行写着 # CONFIG_USE_IMXIMG_PLUGIN is not set，预处理产物 cfgout 里一行 PLUGIN 都没有，mkimage 解析的是 #else 分支。产物这头，咱们再看 mkimage 干完活自己写的报告，它躺在 /tmp/uboot-ref-aes/u-boot-dtb.imx.log 里:

```text
Image Type:   Freescale IMX Boot Image
Image Ver:    2 (i.MX53/6/7 compatible)
Mode:         DCD
Data Size:    1703936 Bytes = 1664.00 KiB = 1.62 MiB
Load Address: 877ff420
Entry Point:  87800000
```

第三行 Mode: DCD 的出处是 tools/imximage.c 507 行那个 printf，插件位非零才报 PLUGIN。转储里还有两个旁证，这两个咱们都在 256 字节转储里点过。0x28 那个字是 0000 0000，boot data 的插件位为零。0x2C 处的 dcd_ptr 非 0，而插件态下源码 378 行把它写成 0。几处证据合起来说一件事:这条路铺好了，11 月 14 日这一轮没走。EVK 的 cfg 第 30 到 32 行同样铺着这条路，路径换成 mx6ullevk/plugin.bin，它的报告第三行同样是 Mode: DCD，两块板的镜像都留在 DCD 这条道上。

## 四、写错一个值的后果

清单的执行者是 Boot ROM，它没有任何报错渠道。六十个值里写错一个时序，板子上的症状是安静:MMDC 起不来，或者起来了读写全错，Boot ROM 照 boot data 把镜像往 0x877ff000 搬、往 0x87800000 跳，落点全是死内存。U-Boot 的第一条指令都执行不到，串口一行都不出。这一步咱们验不到，只能照机制推演。往深处追，坏的那一环在清单里，而搬运与跳转全发生在芯片内部，外面看不见动静。

::: warning DDR 参数改错，全静默
DDR 时序或校准值改错，症状是串口零输出，与介质选错、镜像烧偏一模一样。根因是这几类毛病共用同一条链，Boot ROM 执行 DCD 没有回执，断在哪一环，串口分不出来。判读以 NXP 参考手册的 System Boot 与 MMDC 章节为准。逐环排查的完整路径回收 09 章《DDR 初始化与镜像头》那篇:[DDR 初始化与镜像头:imximage.cfg 里写了什么](../09_ddr_imxheader.md)。
:::

清单里唯一的自验手段是检查类指令。CHECK_BITS_SET 在写入后验掩码位真的置上了，验不过 boot 停下（这一步同样发生在芯片里，以手册为准），关键写入配上它等于多一道自查。源码层面它一格只放一条，这个限制咱们回头在源码注释里核对过，tools/imximage.c 那句 Check data command only supports one entry 写得明白。语法样例就是第二节 61 到 63 行 OPTEE 分支那两条，写完跟上验位，一行不多。时钟段那七条全 1 的写入没配检查，写完就往下走。

至于那批 0x33 与 0xf3 串起来的延时档位，第二节说过它们跟颗粒与布线绑定，这批档位咱们在 cfg 与 plugin.S 两处见过同样的串，真换颗粒就得整批重调。怎么调、调完怎么验，09 章那一篇有完整实作，本篇不重复展开。

## 五、Boot ROM 这一程收尾

Boot ROM 这一程到这里把链走完了。上电后 Boot ROM 挑介质，在 0x400 认出 d1 开头的索引卡，照 dcd 指针找到 0x2C 处那份 488 字节的清单逐条执行，DDR 就在这一段活过来。接着 Boot ROM 按 boot data 把镜像搬进 DDR，跳 0x87800000，把世界交给 U-Boot。咱们把第一篇与本篇串成一根线:

```text
上电
  -> Boot ROM 挑介质，在 0x400 读 IVT
  -> 照 dcd 指针 0x877ff42c 找到 0x2C 处的 DCD，逐条执行
  -> 时钟开，引脚配档，MMDC 与 PHY 配平，MR 写完，DDR 活
  -> 按 boot data 把镜像搬进 DDR，跳 0x87800000
  -> U-Boot 接手
```

第一篇说过，清单怎么编、每个字段什么意思，要留给专门一篇，本篇兑现的就是这句。调参实作本身归 09 章那一篇，那里有完整实作。芯片里那段执行咱们只能凭字段与手册互证，文件侧的每一步都留了命令，拿自己的 out/uboot 重跑一遍就验证了。

下一篇从 ROM 跳进 0x87800000 那一刻开始看 U-Boot 本体，入口 _start 与异常向量。手头这份 AES 镜像给咱们把边界算清了:0x00 到 0x2C 是索引卡与 boot data，0x2C 到 0x214 是清单，0x214 到 0xC00 是补零，0xC00 起第一条指令 b8 00 00 ea 已经在 0x87800000 等着 ROM 跳进来。

## 继续学习

- [上电之后:Boot ROM 怎么挑启动介质、认出咱们的镜像](01_boot_rom_boot_media.md):第一篇倒出的头 64 字节是本篇全部偏移算术的入口，咱们回头重读那张表，dcd 指针的来历就在里面。
- [DDR 初始化与镜像头:imximage.cfg 里写了什么](../09_ddr_imxheader.md):清单里六十个值怎么调出来、镜像头排查怎么走，09 章那一篇给咱们铺开完整实作。
