---
title: env 加载与倒计时：接管前的最后准备
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# env 加载与倒计时：接管前的最后准备

> U-Boot 本体接手之后、提示符出现之前，中间还排着两件事：环境变量什么时候真正从 eMMC 读进来，倒计时在源码里怎么转。本篇带咱们把这两件事的路径走完。env_init 在重定位前给后端登记，env_relocate 在驱动就绪后去存储里把 8 KB 读回来，读坏了回落内置缺省，倒计时住在 common/autoboot.c，一秒一片地扫串口按键。主线 11 章讲的是行为层，printenv 列出的那批变量怎么改板子的脾气，本篇往源码里再下一层。主线 01 章把这一卷分四段，第二段的 _start 与异常向量由 [从 _start 开始：U-Boot 的第一条指令](05_entry_and_vectors.md) 立起，第三段的搬家在 [链接地址与运行地址对不上的日子](07_relocation_limits.md) 落了地。本篇接在搬家之后，走第三段的后半程，时刻表排在第四节，每一格都挂着源码锚点。

## 一、env 什么时候加载：env_init 与 env_relocate 在序列里的位置

### env_init 在重定位之前

env 后端有多少个，咱们打开目录自己数，每样介质一个同名文件：

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/env/ | head -12
```

```text
Kconfig
Makefile
attr.c
callback.c
common.c
eeprom.c
embedded.c
env.c
ext4.c
fat.c
flags.c
flash.c
```

咱们数下来，头 12 个条目里 env.c 是调度中枢。启用哪些后端由它里面的 env_locations[] 表说了算，CONFIG_ENV_IS_IN_MMC 这类开关把对应位置编进表里，AES 的这枚开关在 defconfig 第 46 行，后面第四节的环境字符串取证会回到这里。

env_init 的位置，咱们照章在重定位后的序列文件里搜，结果只有一行：

```bash
# 主机 ~/imx-forge
grep -n "env_relocate\|env_init" third_party/uboot-mainline/common/board_r.c | head -5
```

```text
451:		env_relocate();
```

env_init 在 board_r.c 里零命中，这个搜一半的结果本身就是线索：它不住在重定位后的序列里。咱们换个文件再搜，连串口那几行一起带出来：

```bash
# 主机 ~/imx-forge
grep -n "INITCALL(env_init)\|INITCALL(init_baud_rate)\|INITCALL(serial_init)\|INITCALL(console_init_f)\|INITCALL(display_options)" third_party/uboot-mainline/common/board_f.c
```

```text
959:	INITCALL(env_init);		/* initialize environment */
960:	INITCALL(init_baud_rate);	/* initialze baudrate settings */
961:	INITCALL(serial_init);		/* serial communications setup */
962:	INITCALL(console_init_f);	/* stage 1 init of console */
963:	INITCALL(display_options);	/* say that we are here */
```

咱们在第 959 行逮到 env_init，它排在串口初始化前面，干的是登记活：按优先级把每个后端标记进 gd 的 env_has_init 位图，gd 是 U-Boot 启动全程共用的全局数据结构（global_data），启动各步的中间状态都记在它身上。env/mmc.c 末尾 572 行的 U_BOOT_ENV_LOCATION(mmc) 连 init 钩子都没挂，只登记 load、save、erase 三个入口，钩子为空时 env.c 第 331 行的条件照样把位置记上。此时一个字节都还没读，真正的读取留给重定位之后。这轮 grep 还顺手交代了另一件事：console_init_f 在 962 行，一级控制台在这一步就绪，963 行的 display_options 打出 U-Boot 版本行，那是串口上出现的第一句 U-Boot 自己的话。

### 重定位后的序列与 MMC 后端

重定位之后轮到 board_r.c 的 initcall 序列，关键几行的行号咱们一次抓出来：

```bash
# 主机 ~/imx-forge
grep -n "INITCALL(initr_reloc)\|INITCALL(initr_dm)\|INITCALL(serial_initialize)\|INITCALL(initr_mmc)\|INITCALL(initr_env)\|INITCALL(console_init_r)\|INITCALL(initr_net)\|INITCALL(run_main_loop)" third_party/uboot-mainline/common/board_r.c
```

```text
602:	INITCALL(initr_reloc);
630:	INITCALL(initr_dm);
659:	INITCALL(serial_initialize);
704:	INITCALL(initr_mmc);
712:	INITCALL(initr_env);
734:	INITCALL(console_init_r);	/* fully init console as a device */
765:	INITCALL(initr_net);
776:	INITCALL(run_main_loop);
```

顺序不是随手排的。咱们按行号把这段序列读一遍：602 行 initr_reloc 把重定位标记翻上，630 行 initr_dm 扫一遍驱动模型并自动探测，704 行 initr_mmc 把 MMC 登记进来（串口打 MMC: 开头一行），712 行才轮到 initr_env。env 排在 MMC 后面是硬依赖：MMC 后端要从 eMMC 读数据，卡没登记好就无处可读。initr_env 的正文（board_r.c 447 行起）主活只有一句，should_load_env() 放行就调 env_relocate()，451 行正是 probe 里那一行，不放行就直接 env_set_default。env_relocate（env/common.c 603 行起）再看 gd->env_valid 的脸色，有效走 env_load()，无效直接回落缺省。

env_load（env/env.c 172 行起）按优先级调 drv->load()。AES 配置里编进表的是 ENVL_MMC，落到 env/mmc.c 的 env_mmc_load_singular：器件号问 mmc_get_env_dev()（arch/arm/mach-imx/mx6/soc.c 第 530 行，ENV 器件跟启动器件走，主线 11 章核过这条），落点与长度由 defconfig 两行给，咱们直接抄：

```bash
# 主机 ~/imx-forge
grep -n "BOOTDELAY\|BOOTCOMMAND\|ENV_SIZE\|ENV_OFFSET\|ENV_IS_IN_MMC\|MMC_DEVICE_INDEX" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
6:CONFIG_ENV_SIZE=0x2000
8:CONFIG_ENV_OFFSET=0x400000
16:CONFIG_BOOTDELAY=-1
17:CONFIG_USE_BOOTCOMMAND=y
18:CONFIG_BOOTCOMMAND="echo Current do not autoboot"
46:CONFIG_ENV_IS_IN_MMC=y
48:CONFIG_ENV_MMC_DEVICE_INDEX=1
```

0x2000 是 8 KB 的读取窗口，0x400000 是落点，折合 4 MiB。避让推理在主线 06 章[净源码里没有咱们的板卡：官方参考配置逐行对账](../06_aes_vs_evk_diff.md)与 10、11 章逐层立过：老偏移 0xC0000 折合 768 KiB，整段落在一千六百多 KiB 的镜像身体里，挪到 4 MiB 之后，跟镜像身体之间隔出两 MiB 多的余量。读回的动作在串口上有痕迹，env_mmc_load_singular 打 Reading from MMC(1)...，读成功 env_load 再补一行 Loading Environment from MMC... OK（env/env.c 第 200 行）。这几句字符串第四节咱们拿自己的镜像一一对上。第 16 行那个 -1 留给第二节，它是那节的主角。

### CRC 对不上时回落到哪

读回来的数据咱们信不信，裁决在 env_import（env/common.c 443 行起）。头 4 字节是整段数据区的 CRC32（env_internal.h 里 env_t 结构的注释写着 CRC32 over data bytes，主线 11 章引过），判断就三行：

```c
	if (crc32(0, ep->data, ENV_SIZE) != crc) {
		env_set_default("bad CRC", 0);
		return -ENOMSG; /* needed for env_load() */
	}
```

CRC 对不上，U-Boot 不罢工。env_set_default（env/common.c 388 行起）打一行 *** Warning - bad CRC, using default environment，然后把编译期内置缺省整表导入：defconfig 那几行、人人同款的 baudrate，加上 AES 头文件 CFG_EXTRA_ENV_SETTINGS 那一大段（回收主线 11 章）。回落之后还有一层安排，咱们在 env_load 里读到：坏 CRC 的位置被记进 gd->env_load_prio（env/env.c 204 到 207 行挑位置，222 到 227 行落定），下次 saveenv 照旧写回 MMC 原位，写一次 CRC 头就修复，复电不再刷警告。此时的缺省环境只活在内存里，跟存储还没关系。

## 二、倒计时的实现：一秒一片的按键扫描

### Hit any key 的户口

咱们把倒计时这行字的出处搜出来。autoboot.c 里搜一遍，函数与字符串一次带出：

```bash
# 主机 ~/imx-forge
grep -n "abortboot\|Hit any key" third_party/uboot-mainline/common/autoboot.c | head -8
```

```text
342:static int abortboot_key_sequence(int bootdelay)
373:	printf(ANSI_CLEAR_LINE "\rHit any key to stop autoboot: %d", bootdelay);
376:static int abortboot_single_key(int bootdelay)
418:static int abortboot(int bootdelay)
424:			abort = abortboot_key_sequence(bootdelay);
426:			abort = abortboot_single_key(bootdelay);
498:		 (stored_bootdelay != -1 && !abortboot(stored_bootdelay)))) {
```

Hit any key 的户口咱们翻出来就在 373 行，print_boot_delay 的函数体只有一行：

```c
static void print_boot_delay(int bootdelay)
{
	printf(ANSI_CLEAR_LINE "\rHit any key to stop autoboot: %d", bootdelay);
}
```

ANSI_CLEAR_LINE 加回车符，每次打印把终端当前行擦掉再从行首重打，咱们看到的倒计时数字一秒减一格，靠的就是同一行反复重印，没有别的魔法。

418 行的 abortboot 是总闸，bootdelay 小于 0 直接不开窗。走哪条支路看 autoboot_keyed()：AES 与 EVK 两份 defconfig 里连一行 AUTOBOOT 都搜不出，include/autoboot.h 第 37 行的内联版本把没配 CONFIG_AUTOBOOT_KEYED 的情形编成 false，所以两块板都走 426 行的 abortboot_single_key。这条单键路咱们逐行看一遍。入口先 print_boot_delay 把当前值打出来，接着查一次 tstc()，串口缓冲里要是已经压着键，当场消费掉、abort 置 1（386 到 390 行），这是给手快的人留的口子。正经等待在 392 行起的循环里：每圈把 bootdelay 减一，在 get_timer 切出的一秒钟里每 10 毫秒（udelay(10000)）探一次串口，探到键就 abort 置 1、bootdelay 清零，一秒走完把新数字重印一遍，最后补一个换行收场。

### CONFIG_BOOTDELAY 的四种取值

咱们把四种取值摆一遍，编译默认值自己交代：正数是一秒一格的倒计时，0、-1、-2 是三种特殊档，下面挨个看。

```bash
# 主机 ~/imx-forge
grep -n -A7 "config BOOTDELAY" third_party/uboot-mainline/boot/Kconfig
```

```text
1601:config BOOTDELAY
1602-	int "delay in seconds before automatically booting"
1603-	default 2
1604-	help
1605-	  Delay before automatically running bootcmd;
1606-	  set to 0 to autoboot with no delay, but you can stop it by key input.
1607-	  set to -1 to disable autoboot.
1608-	  set to -2 to autoboot with no delay and not check for abort
```

默认 2。EVK 参考板没设 BOOTDELAY，落到这个 2，05 章对照表里 Hit any key to stop autoboot: 2 那行现场就是这么来的。0 的行为 help 写了，代码对得上：abortboot(0) 照样把 ：0 打出来并查一次已按下的键，392 行的循环一圈不进，按键拦得住，只是没有一秒一格的过程。-1 与 -2 的走向在 autoboot_command 的条件里（497 与 498 行），咱们把条件原样摆出来，把这两种取值的分岔读出来：`stored_bootdelay == -2 || (stored_bootdelay != -1 && !abortboot(stored_bootdelay))`。是 -2，前半句短路成立，bootcmd 立刻整串执行，连 ：0 那一行都不打。是 -1，后半句里的 stored_bootdelay != -1 不成立，run_command_list 一个字都不跑，函数返回，main_loop 顺序走到 cli_loop()（main.c 第 86 行），提示符出现。AES 的 CONFIG_BOOTDELAY=-1（defconfig 第 16 行）走的就是这条道——上电即停提示符，倒计时一行都没有，05 章那行 ：2 的现场是 EVK 参考板的。同一份镜像里 Hit any key 的字符串照样编着（第四节 strings 指认），-1 只是让打印它的函数永远等不到被调用。

### 环境变量与设备树都能盖

CONFIG_BOOTDELAY 只是兜底，咱们看 bootdelay_process（autoboot.c 452 行起）的读法，写在脸上：

```c
const char *bootdelay_process(void)
{
	char *s;
	int bootdelay;

	bootcount_inc();

	s = env_get("bootdelay");
	bootdelay = s ? (int)simple_strtol(s, NULL, 10) : CONFIG_BOOTDELAY;

	/*
	 * Does it really make sense that the devicetree overrides the user
	 * setting? It is possibly helpful for security since the device tree
	 * may be signed whereas the environment is often loaded from storage.
	 */
	if (IS_ENABLED(CONFIG_OF_CONTROL))
		bootdelay = ofnode_conf_read_int("bootdelay", bootdelay);
```

环境变量 bootdelay 优先于编译值，咱们改一个变量就能试，setenv bootdelay 3 加 saveenv，不改一行代码倒计时就变 3 秒。设备树 /config 节点的 bootdelay 还能再盖一层，那段注释把理由写得直白：设备树可能带签名，存储里的环境常常不带，安全场景宁可信前者。层层覆盖的终点，才是串口上那行字。

## 三、脚本与中断：两道分岔口

倒计时没被打断时，bootcmd 整串执行（run_command_list 在 autoboot.c 507 行）。EVK 的 bootcmd 是量产形态的脚本，主线 11 章逐句讲过，咱们这里回收它的形状：

```bash
# 主机 ~/imx-forge
grep -n "BOOTCOMMAND\|BOOTDELAY" third_party/uboot-mainline/configs/mx6ull_14x14_evk_defconfig
```

```text
16:CONFIG_USE_BOOTCOMMAND=y
17:CONFIG_BOOTCOMMAND="run findfdt;mmc dev ${mmcdev}; if mmc rescan; then if run loadbootscript; then run bootscript; else if run loadimage; then run mmcboot; else run netboot; fi; fi; else run netboot; fi"
```

脚本里 loadbootscript 与 bootscript 两个名字的户口，咱们到板级环境文本里翻：

```bash
# 主机 ~/imx-forge
grep -n "script=" third_party/uboot-mainline/board/nxp/mx6ullevk/mx6ullevk.env
```

```text
3:script=boot.scr
17:loadbootscript=fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} ${script};
18:bootscript=echo Running bootscript from mmc ...; source
```

咱们把这条脚本链顺着读一遍。mmc rescan 把卡探活，探得活才轮到 loadbootscript：fatload 把第 1 分区根目录的 boot.scr（变量 script 给的文件名）读进 loadaddr。读到了，run bootscript 执行，它回显一行 Running bootscript from mmc ...，然后一句 source 收尾——cmd/source.c 第 26 行的 do_source 把内存里那份脚本镜像就地展开执行，boot.scr 里写的命令序列从这里接管。boot.scr 不在卡上，fatload 失败，落进 else 分支的 loadimage、mmcboot，再不行 netboot 兜底。脚本路排在镜像路前面，板卡厂想换启动行为时改一个卡上的 boot.scr 文件就行，镜像这边一动也不用动。

咱们数一数，“走脚本还是进命令行”的分岔其实有两道。头一道在倒计时窗口：abortboot 返回 1，autoboot_command 那个条件不成立，run_command_list 不被调，函数返回，cli_loop() 把提示符端出来，引导脚本一步没跑。这道分岔只在倒计时的几秒里存在，脚本链一旦开跑，中断的资格就收走了。第二道在 loadbootscript：卡上有没有 boot.scr，决定走脚本还是走镜像。两道岔口前后接着，串口上看到的都是同一个提示符，根子差着一级。

咱们看 AES 上电时这两道岔口的走向，两道都轮不到。自家的脚本住在头文件里（emmcbootaes，include/configs/mx6ull_aes_emmc.h 第 71 行起，主线 11 章引过），ext4load 直接从 eMMC 第 1 分区把 zImage 与 DTB 读进内存。boot.scr 那条路在 AES 的默认 bootcmd 里没接，loadbootscript、bootscript 与 EVK 同款编在内置环境里（主线 11 章引过），自动引导不经过它们，只有手敲 run loadbootscript 才轮得到。倒计时又被 -1 关着，于是 AES 上电的实际路线是：时刻表里倒计时那格直接跳过，提示符等人，引导动作全靠手敲 setenv bootcmd 或 run emmcbootaes。适配期这么配留的正是操作窗口，bootcmd 只有一句 echo（defconfig 第 18 行），就算哪天 bootdelay 被改成正值，自动执行的内容也只有回显一行。

::: warning bootdelay 改成 -2 之前想一步
后果是提示符可能再也进不去。setenv bootdelay -2 加 saveenv 之后，复电时 autoboot_command 的条件短路，bootcmd 立刻整串执行，:0 那一行都不打，连按键的机会都没有。根因是 bootdelay 是环境变量，bootdelay_process 读它排在读编译值前面，会盖过 CONFIG_BOOTDELAY，而 -2 这条道没有第二道人工闸门，bootcmd 写错一行（比如误留一个 reset），坏脚本每次上电都原样跑一遍。咱们要退路，得顺着第一节的机制走：换 SD 卡启动，ENV 器件跟启动器件走，SD 上的 0x400000 没存过环境，那 8 KB 读回来过不了 CRC 校验，U-Boot 回落内置缺省（bootdelay=-1，bootcmd 只有一句 echo），提示符回来。从 SD 启动拿到提示符后，环境已经换回缺省，saveenv 也只会写进 SD 卡，eMMC 上 0x400000 那 8 KB 得手工处理。做法是 mmc dev 1 之后按 10 章第五节的落位用 mmc write 或 mmc erase 覆写（块 0x2000 起 16 块），或者擦掉，让 U-Boot 回落缺省后再从 eMMC 启动。板端这套动作本环境没有条件实测，以主线 11 章第三节的 setenv、saveenv 篇为准。
:::

## 四、镜像自证与 U-Boot 本体初始化的收拢

自证的命令对着自己的产物跑才有分量。本来对着的参考构建日志 /tmp/uboot-ref-build.log，咱们如实记录，今天（11 月 15 日）查过，它已经不在了。03 篇引用的 11 月 14 日那轮参考产物连同 /tmp/uboot-ref-aes 与 /tmp/uboot-ref-evk，ls 全报 No such file or directory。仓库里自己的产物还在，等价命令换它跑。out/uboot 是 10 月 20 日的 AES 构建，generated_defconfig 第 16 行同样是 CONFIG_BOOTDELAY=-1，与源 defconfig 同款，7041816 字节的 u-boot ELF 躺在 out/uboot/u-boot：

```bash
# 主机 ~/imx-forge
strings out/uboot/u-boot | grep "Hit any key" | head -2
```

```text
Hit any key to stop autoboot: %d
```

咱们看，一行就是全部。格式串编进二进制就长这样，%d 等着运行时被 bootdelay 的值填。这块板的倒计时一次都没跑过（bootdelay=-1），字符串照样在镜像里——abortboot_single_key 不吃条件编译，编进的是代码本体，开关只管那个值。环境那几句也在同一个文件里，咱们拿 strings 指认：

```bash
# 主机 ~/imx-forge
strings out/uboot/u-boot | grep -E "Loading Environment from|Reading from MMC|using default environment"
```

```text
*** Warning - %s, using default environment
Loading Environment from %s...
Loading Environment from %s... OK
Loading Environment from %s... 
Reading from MMC(%d)... 
```

咱们把五句全部对上正文。头一句是坏 CRC 的警告，env_set_default 打的，%s 的位置填 bad CRC。中间两句是 env_load 的开场与成功收尾。第四句出自 env_reload（env/env.c 第 240 行），它先打前半句，等结果再补 OK，格式串句尾多一个空格，跟开场那句在渲染里肉眼分不出来，cat -A 才现形。末句 Reading from MMC(%d) 出自 env/mmc.c 的 env_mmc_load_singular。哪天镜像重编了，同一条 strings 换个路径再跑一遍就行。

console、重定位、驱动扫描、env，这四个时刻散在两个初始化序列里，前面各节都到过现场，咱们把这四个时刻拼成一张带源码锚点的时刻表，U-Boot 本体的初始化序列到此收拢。env_addr 那格能修正是有开关撑着的，CONFIG_ENV_RELOC_GD_ENV_ADDR 在 out/uboot/generated_defconfig 第 47 行开着：

| 时刻 | 串口上能看到什么 | 源码锚点 |
|------|----------------|---------|
| 后端登记（重定位前） | 还没有输出，串口要再过两级才开口 | common/board_f.c 959 |
| 一级控制台就绪，banner 出字 | U-Boot 版本行 | board_f.c 962、963 |
| 重定位收尾，gd 翻上 RELOC 标记，env_addr 按 reloc_off 修正 | 默认看不见（debug 级） | board_r.c 602、151 |
| 驱动模型扫描，MMC 登记 | Core: 与 MMC: 开头的两行 | board_r.c 661（dm_announce）、704 |
| env 从 eMMC 读入、校验、接管 | Loading Environment from MMC... OK | board_r.c 712 → env/env.c 172 → env/mmc.c |
| 倒计时开窗（bootdelay 不小于 0 才有） | Hit any key to stop autoboot: 2 | main.c 75 → autoboot.c 418 |
| 提示符待人 | =>（CONFIG_SYS_PROMPT 的字面值） | main.c 86 |

时刻表最后一格之后没有新的一格。提示符出现，=> 后面等着的是人敲的命令。咱们把这行 %d 留在镜像里，bootdelay 哪天改成几，串口就把它填成几。

## 继续学习

- [链接地址与运行地址对不上的日子](07_relocation_limits.md)：扩展卷上一篇，搬家在那篇干完，本篇接着把 env 与倒计时的源码路径走完。
- [从 _start 开始：U-Boot 的第一条指令](05_entry_and_vectors.md)：进门之后、进 C 之前的状态在那篇摆清，栈与 gd 立在那里。
- [DCD 逐条读：BootROM 替咱们执行的初始化清单](03_dcd_walkthrough.md)：Boot ROM 三篇的收尾，跳进 0x87800000 的交接证据在那篇备齐。
- [上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像](01_boot_rom_boot_media.md)：启动介质怎么定的，ENV 器件编号就跟着怎么走。
- [环境变量与 bootcmd：U-Boot 的行为由谁来定](../11_env_bootcmd.md)：行为层对应篇，setenv、saveenv 与坏环境救援的实作在那边。
- [串口验收：亲眼看见咱们编的 U-Boot 活着](../05_serial_acceptance.md)：倒计时 ：2 的串口现场与验收对照表。
- [console 什么时候就绪](09_console_ready.md)：本篇时刻表里一级控制台就绪那几格的深展开，从字符串到寄存器的每一站在那一篇。
- [07 结尾预告的 SPL 搬家旁栏](08_spl_sidebar.md)：排在本卷第八篇，无 SPL 的路线读它就当对照。
- [启动 Linux：把内核装进板子完成交接](../12_boot_linux.md)：bootcmd 链条跑通之后的下一站，bootz 交接的细节。
