---
title: FDT 传递：设备树怎么交到内核手里
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# FDT 传递：设备树怎么交到内核手里

> bootz 把 zImage 与设备树交给内核之前，U-Boot 还要对 FDT 动一轮手脚：内存范围按实测值重写，MAC 地址与 serial# 从环境抄进属性，/chosen 里补上 bootargs、kaslr-seed 与自家版本号，必要时把整棵树搬到内存尾部。本篇带咱们把这一轮修补的调用链在源码里走完，把串口上 Loading Device Tree 那行日志的来历翻出来，也给咱们留一套主机侧与板端都能跑的自证动作。主线 12 章在行为层把 bootz 装进板子跑通，本卷第十二篇停在提示符待人，本篇接在提示符之后，把交接那一刻的源码路径补齐。设备树本身的写法与来历归主线 08 章，bootargs 在行为层的用法归主线 11 章。

## 一、交接前 U-Boot 对 FDT 动了什么

### bootz 的交接链：从 do_bootz 到 kernel_entry

咱们按探针命令把 cmd/bootz.c 过一遍，输出原样贴在这里：

```bash
# 主机 ~/imx-forge
grep -n "fdt_fixup\|bootz_setup\|images->" third_party/uboot-mainline/cmd/bootz.c | head -8
```

```text
15:int __weak bootz_setup(ulong image, ulong *start, ulong *end)
17:	/* Please define bootz_setup() for your platform */
47:		images->ep = image_load_addr;
51:		images->ep = hextoul(argv[0], NULL);
53:			images->ep);
56:	ret = bootz_setup(images->ep, &zi_start, &zi_end);
60:	ep_addr = (phys_addr_t)images->ep);
65:		       (unsigned long long)images->ep);
```

这八行把命令的骨架交代了。do_bootz（cmd/bootz.c 第 81 行）接到 `bootz ${loadaddr} - ${fdt_addr}` 之后，第 89 行调 bootz_start，入口地址从命令行取（第 51 行）或退回装载地址（第 47 行），第 56 行交给 bootz_setup 验明正身。bootz.c 里那份是 __weak 的空壳（第 15 行），真身在 arch/arm/lib/zimage.c 第 21 行，对着 zImage 头部的 magic 常量检查，对上了把内核的起止地址抄出来交给 LMB 排程（LMB，logical memory block，启动期的内存排程器），串口上 Kernel image @ 0x82000000 那种行就是它打的（地址数字抄自主线 14 章整理的形态，第三节咱们还要回到这组数字）。

FDT（flat device tree，扁平化的设备树 blob，内核认硬件全靠它）怎么进 images 结构，这条链咱们一步步跟：靠 bootz_start 第 73 行调 bootm_find_images（boot/bootm.c 第 487 行起）再调 boot_get_fdt，blob 的地址与长度记进 images->ft_addr 与 ft_len，串口同时多一行 Booting using the fdt blob at 0x83000000（boot/image-fdt.c 第 520 行）。咱们记住分界，bootz_start 只排 START 这一个状态，剩下的活全在 bootz_run 里。boot_run 给它排 OS_PREP 与 OS_GO，配了 initrd 再添 RAMDISK（boot/bootm.c 第 1171 行起的状态表）。OS_PREP 落到 arch/arm/lib/bootm.c 第 386 行的 do_bootm_linux，它调 boot_prep_linux（同文件第 158 行），这一步是全篇的正主：

```c
	if (CONFIG_IS_ENABLED(OF_LIBFDT) && IS_ENABLED(CONFIG_LMB) && images->ft_len) {
		debug("using: FDT\n");
		if (image_setup_linux(images)) {
			panic("FDT creation failed!");
		}
	}
```

咱们对着配置验一步：OF_LIBFDT 与 LMB 在咱们的构建里都开着（out/uboot/.config 第 1902 与 1919 行），ft_len 又有值，FDT 这条路必然走。image_setup_linux（boot/image-board.c，第 940 行调修补入口）干两件事：boot_relocate_fdt 把树搬到位，image_setup_libfdt（boot/image-fdt.c 第 629 行）把修补一轮做完。搬运留在第三节，修补的清单现在摊开。

### 修补动作的全景表

| 环节 | 源码锚点 | 干了什么 |
|------|---------|---------|
| 装载识别 | boot/image-fdt.c 502 | boot_get_fdt 找到 blob，记进 ft_addr 与 ft_len |
| 搬运或就地 | boot/image-fdt.c 195 | boot_relocate_fdt 挑位置，垫 CONFIG_SYS_FDT_PAD |
| 环境命令修补 | boot/image-fdt.c 636 | env 的 fdt_fixup 当命令串执行（CONFIG_OF_ENV_SETUP 本构建未开，.config 第 447 行，AES 交接不执行） |
| 序列号写进根节点 | boot/fdt_support.c 201 | fdt_root 把 env 的 serial# 抄成根节点的 serial-number |
| chosen 补写 | boot/fdt_support.c 337 | fdt_chosen 写 bootargs、kaslr-seed、u-boot,version |
| 内存范围重写 | arch/arm/lib/bootm-fdt.c 34 | arch_fixup_fdt 调 fdt_fixup_memory_banks 改 memory 节点 |
| MAC 注入 | boot/fdt_support.c 639 | fdt_fixup_ethernet 按别名表把 env 的 MAC 抄进网口节点 |
| initrd 登记 | boot/image-fdt.c 707 | fdt_initrd 把 initrd 起止写进 chosen（有 initrd 才有值） |
| 体检与收缩 | boot/image-fdt.c 710-755 | ft_verify_fdt 校验，fdt_shrink_to_minimum 收缩，LMB 重新登记 |
| 交接 | arch/arm/lib/bootm.c 334 | r2 放 ft_addr，kernel_entry(0, machid, r2) 跳进内核 |

这张表是 image_setup_libfdt 的执行顺序，笔者顺着源码一行一行核过。ft_board_setup、ft_system_setup 与 env 的 fdt_fixup 三格在咱们的镜像里不发生，因为对应的 CONFIG_OF_BOARD_SETUP、CONFIG_OF_SYSTEM_SETUP 与 CONFIG_OF_ENV_SETUP 都没开（out/uboot/.config 第 447 到 450 行，四行 is not set），image_setup_libfdt 第 636、690 与 698 行的三处调用连编译都进不来。板级层面的修补钩子在 AES 上究竟有没有，这一节末尾咱们专门判定。

### 内存：按量出来的写

内存范围重写这条线，起点不在修补函数里，在板级文件自己的 dram_init（board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c 第 33 行起），它调 imx_ddr_size() 把 DDR 控制器量出来的实际容量写进 gd->ram_size。交接时咱们跟着数组走一趟，arch_fixup_fdt（arch/arm/lib/bootm-fdt.c 第 34 行）把 gd->dram 里每个 bank 的起点与大小抄进数组，转手交给 fdt_fixup_memory_banks（boot/fdt_support.c 第 545 行），它找到或者新建 memory 节点，把数组写进 memory 节点的 reg 属性。

静态树里那份 memory 是编译期写的（arch/arm/dts/imx6ull-aes.dtsi 第 14 到 17 行，reg 从 0x80000000 起 0x20000000，折合 512 MiB），交接那一刻被 runtime 量出来的数字对着改。咱们把话说明白：内核认内存认的是交接后那份属性，dts 里写多少不作数，板子换了内存颗粒，改的是量出来的结果，dts 不动。bank 数量由 CONFIG_NR_DRAM_BANKS 定，AES 构建里是 1（out/uboot/generated_defconfig 第 4 行），单 bank 一条 reg 记录。

### MAC 与 serial#：两条不用改代码的注入线

MAC 注入走别名表。SoC 基线 imx6ul.dtsi 第 21 到 23 行写着 ethernet0 = &fec1 与 ethernet1 = &fec2，最终 dtb 里就带着这张别名表。fdt_fixup_ethernet（boot/fdt_support.c 第 639 行）逐条扫 /aliases 下的 ethernetN，别名编号翻译成环境变量名：0 号对应 ethaddr，其余对应 ethNaddr，读到值就用 fdt_setprop 把 local-mac-address 写进别名指向的节点。AES 出厂环境三条 MAC 全备着（include/configs/mx6ull_aes_emmc.h 第 40 到 42 行，eth0addr、eth1addr、ethaddr 各一条），这条路上真正被消费的是 ethaddr 与 eth1addr，eth0addr 备而不用，因为别名 ethernet0 翻译过去的是 ethaddr 这个名字。咱们把双网口两张地址的对应关系记在这里：fec1 对 ethaddr，fec2 对 eth1addr。

serial# 这条线更长，咱们从芯片熔丝一路翻到设备树。板级复位后的初始化序列里有 INITCALL(arch_misc_init)（common/board_r.c 第 741 行），开关 CONFIG_ARCH_MISC_INIT 在咱们的构建里是 y（out/uboot/.config 第 514 行）。arch_misc_init（arch/arm/mach-imx/mx6/soc.c 第 745 行）调 setup_serial_number（同文件第 729 行），env 里没有 serial# 时，它从 OCOTP（i.MX6 的熔丝箱，出厂烧死的唯一编号）第一个 bank 读 uid_low 与 uid_high，拼成十六个十六进制字符 env_set 进 serial#（第 742 行）。交接时 fdt_root（boot/fdt_support.c 第 201 行）读 env 的 serial#，把它写成根节点的 serial-number 属性（第 214 行）。熔丝、环境、属性三站一条线，编译期不需要任何板级代码。

### 板级钩子：AES 上一件都没有

AES 板级代码里到底有没有 board_fixup 钩子，咱们拿探针直接查：

```bash
# 主机 ~/imx-forge
grep -n "fdt_addr\|board_fixup" third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c | head -5
```

输出一行没有，grep 的退出码是 1。板级 C 文件里 fdt_addr 与 board_fixup 双双零命中，ft_board_setup 又因为 CONFIG_OF_BOARD_SETUP 没开而整段缺席，AES 对交接链的全部贡献只有两处——board_init 里给 bi_boot_params 定了 PHYS_SDRAM + 0x100 当兜底落点，board_quiesce_devices 空着身位站在 bootm_final（boot/bootm.c 第 1245 行）调用的位置上（同文件第 1259 行），板级那份覆盖是空函数，注释交代它排在 dm_remove_devices_active 之前，LCDIF（i.MX6ULL 的 LCD 显示控制器）的时钟要留到显示驱动退出再关。头文件第 57 行把 fdt_addr 定成环境变量 0x83000000，与 C 文件无关。

## 二、/chosen 节点：bootargs 的快照怎么写进树

### fdt_chosen 的户口

bootm 的实现按老户口该在 common/bootm.c，咱们照跑探针，报错原样记录：

```bash
# 主机 ~/imx-forge
grep -n "chosen\|fdt_chosen" third_party/uboot-mainline/common/bootm.c | head -6
```

```text
grep: third_party/uboot-mainline/common/bootm.c: No such file or directory
```

这棵 v2026.10 树里 bootm 的实现文件都搬进了 boot/ 目录，bootm.c、bootm_os.c、image-fdt.c、fdt_support.c 全在底下。换到真户口咱们再查，boot/bootm.c 里 chosen 与 fdt_chosen 零命中，全目录搜一遍定位真正写 chosen 的人：

```bash
# 主机 ~/imx-forge
grep -rn "fdt_chosen" third_party/uboot-mainline/boot/ | head -5
```

```text
third_party/uboot-mainline/boot/fdt_support.c:329: * board_fdt_chosen_bootargs - boards may override this function to use
third_party/uboot-mainline/boot/fdt_support.c:332:__weak const char *board_fdt_chosen_bootargs(const struct fdt_property *fdt_ba)
third_party/uboot-mainline/boot/fdt_support.c:337:int fdt_chosen(void *fdt)
third_party/uboot-mainline/boot/fdt_support.c:347:		printf("fdt_chosen: %s\n", fdt_strerror(err));
third_party/uboot-mainline/boot/fdt_support.c:376:	str = board_fdt_chosen_bootargs(fdt_get_property(fdt, nodeoffset,
```

chosen 本体是设备树里一个约定节点，启动程序留给内核的留言条，bootargs、随机数种子这类一次性信息都塞在里面。fdt_chosen（boot/fdt_support.c 第 337 行）被 image_setup_libfdt 在第 655 行调起，排在 fdt_root 之后，咱们把四件事一件件点出来。头一件，fdt_find_or_add_subnode 找或建 /chosen，AES 的静态树里它已经在（imx6ull-aes.dtsi 第 10 到 12 行，stdout-path 指着 uart1），找到现成的。第二件，DM_RNG 开着（out/uboot/.config 第 1482 行）就走 fdt_kaslrseed（fdt_support.c 第 287 行）：从 UCLASS_RNG 头一个设备 dm_rng_read 读 8 字节写进 kaslr-seed 属性，AES 的 RNG 后端是 DCP（i.MX6 的数据协处理器 Data Co-Processor，片上加解密模块，内含真随机数发生器，out/uboot/generated_defconfig 第 53 行 CONFIG_FSL_DCP_RNG=y）。这个属性写进 /chosen 之后，本板这套 arm32 内核没有消费方，内核熵池走的 rng-seed 本板没写。第三件，board_fdt_chosen_bootargs（第 332 行 weak，缺省实现就是 `env_get("bootargs")`）把命令行抄进 bootargs 属性，env 为空时连属性都不设（第 379 行的 if (str) 把着门）。第四件，写 u-boot,version 属性，咱们 10 月 20 日那份镜像的版本号就此烙进 blob。

### AES 的 bootargs 从哪来

env 里的 bootargs 由 emmcbootaes 链条自己设。板级头文件第 67 行的 emmcargs 一句 setenv bootargs console=${console},${baudrate} root=/dev/mmcblk1p2 rootwait rw，console 变量在第 53 行定为 ttymxc0。第 71 行起的 emmcbootaes 在 bootz 之前 run emmcargs，变量就位，bootz 交接时 fdt_chosen 把它抄进 /chosen。咱们看这段出厂脚本的原样：

```c
"emmcargs=setenv bootargs console=${console},${baudrate} "
	"root=/dev/mmcblk1p2 rootwait rw\0" \
"emmcbootaes=echo Booting AES from eMMC ...; " \
	"run emmcargs; " \
	"mmc dev ${emmc_dev}; " \
	"run loademmcimage; " \
	"run loademmcfdt; " \
	"bootz ${loadaddr} - ${fdt_addr};\0" \
```

命令行的快照属性就此定稿，咱们记下这两个值：串口 ttymxc0、根文件系统 eMMC 第二分区。printenv bootargs 与 fdt print /chosen 里的 bootargs 一字一样，因为后者就是前者在交接那一瞬的复写。

::: warning bootargs 没进树，内核一启动就静默
后果是串口在 Starting kernel ... 之后一条内核日志都收不到，看着像内核没起。根因在 fdt_chosen 第 379 行：它只把 env 里实际存在的 bootargs 抄进 /chosen，哪次 emmcbootaes 漏跑 run emmcargs，或者 setenv bootargs 拼错清了变量，blob 里就没有 bootargs 属性，内核端取到 NULL，命令行退回内核编译期的缺省，UART 没人开口。咱们排查的动作很便宜：交接前 printenv bootargs 看一眼，交接后 fdt print /chosen 再看一眼，两处对上才算数。
:::

### 内核从哪读

寄存器层面的交接咱们摆到寄存器上看：ARM32 上是三个通用寄存器，r0 固定 0，r1 放机器编号，r2 放参数块地址（arch/arm/lib/bootm.c 第 357 行的 kernel_entry(0, machid, r2)，r2 在第 334 行取 ft_addr）。内核这头，arch/arm/kernel/head-common.S 第 141 到 142 行把 r1 存进 __machine_arch_type、r2 存进 __atags_pointer，arch/arm/kernel/devtree.c 第 192 行的 setup_machine_fdt 认下这份 dtb，随后 drivers/of/fdt.c 第 1232 行调 early_init_dt_scan_chosen（第 1090 行）扫 /chosen。它从 rng-seed 里收走随机数喂给内核熵池，用完把属性 nop 掉防止泄漏，再到第 1123 行取 bootargs：

```c
	p = of_get_flat_dt_prop(node, "bootargs", &l);
	if (p != NULL && l > 0)
		strscpy(cmdline, p, min(l, COMMAND_LINE_SIZE));
```

bootargs 由此进了内核的 boot_command_line，之后 setup_arch 的一切参数解析都从它出发。内核起来之后 /chosen 原样留在 /proc/device-tree/chosen，咱们 cat 一下 bootargs 就能和 U-Boot 那头对质（这一步归第四节标注）。

### 与直接传 bootargs 的关系

同一个 env 变量，两辆车，咱们把两辆都过一遍。FDT 这辆车刚才走完了。ATAG（ARM 老式传参协议，内核参数逐条打标签排在内存里，FDT 出现前 r2 指的就是这条链）那辆是老式通道，boot_prep_linux 的 ATAG 分支（arch/arm/lib/bootm.c 第 158 行起的另一头）把 env 的 bootargs 拷进 ATAG_CMDLINE 标签（setup_commandline_tag，同文件第 74 行起），r2 指向 bi_boot_params，AES 上就是 PHYS_SDRAM + 0x100。bootz 不带第三个参数时，help 文本（cmd/bootz.c 第 124 行）写着 If you do not pass a third argument a bd_info struct will be passed instead，ATAG 兜底一直留着。AES 的出厂链条永远带 ${fdt_addr}，所以这块板永远走 FDT 车。内核端也有兜底：/chosen 里没有 bootargs 时，early_init_dt_scan_chosen 落到 handle_cmdline，CONFIG_CMDLINE 当缺省，只有 CONFIG_CMDLINE_FORCE 才反盖 bootloader 给的（drivers/of/fdt.c 第 1127 行前后的注释自己交代了这个分层）。车换了，货没换，货就是 env 里那条 bootargs。

## 三、拷贝到安全区：Loading Device Tree 的来历

### 搬运的算法：垫 12 KiB，从顶上往下划

boot_relocate_fdt（boot/image-fdt.c 第 195 行）决定树搬不搬、搬到哪，咱们把它的两条岔路都走一遍。目标长度在第 218 行算出：树本身的大小加 CONFIG_SYS_FDT_PAD，垫的缺省 0x3000 折合 12 KiB（lib/Kconfig 第 1073 行起，帮助文本交代理由：内核可能在树尾要空地做修补）。fdt_high 没设时走第 257 行的 else 分支，逐个 DRAM bank 算 usable 等于 bank 上沿与 bootm_low 加 bootm_mapsize 两者的较小值，再拿 LMB_MEM_ALLOC_MAX 从这段的顶上往下划一块（第 277 行），第 313 行打出那行日志，第 316 行 fdt_open_into 把老树倒进新家，第 321 行补 OK。bootm_low 与 bootm_mapsize 在 AES 上缺省就是 0x80000000 加 512 MiB（boot/image-board.c 第 111 行的 env_get_bootm_low 落到 CFG_SYS_SDRAM_BASE，第 151 行的 env_get_bootm_mapsize 缺省落到第 161 行的 env_get_bootm_size()，再按 ram 上沿减 bootm_low 算出），这段 bootm 地图的顶端就是 DDR 顶端。

主线 14 章（document/tutorial/uboot/14_debug_reference.md）贴过同款形态，笔者抄三行来当形状样本，那是按代码路径整理的串口输出：

```text
## Flattened Device Tree blob at 83000000
   Booting using the fdt blob at 0x83000000
   Loading Device Tree to 0x9ff5e000, end 0x9ff65f68 ... OK
```

数字咱们算一遍。end 减 start 加一等于 0x7f69，折合 32617 字节，减掉 0x3000 的垫，blob 本体 0x4f69 折合约 19.9 KiB，正是一棵 imx6ull 板级树的大小量级。落点 0x9ff5e000 距 DDR 上沿 0xA0000000 差 0xA2000，折合 648 KiB。大小这一头对得上，end 减 start 加一正是前一步算出的目标长度，这行字的来历就是 boot_relocate_fdt 第 313 行那一个 printf。落位这一头对不上，按第 277 行的算法应贴 usable 上沿（end 约 0x9fffff68），样本停在距上沿约 0x9A000 处，属主线 14 章那份整理形态的取位，不拿它当算法证据。

### AES 的出厂开关把这步关了

fdt_high 一设，第 221 行 env_get 拿到值，等于 ~0UL 时第 225 行直接换道：不搬，第 306 行 fdt_set_totalsize 就地把树的 totalsize 扩成目标长度，把树尾的垫圈进来，第 307 行打 Using Device Tree in place，第 229 行还先打一串 WARNING，原话说 fdt_high 设成 ~0 已知会因设备树摆在对齐不足的地址上引发启动失败。AES 出厂环境恰恰设着 fdt_high=0xffffffff（include/configs/mx6ull_aes_emmc.h 第 54 行），32 位平台 ulong 四字节，0xffffffff 就是 ~0UL。所以咱们这块板真跑 run emmcbootaes，串口该出现的是 WARNING 加 in place，主线 14 章那份 Loading Device Tree to 的形态轮不到。两条串都在镜像里，咱们 strings 指认：

```bash
# 主机 ~/imx-forge
strings out/uboot/u-boot | grep -E "Loading Device Tree|Using Device Tree in place|fdt_high"
```

```text
fdt_high
The 'fdt_high' environment variable is set to ~0. This is known to cause
This system will likely fail to boot. Unset the 'fdt_high' environment
   Using Device Tree in place at %p, end %p
   Loading Device Tree to %p, end %p ... 
fdt_high=0xffffffff
fdt_high 
```

咱们补一句判断，image-fdt.c 的两个分支没有条件编译隔开，代码把两条路都编了进去。运行时谁说话，由 env 里的 fdt_high 定，AES 上源头就是头文件第 54 行那个 0xffffffff。

### 为什么要搬到尾部

咱们把这张地图摆开看，bootm 地图（bootm_low 到 bootm_low 加 bootm_mapsize 圈出的那段）是内核、initrd、DTB 三方共用的安置区，LMB 管着谁占哪段、互不重叠。bootm_find_images 里 check_overlap 对 FDT 与内核身体做重叠检查，真重叠了当场报 `ERROR: FDT image overlaps OS image (OS=lx..lx)` 一类错误并把启动拦停。blob 自己声明的 memreserve 与 reserved-memory 也被尊重：boot_fdt_add_mem_rsv_regions（boot/image-fdt.c 第 167 行）把这些区域登记进 LMB，initrd 与 DTB 排位时绕开。树被搬到地图顶端，理由不玄：内核 zImage 解压后的身体比 zImage 大出数倍，解压写入落在低端内存，树若停在身体将要铺开的地方，一轮解压就把属性盖花。顶端离内核身体最远，被盖的风险最小。

AES 就地摆放还能成立，靠的是距离。zImage 在 0x82000000，身体到 0x82681680（主线 14 章那组数字），blob 在 0x83000000，中间隔约 9.5 MiB（0x83000000 − 0x82681680 = 0x97E980），树尾还留着 12 KiB 的垫。咱们把这段当设计意图理解，真板校验归第四节的自证动作。

## 四、自证：板上一遍，主机一遍

### 板端：fdt print /chosen

交接后树里多了什么，板上能直接看，咱们分两步看。AES 镜像编着 fdt 命令（cmd/Kconfig 第 574 行起给 CMD_FDT 默认 y，依赖 OF_LIBFDT，构建产物 out/uboot/.config 第 614 行在册），动作两步：

```bash
# 板端 /
fdt addr 0x83000000
fdt print /chosen
```

四个属性咱们逐个对：stdout-path 是 dtsi 里带来的，bootargs、kaslr-seed、u-boot,version 是 fdt_chosen 补的。根节点上另有 serial-number（fdt_root 写的），fdt print / 能看到。内核起来之后还有一条路：/proc/device-tree/chosen/bootargs 原样留着，cat 出来与 printenv bootargs 对质。

### 主机侧：修补链一 grep 到位

全链的函数名与位置，笔者一次抓出来，输出真实：

```bash
# 主机 ~/imx-forge
grep -rn "int image_setup_libfdt\|boot_relocate_fdt(char\|int fdt_chosen\|int fdt_root\|int arch_fixup_fdt\|void fdt_fixup_ethernet\|int fdt_fixup_memory_banks\|int bootz_setup\|void board_quiesce_devices" third_party/uboot-mainline/boot/ third_party/uboot-mainline/arch/arm/lib/ third_party/uboot-mainline/cmd/bootz.c
```

```text
third_party/uboot-mainline/boot/fdt_support.c:201:int fdt_root(void *fdt)
third_party/uboot-mainline/boot/fdt_support.c:337:int fdt_chosen(void *fdt)
third_party/uboot-mainline/boot/fdt_support.c:545:int fdt_fixup_memory_banks(void *blob, u64 start[], u64 size[], int banks)
third_party/uboot-mainline/boot/fdt_support.c:639:void fdt_fixup_ethernet(void *fdt)
third_party/uboot-mainline/boot/bootm.c:50:__weak void board_quiesce_devices(void)
third_party/uboot-mainline/boot/image-fdt.c:195:int boot_relocate_fdt(char **of_flat_tree, ulong *of_size)
third_party/uboot-mainline/boot/image-fdt.c:624:__weak int arch_fixup_fdt(void *blob)
third_party/uboot-mainline/boot/image-fdt.c:629:int image_setup_libfdt(struct bootm_headers *images, void *blob, bool lmb)
third_party/uboot-mainline/arch/arm/lib/bootm-fdt.c:34:int arch_fixup_fdt(void *blob)
third_party/uboot-mainline/arch/arm/lib/zimage.c:21:int bootz_setup(ulong image, ulong *start, ulong *end)
```

行序随目录遍历走，复跑可能不同，以内容为准。十行把全链的名与位次摆齐，咱们逐行点一遍名。arch_fixup_fdt 在 image-fdt.c 第 624 行有个 __weak 缺省版，直接返回 0，ARM 用 bootm-fdt.c 第 34 行的同名实版本把它顶掉，弱符号让位给强符号，链上其余函数都是单点。全篇探针共六发，按文中先后是 cmd/bootz.c 的骨架、板级 C 文件零命中、common/bootm.c 的报错、chosen 的户口纠正到 boot/fdt_support.c 第 337 行、strings 指认出厂分支、这一节的合并 grep。板子到手那天，拿第一节的全景表对着 fdt print 的打印逐项核，属性多一个少一个都能在表里找到出处。

## 继续学习

- [启动 Linux：把内核装进板子完成交接](../12_boot_linux.md)：bootz 在行为层的完整现场，本篇翻的是它的源码底盘。
- [设备树：imx6ull-aes 从参考板改到了咱们的板子](../08_device_tree_aes.md)：chosen 与 memory 节点的出生地，两棵源码树同名不同命在那篇分清。
- [调试命令速查：命令行是嵌入式开发的神器](../14_debug_reference.md)：Loading Device Tree 那组串口形态的出处，fdt 命令的用法也在那篇。
- [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md)：本卷上一篇，提示符出现之前 env 与倒计时的源码路径。
- [环境变量与 bootcmd：U-Boot 的行为由谁来定](../11_env_bootcmd.md)：bootargs、setenv 与 saveenv 在行为层的实作。
- [换条路：tftp 网络加载，迭代不再反复烧卡](../13_tftp_netboot.md)：网络路线同样要传 fdt，只是加载动作换了来源。
