---
title: 调试命令速查：命令行是嵌入式开发的神器
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 调试命令速查：命令行是嵌入式开发的神器

> 这是 U-Boot 主线的收尾篇：串口与 eMMC 的验收、板级移植在前面各章走完，散落在各处的调试命令，本篇收拢成一张速查表加一份排错手册。细节不重讲，每条命令一句用途，讲得最细的章节给回收链接，排查时按表翻，翻到哪条就能回到哪一章。网络、LCD、Logo 各有专章在后面等着，那边管来龙去脉，这边管速查与排错。旧口径按 v2026.10 改正：样例与判断对着这棵源码树和构建产物重核过，NXP 时代的老说法、旧样例里对不上的数值，改到哪儿咱们说到哪儿。

## 一、信息查询组：bdinfo、version、coninfo、printenv

### bdinfo：板子的身份证

拿到一块新板，串口一通，笔者头一个敲的就是 bdinfo。它把内存、网卡、波特率、设备树地址一次报齐，后面每组命令都以这份底子当参照。这棵树里它的实现长什么样，咱们拿源码说话：

```bash
# 主机 ~/imx-forge
grep -n "bdinfo\|arch_print_bdinfo" third_party/uboot-mainline/cmd/bdinfo.c third_party/uboot-mainline/arch/arm/lib/bdinfo.c | head -10
```

```text
third_party/uboot-mainline/cmd/bdinfo.c:25:void bdinfo_print_size(const char *name, uint64_t size)
third_party/uboot-mainline/cmd/bdinfo.c:31:void bdinfo_print_str(const char *name, const char *str)
third_party/uboot-mainline/cmd/bdinfo.c:36:void bdinfo_print_num_l(const char *name, ulong value)
third_party/uboot-mainline/cmd/bdinfo.c:41:void bdinfo_print_num_ll(const char *name, unsigned long long value)
third_party/uboot-mainline/cmd/bdinfo.c:73:void bdinfo_print_mhz(const char *name, unsigned long hz)
third_party/uboot-mainline/cmd/bdinfo.c:86:			bdinfo_print_num_l("DRAM bank",	i);
third_party/uboot-mainline/cmd/bdinfo.c:87:			bdinfo_print_num_ll("-> start",	gd->dram[i].start);
third_party/uboot-mainline/cmd/bdinfo.c:88:			bdinfo_print_num_ll("-> size",	gd->dram[i].size);
third_party/uboot-mainline/cmd/bdinfo.c:93:__weak void arch_print_bdinfo(void)
third_party/uboot-mainline/cmd/bdinfo.c:109:			bdinfo_print_num_ll("FB base", (ulong)upriv->fb);
```

head -10 把列表截断了，grep 对 head 提前关流还在 stderr 报了一句 write error: Broken pipe，咱们看到这句别慌，那是管道截断的正常现象，跟源码无关。完整的打印顺序咱们对着 `bdinfo_print_all` 数一遍：boot_params 从 cmd/bdinfo.c 第 146 行起，接着是 DRAM 三行、flash 三项和 baudrate。第 152 行 relocaddr 之后依次是 reloc off、Build 与网络三行（current eth、ethaddr、IP addr），再往后是 fdt_blob，Video 组跟在后面。FB size 之后垫着 LMB 布局、一行 devicetree 与串口寄存器组，压轴的 `arch_print_bdinfo` 调用落在第 177 行。末组由 `arch/arm/lib/bdinfo.c` 第 31 行起头，头一行就是 arch_number。

按这个顺序，咱们给 AES 板整理一份样例。格式对着源码摆，数值按 512MB DDR 的配置给，属于整理形态而非板端实测：

```text
=> bdinfo
boot_params = 0x80000100
DRAM bank   = 0x00000000
-> start    = 0x80000000
-> size     = 0x20000000
flashstart  = 0x00000000
flashsize   = 0x00000000
flashoffset = 0x00000000
baudrate    = 115200 bps
relocaddr   = 0x9ff4a000
reloc off   = 0x1874a000
Build       = 32-bit
current eth = ethernet@2188000
ethaddr     = b8:ae:1d:01:00:08
IP addr     = 192.168.60.200
fdt_blob    = 0x9ef24000
Video       = lcdif@21c8000 active
FB base     = 0x9ef00000
FB size     = 1024x600x32
devicetree  = separate
```

咱们逐组翻译。DRAM bank 三行说的是内存，bank 0 从 0x80000000 起，0x20000000 就是 512MB，手动加载内核时地址得落在这段里。flash 三项是 0，这块板没有 NOR flash，启动介质是 eMMC，对不上号是正常的。baudrate 对着串口，乱码就回头看它。relocaddr 与 reloc off 是 U-Boot 重定位的坐标——0x9ff4a000 减 0x1874a000 正好等于 0x87800000，对着 CONFIG_TEXT_BASE（out/uboot/.config 第 183 行），说明把自己挪到 DDR 顶端附近运行了，这组数平时用不上，查内存冲突时才派上用场。Build 32-bit 是 cmd/bdinfo.c 第 154 行拿 sizeof(void*) 乘 8 打出来的，i.MX6ULL 是 32 位 ARM。

网络三行是咱们排查网络的起点。第 46 行的 print_eth 把设备名、当前网卡的 MAC、IP 一次打齐，网卡多于一块时变量名会变成 eth1addr、ipaddr1。Video 那组来自第 97 行的 show_video_info，defconfig 里 CONFIG_VIDEO 开着。CONFIG_LMB 打开时 FB size 之后先接一段内存布局 dump，接着第 166 至 167 行打一行 devicetree = separate（构建产物 CONFIG_OF_REAL=y，out/uboot/.config 第 865 行，板上必有），CONFIG_DM_SERIAL 打开时再接一段串口寄存器组。头尾两段行数多且板板不同，样例里省去了，中间那行 devicetree 咱们收进了上面的样例，位置在 FB size 与末组之间。separate 这个值是来源名，出自 fdtdec_get_srcname()：这棵构建 CONFIG_OF_SEPARATE=y（out/uboot/.config 第 868 行），设备树附在 U-Boot 镜像末尾，来源登记的就是这个名字。

末组咱们按 arch/arm/lib/bdinfo.c 给全：

```text
arch_number = 0x00000000
TLB addr    = 0xffff0000
irq_sp      = 0x9ef24e30
sp start    = 0x9ef24e20
Early malloc usage: 2f8 / 2000
```

arch_number 是 0 咱们别当异常。第 18 行的逻辑写着，只有定义了 CONFIG_MACH_TYPE 它才有值，AES 的 defconfig 与构建产物里都没有这项，设备树时代内核不靠这个数认板。TLB addr、irq_sp、sp start 是内存布局的三根柱子，Early malloc usage 报启动早期那块小堆的用量，2000 是上限，真跑超了说明初始化阶段内存吃紧。假如哪天打开了 CONFIG_CMD_BDINFO_EXTRA（cmd/Kconfig 第 154 行写着 default y if SANDBOX || X86，ARM 板默认不开），这里还会多出 stack ptr、ram_top ptr、malloc base 三行。

带参数的形态有三个，咱们各对一眼源码：bdinfo -a 全量，bdinfo -e 只看网络三行（需要 CONFIG_NET），bdinfo -m 只看 DRAM。选项解析在 cmd/bdinfo.c 第 192 行，选项串就是“aem”。

### version 与 coninfo

version 报版本。咱们平时认版本看横幅就够，输出按 cmd/version.c 第 21 至 26 行整理：横幅一行，编译器与链接器各跟一行，横幅里的 2026.10 对着顶层 Makefile 第 3 至 4 行的 VERSION 与 PATCHLEVEL。提交号与日期是占位的整理值，以板上输出为准：

```text
=> version
U-Boot 2026.10-g1a2b3c4d (Nov 14 2026 - 10:06:00 +0800)
arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203
GNU ld (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 2.45.1.20251203
```

coninfo 列控制台设备。咱们把它的格式对着 cmd/console.c 第 25 至 45 行摆出来：一行设备名带输入输出标志，下面挂着它占用的 stdin、stdout、stderr：

```text
=> coninfo
List of available devices
|-- serial (IO)
|   |-- stdin
|   |-- stdout
|   |-- stderr
```

(IO) 两个字母表示这只设备读写都占。板上多串口想换日志口时，咱们看这张表认名字，再去改 stdout 环境变量。

### printenv：环境变量的第一手资料

printenv 把环境变量摊开，不带参数打全量，跟变量名打单条。AES 板的出厂默认都在 include/configs/mx6ull_aes_emmc.h 第 49 行起的 CFG_EXTRA_ENV_SETTINGS 里，咱们摘几条关键的：

```text
console=ttymxc0
image=zImage
fdt_file=imx6ull-aes.dtb
fdt_addr=0x83000000
mmcdev=1
mmcroot=/dev/mmcblk1p2 rootwait rw
```

这几条是后面各组的底子：内核组用的镜像名与设备树名在这，存储组的设备号 mmcdev 等于 1 对着 eMMC，网络组要的 serverip 倒不在默认环境里，得咱们手工设。mmcargs 那条（第 65 行）是拼装 bootargs 的模板，run 一下才生成 bootargs 本身，第五节与第六节的案例二都会回到它。

## 二、存储组：mmc 族与文件系统命令

存储组围绕 mmc 展开，每条一句用途：mmc list 列控制器，mmc dev 切设备，mmc info 读卡身份，mmc rescan 重扫卡，mmc part 看分区表，mmc read 与 mmc write 在内存和介质之间搬块，mmc erase 擦块。逐条验收与输出解读，10 章走完了，这里只补一个编号证据：设备编号写在 arch/arm/dts/imx6ul.dtsi 第 33 至 34 行的 aliases 里，mmc0 对 usdhc1，mmc1 对 usdhc2，AES 板 0 号口接 SD 卡座、1 号口接 eMMC。早期样例把这对标注写反过，咱们这里按 aliases 改正。

文件系统那侧咱们认三条：ext4ls 列目录，ext4load 把 ext4 分区里的文件读进内存（cmd/ext4.c 第 81 与 86 行），fatload 对 FAT 分区干同样的事（cmd/fat.c 第 36 行）。AES 板两条路都铺了：emmcbootaes 用 ext4load 从 eMMC 取 zImage 与 imx6ull-aes.dtb（板级头文件 include/configs/mx6ull_aes_emmc.h 第 69 至 70 行），boot.scr 脚本那条路走 fatload（板级头文件第 87 至 90 行：loadbootscript 把脚本读进内存，bootscript 再用 source 执行），这条不在第四节点名的那三条 run 链之列。defconfig 里 CONFIG_CMD_EXT4、CONFIG_CMD_EXT4_WRITE、CONFIG_CMD_FAT 全开着，构建产物 out/uboot/.config 第 823 至 825 行对应在册。

::: warning mmc write 与 mmc erase 没有后悔药
后果：块号算错，写坏或擦掉的可能是引导镜像、分区表或环境区，板子重启后串口静默，看着像烧录事故。根因：这两条命令按块号直接动手，不做位置校验，正确性全押在咱们算的数字上。写之前用 mmc read 读回核内容，写完再读一遍比对，擦除范围宁可少一块，别多一块。
:::

## 三、网络组：dhcp、tftpboot、ping

三条命令都在 cmd/net.c，咱们把注册位置对一眼：dhcp 在第 144 行，tftpboot 在第 53 行，ping 在第 448 行。defconfig 里 CONFIG_CMD_DHCP 与 CONFIG_CMD_PING 是显式开的（第 33、34 行），CONFIG_CMD_TFTPBOOT 没写，cmd/Kconfig 第 2280 行给它 default y，网络开着它就跟着进来，构建产物第 763 行在册。

用法咱们一句话一条。dhcp 找服务器要 IP，拿到后写进 ipaddr、netmask。tftpboot 把文件从服务器搬进内存，参数是地址加文件名，loadaddr 的默认 0x82000000 出自 CONFIG_SYS_LOAD_ADDR（.config 第 227 行），省地址就写 tftpboot ${image}。ping 测连通，通就一行 is alive。串口上的形态按排查记录整理：

```bash
# 板端 U-Boot 命令行
dhcp
tftpboot 0x82000000 zImage
ping 192.168.60.129
```

```text
=> dhcp
BOOTP broadcast 1
DHCP client bound to address 192.168.60.200 (1033 ms)
```

```text
=> tftpboot 0x82000000 zImage
Using ethernet@2188000 device
TFTP from server 192.168.60.129; our IP address is 192.168.60.200
Filename 'zImage'.
Load address: 0x82000000
Loading: ####################
	 5.9 MiB/s
done
Bytes transferred = 6821504 (681680 hex)
```

```text
=> ping 192.168.60.129
Using ethernet@2188000 device
host 192.168.60.129 is alive
```

命令名有个分岔。这棵树注册的名字是 tftpboot，cmd/net.c 里两处 U_BOOT_CMD 都用它（第 53 与 61 行，分别对应 IPv6 打开与关闭两种编译），旧手册满篇的简写 tftp，咱们在 cmd 目录里对着注册表 grep，找不到裸的 tftp 项。板级头文件里 netboot 那条链（第 111 行起）还写着 setenv get_cmd tftp，旧字串在板上解析不解析得动，敲一下就知道，能改的咱们照 tftpboot 改。

排查按层走。咱们要判断链路层通不通，tcpdump 抓 ARP 最快见分晓。NFS 挂根的 netargs 在板级头文件第 108 行，root=/dev/nfs，那是网络组的另一条路，本篇不展开，需要时再去。

## 四、内核启动组：bootm、bootz、booti 与 fdt

三条启动命令对应三种内核镜像，区别在头上，咱们把头翻出来看。bootm 吃 uImage，那是 mkimage 加过 64 字节头的镜像，头里写着加载地址、入口点与 CRC，bootm 验完头再跳。bootz 吃 zImage，ARM 的自解压压缩内核，没有头，所以第二、第三个参数要显式给：第二个参数占位 initrd，没有就写减号，第三个参数是设备树地址。booti 吃 Image，未压缩的内核镜像。源码的自述就是帮助文本：bootz.c 第 131 行写 `boot Linux zImage image from memory`，booti.c 第 177 行写 `boot Linux kernel 'Image' format from memory`，bootm.c 第 229 行写 `boot application image from memory`。

三个源文件都在 cmd/ 里躺着，咱们真跑一遍列目录：

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/cmd/ | grep -E "booti|bootm|bootz"
```

```text
abootimg.c
booti.c
bootm.c
bootmenu.c
bootmeth.c
bootz.c
```

bootmeth.c 是启动方法框架，管启动方法的注册与选择，不是本节的启动命令。文件在树里，命令可不都进镜像。defconfig 里显式开的只有一条，咱们原样贴：

```bash
# 主机 ~/imx-forge
grep -rn "CONFIG_CMD_BOOTI\|CONFIG_CMD_BOOTM\|CONFIG_CMD_BOOTZ" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig third_party/uboot-mainline/configs/mx6ull_14x14_evk_defconfig
```

```text
third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig:25:CONFIG_CMD_BOOTZ=y
third_party/uboot-mainline/configs/mx6ull_14x14_evk_defconfig:21:CONFIG_CMD_BOOTZ=y
```

bootm 没在 defconfig 里露面，cmd/Kconfig 第 312 行给它 default y，构建产物 out/uboot/.config 第 588 行在册，它进了镜像。booti 相反，cmd/Kconfig 第 398 行的依赖写着 ARM64 || RISCV || SANDBOX，i.MX6ULL 是 32 位 ARM，三个都不沾，咱们 grep 构建产物 .config，CONFIG_CMD_BOOTI 零命中，booti 编不进这两块板的镜像，booti.c 留在树里是给 64 位平台用的。落到这块板，咱们要认的格式就两种：zImage 配 bootz，uImage 配 bootm。

第四条相关的命令是 boot，它做的事就是跑 bootcmd，bootm.c 第 243 行的自述写着 `boot default, i.e., run 'bootcmd'`。咱们想调启动行为，得知道这块板的出厂开关：defconfig 第 16 行 CONFIG_BOOTDELAY=-1，第 18 行 `CONFIG_BOOTCOMMAND="echo Current do not autoboot"`。按 common/autoboot.c 第 497 至 498 行的判断，bootdelay 等于 -1 时 bootcmd 压根不执行，也不倒计时，上电直接停在命令行。想让板子自己起，要么改这两个变量，要么手动 run 板级头文件备好的命名链。

板级头文件里备好的链子不止三条，本篇挨条点名要认的三条：emmcbootaes 从 eMMC 起，sdbootaes 从 SD 卡起，netboot 从网络起。boot.scr 脚本那条（bootscript）第二节提过一句，mmcboot 07 章点过名，这里不展开。eMMC 那条的骨架是 ext4load 取 zImage 与 imx6ull-aes.dtb 到内存，再 bootz ${loadaddr} - ${fdt_addr}（板级头文件第 69 至 76 行）。启动形态按源码整理：

```bash
# 板端 U-Boot 命令行
run emmcbootaes
```

```text
Booting AES from eMMC ...
Kernel image @ 0x82000000 [ 00000000 - 0x681680 ]
## Flattened Device Tree blob at 83000000
   Booting using the fdt blob at 0x83000000
   Loading Device Tree to 0x9ff5e000, end 0x9ff65f68 ... OK

Starting kernel ...
```

fdt 族咱们一句一个：fdt addr 0x83000000 指定操作的设备树 blob，fdt print / 或 fdt print /memory 看节点，fdt set 改属性，改动会让 blob 变大，装不下前记得 fdt resize 腾空间。实现在 cmd/fdt.c，构建产物第 614 行 CONFIG_CMD_FDT=y 在册。设备树本身的读法回收 08 章。

## 五、环境变量组：setenv、saveenv、env default

setenv 改，saveenv 存，env default 回出厂，printenv 查（第一节刚用过）。setenv 只改内存里那份，重启就丢，咱们要持久还得 saveenv 把内存这份写回介质，它的注册在 cmd/nvedit.c 第 469 行。AES 板的环境住在 eMMC 4MiB 偏移处（CONFIG_ENV_OFFSET=0x400000，defconfig 第 8 行，10 章核过），读不到时 U-Boot 打 *** Warning - bad CRC, using default environment，回退到编译时打进去的默认值，那套默认值就是 CFG_EXTRA_ENV_SETTINGS。

env default 是 env 命令的子命令，env 的注册在 nvedit.c 第 1203 行。env default -a 把全部变量恢复成默认，咱们跑完要 saveenv 才存得住。

::: warning env default 会连网络参数一起洗掉
后果：咱们手工 setenv 过的 ipaddr、serverip、netmask 不在编译时默认环境里，env default -a 一跑全没了，接着 tftpboot 报超时，看着像网络移植翻车，其实是环境被洗了。根因：default 恢复的是 CONFIG_BOOTCOMMAND 与 CFG_EXTRA_ENV_SETTINGS 那套内置值，手工改的东西只有 saveenv 过才写进介质那份环境。跑完补 saveenv，网络参数重新设一遍，改之前 printenv 存一份底稿更稳。
:::

bootargs 要在 bootz 之前就位，出厂不直接存，靠 mmcargs 拼（板级头文件第 65 行），咱们把拼装规则看明白：run mmcargs 等于把 bootargs 设成 console=${console},${baudrate} root=${mmcroot}，console 与 mmcroot 的值在第 53、63 行，拼完就是 console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw。第六节案例二的事故就出在 bootargs 被人手工覆盖。

还有一条咱们要记住：bootdelay=-1 的板子没有倒计时可拦，重启之后直接就是命令行。这对排错是好事，断电重来不用抢窗口，咱们一眼就能确认自己回到了 U-Boot。

## 六、实战案例两则

两则按现象、排查、根因、解决四段走，串口输出按当时的排查记录整理。

### 案例一：tftp 下载大文件必超时

现象：咱们拿这块板子 ping 服务器，通的，几 KB 的测试文件秒下，换 zImage 就在 Loading 那行卡住，几个 # 之后报 T，超时收场。网线换过、交换机换过，症状不变。

排查咱们按层走。ping 回 is alive，链路活着。小文件秒下，服务器活着。服务器端 tcpdump 看得到数据包在出，卡点不在链路也不在服务，嫌疑落在板子自己身上：

```bash
# 板端 U-Boot 命令行
ping 192.168.60.129
tftpboot 0x82000000 zImage
```

根因藏在环境变量里。printenv 一查，netretry=no。这个变量的语义在 net/net.c 第 744 至 758 行写得很直白：取值 yes 是失败后整个重来，no 与不设都是只试一次。当时这板子的环境里躺着一条 no，等于咱们亲手把重试关了，大文件传输赶上链路抖一下，整次操作直接判负，小文件一次成功，自然从不触发。

解决就两条命令：

```bash
# 板端 U-Boot 命令行
setenv netretry yes
saveenv
```

再下 zImage，失败后整个操作自动重来，Loading 的 # 走完，Bytes transferred 收尾，咱们这才把传输跑通。还有一层边界要交代：netretry 管的是失败后要不要重来，链路本身质量差，光靠重试只是把成功率磨上去，PHY 与布线那一半是硬件的事。

### 案例二：内核一起来串口就静了

现象：咱们敲下 bootz，Starting kernel 一闪，之后串口再没有一行内核日志，敲键也没有回显。bootdelay 是 -1，断电重来直接回到 => 提示符，连倒计时都没有。

排查咱们从镜像开始。tftpboot 重下，bootz 复现同样的静默。设备树是 07 章编出来、10 章 ext4ls 在 p1 里见过的那份 imx6ull-aes.dtb，fdt print /memory 的内存段也对。咱们把 bootargs 减到最简，串口与根设备都留着（${mmcroot} 展开即 /dev/mmcblk1p2 rootwait rw）：

```bash
# 板端 U-Boot 命令行
setenv bootargs console=ttymxc0,115200 root=${mmcroot}
bootz ${loadaddr} - ${fdt_addr}
```

这一回内核日志整段滚出来，一路打到挂载根文件系统，再到 shell。咱们把原 bootargs 逐个参数加回去，加回 console=ttyS0 那一项时，串口重新静默，板子起没起来从串口上一眼看不出。

根因在那条 bootargs 的来路上，两条错分开看。头一条在 console：它从别的板子的笔记里搬来，console 写成 ttyS0，而 i.MX6ULL 的串口在内核里叫 ttymxc0。console 指到不存在的设备，内核照常在跑，日志一行都到不了串口，串口看着就是死，后面真出了什么事都看不见。第二条要交代这类静默不会自己解除：这块板的内核没有兜底命令行，out/linux/.config 第 515 行 CONFIG_CMDLINE 只有 noinitrd console=ttymxc0,115200，第 516 行 CONFIG_CMDLINE_FROM_BOOTLOADER=y 让 bootloader 的 bootargs 整体替换这份内置值，bootargs 里 root= 一缺，内核停在挂根的 panic。第 7137 行 CONFIG_PANIC_TIMEOUT=0，U-Boot 侧 WATCHDOG 与 IMX_WATCHDOG 都没开（out/uboot/.config 第 1783 至 1784 行），panic 之后板子不会自己复位，只能断电重来。console 参数错误遮住的是报错本身，真错的是那条搬来的 bootargs。

解决用板子自己的模板：

```bash
# 板端 U-Boot 命令行
run mmcargs
saveenv
```

run mmcargs 拼出来的就是 console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw，console 的设备名咱们别搬别家，这块板出厂默认写在板级头文件第 53 行。手工敲也行，setenv bootargs 配上同一串值，效果一样。

## 七、常见错误速查

表里五条是排查记录里反复出现的报错，咱们每条配上根因与解法，解法里的命令多数前面铺过，iminfo 与 journalctl 这里补认：iminfo 核镜像头（CONFIG_CMD_IMI=y，out/uboot/.config 第 617 行，编进了镜像），journalctl 是主机上看 tftpd-hpa 日志的工具。

| 现象 | 根因 | 解法 |
|------|------|------|
| Bad Magic Number | 地址上不是合法镜像：没下到东西，或把没有 mkimage 头的 zImage 交给了认头的命令 | iminfo 核地址，bootz 配 zImage，bootm 配 uImage |
| Bad Data CRC | 镜像头认了，数据体 CRC 对不上，传输或存储环节损坏 | 重下重烧，换线换服务器交叉验证 |
| No MMC device available | 控制器没被设备树放出，或设备号越界 | mmc list 看注册编号，usdhc 节点回 08 章 |
| TFTP timeout | 链路、服务器、防火墙、路径，四选一 | ping serverip 分层查，journalctl 看 tftpd-hpa 日志 |
| Kernel panic - not syncing | root 或 console 指错，报错还被 console 参数遮住 | 最小 bootargs 分段定位，案例二就是活例 |

Bad Magic Number 这行字有出处，boot/image-board.c 第 50 行与 boot/bootm.c 第 72 行，认头失败就打它。zImage 本来就没有 mkimage 头，iminfo 对 zImage 报 Bad Magic Number 属于预期行为，咱们别误判成镜像损坏。CRC 还得跟环境的坏 CRC 分清：镜像的 CRC 检查挂在 bootm 与 iminfo 的输出里，环境的坏 CRC 打的是 *** Warning - bad CRC, using default environment（env/common.c 第 453 行，10 章核过），一个是镜像坏了，一个是环境区没写好回退默认值，两码事。

No MMC device available 出现在 mmc dev 指向不存在的编号时，以 mmc list 的输出为准，列表里没有的编号咱们别切。电压类报错 Card did not respond to voltage select，mmc rescan 一把通常就能找回，找回后记得重新核对 mmc dev 指向的编号。

## 继续学习

- [产物验证与烧录](./04_verify_and_flash.md)：四个文件的验证与烧录实操，Bad Magic Number 与 CRC 报错的上游多半在那里。
- [第一次上电与串口检查](../start/05_first_boot_check.md)：开串口与进 U-Boot 命令行的第一课，本篇所有板端命令从那里起步。
- [存储验收](./10_emmc_acceptance.md)：mmc 族逐条验收与环境变量住处的完整讲法，第二节只回收了一句。
- [设备树](./08_device_tree_aes.md)：fdt 族操作的对象怎么来，usdhc 与 aliases 的写法都在。
