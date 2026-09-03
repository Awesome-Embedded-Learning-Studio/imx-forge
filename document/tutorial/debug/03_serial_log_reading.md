---
title: 串口日志阅读路线：从一行输出找到下一站
---

# 串口日志阅读路线：从一行输出找到下一站

> 调试卷前两篇的工具都默认一件事：咱们已经知道问题出在哪个程序里。gdbserver 把断点打进指定进程，strace 盯着指定命令跑；可最常见的第一现场，是串口上一行行滚动的输出。读不懂这份输出，咱们就不知道下一站该去哪。本篇是调试卷的收尾篇：教您把串口日志读成定位线索，启动分段地图、Oops 解剖、噪音过滤、截日志的规范一次讲完。Oops 的内核态深入解剖在驱动卷与内核卷已有专章，本篇只管用户视角的读法，细节放进不重写那几章。

::: info 您将学到
- 把三百多行启动日志切成五段的地图，卡在哪一段，问题就在哪个子系统
- 从 Linux version 行与 Kernel command line 行读出环境、版本、根设备与控制台
- Oops 与 panic 的区别，PC、LR、Call trace、寄存器现场怎么读，再用 nm 加 addr2line 把地址落回源码(含真跑整条链路与它的边界)
- deferred probe、固件加载失败、模拟器里的桩超时这三类噪音怎么判读，单行失败与链路失败是两种世界
- 截一段拿去提问、提 Issue 的日志，要凑齐哪四要素
:::

::: tip 前置知识 · 咱们的环境
- 串口工具的装配与配置(minicom、picocom，115200 8N1 无流控)您回 [串口工具使用](../start/04_serial_tools_minicom.md) 看；首次上电流程与 tee 记日志的手法在 [启动与调试](../practical/03_boot_and_debug.md)
- 本篇只讲读日志。读完要下断点进内核态，kgdb 路线见 [内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) 与 [驱动开发入门](../kernel/07_driver_basic.md)；启动流程逐阶段的完整讲解在 [内核启动与调试](../kernel/08_kernel_boot_debug.md)，U-Boot 阶段的命令在 [U-Boot 调试命令](../uboot/09_debugging_commands.md)
- 路径上下文：咱们的宿主操作都在仓库根 ~/imx-forge 下进行；日志样本来自 QEMU 直启(mcimx6ul-evk 机器，run-qemu.sh 那条链)的真跑记录，对应的主线内核构建树是 out/mainline/linux,vmlinux 就在 out/mainline/linux/vmlinux;交叉工具链装在 /opt/arm-gnu-toolchain(Arm GNU Toolchain 15.2.Rel1)
:::

## 一、串口是板子唯一的主诉渠道

板子不会说话，它从头到尾只有一个正式的输出口：调试串口。U-Boot 挂了，没有 SSH 可言，网络栈压根还没起来；init 挂了，咱们连 dmesg 都敲不了，因为 shell 根本没出生。从 ROM Code 的第一行输出(如果它配了输出)到 login 提示符之后的一切，这条 UART1 上的 115200 波特流是咱们唯一的实时现场。所以排障的第一站永远是串口，而不是重启再试一次。

工具层面咱们不在本篇重复：minicom 的菜单配置、dialout 权限、硬件流控那颗雷，[串口工具使用](../start/04_serial_tools_minicom.md) 讲过;`picocom -b 115200 /dev/ttyUSB0 | tee boot.log` 这种边看边写进文件的手法，[启动与调试](../practical/03_boot_and_debug.md) 有现成命令。本篇假设您手上已经有一份完整的 boot.log,咱们专心解决读的问题。

本篇分段地图与噪音判读引用的日志，全部来自同一条 QEMU 直启会话的串口记录，全份 374 行，从内核第一行一直到登录后敲命令，原文照 emu 卷的惯例收在本卷 `assets/qemu-e2e.log`，您随时可以对照复核；第三节那段 Oops 实录是唯一例外，引自模拟卷打地鼠那一章的串口记录。QEMU 直启(-kernel 直接引导)没有 ROM 输出，也没有 U-Boot 阶段，日志从内核第一行开始；实际的板子上，这份记录前面还躺着 ROM 到 U-Boot 的一段，那个阶段怎么读，[U-Boot 调试命令](../uboot/09_debugging_commands.md) 与 [启动与调试](../practical/03_boot_and_debug.md) 有逐行实录，咱们不在这里重抄。

::: warning 未实测标注
ROM 输出与 U-Boot 阶段的串口形态，本环境验证不了，笔者手边没有上电的 i.MX6ULL;相关描述以 uboot/09 与 practical/03 两章已发布的实测日志为准(Hit any key 倒计时的实录在 practical/03，printenv 与命令箱的实测输出在 uboot/09)。本篇所有贴出的输出均出自 QEMU 直启链，命令参数在 emu 卷有完整记录。
:::

## 二、启动日志分段地图

拿到三百多行日志别逐行啃，咱们先 grep 里程碑词，把骨架抽出来：

```bash
# 主机 ~/imx-forge;qemu-e2e.log 就是上面那份会话日志，收在本卷 assets/ 下
grep -n "Linux version\|command line\|Mounted root\|as init process\|Welcome\|login:" document/tutorial/debug/assets/qemu-e2e.log | head -8
```

笔者对这份 QEMU 记录真跑的输出如下，六个里程碑把整条启动链的骨架撑起来了：

```text
3:[    0.000000] Linux version 7.1.0-dirty (charliechen@DESKTOP-65DBAA7) (arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203, GNU ld (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 2.45.1.20251203) #3 Sat Aug 29 09:54:58 CST 2026
26:[    0.000000] Kernel command line: console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw
222:[    1.820645] VFS: Mounted root (ext4 filesystem) on device 179:0.
226:[    1.845247] Run /sbin/init as init process
249:Welcome to Buildroot
250:buildroot login: [   12.075600] fec 20b4000.ethernet eth0: registered PHC device 0
```

注意第 26 行那组关键词用的是小写 command line,匹配 Kernel command line 这个固定措辞;笔者头一次写成大写 Command line,grep 颗粒无收，这种大小写陷阱值得您先吃一次亏再记住。下面把日志切成五段，每段看正常长什么样、卡住说明什么。

### 第一段：内核的自我介绍

```text
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 7.1.0-dirty (charliechen@DESKTOP-65DBAA7) (arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203, ...) #3 Sat Aug 29 09:54:58 CST 2026
[    0.000000] OF: fdt: Machine model: Awesome Embedded Studio IMX6ULL (i.mx NXP)
[    0.000000] Kernel command line: console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw
```

Linux version 一行是内核的自动报名：版本 7.1.0-dirty、在哪台主机编的、哪套 gcc 哪天编的。您日后提 Issue 贴日志，环境与版本说明这一行自带，不用手打。Machine model 行核对的是设备树有没有选对，这里就是咱们自己的 AES 板。Kernel command line 一行信息量最大:console=ttymxc0,115200 告诉咱们内核把话往哪个串口说(要是您屏幕上一行都没有，第一个要查的就是它，设备名拼错、波特率不对都归这案)；root=/dev/mmcblk1 交代根设备在哪。同一条参数在实际的板子上带分区号,咱们 practical/03 的真机实录里写的是 root=/dev/mmcblk0p2，QEMU 这张镜像是整盘 ext4 所以没有 pN 后缀；rootwait 让内核老老实实等 SD 卡就绪再挂。卡在这一段之前(连 Booting 都没有)，问题在引导参数或串口本身，[内核启动与调试](../kernel/08_kernel_boot_debug.md) 的问题 3 有完整清单。

### 第二段：驱动 probe 的流水账

```text
[    0.120108] imx6ul-pinctrl 20e0000.pinctrl: initialized IMX pinctrl driver
[    0.162468] i2c i2c-0: IMX I2C adapter registered
[    0.163871] i2c i2c-1: IMX I2C adapter registered
[    0.241211] 2020000.serial: ttymxc0 at MMIO 0x2020000 (irq = 191, base_baud = 5000000) is a IMX
[    0.243106] printk: console [ttymxc0] enabled
# ……中间数行省略……
[    1.537338] mmc1: SDHCI controller on 2194000.mmc [2194000.mmc] using ADMA
[    1.564460] mmc1: new high speed SD card at address 93cc
[    1.569192] mmcblk1: mmc1:93cc QEMU! 256 MiB
```

这一段是一长串 registered、initialized、enabled,每行一个子系统或一个设备探到了。console [ttymxc0] enabled 值得认脸：串口驱动接管控制台，之后的输出才是完整可靠的。mmc 那三行把 SD 卡认出来，厂商串打的是 QEMU! 256 MiB,虚拟环境的自供状态；实际的板子上这里会是真卡型号，这也是咱们扫一眼日志就能分辨虚拟与实体的特征之一。卡在这一段的判据：滚动的输出停在哪一行，最后成功那行指向的下一个 probe 对象往往就是嫌疑犯，把它拿到 dmesg 与设备树里对质。

### 第三段：挂上根文件系统

```text
[    1.819509] EXT4-fs (mmcblk1): mounted filesystem 38cb4c97-5868-4d15-9c31-762d94739e83 r/w with ordered data mode. Quota mode: none.
[    1.820645] VFS: Mounted root (ext4 filesystem) on device 179:0.
[    1.823392] devtmpfs: mounted
[    1.824483] VFS: Pivoted into new rootfs
[    1.841709] Freeing unused kernel image (initmem) memory: 1024K
```

命令行里声明的 root=/dev/mmcblk1 与实际块设备在这里对上了号:179:0 是它的 主：次设备号，179 这一位正是 mmc 块设备家族。EXT4 那行还带卷标 UUID,两行互为佐证。反过来，这一段最常见的死法是 VFS: Cannot open root device 一族，root= 写错、分区没烧进去、文件系统类型不对、块设备驱动没编进内核都会走到这里，[内核启动与调试](../kernel/08_kernel_boot_debug.md) 的问题 4 列了四条可能原因,排查命令(mmc part、cat /proc/partitions)也在同一节，咱们查之前先回看第二段里 mmc 有没有认出卡。

### 第四段：init 与 rcS 起服务

```text
[    1.845247] Run /sbin/init as init process
[    2.415612] random: crng init done
Starting syslogd: OK
Starting klogd: OK
Running sysctl: OK
Starting udevd: OK
# ……中间数行省略……
Starting network: OK
Starting ifplugd for eth0: OK
Starting crond: OK
Starting dropbear sshd: OK
Starting telnetd: OK
```

Run /sbin/init as init process 一出，PID 1 诞生，内核把舞台让给用户空间。紧接着这些 Starting xxx: OK 没有 printk 时间戳，它们是 Buildroot rootfs 的 rcS 按着 /etc/init.d 里 Sxx 序号逐个跑脚本打的招呼：S50dropbear 起了 sshd,咱们后面才有 ssh 可用。卡在这一段的判据：输出停在某个 Starting 之后就没了动静，问题多半在那个脚本或它依赖的服务，往 rootfs 侧查，构建选项的排查有 [Buildroot 调试与排错](../buildroot/10_debugging.md) 兜着。

### 第五段：login 提示符

```text
Welcome to Buildroot
buildroot login: [   12.075600] fec 20b4000.ethernet eth0: registered PHC device 0
```

login: 出现等于宣布系统活着：getty 已经守在 ttymxc0 上等您输入。有个细节别误读:login: 后面紧跟的内核行(fec 注册 PHC)不是异常，用户态输出与内核 printk 共用一条串口，交错是常态；时间戳也不用慌，第四段引文里省略的那几行 udevd printk 在 2.78 到 3.04 秒之间打完，内核随后安静下来，直到 12 秒才又开口，中间约九秒的空档里用户态脚本在安顿网络与服务，日志出现空档是常态，不是卡死。咱们这份记录再往后就是 root 回车、敲命令拿到回显，登录链路完整闭合。过了 login: 之后程序再出的事，就不归本篇管了，那是 [strace 与 coredump](02_strace_log_coredump.md) 的主场。

## 三、Oops 与 panic:把地址落回源码

先用一句话分清两个词:Oops 是内核遇到致命错误时打印现场、杀死当前执行流，系统多半还活着;panic 是内核认定自己没法再运转，整机停下。同一个崩溃点，炸在普通进程上下文是 Oops，炸进 PID 1 或关键路径就成了 panic,所以咱们在模拟卷的实录里见过 worker 线程被 external abort 杀掉而 login 照常出来的场面。

一份 Oops 报告的关键字段，拿咱们仓库里真实出现过的三行来看(出处是 [QEMU 板级模拟卷](../emu/) 打地鼠那一章的串口实录):

```text
[    0.300767] Unhandled fault: external abort on non-linefetch (0x008) at 0xe0870018
[    0.301051] [e0870018] *pgd=8201d811, *pte=021b0653, *ppte=021b0453
[    0.303615] PC is at imx_mmdc_probe+0x80/0x31c
```

第一行给异常类型与出事地址；第二行是页表现场，高 20 位拼上页内偏移能手算出物理地址;第三行 PC is at 函数+偏移/函数大小，直接点名案发函数。往下通常还有 LR is at(从哪儿跳来，但内联与尾调用会让它指去不相干的地方，只能当旁证)、一排 Register rN information、Call trace 调用链。读的次序咱们记成一句：以 PC 为纲，寄存器做旁证，LR 只当八卦听。这三行怎么三路互证、pte 怎么手算，emu 卷的排查实录有整章演绎，本篇不抢它的戏。

咱们本篇要补的是另一环：报告里只有裸地址、没有符号的场合，怎么把地址落回源码。思路是从 vmlinux 出发，nm 给地址，addr2line 反查。先说符号从哪来：别猜。笔者拿 imx6ull_aes_init 这种想当然的名字去 grep nm 输出，颗粒无收，这个名字在内核里根本不存在；可靠的来源是日志自己，咱们这份记录里就有一行 `imx_soc_device_init: failed to find fsl,imx6ul-ocotp regmap!`,函数在报错时把自己的名字印了出来。拿它把整条链路走一遍：

```bash
# 主机 ~/imx-forge;vmlinux 与产生日志的内核是同一份构建
ls -l out/mainline/linux/vmlinux
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-nm out/mainline/linux/vmlinux | grep -w imx_soc_device_init
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-addr2line -e out/mainline/linux/vmlinux -f -i 0xc1334be0
```

```text
-rwxr-xr-x 1 charliechen charliechen 26584684 Aug 29 09:55 out/mainline/linux/vmlinux
c1334be0 t imx_soc_device_init
imx_soc_device_init
soc-imx.c:?
```

三段输出咱们挨个验一遍。ls 那行的修改时间 Aug 29 09:55,与日志第三行 Linux version 末尾的 #3 Sat Aug 29 09:54:58 CST 2026 对上，磁盘上这份 vmlinux 就是吐出那份日志的构建，拿它做地址解析才有效；版本对不上的 vmlinux,解出来的行号全是误导。nm 给出函数落在 0xc1334be0(小写 t 表示局部符号)，ARM 32 位内核链接在 0xc0000000 段，Oops 报告里的 PC 值可以直接拿来对。addr2line 把地址还原成函数名 imx_soc_device_init 与文件名 soc-imx.c,行号给的是问号，而且它只回这个不带目录的 basename;目录得咱们自己补，拿 soc-imx.c 在内核树里一搜，整个 third_party/linux_mainline 只命中 drivers/soc/imx/soc-imx.c 一处，imx_soc_device_init 的定义与那行 pr_err 都在这份文件里。把文件名搜回源码树，本来就是地址落回源码这条链的最后一环，addr2line 不包送。

行号为什么是问号，值得咱们刨一下根，别让它默默糊弄过去：

```bash
# 主机 ~/imx-forge;数一数 vmlinux 里有没有 DWARF 调试段
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-readelf -S out/mainline/linux/vmlinux | grep -c debug
grep -n "CONFIG_DEBUG_INFO_NONE" out/mainline/linux/.config
```

```text
0
6918:CONFIG_DEBUG_INFO_NONE=y
```

.debug 段计数为零，配置里 DEBUG_INFO_NONE,这棵主线内核压根没编调试信息，addr2line 只能靠符号表回函数名与文件名，文件名还只有不带目录的 basename,file:line 无从谈起。想要行号，得开 CONFIG_DEBUG_INFO 重编内核再重跑 addr2line。不过实战里这个缺口没那么疼：内核报告自带 kallsyms,PC is at 某某函数+偏移 这一行就是内核替咱们算好的符号；addr2line 的主战场是日志里只剩十六进制地址、或需要精确到源码行的场合。真要单步进内核函数，那已经不是读日志的事，kgdb 在 [内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) 与 [驱动开发入门](../kernel/07_driver_basic.md) 等着咱们。

## 四、噪音与信号：哪些失败行不用管

真实日志里混着大量带 error 字样的行，新手容易见一行慌一行。咱们这份记录单是 probe failed 就有七八处，系统照样跑到了 login。

deferred probe 咱们这份实录里就有这么一行:

```text
[   12.382860] platform sound-wm8960: deferred probe pending: fsl-asoc-card: snd_soc_register_card failed
```

机制一句话：驱动 probe 时依赖还没到位，返回 EPROBE_DEFER,内核记下来稍后重试，defer 意味着它在等依赖,probe 队列稍后会重试。判断法咱们逐条看它后来解除没有，/sys/kernel/debug/devices_deferred 列着未决名单。这份实录自己就是反面教材:sound-wm8960 的 defer 从 12.38 秒挂上，一路悬到关机前(最后的时间戳 72.8 秒)都没清——会话末尾那条 `cat /sys/kernel/debug/devices_deferred | grep -v sound-wm8960 | grep -c .` 数出 DEFER_EXTRA=0，这个零是把 sound-wm8960 排除掉之后才数出来的，名单里其实一直挂着它。悬着不落，就是链路没通的样子，与本节末尾把 wm8960 判成链路失败正好凑成一对；除 wm8960 这类真缺依赖的之外，启动稳定后名单里其余条目应已清空，真碰上悬着不落的，再去查它等的依赖(时钟、DMA、编解码器)缺了哪个。

固件加载失败的判读，咱们看的是相邻两行摆在一起的证据:

```text
[   12.378328] Goodix-TS 1-005d: Direct firmware load for goodix_911_cfg.bin failed with error -2
[   12.382519] input: Goodix Capacitive TouchScreen as /devices/platform/soc/2100000.bus/21a4000.i2c/i2c-1/1-005d/input/input2
```

咱们拿到 -2 先认码:它是 ENOENT,文件不存在；要是 -12(ENOMEM)或别的码，含义就换成内存不足或读取出错，排查方向完全不同。咱们更要盯的是紧挨着的下一行：触摸屏的 input 设备照样注册成功了，说明缺的只是可选配置固件，链路没断。同一份日志里 sdma 那行 external firmware not found, using ROM firmware 则是明说的回退，外部固件没有就用 ROM 里的，连失败都算不上。

模拟环境特有的那类，症状是 error -110(ETIMEDOUT)。这份 QEMU 记录笔者 grep 过 unimplemented，计数为零，客户机串口里不会出现这个词，QEMU 没建模的外设不点名，只在 probe 超时里现形。这一族清一色 -110:mxs-dma、pxp、mxs-dcp,外加 spi-nor,根因都是驱动在零读桩上等完成位置位，永远等不到。imx_thermal 是单独一种，它抱怨校准数据无效，因为虚拟机里 OCOTP 熔丝盒没有数据。pwm-imx27 那两行 software reset timeout 则要反着读:PWM 已被 patches/qemu 的 0003 号补丁建成纯寄存器存储模型，SWR 复位位写 1 读 1、永不清零，所以警告行照样出现，probe 却继续走完——同一份会话后头咱们自己断言过 /sys/class/pwm/pwmchip0 存在，PWM=yes，链路活着。这些行搬回实际的板子上，含义就翻转成真失败，得一个个查。哪些外设被模拟器建模到了哪一层，emu 卷的三档地图(真模型、桩、空气)给了完整的核对方法。

::: warning 虚拟机里的失败行不能照搬去修驱动
在 QEMU 记录里看到 -110 与 reset timeout,先确认这个外设是不是模拟器根本没建模，再决定要不要动代码；拿着虚拟机的日志去改在实际的板子上跑得好好的驱动，是咱们最容易白忙的方向。
:::

最后给判据，也是本节的收束:单行失败与链路失败是两种世界。咱们这份日志里 wm8960 probe 失败(-22),往下翻到 ALSA device list 只剩 #0: ASRC-M2M,声卡没注册成，这是链路失败，后果是没声音，但系统照常启动；Goodix 丢了一行固件加载失败，input 设备照样注册，链路活着。判断动作就一条：grep 出失败行后，顺着它往下游看一眼，设备节点、声卡列表、网络接口，起没起来。一个驱动 probe 失败但系统继续走，与卡住不动，处理它们的优先级天差地别。

## 五、截一段能用的日志

您终有一天要拿日志去问人、提 Issue。截得好，一轮往返就定位；截得差，对面只能回一句"贴完整日志"。咱们按四要素自查。环境与版本:Linux version 行自带内核版本、编译器、日期，别把它截掉，虚拟机还是实际的板子也要说明，因为上一节刚讲过，同一个失败行在两种环境里含义相反。完整无删减：从上电或内核第一行，到卡住或崩溃的那一行，带时间戳原样贴；实在太长要省略中间，就在截断处写一行省略标注，悄悄删行是大忌，线索往往就藏在被删的那几行里。复现步骤：干了什么、敲了什么命令、第几步出的事。期望与实际：您预期看到什么，实际看到什么，一句话各说清。

记录手法前面的章节教过，咱们直接给命令:实际串口用 `picocom -b 115200 /dev/ttyUSB0 | tee boot.log`,细节在 [启动与调试](../practical/03_boot_and_debug.md);QEMU 直启的串口走的是进程 stdout,交互跑 run-qemu.sh,输出只在终端上滚动，不产生任何文件;要留档，用 `run-qemu.sh --smoke --log=路径` 把串口收进文件(默认写进 out/qemu/uart.log)，或像 e2e-test.sh 那样做整段重定向，本篇的 qemu-e2e.log 就是这么收下来的。提 Issue 前把这四要素凑齐。[内核启动与调试](../kernel/08_kernel_boot_debug.md) 收尾也强调遇到问题先看日志;本篇给它补上的,就是怎么看的那一半操作细节。

## 速查表：看到什么，去哪章

| 看到什么 | 根因方向 | 去哪章 |
|---|---|---|
| 上电后串口零输出 | 串口接线、波特率、烧写问题 | [串口工具使用](../start/04_serial_tools_minicom.md)、[U-Boot 调试命令](../uboot/09_debugging_commands.md) |
| 卡在 U-Boot 或 tftp 超时 | 环境变量、网络、镜像加载 | [U-Boot 调试命令](../uboot/09_debugging_commands.md) |
| Starting kernel 后无输出 | console 参数、设备树、早期初始化 | [内核启动与调试](../kernel/08_kernel_boot_debug.md) |
| VFS: Cannot open root device | root= 参数、分区、块设备驱动 | [内核启动与调试](../kernel/08_kernel_boot_debug.md)、[Buildroot 调试与排错](../buildroot/10_debugging.md) |
| probe failed 单行，系统继续走 | 多为噪音，按第四节判链路 | 本篇第四节、[内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) |
| Oops 或 panic 现场报告 | PC 定函数，地址落回源码 | 本篇第三节、[内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) |
| login 后程序行为异常 | 用户态问题，strace 或断点 | [strace、日志与 coredump](02_strace_log_coredump.md)、[gdbserver 远程调试](01_gdbserver_remote_debug.md) |
| 只在 QEMU 里复现的怪象 | 外设建模边界，桩与空气 | [QEMU 板级模拟卷](../emu/) |

## 继续学习

- 上一篇:[02 程序在板上崩了：strace、日志与 coredump](02_strace_log_coredump.md),三件更轻的工具，本篇 login 之后的那半场归它
- 下一篇：调试卷到这里收尾。三篇合起来是一整套分工：日志定方向，strace 看系统调用，gdbserver 下断点；回 [调试卷目录](index.md) 可以整体回顾。接下来咱们的学习主线进驱动开发卷与工程实战，把调试功夫用在真刀真枪的代码上
- 深读:启动全流程的逐阶段机制看 [内核启动与调试](../kernel/08_kernel_boot_debug.md);引导阶段的命令箱是 [U-Boot 调试命令](../uboot/09_debugging_commands.md);内核态深入(dmesg、动态调试、kgdb)在 [内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) 与 [驱动开发入门](../kernel/07_driver_basic.md);崩溃报告三路互证的完整演绎在 [QEMU 板级模拟卷](../emu/)
