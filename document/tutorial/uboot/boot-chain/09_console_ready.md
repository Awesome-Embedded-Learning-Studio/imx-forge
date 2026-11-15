---
title: console 什么时候就绪：第一行输出来自哪
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# console 什么时候就绪：第一行输出来自哪

> console 就绪前后，同一段打印走的不是同一条路。主线验收篇里，咱们对着串口 banner 核过时间戳。本篇回到源码把三件事一起答掉：第一个字符从哪个函数写出去，console 的就绪开关装在哪、没就绪时打印又去了哪，板子与设备树在这之前替咱们干了什么活。读完再回头看验收那天抄下的 banner，咱们能指着它说出从字符串到寄存器的每一站。

## 一、console 从哪一刻开始出声

验收那天咱们核的是字面。banner 的时间戳 17:02:31 对上了，板上跑的才算是主线教程 03 章《第一次编译官方参考板：从 distclean 到四个产物》出炉的那一轮，至于这行字怎么从代码走到串口，当时没往下问。前面几篇讲到 BootROM 跳转为止，U-Boot 这边串口从哪一刻开始出声，还没交代过。把两件事合起来，本篇要回答的就三件事：第一个字符从哪个函数写出去，console 的就绪开关装在哪、没就绪时打印又去了哪，板子与设备树在这之前替咱们干了什么活。

动笔前笔者照移植的老习惯，去板级 C 文件里找 setup_uart 这样的串口预备函数，grep 跑完一条命中都没有——这块板的串口预备活根本不住在板级代码里。那它住哪，咱们顺着初始化链一层层看下去，第四节给答案。方法交代在前面：本篇全部证据来自主机侧源码取证，grep 真跑，输出原样贴进正文，行号就是这棵 v2026.10 树当下的行号，咱们跟着敲一遍就能对上。

## 二、串口驱动初始化链

### 驱动本体：一个文件两层皮

看驱动先看它把自己摆在哪。咱们把第一条 grep 对着 serial_mxc.c 撒下去：

```bash
# 主机 ~/imx-forge
grep -n "serial_init\|mxc_serial" third_party/uboot-mainline/drivers/serial/serial_mxc.c | head -6
```

```text
148:static void _mxc_serial_flush(struct mxc_uart *base)
160:static void _mxc_serial_init(struct mxc_uart *base, int use_dte)
162:	_mxc_serial_flush(base);
182:static void _mxc_serial_setbrg(struct mxc_uart *base, unsigned long clk,
187:	_mxc_serial_flush(base);
220:static void mxc_serial_setbrg(void)
```

serial_mxc.c 一共 441 行，笔者通读了一遍，里头住着两层驱动皮。前半段被 `#if !CONFIG_IS_ENABLED(DM_SERIAL)` 包住，是老式那层，不带设备参数的 mxc_serial_setbrg 就是它的居民。后半段换成 `#if CONFIG_IS_ENABLED(DM_SERIAL)`，这是驱动模型那一层。AES 的 defconfig 第 82、83 行配着 `CONFIG_DM_SERIAL=y` 与 `CONFIG_MXC_UART=y`，所以编进咱们固件的是第二层。第二层以 U_BOOT_DRIVER(serial_mxc) 挂号，of_match 列表里收着 `fsl,imx6ul-uart` 这串 compatible，`DM_FLAG_PRE_RELOC` 又保证它在重定位之前就能绑上设备。

设备被 probe 时驱动干的活很集中，咱们把执行路径捋了一遍。mxc_serial_probe 里先按 `CONFIG_IS_ENABLED(CLK_CCF)` 的条件取时钟并使能，AES 没配 CLK_CCF，这几行不参与编译，实际执行的只有 `_mxc_serial_init(plat->reg, plat->use_dte)`。这个函数的活计朴素：flush 掉发到一半的字，把 CR1 与 CR2 清零，原地转等 `UCR2_SRST` 自复位完成，再往 CR3、CR4、esc、tim、ts 写一组定值。波特率另有专门一步 `_mxc_serial_setbrg`：BIR 写 0xf，BMR 写 `clk / (2 * baudrate)`，115200 的波特率就是把 UART 时钟频率除以 230400 填进去。CR2 一笔写成 `WS | IRTS | RXEN | TXEN | SRST`，8 位数据、忽略 RTS、收发都开。末了 CR1 写 `UCR1_UARTEN`，串口这才真正能收发。

对上层它只交出四个钩子，咱们把 dm_serial_ops 表数了一遍，里头只有 putc、pending、getc、setbrg，没有 puts。上层想打一句话怎么办，serial-uclass.c 里的 `_serial_puts` 写得明白：驱动没有 puts 钩子时逐字符循环，一个字符一个字符过 `_serial_putc`。AES 的串口输出就是这么一个字一个字挤出去的，串口这一层的通用调度全在 serial-uclass.c，驱动只管往寄存器里塞字节。

### 排进 init_sequence_f 的第 961 格

驱动再好也得有人按顺序来调。U-Boot 重定位之前的初始化队列在 common/board_f.c 的 init_sequence_f 里，串口相关的几格咱们抄下来：

```bash
# 主机 ~/imx-forge
grep -n "INITCALL(serial_init)\|INITCALL(console_init_f)\|INITCALL(display_options)" third_party/uboot-mainline/common/board_f.c
```

```text
961:	INITCALL(serial_init);		/* serial communications setup */
962:	INITCALL(console_init_f);	/* stage 1 init of console */
963:	INITCALL(display_options);	/* say that we are here */
```

三格连排，前头还有一格 init_baud_rate 把波特率先定下来，setbrg 算 BMR 用的就是它。serial_init 本体咱们跟进去看：进门先调 serial_find_console_or_panic，它顺着设备树 chosen 节点的 stdout-path 找串口设备，serial_check_stdout 读出这个属性，再按节点拿到 UCLASS_SERIAL 的设备并触发 probe，也就是上一小节那套寄存器活。找到之后把 `GD_FLG_SERIAL_READY` 插进 gd->flags，再补一发 setbrg。到这一步，硬件能出声了，可 console 层还没挂上牌。

banner 自己排在第 963 格，咱们对着队列核过，它前面正好两步：961 让驱动活起来，962 的 console_init_f 把 `GD_FLG_HAVE_CONSOLE` 插上。所以第一行输出的诞生时刻被序列钳得很死，只可能出在 963 之后，再早的打印谁也听不见，这话第三节展开。banner 也没有重打的机会——重定位之后的 board_r.c 队列里没有第二个 display_options，一生只打这一次。

## 三、puts 与 printf 走到哪

### 三个标志，三个时刻

console 的就绪不是一刀切，源码拿三个标志分出三个时刻。咱们把第二条 grep 对着标志名与 console_init 撒了一把：

```bash
# 主机 ~/imx-forge
grep -n "GD_FLG_DEVINIT\|console_init" third_party/uboot-mainline/common/console.c | head -8
```

```text
46:	if (console == -1 || (gd->flags & GD_FLG_DEVINIT) == 0)
358:	if (gd->flags & GD_FLG_DEVINIT)
443:	if ((gd->flags & GD_FLG_DEVINIT) &&
617:	if (gd->flags & GD_FLG_DEVINIT) {
637:	if (gd->flags & GD_FLG_DEVINIT) {
740:		if (!(gd->flags & GD_FLG_DEVINIT))
751:	if (gd->flags & GD_FLG_DEVINIT) {
780:		if (!(gd->flags & GD_FLG_DEVINIT))
```

贴出的 8 条全落在判断位上，命令挂了 head -8，console.c 全文命中其实是 15 处，笔者拿 grep -c 数过，第 791 行 puts 门口那条后文马上会用到。第 46 行在环境变量回调里，stdin、stdout、stderr 有变动它才理会。第 740 与 751 行守在 putc 门口，DEVINIT 置没置位决定字符走 stdio 层还是直落驱动。其余几条是同一判断在输入侧与 stderr 旁支的变体，不逐条念了。这个输出没露置位的地方，笔者补一个全量的：

```bash
# 主机 ~/imx-forge
grep -n "GD_FLG_DEVINIT" third_party/uboot-mainline/common/console.c | grep "|="
```

```text
1184:	gd->flags |= GD_FLG_DEVINIT;	/* device initialization completed */
1254:	gd->flags |= GD_FLG_DEVINIT;	/* device initialization completed */
```

第 1184 行落在 console_init_r 的 `SYS_CONSOLE_IS_IN_ENV` 版本里，AES 配了这个选项，走的正是这份，另一行是没配时的兄弟版本。console_init_r 由重定位后的 init_sequence_r 来调。三个时刻咱们排成了线：serial_init 置 `GD_FLG_SERIAL_READY`，硬件会出声。console_init_f 置 `GD_FLG_HAVE_CONSOLE`，输出不再被当垃圾丢掉。console_init_r 置 `GD_FLG_DEVINIT`，console 升格成标准输入输出设备，从此可以挪窝。

### 就绪前：打印可能无声消失

putc 与 puts 的核心判断在 console.c 第 751 行与第 791 行，putc 那段咱们抄出来：

```c
	if (!(gd->flags & GD_FLG_HAVE_CONSOLE))
		return pre_console_putc(c);

	if (gd->flags & GD_FLG_DEVINIT) {
		/* Send to the standard output */
		fputc(stdout, c);
	} else {
		/* Send directly to the handler */
		pre_console_putc(c);
		serial_putc(c);
	}
```

DEVINIT 没置位时直接下探 serial_putc，这条路直通硬件，穿过 serial-uclass.c 里那层壳，落到驱动的 putc 钩子上。可 HAVE_CONSOLE 也没置位呢，就拐进 pre_console_putc。笔者顺着翻过去，这函数名里带着缓冲的承诺，但 AES 没配 `CONFIG_PRE_CONSOLE_BUFFER`，编译出来只是个空函数，字符进了它就没了声响。

::: warning 早期打印无声消失
移植新板、串口还没调通的阶段，写在 banner 之前的 printf 一条都不会出现在串口里，也没有任何报错。根因就在上面的分支上：DEBUG_UART 没配（AES 的 defconfig 里没有 DEBUG_UART 行）就进不了 printch 的兜底（把字符直打进 debug UART 的函数，守卫在第 734 行，调用在第 735 行），HAVE_CONSOLE 未置位又让输出拐进空壳 pre_console_putc，字符被静默丢掉。排查时您先别急着怀疑接线，先看打印落在序列哪一格之前。
:::

### 就绪后：中间隔了一层 stdio

DEVINIT 置位之后，同样这行打印换了个出口，fputc(stdout, c) 走标准输入输出层。这一层是 console_init_r 亲手搭的，咱们把它干的活按顺序过一遍：先把跳转表挂到 serial 上当默认，再按环境变量 stdin、stdout、stderr 找设备，AES 配了 `CONFIG_SYS_CONSOLE_IS_IN_ENV=y`（defconfig 第 21 行）又没开 CONSOLE_MUX，走的是单选逻辑，环境里没写就回落到名叫 serial 的设备。第 1176 行把现状打成三行设备登记，In:、Out:、Err: 各占一行，板子到手开机就照这三行核对输入输出口径。末了第 1184 行才把 DEVINIT 插上。

printf 本体住在 lib/vsprintf.c，一层薄壳转进 vprintf，格式化结果放进栈上的 printbuffer，缓冲大小由 `CONFIG_SYS_PBSIZE` 定，咱们查了 AES 给的数：532 字节，超长的部分被截断，然后交给 puts 汇进同一条流。两条路收成一张对比表：

| 阶段 | 门口标志 | puts 的出口 | 能否重定向 |
|---|---|---|---|
| 961 到 1184 之间 | SERIAL_READY、HAVE_CONSOLE 已置，DEVINIT 未置 | serial_puts，直落驱动 putc 钩子 | 否，串口独占 |
| 1184 之后 | DEVINIT 已置 | fputs(stdout, s)，经 stdio 层 | 是，stdout 可改指别的设备 |

## 四、板级贡献了什么

咱们把板级文件翻个底朝天，这是第三条 grep 的原样结果：

```bash
# 主机 ~/imx-forge
grep -n "setup_uart\|uart" third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c | head -6
```

```text
```

一条命中都没有，输出是空的。笔者换成整个板级目录再扫一遍，`grep -rn uart board/nxp/mx6ull_aes_emmc/`，还是零命中，这个目录连同 imximage.cfg、plugin.S 一起，没有一个词提到 uart。把 mx6ull_aes_emmc.c 全文 165 行读完，跟串口能扯上关系的只有空转的 board_early_init_f，它进来就 return 0，defconfig 里 `CONFIG_BOARD_EARLY_INIT_F=y` 倒是开着，所以它确实会被调到，只是啥也不干。board_init 管的是启动参数地址、FEC 网口与 QSPI 时钟，一样没串口的事。

结论有点反直觉：这块板的串口预备活，板级 C 代码一行都没参与，两件前置活各有各的住处，咱们一件一件找。引脚复用住在设备树里，imx6ull-aes.dtsi 的 chosen 节点把 stdout-path 指到 &uart1，又给 uart1 挂上 `pinctrl-0 = <&pinctrl_uart1>`，TX、RX 两组引脚各配 0x1b0b1 的 pad 值：

```text
pinctrl_uart1: uart1grp {
    fsl,pins = <
        MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX 0x1b0b1
        MX6UL_PAD_UART1_RX_DATA__UART1_DCE_RX 0x1b0b1
    >;
};
```

谁去套这组引脚，DM 框架代劳，这条线咱们也核过：设备 probe 时，驱动核心会对每个非根、又不是 pinctrl 设备的家伙调 `pinctrl_select_state(dev, "default")`，AES 在 defconfig 里配着 `CONFIG_PINCTRL_IMX6=y`，串口一被 probe，引脚就位，板级代码全程没出手。

时钟门开得更早，开门的手是 BootROM 时代就备好的 DCD，咱们把 imximage.cfg 里那七条 DATA 抄下来：

```text
DATA 4 0x020c4068 0xffffffff
DATA 4 0x020c406c 0xffffffff
DATA 4 0x020c4070 0xffffffff
DATA 4 0x020c4074 0xffffffff
DATA 4 0x020c4078 0xffffffff
DATA 4 0x020c407c 0xffffffff
DATA 4 0x020c4080 0xffffffff
```

0x020c4068 到 0x020c4080 正是 CCM 的 CCGR0 到 CCGR6 七个时钟门控寄存器，地址咱们在参考手册里核过，一口气全写 0xffffffff，七个门全开到最大，UART1 的门在其中。这份清单由 BootROM 在跳转之前逐条执行，本卷 03 章《DCD 逐条读》逐条走过。所以驱动从没碰过时钟开关，setbrg 只管问频率：serial_mxc.c 调 imx_get_uartclk，实现在 arch/arm/mach-imx/mx6/clock.c，转手交给 get_uart_clk，拿回来的数除以 230400 填进 BMR。

::: warning 换板移植的哑串口
把这套推到自己的板上时，DCD 若漏开 UART 所在的那个 CCGR 门，驱动照常把 CR1、CR2 写进去，串口一声不出，全程没有错误码。根因是时钟门没开，写进外设寄存器的值落不到电路里。您对照参考手册查 UART 时钟挂在 CCGR 几号位，回 imximage.cfg 补上对应的 DATA 行，再回头排查驱动。
:::

## 五、自证：把横幅那行字追到底

绳头交到咱们手里了，顺着 banner 从字符串追到寄存器，每一步的输出都是笔者刚跑的。头一个问：那行字本体住在哪。

```bash
# 主机 ~/imx-forge
grep -n "version_string" third_party/uboot-mainline/common/version.c
```

```text
9:#include <version_string.h>
14:const char version_string[] = U_BOOT_VERSION_STRING;
```

version_string 是个字符数组，内容由 U_BOOT_VERSION_STRING 宏展开，咱们把展开过程也对了一遍：顶层 Makefile 编译时把 `VERSION = 2026`、`PATCHLEVEL = 10` 与编译时刻拼进去，所以 05 章拿 strings 从产物里抓到的是 `U-Boot 2026.10-dirty (Nov 14 2026 - 17:02:31 +0800)` 那一行。接着看谁把它搬出来：

```bash
# 主机 ~/imx-forge
sed -n '46,54p' third_party/uboot-mainline/lib/display_options.c
```

```c
int display_options(void)
{
	char buf[DISPLAY_OPTIONS_BANNER_LENGTH];

	display_options_get_banner(true, buf, sizeof(buf));
	printf("%s", buf);

	return 0;
}
```

display_options_get_banner_priv 用 snprintf 在头尾各垫两个换行，把 banner 拼进栈上的 buf，第 51 行 `printf("%s", buf)` 把它交出去，咱们要追的就是这个 printf 的去向。

这一刻 puts 走哪条路，答案已经在前头等着，咱们把这条路从头串一遍：banner 打印发生在序列 963 格，DEVINIT 要等重定位后的 console_init_r 才置位，console.c 里第 791 行那条 DEVINIT 判断落空，字符落进 serial_puts。serial-uclass.c 的壳拿到 gd->cur_serial_dev，`_serial_puts` 发现驱动没 puts 钩子，逐字符过 `_serial_putc`，换行还会补成 \r\n。最后一站是 mxc_serial_putc。TS 寄存器里 `UTS_TXFULL` 没满，就把字符 writel 进 txd。struct mxc_uart 定义在 serial_mxc.c 第 122 行，txd 排在第 126 行，前面隔着 rxd 与 15 个保留字，偏移正好 0x40。uart1 的基址从设备树来，imx6ul.dtsi 里 uart1 节点的 reg 摆着 0x02020000：

```text
uart1: serial@2020000 {
	compatible = "fsl,imx6ul-uart",
		     "fsl,imx6q-uart";
	reg = <0x02020000 0x4000>;
```

0x02020000 加 0x40，落点 0x02020040。咱们看见 banner 出现在终端的那一瞬，CPU 正把这个地址写了一遍又一遍。三个就绪时刻也在同一条时间轴上排好了：961 格驱动能出声，963 格 banner 出门，重定位之后 board_r.c 第 734 格的 console_init_r 把 DEVINIT 插上，stdout 从此不再固定在串口上。banner 之后还有一行 Awesome Embedded Studio Authored，它出自 board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c 第 154 行的 checkboard（板级署名打印函数，第 155 行那行 puts 打的就是这行字）。这一行打得早，重定位之前 board_f.c 队列里 DISPLAY_BOARDINFO 门下的 show_board_info 先打 Model 行再调它（该选项对 ARM 默认开），走的还是第三节那张表里 DEVINIT 未置位的直连串口路。

## 继续学习

- [串口验收：亲眼看见咱们编的 U-Boot 活着](../05_serial_acceptance.md)：拿本篇的函数链回去，把那张对照表逐行对到源码上。
- [DCD 逐条读：BootROM 替咱们执行的初始化清单](./03_dcd_walkthrough.md)：CCGR 七条 DATA 行的完整上下文与逐条解读在那一篇。
- [串口日志阅读路线：从一行输出找到下一站](../../debug/03_serial_log_reading.md)：banner 之后的报错行怎么读，debug 卷有专门一篇。
