---
title: bootz 解析 zImage：内核镜像的头与肚
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# bootz 解析 zImage：内核镜像的头与肚

> 本篇解决一件事：主线 12 章里咱们敲下的 bootz ${loadaddr} - ${fdt_addr}，U-Boot 在这里面到底干了什么。它凭什么认出 0x82000000 处那串字节是一份能跑的内核，三个地址从哪进来，两份东西在内存里叠住时谁报警，本篇把这些问题全部追到源码行。它接在主线交接章与扩展卷 [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md) 之后，前面几篇讲的是 U-Boot 自己怎么活下来，从 Boot ROM 挑介质一路走到提示符出现，本篇往后挪一步，看它怎么把内核接出门。内核侧的 zImage 怎么生产、解压代码怎么跑，归内核卷，本篇的边界定在 U-Boot 怎么对待这份镜像。

## 一、bootz 吃的是什么：zImage 的自解压结构

咱们把问题摆得具体一点。bootz 敲下去，U-Boot 手里只有三个位置参数，内存里 0x82000000 起躺着 10369960 个字节，bmp 也好、乱码也好，都是字节，它凭什么认出这是一份内核？答案藏在文件最开头的 48 个字节里，咱们拿自己那份 10 月 12 日的产物，把原始字节翻出来：

```bash
# 主机 ~/imx-forge
ls -la ~/experiments/linux-build/arch/arm/boot/zImage
hexdump -C -n 64 ~/experiments/linux-build/arch/arm/boot/zImage
```

```text
-rwxr-xr-x 1 charliechen charliechen 10369960 Oct 12 08:44 /home/charliechen/experiments/linux-build/arch/arm/boot/zImage
00000000  00 00 a0 e1 00 00 a0 e1  00 00 a0 e1 00 00 a0 e1  |................|
*
00000020  05 00 00 ea 18 28 6f 01  00 00 00 00 a8 3b 9e 00  |.....(o......;..|
00000030  01 02 03 04 45 45 45 45  68 63 00 00 00 90 0f e1  |....EEEEhc......|
```

咱们把头 48 个字节念完。0x00 到 0x1f 八个字清一色 0xe1a00000，ARM 的 mov r0, r0，什么都不干，纯垫场。第九个字落在 0x20，是 0xea000005，一条向前跳的转移指令，按 ARM 的算法算落点，0x20 加 8 再加偏移乘 4，正好跳到 0x3c，把说明书区整个让开。0x30 到 0x3b 的十二个字节已经出了头，归肚子，本篇不展开，0x3c 那个字按编码读出 0xe10f9000，mrs r9, cpsr，把状态寄存器读进 r9，自解压代码的第一句从这里起头。跳转自己落在 0x20，越过三张说明书页落到 0x3c。0x24 的 18 28 6f 01 按小端读出 0x016f2818，这就是 zImage 的魔数，0x28 的四个零是 zi_start，0x2c 的 a8 3b 9e 00 读出 0x9e3ba8，折成十进制 10369960，跟 ls 报的文件大小一字不差。

U-Boot 侧的读法住在 arch/arm/lib/zimage.c，咱们把判据与结构体一起翻出来：

```c
#define	LINUX_ARM_ZIMAGE_MAGIC	0x016f2818
#define	BAREBOX_IMAGE_MAGIC	0x00786f62

struct arm_z_header {
	uint32_t	code[9];
	uint32_t	zi_magic;
	uint32_t	zi_start;
	uint32_t	zi_end;
} __attribute__ ((__packed__));
```

code[9] 九个字收着垫场与跳转，后三个字段对着 magic、zi_start、zi_end，`__packed__` 让结构体不补任何空隙，U-Boot 把加载地址往这个结构体上一套，每个字段都对得上刚才的字节。咱们把头与肚的分界也划在这里：头是跳板加说明书，肚是压缩的内核本体加上随身携带的解压代码。自解压三个字的意思就落在这份代码里，解压程序不靠外人提供，它自己编在镜像里，内核自己把自己解开。U-Boot 的分工因此很省事，它不解压，不看肚子里写了什么，它认头、读跨度、把控制权送到位，解压这场戏要等 CPU 跳进 0x3c 之后才开演。

有一处字节咱们照实记录，不加粉饰。这份产物的 zi_start 写的是 0，zi_end 是文件大小，头里报的跨度是 0 到 0x9e3ba8，U-Boot 实际拿用的正是这个差值，zi_end 减 zi_start 等于 10369960 字节，第二节占内存时用的就是它。内核为什么把 start 填成 0，那是内核卷的工艺，本篇按字节如实记录，不代答。

bootz 之外，同目录还躺着 booti，它也能交内核，区别一句话讲完：zImage 自带解压代码、认魔数，booti 吃没压缩的原生 Image，镜像里没有魔数，U-Boot 按入口地址直接交。咱们拿 `grep -n "CONFIG_CMD_BOOTI" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig` 搜过自己的 defconfig，输出为空，booti 没编进固件，AES 板吃得上的只有 bootz。

| 命令 | 吃的镜像 | U-Boot 怎么认它 |
|---|---|---|
| bootz | zImage，自解压 | 认 0x016f2818 魔数，跨度从头部读出 |
| booti | 原生 Image，未压缩 | 没有魔数可认，按入口地址直接交接 |

0x3c 之后肚子里的活怎么干，归内核卷，咱们在那边看过它出炉，本篇只从 U-Boot 的视角讲到交棒为止。

## 二、bootz 的源码路径：cmd/bootz.c 从命令到状态机

### 命令的户口与编译开关

函数链咱们一次抓全，两条命令的输出按顺序排好：

```bash
# 主机 ~/imx-forge
grep -n "bootz_start\|do_bootz\|bootz_setup" third_party/uboot-mainline/cmd/bootz.c | head -8
grep -n "CONFIG_CMD_BOOTZ" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
15:int __weak bootz_setup(ulong image, ulong *start, ulong *end)
17:	/* Please define bootz_setup() for your platform */
26:static int bootz_start(struct cmd_tbl *cmdtp, int flag, int argc,
56:	ret = bootz_setup(images->ep, &zi_start, &zi_end);
81:int do_bootz(struct cmd_tbl *cmdtp, int flag, int argc, char *const argv[])
89:	if (bootz_start(cmdtp, flag, argc, argv, &images))
130:	bootz,	CONFIG_SYS_MAXARGS,	1,	do_bootz,
25:CONFIG_CMD_BOOTZ=y
```

末行的 25:CONFIG_CMD_BOOTZ=y 是 defconfig 的开关。八行输出里住着 bootz 的全套人马，130 行的 U_BOOT_CMD 把 bootz 注册进命令表，回调挂 81 行的 do_bootz，干活主力是 26 行的 bootz_start。编译这边两道开关把守，defconfig 第 25 行之外还有 cmd/Makefile 第 40 行的 obj-$(CONFIG_CMD_BOOTZ) += bootz.o，开关合上 bootz.o 才进产物。自家构建里这份命令真的在，咱们拿 strings 指认过：

```bash
# 主机 ~/imx-forge
strings out/uboot/u-boot | grep "boot Linux zImage" | head -2
```

```text
    - boot Linux zImage stored in memory
boot Linux zImage image from memory
```

bootz.c 第 15 行那个 bootz_setup 咱们多看一眼，它挂着 `__weak` 标记，是留给各芯片自己接手的钩子，没人接手时打印 Your platform's zImage format isn't supported yet! 然后回 -1。ARM 侧的真身在 zimage.c，第一节刚读过它的判据，bootz_start 第 56 行调的正是它。

### bootz_start：认头、占内存、找同伴

26 行的 bootz_start 是 bootz 的第一站，咱们按它干的三件事往下读。第一件收参数，34 到 41 行把命令行的三个位置参数摆进 bootm_info 这个参数包，addr_img 收第 0 个，conf_ramdisk 收第 1 个，conf_fdt 收第 2 个，随后 43 行 bootm_run_states(&bmi, BOOTM_STATE_START) 把状态机的 START 一拍记下。第二件定内核地址，45 到 54 行原文如下：

```c
	/* Setup Linux kernel zImage entry point */
	if (!argc) {
		images->ep = image_load_addr;
		debug("*  kernel: default image load address = 0x%08lx\n",
				image_load_addr);
	} else {
		images->ep = hextoul(argv[0], NULL);
		debug("*  kernel: cmdline image address = 0x%08lx\n",
			images->ep);
	}
```

命令没带地址参数时内核入口取 image_load_addr，带了就 hextoul 当场把十六进制文本换算成数，这条优先序第三节专门展开。第三件认头加占内存，56 行 bootz_setup 把加载地址递给 zimage.c，魔数对不上它回 1，bootz_start 跟着回 1，bootz 当场收工。对上了，zi_start 与 zi_end 被填出来，60 到 67 行咱们拿这个跨度去占内存：

```c
	ep_addr = (phys_addr_t)images->ep;
	ret = lmb_alloc_mem(LMB_MEM_ALLOC_ADDR, 0, &ep_addr, zi_end - zi_start,
			    LMB_NONE);
	if (ret) {
		printf("Failed to allocate memory for the image at %#llx\n",
		       (unsigned long long)images->ep);
		return 1;
	}
```

LMB 是 U-Boot 的内存登记处，lib/lmb.c 第 762 行的 lmb_alloc_mem 收到固定地址的申请（LMB_MEM_ALLOC_ADDR），第 781 行转给第 737 行的 _lmb_alloc_addr，逐段核对这段区间是否整个落在已登记的可用内存里、是否压到任何已保留的区间，核对不过返回负数，bootz.c 第 64 行的 printf 当场报 Failed to allocate memory for the image at 加载地址。占住地盘还不算完，69 行起有一段容易被略过的注释，咱们把它念出来：Handle the BOOTM_STATE_FINDOTHER state ourselves as we do not have a header that provide this informaiton（源文件里 informaiton 这个词本身拼错了，provide 也没变三单，引文照原文保留）。旧格式 uImage 的头里写着 ramdisk 与 fdt 在哪，zImage 的头没有这张组件表，bootz 只能自己当这个班，73 行调 bootm_find_images，把 ramdisk 与设备树挨个找出来再核对重叠。参数里的 cmd_arg1 与 cmd_arg2 出自 include/command.h 第 70 行的 cmd_arg_get，参数缺席时返回 NULL，不会拿野地址去查。

### do_bootz：补全档案然后交棒

images 这个全局是 bootm 家族共用的档案，定义在 boot/bootm.c 第 48 行，注释写着 pointers to os/initrd/fdt images，include/image.h 第 431 行 extern 给全家共用。bootz 在哪些行碰它，咱们搜出来看：

```bash
# 主机 ~/imx-forge
grep -n "images" third_party/uboot-mainline/cmd/bootz.c | head -5
```

```text
27:		       char *const argv[], struct bootm_headers *images)
47:		images->ep = image_load_addr;
51:		images->ep = hextoul(argv[0], NULL);
53:			images->ep);
56:	ret = bootz_setup(images->ep, &zi_start, &zi_end);
```

内核入口 ep 从 47 与 51 行写进档案，56 行认头用的也是它，随后的组件查找结果记在同一份档案上。81 行的 do_bootz 接手收尾，咱们把 86 到 98 行逐行读一遍：

```c
	/* Consume 'bootz' */
	argc--; argv++;

	if (bootz_start(cmdtp, flag, argc, argv, &images))
		return 1;

	/*
	 * We are doing the BOOTM_STATE_LOADOS state ourselves, so must
	 * disable interrupts ourselves
	 */
	bootm_disable_interrupts();

	images.os.os = IH_OS_LINUX;
```

咱们把这几行串起来。命令名 bootz 自己被从参数表里消费掉，这是 U-Boot 命令的惯例，bootz_start 全过之后，96 行关中断，98 行给 images.os.os 填上 IH_OS_LINUX——zImage 的头里同样没有 OS 类型字段，bootz 知道自己只交 Linux，替档案补上这一格。109 行 bootz_run(&bmi) 把棒递出去，它在 boot/bootm.c 第 1187 行，正文一行，`boot_run(bmi, "bootz", 0)`，状态机从 OS_PREP 一路推到 OS_GO，修补 FDT、清场、跳转三件事在那一程轮番上场，主线 12 章已经拿 boot_jump_linux 与 kernel_entry(0, machid, r2) 把那条路走完，本篇不重走。

## 三、地址从哪来：loadaddr 与 fdt_addr 的优先序

### loadaddr 的三层来源

内核地址的取值，bootz_start 那个 if 分岔给出了骨架：带了参数就 hextoul 当场定，没带就取 image_load_addr。这个全局的正身在 boot/image-board.c，咱们把证据链一次抓出来：

```bash
# 主机 ~/imx-forge
grep -n "image_load_addr = CONFIG_SYS_LOAD_ADDR\|U_BOOT_ENV_CALLBACK(loadaddr" third_party/uboot-mainline/boot/image-board.c
grep -n "loadaddr" third_party/uboot-mainline/include/env_default.h
grep -n "CONFIG_SYS_LOAD_ADDR" out/uboot/.config
```

```text
91:ulong image_load_addr = CONFIG_SYS_LOAD_ADDR;	/* Default Load Address */
109:U_BOOT_ENV_CALLBACK(loadaddr, on_loadaddr);
86:	"loadaddr="	__stringify(CONFIG_SYS_LOAD_ADDR)"\0"
227:CONFIG_SYS_LOAD_ADDR=0x82000000
```

咱们把四行证据咬成一条链。第 91 行给 image_load_addr 配的缺省是编译期的 CONFIG_SYS_LOAD_ADDR，第 109 行给环境变量 loadaddr 登记了一个回调，on_loadaddr 在第 95 行，环境变量一被创建或改写，image_load_addr 当场跟着换数。env_default.h 第 86 行把 loadaddr 的缺省文本也接在同一个宏上，out/uboot/.config 第 227 行落出 0x82000000。优先序因此摆成三层：命令行参数盖过环境变量 loadaddr，loadaddr 盖过编译缺省 0x82000000。AES 头文件第 69 行的 loademmcimage 把 zImage 读进 ${loadaddr}，随后 bootz ${loadaddr} 把同一个地址显式递回去，读进哪个地址就交哪个地址，串口现场不会出现两套说法。在板上想换落点，setenv loadaddr 这类改法主线 11 章演练过，改的就是这个回调的输入。

### fdt_addr 靠脚本显式摆进参数位

fdt_addr 的待遇跟 loadaddr 不同，咱们拿 `grep -rn "U_BOOT_ENV_CALLBACK(fdt_addr" third_party/uboot-mainline/` 全树搜过，输出为空，它没有回调链，它也不进 env_default.h 的缺省表。0x83000000 这个值写在 AES 头文件第 57 行，ext4load 把 dtb 读进这个地址，脚本再把同一个值显式摆进 bootz 的第三个参数位。bootz_start 第 39 到 40 行把它装进 conf_fdt，找树时 select_fdt（boot/image-fdt.c 第 346 行）拿它 hextoul（第 383 行）。还有一层值得点名：咱们这份构建把 FIT 关着（FIT 是 U-Boot 的打包镜像格式，把内核、设备树、ramdisk 连同清单装进一个文件，out/uboot/.config 第 391 行 # CONFIG_FIT is not set），select_fdt 编出来只剩一个 if (select) 块，else 分支整段被裁掉，第三个参数缺席时 fdt_addr 没有任何一路赋值——头文件第 71 与 81 行的 emmcbootaes 与 sdbootaes 两个启动脚本从不给它缺席的机会，中间那槽写连字符只空 initrd，fdt 这一槽永远填 ${fdt_addr}。

### 两道重叠检查

内核落点与设备树落点的距离，主线 12 章算过：zImage 尾巴 0x829e3ba8，fdt 0x83000000，空隙 0x61c458，约合 6.11 MiB。咱们把这 6 MiB 的来历讲清，它有源码撑着。头一道检查在 bootz_start 自己手里，lmb_alloc_mem 的固定地址申请逐段核对重叠，压到保留区当场回错。咱们再看第二道，它住在 bootm_find_images 里，boot/bootm.c 第 466 行的 check_overlap 拿两份区间的头尾做判断：

```c
	if ((base >= os_start && base < os_end) ||
	    (end > os_start && end <= os_end) ||
	    (base < os_start && end >= os_end)) {
		printf("ERROR: %s image overlaps OS image (OS=%lx..%lx)\n",
		       name, os_start, os_end);

		return -EXDEV;
	}
```

咱们按三条读这段条件：谁的头部进了内核的地界，谁的尾部压了内核的地界，或者一方整个包住另一方，命中任何一条就报 ERROR: FDT image overlaps OS image 这样的错，ramdisk 与 FDT 各查一遍。6 MiB 的空隙就是给这两道检查留的余量。

::: warning 手改 fdt_addr 之前拿区间算一遍
后果是交接当场回错，或者换一种更难查的故障形态，内核与设备树在内存里互相覆盖，启动到一半行为错乱。根因是 bootz 占内存与查重叠都以区间为单位，zi_end 减 zi_start 算出的区间是内核的地界，fdt_addr 加 dtb 长度算出的区间落进去就触发上面那段 printf。哪天换了大内核或者想挪 dtb，咱们把新值跟 0x82000000 加镜像大小算出的区间比一遍再上电。板端这套动作本环境没有条件实测，机制证据全部来自上述源码行。
:::

## 四、自证：源码侧核对与板端对照

自证的办法是拿串口现场跟源码行对号，咱们把板端会碰到的两句打印全找到出处。板端动作就两行：

```bash
# 板端 /
iminfo ${loadaddr}
bootz ${loadaddr} - ${fdt_addr}
```

头一句的出处咱们抓出来，iminfo 跟 bootm 住同一个屋檐下，判据全在 cmd/bootm.c：

```bash
# 主机 ~/imx-forge
grep -n "static int image_info\|Unknown image format\|iminfo," third_party/uboot-mainline/cmd/bootm.c
strings out/uboot/u-boot | grep "Kernel image @"
```

```text
24:static int image_info(unsigned long addr);
279:static int image_info(ulong addr)
342:		puts("Unknown image format!\n");
351:	iminfo,	CONFIG_SYS_MAXARGS,	1,	do_iminfo,
Kernel image @ %#08lx [ %#08lx - %#08lx ]
```

279 行的 image_info 拿地址上的字节判格式，判据分三路：旧格式 uImage 头、Android 头、FIT，三路都判不上就走 342 行的兜底。咱们拿它对照 zImage，正好能看出两套判据的分工：iminfo 认的是带头或者打包过的镜像，zImage 的 0x016f2818 不在它的判据里，板端把 ${loadaddr} 递给 iminfo，预期走到兜底打印 Unknown image format!。认 zImage 的判据住在 zimage.c，两边不住一个屋檐下，各有各的户口。

第二句出自 bootz 自己。zimage.c 第 35 行那根 printf 等着运行时填三个数，格式串编在咱们自己的产物里，咱们拿 strings 把它抓了出来。按第一节的字节，三个数该是 0x82000000、0x0 与 0x9e3ba8，镜像地址、头部报的起点与终点，板子到手那天敲下 bootz ${loadaddr} - ${fdt_addr}，串口该把它念出来。

主机侧的每一步咱们都留了可复现的命令。认头判据与结构体，咱们读的是 arch/arm/lib/zimage.c。头部字节拿 hexdump -C -n 64 对着自己那份 zImage 核一遍，跨度拿 zi_end 减 zi_start 跟 ls 报的字节数对。函数链与 images 填充点用第二节的 grep 就能复现，编译开关落在 defconfig 第 25 行和 cmd/Makefile 第 40 行。哪一步对不上，顺着那一步的行号回源码。

## 继续学习

- [启动 Linux：把内核装进板子完成交接](../12_boot_linux.md)：主线交接章，bootz 的行为层用法与 Starting kernel 现场在那边。
- [换条路：tftp 网络加载，迭代不再反复烧卡](../13_tftp_netboot.md)：内核换个进内存的路，地址这一套照旧。
- [编译、外挂模块与 QEMU 首启验收](../../kernel/08_dts_build_boot.md)：zImage 的生产现场，头与肚的内核侧工艺归它。
- [串口日志阅读路线：从一行输出找到下一站](../../debug/03_serial_log_reading.md)：交接之后的串口记录怎么分段判读。
- [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md)：本卷上一篇，提示符怎么出现在串口上。
