---
title: 链接地址与运行地址对不上的日子
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 链接地址与运行地址对不上的日子

> Boot ROM 把镜像搬进 DDR、跳进 0x87800000，Boot ROM 那三篇把交接证据备齐了。跳进来之后 U-Boot 并不常住，它给自己在 DDR 顶端选好一块新地皮，把整个镜像搬过去，从那一刻起，运行地址与链接地址就分了家。本篇把分家这件事从头讲清楚，链接器按哪个地址排的座位，搬家之前那段日子代码为什么活得小心，搬家的活由谁干，最后留一组对数的命令，咱们在自己的产物上把每个数字亲眼对一遍。SPL 平台的搬家是另一套做法，本篇立一块对照牌，下一篇旁栏专门展开。

## 一、问题的根源 —— 链接器按 TEXT_BASE 排地址

探针命令咱们照原样跑，空结果也值得一看。

```bash
# 主机 ~/imx-forge
grep -n "CONFIG_TEXT_BASE\|TEXT_BASE" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig third_party/uboot-mainline/include/configs/mx6ull_aes_emmc.h
```

两个文件都没有这一行，grep 以退出码 1 收场。空结果本身就是信息，这块板的 TEXT_BASE 不住在 defconfig 里，也不住在 include/configs 的板级头文件里。它住哪，咱们换个地方问。

```bash
# 主机 ~/imx-forge
sed -n '15,17p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/Kconfig
```

```text
config TEXT_BASE
	default 0x87800000
endif
```

板级 Kconfig 里一行 default 0x87800000。顶层 Kconfig 第 703 行起也给这个符号排了一串架构默认值，ARCH_MX6 那条写的是 0x17800000，板级这行把最终值换了过来。两处默认怎么合，咱们不必去背合并规则，编出来的产物配置里有落地的值。

```bash
# 主机 ~/imx-forge
grep -n "CONFIG_TEXT_BASE" out/uboot/.config
```

```text
183:CONFIG_TEXT_BASE=0x87800000
```

0x87800000 落在 .config 第 183 行，咱们拿它当锚。链接器就按这个数给全镜像排座位，System.map 里 _start 与 __image_copy_start（镜像拷贝起点标记，第三节的复制循环从它开始）都在这一格，ELF 的入口也是它。

```bash
# 主机 ~/imx-forge
grep -w "_start\|__image_copy_start" out/uboot/System.map
arm-none-linux-gnueabihf-readelf -h out/uboot/u-boot | grep Entry
```

```text
87800000 T __image_copy_start
87800000 T _start
     Entry point address:               0x87800000
```

链接地址到此有了实物。咱们把两边放在一起看，运行地址却不受链接器管，归 Boot ROM 的搬运，ROM 照 boot data 写死的地址搬镜像、跳入口，前三篇验过这套流程。AES 这份镜像那个地址恰好也是 0x87800000，跳进来那一刻两个地址对得上。对得上是设计出来的，不是天经地义。boot data 指哪儿代码就在哪儿跑，链接器管不着。

真正的分家发生在进门之后。board_init_f 的后半程全在给搬家定地方，安排记在 common/board_f.c 里，setup_dest_addr 把 gd（global data，U-Boot 早期阶段随身携带的全局数据结构，ARM 上一直住在 r9 寄存器里）的 relocaddr 起点定在 ram_top，中间 reserve_round_4k 把地址做四 KiB 对齐，arch_reserve_mmu 给页表留出一块，reserve_uboot 从那里减掉 mon_len 再按 4KiB 取整。ARM 路径上 mon_len 算的是 __bss_end 减 _start，System.map 把数备齐，咱们挑相关的五行看。

```bash
# 主机 ~/imx-forge
grep -w "__bss_start\|__bss_end\|__image_copy_end\|__rel_dyn_start\|__rel_dyn_end" out/uboot/System.map
```

```text
87987290 ? __bss_start
87987290 R __image_copy_end
87987290 R __rel_dyn_start
8798e328 ? __bss_end
87996268 R __rel_dyn_end
```

mon_len 是 0x18E328，即 1,631,016 字节。咱们拿调试速查那一篇（[调试命令速查：命令行是嵌入式开发的神器](../14_debug_reference.md)）样例给的 512MB 口径推演，setup_dest_addr 把 gd->relocaddr 定在 ram_top 0xA0000000，reserve_round_4k 做四 KiB 对齐，arch_reserve_mmu 扣掉 PGTABLE_SIZE 0x4000 的页表、按 64KiB 向下取整，落到 0x9FFF0000（video 与 trace 在这份产物里空转），reserve_uboot 再减去 mon_len 0x18E328 按 4KiB 向下取整，新家住址是 0x9FE61000，离链接地址差 0x18661000。这个差值在源码里有名字，board_f.c 第 748 行把它写进 gd->reloc_off。搬完家，代码在 0x9FE61000 一带执行，链接器排的座位表还写着 0x87800000。

偏移一出现，三类东西跟着失灵，咱们挨个点名。字面量池里的绝对地址，函数指针是最大的一类，存的值都在 0x87800000 一带，照着跳就跳回旧拷贝。全局变量一样，地址指回旧位置，旧位置从此没人维护。字符串字面量坐在 .rodata 段，地址同样是链接地址，读出来的是搬家前的旧字节，搬去别的地址的板上更是直接指到空 DDR。机制就一句，按链接地址访存，落点还留在 0x87800000 一带，可那份镜像已经是被扔下的前身。

## 二、重定位前的生存法则

### 栈与 gd 住在 OCRAM 和寄存器里

咱们把 crt0.S 文件头的注释读一遍，它把这一阶段的处境写得直白。_main 搭的第一个 C 环境只有栈和 gd，放在现成的 RAM 里（SRAM，或者锁定当缓存用的那一段），变量型全局数据不管初始化没初始化、连同 BSS，一律不可用，手边只有常量初始化数据。反汇编跟这句话对得上，_main 的第一条指令就从字面量池里取栈顶。

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d --start-address=0x878015f4 --stop-address=0x87801618 out/uboot/u-boot | sed -n '7,14p'
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
```

字面量池里那个词的值是 0x0091ff00，咱们对一下数。i.MX6ULL 的 OCRAM 从 0x00900000 起，大小 0x00020000（IRAM_BASE_ADDR 与 IRAM_SIZE 分别在 arch/arm/include/asm/arch-mx6/imx-regs.h 第 67 行与第 375 行），顶端让出 GENERATED_GBL_DATA_SIZE 256（编译生成的 out/uboot/include/generated/generic-asm-offsets.h 第 9 行写着 GENERATED_GBL_DATA_SIZE 256，这份头文件是构建产物，源码树里没有）后剩 0x0091ff00，这是预留区的顶，也是 alloc_reserve 的入参。它还要过 board_init_f_alloc_reserve 一道：SYS_MALLOC_F 生效时（.config 第 185 行 CONFIG_SYS_MALLOC_F_LEN=0x2000）先往下扣出 0x2000 的早期堆区，再按 gd 尺寸向下收，返回值既是预留区底也是 gd 的地址（common/init/board_init.c 第 81 行，函数注释明说这一层）。crt0.S 随后 mov sp, r0、mov r9, r0，初始栈顶与 gd 同在 0x0091de00，栈向下生长，gd 本身占 256 字节，从它头顶到预留区顶正好摆下 0x2000 的早期堆。不变的是：都在 OCRAM 里，不占链接地址的内存。

咱们从源码里把 gd 的住处找出来，它本人更干脆——直接搬进寄存器。arch/arm/include/asm/global_data.h 的 32 位分支写着 `register gd_t *gd asm("r9")`，board_init_f 之后所有早期初始化函数都从 r9 摸到它。重定位之前变量型全局数据一律不可信，这条线写在 crt0.S 文件头的注释里，能把身家带在身上的只有 gd。board_f.c 里的早期初始化也守着这条线，setup_mon_len 写 gd->mon_len，dram_init 在板级代码里写 gd->ram_size（gd->ram_size = imx_ddr_size()，内存大小是运行时测出来的），交接数据全走 gd。crt0.S 注释里点过名，搬家目的地、未来的栈、未来的 gd 位置，全存在 gd 里带过去。

### BSS 没人搬，也没人清

System.map 里有个耐看的细节，咱们把它圈出来，__image_copy_end 与 __bss_start 是同一个地址 0x87987290。BSS 不占镜像文件，Boot ROM 搬镜像搬的是 boot data 给的文件尺寸，BSS 没份。relocate_code 的拷贝循环从 __image_copy_start 拷到 __image_copy_end，BSS 也没份。清 BSS 的 CLEAR_BSS 排在 crt0.S 的 here 标签（第 165 行，relocate_code 返回的落点）之后，搬家落地才执行，清的还是新位置。串起来看，重定位之前任何 BSS 变量读出来的都是 DDR 上电后的随机残留，写进去的值也没人担保活得过搬家。

### 字符串字面量为什么危险

字符串坐在 .rodata 段，地址按链接地址排死，咱们拿 board_init_f 里那句 `puts("DRAM:  ")` 挖出来看。字符串真身在 0x8785e817，引用它的字面量池词就在 board_init_f 的池子里，值恰好是 0x8785e817。符号表里找不到 announce_dram_init 这个名字，这个 static 函数被内联进了 board_init_f，池词正好落在它的地址段里。它是个数，不是会自己挪的东西，正确性完全托付给运行地址等于链接地址，或者托付给搬家机制把它修过。咱们这块板入口恰好在链接地址上，落地之前它当场可用。前提一破，比如别的板 ROM 把镜像搬去 TEXT_BASE 之外的地方，或者 SPL 那类不搬家的阶段，它指过去的位置就是空 DDR。

::: warning 搬家完成前别碰全局变量与字符串
后果是错得不报错，读到冻结的旧值、没人清过的 DDR 残留，或者打出乱码，串口有输出但行为诡异，比直接崩更难查。根因是按链接地址访存的落点在旧拷贝或空 DDR，搬家开始后旧拷贝没人维护，gd 也已经换址，旧位置上没有任何机制替代码兜底。解法只有一条，搬家完成之前只信局部变量与 gd，这也是 crt0.S 用注释替咱们守住的线。
:::

## 三、重定位由谁做

第二条探针把调用点指了出来。

```bash
# 主机 ~/imx-forge
grep -n "relocate_code\|relocate_vectors" third_party/uboot-mainline/arch/arm/lib/crt0.S | head -6
```

```text
40: * 4a.For U-Boot proper (not SPL), call relocate_code(). This function
131: * relocate_code(addr_moni). Trick here is that we'll return
161:	bl	relocate_code
163:	b	relocate_code
170:	bl	relocate_vectors
```

AES 这条路没有 SPL。defconfig 一百零五行里咱们 grep SPL 只匹配到 SPLASH_SCREEN 两行，真正的 SPL 配置一个没有，Boot ROM 直接把完整的 U-Boot 送进 DDR，所以搬家的活是 U-Boot proper 自己干。crt0.S 第 40 行起的注释把分工写明，U-Boot proper 调 relocate_code，SPL 里 board_init_f 直接返回，SPL 没有搬家这一说（新版源码把 SPL 构建宏改名叫 XPL，第 127 行的 #if ! defined(CONFIG_XPL_BUILD) 就是这道分工在源码里的写法）。咱们编出的产物走的是第 163 行那条 b，尾跳，不打算回来。

board_f.c 第 787 行有句注释，ARM calls relocate_code from its crt0.S。不是 ARM 的架构走 jump_to_copy，x86 还有自己的跳板，这条路是 ARM32 特有的。relocate_code 的真身在 arch/arm/lib/relocate.S，咱们翻出来看，它开头有一段少见的注释，为了不让自己挂上 R_ARM_ABS32 类型的重定位记录，这个函数从头到尾不直接引用链接符号，改把各符号相对 relocate_code 的偏移放进字面量池，运行时拿当前地址加回去。反汇编里这招看得见。

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d --start-address=0x878016b4 --stop-address=0x8780172c out/uboot/u-boot | sed -n '7,44p'
```

```text
878016b4 <relocate_code>:
878016b4:	e24f3008 	sub	r3, pc, #8
878016b8:	e59f105c 	ldr	r1, [pc, #92]	@ 8780171c <_image_copy_start_ofs>
878016bc:	e0811003 	add	r1, r1, r3
878016c0:	e0504001 	subs	r4, r0, r1
878016c4:	0a000013 	beq	87801718 <relocate_done>
878016c8:	e59f2050 	ldr	r2, [pc, #80]	@ 87801720 <_image_copy_end_ofs>
878016cc:	e0822003 	add	r2, r2, r3

878016d0 <copy_loop>:
878016d0:	e8b10c00 	ldm	r1!, {sl, fp}
878016d4:	e8a00c00 	stmia	r0!, {sl, fp}
878016d8:	e1510002 	cmp	r1, r2
878016dc:	3afffffb 	bcc	878016d0 <copy_loop>
878016e0:	e59f103c 	ldr	r1, [pc, #60]	@ 87801724 <_rel_dyn_start_ofs>
878016e4:	e0812003 	add	r2, r1, r3
878016e8:	e59f1038 	ldr	r1, [pc, #56]	@ 87801728 <_rel_dyn_end_ofs>
878016ec:	e0813003 	add	r3, r1, r3

878016f0 <fixloop>:
878016f0:	e8b20003 	ldm	r2!, {r0, r1}
878016f4:	e20110ff 	and	r1, r1, #255	@ 0xff
878016f8:	e3510017 	cmp	r1, #23
878016fc:	1a000003 	bne	87801710 <fixnext>
87801700:	e0800004 	add	r0, r0, r4
87801704:	e5901000 	ldr	r1, [r0]
87801708:	e0811004 	add	r1, r1, r4
8780170c:	e5801000 	str	r1, [r0]

87801710 <fixnext>:
87801710:	e1520003 	cmp	r2, r3
87801714:	3afffff5 	bcc	878016f0 <fixloop>

87801718 <relocate_done>:
87801718:	e12fff1e 	bx	lr

8780171c <_image_copy_start_ofs>:
8780171c:	ffffe94c 	.word	0xffffe94c
```

sub r3, pc, #8 拿到的是自己此刻的真实位置，池子里那个 0xffffe94c 是 __image_copy_start 减 relocate_code 的相对偏移，一加就还原出运行中的拷贝起点。r4 是偏移，进函数时的 r0 是 gd->relocaddr，两下一减就算出来，偏移为零说明镜像已在位，直接跳 relocate_done 完事。copy_loop 八字节八字节把镜像搬进新家，fixloop 认着 R_ARM_RELATIVE（23）逐条修字，目的地址加偏移，值也加偏移，写回去。收尾 bx lr，那条 lr 早在 crt0.S 里加过 reloc_off，落点正是新拷贝里的 here 标签。crt0.S 的注释管这叫 trick，咱们把 trick 翻译成人话，返回到 here，不过是搬过去的 here。向量表随后由 relocate_vectors 接手，产物里它真正干活的只有两条指令，从 gd 摸出 relocaddr 写进 VBAR（Vector Base Address Register，向量基址寄存器，CPU 从这里取异常入口的基址）。

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d --start-address=0x878016a8 --stop-address=0x878016b4 out/uboot/u-boot | sed -n '7,10p'
```

```text
878016a8 <relocate_vectors>:
878016a8:	e5990030 	ldr	r0, [r9, #48]	@ 0x30
878016ac:	ee0c0f10 	mcr	15, 0, r0, cr12, cr0, {0}
878016b0:	e12fff1e 	bx	lr
```

SPL 那条对照路咱们一句话带过，SPL 不搬家，它在自己那点内存里把时钟与 DDR 张罗好，把完整的 U-Boot 交给下一棒，搬家这套功夫是 U-Boot proper 的看家本领。那条路怎么走，下一篇旁栏展开。

## 四、在产物上自己验证一遍

上面的反汇编咱们都能自己跑出来，命令都摆在各自出现的那一节，产物用 out/uboot 那份 ELF。下面再补三件对数的事：头一件对 _main 的搬家前奏，窗口从 board_init_f 返回之后开到 here 的字面量池。

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -d --start-address=0x87801618 --stop-address=0x8780167c out/uboot/u-boot | sed -n '7,36p'
```

```text
87801618 <_main+0x24>:
87801618:	e599003c 	ldr	r0, [r9, #60]	@ 0x3c
8780161c:	e3c00007 	bic	r0, r0, #7
87801620:	e1a0d000 	mov	sp, r0
87801624:	e5999004 	ldr	r9, [r9, #4]
87801628:	e28fe00c 	add	lr, pc, #12
8780162c:	e5990040 	ldr	r0, [r9, #64]	@ 0x40
87801630:	e08ee000 	add	lr, lr, r0
87801634:	e5990030 	ldr	r0, [r9, #48]	@ 0x30
87801638:	ea00001d 	b	878016b4 <relocate_code>

8780163c <here>:
8780163c:	eb000019 	bl	878016a8 <relocate_vectors>
87801640:	ebfffb38 	bl	87800328 <c_runtime_cpu_setup>
87801644:	e59f0024 	ldr	r0, [pc, #36]	@ 87801670 <_start_ofs+0x8>
87801648:	e59f3024 	ldr	r3, [pc, #36]	@ 87801674 <_start_ofs+0xc>
8780164c:	e3a01000 	mov	r1, #0
87801650:	e0532000 	subs	r2, r3, r0
87801654:	fa000041 	blx	87801760 <memset>
87801658:	e1a00009 	mov	r0, r9
8780165c:	e5991030 	ldr	r1, [r9, #48]	@ 0x30
87801660:	e59fe010 	ldr	lr, [pc, #16]	@ 87801678 <_start_ofs+0x10>
87801664:	e12fff1e 	bx	lr

87801668 <_start_ofs>:
87801668:	ffffea0c 	.word	0xffffea0c
8780166c:	0091ff00 	.word	0x0091ff00
87801670:	87987290 	.word	0x87987290
87801674:	8798e328 	.word	0x8798e328
87801678:	87815ca5 	.word	0x87815ca5
```

咱们一句句对，add lr, pc, #12 就是 adr lr, here 编出来的样子，0x87801628 加 8 加 12，算出来正是 0x8780163c 的 here。接着从 gd 摸出 reloc_off 加到 lr 上，再摸出 relocaddr 放进 r0，尾跳 relocate_code。池子五个词全是证据，0xffffea0c 是 _start 减 _main 的偏移，留给位置无关配置 CONFIG_POSITION_INDEPENDENT 那条路（crt0.S 第 141 行的 #if 守着 adr lr, here 之后这段），.config 第 48 行它是 is not set，这份产物没开它。0x0091ff00 是第二节算过的预留区顶，0x87987290 与 0x8798e328 是 __bss_start 与 __bss_end（CLEAR_BSS 在这份产物里走的是 memset 分支），0x87815ca5 是 board_init_r（重定位之后接棒的第二个 C 阶段入口，main_loop 从它进）加 1，那个 1 是 Thumb 位，bx lr 靠它切指令集。这些按链接地址排死的词，运行时全靠 fixloop 加偏移救回来。

第二件数重定位记录。

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-readelf -r out/uboot/u-boot | awk "/Relocation section '.rel.dyn'/{f=1} /^Relocation section '.rel.dyn'/{next} f==0{next} /^Relocation section|^$/{exit} /R_ARM/{c++} END{print c}"
arm-none-linux-gnueabihf-readelf -r out/uboot/u-boot | grep -w "87801678\|87801670\|87815ad4"
```

```text
7675
87801670  00000017 R_ARM_RELATIVE   
87801678  00000017 R_ARM_RELATIVE   
87815ad4  00000017 R_ARM_RELATIVE   
```

.rel.dyn 里排着 7675 条记录，正好等于 System.map 里 __rel_dyn_start 到 __rel_dyn_end 的 0xEFD8 字节除以 8。咱们挑的三条刚好对上看过的三处，0x87801670 与 0x87801678 是 here 池子里 BSS 起点与 board_init_r 那两个词，0x87815ad4 是 board_init_f 池子里 DRAM 字符串那个词。每条记录的意思都一样，这个位置上存着一个链接地址，运行时给它加上 reloc_off。

第三件对字符串。

```bash
# 主机 ~/imx-forge
arm-none-linux-gnueabihf-objdump -s -j .rodata out/uboot/u-boot | grep "DRAM:  "
```

```text
 8785e810 645f696e 666f0044 52414d3a 20200064  d_info.DRAM:  .d
```

咱们把十六进制念出来，44 52 41 4d 3a 20 20 就是 DRAM 加冒号加两个空格，字符串起点在 0x8785e817，与池词 0x87815ad4 里的值对上。三样证据咬在一起，字面量池里存的数、.rel.dyn 里的记录、.rodata 里的真身。板子在手边的话，拿 bdinfo 打出的 relocaddr 减去链接基址 0x87800000，得出 reloc off，拿它跟推演值 0x18661000 对，再把 reloc off 加到 System.map 里任意一个符号的链接地址上，就是它在板上的运行地址。拿 _start 试一把，0x87800000 加 0x18661000 等于 0x9FE61000，正是推演的新家，这套机制在板上跑出来的就是这张表。

## 继续学习

- [DCD 逐条读：BootROM 替咱们执行的初始化清单](03_dcd_walkthrough.md)：ROM 把镜像搬进 DDR、跳 0x87800000 的交接证据在那篇里，咱们本篇的链接地址就从它手里接过来。
- [七步造出咱们的板卡：从参考配置到 AES 入册](../07_board_porting.md)：TEXT_BASE 进板级 Kconfig 的来龙去脉，移植自家板时咱们要改的就是那一行。
- [调试命令速查：命令行是嵌入式开发的神器](../14_debug_reference.md)：bdinfo 的 relocaddr 与 reloc off 两行怎么读，板子在手边时咱们用它们核出真实坐标。
