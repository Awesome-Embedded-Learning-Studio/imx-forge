---
title: 搬家：重定位算法与地址计算
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 搬家：重定位算法与地址计算

> U-Boot 在 DDR 里落了脚并不常住。board_init_f 的队列走到末段，它给自己算好一块新家，把 1.6MB 的镜像八字节一步搬过去，再拿 7675 条重定位记录把镜像里的地址逐个修回来。本篇把这套搬家工程按顺序走一遍：新家地址在队列哪一格算出来、为什么定在 DDR 高处、拷贝与修正两个循环各自干什么、搬完之后全局变量靠什么复活，末尾咱们拿 u-boot.sym 把链接地址与运行地址逐个对出来。分家的现象、搬家前的生存法则和 relocate_code 的反汇编在 [链接地址与运行地址对不上的日子](./07_relocation_limits.md) 立过案，本篇从源码层接着讲，坐标沿用那一篇的推演口径。console 的三个就绪时刻在 [console 什么时候就绪：第一行输出来自哪](./09_console_ready.md) 排过，其中 console_init_r 那一格本来就站在搬家之后，第三节咱们再跟它碰一次头。

## 一、重定位的时机：队列末段把新家算好

探针第一条咱们对着 board_f.c 撒下去，落点全在给 gd->relocaddr 扣数的现场：

```bash
# 主机 ~/imx-forge
grep -n "setup_reloc\|relocaddr" third_party/uboot-mainline/common/board_f.c | head -8
```

```text
389:	gd->relocaddr = gd->ram_top;
390:	debug("Reloc addr: %08llX\n", (unsigned long long)gd->relocaddr);
396:	gd->initial_relocaddr = gd->relocaddr;
407:	gd->relocaddr -= (reg << 10);		/* size is in kB */
409:	      gd->relocaddr);
417:	gd->relocaddr &= ~(4096 - 1);
440:		/* Sanity check fb from blob is before current relocaddr */
441:		if (likely(gd->relocaddr > (unsigned long)ho->fb))
```

八条都落在给 gd->relocaddr 扣数的函数里，head -8 把 setup_reloc 本尊截在了后面。setup_reloc 本尊长什么样、在队列里排第几格，换个只搜 setup_reloc 与 reloc_off 的窄探针补全：

```bash
# 主机 ~/imx-forge
grep -n "setup_reloc\|reloc_off" third_party/uboot-mainline/common/board_f.c
```

```text
457:static int setup_relocaddr_from_bloblist(void)
743:static int setup_reloc(void)
748:		gd->reloc_off = gd->relocaddr - (unsigned long)__image_copy_start;
750:		gd->reloc_off = gd->relocaddr - (u32)_start;
756:		gd->reloc_off = gd->relocaddr - (CONFIG_TEXT_BASE + 0x400);
758:		gd->reloc_off = gd->relocaddr - CONFIG_TEXT_BASE;
769:		mcheck_on_ramrelocation(gd->reloc_off);
771:		debug("Relocation Offset is: %08lx\n", gd->reloc_off);
1023:	INITCALL(setup_relocaddr_from_bloblist);
1052:	INITCALL(setup_reloc);
1137:	(board_init_r + gd->reloc_off)((gd_t *)gd, gd->relocaddr);
```

末行 1137 先给咱们剧透了一个别家的写法，它住在 board_init_f_r 里，外面套着 `#if defined(CONFIG_X86) || defined(CONFIG_ARC)`，是 x86 与 ARC 用 C 函数补偏移的路子。ARM 不走这条路，board_f.c 第 787 行的注释写得明白：`/* ARM calls relocate_code from its crt0.S */`。所以 AES 这块板的分工是，算数归 C 代码，在队列 1052 格的 setup_reloc 里做完，动手归汇编，board_init_f 返回之后交回 crt0.S。

### 时机藏在 init_sequence_f 的末段

重定位的时机藏在初始化队列 init_sequence_f 的末段（源码里没有这个数组名，队列实为 initcall_run_f 函数体内 INITCALL 宏的顺序展开，系列沿用旧称），setup_reloc 一格定案。board_f.c 第 1000 行起的注释把设计意图铺在明面上：DRAM 一能干活就搬家，从内存顶端往下按固定次序预留。队列原文咱们抄两段：

```bash
# 主机 ~/imx-forge
sed -n '1011,1028p' third_party/uboot-mainline/common/board_f.c
```

```c
	INITCALL(setup_ram_base);
	INITCALL(dram_init_banksize);
	INITCALL(setup_ram_config);
	INITCALL(setup_dest_addr);
#if CONFIG_IS_ENABLED(OF_BOARD_FIXUP) && \
    !CONFIG_IS_ENABLED(OF_INITIAL_DTB_READONLY)
	INITCALL(fix_fdt);
#endif
#ifdef CFG_PRAM
	INITCALL(reserve_pram);
#endif
	INITCALL(reserve_round_4k);
	INITCALL(setup_relocaddr_from_bloblist);
	INITCALL(arch_reserve_mmu);
	INITCALL(reserve_video);
	INITCALL(reserve_trace);
	INITCALL(reserve_uboot);
	INITCALL(reserve_malloc);
```

```bash
# 主机 ~/imx-forge
sed -n '1040,1057p' third_party/uboot-mainline/common/board_f.c
```

```c
	INITCALL(reserve_stacks);
	INITCALL(show_dram_config);
	WATCHDOG_RESET();
	INITCALL(setup_bdinfo);
	INITCALL(display_new_sp);
	WATCHDOG_RESET();
#if !CONFIG_IS_ENABLED(OF_BOARD_FIXUP) || \
    !CONFIG_IS_ENABLED(INITIAL_DTB_READONLY)
	INITCALL(reloc_fdt);
#endif
	INITCALL(reloc_bootstage);
	INITCALL(reloc_bloblist);
	INITCALL(setup_reloc);
#if CONFIG_IS_ENABLED(X86) || CONFIG_IS_ENABLED(ARC)
	INITCALL(copy_uboot_to_ram);
	INITCALL(do_elf_reloc_fixups);
#endif
	INITCALL(clear_bss);
```

咱们把这条链按 AES 的配置过一遍筛。setup_dest_addr 一格把 gd->relocaddr 的起点定在 ram_top（setup_ram_base 在 1011 格先把内存底定在 CFG_SYS_SDRAM_BASE，可用内存顶由下一格 dram_init_banksize 算出）。往后的格子逐个往下扣，扣完一轮再进 setup_reloc 定案。AES 编出来的产物里，video 那格在 f 阶段没有设备可绑，07 篇核过它空转，bloblist、bootstage、trace 三格的功能没编进去（out/uboot/.config 第 546、417、1841 行都是 not set），INITCALL 还站在队列里，函数体被各自的 CONFIG 包住、只剩 return 0，跟 video 一样是空转。`CONFIG_OF_CONTROL=y`（.config 第 864 行）让 reserve_fdt 有真活干。真正动地基的是这几格：reserve_round_4k 做四 KiB 对齐，arch_reserve_mmu 给页表留地，reserve_uboot 给镜像本体留地。

### relocaddr 怎么算：从 ram_top 一路往下扣

reserve_uboot 的本体在 board_f.c 第 494 行，扣数的三行加上一句收尾，咱们抄出来：

```bash
# 主机 ~/imx-forge
sed -n '503,519p' third_party/uboot-mainline/common/board_f.c
```

```c
	if (!(gd->flags & GD_FLG_SKIP_RELOC) && !CONFIG_IS_ENABLED(SKIP_RELOCATE_CODE)) {
		/*
		 * reserve memory for U-Boot code, data & bss
		 * round down to next 4 kB limit
		 */
		gd->relocaddr -= gd->mon_len;
		gd->relocaddr &= ~(4096 - 1);
	#if defined(CONFIG_E500) || defined(CONFIG_MIPS)
		/* round down to next 64 kB limit so that IVPR stays aligned */
		gd->relocaddr &= ~(65536 - 1);
	#endif

		debug("Reserving %dk for U-Boot at: %08lx\n",
		      gd->mon_len >> 10, gd->relocaddr);
	}

	gd->start_addr_sp = gd->relocaddr;
```

mon_len 在 07 篇算过，__bss_end 减 _start 等于 0x18E328，即 1,631,016 字节，System.map 把两个符号备齐。沿那一篇的 512MB 口径咱们接着推：页表扣完落在 0x9FFF0000，这里再减 mon_len 按 4KiB 取整，镜像新家的地基是 0x9FE61000。末行 gd->start_addr_sp = gd->relocaddr 有个容易看走眼的地方：这名字叫栈指针，此刻干的是高水位线的活。从这一格起，后面每个 reserve_* 都拿它往下扣，扣到 reserve_stacks 才真正变回栈顶。

malloc 区的地盘紧跟着镜像脚下，reserve_malloc 在 558 行，咱们抄出来：

```bash
# 主机 ~/imx-forge
sed -n '557,562p' third_party/uboot-mainline/common/board_f.c
```

```c
/* reserve memory for malloc() area */
static int reserve_malloc(void)
{
	gd->start_addr_sp = reserve_stack_aligned(TOTAL_MALLOC_LEN);
	debug("Reserving %dk for malloc() at: %08lx\n",
	      TOTAL_MALLOC_LEN >> 10, gd->start_addr_sp);
```

TOTAL_MALLOC_LEN 的取值住在 include/env_internal.h，咱们把三个分支抄出来对一对：

```bash
# 主机 ~/imx-forge
sed -n '68,75p' third_party/uboot-mainline/include/env_internal.h
```

```c
#if defined(ENV_IS_EMBEDDED)
#define TOTAL_MALLOC_LEN	CONFIG_SYS_MALLOC_LEN
#elif (CONFIG_ENV_ADDR + CONFIG_ENV_SIZE < CONFIG_SYS_MONITOR_BASE) || \
      (CONFIG_ENV_ADDR >= CONFIG_SYS_MONITOR_BASE + CONFIG_SYS_MONITOR_LEN) || \
      defined(CONFIG_ENV_IS_IN_NVRAM)
#define	TOTAL_MALLOC_LEN	(CONFIG_SYS_MALLOC_LEN + CONFIG_ENV_SIZE)
#else
#define	TOTAL_MALLOC_LEN	CONFIG_SYS_MALLOC_LEN
```

AES 的环境在 eMMC 里（.config 第 894 行 CONFIG_ENV_IS_IN_MMC=y），咱们把分支过一遍筛：CONFIG_ENV_ADDR 与 CONFIG_SYS_MONITOR_BASE 未定义按 0 算，CONFIG_SYS_MONITOR_LEN 有定义、值为 0（.config 第 225 行），第二个条件 0 >= 0+0 成立，落进中间分支。分支走到哪条，gcc -E 把 env_internal.h 连同构建生成的 autoconf.h 真预处理一遍，展开结果当场打印（stderr 会捎带一条 unreachable 重定义的警告，宏展开不受它影响）：

```bash
# 主机 ~/imx-forge
printf '#include <env_internal.h>\nint probe = TOTAL_MALLOC_LEN;\n' | \
arm-none-linux-gnueabihf-gcc -E -x c -P -D__KERNEL__ \
  -include third_party/uboot-mainline/include/linux/kconfig.h \
  -imacros out/uboot/include/generated/autoconf.h \
  -I third_party/uboot-mainline/include -I out/uboot/include \
  -I third_party/uboot-mainline/arch/arm/include -I out/uboot/arch/arm/include - | tail -1
```

```text
int probe = (0x1000000 + 0x2000);
```

展开式正是中间分支的那一条，CONFIG_SYS_MALLOC_LEN 加 CONFIG_ENV_SIZE。咱们把数代进去：.config 第 184 行给 CONFIG_SYS_MALLOC_LEN 的数是 0x1000000，第 191 行给 CONFIG_ENV_SIZE 的数是 0x2000，TOTAL_MALLOC_LEN = 0x1000000 + 0x2000 = 0x1002000，即 16 MiB 加 8 KiB。从镜像脚 0x9FE61000 再往下扣 0x1002000，malloc 区间的下沿到 0x9EE5F000（推演口径）。这个结果有两头互证：board_r.c 第 232 行 initr_malloc 里写的是 `start = gd->relocaddr - TOTAL_MALLOC_LEN`，它头顶第 227 行的注释原话是 The malloc area is immediately below the monitor copy in DRAM，跟 reserve_malloc 是同一扣法。

再往下还有几格小个头。reserve_board 给 bd_info 结构留位，reserve_global_data 给新 gd 留位，咱们把 reserve_global_data 抄出来：

```bash
# 主机 ~/imx-forge
sed -n '584,591p' third_party/uboot-mainline/common/board_f.c
```

```c
static int reserve_global_data(void)
{
	gd->start_addr_sp = reserve_stack_aligned(sizeof(gd_t));
	gd->new_gd = (gd_t *)map_sysmem(gd->start_addr_sp, sizeof(gd_t));
	debug("Reserving %zu Bytes for Global Data at: %08lx\n",
	      sizeof(gd_t), gd->start_addr_sp);
	return 0;
}
```

gd_t 的尺寸 256 字节，咱们在构建生成的 generic-asm-offsets.h 里核过 GENERATED_GBL_DATA_SIZE 256。reserve_fdt 给控制设备树留位（尺寸运行时按 fdt_totalsize 算），reserve_stacks 收尾对齐 16 字节再交架构钩子。整块地皮对齐之后，为什么往高处搬就清楚了：页表贴着 64KiB 对齐线，镜像贴在页表脚下方，中间只垫着 4KiB 取整剩下的 0xCD8，malloc、bd、新 gd、fdt、栈一串塞在镜像脚下，全部住在预留块里，DDR 低处一整段干干净净留给将来要装的内核。队列注释里那句 top down in that order 说的就是这套次序。

### reloc_off 在 setup_reloc 定案

队列末段第 1052 格 setup_reloc，本体在 743 行，咱们把它翻出来：

```bash
# 主机 ~/imx-forge
sed -n '743,750p' third_party/uboot-mainline/common/board_f.c
```

```c
static int setup_reloc(void)
{
	if (!(gd->flags & GD_FLG_SKIP_RELOC)) {
#ifdef CONFIG_TEXT_BASE
#ifdef ARM
		gd->reloc_off = gd->relocaddr - (unsigned long)__image_copy_start;
#elif defined(CONFIG_MICROBLAZE)
		gd->reloc_off = gd->relocaddr - (u32)_start;
```

四个分支各有一条算式，ARM 这条拿 __image_copy_start 当减数。这个符号跟 _start 同在 0x87800000（u-boot.sym 里两行都是它，第四节咱们会亲手对），所以差值就是新家地基减旧宅起点，0x9FE61000 减 0x87800000 得 0x18661000，07 篇推的就是这个数。算完偏移，第 763 行一句 memcpy(gd->new_gd, (char *)gd, sizeof(gd_t)) 把旧 gd 整个抄进刚预留的那 256 字节，从此 gd 的继任者已经在新家住着。1057 格的 clear_bss 在这份产物里是个空壳，board_f.c 第 892 行起 __weak 修饰、函数体只有 return 0，ARM 侧没有强符号覆盖它，BSS 的清零归 crt0.S 的 CLEAR_BSS，站在搬家落地之后执行。

## 二、relocate_code 做什么：八字节一步的拷贝与修正

第二条探针对着 crt0.S：

```bash
# 主机 ~/imx-forge
grep -n "relocate_code\|copy_loop" third_party/uboot-mainline/arch/arm/lib/crt0.S | head -6
```

```text
40: * 4a.For U-Boot proper (not SPL), call relocate_code(). This function
131: * relocate_code(addr_moni). Trick here is that we'll return
161:	bl	relocate_code
163:	b	relocate_code
```

四条命中全是调用点，copy_loop 一条没有。这不是 grep 抽风，拷贝循环根本不住在 crt0.S，它的真身在 arch/arm/lib/relocate.S，咱们换个文件再扫：

```bash
# 主机 ~/imx-forge
grep -n "relocate_code\|copy_loop\|fixloop\|relocate_vectors" third_party/uboot-mainline/arch/arm/lib/relocate.S
```

```text
25:	.section	.text.relocate_vectors,"ax",%progbits
27:WEAK(relocate_vectors)
65:ENDPROC(relocate_vectors)
68: * void relocate_code(addr_moni)
76: * respect to relocate_code, and at run time, add relocate_code back to them.
79:ENTRY(relocate_code)
97:copy_loop:
101:	blo	copy_loop
111:fixloop:
133:	blo	fixloop
138:ENDPROC(relocate_code)
141:	.word	__image_copy_start - relocate_code
143:	.word	__image_copy_end - relocate_code
145:	.word	__rel_dyn_start - relocate_code
147:	.word	__rel_dyn_end - relocate_code
150:	.word	__data_start - relocate_code
152:	.word	__data_end - relocate_code
```

### crt0.S 交棒：lr 背着回家的路

board_init_f 返回之后，crt0.S 的第 135 行起把三样交接物装进寄存器，原文在第 129 行的注释里被称作中间环境，咱们抄出来：

```bash
# 主机 ~/imx-forge
sed -n '135,165p' third_party/uboot-mainline/arch/arm/lib/crt0.S
```

```asm
	ldr	r0, [r9, #GD_START_ADDR_SP]	/* sp = gd->start_addr_sp */
	bic	r0, r0, #7	/* 8-byte alignment for ABI compliance */
	mov	sp, r0
	ldr	r9, [r9, #GD_NEW_GD]		/* r9 <- gd->new_gd */

	adr	lr, here
#if defined(CONFIG_POSITION_INDEPENDENT)
	adr	r0, _main
	ldr	r1, _start_ofs
	add	r0, r1
	ldr	r1, =CONFIG_TEXT_BASE
	sub	r1, r0
	add	lr, r1
#if defined(CONFIG_ENV_RELOC_GD_ENV_ADDR)
	ldr	r0, [r9, #GD_ENV_ADDR]		/* r0 = gd->env_addr */
	add	r0, r0, r1
	str	r0, [r9, #GD_ENV_ADDR]
#endif
#endif
	ldr	r0, [r9, #GD_RELOC_OFF]		/* r0 = gd->reloc_off */
	add	lr, lr, r0
#if defined(CONFIG_CPU_V7M_V8M)
	orr	lr, #1				/* As required by Thumb-only */
#endif
	ldr	r0, [r9, #GD_RELOCADDR]		/* r0 = gd->relocaddr */
#if defined(CONFIG_SKIP_RELOCATE_CODE)
	bl	relocate_code
#else
	b	relocate_code
#endif
here:
```

咱们一句一句拆。sp 先切到新栈，start_addr_sp 在第一节算好，栈从此长在 DDR。r9 切到 new_gd，数据早在 setup_reloc 里 memcpy 过去，交接链全程不断。lr 是最巧的一手，adr lr, here 把旧宅 here 标签的地址存进 lr，再从 gd 摸出 reloc_off 加上去，lr 里躺着的就成了新宅里同一段代码的地址。AES 没配 CONFIG_POSITION_INDEPENDENT（.config 第 48 行 not set），中间那坨条件编译不参与。末尾 r0 装上 gd->relocaddr 当参数，AES 没配 SKIP_RELOCATE_CODE，走 163 行的 b，尾跳、不带 bl 的返回链接，返回全交给事先算好的 lr。第 131 行注释把这个安排叫 trick，翻译过来就是：relocate_code 会返回，返回到的 here，不过是搬过去的 here。

### relocate.S：拷贝一个循环，修正一个循环

relocate.S 第 79 行起是搬家的本体，07 篇贴过它的反汇编，本篇贴源码讲意图，咱们两边对着读：

```bash
# 主机 ~/imx-forge
sed -n '79,102p' third_party/uboot-mainline/arch/arm/lib/relocate.S
```

```asm
ENTRY(relocate_code)
relocate_base:
	adr	r3, relocate_base

#ifdef CONFIG_SKIP_RELOCATE_CODE
	mov r4,	#CONFIG_SKIP_RELOCATE_CODE_DATA_OFFSET

	ldr	r1, _data_start_ofs
	add	r5, r1, r3		/* r5 <- Run &__data_start */
	ldr	r1, _data_end_ofs
	add	r6, r1, r3		/* r6 <- Run &__data_end */
#else
	ldr	r1, _image_copy_start_ofs
	add	r1, r3			/* r1 <- Run &__image_copy_start */
	subs	r4, r0, r1		/* r4 <- Run to copy offset      */
	beq	relocate_done		/* skip relocation               */
	ldr	r2, _image_copy_end_ofs
	add	r2, r3			/* r2 <- Run &__image_copy_end   */
copy_loop:
	ldmia	r1!, {r10-r11}		/* copy from source address [r1] */
	stmia	r0!, {r10-r11}		/* copy to   target address [r0] */
	cmp	r1, r2			/* until source end address [r2] */
	blo	copy_loop
#endif
```

进门第一句 adr r3, relocate_base 拿到的是自己此刻的老位置——搬家这段代码自己还住在旧宅里。文件头第 72 行起的注释交代了为什么符号要绕：这些代码不许带上 R_ARM_ABS32 类型的重定位记录，否则 fixloop 会把它的字面量也当成待修对象，改出四个负偏移池词（141 到 147 行，池里存的是各符号减 relocate_code 的差），运行时拿 r3 加回去还原。subs r4, r0, r1 一句算出偏移，r0 是 crt0.S 递进来的 gd->relocaddr，r1 还原出旧宅的 __image_copy_start，两下一减正是 reloc_off。偏移为零说明镜像已经在位，直接跳收工。copy_loop 每趟 ldm 加 stm 搬八个字节，咱们拿产物把趟数算出来：区间从 __image_copy_start 到 __image_copy_end，System.map 里两个符号给出 0x87800000 到 0x87987290，跨度 0x187290，即 1,602,192 字节，除以八是 200,274 趟。落点从 0x9FE61000 铺到 0x9FFE8290（推演口径）。这段区间装着 .text、.rodata、.data 全部实物，装不下 .rel.dyn（它正好从 __image_copy_end 起步，第三节用链接脚本证据兑现这句话），也装不下 BSS，BSS 本来就没有文件字节。

拷完接着修正，第 104 行起：

```bash
# 主机 ~/imx-forge
sed -n '104,120p' third_party/uboot-mainline/arch/arm/lib/relocate.S
```

```asm
	/*
	 * fix .rel.dyn relocations
	 */
	ldr	r1, _rel_dyn_start_ofs
	add	r2, r1, r3		/* r2 <- Run &__rel_dyn_start */
	ldr	r1, _rel_dyn_end_ofs
	add	r3, r1, r3		/* r3 <- Run &__rel_dyn_end */
fixloop:
	ldmia	r2!, {r0-r1}		/* (r0,r1) <- (SRC location,fixup) */
	and	r1, r1, #0xff
	cmp	r1, #R_ARM_RELATIVE
	bne	fixnext

	/* relative fix: increase location by offset */
	add	r0, r0, r4
	ldr	r1, [r0]

```

记录表一条八字节，前四字节是要修的位置，后四字节是类型信息。类型抹到低字节跟 R_ARM_RELATIVE（这个 23 咱们去 elf.h 里核过）比，对得上才修。修的手法三步：位置加偏移，指向新家里的那个字，旧值加偏移，写回去。收尾这几行在 131 行往后，咱们补一条 sed：

```bash
# 主机 ~/imx-forge
sed -n '131,136p' third_party/uboot-mainline/arch/arm/lib/relocate.S
```

```asm
fixnext:
	cmp	r2, r3
	blo	fixloop

relocate_done:
	ret	lr
```

记录表本身从旧宅读——r3 还站在旧位置，表也没被拷贝循环带走，fixloop 跑的时候，新家那两个地址一带还没人写过。ret lr 落进 lr 里背好的新地址，从此 PC 在新宅里跑。这一段机制 07 篇拿 objdump 从 0x878016b4 起逐条对过，数字与本节源码一一咬合，笔者这里不再重复贴反汇编。

### relocate_vectors：向量表跟着搬

crt0.S 第 170 行，落地后的第一件事是 relocate_vectors，真身在 relocate.S 第 27 行的弱符号里。AES 的 Cortex-A7 带安全扩展，.config 第 54 行 CONFIG_HAS_VBAR=y，走的是 VBAR 分支，咱们把这几行抄出来：

```bash
# 主机 ~/imx-forge
sed -n '38,44p' third_party/uboot-mainline/arch/arm/lib/relocate.S
```

```asm
#ifdef CONFIG_HAS_VBAR
	/*
	 * If the ARM processor has the security extensions,
	 * use VBAR to relocate the exception vectors.
	 */
	ldr	r0, [r9, #GD_RELOCADDR]	/* r0 = gd->relocaddr */
	mcr     p15, 0, r0, c12, c0, 0  /* Set VBAR */
```

向量表不用拷，镜像头上那份本来就跟着 copy_loop 搬了过去，这里只做一件事：把 gd->relocaddr 写进 VBAR 寄存器（cp15 的 c12），CPU 从此按新地址取异常入口。07 篇的反汇编里这一段就两条指令，ldr 加 mcr，咱们跟源码对过，对得上。往后 crt0.S 调 c_runtime_cpu_setup、执行 CLEAR_BSS、带着新 gd 与 gd->relocaddr 跳 board_init_r，第 190 行起的注释把这步交接写得清楚。

## 三、搬完之后的世界：7675 条记录把地址修回来

### .rel.dyn 从哪来，住在哪

修正的原料是链接期留下的重定位记录。arch/arm/config.mk 第 112 行起两行是它们的出生证明，咱们抄下来：

```bash
# 主机 ~/imx-forge
sed -n '112,113p' third_party/uboot-mainline/arch/arm/config.mk
```

```make
# needed for relocation
LDFLAGS_u-boot += -pie
```

ARM 链接 u-boot 时无条件加 -pie，链接器把每个装着绝对地址的字登记进动态重定位段。链接脚本再给这段圈出地界，咱们编出来的 out/uboot/u-boot.lds 第 43 行起：

```bash
# 主机 ~/imx-forge
sed -n '43,53p' out/uboot/u-boot.lds
```

```text
 . = ALIGN(8);
 __image_copy_end = .;
 .rel.dyn ALIGN(8) : {
  __rel_dyn_start = .;
  *(.rel*)
  __rel_dyn_end = .;
  . = ALIGN(8);
 }
 _end = .;
 _image_binary_end = .;
 .bss ADDR(.rel.dyn) (OVERLAY): {
```

__image_copy_end 一画句点，.rel.dyn 紧排其后，这兑现了第二节那句话：拷贝循环天然不带记录表。.bss 用 OVERLAY 压在 .rel.dyn 的同一段地址上，没有文件字节，咱们在 System.map 里能看见 __bss_start、__image_copy_end、__rel_dyn_start 三个符号同在 0x87987290 的奇观，根子就在这个 OVERLAY。

第三条探针本该打在 /tmp/uboot-ref-aes 的产物上，grep 原样报错：grep: /tmp/uboot-ref-aes/u-boot.map: No such file or directory。这台主机没有那份快照，咱们按 tip 里的声明改打仓库自产的地图文件：

```bash
# 主机 ~/imx-forge
sed -n '15470p;15471p;18729p' out/uboot/u-boot.map
```

```text
.rel.dyn        0x87987290     0xefd8
                0x87987290                        __rel_dyn_start = .
                0x87996268                        __rel_dyn_end = .
```

段的尺寸 0xEFD8，61,400 字节，一条记录八字节，正好 7675 条。咱们拿 readelf 再数一遍：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-readelf -r out/uboot/u-boot | awk "/Relocation section '.rel.dyn'/{f=1} /^Relocation section '.rel.dyn'/{next} f==0{next} /^Relocation section|^$/{exit} /R_ARM/{c++} END{print c}"
```

```text
7675
```

两个口径咬上了，咱们两边都数过。这批记录不是运行期攒出来的——链接器在 -pie 下早就把它们备好，BootROM 按链接地址把整段实物铺进 DDR 时它们就在原地。readelf -l 给出佐证：u-boot 只有一个 LOAD 段，从 0x87800000 起盖 0x196268 字节，正好到 System.map 的 _end（0x87996268），记录表的 61,400 字节就住在这段实物里。

### fixloop 怎么改一条记录

记录长什么样，咱们挑一条新的来看。env_relocate 是 board_init_r 队列里要调的函数，反汇编里它的字面量池只有一个词：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d --start-address=0x878317e4 --stop-address=0x878317f8 out/uboot/u-boot | sed -n '7,14p'
```

```text
878317e4 <env_relocate>:
878317e4:	f899 1056 	ldrb.w	r1, [r9, #86]	@ 0x56
878317e8:	b911      	cbnz	r1, 878317f0 <env_relocate+0xc>
878317ea:	4802      	ldr	r0, [pc, #8]	@ (878317f4 <env_relocate+0x10>)
878317ec:	f7ff bf3c 	b.w	87831668 <env_set_default>
878317f0:	f000 b8b0 	b.w	87831954 <env_load>
878317f4:	87863384 	.word	0x87863384
```

池词 0x878317f4 里存着 0x87863384，那是 .rodata 里一个字符串的链接地址。它有没有登记在案，咱们问 readelf：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-readelf -r out/uboot/u-boot | grep -w "878317f4"
```

```text
878317f4  00000017 R_ARM_RELATIVE   
```

00000017 的低字节 23 正是 fixloop 认的那个类型。运行期的数咱们按推演口径算：位置 0x878317f4 加 0x18661000 得 0x9FE927F4，fixloop 从新宅这个词里读出抄过来的旧值 0x87863384，加偏移得 0x9FEC4384 写回去。7675 条记录全是这套三步，执行完的那一刻，新宅里每个装绝对地址的字都指向新宅自己，全局变量、字符串字面量、函数指针集体复活。crt0.S 里 CLEAR_BSS 那三行 `/* this is auto-relocated! */` 的注释说的就是这层保障，咱们把宏抄出来：

```bash
# 主机 ~/imx-forge
sed -n '68,76p' third_party/uboot-mainline/arch/arm/lib/crt0.S
```

```asm
.macro CLEAR_BSS
	ldr	r0, =__bss_start	/* this is auto-relocated! */

#ifdef CONFIG_USE_ARCH_MEMSET
	ldr	r3, =__bss_end		/* this is auto-relocated! */
	mov	r1, #0x00000000		/* prepare zero to clear BSS */

	subs	r2, r3, r0		/* r2 = memset len */
	bl	memset
```

=__bss_start 这个池词自己也有记录，fixloop 修过它才指向新 BSS。新 BSS 的区间咱们按同一口径算，是 0x9FFE8290 到 0x9FFEF328，跟页表起步的 0x9FFF0000 之间还剩 0xCD8 空隙，07 篇定的那块地皮刚好装下镜像加 BSS，扣完 BSS 只剩 0xCD8，连一页都腾不出来。

::: warning 旧地址的字节还在，别当活代码
后果是错得不报错。搬家是复制不是移动，0x87800000 一带的旧拷贝搬完之后没人清也没人维护，拿 md（U-Boot 的内存显示命令，按地址把内存打成十六进制）看，旧地址那段指令字节看着完好，对着它单步、改数据、下条件，全都落在新宅看不见的地方，串口不吭声，行为诡异。根因是 relocate_code 完成后维护只发生在新址，旧宅从那一刻起就没人再看它，出了错也不会有人发现。解法咱们记一条：核地址先做换算——拿 bdinfo 的 relocaddr 与 reloc off 两行（读法在 [调试命令速查：命令行是嵌入式开发的神器](../14_debug_reference.md)，md 的用法那篇暂未收录，以本条括注为准）把链接地址加上偏移，再落到 System.map 上对符号。
:::

### 全局变量复活之后的队列

board_init_r 进门收到的两个参数正是新 gd 和 gd->relocaddr（crt0.S 第 190 到 192 行），此后整条 init_sequence_r 都在新宅执行。队列前段有几格跟本篇直接接榫，咱们把 grep 抄下来：

```bash
# 主机 ~/imx-forge
grep -n "initr_malloc\|mem_malloc_init\|env_relocate\|console_init_r" third_party/uboot-mainline/common/board_r.c | head -10
```

```text
219:static int initr_malloc(void)
234:	mem_malloc_init(start, TOTAL_MALLOC_LEN);
451:		env_relocate();
473:static int initr_malloc_bootparams(void)
619:	INITCALL(initr_malloc);
714:	INITCALL(initr_malloc_bootparams);
734:	INITCALL(console_init_r);	/* fully init console as a device */
```

第 619 格 initr_malloc 把第一节算好的那块 0x1002000（16 MiB 加 8 KiB）正式划给堆分配，第 734 格 console_init_r 就是 09 篇排时刻表时挂 DEVINIT 标志的那一格，console 从此升格成可重定向的标准设备。env_relocate 在 initr_env 里被调（第 451 行），它去 eMMC 把环境读回来，那是下一篇的主场，咱们到那边接着排 env 加载与倒计时的源码路径。

## 四、自证：在 u-boot.sym 上对出两套地址

u-boot.sym 是链接器的符号表，里头只有链接地址。运行地址不在任何现成文件里，它等于链接地址加 reloc_off，咱们把十个符号抓出来算：

```bash
# 主机 ~/imx-forge
grep -w "_start\|__image_copy_start\|board_init_f\|board_init_r\|main_loop\|do_bootm\|env_relocate\|env_htab\|mem_malloc_start\|console_buffer\|init_sequence_r\|init_sequence_f" out/uboot/u-boot.sym
```

```text
8798a280 g     O .bss	00000201 console_buffer
87983c10 g     O .data	00000010 env_htab
878137d0 g     F .text_rest	0000003c main_loop
87815ca4 g     F .text_rest	00000254 board_init_r
87809c2c g     F .text_rest	000000d4 do_bootm
87800000 g       .text	00000000 _start
8798a944 g     O .bss	00000004 mem_malloc_start
878317e4 g     F .text_rest	00000014 env_relocate
87815850 g     F .text_rest	00000448 board_init_f
87800000 g       .text	00000000 __image_copy_start
```

grep 没给咱们 init_sequence_r 与 init_sequence_f 这两行，因为这两个名字在源码里就不存在：队列不是数组，是 initcall_run_f / initcall_run_r 函数体内 INITCALL 直调宏的顺序展开，被直调的 static 函数连符号都没有，setup_reloc、initr_malloc 在符号表里同样搜不到。.rel.dyn 里的记录按编译后真实存在的字登记，源码里的名字它不认。十个有名字的符号加偏移，数目如下（偏移 0x18661000 为 07 篇推演值）：

| 符号 | 所在段 | u-boot.sym 链接地址 | 推演运行地址 |
|---|---|---|---|
| _start | .text | 0x87800000 | 0x9FE61000 |
| __image_copy_start | .text | 0x87800000 | 0x9FE61000 |
| do_bootm | .text_rest | 0x87809c2c | 0x9FE6AC2C |
| main_loop | .text_rest | 0x878137d0 | 0x9FE747D0 |
| board_init_f | .text_rest | 0x87815850 | 0x9FE76850 |
| board_init_r | .text_rest | 0x87815ca4 | 0x9FE76CA4 |
| env_relocate | .text_rest | 0x878317e4 | 0x9FE927E4 |
| env_htab | .data | 0x87983c10 | 0x9FFE4C10 |
| console_buffer | .bss | 0x8798a280 | 0x9FFEB280 |
| mem_malloc_start | .bss | 0x8798a944 | 0x9FFEB944 |

每一行右边都等于左边加同一个 0x18661000，十个符号没有一个例外，函数与数据共用同一次搬家。这就是自证的全部门道：任意挑一个符号，sym 值加 bdinfo 打出的 reloc off，落到的就是板上真实的运行地址。board 端的核对咱们只能先写在纸上：

## 继续学习

- [链接地址与运行地址对不上的日子](./07_relocation_limits.md)：分家的现象、搬家前的生存法则与 relocate_code 的反汇编在那篇，本篇的源码层与它逐条咬合。
- [env 加载与倒计时：接管前的最后准备](./12_env_and_autoboot.md)：搬家落定之后 board_init_r 队列怎么走到 env_relocate，env 与倒计时在那篇接着排。
- [调试命令速查：命令行是嵌入式开发的神器](../14_debug_reference.md)：bdinfo 的 relocaddr 与 reloc off 两行怎么读，板子在手边时咱们靠它核出真实坐标。
