---
title: 环境变量与 bootcmd：U-Boot 的行为由谁来定
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 环境变量与 bootcmd：U-Boot 的行为由谁来定

> 本篇解决一个悬了两章的问题：U-Boot 上电之后按谁的意思干活。答案是命令行里 printenv 列出的那批环境变量，本篇带咱们把它们是什么、存在哪、怎么改、坏了怎么救一次讲清楚。概念篇把 EVK 那行 CONFIG_BOOTCOMMAND 原样贴过，说好了到这一站逐句过。环境扇区挪去 4 MiB 的避让推理在对账篇（06 章）里交底，留的“逐句讲解留给后面”那句，咱们这里接上。bootcmd 的尽头是 bootz 这类引导命令，内核与设备树怎么装进板子完成交接，归下一篇。

## 一、环境变量是什么、住哪

咱们先把名字对上。U-Boot 起到提示符之后敲 printenv，串口刷出一整页 name=value，那一页就是环境变量的全部家当。它的本体是一个键值对集合，值既可以是普通字符串（console=ttymxc0），也可以是用分号串起来的命令脚本（mmcargs=setenv bootargs ...），脚本里的分号是命令分隔符，CONFIG_HUSH_PARSER=y（AES defconfig 第 23 行）给 U-Boot 装上的 HUSH shell 认它，run 命令负责把整段脚本按顺序执行。改一行变量就改一段行为，不用重编镜像，这套机制的价值全在这一句里。

变量集合在内存里好理解，断电之后它住在哪才是正题。咱们拿 defconfig 自己作证，AES 这条的输出贴出来：

```bash
# 主机 ~/imx-forge
grep -n "BOOTDELAY\|BOOTCOMMAND\|ENV_SIZE\|ENV_OFFSET\|ENV_IS_IN_MMC\|MMC_DEVICE_INDEX\|CONFIG_ENV_OVERWRITE" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
6:CONFIG_ENV_SIZE=0x2000
8:CONFIG_ENV_OFFSET=0x400000
16:CONFIG_BOOTDELAY=-1
17:CONFIG_USE_BOOTCOMMAND=y
18:CONFIG_BOOTCOMMAND="echo Current do not autoboot"
45:CONFIG_ENV_OVERWRITE=y
46:CONFIG_ENV_IS_IN_MMC=y
48:CONFIG_ENV_MMC_DEVICE_INDEX=1
```

咱们把第 46 行与第 48 行连起来读，再补一条机制：ENV 器件跟着启动器件走，从 SD 卡启动时 ENV 在 0 号卡上，从 eMMC 启动才落编号 1，也就是挂 eMMC 的 usdhc2。第 48 行的 CONFIG_ENV_MMC_DEVICE_INDEX=1 是兜底值，只有不从 SD/MMC 启动时才轮到它：soc.c 第 530 行的 mmc_get_env_dev() 在 SD/MMC 启动时问板级 board_mmc_get_env_dev，AES 板级文件第 39 行一行返回启动器件号。01 章交代过咱们板子默认从 usdhc2 的 eMMC 启动，本篇按这条默认路线说话。落点与容量由另外两行给，CONFIG_ENV_OFFSET=0x400000 是起始字节，折合 4 MiB，CONFIG_ENV_SIZE=0x2000 是窗口大小，8192 字节，折合 8 KB。这片 8 KB 不全是变量，头 4 个字节是整段数据区的 CRC32 校验值，include/env_internal.h 里 env_t 结构的注释原话写着 CRC32 over data bytes，剩下的才是变量本体。printenv 能列出什么，取决于这 8 KB 里存了什么。

0x400000 这个数不是随手填的，咱们在这里回收 06 章的避让推理。EVK 的 ENV_OFFSET 是 0xC0000，折合 768 KiB，AES 参考产物的 u-boot-dtb.imx 有 1702912 字节（09 章数过），折合 1663 KiB，768 KiB 这个落点整个落在镜像身体里。AES 还把内嵌 Logo 换成了 1152054 字节的大图（06 章贴过官方版 15538 字节与工作区 1152054 字节两个数），上面数的 1663 KiB 本身就是带着这张大图的数字，往后再换图加料只会长不会短。saveenv 要是往 768 KiB 处写，写下的位置恰好是 U-Boot 镜像的某一段，下次启动读回的环境是烂的，镜像自己也被改坏。挪到 4 MiB，镜像再长也不碰 ENV 区。8 KB 这个窗口同时是另一条边界，变量塞不塞得下的问题第四节细说。0x400000 在实际板子上的落位怎么核，10 章第五节立了清单，实板到手照那份清单现场补核。

笔者把第 45 行单独点名。U-Boot 给个别变量默认上了写保护，include/env_flags.h 写得直白：不带这个开关时，serial# 与 ethaddr 这类变量的访问标记是 o（writeonce，只许写一次），带上之后 ethaddr 这类换成 a（any，随便改），serial# 的标记整段移除。标记里两个字母各管一样，头一个字母是类型（m 是 macaddr，s 是字符串），第二个才是访问权限。AES 的头文件预设了 eth0addr、eth1addr、ethaddr 三个 MAC（第 40 到 42 行），调试中要换地址，能 saveenv 改得动就靠这一行放行。

## 二、启动行为的三层控制

变量集合适配谁、控制什么？咱们分三层认：bootdelay 管上电后倒计时几秒，bootcmd 是倒计时结束后自动执行的那串命令，bootargs 是交给内核的启动参数，本篇认到它由哪个变量设置，逐参数的展开归下一篇。三层全在环境变量里，这就是本章标题里“行为由谁来定”的定语。

### bootdelay：倒计时与拦截窗口

倒计时的裁决逻辑住在 common/autoboot.c 的 autoboot_command()，条件咱们原样贴出来：

```c
if (s && (stored_bootdelay == -2 ||
	 (stored_bootdelay != -1 && !abortboot(stored_bootdelay)))) {
```

这一行把三种取值的后果全交代了。bootdelay 是 -2，条件短路成立，bootcmd 立刻执行，连按键窗口都不开。是 -1，两个分支都不成立，bootcmd 压根不跑，U-Boot 停在提示符等人。是 0 或正数，abortboot() 开出倒计时窗口，串口打 Hit any key to stop autoboot，窗口里敲了键停在提示符，没敲就执行 bootcmd。还有一处灵活咱们记一下：bootdelay_process() 先读环境变量 bootdelay，读不到才用 CONFIG_BOOTDELAY 的编译值，所以改倒计时不必重编，setenv 一下就生效。

咱们把 AES 的两行放一起看：第 16 行 `CONFIG_BOOTDELAY=-1`，第 18 行 `CONFIG_BOOTCOMMAND="echo Current do not autoboot"`，这是适配期的一对组合。不倒计时，也绝不引导，bootcmd 被设成一句 echo，就算哪天 bootdelay 被改成正值，自动执行的内容也只有回显一行，每改一轮环境都从干净的提示符开始。05 章验收的官方参考板是另一副面孔，EVK 镜像没设 BOOTDELAY，落到编译默认值，05 章第二节那张上电前的对照表里的默认 2 秒倒计时就是这么来的。

### bootcmd：EVK 的完整引导链逐段过

EVK 的 bootcmd 是量产形态的脚本，在 defconfig 第 17 行。咱们把 EVK defconfig 这条查证的输出贴出来：

```bash
# 主机 ~/imx-forge
grep -n "BOOTCOMMAND" third_party/uboot-mainline/configs/mx6ull_14x14_evk_defconfig
```

```text
16:CONFIG_USE_BOOTCOMMAND=y
17:CONFIG_BOOTCOMMAND="run findfdt;mmc dev ${mmcdev}; if mmc rescan; then if run loadbootscript; then run bootscript; else if run loadimage; then run mmcboot; else run netboot; fi; fi; else run netboot; fi"
```

概念篇贴过这行原文，说好了本站逐句过，这里兑现。脚本里的 findfdt、mmcboot、netboot 全是环境变量，找它们的定义时，咱们照章在 board/nxp/mx6ul_14x14_evk/mx6ul_14x14_evk.c 里搜了一遍，命令真跑了，输出一行都没有，findfdt、mmcboot、netboot、loadimage 四个名字零命中。这份目录是 6UL 系两块 EVK 共用的板级目录，跟 6ULL EVK 认的 mx6ullevk 是两回事（06 章讲登记点时分开过）。换个可跑的等价命令，直接搜环境文本：

```bash
# 主机 ~/imx-forge
grep -rn "findfdt\|mmcboot\|netboot\|loadimage" third_party/uboot-mainline/board/nxp/mx6ullevk/mx6ullevk.env | head -8
```

```text
19:loadimage=fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} ${image}
21:mmcboot=echo Booting from mmc ...;
36:findfdt=if test $fdt_file = undefined; then
49:netboot=echo Booting from net ...;
```

咱们把 .env 文件的来路说清。板级目录下与板同名的 .env 就是内置缺省环境的文本源，顶层 Makefile 的规则写明：CONFIG_ENV_SOURCE_FILE 没设时，构建自动认领 board 目录下按 CONFIG_SYS_BOARD 命名的那个 .env，拿 C 预处理器过一遍再编进镜像。预处理顺手办了另一件事，mmcdev=CONFIG_ENV_MMC_DEVICE_INDEX 里的符号展开成 defconfig 给的 1。AES 没有这个 .env 文件，同款脚本全住在 include/configs/mx6ull_aes_emmc.h 的 CFG_EXTRA_ENV_SETTINGS 里（include/env_default.h 第 134 行认这个宏），变量名跟 EVK 是同一套，mmcdev 也一样从 Kconfig 符号来，走的是头文件第 61 行的 __stringify(CONFIG_ENV_MMC_DEVICE_INDEX)。

### findfdt：按板型挑设备树

EVK 一套源码服务好几块板，用哪份 DTB 得看板子身份。findfdt 的开头是 if test $fdt_file = undefined，fdt_file 的初值在 .env 第 7 行，写着 undefined。身份从哪来？mx6ullevk.c 的 board_late_init() 往环境里塞，咱们把源码原样贴出来：

```c
#ifdef CONFIG_ENV_VARS_UBOOT_RUNTIME_CONFIG
	if (is_cpu_type(MXC_CPU_MX6ULZ))
		env_set("board_name", "ULZ-EVK");
	else
		env_set("board_name", "EVK");
	env_set("board_rev", "14X14");
#endif
```

板子报上 board_name=EVK、board_rev=14X14，findfdt 就把 fdt_file 设成 imx6ull-14x14-evk.dtb，6ULZ 与 6ULL 各认各的 DTB，6ULZ 那块认 imx6ulz-14x14-evk.dtb。条件开关 CONFIG_ENV_VARS_UBOOT_RUNTIME_CONFIG 两份 defconfig 里都开着（AES 在第 49 行）。AES 不用这套推断，咱们自己的板子在头文件第 56 行一行写死 fdt_file=imx6ull-aes.dtb，设备树本身的来历归 08 章。

### mmc dev 加 rescan：把卡探活

咱们看这条分支。mmc dev ${mmcdev} 把当前器件切到编号 1 的 eMMC，紧跟的 if mmc rescan 是分水岭：卡探得活，往存储引导走，探不活，落进 else 直接 netboot。mmc dev 报 Card did not respond to voltage select 的话，先跑 mmc rescan 再切器件就能绕过。

### loadbootscript 与 loadimage：两条尝试

探活之后脚本给两条路，咱们分开看。头一条 loadbootscript，fatload 把第 1 分区根目录的 boot.scr（.env 第 3 行 script=boot.scr）读进内存，读到了就 run bootscript。bootscript 先回显一行 Running bootscript from mmc ...，再用一句 source 把刚读进来的脚本就地执行。第二条是常规路，loadimage 用 fatload 把 zImage 读进 loadaddr。fatload 这个名字里的 fat 是认真的，咱们翻 cmd/fat.c，do_fat_fsload 把文件系统类型锁在 FS_TYPE_FAT，只认 FAT。全类型自适应的是另一个命令 load，CONFIG_CMD_FS_GENERIC=y（AES defconfig 第 42 行）把它打开。EVK 链条探的是 FAT 分区，AES 自家的脚本用的却是 ext4load，两套各认各的分区格式。

### mmcboot 与 netboot：二选一，都收在 bootz 上

zImage 读到了就 run mmcboot。咱们把它的第一步看清楚：run mmcargs，mmcargs 的值是 setenv bootargs console=${console},${baudrate} root=${mmcroot}，三层里的第三层在这里设上，console 是 ttymxc0，baudrate 没显式给时落编译默认 115200（drivers/serial/Kconfig 里 default 115200），root 是 mmcroot 即 /dev/mmcblk1p2 rootwait rw。随后 loadfdt 把 DTB 读到 fdt_addr 0x83000000，收尾一行 bootz ${loadaddr} - ${fdt_addr} 完成交接。boot_fdt=try 的兜底也写在脚本里，DTB 加载失败时还能 bootz 裸跑。netboot 是镜像不在卡上的那条路，netargs 设好 NFS 的 root，ip_dyn=yes 时用 dhcp 取地址，把 zImage 与 DTB 从网口拉进来，同样落进 bootz。AES 的头文件里 mmcboot、netboot、mmcargs、netargs 全部同名存在（第 93 行起），EVK 链条在咱们的板上一样跑得通。

## 三、setenv 与 saveenv 实操

认完 EVK 的链条，咱们回到自己的板子动手。命令就三个：printenv 看，setenv 改，saveenv 存。printenv 与 setenv 是 cmd/nvedit.c 里的常驻命令（ENV_SUPPORT 在 env/Kconfig 里 def_bool y），saveenv 的开关 CMD_SAVEENV 默认开，AES 这套配置三个都有。板上操作本环境做不了，板子不在手边，下面的动作按源码写明，现场核验以实板串口输出为准。

```bash
# 板端 /
setenv bootdelay 3
printenv bootdelay
```

printenv 会按 setenv 后的即时状态回显 bootdelay=3，这个值此刻只活在内存里，跟存储还没有任何关系。AES 镜像的编译值是 -1，上电不自动引导，正好留给咱们一个不会被倒计时打断的操作窗口，这是第二节那对组合的另一个好处。

```bash
# 板端 /
setenv bootcmd 'run emmcbootaes'
saveenv
```

emmcbootaes 是 06 章预告过的现成脚本，住在头文件第 71 行起：run emmcargs 设 bootargs，mmc dev ${emmc_dev} 切到 eMMC，ext4load 从第 1 分区把 /zImage 与 /imx6ull-aes.dtb 读进内存，bootz 收尾。单引号把整段值包住，值里的分号才老老实实当分隔符。saveenv 落存储的动作在 env/mmc.c 的 env_mmc_save 里，咱们按顺序一个个看：env_export 把内存哈希表导出成缓冲，算好 CRC32，串口打 Writing to MMC(1)...，然后把带头的 8 KB 写到 0x400000，写不够数时源码 `puts("failed")`，串口就是这两个词。器件号跟着启动器件走，从 eMMC 启动打 MMC(1)，从 SD 卡启动打 MMC(0)。

内存与存储的界线咱们务必分清。setenv 只动内存里的哈希表，saveenv 才碰存储，只 setenv 不 saveenv，复电之后读回的是存储里上次存的那套。没存过任何东西的板子复电，回到的是出厂状态，bootdelay=-1 加一句 echo 的 bootcmd。调试时想临时试一个 bootcmd，恰恰该用只 setenv 不 saveenv 的玩法，试砸了复位就回来，存储里干干净净。

## 四、环境变量坏了怎么办

8 KB 窗口与 CRC 头是这套机制的两个故障面，读回时的裁决在 env/common.c 的 env_import，咱们把关键判断贴出来：

```c
if (crc32(0, ep->data, ENV_SIZE) != crc) {
	env_set_default("bad CRC", 0);
	return -ENOMSG; /* needed for env_load() */
}
```

CRC 对不上，U-Boot 不罢工。env_set_default 打一行 *** Warning - bad CRC, using default environment，然后回落到编译期内置缺省：defconfig 的 BOOTDELAY 与 BOOTCOMMAND、env_default.h 里人人同款的 baudrate 之类，再加上头文件 CFG_EXTRA_ENV_SETTINGS 那一大段。板子照样起来、照样进提示符，只是变量回到出厂。此时的缺省环境只在内存里，咱们 saveenv 一次把它写回 0x400000，CRC 头才重新有效，复电才不再刷警告。

常见的坏法，咱们收成一张速查表：

| 现象 | 根因 | 解法 |
|------|------|------|
| saveenv 报 Cannot export environment: errno = ... | 变量总量超过 CONFIG_ENV_SIZE=0x2000，env_export 往 8 KB 缓冲导出失败，env_mmc_save 当场放弃，一个字节都没写进存储 | 换短脚本，把长启动逻辑挪进 boot.scr 走 loadbootscript 那条路，或调大 ENV_SIZE 重新构建 |
| saveenv 串口打 Writing to MMC(1)... failed（从 eMMC 启动时） | ENV 落点写不进去：器件编号不对、0x400000 处有写入冲突、存储本身报错 | mmc dev 看当前器件编号再核 ENV 所在介质：ENV 器件跟启动器件走，从 eMMC 启动才是 1，从 SD 卡启动 ENV 在卡上，确认 ENV 落点没跟镜像或分区数据重叠，再重试 |
| 上电刷 *** Warning - bad CRC，printenv 全是出厂值 | 0x400000 起的 8 KB 读回来 CRC 对不上，最常见是 ENV 区被别处的写入盖了，06 章 Logo 避让防的就是这一手：768 KiB 的老偏移落在 1663 KiB 的镜像体内 | saveenv 一次把缺省写回，再核 ENV_OFFSET 与镜像实际大小，确认避让还成立 |

表里三条各自的出处咱们交代一下。头一条的报错出自 env/common.c 的 env_export，导出函数把整张哈希表塞进 ENV_SIZE 大小的缓冲，塞不下就带着 errno 退出。第二条的 failed 是 env/mmc.c 原文，write_env 按块写，写不够数返回负数，saveenv 当场放弃。第三条离咱们最近，诱因往往是咱们烧镜像时偏移没算对，环境变量本身没毛病。排查上最短的闭环是 saveenv 之后复电 printenv emmcbootaes，变量还在，ENV 区就是活的。想手工核 CRC，crc32 命令能用（CONFIG_CMD_CRC32 默认开，cmd/Kconfig 第 822 行），AES 这份配置又开了 CONFIG_CRC32_VERIFY=y（第 26 行），还能加 -v 做写后校验。不过得把 0x400000 处读进内存才能算，不如上面那条来得直接。

## 五、与下一篇的衔接

链条拆到最底，每一层都收在 bootz 上。EVK 的 mmcboot 收尾一行是 bootz ${loadaddr} - ${fdt_addr}，AES 自带的 emmcbootaes 与 sdbootaes（头文件第 81 行起，从 SD 卡引导的同构脚本）同样以 bootz 收尾。bootz 拿着内存里的内核、设备树与 bootargs 完成交接，交接那一瞬间发生什么归下一篇，路线表里排的是启动 Linux 一站。AES 的缺省环境已经把接口备好了，咱们念一遍头文件里的原文：loademmcimage=ext4load mmc ${emmc_dev}:1 ${loadaddr} /zImage，loademmcfdt=ext4load mmc ${emmc_dev}:1 ${fdt_addr} /imx6ull-aes.dtb。文件名与路径写得很死，eMMC 第 1 分区根目录，/zImage 与 /imx6ull-aes.dtb。setenv bootcmd 'run emmcbootaes' 加 saveenv，再放这两份文件进去。

## 继续学习

- [产物验证与烧录：四个文件各自是什么、怎么落到板子上](./04_verify_and_flash.md)：四个产物怎么核，SD 卡与 eMMC 两条烧录路怎么走。
- [串口验收：亲眼看见咱们编的 U-Boot 活着](./05_serial_acceptance.md)：提示符怎么拿，倒计时窗口与 2 秒默认值的现场。
- [净源码里没有咱们的板卡：官方参考配置逐行对账](./06_aes_vs_evk_diff.md)：环境扇区从 0xC0000 挪到 0x400000 的完整推理。
- [设备树](./08_device_tree_aes.md)：findfdt 挑出来的 imx6ull-aes.dtb 讲的是什么。
- [调试命令速查](./14_debug_reference.md)：printenv、setenv、mmc 一类命令的工具箱。
