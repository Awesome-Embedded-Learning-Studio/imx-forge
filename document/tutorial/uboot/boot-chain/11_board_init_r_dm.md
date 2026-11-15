---
title: board_init_r 与驱动模型扫描：设备树变活设备
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# board_init_r 与驱动模型扫描：设备树变活设备

> 搬家那篇收尾时，字面量池里躺着 board_init_r 的地址，咱们对着它核完了 7675 条重定位记录，故事停在跳转前的最后一格。本篇就跨进这个函数，把后半程初始化走完：设备树里的节点怎么在扫描中对上驱动，变成能 probe 的活设备，mmc、网卡、串口各自挂在序列哪一格、什么时候真正可用。console 那篇讲的前半程在本篇对出下半张图，env 加载与倒计时排在下一篇，它要读回的 8 KB 环境恰恰住在本篇养活的 eMMC 设备上。

## 一、后半程的初始化 —— board_init_r 与 initcall_run_r

探针第一条，笔者照原样撒下去：

```bash
# 主机 ~/imx-forge
grep -n "init_sequence_r" third_party/uboot-mainline/common/board_r.c | head -3
```

```text
```

空的，grep 以退出码 1 收场。旧版 U-Boot 里这个队列叫 init_sequence_f，是个数组，常见教程沿用这个叫法，这棵 v2026.10 树把它换成了函数。console 那篇引用的行号本身站得住，它用的是旧名字，改名不改行的位置，同一个 grep 在 board_f.c 上跑也会空手而归。咱们换个关键词立刻现形：

```bash
# 主机 ~/imx-forge
grep -n "initcall_run" third_party/uboot-mainline/common/board_r.c third_party/uboot-mainline/common/board_f.c
```

```text
common/board_r.c:595:static void initcall_run_r(void)
common/board_r.c:806:	initcall_run_r();
common/board_f.c:917:static void initcall_run_f(void)
common/board_f.c:1081:	initcall_run_f();
common/board_f.c:1109:static void initcall_run_f_r(void)
common/board_f.c:1118:	initcall_run_f_r();
```

咱们把两个调起点的行号并排核一遍，前半程 initcall_run_f 由 board_init_f 在第 1081 行调起，后半程 initcall_run_r 由 board_init_r 在第 806 行调起，两个函数各自抱着一串 INITCALL。跳进 board_init_r 的那一下，行号是本篇现核的。crt0.S 第 195 行把 board_init_r 的地址装进 lr，第 196 行 bx lr 跳过去，第 198 行的 ldr pc 是非 Thumb 分支的写法，这份产物没编它，ARCH_MX6 名下 imply SYS_THUMB_BUILD，那一条写在 arm/Kconfig 第 1014 行起的块里，out/uboot/.config 第 69 行可查。字面量池里 0x87815ca5 正是 board_init_r 加 1，那个 1 是 Thumb 位，搬家那篇追到过。本篇就从这条跳转落地开始写。进门第一件事值得整段看，board_r.c 第 779 行起：

```c
void board_init_r(gd_t *new_gd, ulong dest_addr)
{
	/*
	 * The pre-relocation drivers may be using memory that has now gone
	 * away. Mark serial as unavailable - this will fall back to the debug
	 * UART if available.
	 *
	 * Do the same with log drivers since the memory may not be available.
	 */
	gd->flags &= ~(GD_FLG_SERIAL_READY | GD_FLG_LOG_READY);
```

函数体不长，主角是第 595 行那条队列。注释自己交代了脾气：这函数不许加逻辑，永远保持一列函数调用。咱们把 AES 用得着的几格抄下来：

```c
static void initcall_run_r(void)
{
	/*
	 * Please do not add logic to this function (variables, if (), etc.).
	 * For simplicity it should remain an ordered list of function calls.
	 */
	INITCALL(initr_trace);
	INITCALL(initr_reloc);
```

```c
	INITCALL(initr_of_live);
#if CONFIG_IS_ENABLED(DM)
	INITCALL(initr_dm);
#endif
#if CONFIG_IS_ENABLED(ADDR_MAP)
	INITCALL(init_addr_map);
#endif
#if CONFIG_IS_ENABLED(BOARD_INIT)
	INITCALL(board_init);	/* Setup chipselects */
#endif
```

```c
	INITCALL(initr_dm_devices);
	INITCALL(stdio_init_tables);
	INITCALL(serial_initialize);
	INITCALL(initr_announce);
	INITCALL(dm_announce);
```

```c
#if CONFIG_IS_ENABLED(MMC)
	INITCALL(initr_mmc);
#endif
#if CONFIG_IS_ENABLED(XEN)
	INITCALL(xen_init);
#endif
#if CONFIG_IS_ENABLED(PVBLOCK)
	INITCALL(initr_pvblock);
#endif
	INITCALL(initr_env);
```

```c
#if CONFIG_IS_ENABLED(NET)
	WATCHDOG_RESET();
	INITCALL(initr_net);
#endif
#if CONFIG_IS_ENABLED(POST)
	INITCALL(initr_post);
#endif
	WATCHDOG_RESET();
	INITCALL_EVT(EVT_LAST_STAGE_INIT);
#if defined(CFG_PRAM)
	INITCALL(initr_mem);
#endif
	INITCALL(initr_boot_led_on);
	INITCALL(run_main_loop);
```

run_main_loop 是队尾，进去就是 `for (;;)` 的 main_loop，再也不回来。前后半程的分工，咱们收成一张对照表：

| | 前半程 | 后半程 |
|---|---|---|
| 队列真名 | initcall_run_f 在 board_f.c 第 917 行 | initcall_run_r 在 board_r.c 第 595 行 |
| 内存状态 | SYS_MALLOC_F 受限池，BSS 没清、字面量池没修（搬家那篇立过） | 第 602 格 initr_reloc 插上 GD_FLG_RELOC 与 GD_FLG_FULL_MALLOC_INIT，第 619 格 initr_malloc 换全量池 |
| DM 树 | 第 945 格 initf_dm 调 dm_init_and_scan(true)，只绑带旗的设备 | 第 630 格 initr_dm 丢掉旧树，dm_init_and_scan(false) 全绑 |
| console | 第 961 格 serial_init 起硬件，第 962 格插 HAVE_CONSOLE | 第 734 格 console_init_r 插 DEVINIT，stdout 从此可挪窝 |

咱们把两半程的处境并在一起看，分工的根子在内存。前半程每一格都得踩着受限池小心走，设备树的大扫描摆不下。后半程全量池立起来，扫描才有地方给每台设备分私有的 plat 与 priv。这个顺序谁也换不得。

## 二、驱动模型扫描 —— dm_init 与 uclass、device、driver 三概念

第 630 格 initr_dm 是本篇的心脏。第二条探针在 board_r.c 里只找到一处命中，咱们整段抄：

```bash
# 主机 ~/imx-forge
grep -n "dm_init\|dm_scan" third_party/uboot-mainline/common/board_r.c | head -5
```

```text
267:	ret = dm_init_and_scan(false);
```

```c
#ifdef CONFIG_DM
static int initr_dm(void)
{
	int ret;

	oftree_reset();

	/* Drop the pre-reloc driver model and start a new one */
	gd->dm_root = NULL;
#ifdef CONFIG_TIMER
	gd->timer = NULL;
#endif
	bootstage_start(BOOTSTAGE_ID_ACCUM_DM_R, "dm_r");
	ret = dm_init_and_scan(false);
	bootstage_accum(BOOTSTAGE_ID_ACCUM_DM_R);
	if (ret)
		return ret;

	return dm_autoprobe();
}
#endif
```

头两行最狠。oftree_reset 之后 gd->dm_root 置空，注释写得直白，Drop the pre-reloc driver model and start a new one：重定位前那棵小树连同它的设备、私有数据一起作废。那些结构住在 OCRAM 的受限池里，07 篇算过，gd 和早期堆都挤在那 0x2000 里。全量池另起炉灶，board_r.c 第 227 行的注释写明新堆紧跟 monitor copy 之下，第 233 行按 gd->relocaddr 减 TOTAL_MALLOC_LEN 起算。代码和驱动结构整体搬了家，旧树里的指针指着搬走前的地址，留着就是死结构。

扫描牵扯三个概念，咱们拿 AES 的真实驱动对号。driver 是配方，U_BOOT_DRIVER 宏把一个 struct driver 登记进链接器收拢的表，fsl_esdhc_imx.c 第 1687 行那份挂着 of_match 匹配表、probe 钩子和 ops 接口。device 是实例，设备树一个节点绑一次，绑的动作在 device.c 第 249 行 device_bind，plat 与 priv 随绑分配。uclass 是接口柜，UCLASS_MMC、UCLASS_ETH、UCLASS_SERIAL 各占一格，柜只认 ops 不认芯片，mmc.c 那层通用逻辑全靠柜写，drivers/core/uclass.c 第 145 行的 uclass_get 负责开柜，柜的链表头在 dm_init 里挂上 gd->uclass_root。

咱们顺着这条调用链往下走。dm_init_and_scan(false) 落在 drivers/core/root.c 第 370 行，里面是第 93 行的 dm_init，它造根设备并 probe 自己，接着 dm_scan 先扫平台设备再进设备树，末尾按 DM_EVENT 发通知。设备树那半截在 dm_extended_scan，第 246 行起：

```c
int dm_extended_scan(bool pre_reloc_only)
{
	int ret, i;
	const char * const nodes[] = {
		"/chosen",
		"/clocks",
		"/firmware",
		"/reserved-memory",
	};

	ret = dm_scan_fdt(pre_reloc_only);
	if (ret) {
		dm_warn("dm_scan_fdt() failed: %d\n", ret);
		return ret;
	}

	/* Some nodes aren't devices themselves but may contain some */
	for (i = 0; i < ARRAY_SIZE(nodes); i++) {
```

咱们跟着扫描走到设备树这半截：dm_scan_fdt 从根逐层走，本层循环只扫一层子节点，这个循环是 root.c 第 195 行起的 dm_scan_fdt_node，simple-bus 这类总线设备的 uclass 在 simple-bus.c 第 56 行的 post_bind 钩子里调 dm_scan_fdt_dev，深层节点一层层带出来。lists_bind_fdt 对每个启用的节点都调，不带 compatible 的在里面静默返回。配对的原料两份，节点侧在 lists.c 第 216 行把 compatible 属性整块读出，驱动侧是链接器收拢的整张 driver 表。匹配循环外层逐串试 compatible，内层逐个驱动，lists.c 第 181 行的 driver_check_compatible 拿 strcmp 比对 of_match 表，比中即绑。关键在顺序，compatible 列表按优先级从头试到尾，源码注释写明 match in order of priority。

AES 设备树里有个现成的活教材，咱们拿 usdhc 这对控制器来看。usdhc1、usdhc2 在 imx6ul.dtsi 第 895、909 行写的 compatible 是 fsl,imx6ul-usdhc 与 fsl,imx6sx-usdhc，到 imx6ull.dtsi 第 44 至 50 行，6ULL 的覆盖把首串改写了：

```dts
&usdhc1 {
	compatible = "fsl,imx6ull-usdhc", "fsl,imx6sx-usdhc";
};

&usdhc2 {
	compatible = "fsl,imx6ull-usdhc", "fsl,imx6sx-usdhc";
};
```

最终 FDT 里每台控制器顶着这两串。头一串 fsl,imx6ull-usdhc，笔者把 drivers/ 全目录扫了一遍，一条都对不上，第二串 fsl,imx6sx-usdhc 在匹配表里等着。头串落空、次串接住，前面 match in order of priority 那条注释在这台设备上看得最清楚。配对的另一半长这样，fsl_esdhc_imx.c 第 1661 行起：

```c
static const struct udevice_id fsl_esdhc_ids[] = {
	{ .compatible = "fsl,imx51-esdhc", },
	{ .compatible = "fsl,imx53-esdhc", },
	{ .compatible = "fsl,imx6ul-usdhc", },
	{ .compatible = "fsl,imx6sx-usdhc", },
	{ .compatible = "fsl,imx6sl-usdhc", },
	{ .compatible = "fsl,imx6q-usdhc", },
	{ .compatible = "fsl,imx7d-usdhc", .data = (ulong)&usdhc_imx7d_data,},
	{ .compatible = "fsl,imx7ulp-usdhc", .data = (ulong)&usdhc_imx7ulp_data,},
	{ .compatible = "fsl,imx8qm-usdhc", .data = (ulong)&usdhc_imx8qm_data,},
```

第三条探针顺带交代，它对着 fsl_esdhc.c 查 compatible：

```bash
# 主机 ~/imx-forge
grep -rn "compatible" third_party/uboot-mainline/drivers/mmc/fsl_esdhc.c 2>/dev/null | head -3 || ls third_party/uboot-mainline/drivers/mmc/ | head -10
```

```text
1185:	{ .compatible = "fsl,esdhc", },
```

咱们把这条命中往下查一层：命中是真的，但这份文件不进 AES 固件。drivers/mmc/Makefile 第 36、37 行写得分明，fsl_esdhc.o 挂在 CONFIG_FSL_ESDHC 下，fsl_esdhc_imx.o 挂在 CONFIG_FSL_ESDHC_IMX 下。AES 的 defconfig 只有第 64 行 CONFIG_FSL_USDHC=y，它 select FSL_ESDHC_IMX，这条 select 写在 drivers/mmc/Kconfig 第 940 行，另一份压根没编。两条匹配表里都躺着 fsl,esdhc，真正干活的始终是 imx 这份。

bind 不等于 probe，咱们分开说。dm_init_and_scan 回来后 initr_dm 补了一发 dm_autoprobe，名字唬人，活儿克俭，dm_probe_devices 只探带着 DM_FLAG_PROBE_AFTER_BIND 旗的设备：

```c
	if (dev_get_flags(dev) & DM_FLAG_PROBE_AFTER_BIND) {
		ret = device_probe(dev);
		if (ret)
			return ret;
	}
```

usdhc、fec 都不在旗下，老老实实等点名，点名分别来自第 704 格与第 765 格，第三节展开。绑定阶段驱动自己先干的活是 of_to_plat，咱们看它在这台板上收走了什么：fsl_esdhc_imx.c 第 1389 行的 fsl_esdhc_of_to_plat 拿 dev_read_addr 读 reg，usdhc2 的 0x02194000 就是这么进 priv 的，fsl,tuning-step、cd-gpios 这批属性也一并收走。

u-boot,dm-pre-reloc 一句。笔者照原样在 drivers、include、arch/arm/dts 三个目录各扫一遍，零命中。判别函数 ofnode.c 第 1668 行的 ofnode_pre_reloc 如今只认 bootph 这批属性：

```c
bool ofnode_pre_reloc(ofnode node)
{
#if defined(CONFIG_XPL_BUILD) || defined(CONFIG_TPL_BUILD)
	/* for SPL and TPL the remaining nodes after the fdtgrep 1st pass
	 * had property bootph-all or bootph-pre-sram/bootph-pre-ram.
	 * They are removed in final dtb (fdtgrep 2nd pass)
	 */
	return true;
#else
	if (ofnode_read_bool(node, "bootph-all"))
		return true;
	if (ofnode_read_bool(node, "bootph-some-ram"))
		return true;

	/*
	 * In regular builds individual spl and tpl handling both
	 * count as handled pre-relocation for later second init.
	 */
	if (ofnode_read_bool(node, "bootph-pre-ram") ||
	    ofnode_read_bool(node, "bootph-pre-sram"))
		return gd->flags & GD_FLG_RELOC;

	return false;
#endif
}
```

节点带旗是一半，另一半在配对现场的检查条件上：pre_reloc_only 为真时，节点没有 bootph 旗、驱动又没有 DM_FLAG_PRE_RELOC 旗，lists_bind_fdt 直接跳过它。咱们顺着 include 链找，AES 的 bootph 藏在链上的另一份 dtsi 里。imx6ull-aes.dts、imx6ull-aes.dtsi、imx6ull.dtsi、imx6ul.dtsi 四份主文件里 grep bootph，零命中，可 imx6ull-aes.dts 第 9 行 include 的 imx6ull-14x14-evk-u-boot.dtsi 里有两处 bootph-all，分别挂在 &pinctrl_uart1 与 &rngb 名下，设备树那篇讲覆盖时点过它。串口重定位前能活着，靠两样合力：serial_mxc.c 第 413 行那面 DM_FLAG_PRE_RELOC 把 uart1 绑进 945 格的小树，overlay 的 bootph-all 把串口引脚组留在册上。usdhc 和 fec 连 bootph 也不沾，点名之前它们不在册。root.c 名单里那个 /chosen，是给 stdout-path 这类不入册的容器留的特批通道。

::: warning compatible 全串落空的设备一声不响
匹配失败的出口是安静的：节点连 compatible 都没有时，lists.c 里只有一句 log_debug 就 return 0，板上没有任何报错，设备就是不出现。根因在机制本身，配对是逐串试出来的。usdhc 这个案例就是提醒：imx6ull.dtsi 改写首串、驱动表里没有它，全靠次串 fsl,imx6sx-usdhc 兜底。咱们移植自己的板子时，compatible 每一串都要 grep 得到对应驱动再编译，别指望 U-Boot 替咱们喊。
:::

## 三、三类设备挂载时刻 —— mmc、fec 网卡、uart

### mmc：第 704 格点名

咱们从 mmc 这格看起。initr_mmc 的门是 CONFIG_IS_ENABLED(MMC)。AES 的 defconfig 里没有 CONFIG_MMC= 这一行，可这一格照跑，因为 drivers/mmc/Kconfig 第 5 行给 MMC 配了 default ARM || PPC || SANDBOX，ARM 板默认就开着，还顺带 select BLK 与 DM_MMC。第 704 格进门先 `puts("MMC:   ")`，进门调第 3275 行的 mmc_initialize，转手交给第 3237 行的 mmc_probe，DM 版本长这样：

```c
static int mmc_probe(struct bd_info *bis)
{
	int ret, i;
	struct uclass *uc;
	struct udevice *dev;

	ret = uclass_get(UCLASS_MMC, &uc);
	if (ret)
		return ret;

	/*
	 * Try to add them in sequence order. Really with driver model we
	 * should allow holes, but the current MMC list does not allow that.
	 * So if we request 0, 1, 3 we will get 0, 1, 2.
	 */
	for (i = 0; ; i++) {
		ret = uclass_get_device_by_seq(UCLASS_MMC, i, &dev);
		if (ret == -ENODEV)
			break;
	}
	uclass_foreach_dev(dev, uc) {
		ret = device_probe(dev);
		if (ret)
			log_err("%s - probe failed: %d\n", dev->name, ret);
	}

	return 0;
```

uclass_get 把 UCLASS_MMC 柜拿出来，uclass_foreach_dev 逐台 device_probe。AES 两台控制器都绑在柜里，咱们分开看：usdhc1 是 SD 卡座，靠 cd-gpios 做插卡检测。usdhc2 是 eMMC，non-removable，imx6ull-aes.dtsi 第 398 行起：

```dts
&usdhc2 {
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_usdhc2>;
	non-removable;
	keep-power-in-suspend;
	wakeup-source;
	status = "okay";
};
```

probe 落到第 1461 行的 fsl_esdhc_probe。咱们跟进去走一遍：AES 没配 CONFIG_CLK，defconfig 通篇 105 行找不出 CLK，编译走 #else 分支：init_clk_usdhc(dev_seq) 先把时钟开好，priv->sdhc_clk 再从 mxc_get_clock(MXC_ESDHC_CLK + dev_seq) 按序号问频率。源码注释在这里留了句提醒，序号想对准，设备树里最好给 aliases 排上 mmc0、mmc1。寄存器基址 0x02190000 与 0x02194000 来自 imx6ul.dtsi 里的 reg，早在 of_to_plat 阶段就进了 priv，probe 的收尾落在第 1152 行的 fsl_esdhc_init，第 1215 行把 cfg->name 写成 FSL_SDHC，板上 MMC: 后面跟的就是这个名字。

### fec：第 765 格点名，全序列最晚

咱们再看 fec 这一路。initr_net 的门是 CONFIG_IS_ENABLED(NET)，net/Kconfig 第 13 行 default y，AES 又配了 CMD_PING、CMD_DHCP 这些挂在 NET 底下的命令，这格必跑。进门 `puts("Net:   ")`，进门调第 475 行的 eth_initialize，第 488 行 uclass_first_device_check(UCLASS_ETH, &dev) 把柜里第一台探活。AES 两台 FEC 都 status okay，分别写在 imx6ull-aes.dtsi 第 161 行与第 173 行。配对走 fec_mxc.c 第 1513 行的 fecmxc_ids，fec1 节点在 imx6ul.dtsi 第 875 行写的首串 fsl,imx6ul-fec 直接命中第 1518 行，连回退都不用。

fecmxc_probe 第 1249 行起，进门先 board_interface_eth_init 配引脚与接口模式，咱们跟进去看。AES 既没配 IMX8 也没配 CLK_CCF，fecmxc_probe 里 CONFIG_IMX8 与 CONFIG_CLK_CCF 两块取时钟分支整个编译掉，时钟活是 board_init 在前头干的，console 那篇翻板级文件时见过它。往后是探测里最有脾气的一段：

```c
	fec_gpio_reset(priv);
#endif
	/* Reset chip. */
	writel(readl(&priv->eth->ecntrl) | FEC_ECNTRL_RESET,
	       &priv->eth->ecntrl);
	start = get_timer(0);
	while (readl(&priv->eth->ecntrl) & FEC_ECNTRL_RESET) {
		if (get_timer(start) > (CONFIG_SYS_HZ * 5)) {
			printf("FEC MXC: Timeout resetting chip\n");
			ret = -ETIMEDOUT;
			goto err_timeout;
		}
		udelay(10);
	}

	fec_reg_setup(priv);
```

咱们接着跟引脚和复位这一段：引脚复位走 fec_gpio_reset，用的是 aes dtsi 里那根 phy-reset-gpios，200 毫秒低电平加 200 毫秒延迟。芯片软复位把 ECNTRL 的 RESET 位置上，原地轮询五秒，超时打印 FEC MXC: Timeout resetting chip 后带 -ETIMEDOUT 退出，这是 probe 阶段少数会喊出声的失败。复位过了再 fec_reg_setup 配寄存器，CONFIG_DM_MDIO 与 CONFIG_DM_ETH_PHY 在 defconfig 第 69、70 行，把 MDIO 总线交给 DM 管，defconfig 第 68 行那句注释就是为此写的。

### uart：前半程就活，后半程换零件再活一次

串口是三类里唯一的例外，咱们单独说。它在前半程 961 格就出声了，console 那篇整篇都在讲。本篇只讲后半程它经历了什么。搬家落地那一刻，board_init_r 第 788 行摘掉 SERIAL_READY 旗，注释交代了动机：重定位前的驱动可能踩着已经消失的内存，摘旗让输出回落 debug UART。AES 没配 DEBUG_UART，这段空窗里打印等于没有嘴。第 630 格丢掉旧树，串口设备跟着旧树一起没了。第 659 格 serial_initialize 重新点名，这回是 DM 那层的版本，drivers/serial/serial-uclass.c 第 232 行，注释写着 Called after relocation。树上另有一份不带 uclass 的同名函数住在 drivers/serial/serial.c 第 159 行，AES 在 defconfig 第 82 行配了 DM_SERIAL，走的是前者：

```c
int serial_initialize(void)
{
	/* Scanning uclass to probe devices */
	if (IS_ENABLED(CONFIG_SERIAL_PROBE_ALL)) {
		int ret;

		ret  = uclass_probe_all(UCLASS_SERIAL);
		if (ret)
			return ret;
	}

	return serial_init();
}
```

函数转手又调 serial_init，注释里写得清楚，serial_init 上方挂着 prior to relocation，serial_initialize 上方挂着 after relocation，同一个名字跑两遍，一遍伺候旧树，一遍伺候新树。新树里绑定不再看旗，uart1 靠 compatible 进树，serial_init 还是拿 /chosen 的 stdout-path 点名。找到设备、probe、setbrg，SERIAL_READY 重新插上。DEVINIT 要等到第 734 格 console_init_r，那是 console 那篇的结论，本篇把它的位置在后半程队列里摆正了。三类设备的位置与可用时刻，咱们收成一张表：

| 设备 | 挂载格 | 谁来 probe | probe 干的活 |
|---|---|---|---|
| uart1 | 前半程 961 格首活，后半程 659 格再活 | serial_init 按 stdout-path 点名 | mxc_serial_probe 写寄存器组 |
| usdhc1、usdhc2 | 后半程 704 格 | mmc_probe 逐台 device_probe | 拿基址、起时钟、登记 FSL_SDHC |
| fec1、fec2 | 后半程 765 格 | eth_initialize 点柜里第一台 | 引脚复位、芯片软复位、挂 MDIO 总线 |

咱们把三类设备的时刻并排一看，位置决定时刻，顺序本身就是时刻表。MMC 排在 env 之前，initr_env（第 712 格）才能把 8 KB 环境从 eMMC 读回来，那是下一篇的地盘。网卡排到倒数第几格，提示符前的 Net 行总是最后一批。这个顺序是 initcall_run_r 里一行一行排出来的，调换顺序的代价都写在依赖里。

## 四、自证 —— grep 数一数 AES 配置会启用多少 DM 驱动

探针第四条，数明面上的：

```bash
# 主机 ~/imx-forge
grep -c "CONFIG_DM" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
12
```

12 条。逐条列出来看性质：

```bash
# 主机 ~/imx-forge
grep -n "CONFIG_DM" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
11:CONFIG_DM_GPIO=y
60:CONFIG_DM_74X164=y
61:CONFIG_DM_I2C=y
66:CONFIG_DM_SPI_FLASH=y
69:CONFIG_DM_MDIO=y
70:CONFIG_DM_ETH_PHY=y
78:CONFIG_DM_REGULATOR=y
79:CONFIG_DM_REGULATOR_FIXED=y
80:CONFIG_DM_REGULATOR_GPIO=y
81:CONFIG_DM_RNG=y
82:CONFIG_DM_SERIAL=y
85:CONFIG_DM_SPI=y
```

明面 12 条里没有 DM_MMC、DM_ETH，可它们实实在在开着。暗地进来的路有三条，笔者把 Kconfig 原文抄给咱们：

```bash
# 主机 ~/imx-forge
sed -n '3,7p' third_party/uboot-mainline/drivers/mmc/Kconfig && sed -n '95,97p' third_party/uboot-mainline/drivers/net/Kconfig && sed -n '937,940p' third_party/uboot-mainline/drivers/mmc/Kconfig
```

```text
config MMC
	bool "MMC/SD/SDIO card support"
	default ARM || PPC || SANDBOX
	select BLK
	select DM_MMC
config NETDEVICES
	bool
	select DM_ETH
config FSL_USDHC
	bool "Freescale/NXP i.MX uSDHC controller support"
	depends on MX6 || MX7 ||ARCH_MX7ULP || IMX8 || IMX8M || IMX8ULP || IMX9 || IMXRT
	select FSL_ESDHC_IMX
```

咱们把这三条路挨个对上。MMC 默认 ARM 板就开，开着就 select BLK 与 DM_MMC。NETDEVICES 是个哑开关，bool 连描述都没有，select DM_ETH。FSL_USDHC 再 select FSL_ESDHC_IMX，usdhc 驱动跟着进来。所以数法有两种，defconfig 明写 12 条，依赖链暗带 DM_MMC、DM_ETH、BLK、FSL_ESDHC_IMX 一批。想盘点一块板子的 DM 家底，编译产物之外还有更直接的窗口，boot 日志里的 Core 行。那行来自 dm_announce，board_r.c 第 661 格点名，函数体第 545 行起，引文从第 550 行那条 if 进，IS_ENABLED(CONFIG_DM) 门里 dm_get_stats 数出设备与 uclass 两个数：

```c
	if (IS_ENABLED(CONFIG_DM)) {
		dm_get_stats(&device_count, &uclass_count);
		printf("Core:  %d devices, %d uclasses", device_count,
		       uclass_count);
		if (CONFIG_IS_ENABLED(OF_REAL))
			printf(", devicetree: %s", fdtdec_get_srcname());
```

板端还有一套 dm 命令，咱们把 cmd/dm.c 第 117 行的长帮助抄下来：

```text
	"dm devres        Dump list of device resources for each device\n"
	"dm drivers       Dump list of drivers with uclass and instances\n"
	DM_MEM_HELP
	"dm static        Dump list of drivers with static platform data\n"
	"dm tree [-s][-e][name]   Dump tree of driver model devices (-s=sort)\n"
	"dm uclass [-e][name]     Dump list of instances for each uclass");
```

这批命令，咱们在 AES 的现行固件里就能确认。AES 自己的目标块 TARGET_MX6ULL_AES_EMMC 在 arch/arm/mach-imx/mx6/Kconfig 第 461 行起就写了 imply CMD_DM，编出的 out/uboot/.config 第 677 行是 CONFIG_CMD_DM=y，dm 命令就在这份固件里，输出等板端核对。CMD_DM 自己在 cmd/Kconfig 第 1189 行，只 depends on DM，没有 default，ARCH_MX6 这个架构符号名下没有这一条，树里一百多处 imply 多撒在别的架构与目标名下，AES 沾的是自家目标块。

绳头留在 0x02194000 上。它是 usdhc2 的寄存器基址，reg 写在 imx6ul.dtsi 第 910 行，of_to_plat 阶段经 dev_read_addr 进了 priv，initr_env 那一格从它身后把 8 KB 环境读回来，env 器件编号 ENV_MMC_DEVICE_INDEX=1 在 defconfig 第 48 行写着，指的正是这台设备。笔者把这根绳头留在这儿，下一篇从那一格接着走。

## 继续学习

- [env 加载与倒计时：接管前的最后准备](./12_env_and_autoboot.md)：env_init 在重定位前登记后端、env_relocate 由 initr_env 在重定位后调起的源码之旅，倒计时住在 common/autoboot.c。
- [存储验收：在 U-Boot 里把 eMMC 摸一遍](../10_emmc_acceptance.md)：板上 mmc 信息的核对清单，对照 06 章样例日志，拿本篇的匹配链去对 FSL_SDHC 的编号。
- [设备树：imx6ull-aes 从参考板改到了咱们的板子](../08_device_tree_aes.md)：compatible 语法与节点覆盖的完整一课。
