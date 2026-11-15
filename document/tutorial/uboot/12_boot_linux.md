---
title: 启动 Linux：把内核装进板子完成交接
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 启动 Linux：把内核装进板子完成交接

> 本篇解决主线上剩下的一件事：U-Boot 已经能编、能验、能烧、能把 AES 板登记进源码树，内核怎么被它装进存储，又怎么被它亲手交出去。咱们把要装的三样东西的来历交代清，把装载命令与三个加载地址全部追到源码出处，再把板端要敲的那条启动脚本备好讲清。前面的铺垫在 [产物验证与烧录](./04_verify_and_flash.md) 与 [DDR 初始化与镜像头](./09_ddr_imxheader.md)，交接之后的内核世界归内核卷与 rootfs 卷，链路前半段的逐字节深读归扩展卷 boot-chain。板子不在手边，板端动作笔者一条都没实证，能验的全在主机侧，证据随行贴出。

## 一、最终里程碑的清单：三样东西，一次交接

要装进存储的东西，咱们数出来三样。zImage 是内核本体，ARM 上常用的自解压镜像格式，解压的活它自己带在身上。dtb 是编译好的设备树文件，一份硬件描述，内核靠它认出串口、网卡、分区挂在哪颗芯片的哪个外设上。根文件系统（rootfs）是内核把初始化跑完后要挂载的那个根，init 程序与一堆工具、配置全住在里面。三样分工不同，缺一样，交接就断在半路。

U-Boot 在这场交接里只干两件事——装载与交接，咱们把这两步分清：装载是把字节从存储读进内存，交接是把控制权送出门口。内核与 rootfs 怎么生产，它一概不问，前者归内核卷，后者归 rootfs 卷，本篇不重复造这两样。

内核侧两样，笔者手头就有真货，是内核卷 10 月 12 日编出的那一轮：

```bash
# 主机 ~/imx-forge
ls -la ~/experiments/linux-build/arch/arm/boot/zImage ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
file ~/experiments/linux-build/arch/arm/boot/zImage
```

```text
-rw-r--r-- 1 charliechen charliechen    35594 Oct 12 08:41 /home/charliechen/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
-rwxr-xr-x 1 charliechen charliechen 10369960 Oct 12 08:44 /home/charliechen/experiments/linux-build/arch/arm/boot/zImage
/home/charliechen/experiments/linux-build/arch/arm/boot/zImage: Linux kernel ARM boot executable zImage (little-endian)
```

zImage 10369960 字节，dtb 35594 字节，`file` 的判词 Linux kernel ARM boot executable zImage 说明它确实是 ARM 自解压内核镜像。dtb 咱们也认一眼门牌，拿 dtc 把它还原成文本，抓身份与内存两条：

```bash
# 主机 ~/imx-forge
dtc -I dtb -O dts ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb | grep -m2 "model =\|compatible ="
dtc -I dtb -O dts ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb | grep -A3 "device_type = \"memory\""
```

```text
	model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)";
	compatible = "fsl,imx6ull-14x14-evk\0fsl,imx6ull";
		device_type = "memory";
		reg = <0x80000000 0x20000000>;
	};
```

model 一行写着 Awesome Embedded Studio，compatible 挂在 fsl,imx6ull-14x14-evk 上，设备树那一章（08 章）给这块板换名的故事就落在这串字里。memory 节点声明内存从 0x80000000 起、共 0x20000000（512 MiB），这个声明到第三节还有下文，交接前它会被人亲手改写。rootfs 这一样本篇不生产，[Rootfs 概述](../rootfs/01_rootfs_overview.md) 把它为什么必须有、装些什么铺过底，咱们到第二节把它放进第二个分区，清单就齐了。

## 二、把它们放进存储：分区摆位与内存落点

存储这一侧，一块 SD 卡或一颗 eMMC 咱们都按两个分区摆。第一个分区当 boot 分区，放 zImage 与 imx6ull-aes.dtb 两个文件。第二个分区当 rootfs，内核起来后挂载的就是它。整卡镜像怎么从产物目录生成、又怎么写进卡里，flash 卷的 [为什么需要完整镜像](../flash/05_why_full_image.md)、[镜像布局设计](../flash/06_image_layout_design.md)、[脚本设计拆解](../flash/07_build_imx6ull_image_script.md) 与 [SD 卡烧录实战](../flash/09_sd_card_flashing.md) 实测过一遍，本篇不重走。分区格式那边也交代过：boot 分区做成 ext4，rootfs 同样是 ext4。

U-Boot 侧的读取命令要跟分区格式配套。ext4load 与 fatload 是一对兄弟，都把文件从分区读到内存，一个认 ext4，一个认 FAT。AES 头文件里两套并存，咱们把取证命令跑一遍，拿真实输出说话：

```bash
# 主机 ~/imx-forge
grep -n "loadaddr\|fdt_addr\|bootz\|fdt_file\|initrd" third_party/uboot-mainline/include/configs/mx6ull_aes_emmc.h | head -10
```

```text
32:	"kboot=bootz \0" \
43:	"initrd_addr=0x86800000\0" \
44:	"initrd_high=0xffffffff\0" \
55:	"initrd_high=0xffffffff\0" \
56:	"fdt_file=imx6ull-aes.dtb\0" \
57:	"fdt_addr=0x83000000\0" \
69:	"loademmcimage=ext4load mmc ${emmc_dev}:1 ${loadaddr} /zImage\0" \
70:	"loademmcfdt=ext4load mmc ${emmc_dev}:1 ${fdt_addr} /imx6ull-aes.dtb\0" \
76:		"bootz ${loadaddr} - ${fdt_addr};\0" \
79:	"loadsdimage=ext4load mmc ${sd_dev}:1 ${loadaddr} /zImage\0" \
```

十行输出，咱们按脚本的出身分两拨。69 到 86 行这一拨是 AES 板专属的 loademmcimage、loademmcfdt、loadsdimage、loadsdfdt，清一色 ext4load，从 mmc 1:1 或 mmc 0:1 把 /zImage 与 /imx6ull-aes.dtb 读进内存，分区号 1 就是 boot 分区。另一拨是官方 EVK 遗产，loadimage 与 loadfdt（92 行）用 fatload 认 FAT 分区，那是 NXP 原始配置的老习惯。咱们这块板的 boot 分区是 ext4，老路对不上新格式，真正要跑的是 ext4load 这一拨。

### 加载地址从哪来：两个地址，两个出处

fdt_addr 直接写在 AES 头文件第 57 行，值 0x83000000。loadaddr 在这份头文件里只被引用、没被定义，它的缺省值另有来路，咱们把来路追到底：

```bash
# 主机 ~/imx-forge
grep -n "loadaddr" third_party/uboot-mainline/include/env_default.h
grep -n "config SYS_LOAD_ADDR\|MX6ULL)" third_party/uboot-mainline/Kconfig | head -4
grep -n "SYS_LOAD_ADDR" out/uboot/.config /tmp/uboot-ref-aes/.config
```

```text
86:	"loadaddr="	__stringify(CONFIG_SYS_LOAD_ADDR)"\0"
619:config SYS_LOAD_ADDR
627:	default 0x82000000 if ARCH_MX6 && (MX6SL || MX6SLL  || MX6SX || MX6UL || MX6ULL)
628:	default 0x12000000 if ARCH_MX6 && !(MX6SL || MX6SLL  || MX6SX || MX6UL || MX6ULL)
out/uboot/.config:227:CONFIG_SYS_LOAD_ADDR=0x82000000
/tmp/uboot-ref-aes/.config:227:CONFIG_SYS_LOAD_ADDR=0x82000000
```

三层证据咱们咬在一起看。include/env_default.h 第 86 行把 loadaddr 的缺省值接在 CONFIG_SYS_LOAD_ADDR 上，顶层 Kconfig 第 627 行给 MX6ULL 这一代芯片定的缺省是 0x82000000，out/uboot 与 /tmp/uboot-ref-aes 两份 .config 的第 227 行都落成同一个数。板上串口里 echo ${loadaddr}，该回出来 0x82000000，内核就从这里进内存。

三个地址都住在同一条内存里，咱们把占位算一遍，免得互相踩到。内存起点 0x80000000 来自 third_party/uboot-mainline/arch/arm/include/asm/arch-mx6/imx-regs.h 第 114 行的 MMDC0_ARB_BASE_ADDR（MMDC 是 i.MX6ULL 的 DDR 控制器，这个常量是它映射出的内存起始地址），zImage 从 0x82000000 装进去，10369960 字节折成十六进制，算它住到哪、离设备树多远：

```bash
# 主机 ~/imx-forge
python3 -c "
size=10369960
print(hex(size), hex(0x82000000+size), hex(0x83000000-(0x82000000+size)))"
```

```text
0x9e3ba8 0x829e3ba8 0x61c458
```

zImage 的尾巴停在 0x829e3ba8，离 fdt_addr 的 0x83000000 还空出 0x61c458，约合 6.1 MiB。dtb 自己只有 35594 字节，住在 0x83000000 往后一小段，离第三个地址 initrd_addr=0x86800000（头文件第 43 行）也远。三个地址排成一列，大件小件互不越界，这个间距不是凑出来的，依据就是第一节那个 10369960。内核哪天换了版本体积涨上一截，咱们把这笔算术重算一遍再上电。

同一套数画成布局条是这样的，点图例行看每段的地址与来历：

<MemLayoutBar
  title="AES 板 DDR 占位（上电加载视角，窗口 0x80000000–0x88000000）"
  :view-start="0x80000000"
  :view-end="0x88000000"
  :segments="[
    { label: '空闲', start: 0x80000000, size: 0x2000000, soft: true, desc: '内存底部，加载视角暂无人居住' },
    { label: 'zImage', start: 0x82000000, size: 10369960, desc: '内核镜像 10369960（0x9E3BA8）字节，尾停在 0x829E3BA8' },
    { label: '空隙', start: 0x829e3ba8, size: 0x61c458, soft: true, desc: '约合 6.1 MiB 的安全间距' },
    { label: 'dtb', start: 0x83000000, size: 35594, desc: 'fdt_addr=0x83000000，设备树 35594 字节，窄段在条内只是一条线' },
    { label: '空闲', start: 0x83008b0a, size: 0x37f74f6, soft: true, desc: 'dtb 尾到 initrd 之间的空档' },
    { label: 'initrd', start: 0x86800000, size: 0x80000, desc: 'initrd_addr=0x86800000（头文件第 43 行），本路线未装载镜像，宽度是占位示意' },
    { label: 'U-Boot', start: 0x87800000, size: 0x100000, desc: '链接/加载地址 TEXT_BASE（04 章入口互证过），镜像 437248 字节约 430 KiB，示意画 1 MiB 对齐区；重定位后本体搬去 DDR 顶端，boot-chain 卷细讲' }
  ]"
  note="条子按真实比例画，窄段不足 1.6% 时画成一条竖线，数字以图例和详情面板为准。"
/>

咱们把 fdt_file 的角色摆正。头文件第 56 行给它缺省值 imx6ull-aes.dtb，它只喂两条路：EVK 遗产的 loadfdt（fatload mmc ${mmcdev}:${mmcpart} ${fdt_addr} ${fdt_file}）与网络启动的取文件命令。AES 专属的 loademmcfdt 与 loadsdfdt 不理它，文件名直接写死在命令里。想靠改 fdt_file 换设备树的朋友要看清，改完只有走 fatload 或网络那两条路才生效，跑专属脚本它纹丝不动。

## 三、bootz 的交接语法：三个位置参数，最后三件事

交接动作在现树下不自动发生。构建开关里写着答案，咱们把它抓出来，这三行笔者核过两遍才贴：

```bash
# 主机 ~/imx-forge
grep -n "BOOTCOMMAND\|CONFIG_CMD_BOOTZ" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
17:CONFIG_USE_BOOTCOMMAND=y
18:CONFIG_BOOTCOMMAND="echo Current do not autoboot"
25:CONFIG_CMD_BOOTZ=y
```

咱们把这三行念一遍：CONFIG_BOOTCOMMAND 的值把话说得很直白，Current do not autoboot，再配上 defconfig 第 16 行的 CONFIG_BOOTDELAY=-1，这块板现树上电后不倒计时、不自动引导，串口停在 => 提示符等人。第 25 行 CONFIG_CMD_BOOTZ=y，bootz 命令编进了固件，bootz 是把内核从内存推上路的命令，认 zImage 这种自解压格式。

手上两条专属脚本挑一条跑，eMMC 介质跑 run emmcbootaes，SD 介质跑 run sdbootaes。SD 这条的全文咱们从头文件里念出来，一步步干什么一目了然：

```text
"sdbootaes=echo Booting AES from SD ...; " \
	"run sdargs; " \
	"mmc dev ${sd_dev}; " \
	"run loadsdimage; " \
	"run loadsdfdt; " \
	"bootz ${loadaddr} - ${fdt_addr};\0" \
```

咱们把这句脚本从头念：头一句 echo 报家门，run sdargs 把 bootargs（传给内核的启动参数串）拼好，console 与 root 在那一步定（第 78 行写明 root=/dev/mmcblk0p2），mmc dev 0 选中 SD 卡，两个 run 完成装载，末句 bootz 完成交接。板端把它跑起来就是一句：

```bash
# 板端 /
run sdbootaes
```

bootz 后面跟三个位置参数，咱们逐个认。第一个 ${loadaddr} 是内核住址 0x82000000，第二节刚追完出处。第二个槽位写的是一个连字符 -，意思是这一位空着，不放 initrd。initrd 是装在内存里的临时根文件系统，内核起手可以先挂它再切真根。这棵树给 initrd 留了余地：头文件第 43 行备着 initrd_addr=0x86800000，defconfig 第 15 行 CONFIG_SUPPORT_RAW_INITRD=y 允许不打包的裸 initrd。哪天咱们做 initramfs 实验，把它读到 0x86800000，把地址填进中间那槽，连字符才退休。第三个 ${fdt_addr} 是设备树住址 0x83000000，内核靠它认外设，少了它，内核就是睁着眼也不认得自家外设。

### 交接前 U-Boot 干的三件事

bootz 不是把程序计数器一拨就跑，交棒前它替内核办完三件事。头一件修补 FDT。FDT 是设备树在内存里的扁平形态，boot/image-fdt.c 里 fdt_chosen 把 bootargs 塞进设备树的 /chosen 节点（内核从这里领启动参数），arch_fixup_fdt 由 ARM 侧接手，arch/arm/lib/bootm-fdt.c 把 U-Boot 自己探测到的内存容量用 fdt_fixup_memory_banks 重写进 memory 节点，第一节 dtb 里那个 512 MiB 的声明，到这一步让位给实测值。第二件清场。boot_jump_linux 末尾调 cleanup_before_linux，arch/arm/cpu/armv7/cpu.c 的实现里 disable_interrupts 关中断，dcache_disable 把数据缓存冲净连同 MMU 一起关掉，icache_disable 关指令缓存，省得内核接手时上一棒的现场还是热的。第三件跳转。arch/arm/lib/bootm.c 里参数按 ARM 的启动约定摆好，r2 寄存器装设备树地址，最后一行 C 代码是 kernel_entry(0, machid, r2)，第一个 0 对应约定里必须为零的 r0，machid 是板子编号。三件事咱们各按一处源码证据：

```bash
# 主机 ~/imx-forge
grep -n "fdt_chosen\|arch_fixup_fdt" third_party/uboot-mainline/boot/image-fdt.c | head -3
grep -n "cleanup_before_linux\|kernel_entry(0, machid, r2)" third_party/uboot-mainline/arch/arm/lib/bootm.c
```

```text
624:__weak int arch_fixup_fdt(void *blob)
655:	if (fdt_chosen(blob) < 0) {
659:	if (arch_fixup_fdt(blob) < 0) {
269:	cleanup_before_linux();
331:	cleanup_before_linux();
357:		kernel_entry(0, machid, r2);
414:	cleanup_before_linux();
```

image-fdt.c 的 655 行塞 bootargs，659 行调修内存的钩子，624 行是它的缺省空实现，真身由 ARM 侧 bootm-fdt.c 提供。bootm.c 一把抓回三条 cleanup_before_linux，269 行那条住在 arm64 的跳转里，咱们认 331 行那条，它才是这块 32 位板的，414 行属于别的启动路径，机制同源。331 行清场，357 行 kernel_entry(0, machid, r2)，C 语言到此为止，下一行就是内核的第一条指令。修补、清场、跳转三步往深里还有更多机制，扩展卷 boot-chain 已经把这条交接路线排进篇目，排到讲交棒内核那一跳的篇目时，拿今天这三个参数与三步清场逐项展开，本篇停在能跟串口对上号的深度。

## 四、交接成功的标志：Starting kernel 之后安静一阵

Starting kernel ... 是 U-Boot 的最后一句。这句不是玄学，咱们到源码里对原文：

```bash
# 主机 ~/imx-forge
grep -n -A2 "Starting kernel" third_party/uboot-mainline/boot/bootm.c
```

```text
1247:	printf("\nStarting kernel ...%s\n\n",
1248-	       (flag & BOOTM_STATE_OS_FAKE_GO) ?
1249-	       " (fake run for tracing)" : "");
```

咱们把这句对到 boot/bootm.c 第 1247 行，bootm_final 函数在跳转前把它打印出来，连头带尾各空一行。这句出了，装载与修补全部办完，U-Boot 的话到此说尽。

之后的安静是正常现象，咱们把道理讲清。U-Boot 退场，串口上再往外出字的就该是内核，可内核的第一行日志要等它自己的串口驱动起来才发得出来。驱动什么时候起，参数在交接那一步就定了。bootargs 里的 console=ttymxc0,115200 告诉内核往哪个串口说、用什么速度说，ttymxc0 对应 UART1，出处在这两处：

```bash
# 主机 ~/imx-forge
grep -n "console=\|baudrate" third_party/uboot-mainline/include/configs/mx6ull_aes_emmc.h | head -3
grep -n "CONFIG_BAUDRATE" /tmp/uboot-ref-aes/.config
```

```text
30:	"mfgtool_args=setenv bootargs console=${console},${baudrate} " \
53:	"console=ttymxc0\0" \
65:	"mmcargs=setenv bootargs console=${console},${baudrate} " \
1496:CONFIG_BAUDRATE=115200
```

这几处出处咱们都核过。第 53 行定 console 为 ttymxc0，波特率 115200 来自 .config 第 1496 行的 CONFIG_BAUDRATE，头文件第 17 行 CFG_MXC_UART_BASE 挂的就是 UART1_BASE，U-Boot 自己的横幅也从它出，两边用的是同一个口。内核的低级打印没配全时，这段安静还会拉长，解压内核、初始化内存都在黑着灯干。

交接成没成，咱们认两样。串口里冒出内核日志，起头一般带着 Linux version 与编译时间戳，内核活了。冒不出日志却报出一段 panic 栈，同样算内核活了，栈是内核亲笔，只是它下一棒摔了，最常见的摔法是根文件系统没跟上，root= 指的分区上没有像样的根，串口里会挂着 VFS: Unable to mount root fs 一类的话。run sdargs 与 run emmcargs 拼出的 root 参数不一样，SD 是 /dev/mmcblk0p2，eMMC 是 /dev/mmcblk1p2，介质选错脚本，根设备号就指错分区。

到这一步，Boot ROM、U-Boot、内核三段链路咱们全走通了。Boot ROM 在介质固定偏移找头、拉起内存那一段，扩展卷 [上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像](./boot-chain/01_boot_rom_boot_media.md) 收了尾，它末尾那根线停在“U-Boot 接手”，往后那一跳今天补上。链上剩 rootfs 一段，内核日志出来、挂载完根、init 起来，这根线才算全亮。

## 五、起不来的排查：现象、根因、解法

交接卡住时，咱们按现象归三路。表里的 earlycon 是内核在正式串口驱动就位前临时顶班的低级打印通道，配了它，安静期会短很多。先对号，再动手：

| 现象 | 根因 | 解法 |
|---|---|---|
| Starting kernel 之后串口一直无声 | 内核侧控制台没就绪：bootargs 的 console 与实际串口不符、内核没编对应串口驱动或 earlycon 没配。另一种是加载布局冲突：fdt_addr 被挪进 zImage 占用的区间，两个文件在内存里重叠，后读入的把先读入的盖掉，内核或设备树总有一份是残缺的 | 核 bootargs 的 console=ttymxc0 与内核配置里的串口、earlycon 开关。按第二节的算术把加载地址拉开距离，挪开重试 |
| bootz 当场回错，字样是 zimage: Bad magic! 或 Bad Magic Number | loadaddr（或中间槽）里没有 bootz 期望的字节：ext4load 读失败没人看回显、文件名或分区号打错、加载地址被改过，魔数对不上就回错。魔数是文件开头约定的一串字节，bootz 靠它认出 zImage | 看 ext4load 回显的字节数是否与主机侧文件大小一致，ext4ls mmc 0:1 / 核分区里的真名，printenv 核地址没被改，再重跑 |
| 内核接手后外设不对劲或再度无声 | 设备树不匹配：fdt_file 指错文件。AES 专属脚本把 /imx6ull-aes.dtb 写死在命令里，走 loadfdt（fatload）或网络启动的路径才会被 fdt_file 带偏，指到别的板的 dtb 上，串口与引脚的硬件描述全错 | ext4ls 核对 boot 分区里 dtb 的真名，setenv fdt_file imx6ull-aes.dtb，或改用写死文件名的专属脚本 |

第二路的两个错字，咱们在源码里各领一个。zimage: Bad magic! 来自 arch/arm/lib/zimage.c，bootz 进场头一件事就是到加载地址认魔数，0x016f2818 这串对不上当场回错：

```bash
# 主机 ~/imx-forge
sed -n '11,32p' third_party/uboot-mainline/arch/arm/lib/zimage.c
```

```text
#define	LINUX_ARM_ZIMAGE_MAGIC	0x016f2818
#define	BAREBOX_IMAGE_MAGIC	0x00786f62

struct arm_z_header {
	uint32_t	code[9];
	uint32_t	zi_magic;
	uint32_t	zi_start;
	uint32_t	zi_end;
} __attribute__ ((__packed__));

int bootz_setup(ulong image, ulong *start, ulong *end)
{
	struct arm_z_header *zi = (struct arm_z_header *)image;

	if (zi->zi_magic != LINUX_ARM_ZIMAGE_MAGIC &&
	    zi->zi_magic != BAREBOX_IMAGE_MAGIC) {
		if (!IS_ENABLED(CONFIG_XPL_BUILD))
			puts("zimage: Bad magic!\n");
		return 1;
	}

	*start = zi->zi_start;
```

Bad Magic Number 则是另一处检查报出来的：boot/image-board.c 第 50 行的 image_get_ramdisk 在验 initrd 槽里的旧格式镜像头，验不过就报这句。两处回错根因同路，都是地址里的字节不是命令期望的那份，顺着加载命令的回显往回查就行。排查时咱们手里就攥着三样核对物：主机侧的文件字节数、串口里 ext4load 报的读入字节、printenv 里的地址，三者对上，交接这关才轮得到谈成败。

## 继续学习

- [上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像](./boot-chain/01_boot_rom_boot_media.md)：链路前半段，IVT 头 64 字节逐项读过，它末尾那根线把“U-Boot 接手”往后一笔带过，本篇补的正是这一跳。
- [编译、外挂模块与 QEMU 首启验收](../kernel/08_dts_build_boot.md)：zImage 与 dtb 的生产现场，本篇装进存储的就是它出炉的那两个文件。
- [Rootfs 概述](../rootfs/01_rootfs_overview.md)：内核挂载的那个根从哪来，BusyBox 方案的取舍在那边。
- [串口日志阅读路线](../debug/03_serial_log_reading.md)：Starting kernel 之后的串口记录怎么分段读，panic 与 Oops 的判读归它。
