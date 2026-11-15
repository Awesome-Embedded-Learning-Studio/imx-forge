---
title: 从 _start 开始：U-Boot 的第一条指令
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 从 _start 开始：U-Boot 的第一条指令

> 上一篇把 Boot ROM 的活儿全部收了尾，ROM 照 boot data 把镜像搬进 DDR，跳向 IVT 里那个 0x87800000。本篇从 PC 落地那一刻接棒，回答一个具体的问题：进门之后、进 C 之前，CPU 被摆成了什么状态，每一步在源码哪行。跟读的家伙什（交叉读汇编与 C、objdump、符号表）也在本篇交到咱们手里，栈与 gd（global data，U-Boot 的全局数据块）怎么立，本篇一并立起来，board_init_f 在这个缺这缺那的环境里怎么活，留给下一篇。

## 一、接力棒到咱们手里

Boot ROM 那一程咱们已经走完了：上电后挑中启动介质，在 0x400 读出 d1 开头的 IVT，照 dcd 指针执行完 0x2C 处那份 488 字节的清单，DDR 活了，再按 boot data 把镜像搬进 DDR（起点 0x877ff000，长度 0x001a0000），跳向 entry，0x87800000。这个数咱们在 IVT 那一篇逐字节认过，也是链接地址，out/uboot/.config 第 183 行写着 CONFIG_TEXT_BASE=0x87800000。Boot ROM 跳过来的落点，正是链接器摆好的第一格。

手头的产物有个变化得交代：上一篇引的 /tmp/uboot-ref-aes 与 /tmp/uboot-ref-evk 不在了，咱们把探针照原样跑一遍，露了底：

```bash
# 主机 ~/imx-forge
ls -la /tmp/uboot-ref-aes/u-boot.sym
ls -la out/uboot/u-boot.sym out/uboot/u-boot out/uboot/System.map out/uboot/u-boot.bin
```

```text
ls: cannot access '/tmp/uboot-ref-aes/u-boot.sym': No such file or directory
-rw-r--r-- 1 charliechen charliechen  108849 Oct 20 10:06 out/uboot/System.map
-rwxr-xr-x 1 charliechen charliechen 7041816 Oct 20 10:06 out/uboot/u-boot
-rw-r--r-- 1 charliechen charliechen 1696688 Oct 20 10:06 out/uboot/u-boot.bin
-rw-r--r-- 1 charliechen charliechen  220067 Oct 20 10:06 out/uboot/u-boot.sym
```

等价的产物仓库自己就有，就是 tip 里那轮 out/uboot 的 mx6ull_aes_emmc 构建。上一篇第一节末尾验正文起点的那条入口字节命令，咱们对它原样再验一遍：

```bash
# 主机 ~/imx-forge
xxd -s 3072 -l 16 out/uboot/u-boot-dtb.imx
```

```text
00000c00: b800 00ea 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
```

与上一篇的转储一字不差，咱们站在这轮产物上往下走。跟读的家伙什换成交叉读汇编与 C、objdump、符号表，用法见第四节。

## 二、入口在哪个文件

顺着直觉咱们会摸到 arch/arm/lib/crt0.S，entry 招人，grep 却扑了个空：

```bash
# 主机 ~/imx-forge
grep -n "_start" third_party/uboot-mainline/arch/arm/lib/crt0.S | head -6
```

```text
69:	ldr	r0, =__bss_start	/* this is auto-relocated! */
143:	ldr	r1, _start_ofs
205:_start_ofs:
206:	.word	_start - _main
```

咱们把结果摊开：crt0.S 里没有 _start 标号，只有 _start_ofs，205 行起一个字，装着 _start 减 _main 的差值，给位置无关修补（镜像不在链接地址也能跑）贴用，这份构建没开 CONFIG_POSITION_INDEPENDENT（.config 第 48 行明写 not set），代码被裁掉了。crt0.S 开头的注释自己交代了身份：它管 C 运行时启动，入口叫 _main，等人跳进来。真正摆 _start 的在隔壁：

```bash
# 主机 ~/imx-forge
grep -n "_start\|reset" third_party/uboot-mainline/arch/arm/lib/vectors.S | head -6
grep -n "^reset:" third_party/uboot-mainline/arch/arm/cpu/armv7/start.S
```

```text
23:	ldr     pc, _reset
25:	b	reset
42: * Symbol _start is referenced elsewhere, so make it global
47:.globl _start
85:_start:
39:reset:
```

_start 躺在 vectors.S 的 85 行，reset 的正文写在 arch/arm/cpu/armv7/start.S 的 39 行。两个文件怎么咬合，咱们把向量表的宏摆出来：

```bash
# 主机 ~/imx-forge
sed -n '21,26p' third_party/uboot-mainline/arch/arm/lib/vectors.S
```

```text
        .macro ARM_VECTORS
#ifdef CONFIG_ARCH_K3
	ldr     pc, _reset
#else
	b	reset
#endif
```

宏的第一格是 b reset，只有 TI K3 那类 SoC（AM62x 这类机器，代码里开 CONFIG_ARCH_K3）换成 ldr pc,_reset（23 与 25 行），往后七格全是 ldr pc 间接跳转（28 到 34 行的宏体），落点装在表后的字表里。vectors.S 的注释写着 Uses indirect branch to allow reaching handlers anywhere in memory，间接一跳，handler 想放哪就放哪，搬家之后字面量跟着镜像走。复位向量落在哪，咱们多说一句：Cortex-A7 复位后取指地址由芯片定，6ULL 上电 PC 在 Boot ROM，是 ROM 照 IVT 的 entry 把控制交到 0x87800000，CPU 并没有按异常表取复位向量。U-Boot 把异常表摆在链接地址第一格，表头与入口共用 _start 一个标号，ROM 跳进来正好落在表的第一格上。

产物给咱们作证：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d --start-address=0x87800000 --stop-address=0x87800020 out/uboot/u-boot
```

```text
out/uboot/u-boot:     file format elf32-littlearm

Disassembly of section .text:

87800000 <__image_copy_start>:
87800000:	ea0000b8 	b	878002e8 <reset>
87800004:	e59ff014 	ldr	pc, [pc, #20]	@ 87800020 <_undefined_instruction>
87800008:	e59ff014 	ldr	pc, [pc, #20]	@ 87800024 <_software_interrupt>
8780000c:	e59ff014 	ldr	pc, [pc, #20]	@ 87800028 <_prefetch_abort>
87800010:	e59ff014 	ldr	pc, [pc, #20]	@ 8780002c <_data_abort>
87800014:	e59ff014 	ldr	pc, [pc, #20]	@ 87800030 <_not_used>
87800018:	e59ff014 	ldr	pc, [pc, #20]	@ 87800034 <_irq>
8780001c:	e59ff014 	ldr	pc, [pc, #20]	@ 87800038 <_fiq>
```

0x87800000 那格的字节，咱们上一篇在镜像里见过（b8 00 00 ea），objdump 按小端拼回 0xea0000b8，念给咱们听。e 开头是条件域，无条件执行，指令码 1010 说明这是 b，末尾 24 位偏移 0x0b8 按字算出 736 字节，PC 加 8 的流水线修正再添上这段偏移，落点 0x878002E8，objdump 把算术写在行尾：878002e8 <reset>。

reset 为什么隔这么远，咱们看 vectors.S 的排布就能算：表本体 0x20 字节，往后七个字是落点表，123 行的 .balignl 16,0xdeadbeef 垫一格填充字，0x40 起是 IRQ_STACK_START_IN 的字（172 到 178 行，值取 IRAM_BASE_ADDR 加 0x20（IRAM_BASE_ADDR 就是片上 RAM 起点 0x00900000，定义在 arch/arm/include/asm/arch-mx6/imx-regs.h 第 67 行）），七根异常桩按 32 字节对齐排开，排到 0x2E8 才轮到 reset。这段地理符号表作证，u-boot.sym 由 objdump -t u-boot 生成（原始命令留在 out/uboot/.u-boot.sym.cmd），咱们把关键标号捞出来：

```bash
# 主机 ~/imx-forge
grep -n " reset$\| _start$\| _main$\| c_runtime_cpu_setup$" out/uboot/u-boot.sym
```

```text
2454:878002e8 g       .text	00000000 reset
3141:87800000 g       .text	00000000 _start
3635:87800328 g     F .text	00000010 c_runtime_cpu_setup
4093:878015f4 g     F .text_rest	00000074 _main
```

_start 在 0x87800000，reset 在 0x878002e8，咱们对上 objdump 行尾的算术，分毫不差，这一路没有一个地址靠记忆。入口的答案齐了：表摆在 vectors.S，reset 正文在 start.S，crt0.S 在后面等着接 C。

## 三、进 C 之前的几件小事

reset 的正文从 0x878002e8 开始，咱们整段倒出来，一行行对着源码认（下面几块反汇编省去开头的格式说明行与空行）：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d --start-address=0x878002e8 --stop-address=0x87800328 out/uboot/u-boot
```

```text
878002e8 <reset>:
878002e8:	ea000012 	b	87800338 <save_boot_params>

878002ec <save_boot_params_ret>:
878002ec:	e10f0000 	mrs	r0, CPSR
878002f0:	e200101f 	and	r1, r0, #31
878002f4:	e331001a 	teq	r1, #26
878002f8:	13c0001f 	bicne	r0, r0, #31
878002fc:	13800013 	orrne	r0, r0, #19
87800300:	e38000c0 	orr	r0, r0, #192	@ 0xc0
87800304:	e129f000 	msr	CPSR_fc, r0
87800308:	ee110f10 	mrc	15, 0, r0, cr1, cr0, {0}
8780030c:	e3c00a02 	bic	r0, r0, #8192	@ 0x2000
87800310:	ee010f10 	mcr	15, 0, r0, cr1, cr0, {0}
87800314:	e59f0084 	ldr	r0, [pc, #132]	@ 878003a0 <cpu_init_crit+0x4>
87800318:	ee0c0f10 	mcr	15, 0, r0, cr12, cr0, {0}
8780031c:	eb000006 	bl	8780033c <cpu_init_cp15>
87800320:	eb00001d 	bl	8780039c <cpu_init_crit>
87800324:	eb0004b2 	bl	878015f4 <_main>
```

### 模式与中断，接过来自己确认

头一落点是 save_boot_params。start.S 154 行起给它挂了 WEAK，板卡想接上层交棒塞在 r0 到 r3 里的参数就自己补一份实现，默认那份只弹回 save_boot_params_ret。函数头的注释把纪律写明白了：栈指针此刻还没立，-O0 也不许往栈上存东西。为什么谨慎，咱们想想就明白，sp 没立之前压栈，是往没主的内存里写。

模式这一关紧跟着来，咱们对照 objdump 认。mrs 把 CPSR 读进 r0，and #31 掩出低五位的模式位，teq #26 试的是 0x1a，HYP 模式。不在 HYP 就把模式位清干净、填回 0x13 的 SVC，再 orr 0xc0 关掉 FIQ 与 IRQ，msr 写回去，源码在 start.S 93 到 99 行。6ULL 复位后本来就在 SVC，Boot ROM 交棒时也没动过模式，U-Boot 不赌，接过来自己确认一遍。后面每一步都假设没人打断，这两根开关等中断控制器与栈就位才放开。

### 异常表指到自己门口

87800308 起三行读改写 SCTLR，bic #8192 清掉第 13 位，SCTLR 的 V 位，让 CPU 按 VBAR 寻址异常表而不走高向量。跟着的 ldr r0,[pc,#132] 从 0x878003a0 取一个字，mcr 写进 cr12，VBAR 寄存器。取出来的值是什么，字面量池就在 cpu_init_crit 后头，咱们一并倒出来：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d --start-address=0x8780039c --stop-address=0x878003a8 out/uboot/u-boot
```

```text
8780039c <cpu_init_crit>:
8780039c:	ea000421 	b	87801428 <lowlevel_init>
878003a0:	87800000 	.word	0x87800000
878003a4:	0091ff00 	.word	0x0091ff00
```

0x87800000，_start 自己，VBAR 从此指着第二节看过的那张表。源码对应 start.S 101 到 115 行，ARMv7-A 上 CONFIG_HAS_VBAR 开着，写 VBAR 的两行才编进来。为什么现在就得做：此刻任何取指错、数据错都按当前 VBAR 找表，VBAR 复位值是 0，6ULL 的 0 地址是 Boot ROM 的地界，异常跳过去就交回 ROM，串口一行都不出。咱们把异常表指到自己门口，异常才落进自己的桩子。

### 清 CP15，把 CPU 洗回已知状态

cpu_init_cp15 在 start.S 203 行起，这一程里最长的一段汇编，咱们把开头一半倒出来：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d --start-address=0x8780033c --stop-address=0x87800374 out/uboot/u-boot
```

```text
8780033c <cpu_init_cp15>:
8780033c:	e3a00000 	mov	r0, #0
87800340:	ee080f17 	mcr	15, 0, r0, cr8, cr7, {0}
87800344:	ee070f15 	mcr	15, 0, r0, cr7, cr5, {0}
87800348:	ee070fd5 	mcr	15, 0, r0, cr7, cr5, {6}
8780034c:	f57ff04f 	dsb	sy
87800350:	f57ff06f 	isb	sy
87800354:	ee110f10 	mrc	15, 0, r0, cr1, cr0, {0}
87800358:	e3c00a02 	bic	r0, r0, #8192	@ 0x2000
8780035c:	e3c00007 	bic	r0, r0, #7
87800360:	e3800002 	orr	r0, r0, #2
87800364:	e3800b02 	orr	r0, r0, #2048	@ 0x800
87800368:	e3800a01 	orr	r0, r0, #4096	@ 0x1000
8780036c:	ee010f10 	mcr	15, 0, r0, cr1, cr0, {0}
87800370:	e1a0500e 	mov	r5, lr
```

咱们对照 start.S 218 到 223 行看，mov r0,#0 之后三条 mcr，把 TLB、I-cache 与分支预测缓冲的旧内容作废，dsb 与 isb 等它们落定。然后读 SCTLR，bic #7 清掉低三位，MMU、对齐检查与 D-cache 一并关掉，再逐位立回来：orr #2 开对齐检查，orr #0x800 开分支预测，orr #0x1000 开 I-cache，这份构建没配 SYS_ICACHE_OFF（.config 第 41 行明写 not set），I 位才编成置 1。

函数后半段读 MIDR 认 CPU 版型，结尾把 sp 装上 0x0091ff00 再 mov pc,r5 回去，字面量就在 0x878003a4，咱们前一块 objdump 里见过。这根栈给 errata 修正调 C 函数备着，本版 .config 里一条 ARM_ERRATA 都没有，修正代码全被裁掉，装栈的代码不在条件编译里，照装。Boot ROM 为自己开过 MMU 与 cache，不清干净，第一段 C 代码就活在别人的映射里。

### lowlevel_init 与交棒

cpu_init_crit 只有一条 b，咱们跟进 arch/arm/cpu/armv7/lowlevel_init.S 的 lowlevel_init，整个函数 objdump 出来 32 字节：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d --start-address=0x87801428 --stop-address=0x8780144c out/uboot/u-boot
```

```text
87801428 <lowlevel_init>:
87801428:	e59fd018 	ldr	sp, [pc, #24]	@ 87801448 <lowlevel_init+0x20>
8780142c:	e3cdd007 	bic	sp, sp, #7
87801430:	e24ddc01 	sub	sp, sp, #256	@ 0x100
87801434:	e3cdd007 	bic	sp, sp, #7
87801438:	e1a0900d 	mov	r9, sp
8780143c:	e92d5000 	push	{ip, lr}
87801440:	fa0006a4 	blx	87802ed8 <s_init>
87801444:	e8bd9000 	pop	{ip, pc}
87801448:	0091ff00 	.word	0x0091ff00
```

sp 装的还是 0x0091ff00，字面量在函数尾巴 0x87801448，咱们核过它按 8 字节对齐。跟着 sub sp,#256，让出的这格是 gd（global data，U-Boot 的全局数据块，后面 C 代码全靠 r9 找到它）占位，256 是 generic-asm-offsets.h 第 9 行的 GENERATED_GBL_DATA_SIZE（out/uboot 的 include/generated 下），第 11 行的 GD_SIZE 同值。mov r9,sp 之后，gd 固定住 r9 的约定生效，占位里的内容还没人清。push {ip,lr} 存下现场，blx s_init 把板卡早期初始化叫起来，pop {ip,pc} 原路回去。s_init 在 arch/arm/mach-imx/mx6/soc.c 613 行有正身，开头一组 if 判型号，6ULL 命中 return 空手而回。往下的时钟修正是给 6Quad 这档四核型号做的，6DL 与 6SL 那两档 Boot ROM 里已加好 396M workaround，轮不到这里再补。这是汇编层留给板卡最后一个说话的位置，gd 住 r9 的约定也要在进 C 之前立好，因为 C 侧代码张口就找 r9。

交棒那一下在 87800324，bl _main 把控制交给 0x878015f4，咱们跟过去：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d --start-address=0x878015f4 --stop-address=0x87801618 out/uboot/u-boot
```

```text
878015f4 <_main>:
878015f4:	e59f0070 	ldr	r0, [pc, #112]	@ 8780166c <_start_ofs+0x4>
878015f8:	e3c00007 	bic	r0, r0, #7
878015fc:	e1a0d000 	mov	sp, r0
87801600:	fa004869 	blx	878137ac <board_init_f_alloc_reserve>
87801604:	e1a0d000 	mov	sp, r0
87801608:	e1a09000 	mov	r9, r0
8780160c:	fb004868 	blx	878137b6 <board_init_f_init_reserve>
87801610:	e3a00000 	mov	r0, #0
87801614:	fa00508d 	blx	87815850 <board_init_f>
```

crt0.S 的 103 到 125 行跟这段一一对应。头一句 ldr 从 0x8780166c 取字，又是 0x0091ff00，公式在 include/system-constants.h 19 到 20 行，CFG_SYS_INIT_RAM_ADDR 加 CFG_SYS_INIT_RAM_SIZE 减 GENERATED_GBL_DATA_SIZE。CFG_SYS_INIT_RAM_ADDR 就是 IRAM_BASE_ADDR，CFG_SYS_INIT_RAM_SIZE 就是 IRAM_SIZE，这层等价定义在 include/configs/mx6ull_aes_emmc.h 第 139 到 140 行，数值本体在 imx-regs.h 第 67 与 375 行。咱们把这块板的两个数代进去，0x00900000 加 0x00020000 减 0x100。

低三位清零，mov sp，第一根真正的 C 栈立起来。blx board_init_f_alloc_reserve 在栈底圈出一块地，返回值写回 sp，r9 跟过去，blx board_init_f_init_reserve 把地清零，gd 有了正式落脚处。mov r0,#0 加 blx board_init_f，C 的正篇开演，参数只有孤零零一个 0。留意这几记是 blx 不是 bl，.config 第 69 行 CONFIG_SYS_THUMB_BUILD=y，C 那侧编成 Thumb 指令集，跳过去得顺手换状态。

## 四、怎么跟读

这一篇的办法咱们自己就能复现。objdump 管指令与地址，--start-address 与 --stop-address 夹住关心的区间，全量反汇编去掉这两个参数就行，配 grep 找标号省力。符号表管名字与地址，u-boot.sym 220067 字节，System.map 108849 字节，同一套地址换个朴素排法。咱们的互证链：分支编码算出的落点、objdump 行尾的 <reset>、符号表里的 878002e8，样样咬合，无一靠记忆。

第一节 ls 输出里那个 u-boot.bin 也值得咱们亲手一试，拿去 objdump 会怎样：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d out/uboot/u-boot.bin
```

```text
objdump: out/uboot/u-boot.bin: file format not recognized
```

::: warning 反汇编别拿 u-boot.bin，工具直接拒读
.bin 是剥掉 ELF 头的纯二进制，段表与符号一个不剩，objdump 找不到格式的凭据，file format not recognized 就是这么来的。后果是按地址反汇编、按标号查表的活全干不了，不少人会在这里空耗半天。分工记一条：按偏移读字节用 .bin，反汇编与查符号认准 ELF 那份 out/uboot/u-boot，咱们前文就是这么分的。
:::

还有一层本环境验不了，咱们把边界划清楚：

## 五、下一篇预告

接力棒的位置咱们看清了：sp 立在 0x0091ff00，gd 在栈底刚圈出又清了零，r0 里只揣着一个 0，board_init_f(0) 马上开演。可这个 C 环境是残缺的，crt0.S 开头的注释写得明白：只有栈与 gd 的位置，变量与 BSS 一律没有，常量才能用。下一篇跟着 board_init_f 走，看代码在这种缺这缺那的环境里怎么活得小心，DRAM 边界怎么探，重定向落点怎么定。

还有一处伏笔咱们点出来：87800324 的 bl _main，返回地址算出来是 87800328，恰好是 c_runtime_cpu_setup 的第一条指令。_main 不会走这条返回路，可 crt0 搬完家会正经调它一回，0x8780163c 起两行就是那一记，干的是 I-cache 无效化（start.S 131 行起，符号表 3635 行）。

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-objdump -d --start-address=0x8780163c --stop-address=0x87801644 out/uboot/u-boot
```

```text
8780163c <here>:
8780163c:	eb000019 	bl	878016a8 <relocate_vectors>
87801640:	ebfffb38 	bl	87800328 <c_runtime_cpu_setup>
```

## 继续学习

- [IVT 逐字段：BootROM 拿到的说明书](02_ivt_fields.md)：entry 与 boot data 两个字的逐字节来历，本篇的落点 0x87800000 由它交给 Boot ROM，咱们回头看那张字段表，entry 那格就是起跑线。
- [DCD 逐条读：BootROM 替咱们执行的初始化清单](03_dcd_walkthrough.md)：Boot ROM 挑介质、执行清单、搬运与跳交的全过程，与本篇头尾相接，两篇摆在一起，交接就完整了。
