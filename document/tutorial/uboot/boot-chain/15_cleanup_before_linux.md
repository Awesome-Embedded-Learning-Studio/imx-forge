---
title: cleanup_before_linux：交接前把场地清干净
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# cleanup_before_linux：交接前把场地清干净

> bootz 打完 Starting kernel ... 之后、内核第一条指令跑起来之前，中间还隔着一段清场加交接:D-cache 里的脏行要送回主存，中断要保证掩蔽，MMU 要关掉，然后 r0、r1、r2 装好三个值跳过去。本篇带咱们把这段路走到指令级，清场函数 cleanup_before_linux 逐条过，跳转参数的来路逐个追。扩展卷上一篇 [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md) 停在 => 等人敲命令，本篇从命令敲下去那一刻接着走。主线 [启动 Linux:把内核装进板子完成交接](../12_boot_linux.md) 讲的是 bootz 的行为层，本篇往源码里再下一层，跳过去之前处理器被收拾成什么样，源码与产物两头对。

## 一、为什么内核怕脏现场

### 交接那一刻 U-Boot 手里是什么

咱们先把交接前的现场摆出来。提示符等人时，U-Boot 的 D-cache 开着，enable_caches 由重定位后的初始化序列调，位置在 common/board_r.c 的初始化表里。这个函数在 arch/arm/mach-imx/cache.c 里有两支，按 CONFIG_SYS_DCACHE_OFF 分开，AES 构建编进产物的是缓存开启那一支，函数体明确写着 dcache_enable(),MMU 跟着页表一起在跑。异常向量表也搬过家了，relocate_vectors 把重定位后的地址写进 VBAR(Vector Base Address Register,向量基址寄存器，07 章)。这时的 DRAM 上躺着不少东西：0x87800000 一带的旧拷贝、页表、malloc 池、栈和 gd(global data,U-Boot 全程随身的全局数据结构)，加上 0x82000000 的 zImage 与 0x83000000 的 DTB,全挤同一条内存上。

crt0.S 把答案写在注释里，咱们把 129 到 133 行搬过来：

```c
/*
 * Set up intermediate environment (new sp and gd) and call
 * relocate_code(addr_moni). Trick here is that we'll return
 * 'here' but relocated.
 */
```

搬家那次调用没有回头路。crt0.S 第 159 行起的尾巴把 gd->relocaddr 装进 r0、尾跳 relocate_code,返回落点是搬过去的 here 标签。咱们跟着这段尾巴走一遍，从那一刻起 0x87800000 的旧拷贝再没有指令踏进去：

```c
	ldr	r0, [r9, #GD_RELOCADDR]		/* r0 = gd->relocaddr */
#if defined(CONFIG_SKIP_RELOCATE_CODE)
	bl	relocate_code
#else
	b	relocate_code
#endif
here:
```

这个背景到交接时还有一层意思：跑 cleanup_before_linux 的是重定位后的那份代码，内核一接手就按 FDT 里 /memory 声明的口径把整条 DRAM 接管，旧拷贝、页表、malloc 池、栈、gd 全成了等着被覆盖的空壳。咱们记住这一点，清场动作收拾的是 CPU 状态，场地本身内核进场后自己扫。

### 内核进场前开出的条件

内核侧的要求写在 third_party/linux_mainline/Documentation/arch/arm/booting.rst,咱们把缓存与 MMU 那一小节原文搬过来：

```text
- Caches, MMUs

  The MMU must be off.

  Instruction cache may be on or off.

  Data cache must be off.
```

中断那一条住在 CPU mode 小节，原文是 All forms of interrupts must be disabled (IRQs and FIQs),SVC 模式(带虚拟化扩展的平台也可走 HYP)要在这一刻就位。寄存器层面的 r0、r1、r2 留给第三节，这里咱们盯着三样可能残留的东西:D-cache 里的脏行、可能开着的异常源、MMU 的映射，一样一样看它们能把启动搅成什么样。

### 三样残留各自能把启动搅成什么样

脏行的事根子在回写策略。D-cache 开着，SCTLR 的 C 位置上，普通内存的读写都进 cache,回写型策略下写命中只改 cache 行、标个脏位，主存维持旧值。ext4load 读文件、printf 打日志这一路下来，cache 里难免压着脏行。跳过去之前不 flush,脏行继续赖着，内核一开 MMU 重建映射、cache 一被换出，旧数据回写主存，砸的是内核已经写过的新内容。现象是咱们最不想见的那种：起来就随机死，改一行代码症状就挪窝，复现全看运气。

中断这条，本系列的板子其实占了个便宜。U-Boot 在 ARMv7 上从复位起就没开过中断，CPSR 的 I、F 位一直掩着，向量表虽然被 relocate_vectors 搬过家，从没人触发过它。可咱们别急着把 cleanup_before_linux 里的关中断调用当成白写的：有些平台真开过中断，VBAR 还指着引导程序的表，内核早期的异常处理没接手前进来一针 IRQ,CPU 就跳回废弃代码里，串口停在半句话上不动。机制得立在那，平台换了它就干活。

MMU 残留最直接。U-Boot 的页表把 DRAM 映成带 cache 属性的区域、外设区另立映射，内核假设进来时 MMU 是关的，它要按自己的布局重立。MMU 要是还开着，内核取指访存仍走 U-Boot 那套映射，清 BSS、立栈都可能落到没映射的地址，第一条 abort 就把启动摁死在起跑线上。三样残留对应清场函数里的三件事，下一节咱们逐条对。

## 二、cleanup_before_linux 逐条

### 函数外壳与两个分支

函数的户口在 third_party/uboot-mainline/arch/arm/cpu/armv7/cpu.c,咱们按行号把两个函数抓出来：

```bash
# 主机 ~/imx-forge
grep -n "cleanup_before_linux" third_party/uboot-mainline/arch/arm/cpu/armv7/cpu.c | head -4
```

```text
27:int cleanup_before_linux_select(int flags)
81:int cleanup_before_linux(void)
83:	return cleanup_before_linux_select(CBL_ALL);
```

真正干活的是第 27 行的 cleanup_before_linux_select,第 81 行那个无人不知的名字只是个壳。壳里传的 CBL_ALL 来自 include/cpu_func.h 第 106 到 109 行：CBL_DISABLE_CACHES 等于 1 << 0,CBL_SHOW_BOOTSTAGE_REPORT 等于 1 << 1,CBL_ALL 等于 3。函数体咱们分三段看：

```c
int cleanup_before_linux_select(int flags)
{
	/*
	 * this function is called just before we call linux
	 * it prepares the processor for linux
	 *
	 * we turn off caches etc ...
	 */
#ifndef CONFIG_XPL_BUILD
	disable_interrupts();
#endif

	if (flags & CBL_DISABLE_CACHES) {
		/*
		* turn off D-cache
		* dcache_disable() in turn flushes the d-cache and disables MMU
		*/
		dcache_disable();
```

```c
		v7_outer_cache_disable();

		/*
		* After D-cache is flushed and before it is disabled there may
		* be some new valid entries brought into the cache. We are
		* sure that these lines are not dirty and will not affect our
		* execution. (because unwinding the call-stack and setting a
		* bit in CP15 SCTRL is all we did during this. We have not
		* pushed anything on to the stack. Neither have we affected
		* any static data) So just invalidate the entire d-cache again
		* to avoid coherency problems for kernel
		*/
		invalidate_dcache_all();

		icache_disable();
		invalidate_icache_all();
	} else {
		/*
		 * Turn off I-cache and invalidate it
		 */
		icache_disable();
		invalidate_icache_all();

		flush_dcache_all();
		invalidate_icache_all();
		icache_enable();
	}
```

两个分支给两类平台准备。咱们这条主路把 D-cache 整条关掉：dcache_disable 内部先 flush 再关(下一小节展开)，v7_outer_cache_disable 管外层二级缓存，然后按注释的意思把整条 D-cache 再 invalidate 一遍，收尾关 I-cache 并 invalidate。else 分支留给不关缓存的平台：I-cache 关了马上开回来，D-cache 只 flush 不关。那段英文注释交代了二次 invalidate 的理由，翻译过来是：flush 与 disable 之间可能有新有效行进 cache,脱个栈、写一次 SCTLR 就够做出这种行，它们保证不脏，但为了不给内核留一致性问题，整条再清一遍。

```c
	/*
	 * Some CPU need more cache attention before starting the kernel.
	 */
	cpu_cache_initialization();

	return 0;
}

int cleanup_before_linux(void)
{
	return cleanup_before_linux_select(CBL_ALL);
}
```

cpu_cache_initialization 是第 25 行的 __weak 空函数，留给个别 CPU 补额外的活，i.MX6ULL 这边它是条 bx lr。到此源码层面咱们拿到了完整的顺序：关中断、dcache_disable、v7_outer_cache_disable、invalidate_dcache_all、icache_disable、invalidate_icache_all、cpu_cache_initialization,返回 0。

### 关中断：机制在，这份产物里是空操作

disable_interrupts 在 ARMv7 的现实是两个空函数，咱们把 arch/arm/lib/interrupts.c 第 44 到 51 行搬过来：

```c
void enable_interrupts(void)
{
	return;
}
int disable_interrupts(void)
{
	return 0;
}
```

interrupt_init 在重定位后的序列里排着，位置挂在 common/board_r.c 的 INITCALL 表里，它调的 enable_interrupts 也是空壳。也就是说 ARMv7 的 U-Boot 从复位起就没开过中断，第一节说的那个便宜在这里兑现。cmd/bootz.c 第 96 行 do_bootz 还自己调了一次 bootm_disable_interrupts,产物里那个符号就是一条跳转，落到同一个空函数上。这套调用给真开过中断的平台留着位置，本篇第四节咱们拿 objdump 把这条跳转看清楚。

### dcache_disable:清脏行与摘 MMU 是同一步

第一节说过协议要求 MMU 必须关、D-cache 必须关，咱们往下翻源码，会看到这两件事挤在同一个函数里干。dcache_disable 住在 arch/arm/lib/cache-cp15.c,这个文件里有两份同名函数，SYS_DCACHE_OFF 打开时那份只有一行 return,AES 缓存开着，编进产物的是第 318 行这份，它转手调的 cache_disable 核心几行在第 236 到 255 行：

```c
	reg = get_cr();

	if (cache_bit == CR_C) {
		/* if cache isn;t enabled no need to disable */
		if ((reg & CR_C) != CR_C)
			return;
#ifdef CONFIG_SYS_ARM_MMU
		/* if disabling data cache, disable mmu too */
		cache_bit |= CR_M;
#endif
	}
	reg = get_cr();

#ifdef CONFIG_SYS_ARM_MMU
	if (cache_bit == (CR_C | CR_M))
#elif defined(CONFIG_SYS_ARM_MPU)
	if (cache_bit == CR_C)
#endif
		flush_dcache_all();
	set_cr(reg & ~cache_bit);
```

顺序是讲究过的：关 D-cache 时把 CR_M 一起并进掩码(带 MMU 的配置下)，flush_dcache_all 把脏行整条送回主存，然后 set_cr 一次性摘掉 SCTLR 的 C 位(bit 2)与 M 位(bit 0)。这个先后不能倒：MMU 先关、脏行还在 cache 里，后续取指拿到的就是旧映射下的旧行。关 MMU 的动作就藏在这几条里，cpu.c 注释那句 dcache_disable() in turn flushes the d-cache and disables MMU 说的正是它。flush_dcache_all 转手进 v7_flush_dcache_all,按 CLIDR 寄存器报的层级逐层扫 set 与 way,每条一发 clean 兼 invalidate 的 CP15 指令，收尾 dsb 加 isb 保证 `store` 全部落地才继续走。v7_outer_cache_disable 在这颗芯片上是空壳：i.MX6ULL 这一代没有挂外层二级缓存，没东西可关，第四节反汇编里咱们还要跟它对上一次，就一条 bx lr。

### 二次 invalidate 与 I-cache 收尾

invalidate_dcache_all 跟 flush 走的是同一套循环骨架，差别只在每条 set/way 发的指令：invalidate 版发的是失效那一条，行里的数据不管脏不脏直接扔。这一遍扔掉的是 flush 与 disable 窗口里新冒出来的有效行，注释保证它们不脏，扔了不伤数据，留着反而给内核添一致性麻烦。然后轮到 I-cache:icache_disable 摘 SCTLR 的 I 位，invalidate_icache_all 清标签数组。后者在产物里一共六条指令，两条 CP15 写、dsb、isb,第二条写的还是分支预测数组，预测器里缓的跳转目标一并作废，这是咱们容易漏想的死角。协议说 I-cache 开着或关着都行(Instruction cache may be on or off),U-Boot 选了关，关得干干净净。

## 三、boot_jump_linux 与参数约定

### 协议三条与两条 grep

跳转的活全在 arch/arm/lib/bootm.c 的 boot_jump_linux 里，咱们把两条 grep 一起跑：

```bash
# 主机 ~/imx-forge
grep -n "boot_jump_linux\|kernel_entry" third_party/uboot-mainline/arch/arm/lib/bootm.c | head -6
```

```text
257:static void boot_jump_linux(struct bootm_headers *images, int flag)
259:	void (*kernel_entry)(void *fdt_addr, void *res0, void *res1,
261:	kernel_entry = (void (*)(void *fdt_addr, void *res0, void *res1,
265:		(ulong) kernel_entry);
300:static void boot_jump_linux(struct bootm_headers *images, int flag)
304:	void (*kernel_entry)(int zero, int arch, uint params);
```

```bash
# 主机 ~/imx-forge
grep -n "r0\|machine_type\|r2" third_party/uboot-mainline/arch/arm/lib/bootm.c | head -6
```

```text
305:	unsigned long r2;
334:		r2 = (unsigned long)images->ft_addr;
336:		r2 = gd->bd->bi_boot_params;
348:		boot_jump_linux_via_optee(kernel_entry, machid, r2, boot_jump_via_optee_addr);
353:		secure_ram_addr(_do_nonsec_entry)(kernel_entry, 0, machid, r2);
357:		kernel_entry(0, machid, r2);
```

这份文件里住着两个同名函数，257 行那份整个裹在 #ifdef CONFIG_ARM64 里，32 位的实现在 300 行起，AES 是 ARMv7 的 32 位板，咱们对着的产物走的是 300 这份，304 行的函数指针签名 (int zero, int arch, uint params) 对应 r0、r1、r2。第二条 grep 里 machine_type 一个词都没搜到，前六条全是 r2 相关的行：内核文档管 r1 叫 machine type,U-Boot 源码里这个名字叫 machid,叫法不同，装的是同一个东西。

协议那三条在 booting.rst 第 190 到 195 行，咱们把原文搬过来：

```text
- CPU register settings

  - r0 = 0,
  - r1 = machine type number discovered in (3) above.
  - r2 = physical address of tagged list in system RAM, or
    physical address of device tree block (dtb) in system RAM
```

r0 必须是 0,r1 是机器型号，r2 是参数区的物理地址，FDT 时代就是 DTB 的地址。机器型号那一小节还有句话值得咱们记住：DT-only 平台的型号由设备树定，文档建议 r1 填全一(~0),免得跟现存型号重号，又说这不是严格必要的。U-Boot 走的路子是把 bd->bi_arch_number 原样递进去，这块板的代码从没给这个字段赋过值(board/nxp/mx6ull_aes_emmc/ 下搜 bi_arch_number 零命中)，它一路是 0。内核走 FDT 启动时靠设备树认硬件，r1 实际没人读，所以这层出入没惹过事，但谁要是哪天把它当真的机器型号用，就会在这里摔一跤。

### 内核入口的真实来路

304 行签名下面第 306 行就是赋值：kernel_entry = (void (*)(int, int, uint))images->ep。入口的来路不在 bootm.c,在 cmd/bootz.c 的 bootz_start:bootz 命令带参数时 images->ep = hextoul(argv[0])(第 51 行)，不带参数落 image_load_addr(第 47 行)。这条链上 argv[0] 咱们追过三层证据，就是 ${loadaddr} 即 0x82000000(Kconfig 给 MX6ULL 一代的缺省，三层证据的追法在主线 12 章)，随后 bootz_setup 拿镜像第 36 到 39 字节的魔数验明正身，arch/arm/lib/zimage.c 第 11 行写着 LINUX_ARM_ZIMAGE_MAGIC 0x016f2818。内核入口不从 FDT 来——FDT 只出 r2 那一个地址，入口是 bootz 第一个参数递进来的，zImage 头上那段自解压代码的起点。

### r2 的两个来路

跳之前咱们看 bootm.c 第 330 到 336 行，r2 就在这里定下来：

```c
	bootm_final(flag);
	cleanup_before_linux();

	if (CONFIG_IS_ENABLED(OF_LIBFDT) && images->ft_len)
		r2 = (unsigned long)images->ft_addr;
	else
		r2 = gd->bd->bi_boot_params;
```

正常链路走 ft_addr。这个字段的搬运链咱们串一遍：bootm_find_images 调 boot_get_fdt,两个函数分别在 boot/bootm.c 与 boot/image-fdt.c,后者把 bootz 第三个参数 0x83000000 记进 images->ft_addr 与 ft_len。交接前 boot_relocate_fdt 在 image-fdt.c 里复核落点，要挪才挪，挪的时候打一行 Loading Device Tree to ...（第 313 行）,这句格式串在 out/uboot/u-boot 里搜得到。ft_len 是零时才落 bi_boot_params,bootz 的帮助文本写明了这层意思，cmd/bootz.c 里那两行写着：不给第三个参数就传 bd_info 结构，内核按老 ATAGS 那套读参数区(ATAGS 就是前文引文里的 tagged list,FDT 流行前的启动参数列表)。这条道咱们不走，FDT 才是这颗芯片的正路。

### 跳转那一刻寄存器的样子

上面代码里 cleanup_before_linux 之后的分岔，咱们把产物里的样子搬出来对一对：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot --start-address=0x8780150e --stop-address=0x87801538 | sed -n '5,20p'
```

```text
8780150e <boot_jump_linux+0x2e>:
8780150e:	4620      	mov	r0, r4
87801510:	f003 faa0 	bl	87804a54 <bootm_final>
87801514:	f7ff ff7a 	bl	8780140c <cleanup_before_linux>
87801518:	f8d5 30a4 	ldr.w	r3, [r5, #164]	@ 0xa4
8780151c:	b143      	cbz	r3, 87801530 <boot_jump_linux+0x50>
8780151e:	f8d5 20a0 	ldr.w	r2, [r5, #160]	@ 0xa0
87801522:	f414 7000 	ands.w	r0, r4, #512	@ 0x200
87801526:	d101      	bne.n	8780152c <boot_jump_linux+0x4c>
87801528:	9901      	ldr	r1, [sp, #4]
8780152a:	47b0      	blx	r6
8780152c:	b002      	add	sp, #8
8780152e:	bd70      	pop	{r4, r5, r6, pc}
87801530:	f8d9 3000 	ldr.w	r3, [r9]
```

顺序照源码：bootm_final 在前，它打 Starting kernel ...,board_quiesce_devices 停 DMA 设备，dm_remove_devices_active 拆带移除标记的设备，实现在 boot/bootm.c 第 1245 行往下排开，cleanup_before_linux 紧随其后，然后查 ft_len 定 r2。最妙的是 0x87801522 那条 ands.w r0, r4, #512:一条指令干两件事，测 BOOTM_STATE_OS_FAKE_GO(0x200)在不在 flag 里，非零就地返回。零的话 r0 也被它顺手写成 0。协议要的 r0 清零没靠任何一条 mov 完成，是编译器捎带的。r1 从栈槽里取回 machid(入函数时存的 bd->bi_arch_number,环境变量 machid 存在时 strict_strtoul 按十六进制重解析并盖掉，盖成功还会打一行 Using machid 0x%lx from environment,这句在产物里搜得到)，r2 已在寄存器里，blx r6 跳进 r6 存的 images->ep。咱们把四个去处汇成一张表：

| 去处 | 跳过去时装的什么 | 出处 |
|------|----------------|------|
| r0 | 0(ands.w r4, #512 顺带写成的) | bootm.c 357,反汇编 0x87801522 |
| r1 | machid,来自 bd->bi_arch_number,环境变量 machid 可盖 | bootm.c 302、318 |
| r2 | images->ft_addr,没有 FDT 时 gd->bd->bi_boot_params | bootm.c 334、336 |
| pc | images->ep,即 bootz 第一个参数 0x82000000 | bootm.c 306,cmd/bootz.c 51 |

CPU 模式与外围状态也跟协议对得上：AES 的构建没编 CONFIG_ARMV7_NONSEC(out/uboot/generated_defconfig 里搜 NONSEC 零命中)，咱们在反汇编里也找不到 nonsec 分支，kernel_entry(0, machid, r2) 直落 secure 路径，bootm.c 第 351 行往下那几行就是它，模式还是复位起的 SVC。中断靠的是复位默认的掩蔽。I-cache、D-cache、MMU 三样，由第二节那套动作关掉。

::: warning machid 设错值的后果
后果是串口当场死寂。咱们手滑带个 g,setenv machid 后面跟的就是一个解析不了的值，strict_strtoul 失败后函数只走 debug() 打印，位置在 bootm.c 的 machid 解析处，debug 级日志平常看不见，然后直接 return,连 bootm_final 的 Starting kernel ... 都轮不到打，屏幕停在提示符之后一动不动。根因是解析检查排在 bootm_final 之前：strict_strtoul 在 0x878014fe,解析失败时 0x87801504 的 blt 直接落到 0x8780152c 的收尾两条，0x87801510 的 bl bootm_final 在失败路径上到不了。失败路径一条话都没有，这段现场咱们贴出来，步数可以自己数：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot --start-address=0x878014e0 --stop-address=0x8780150e | sed -n '7,25p'
```

```text
878014e0 <boot_jump_linux>:
878014e0:	b573      	push	{r0, r1, r4, r5, r6, lr}
878014e2:	f8d9 3000 	ldr.w	r3, [r9]
878014e6:	4605      	mov	r5, r0
878014e8:	6adb      	ldr	r3, [r3, #44]	@ 0x2c
878014ea:	f8d0 6094 	ldr.w	r6, [r0, #148]	@ 0x94
878014ee:	4812      	ldr	r0, [pc, #72]	@ (87801538 <boot_jump_linux+0x58>)
878014f0:	460c      	mov	r4, r1
878014f2:	9301      	str	r3, [sp, #4]
878014f4:	f02f fffa 	bl	878314ec <env_get>
878014f8:	b148      	cbz	r0, 8780150e <boot_jump_linux+0x2e>
878014fa:	2110      	movs	r1, #16
878014fc:	aa01      	add	r2, sp, #4
878014fe:	f04b fcb9 	bl	8784ce74 <strict_strtoul>
87801502:	2800      	cmp	r0, #0
87801504:	db12      	blt.n	8780152c <boot_jump_linux+0x4c>
87801506:	9901      	ldr	r1, [sp, #4]
87801508:	480c      	ldr	r0, [pc, #48]	@ (8780153c <boot_jump_linux+0x5c>)
8780150a:	f04b fc17 	bl	8784cd3c <printf>
```

救回来不费事：setenv machid 不带值即删除该变量，再 saveenv,字段回到 bd 里的原值。
:::

## 四、拿产物自证：objdump 与完整链路

### 反汇编对出来的一串地址

自证对着自己的产物跑才有分量。out/uboot 是 10 月 20 日的 AES 构建，7041816 字节的 u-boot ELF 还在，咱们拿 nm 把清场这条链上的符号一次列出来：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-nm out/uboot/u-boot | grep -i "cleanup_before_linux\|flush_dcache_all\|invalidate_dcache_all\|invalidate_icache_all\|disable_interrupts\|icache_disable\|dcache_disable"
```

```text
87801274 T __v7_flush_dcache_all
87801320 T __v7_invalidate_dcache_all
87804434 T bootm_disable_interrupts
8780140c T cleanup_before_linux
878013ce T cleanup_before_linux_select
87801fa6 T dcache_disable
87801b66 T disable_interrupts
8780119a T flush_dcache_all
87801f20 T icache_disable
878011aa T invalidate_dcache_all
87801180 T invalidate_icache_all
87801310 T v7_flush_dcache_all
878013bc T v7_invalidate_dcache_all
```

咱们看到的这些是链接地址——真实执行地址要加上 07 章推演的 reloc off(0x18661000),板上 bdinfo 可核。壳只有两条指令：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot --start-address=0x8780140c --stop-address=0x87801412 | sed -n '6,9p'
```

```text

8780140c <cleanup_before_linux>:
8780140c:	2003      	movs	r0, #3
8780140e:	f7ff bfde 	b.w	878013ce <cleanup_before_linux_select>
```

movs r0, #3 就是 CBL_ALL,那个 3 咱们在 include/cpu_func.h 数过，尾跳进选择器。选择器的全身在这儿，咱们逐条看：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot --start-address=0x878013ce --stop-address=0x8780140c | sed -n '5,32p'
```

```text
Disassembly of section .text_rest:

878013ce <cleanup_before_linux_select>:
878013ce:	b510      	push	{r4, lr}
878013d0:	4604      	mov	r4, r0
878013d2:	f000 fbc8 	bl	87801b66 <disable_interrupts>
878013d6:	07e3      	lsls	r3, r4, #31
878013d8:	d50d      	bpl.n	878013f6 <cleanup_before_linux_select+0x28>
878013da:	f000 fde4 	bl	87801fa6 <dcache_disable>
878013de:	f7ff feda 	bl	87801196 <v7_outer_cache_disable>
878013e2:	f7ff fee2 	bl	878011aa <invalidate_dcache_all>
878013e6:	f000 fd9b 	bl	87801f20 <icache_disable>
878013ea:	f7ff fec9 	bl	87801180 <invalidate_icache_all>
878013ee:	f7ff ffed 	bl	878013cc <cpu_cache_initialization>
878013f2:	2000      	movs	r0, #0
878013f4:	bd10      	pop	{r4, pc}
878013f6:	f000 fd93 	bl	87801f20 <icache_disable>
878013fa:	f7ff fec1 	bl	87801180 <invalidate_icache_all>
878013fe:	f7ff fecc 	bl	8780119a <flush_dcache_all>
87801402:	f7ff febd 	bl	87801180 <invalidate_icache_all>
87801406:	f000 fd82 	bl	87801f0e <icache_enable>
8780140a:	e7f0      	b.n	878013ee <cleanup_before_linux_select+0x20>
```

咱们逐条念。0x878013d2 调 disable_interrupts,跳去 0x87801b66,那边一共两条：movs r0, #0 加 bx lr,第二节说的空操作在这里落实。第二节『关中断』那小节说的 bootm_disable_interrupts 咱们在这里补上看，它本身就一条跳转，两条指令在它落点的本体上：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot --start-address=0x87804434 --stop-address=0x87804438 | sed -n '7,8p'
```

```text
87804434 <bootm_disable_interrupts>:
87804434:	f7fd bb97 	b.w	87801b66 <disable_interrupts>
```

跳转落点 0x87801b66 就是那个空函数：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot --start-address=0x87801b66 --stop-address=0x87801b6a | sed -n '7,9p'
```

```text
87801b66 <disable_interrupts>:
87801b66:	2000      	movs	r0, #0
87801b68:	4770      	bx	lr
```

lsls r3, r4, #31 把 flags 的位 0 顶进 N 位，位 0 是 0 就 bpl 去 0x878013f6 的 else 分支。CBL_ALL 的位 0 是 1,落下来的路径是 0x878013da 起的五连发：dcache_disable、v7_outer_cache_disable(0x87801196,一条 bx lr 的空壳，外层 L2 无可关)、invalidate_dcache_all、icache_disable、invalidate_icache_all,然后 cpu_cache_initialization(0x878013cc,bx lr),返回 0。dcache_disable 的反汇编，咱们也贴出来：

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot --start-address=0x87801fa6 --stop-address=0x87801fc4 | sed -n '5,15p'
```

```text
Disassembly of section .text_rest:

87801fa6 <dcache_disable>:
87801fa6:	b510      	push	{r4, lr}
87801fa8:	ee11 3f10 	mrc	15, 0, r3, cr1, cr0, {0}
87801fac:	075b      	lsls	r3, r3, #29
87801fae:	d509      	bpl.n	87801fc4 <dcache_disable+0x1e>
87801fb0:	ee11 4f10 	mrc	15, 0, r4, cr1, cr0, {0}
87801fb4:	f7ff f8f1 	bl	8780119a <flush_dcache_all>
87801fb8:	f024 0405 	bic.w	r4, r4, #5
87801fbc:	ee01 4f10 	mcr	15, 0, r4, cr1, cr0, {0}
```

mrc 把 SCTLR 读进 r3,lsls #29 把 C 位(bit 2)顶到 N 位，缓存本来就没开，就地返回。开着才走下面：重读 SCTLR 进 r4,flush_dcache_all,bic #5 一次清掉 bit 0(M 位)与 bit 2(C 位)，mcr 写回。源码注释里“顺带关 MMU”那句，咱们在产物里对出来的就是这条 bic。协议要的 D-cache 关、MMU 关，从重读 SCTLR 进 r4 到 mcr 写回，四条指令全部办完。

### 从 bootcmd 到这一跳的完整链路

线索齐了，咱们把主线 11 章配的钥匙到这一跳的路拼成一张图，每格挂着出处：

```text
setenv bootcmd 'run emmcbootaes' + saveenv      主线 11 章
        │
run emmcargs        bootargs 进环境              mx6ull_aes_emmc.h 67
run loademmcimage   /zImage → 0x82000000        mx6ull_aes_emmc.h 69
run loademmcfdt     /imx6ull-aes.dtb → 0x83000000   头文件 70
        │
bootz ${loadaddr} - ${fdt_addr}                  cmd/bootz.c
        ├ bootz_start     ep = 0x82000000,bootz_setup 验魔数 0x016f2818
        ├ bootm_find_images → boot_get_fdt   DTB 进 images->ft_addr/ft_len
        ├ bootm_final     打 Starting kernel ...,停 DMA 设备   boot/bootm.c 1245
        ├ cleanup_before_linux → select(CBL_ALL)                cpu.c 81 → 27
        │     disable_interrupts → dcache_disable(flush + 摘 M、C)
        │     → v7_outer_cache_disable → invalidate_dcache_all
        │     → icache_disable → invalidate_icache_all
        └ kernel_entry(0, machid, r2)   r0=0  r1=机型号  r2=FDT 地址   bootm.c 357
```

图上每一格咱们都能在产物里对上号。emmcbootaes 整串值 strings 一搜就是一行，Starting kernel 的格式串也躺在同一个文件里：

```bash
# 主机 ~/imx-forge
strings out/uboot/u-boot | grep -E "Starting kernel|emmcbootaes"
```

```text
Starting kernel ...%s
emmcbootaes=echo Booting AES from eMMC ...; run emmcargs; mmc dev ${emmc_dev}; run loademmcimage; run loademmcfdt; bootz ${loadaddr} - ${fdt_addr};
```

Starting kernel ...%s 里那个 %s 平时永远是空串——只有带 BOOTM_STATE_OS_FAKE_GO 的 trace 跑法才往里填 (fake run for tracing),真交接时那行字就是五个词加一串省略号，打完这行，处理器手里剩下的只有 r0、r1、r2 和 0x82000000 那一条入口，咱们这一整篇的追查到这条入口就到头了。

## 继续学习

- [env 加载与倒计时：接管前的最后准备](12_env_and_autoboot.md):扩展卷上一篇，提示符之前的初始化序列在那篇收拢成时刻表。
- [链接地址与运行地址对不上的日子](07_relocation_limits.md):reloc off 的推演与 crt0.S 的 here 标签在那篇，本篇反汇编地址换算靠它。
- [从 _start 开始:U-Boot 的第一条指令](05_entry_and_vectors.md):异常向量与进门状态在那篇立起，VBAR 搬家是它的续篇。
- [环境变量与 bootcmd:U-Boot 的行为由谁来定](../11_env_bootcmd.md):bootcmd 行为层，emmcbootaes 这把钥匙在那篇配好。
- [启动 Linux:把内核装进板子完成交接](../12_boot_linux.md):bootz 语法与三个加载地址的主线篇，交接之后的内核世界从那边进。
