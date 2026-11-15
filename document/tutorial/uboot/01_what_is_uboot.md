---
title: 从0开始认识 U-Boot：一块 i.MX6ULL 上电后的事
---

# 从0开始认识 U-Boot：一块 i.MX6ULL 上电后的事

这里是笔者！实际上，笔者本来一直想的是直接冲到 UBoot 的章节，直奔主题聊一聊UBoot的移植，但是我突然想到，大部分的朋友，要是玩这块板子的，都是新手，你说，让一个新手突然之间移植一个偌大的C项目，而且框框说一大堆听不懂的东西，纯粹欺负人，是不是？

所以，从这里开始，我们会稍微铺垫一下 UBoot 这个东西。主要是起码弄清楚这个问题：

> 一块 i.MX6ULL 从按下电源到 Linux 起来之间发生了什么，从而回答你移植这个东西干什么？

## 一、上电之后发生了什么：从电源键到 shell 的四级链条

实际上，不管您是启动PC机，还是你手上的单片机，还是，嗯，就是安静的放在您桌子上的imx6ull，当我们下定决心，祈祷这次启动千万不要挂的时候。我们的第一个动作都是按下电源。

多朴实无华。

对于ARM，我们首先跑起来的代码并不在烧好的卡上。。。实际上是芯片自己内部出场的时候，自己在片子里的一段只读代码，它的名字叫 BootROM。CPU 复位之后执行的第一条指令就从它出，它的全部本事是把启动介质挑出来：读一下 boot 引脚的电平，或者读熔丝（eFuse）里烧好的值，从 eMMC、SD 卡、SPI Flash 这些候选里选定要启动的介质，再把选定介质头部的镜像读进片内 RAM。

片内 RAM 是芯片里一小块掉电即失的内存（这并不意外，毕竟任何一个具备计算机硬件常识的朋友都知道 RAM 是掉电失去信息的，你PC机器上的内存芯片也是），打开我们的 UBoot 树里能查到它的基址：

::: code-loc uboot-mainline arch/arm/include/asm/arch-mx6/imx-regs.h:67
```c
#define IRAM_BASE_ADDR			0x00900000
```
:::

BootROM 在这一级干的活是三件。挑出启动介质、把镜像的开头读进片内 RAM、再把控制权交出去，让下一个程序接力启动。

片内 RAM 装不下内核，那内核将来住哪？住在焊在板子上的另一颗内存里，它叫 DDR。这个名字的全称是 DDR SDRAM，直译过来叫双倍数据率同步动态随机存储器。名字长，一个词一个词看就懂了：SDRAM 是同步动态随机存储器，读写动作跟着统一的时钟节拍走。前头的 DDR 三个字母是 Double Data Rate 的缩写，说的是时钟的上升沿和下降沿各传一次数据，同样的时钟频率下带宽翻倍。你 PC 里插的内存条就是这一类的后代，只不过板子上把它直接焊在板面，这块板焊的还是第三代的 DDR3，容量 512 MiB，片内 RAM 只有 128 KiB，差着四千倍。

DDR 为什么上电那会儿帮不上忙？根子在这两种内存的存法不一样。片内的 128 KiB 是 SRAM，一个存储位用几个晶体管搭成触发器，通着电状态就自己保持，BootROM 拿过来直接用。DDR 走的是 DRAM 的路子，一个存储位靠一颗小电容存电荷，电荷会漏，得隔一小段时间刷新一遍，刷新的节拍和读写的时序全归旁边的存储控制器管，控制器还得按板上焊的颗粒型号来配。芯片刚上电的时候控制器没配、颗粒没初始化，它自然一个字节都不认。谁照着清单把控制器配好，它才头一回认得读写。这份清单叫 DCD，下一节咱们就挨个看它。

咱们要知道 BootROM 怎么认镜像：靠的是一个特定的头，头里最要紧的两样东西，咱们挨个看。咱们要认的头一样是 IVT，它的全名是 Image Vector Table，中文的名字就是镜像向量表，负责告诉 BootROM 入口地址在哪、镜像的各段怎么摆。咱们要认的另一样是 DCD，它的全名是 Device Configuration Data，中文的名字就是设备配置数据，它的内容是一份寄存器写入清单，BootROM 在跳进镜像之前照着清单把值一条条写进外设的寄存器里。咱们最关心的那件事就发生在这里：DDR 是等 DCD 执行完才活过来的。清单里的大头条目都在配 DDR 控制器，这一批值写完了，外面那颗内存颗粒才头一回真正能用了。头读出来了，BootROM 按头里的指示把镜像搬到它的加载地址（这块板是 DDR 里的 0x87800000），NXP i.MX6ULL 的参考手册把这一步叫校验并加载，咱们要认的只有它的产出：CPU 的下一跳落进镜像的入口。

那 BootROM 为什么不直接把 Linux 内核拉起来？它没这个本事。ROM 里的代码出厂就定了，改不了，片内那一点 RAM 也是放不下内核的。内核想活起来的话，DDR、存储驱动、串口这几样是缺不了的，这些活需要一个可编程的中间层来干，而这样的中间层就是 U-Boot。它把外设初始化到命令行能用的地步，咱们看它再从存储里把内核镜像和设备树读进内存，把入口地址和启动参数交代得清清楚楚，然后跳进 Linux 的入口。等 rootfs 挂上了、shell 起来了，咱们才见到熟悉的登录提示符。

咱们把四级链条连起来看：

<StepFlow>
  <StepItem icon="⚡" title="BootROM" description="按 boot 引脚或熔丝挑启动介质" />
  <StepItem icon="📋" title="校验并加载镜像" description="IVT 头加 DCD 清单，DDR 在这一步活过来" />
  <StepItem icon="🛠️" title="U-Boot" description="外设到命令行可用" />
  <StepItem icon="🐧" title="交棒 Linux" description="装载内核与设备树" />
</StepFlow>

第一节就是全卷的地图。咱们讲到链路为止，IVT 头里每个字段的偏移、DCD 条目的编码格式、镜像在卡上固定留出的 1KB 偏移，这些逐字节的问题咱们留给扩展卷 boot-chain，那一卷按四段走完同样的链路：头一段讲 BootROM 与镜像格式，第二段讲片内 RAM 里的早期初始化，第三段讲重定位与后期的搬家，最后一段讲交棒内核的那一跳。

## 二、U-Boot 在链条里的两段工作

那好，现在我们说 BootROM 处理好自己芯片相关的事情，就要准备启动起来跑程序了，实际上，这就是UBoot，哈哈。

UBoot 在启动的过程中，是将芯片从CPU自己可以跑起来的状态，带到可以引导操作系统的地方（哦，往往是Linux），您要是玩过人家厂商烧好的片子会发现欸到达uboot的终点是可以烧录命令行的。对的，就是这样。

当然，到这里没完事，我们一般还要求把内核和Rootfs搞出来，以及设备树（对于arm），一起交给UBoot，告诉他从这里启动起来。

下面，我们就来稍微详细的，聊一聊uboot到底咋搞的。

### 第一段：把 DDR、时钟、存储、串口带到可用

可用两个字是有分量的。U-Boot 最终要住的地方是 DDR，可它刚被加载的时候 DDR 未必活着，所以镜像头里的 DCD 得把 DDR 控制器配好（上一节说过这件事），U-Boot 一进来才有地方安身。接下来时钟树、串口控制器、eMMC 控制器的初始化一路做下去，串口上开始打出日志来了。这一段活干完了，咱们就能敲命令、能读卡、能看内存，板子在咱们手里才算真的活了。

咱们在 defconfig 里搜不到 SPL（二级加载器，U-Boot 拆成两段跑时驻留在片内 RAM 里的第一小段）的配置项，AES 板和参考用的 NXP 官方评估板 EVK（Evaluation Kit）都一样，所以这套镜像走的是单镜像路线：BootROM 把镜像头（IVT 与 DCD）读进片内 RAM，靠的是 DCD 把 DDR 带起来，再把 u-boot.imx 的镜像体拷进 DDR 的加载地址 0x87800000，约 600KB（613888 字节）的体量片内那 128KB 是装不下的，咱们看到 U-Boot 直接在 DDR 里开跑，随后把自己搬到 DDR 的高处去住（这个搬家动作叫重定位，扩展卷的第三段细讲）。DDR 的参数写在补丁新加的 `board/nxp/mx6ull_aes_emmc/imximage.cfg` 里，文件的开头声明镜像版本与启动介质，后面跟着的是 61 条 DATA 行，其中的一条包在 CONFIG_IMX_OPTEE 条件里，当前的 defconfig 没开 OPTEE，实际编进 DCD 的就是 60 条，一条 DATA 行对应的就是一次寄存器写入、交由 BootROM 执行：

```text
IMAGE_VERSION 2

#ifdef CONFIG_QSPI_BOOT
BOOT_FROM	qspi
#elif defined(CONFIG_NOR_BOOT)
BOOT_FROM	nor
#else
BOOT_FROM	sd
#endif
```

这里的版本是 2，介质在条件编译里兜底到了 sd，跟这块板从 eMMC 启动的事实对得上。树里的 defconfig 把 CONFIG_BOOTDELAY 设成了 -1，启动的末尾不倒计时，日志打完了就直接进命令行，提示符这就交到咱们手里。倒计时按任意键拦截的现场，要等 CONFIG_BOOTDELAY 的值调回正值才出现，咱们要是想在第 5 站验一验这个现场，把它的值改回来就行。

### 第二段：读环境变量，装内核与设备树，清理现场

命令行可用了之后，U-Boot 的活就换成搬运。它干的下一件事是读环境变量，启动介质、内核文件名、加载地址、传给内核的参数全在变量里。咱们在 defconfig 里能翻到 `CONFIG_ENV_IS_IN_MMC=y` 与 `CONFIG_ENV_MMC_DEVICE_INDEX=1` 两行，环境变量存在 eMMC 上这件事就是它们写明的，编号 1 对应的正是 usdhc2，也就是挂 eMMC 的那个控制器。

然后是把内核镜像和设备树装进内存的活，再把启动参数的位置告诉内核。设备树此刻只需要咱们知道一件事：它是描述板子上有什么硬件的一份数据，内核认外设靠的也是它，第 8 站（AES 设备树）咱们拿 AES 的设备树逐个节点过。板级代码里有一行专门干这件事：`board/nxp/mx6ull_aes_emmc/mx6ull_aes_emmc.c` 的 board_init() 里写着 `gd->bd->bi_boot_params = PHYS_SDRAM + 0x100`。启动参数块放在 DDR 起始地址往后 0x100 的地方。启动的顺序本身写成环境变量脚本，参考 EVK 的 defconfig 里那段 CONFIG_BOOTCOMMAND，咱们一眼能看明白结构，从哪个设备、按什么顺序、加载什么、启动什么全在其中：

```text
CONFIG_BOOTCOMMAND="run findfdt;mmc dev ${mmcdev}; if mmc rescan; then if run loadbootscript; then run bootscript; else if run loadimage; then run mmcboot; else run netboot; fi; fi; else run netboot; fi"
```

这段脚本咱们到第 11 站（环境变量与 bootcmd）再逐句过。交接之前还有清理现场的收尾活，U-Boot 把自己开起来的中断和缓存收掉，把机器状态交代干净了再跳内核，不给 Linux 留悬着的东西。两段活各自的验收时刻，就是正文的第 5 站和第 12 站，完整的路线表在第四节给咱们备好了。

## 三、本卷的源码口径：官方 mainline v2026.10 单轨

口径这件事是咱们要在第一篇交代清楚的，后面每一站的命令和输出才有统一的参照。本卷只用官方 mainline 的 U-Boot，版本停在 v2026.10 这个正式的发布标签上，NXP 的 uboot-imx 分支不采用。这不是笔者的口头偏好，笔者在本机把下面的命令跑了一遍、输出原样贴出，朋友们可以逐条复跑。

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline log --oneline -1
git -C third_party/uboot-mainline remote get-url origin
```

```text
55084065 Prepare v2026.10
https://github.com/u-boot/u-boot.git
```

头一行的输出说明 HEAD 停在 55084065 这个提交上，提交的标题是 Prepare v2026.10。远端地址指向 github.com/u-boot/u-boot，也就是官方的仓库本身。HEAD 是否正好等于 v2026.10 标签所指？咱们再核一步：

```bash
# 主机 ~/imx-forge/third_party/uboot-mainline
git rev-parse v2026.10^{commit}
git log -1 --format='%H %s %ad' --date=short
```

```text
5508406582f6f7120dce0c4b3059819a41788db2
5508406582f6f7120dce0c4b3059819a41788db2 Prepare v2026.10 2026-10-05
```

两条输出是能对上的，HEAD 就是 v2026.10 标签所指的那个提交，提交的日期是 2026-10-05。咱们就停在发布标签上，不追 master 的滚动头。v2026.10 这个名字本身就是发版的日期，U-Boot 从 2008 年起就是按年月发版的，三个月的时间出一个正式版，认版本是不用查表的。

::: warning 追 master 的代价
为什么不追 master呢？

额，其实，只要你是开发的，就应该知道 Master 分支的代码不意味着可用。大家每一次迭代，都会开发一段时间，把代码向前推进一个部分，然后，拉一个Release分支，将部分修复和必须跟版的Features合入到Release分支上。对于 U-Boot 的发布后约 21 天是合并窗口，窗口里的 master 随时收进还没经过完整测试的补丁。一般都是到完全稳定了，OK，这个分支停下，作为一个发布分支不再前进。

所以如果我们采用了Master分支。后果是教程里每条命令的输出随时间漂移，报错对不上确定的版本，排查也就没了参照。咱们停在发布标签上，教程、源码、输出三样在咱们手里就永远对得上号。
:::

## 四、咱们的板子与十四站路线

### AES 板：正点原子阿尔法（ALPHA）i.MX6ULL 原型改出来的那块板

本卷对着的硬件是 AES 板：芯片用的 i.MX6ULL，封装用的 14x14，原型是正点原子阿尔法（ALPHA）i.MX6ULL 的开发板。AES 三个字母的来历写在设备树里：`arch/arm/dts/imx6ull-aes.dts` 的 model 字符串写的就是 `"Awesome Embedded Studio IMX6ULL (i.mx NXP)"`。原型脉络也在文件里留了痕迹，同一份 dts 开头的注释写明 usdhc2 这一段来自 `arch/arm/dts/imx6ull-14x14-evk-emmc.dts`、简化过一层 include 层级，而正点原子的板卡配置又是照着 NXP 的 EVK 参考设计改的，咱们把这三层关系串起来，这块板的出身就一目了然。板子的家底咱们列成一张表，表里的每一格都能回源码对到：

| 部件 | 这块板上的配置 | 证据在哪 |
|------|------|------|
| 处理器 | i.MX6ULL，14x14 封装 | `arch/arm/mach-imx/mx6/Kconfig` 里 `depends on MX6ULL` |
| 内存 | 512 MiB DDR3 | `imx6ull-aes.dtsi` 的 memory 节点，0x80000000 起始，长 0x20000000 |
| 存储 | eMMC 挂在 usdhc2，8 位线 | `imx6ull-aes.dts` 的 usdhc2 用 8bit 系列 pinctrl |
| 网络 | 双 FEC（i.MX 片上的以太网控制器），各配一路 RMII PHY（挂在 RMII 接口上的以太网物理层芯片），复位脚在 GPIO5 IO7 与 IO8 | `imx6ull-aes.dtsi` 的 fec1、fec2 节点 |
| PHY | Micrel 驱动，KSZ8081 在上游驱动名单里 | defconfig 选 `CONFIG_PHY_MICREL_KSZ8XXX`，`drivers/net/phy/micrel_ksz8xxx.c` 里有 ksz8081_config |
| 显示 | eLCDIF（i.MX 片上的 LCD 控制器）接口，时序按 1024x600、24 位色、51.2MHz 像素时钟 | `imx6ull-aes.dtsi` 的 display0 与 timing0 |
| 环境 | 环境变量与 fastboot 烧录都指向 eMMC | defconfig 的 `CONFIG_ENV_MMC_DEVICE_INDEX=1`、`CONFIG_FASTBOOT_FLASH_MMC_DEV=1` |

内存这一项的原文，咱们从设备树里贴出来：

```dts
memory@80000000 {
	device_type = "memory";
	reg = <0x80000000 0x20000000>;
};
```

0x20000000 对应的就是 512 MiB。两路 FEC 共享一条 MDIO 总线（MDIO 是 CPU 读写 PHY 寄存器用的两线管理总线）这件事，defconfig 里有一行注释专门提醒过了（Both FECs share the MDIO bus）。屏幕的时序在树里是 1024x600，咱们手头的面板标称多少、以实物为准。

### 正文十四站，一站一句话

正文的十四站按顺序走，咱们一站配一句话过一遍：

| 站 | 干的事 | 离站时手里有什么 |
|----|------|------|
| 01 全景 | 本篇，链条、口径、路线 | 一张地图 |
| 02 环境源码 | 装依赖，取 v2026.10 源码 | 一棵可编译的源码树 |
| 03 首次编译 | defconfig 加 make | 第一枚 u-boot.imx |
| 04 产物验证与烧录 | 核对产物格式，烧进卡 | 一枚板上起得来的镜像 |
| 05 串口进命令行 | 接串口，拿到提示符 | 一个能敲命令的提示符 |
| 06 参考配置逐行对账 | 拿 EVK defconfig 对照讲解 | 一份看得懂的配置底版 |
| 07 最小板卡适配 | 改名换姓，登记进构建系统 | 认得咱们板子的构建树 |
| 08 AES 设备树 | 从 EVK 的 dts 出发改外设 | imx6ull-aes 两份设备树 |
| 09 DDR 与镜像头 | imximage.cfg 对着颗粒调 | 一组对得上硬件的内存参数 |
| 10 eMMC 验收 | eMMC 读写与环境保存跑通 | 存储路径确认可用 |
| 11 环境变量与 bootcmd | bootargs 与启动脚本逐句过 | 一套写得明的启动脚本 |
| 12 启动 Linux | 装内核与设备树，交棒 | 内核日志滚上串口 |
| 13 tftp 网络启动 | 从网口取镜像 | 一条不依赖烧卡的迭代路 |
| 14 调试速查 | 现象、根因、排查入口 | 一份速查手册 |

站号以咱们表里列的为准，卷目录的同步，咱们随后跟上。

站与站之间是有依赖的，顺序咱们别乱调，咱们要是镜像没烧进去就谈调试、设备树没就位就谈环境变量，那都是白费的。十四站如今全部成文，从下一站 [源码与环境准备](./02_uboot_compile.md) 起逐站走就行。

### 扩展卷 boot-chain

扩展卷 boot-chain 承接第一节的地图，咱们分四段走。BootROM 与镜像格式讲的，是 IVT 头与 DCD 的逐字节布局。早期初始化讲的是片内 RAM 里的第一段执行。重定位与后期讲的是 U-Boot 怎么把自己搬到 DDR 高处。交棒内核讲的是启动参数的内存约定与跳转的那一瞬间。这一卷的文件还没落成，成文之前第一节就是咱们手里唯一的索引。

手上暂时没有板子的朋友，咱们指条路：emu 卷给了仿真出路，QEMU 替身方案从 [为什么要给开发板找替身](../emu/01_why_emulation.md) 读起，正文站点的大部分命令都能在仿真环境里对练。

## 五、开始之前备齐三件事

头一件要备的是交叉编译工具链。本卷统一用的是 arm-none-linux-gnueabihf- 这套 ARM 硬浮点工具链，装法写在了 [从 0 开始：安装交叉编译工具链](../start/01_start_from_toolchain.md) 里，装完了就拿 `arm-none-linux-gnueabihf-gcc --version` 核一下，实跑输出在下一篇第二节有份，心里就有底了。

另一件要备的是串口线。板子上的调试串口是板载 USB 转串口，一根 USB 线插到板子的调试口就行，接口的清单见 [板子硬件接口速查表](../start/03_hardware_quick_reference.md)，minicom 的安装与参数见 [串口工具使用（minicom）](../start/04_serial_tools_minicom.md)。串口要是不通的话，咱们连第 5 站都进不去，这件是最不能省的。

还有一件要备的是存储介质。咱们板子默认从 usdhc2 上的 eMMC 启动，环境变量与 fastboot 烧录在 defconfig 里的指向都是它，SD 卡是备用的启动路、也是烧写的跳板，卡或 eMMC 咱们至少得备一样，这是咱们的底线。两处的指向咱们到第 10 站验收时还会再核对，硬件的清单在速查表那一篇里。

三样备齐了，下一站（编译与配置）是从装依赖和取源码开始的，等它走完了，咱们手里就有第一枚能烧进卡里的 u-boot.imx。

## 继续学习

- [源码与环境准备](./02_uboot_compile.md)：下一站，装依赖、取源码、锁版本
- [第一次编译官方参考板](./03_first_build.md)：从 distclean 到四个产物
- [产物验证与烧录](./04_verify_and_flash.md)：核对产物格式，烧进卡
- [串口验收](./05_serial_acceptance.md)：拿到提示符，第一个里程碑
- [净源码里没有咱们的板卡](./06_aes_vs_evk_diff.md)：EVK 与 AES 的逐行对账
- [七步造出咱们的板卡](./07_board_porting.md)：Kconfig 系统与第一次板卡适配
- [设备树](./08_device_tree_aes.md)：AES 设备树的来历
- [DDR 初始化与镜像头](./09_ddr_imxheader.md)：imximage.cfg 里写了什么
- [存储验收](./10_emmc_acceptance.md)：eMMC 读写与环境保存
- [环境变量与 bootcmd](./11_env_bootcmd.md)：启动脚本逐句过
- [启动 Linux](./12_boot_linux.md)：装内核与设备树，交棒
- [换条路：tftp 网络加载](./13_tftp_netboot.md)：从网口取镜像的迭代路
- [调试命令速查](./14_debug_reference.md)：命令行工具箱
- [为什么要给开发板找替身](../emu/01_why_emulation.md)：没有板子时的仿真出路
- [一切的源头：如何开始本项目的学习](../start/00_roadmap.md)：全局路线再对一遍
