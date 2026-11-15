---
title: 控制权交接那一刻：全卷的终点线
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 控制权交接那一刻：全卷的终点线

> boot-chain 这卷十六篇里，交棒这一跳排在编号末位：U-Boot 把控制权交出去那一刻，串口上是什么样，交棒之前它替内核办完了什么。本篇把它讲完，10、11、13、14、15 五篇也已落座，全卷十六篇就此齐全。本篇回收 debug 卷留档的真板现场，各行字样另拿主线 14 章整理的期望输出对格式，咱们把 Starting kernel 前后的源码锚点逐个落到 bootm.c、image-fdt.c 与 cpu.c 上，再把已落成的各篇逐篇一句话收拢成一张总表，拿主线 01 章的四段地图解释十六篇的编法，跟主线十四章对出两卷的分工。已落成的上一篇 [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md) 停在提示符等人，本篇从提示符之后那道命令接起。交接之后的世界归内核卷与 rootfs 卷，文末指路。

## 一、最后一跳的现场：串口实录回收

U-Boot 在串口上说的最后一句话是 Starting kernel ...，往前数几行，就是交接前的全部现场。仓库留过一段 2026 年 10 月 13 日的真板产线卡启动实录，debug 卷 [串口日志阅读路线：从一行输出找到下一站](../../debug/03_serial_log_reading.md) 引用过它。那张卡上的 U-Boot 是 2025.04 的旧一轮镜像，跟咱们现树编的 v2026.10 差着一个版本代，上电后的次序却是同一张时刻表：一行 U-Boot 横幅，CPU 与内存的自报，一行 Hit any key to stop autoboot: 0 的倒计时，一句 Booting AES from SD ...，两行 ext4load 读数，然后是 Starting kernel ...。ROM 那一程在串口上不出声，实录从横幅直接开始。

版本差一代，横幅格式是不是也差一代，咱们拿自家产物对一眼。strings 进 out/uboot/u-boot 这个 7041816 字节的 ELF（带符号的编译产物，2026 年 10 月 20 日 10:06 出炉）：

```bash
# 主机 ~/imx-forge
strings out/uboot/u-boot | grep -E "U-Boot 20|Starting kernel|Booting AES" | head -8
```

```text
Starting kernel ...%s
U-Boot 2026.10-dirty
emmcbootaes=echo Booting AES from eMMC ...; run emmcargs; mmc dev ${emmc_dev}; run loademmcimage; run loademmcfdt; bootz ${loadaddr} - ${fdt_addr};
sdbootaes=echo Booting AES from SD ...; run sdargs; mmc dev ${sd_dev}; run loadsdimage; run loadsdfdt; bootz ${loadaddr} - ${fdt_addr};
U-Boot 2026.10-dirty (Oct 20 2026 - 10:06:51 +0800)
```

咱们把这五行按内容点名。打头的 Starting kernel ...%s 是本篇主角，%s 只有假跑模式才填 (fake run for tracing)，正常引导永远是空串，源头在 boot/bootm.c 第 1247 行，下节展开。跟着那行 U-Boot 2026.10-dirty 是不带时间戳的版本串，末行 U-Boot 2026.10-dirty (Oct 20 2026 - 10:06:51 +0800) 才是上电横幅的完整格式串，版本号加编译时间戳。strings 里这副格式串出自 v2026.10 自家镜像，产线卡那行 2025.04 横幅，实录只留了字样没留逐字形状，按格式串跨版本稳定的印法预期它长得一样，变的只有版本字与时间，板上到手逐字核。中间两条是板级头文件里备好的两条命名链整串编进了二进制，产线实录出现的是 SD 那句 Booting AES from SD ...，主线 14 章整理 emmcbootaes 期望输出时写的是 eMMC 那句 Booting AES from eMMC ...，两条 echo 在串口上占同一个位置，run 哪条链就说哪句话。

01 到 03 篇反复对账的那批参考材料，咱们今天再去取已经不在了，如实记录：

```bash
# 主机 ~/imx-forge
ls -la /tmp/uboot-ref-build.log /tmp/uboot-ref-aes /tmp/uboot-ref-evk 2>&1
```

```text
ls: cannot access '/tmp/uboot-ref-build.log': No such file or directory
ls: cannot access '/tmp/uboot-ref-aes': No such file or directory
ls: cannot access '/tmp/uboot-ref-evk': No such file or directory
```

构建日志与两份参考产物全住在 /tmp，2026 年 11 月 15 日这天三样全空。12 篇成稿时已经记过一笔，本篇照实再记一回：那三篇贴出的转储是当时真实采集的，咱们今天要复核，拿 out/uboot 这轮自家产物重跑同样的命令就行，头 64 字节的验证法在 [上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像](01_boot_rom_boot_media.md) 结尾留了完整步骤。

咱们把实录的每行挂上出处，收成一张对表：

| 串口上的一行 | 证据挂哪 |
|---|---|
| U-Boot 2025.04 横幅 | 产线实录（debug 卷 03 引用）；自家 v2026.10 的格式串形状见上文 strings，2025.04 的逐字形状待板上核 |
| CPU 与内存自报 | debug 卷 03 的实录描述（原词）；自报里的内存行，可拿主线 05 对照表的 DRAM 行对读 |
| Hit any key to stop autoboot: 0 | 产线卡旧镜像开着倒计时；现树 third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig 第 16 行 CONFIG_BOOTDELAY=-1，这行不会出现，机制在 12 篇 |
| Booting AES from SD ... / from eMMC ... | 两条 echo 链整串编在自家镜像里，strings 输出见上文 |
| 两行 ext4load 读数 | ext4load 的读数回显，产线实录的形态，字节数应对上主机侧文件大小 |
| Starting kernel ... | boot/bootm.c 第 1247 行，下一节展开 |

## 二、内核接手的前几秒：U-Boot 留给内核的三样遗产

bootz 后面跟着的 bootm 流程走到头，打印、清场、跳转三件事在两个文件里排成一条线，咱们把线上的行号一次抓出来：

```bash
# 主机 ~/imx-forge
grep -n -A2 "Starting kernel" third_party/uboot-mainline/boot/bootm.c
grep -n "bootm_final(flag)\|cleanup_before_linux();\|kernel_entry(0, machid, r2)" third_party/uboot-mainline/arch/arm/lib/bootm.c
```

```text
1247:	printf("\nStarting kernel ...%s\n\n",
1248-	       (flag & BOOTM_STATE_OS_FAKE_GO) ?
1249-	       " (fake run for tracing)" : "");
268:	bootm_final(flag);
269:	cleanup_before_linux();
330:	bootm_final(flag);
331:	cleanup_before_linux();
357:		kernel_entry(0, machid, r2);
414:	cleanup_before_linux();
```

这句打印住在 boot/bootm.c 第 1247 行，跳转住在 arch/arm/lib/bootm.c 的 boot_jump_linux（第 300 行起的那一份）：330 行调完 bootm_final 把话说尽，331 行 cleanup_before_linux() 清场，357 行 kernel_entry(0, machid, r2) 跳走。268 与 269 那对是 arm64 版同名函数里的（主线 12 章判过），414 行属于别的启动路径，这块 32 位板都不走。从 1247 那句到跳走，源码里再没有安排任何打印动作。Starting kernel ... 就是 U-Boot 在生命周期里的最后一次输出，这句话咱们是拿行号排出来的，不是凭印象说的。

清场干的是第一样遗产：干净的 CPU 状态。cleanup_before_linux 在 arch/arm/cpu/armv7/cpu.c 第 81 行，正文只有一行，转手给第 27 行的 cleanup_before_linux_select(CBL_ALL)，flags 两位全置（include/cpu_func.h 第 104 到 110 行），按真关缓存走而不只冲刷，外加 bootstage 报告开关，cpu.c 第 39 到 71 行那对分支就是它挑的，咱们把关键几行抓出来：

```bash
# 主机 ~/imx-forge
grep -n "cleanup_before_linux\|disable_interrupts\|dcache_disable\|icache_disable" third_party/uboot-mainline/arch/arm/cpu/armv7/cpu.c
```

```text
27:int cleanup_before_linux_select(int flags)
36:	disable_interrupts();
42:	 * dcache_disable() in turn flushes the d-cache and disables MMU
44:		dcache_disable();
59:		icache_disable();
65:		icache_disable();
81:int cleanup_before_linux(void)
83:	return cleanup_before_linux_select(CBL_ALL);
```

咱们把这几行念一遍：中断先关（36 行），数据缓存冲净、连同 MMU 一起关掉（44 行，42 行的注释自己写着 flushes the d-cache and disables MMU），指令缓存按 flags 分支关掉（59、65 两行）。内核接手时，CPU 身上不带上一棒的任何现场，它假设自己是醒来之后的第一位房客，这个假设成立，证据就在这几行里。

第二样遗产是修补过的设备树。主线 12 章引过 fdt_chosen 与 arch_fixup_fdt 两处锚点，咱们今天在现树上重新核一遍，655、659 行没挪：

```bash
# 主机 ~/imx-forge
grep -n "Loading Device Tree to\|fdt_chosen(blob)\|arch_fixup_fdt(blob)" third_party/uboot-mainline/boot/image-fdt.c
grep -n "fdt_fixup_memory_banks" third_party/uboot-mainline/arch/arm/lib/bootm-fdt.c
```

```text
313:		printf("   Loading Device Tree to %p, end %p ... ",
655:	if (fdt_chosen(blob) < 0) {
659:	if (arch_fixup_fdt(blob) < 0) {
53:	ret = fdt_fixup_memory_banks(blob, start, size, CONFIG_NR_DRAM_BANKS);
```

咱们按行号把两处改动认一遍：第 655 行的 fdt_chosen 把 bootargs 塞进设备树的 /chosen 节点（内核从这里领启动参数），659 行的 arch_fixup_fdt 改写内存声明，真身在 arch/arm/lib/bootm-fdt.c，第 53 行调 fdt_fixup_memory_banks，把 U-Boot 实测的内存容量写进 memory 节点。主线 12 章贴过 dtb 里那个 reg = <0x80000000 0x20000000> 的声明，交接前它让位给实测值。DTB 本体还要搬一次家，boot_relocate_fdt（image-fdt.c 第 195 行）把它挪到内存顶端附近，313 行那条格式串打的就是这次搬家，这条 Loading Device Tree to 格式串是本篇新核的锚点，它的期望输出主线 14 章整理过，Loading Device Tree to 0x9ff5e000, end 0x9ff65f68 ... OK 填的正是它，0x9ff5e000 离 512 MiB 的顶 0xA0000000 只差一小截。内核拿到的设备树已不是存储里那份原样 dtb，bootargs 与内存声明都被交接前的手改过。

第三样遗产是写进 chosen 的 bootargs。材料在板级头文件里，咱们把拼装的几样抓出来：

```bash
# 主机 ~/imx-forge
grep -n "console=ttymxc0\|mmcroot\|emmcargs=setenv" third_party/uboot-mainline/include/configs/mx6ull_aes_emmc.h
grep -n "CONFIG_BAUDRATE" out/uboot/.config
```

```text
53:	"console=ttymxc0\0" \
63:	"mmcroot=/dev/mmcblk1p2 rootwait rw\0" \
66:		"root=${mmcroot}\0" \
67:	"emmcargs=setenv bootargs console=${console},${baudrate} " \
1496:CONFIG_BAUDRATE=115200
```

咱们把 emmcargs 拼出来的成品念一遍：console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw，fdt_chosen 把它塞进 /chosen。内核从这里领三件事：往哪个串口说话、用什么速度说、根文件系统在哪个分区。SD 那条链拼出的 root 是 /dev/mmcblk0p2，介质换一条链，root 的设备号跟着换，主线 12 章讲交接成败的那一段里，介质选错脚本、根设备号指错分区的那一路，根子就在这个变量上。

三样遗产交割完，咱们看寄存器。ARM 的启动约定把参数摆进 r0、r1、r2，357 行 kernel_entry(0, machid, r2) 三个参数各就各位：0 对应约定里必须为零的 r0，machid 是板子编号，r2 是设备树地址。C 语言到此为止。

之后的前几秒归内核。串口安静一阵，内核在解压 zImage（自解压器它自己带在身上）、初始化内存，第一条日志要等它自己的串口驱动就绪才发得出来，bootargs 里 console=ttymxc0 决定它往哪说。内核还有一层更早的临时通道 earlycon，配了它安静期会短很多，主线 12 章的排查表把它排在第一路。解压的每一步、earlycon 怎么配、第一条日志长什么样，归内核卷，本卷停在交接界面上，这是笔者给自己划的深度。

## 三、全卷收拢到今天：一根链上的两卷

十六篇的编法，主线 01 章画过地图：头一段讲 BootROM 与镜像格式，第二段讲片内 RAM 里的早期初始化，第三段讲重定位与后期的搬家，第四段讲交棒内核的那一跳。咱们拿 ls 的真实清单对一眼现状：

```bash
# 主机 ~/imx-forge
ls document/tutorial/uboot/boot-chain/
```

```text
01_boot_rom_boot_media.md
02_ivt_fields.md
03_dcd_walkthrough.md
04_flash_offset_layout.md
05_entry_and_vectors.md
06_gd_and_stack.md
07_relocation_limits.md
08_spl_sidebar.md
09_console_ready.md
10_relocate_code.md
11_board_init_r_dm.md
12_env_and_autoboot.md
13_bootz_parsing.md
14_fdt_handoff.md
15_cleanup_before_linux.md
16_handoff_moment.md
index.md
```

清单十七行，咱们一行行看过去：十六个编号篇把 01 到 16 排满，末尾的 index.md 是站点的目录页，不算篇，本篇排在卷尾第十六个。当年的空座全部落了座，07 篇结尾预告的 SPL 搬家旁栏已经落成，就是 08 篇，05 篇结尾把 board_init_f 的活儿留给了下一篇，06 篇接住了。

咱们把这十六篇每篇一句话收拢：

| 篇 | 一句话 |
|---|---|
| [上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像](01_boot_rom_boot_media.md) | 挑介质，0x400 认 d1 开头的索引卡，DCD 拉 DDR，跳 0x87800000 |
| [IVT 逐字段：BootROM 拿到的说明书](02_ivt_fields.md) | 32 字节索引卡逐字段过，boot data 三字组与 csf 指针各占一节 |
| [DCD 逐条读：BootROM 替咱们执行的初始化清单](03_dcd_walkthrough.md) | 488 字节清单整份走完，60 条 DATA 对回 imximage.cfg |
| [为什么偏偏写到 1KB 偏移：镜像布局与烧录位置](04_flash_offset_layout.md) | BootROM 只认 0x400 的找头点，dd seek=1 的来历与镜像外那 4 MiB 空地逐项落位 |
| [从 _start 开始：U-Boot 的第一条指令](05_entry_and_vectors.md) | 进门之后、进 C 之前 CPU 被摆成什么状态，栈与 gd 立起 |
| [栈和 gd：U-Boot 的小本本](06_gd_and_stack.md) | 栈按公式立进片内 RAM，gd 这个小本本跟着 r9 走，board_init_f 第一轮算出的 relocaddr、new_gd、start_addr_sp 归搬家篇用 |
| [链接地址与运行地址对不上的日子](07_relocation_limits.md) | 重定位把镜像搬到 DDR 高处，链接地址与运行地址分家 |
| [SPL 旁栏：别的平台为什么多一层](08_spl_sidebar.md) | 有 SPL 的平台链条三级走，ROM 交 SPL、SPL 交完整 U-Boot，本板无 SPL 拿它当对照 |
| [console 什么时候就绪：第一行输出来自哪](09_console_ready.md) | banner 从字符串到寄存器的每一站 |
| [搬家：重定位算法与地址计算](10_relocate_code.md) | board_init_f 队列算出新家，八字节一步拷贝，7675 条重定位记录修回全局地址，u-boot.sym 对出两套地址 |
| [board_init_r 与驱动模型扫描：设备树变活设备](11_board_init_r_dm.md) | dm_init 丢旧树全量重扫，compatible 逐串配对绑驱动，mmc、fec、uart 按格点名 |
| [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md) | 8 KB 环境从 eMMC 读回，坏 CRC 回落内置缺省，倒计时一秒一格 |
| [bootz 解析 zImage：内核镜像的头与肚](13_bootz_parsing.md) | 头 48 字节认出 zImage，bootz_setup 验明正身，三个地址进 images，镜像叠住当场报警 |
| [FDT 传递：设备树怎么交到内核手里](14_fdt_handoff.md) | 交接前的修补链走完，bootargs、serial#、内存范围写进树，Loading Device Tree 那行日志翻出来历 |
| [cleanup_before_linux：交接前把场地清干净](15_cleanup_before_linux.md) | 清场走到指令级，中断掩蔽、D-cache 冲净、MMU 关掉，r0、r1、r2 装好跳进内核 |
| 控制权交接那一刻：全卷的终点线（本篇） | Starting kernel 的现场，三样遗产，全卷收拢 |

跟主线十四章的对位，咱们也摆一张小表。主线把活儿教会，扩展卷把同一段链拆到源码行：

| 主线章（教做） | 扩展卷对应篇（讲为什么） |
|---|---|
| 04 产物验证与烧录 | 01、02、03、04：镜像为什么必须写进 1 KiB 偏移，头里每个字替 BootROM 记什么 |
| 05 串口进命令行 | 05、06、09：_start 之后栈与 gd 怎么立，第一行输出走哪条路 |
| 08、09 AES 设备树与 DDR 镜像头 | 02、03：dtb 的前身与镜像头里那份初始化清单逐字节对账 |
| 10、11 eMMC 验收与环境变量 | 12：环境从 eMMC 哪 8 KB 读回来，倒计时由谁关 |
| 12 启动 Linux | 16（本篇）：交棒前的三样遗产与最后一句话 |

遇到会做但不知道为什么的地方，回扩展卷。懂了机制还没上过手的地方，回主线。主线 12 章教咱们敲 bootz 三参数，本篇把这三个参数坐进哪些寄存器也交代了。主线 11 章教咱们改 bootcmd，12 篇把这份环境的来路追到了 eMMC 的 4 MiB 偏移。两卷互为对方的答案卷——这话不是客气，对位表摆在这儿。

## 四、下一步的路：内核卷与 rootfs 卷

交接完成，串口的下一句归内核。交接之后咱们兵分两路：内核卷从 [内核概述](../../kernel/00_kernel_overview.md) 起步，zImage 与 dtb 怎么编出来的在 [编译、外挂模块与 QEMU 首启验收](../../kernel/08_dts_build_boot.md)。rootfs 卷的 [Rootfs 概述](../../rootfs/01_rootfs_overview.md) 管内核挂载的那个根。Starting kernel 之后的串口记录怎么分段读，debug 卷 [串口日志阅读路线：从一行输出找到下一站](../../debug/03_serial_log_reading.md) 备了全份 371 行的 QEMU 记录可对表（QEMU 直启没有 U-Boot 段，前半段对不上属预期）。迭代不想反复烧卡，主线 [换条路：tftp 网络加载，迭代不再反复烧卡](../13_tftp_netboot.md) 的板端四行命令就是那条路。

路径写法这里有个小插曲，这一节头一条探路命令正好给咱们留了记录：

```bash
# 主机，仓库 document/tutorial/uboot/boot-chain 目录下
ls ../kernel/ 2>&1 | head -2
```

```text
ls: cannot access '../kernel/': No such file or directory
```

```bash
# 主机 ~/imx-forge（仓库根）
ls document/tutorial/kernel/ | head -5
```

```text
00_kernel_overview.md
01_why_mainline.md
02_env_setup.md
03_source_fetch.md
04_bsp_vs_mainline.md
```

从本篇所在的 boot-chain 目录写 ../kernel/，落点是 document/tutorial/uboot 底下，那里没有 kernel 目录。内核卷住在 document/tutorial/kernel，从 boot-chain 出发的正确写法是 ../../kernel/。链接先 ls 确认存在再写进正文，防的就是这个错，本篇文末的每条链接咱们都拿 ls 核过。

U-Boot 卷到此收口，咱们把两卷的里程碑串成一根线：主线 02 章把 v2026.10 的源码树装进 third_party，03 章编出第一枚 u-boot-dtb.imx，05 章在串口拿到 => 提示符，12 章让内核日志滚上串口。扩展卷从 0x400 的索引卡进到 _start 的第一条指令，看它搬完家、打出 banner、读回环境，到本篇看着它交出控制权。这根线的最后一格是一枚具体的文件，咱们拿尺寸说话：

```bash
# 主机 ~/imx-forge
ls -la out/uboot/u-boot-dtb.imx
```

```text
-rw-r--r-- 1 charliechen charliechen 1702912 Oct 20 10:06 out/uboot/u-boot-dtb.imx
```

1702912 字节，2026 年 10 月 20 日 10:06 出炉，它身体里躺着 U-Boot 2026.10-dirty (Oct 20 2026 - 10:06:51 +0800) 这行横幅，也躺着 Starting kernel ...%s 这句告别。哪天板子到手，咱们上电，听串口从横幅开始念，念到 Starting kernel ...，往后的话归内核。

## 继续学习

- [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md)：扩展卷已落成的上一篇，提示符出现前那两件事在那篇讲完。
- [启动 Linux：把内核装进板子完成交接](../12_boot_linux.md)：主线行为层对应篇，bootz 三参数的出处与排查表在那边。
- [换条路：tftp 网络加载，迭代不再反复烧卡](../13_tftp_netboot.md)：不烧卡的迭代路，板端四行命令。
- [串口日志阅读路线：从一行输出找到下一站](../../debug/03_serial_log_reading.md)：Starting kernel 之后的串口记录怎么分段读。
- [内核概述](../../kernel/00_kernel_overview.md)：交接之后的下一卷入口。
- [编译、外挂模块与 QEMU 首启验收](../../kernel/08_dts_build_boot.md)：zImage 与 dtb 的生产现场。
- [Rootfs 概述](../../rootfs/01_rootfs_overview.md)：内核挂载的那个根从哪来。
