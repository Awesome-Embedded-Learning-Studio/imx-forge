---
title: 栈和 gd：U-Boot 的小本本
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 栈和 gd：U-Boot 的小本本

> 上一篇把控制交到 board_init_f(0) 手里时交代过，这个 C 环境是残缺的，crt0.S 开头的注释写得明白：只有栈与 gd 的位置，变量与 BSS 一律没有。本篇带着咱们把仅有的两样家当从头清点，栈按哪条公式立在哪个地址，gd 这个小本本里记了什么，它为什么必须装在固定寄存器里跟着 r9 走，board_init_f 的第一轮活也在这篇过完，它算出的 relocaddr、new_gd、start_addr_sp 三个地址，连同 reloc_off 这个差值，正是下一篇搬家要用的全部依据。串口什么时候才真正开始出字，这里埋一根指针，留给后面第 9 篇《console 什么时候就绪：第一行输出来自哪》细说。

## 一、没有栈的 C 不叫 C

C 函数离不开栈。局部变量放栈上，返回地址压栈，被调方要保存的寄存器也压栈，这些事编译器默认都替咱们办了，前提是 sp 指着一块能写的内存。可上一篇咱们刚看过，reset 一路走进 _main 时，给 errata 用的那根临时栈不算数——真正给 C 用的栈一根都还没立。crt0.S 的 103 到 114 行就是补栈的全部代码，咱们把跟栈沾边的行捞出来：

```bash
# 主机 ~/imx-forge
grep -n "sp\|stack" third_party/uboot-mainline/arch/arm/lib/crt0.S | head -8
```

```text
22: *    This environment only provides a stack and a place to store
33: *    data include the relocation destination, the future stack, and
36: * 3. Set up intermediate environment where the stack and GD are the
49: *    data (initialized to their intended value), and stack in system
50: *    RAM (for SPL moving the stack and GD into RAM is optional - see
109:	mov	sp, r0
111:	mov	sp, r0
130: * Set up intermediate environment (new sp and gd) and call
```

这段（103 到 114 行）里真正写 sp 的就两处，109 与 111 行。搬家的中间环境里还有第三处，137 行把 gd->start_addr_sp 装进 sp，读第二节 crt0 取数那段时再点它。109 行装的值来自 106 行的 ldr r0, =(SYS_INIT_SP_ADDR)，这份构建没开 HAVE_INIT_STACK（out/uboot/.config 里查无此项），走的正是这个分支。SYS_INIT_SP_ADDR 的公式摆在 include/system-constants.h 19 到 20 行，CFG_SYS_INIT_RAM_ADDR 加 CFG_SYS_INIT_RAM_SIZE 减 GENERATED_GBL_DATA_SIZE。三个常量咱们逐个对，板级头 include/configs/mx6ull_aes_emmc.h 第 139 与 140 行把前两个接到 IRAM_BASE_ADDR 与 IRAM_SIZE，定义在 arch/arm/include/asm/arch-mx6/imx-regs.h 第 67 与 375 行，数值是 0x00900000 与 0x00020000，合计 128 KB 的片上 OCRAM。第三个常量咱们从生成目录取真值：

```bash
# 主机 ~/imx-forge
grep -n "GENERATED_GBL_DATA_SIZE\|GD_SIZE" out/uboot/include/generated/generic-asm-offsets.h | head -4
```

```text
9:#define GENERATED_GBL_DATA_SIZE 256 /* (sizeof(struct global_data) + 15) & ~15 */
11:#define GD_SIZE 256 /* sizeof(struct global_data) */
```

256，正好是一个 gd_t 的大小向上取整。咱们代进公式算，0x00900000 加 0x00020000 减 0x100 得 0x0091ff00，跟上一篇从反汇编里挖出来的字面量分毫不差。重定位前的内存地图这就有了第一层。代码不住 OCRAM，它住在 DDR 的 0x87800000，那是 Boot ROM 照 boot data 搬运的落点（CONFIG_TEXT_BASE，out/uboot/.config 第 183 行）。OCRAM 从 0x00900000 到 0x00920000 整块 128 KB，只出栈和小本本，起点掐在顶端往低处数一个 gd 的地方。上一篇 lowlevel_init 垫的那格 256 字节占位（当时 sp 停在 0x0091fe00）马上要被 crt0 的正式编制换掉。

crt0.S 106 到 114 行咱们接着读。ldr 装入 0x0091ff00 之后，108 行 bic r0, r0, #7 把低三位清掉，8 字节对齐是调用约定对 sp 的硬要求，汇编注释写明 ABI compliance。109 行 mov sp, r0，第一根正式 C 栈落地。跟着的六行才是本篇的主角，110 行 bl board_init_f_alloc_reserve 圈地，111 行把返回值写回 sp，113 行再写进 r9（112 行的注释专门点了一句 set up gd here, outside any C code），114 行 bl board_init_f_init_reserve 清零。

圈地怎么圈，正身在 common/init/board_init.c 第 81 行起的 board_init_f_alloc_reserve，它只做两次减法。86 行减去 CONFIG_VAL(SYS_MALLOC_F_LEN)，咱们这份 .config 第 185 行写着 0x2000。90 行减去 sizeof(struct global_data) 并向下做 16 字节对齐。咱们把数代上，0x0091ff00 减 0x2000 得 0x0091df00，再减 0x100 得 0x0091de00，16 字节对齐没挪位。0x0091de00 就是 gd 的家，也是新的 sp，113 行把 r9 定在这里。137 行起的 board_init_f_init_reserve 接手，memset 清掉这 256 字节，158 行把 base 向上加一个对齐过的 gd 大小，167 行把 gd->malloc_base 记在 0x0091de00 加 0x100，也就是 0x0091df00。三个数各管一段，0x0091df00 到 0x0091ff00 这 8 KB 是早期 malloc 的地盘，gd 的 256 字节压在堆脚下，栈从 gd 往低处长，低处还剩 0x1de00 约 119 KB 的余量。sp 与 r9 同指一格，堆往上爬，栈往下退，gd 垫在两者交界上。crt0.S 头注释 22 到 24 行说的 a stack and a place to store the GD，在 6ULL 上就是这块 OCRAM。board_init_f 拿到控制权那一刻，sp 与 r9 都指着 0x0091de00。

## 二、gd：全局数据小本本

小本本本体是 include/asm-generic/global_data.h 里的 struct global_data，35 行一句 typedef struct global_data gd_t 给它起了简称。咱们翻开头文件，开头的注释自己交代了纪律，这块结构要放在启动最早可用的那一小块内存里（DPRAM、锁过的 cache 都行），还得保持极小，GENERATED_GBL_DATA_SIZE 必须不小于 sizeof(gd_t)。咱们这份板卡编出来的 gd_t 正好 256 字节，证据在两头，头文件 469 行一句 static_assert(sizeof(struct global_data) == GD_SIZE) 把 C 侧尺寸与汇编侧的偏移表绑在一起，哪边对不上编译直接拒收，生成目录里 generic-asm-offsets.h 第 11 行的 GD_SIZE 也是 256，那是编译器照真实结构算出来的。

gd 在 C 里怎么摸到，探针给咱们答案：

```bash
# 主机 ~/imx-forge
grep -n "DECLARE_GLOBAL_DATA_PTR" third_party/uboot-mainline/arch/arm/include/asm/global_data.h
```

```text
117:#define DECLARE_GLOBAL_DATA_PTR
136:#define DECLARE_GLOBAL_DATA_PTR		register gd_t *gd asm ("x18")
138:#define DECLARE_GLOBAL_DATA_PTR		register gd_t *gd asm ("r9")
```

三种形态咱们挑着看。138 行是普通 GCC 编 32 位 ARM 的那份，`register gd_t *gd asm ("r9")` 把一个指针变量硬绑到 r9 上，此后每个 gd->xxx 编出来就是对 r9 的一次解引用。136 行是 64 位的，寄存器换成 x18，Arm64 的调用约定同样把这根留作平台自用。117 行是 clang 或开 LTO 时的变体，宏直接为空，gd 改由 get_gd() 一段内联汇编现读 r9（120 到 133 行），行为不变。不管哪种，用 gd 的 C 文件开头都得挂一句这个宏，board_f.c 第 56 行与 board_init.c 第 14 行都挂着。

为什么非占一根固定寄存器不可，咱们把三层原因串起来。头一层看 C 环境本身，crt0.S 头注释 24 到 27 行说得直白，进 board_init_f 时变量型的全局数据连同 BSS 一律没有，只有常量能用。也就是说此刻 C 的静态变量、全局变量一个都靠不住，栈上刚清零的 gd 是唯一被 crt0 安置过的数据，r9 里的这个指针是那个阶段唯一可信的锚。再说搬家这一层，relocate_code 前后地址全变，唯一贯穿全程的是 r9 这个角色本身。crt0.S 135 到 159 行那一整段都在从 r9 指的 gd 里按偏移取数，取完 start_addr_sp，这个数随即在 137 行落进 sp，搬家的中间栈就位，138 行再把 r9 换到新 gd。新 gd 的内容 setup_reloc 已经复制好了，154 与 159 行的 reloc_off、relocaddr 都从新小本本里取，真正拷镜像的 relocate_code 到 163 行才进。汇编不懂 C 结构体，靠的是编译期生成的偏移常量：

```bash
# 主机 ~/imx-forge
grep -n "GD_RELOCADDR\|GD_RELOC_OFF\|GD_START_ADDR_SP\|GD_NEW_GD" out/uboot/include/generated/generic-asm-offsets.h
```

```text
15:#define GD_RELOCADDR 48 /* offsetof(struct global_data, relocaddr) */
16:#define GD_RELOC_OFF 64 /* offsetof(struct global_data, reloc_off) */
17:#define GD_START_ADDR_SP 60 /* offsetof(struct global_data, start_addr_sp) */
18:#define GD_NEW_GD 4 /* offsetof(struct global_data, new_gd) */
```

四个偏移与头文件里的成员排布一一对应，new_gd 排在第二个成员所以偏移是 4。board_f.c 58 到 67 行留有一段设计者的注释，讨论 gd 为什么值得占一根寄存器、重定位之后 ARM 上巨大的字面量池怎么省，有兴趣咱们可以翻过去看。最底下垫着的是调用约定，AAPCS 把 r9 定义为平台专用寄存器，编译器承诺不往里放东西，位置才腾得出来，ARM64 的 x18 同理。

成员清单，探针捞一批：

```bash
# 主机 ~/imx-forge
grep -n "ram_size\|malloc_base\|baudrate" third_party/uboot-mainline/include/asm-generic/global_data.h | head -8
```

```text
71:	 * @ram_size: RAM size in bytes
73:	phys_size_t ram_size;
144:	 * @baudrate: baud rate of the serial interface
146:	unsigned int baudrate;
310:	 * @malloc_base: base address of early malloc()
312:	unsigned long malloc_base;
```

再往下数，成员各有岗位，咱们按用途过一遍。内存这一拨有 ram_size（73 行）、ram_top（77 行）、ram_base（100 行）、dram 数组（463 到 466 行，每个 bank 一对 start 与 size）和 mon_len（142 行），重定位前的整张内存地图就记在这几格里。串口这一拨是 baudrate（146 行）、cur_serial_dev（56 行），外加 flags（83 行）里的 GD_FLG_SERIAL_READY 与 GD_FLG_HAVE_CONSOLE 两面旗。堆这一拨是 malloc_base、malloc_limit、malloc_ptr（310 到 321 行）。搬家这一拨最热闹，relocaddr（109 行，注释里提到 bdinfo 命令能看它，GDB 调试还能拿它 add-symbol-file）、reloc_off（130 行）、start_addr_sp（126 行）、irq_sp（122 行）、new_gd（48 行）与 bd（44 行，板卡信息结构 bd_info，早期收集机器信息的地方）都在。驱动模型的根 dm_root 与 uclass_root 住在 235 与 253 行，fdt_blob（52 行）记着设备树的位置，timebase_h 与 timebase_l（184 与 188 行）记时间戳的高低两个 32 位。这么多岗位挤进 256 字节，头注释那句 keep it *SMALL* 的分量咱们这就掂出来了。

::: warning 自写汇编别挪用 r9
咱们手写启动汇编或给启动流程打补丁时，别把 r9 当临时寄存器用。根因在第二节，整个 C 侧的 gd 访问展开后就是对 r9 的解引用，汇编与 C 两边靠它交接。后果是谁往 r9 里存了个别的数，下一条 C 语句读 gd 读到的就是垃圾地址，轻则数据错乱，重则取指跑飞，那时串口往往还没就绪（第三节细说），板子连一声都吭不出来，只能上 JTAG 才看得到现场。
:::

## 三、board_init_f：第一次 C 调用

老资料讲 board_init_f 都从 init_sequence_f 这个名字讲起，咱们拿它当探针，在这棵 v2026.10 的树上扑了个空：

```bash
# 主机 ~/imx-forge
grep -n "init_sequence_f" third_party/uboot-mainline/common/board_f.c | head -3
```

```text
```

命令正常退出，匹配数为零，输出就是空的。这版树把序列改了名，咱们换等价的探针再跑：

```bash
# 主机 ~/imx-forge
grep -n "initcall_run_f\|void board_init_f" third_party/uboot-mainline/common/board_f.c | head -3
```

```text
917:static void initcall_run_f(void)
1073:void board_init_f(ulong boot_flags)
1081:	initcall_run_f();
```

新名字叫 initcall_run_f，917 行起一整个函数全是序列，1073 行的 board_init_f 调它。往后咱们拿老文章对照新树，这一处得心里有数。

board_init_f 本体短得很（1073 到 1089 行），咱们过一遍。参数 boot_flags 直接填进 gd->flags（1077 行，crt0 传来的那个 0），1078 行再清一遍 GD_FLG_HAVE_CONSOLE，1079 行让 gd->boardf 指向栈上的局部结构 boardf，然后一行 initcall_run_f()。ARM 上序列尾部的 jump_to_copy 被条件编译裁掉了，序列跑完正常返回，搬家的活 crt0 自己接着干，1083 到 1088 行那段 NOTREACHED 的 hang 轮不到咱们这个架构。

序列怎么跑，宏在 include/initcall.h 15 到 22 行。INITCALL(name) 展开成判断 name() 返回值的语句，返回非零就打印失败信息并 hang()，任何一个环节出问题，板子当场挂死。919 到 922 行的注释还叮嘱别往这个函数里加逻辑，它就该是一份排好顺序的调用单。咱们把 959 到 963 行那一段捞出来，串口的分界就在这五格里：

```c
	INITCALL(env_init);		/* initialize environment */
	INITCALL(init_baud_rate);	/* initialze baudrate settings */
	INITCALL(serial_init);		/* serial communications setup */
	INITCALL(console_init_f);	/* stage 1 init of console */
	INITCALL(display_options);	/* say that we are here */
```

init_baud_rate 的正身在 board_f.c 98 到 102 行，`gd->baudrate = env_get_ulong("baudrate", 10, CONFIG_BAUDRATE)`，环境变量里有就用，没有落到默认 115200（.config 第 1496 行）。分界怎么划，咱们从两个函数的正身看。serial_init 在 drivers/serial/serial-uclass.c 190 行起，照设备树 chosen/stdout-path 找到串口设备，找到后 205 行把 GD_FLG_SERIAL_READY 置进 gd->flags。紧跟着 console_init_f 在 common/console.c 1034 行起，把 GD_FLG_HAVE_CONSOLE 也置上，并冲刷 pre-console 缓冲（咱们这份 .config 第 480 行 PRE_CONSOLE_BUFFER 是 not set，那个缓冲压根没编进来）。在 HAVE_CONSOLE 置位之前，puts 与 printf 的入口都会查这面旗（console.c 748 与 788 行两处检查），没置位就空手返回——咱们这份配置连 DEBUG_UART 都没开（.config 第 265 行 not set），serial_init 之前的打印全部无声无息，一个字节都到不了串口，DRAM: 那几个字要等 console_init_f 跑过才见得着。控制台的完整两层初始化与静默记录机制，后面[第 9 篇《console 什么时候就绪：第一行输出来自哪》](09_console_ready.md)接手，这里只把分界立住。

序列前半程还有几步值得咱们点名。setup_mon_len 把 mon_len 算成 __bss_end 减 _start（265 到 287 行，ARM 走 270 行那个分支）。initf_malloc 把堆的三件套摆好（common/dlmalloc.c 2484 行起，校验 gd->malloc_base 非零，malloc_limit 写 0x2000，malloc_ptr 清 0，跟第一节算出的 0x0091df00 与 8 KB 一一对上）。initf_dm 用早期堆把驱动模型的根立起来。再往后才轮到 env_init 到 display_options 这段报到流程。

DRAM 活了之后序列进入下半场。announce_dram_init 打出 DRAM: 四个字母加冒号，dram_init 是板卡自己的正身（board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c 33 到 35 行，gd->ram_size = imx_ddr_size()），imx_ddr_size 在 arch/arm/mach-imx/mmdc_size.c 39 行照 MMDC 控制器寄存器现场算容量，DCD 点活的内存有多大，这里就读出多大。跟着 setup_ram_base 把 ram_base 定在 CFG_SYS_SDRAM_BASE（板级头第 138 行接 PHYS_SDRAM，即 imx-regs.h 114 行的 MMDC0_ARB_BASE_ADDR，0x80000000），setup_ram_config 在 361 行算 ram_top = ram_base + get_effective_memsize()（弱定义在 common/memsize.c 205 行），setup_dest_addr 在 389 行把 relocaddr 顶到 ram_top。往后一串 reserve 从顶往下扣，代码顺序就是扣的顺序，咱们照这个顺序一段段对下去。reserve_uboot 扣镜像本体（508 行减 gd->mon_len，mon_len 等于 __bss_end 减 _start，即 0x8798e328 减 0x87800000，得 0x18e328。两个端点 out/uboot/System.map 都给：第 2 行 _start 0x87800000，第 3776 行 __bss_end 0x8798e328）。reserve_malloc 扣 TOTAL_MALLOC_LEN（include/env_internal.h 68 到 76 行按环境位置分支，这份配置环境在 MMC，ENV_IS_EMBEDDED 不成立，走第 73 行 TOTAL_MALLOC_LEN 等于 CONFIG_SYS_MALLOC_LEN 加 CONFIG_ENV_SIZE，.config 第 184 行 0x1000000、第 191 行 0x2000，即 16 MB 加 8 KB）。这个 8 KB 是环境区，跟第一节 SYS_MALLOC_F_LEN 划出的 8 KB 早期堆数值相同、用途不同，别写成同一块。reserve_board 与 reserve_global_data 扣 bd_info 与新的 gd（571 到 591 行，gd->new_gd 指过去）。reserve_fdt 扣设备树。reserve_stacks 收尾（639 行按 16 字节对齐，跟着 arch/arm/lib/stack.c 18 行起的 arch_reserve_stacks 把 irq_sp 也定好，非 64 位再减 16 留出 abort 栈）。三个数就这样躺进小本本，relocaddr 是新家起点，new_gd 是新 gd 的地址，start_addr_sp 是新栈顶。最后一站 setup_reloc（743 行起）把整份 gd 复制进 new_gd（763 行 memcpy），748 行算出 reloc_off 等于 relocaddr 减 __image_copy_start。relocaddr、new_gd、start_addr_sp 这三个数，连同这个 reloc_off，就是下一篇搬家的全部依据。

::: warning 早期堆只有 8 KB，超了连报错都出不来
咱们在这份配置下要记住，重定位前的堆只有 8 KB。根因是 SYS_MALLOC_F_LEN 只划了 0x2000，这块地盘借的还是 OCRAM 栈顶那 8 KB（第一节的算术），gd->malloc_limit 记的也是这个数。后果是谁在搬家之前想多要一点，malloc 就返回空指针，而那时 console_init_f 往往还没跑，报错一个字都发不出来，现象就是莫名其妙地卡死或挂掉。大块内存的申请挪到搬家之后，等完整 malloc 就绪再提。
:::

本篇所有数字的来路咱们也交代清楚：

## 四、自证：把序列数一遍

自证题这就来做，initcall_run_f 里到底摆了多少个初始化函数。办法一条命令就够，咱们把函数体切出来数：

```bash
# 主机 ~/imx-forge
sed -n '917,1071p' third_party/uboot-mainline/common/board_f.c > /tmp/initcall_body.txt
grep -c "INITCALL(" /tmp/initcall_body.txt
grep -c "INITCALL_EVT" /tmp/initcall_body.txt
grep -c "WATCHDOG" /tmp/initcall_body.txt
```

```text
69
2
7
```

69 个 INITCALL 槽位是源面上的数，外加 2 个事件槽与 7 处喂狗点。这份数每个配置都不一样，咱们换自己的板卡重算，动作就三步：

1. 咱们用上面同一条 sed 加 grep 数出源面槽位数，这棵树是 69。
2. 把自己的 .config 拉出来，咱们逐个 INITCALL 看它上方的条件编译，把 not set 对应的名字划掉。
3. 数剩下的，就是编进咱们这份板卡的序列长度。

拿咱们这份 mx6ull_aes_emmc 当例子过一遍。第 546 行 CONFIG_BLOBLIST 是 not set，936 行的 bloblist_init 被裁。第 1841 行 CONFIG_TRACE not set（连带 TRACE_EARLY 也没了），929 行的 trace_early_init 被裁。第 1585 行 CONFIG_SYSRESET not set，967 行的 print_resetinfo 被裁。第 1783 行 CONFIG_WATCHDOG not set，7 处喂狗点展开后全空，这 7 处是 WATCHDOG_INIT 与 WATCHDOG_RESET 的宏调用点，不占 INITCALL 槽位。咱们逐条数下来，16 个槽位被这份配置裁掉，剩下 53 个真正编进序列，两个事件槽照跑（event_notify_null 找不到监听者就空回），喂狗一个都不剩。

16 个被裁的名字整个列在这里，咱们好按 69 减 16 等于 53 把数对上：trace_early_init(929)、bloblist_init(936)、console_record_init(940)、print_resetinfo(967)、embedded_dtb_select(974)、init_func_i2c(983)、post_init_f(988)、testdram(992)、init_post(996)、fix_fdt(1017)、reserve_pram(1020)、reloc_fdt(1034)、fix_fdt(1035)、copy_uboot_to_ram(1054)、do_elf_reloc_fixups(1055)、jump_to_copy(1069)。容易看走眼的几处也交代一下。get_clocks(951) 保留，它 949 行的守卫 defined(CONFIG_PPC)、defined(CONFIG_SYS_FSL_CLK)、defined(CONFIG_M68K) 满足其一即留，这份配置的 CONFIG_SYS_FSL_CLK 是 y（.config 第 522 行）。fix_fdt 在名单里出现两次（1017 与 1035），reloc_fdt 裁掉的是 1034 那处，真正编进序列的 reloc_fdt 在 1048 行。咱们自己的板卡如果是别的配置，这个数就得重数，差的就是配置裁剪。

数完咱们别忘了这份数的用途。53 个名字里，setup_dest_addr 到 reserve_stacks 那一段把 relocaddr、new_gd、start_addr_sp 逐个填进 gd，setup_reloc 再把整份 gd 复制进 new_gd。crt0.S 135 到 159 行的汇编拿着 GD_START_ADDR_SP、GD_NEW_GD、GD_RELOC_OFF、GD_RELOCADDR 四个偏移（60、4、64、48）守在序列后面，等 board_init_f 一返回就把它们从 r9 指的小本本里一个个取走。搬家那一下怎么把这串地址用起来，下一篇接着算。

## 继续学习

- [链接地址与运行地址对不上的日子](07_relocation_limits.md)：本篇填进 gd 的 relocaddr、new_gd、start_addr_sp 正是搬家的三张地址条，那篇把整串地址从头算到尾。
- [DCD 逐条读：BootROM 替咱们执行的初始化清单](03_dcd_walkthrough.md)：DDR 是 Boot ROM 照清单点活的，本篇 dram_init 照 MMDC 寄存器现场算容量，两篇对起来看，内存的来龙去脉就完整了。
