---
title: 换条路：tftp 网络加载，迭代不再反复烧卡
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 换条路：tftp 网络加载，迭代不再反复烧卡

> 咱们这一篇解决迭代期最磨人的一段路：内核改一版，不再烧一遍、重启一遍。链路四步：U-Boot 起网卡，拿 IP，tftp 拉内核与设备树，bootz 引导，根文件系统原地不动。烧录那条老路在 [产物验证与烧录](04_verify_and_flash.md) 已经走完，本篇站在它的肩膀上，把内核与设备树的搬运通道从 eMMC 换成网线。主机侧的服务、板端的命令、日常迭代的循环都在这里落到位，命令级的排错交给 [调试命令速查](14_debug_reference.md)。

## 一、为什么开发期用网络

把 defconfig 翻到底，咱们找不到一行 TFTPBOOT，可 U-Boot 的命令行里 tftpboot 就在那儿待着。命令在不在，咱们拿 grep 核实：

```bash
# 主机 ~/imx-forge
grep -n "ETHPRIME\|FEC_MXC\|CONFIG_CMD_DHCP\|CONFIG_CMD_PING\|TFTPBOOT" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig
```

```text
33:CONFIG_CMD_DHCP=y
34:CONFIG_CMD_PING=y
50:CONFIG_USE_ETHPRIME=y
51:CONFIG_ETHPRIME="eth1"
71:CONFIG_FEC_MXC=y
```

DHCP 与 ping 两行在，网卡驱动 FEC_MXC 在，默认网口指定给了 eth1，TFTPBOOT 零命中。tftpboot 命令不靠 defconfig 开，咱们到 cmd/Kconfig 里找它的来路，它跟着网络栈默认进来：

```bash
# 主机 ~/imx-forge
grep -n -A 3 "config CMD_TFTPBOOT" third_party/uboot-mainline/cmd/Kconfig | head -8
```

```text
2277:config CMD_TFTPBOOT
2278-	bool "tftp"
2279-	select PROT_UDP_LWIP if NET_LWIP
2280-	default y
```

default y，网络栈一起，命令就在。咱们记住这个 Kconfig 习惯，多数命令自带默认值，defconfig 只写需要特别表态的行。

再看烧录这条路要付什么代价。内核改一行驱动，咱们得重编 zImage，让板子进烧录模式，借 UMS 把 9261464 字节的产物写进 eMMC，重启，等它起来，然后发现少改一处，再进一次烧录模式。这个字节数是本机 out 树的真实产物，第三节的 ls 里能看到。烧录的单步动作不慢，磨人的是围着它转的一圈物理活，板子断电、拨进烧录模式、烧完再上电复位，每一轮迭代都全额重付。网络加载把这段路换成网线，同样的 9261464 字节从主机的 tftp 目录走 UDP 进板子内存，主机侧只剩一次 cp，时间真正花在编译上。

不走网线也有别的道，咱们比对过：串口的 sz 与 rz 能传文件，可那点带宽拿来搬 9 MB 的内核是折磨。USB OTG 加 uuu 能烧，flash 卷有专章，但每回都得让板子进烧录模式。tftp 的好处是链路常驻，服务开着，网线插着，改完就传，跟迭代期的节奏刚好对上。

链路四步咱们放在这里当地图：第二节让网卡活起来，第三节把主机侧的 tftp 服务搭起来，第四节把拿 IP、拉文件、引导三步一口气走完，引导脚本直接接头文件里现成的那套。

defconfig 第 16 到 18 行还把 CONFIG_BOOTDELAY 设成了 -1，BOOTCOMMAND 只剩一句 echo，意思是没有倒计时、不自动引导，板子每次上电直接停在命令行等着。对网络加载来说这是天生配合，咱们上电就敲命令，不用数着秒按回车去打断自动引导。

## 二、让网卡活起来

网卡要活，两层硬件都得就位。FEC 是 i.MX6ULL 芯片内部的以太网控制器，管 MAC 这一层。PHY 是板子上那颗 KSZ8081，管网线上的模拟信号，两颗芯片靠 MDIO 总线配对。这一层的门道（引脚复用、复位时序、时钟来源）本篇不展开，咱们只取要用的结论：AES 板两个网口都在，两颗 PHY 都在，驱动都编进去了。

设备树这边的现状，咱们拿 grep 露一眼：

```bash
# 主机 ~/imx-forge
grep -n "fec1\|fec2\|ethphy\|ethernet-phy@\|phy-reset" third_party/uboot-mainline/arch/arm/dts/imx6ull-aes.dtsi | head -16
grep -n "ethernet0 = \|ethernet1 = " third_party/uboot-mainline/arch/arm/dts/imx6ul.dtsi
```

```text
161:&fec1 {
165:	phy-handle = <&ethphy0>;
166:	phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;
167:	phy-reset-duration = <200>;
168:	phy-reset-post-delay = <200>;
173:&fec2 {
177:	phy-handle = <&ethphy1>;
178:	phy-reset-gpios = <&gpio5 8 GPIO_ACTIVE_LOW>;
179:	phy-reset-duration = <200>;
180:	phy-reset-post-delay = <200>;
188:		ethphy0: ethernet-phy@2 {
197:		ethphy1: ethernet-phy@1 {
22:		ethernet0 = &fec1;
23:		ethernet1 = &fec2;
```

eth0 与 eth1 的编号来自 imx6ul.dtsi 第 22、23 行的别名，ethernet0 指给 fec1、ethernet1 指给 fec2，U-Boot 照别名把 fec1 叫 eth0、fec2 叫 eth1。第一节 grep 里那行 CONFIG_ETHPRIME 指到 eth1，到这里就对上了：咱们把网线插 fec2 这个口，默认网卡就是它。复位给的是 200 毫秒加 200 毫秒的余量（grep 里那四个值），时钟走芯片内部 PLL 生成的 50 MHz，本篇直接取用。MDIO 总线由两个 FEC 共用，defconfig 第 68 行的英文注释交代了这件事，Both FECs share the MDIO bus，还说让 DM 接管总线生命周期，交接给内核时好把状态收拾干净。PHY 驱动编的是 MICREL 这一类（defconfig 第 74、75 行的 CONFIG_PHY_MICREL 与 CONFIG_PHY_MICREL_KSZ8XXX），对着 KSZ8081 这颗芯片。

MAC 地址也交代一句，include/configs/mx6ull_aes_emmc.h 第 40 到 42 行给三个名字都留了预置值，eth0addr、eth1addr、ethaddr，都是 b8:ae:1d 打头。U-Boot 拿不到有效 MAC 时，网络命令常见的反应是报 No ethernet found，预置值就是为了让网络命令随时能用。咱们在实际的板子上调试时要是碰上这句报错，看 MAC，再查链路。

验收点就是 ping 通主机。CONFIG_CMD_PING=y 已经在第一节的 grep 里露过面，板端敲 ping 主机地址，咱们看回显里那句 host 加地址加 is alive，就算通了。完整回显的样子第四节给。

## 三、主机侧搭 tftp 服务

tftp 是个小协议：UDP，69 号端口，板端发起一个读请求，主机把服务目录里的文件按块递过去。它没有鉴权，没有目录遍历，能做的就是把一个目录里的文件递出去，迭代期要的恰恰是这份简单。主机侧的服务端咱们用 tftpd-hpa，Ubuntu 仓库里最常见的那一个。安装命令是 sudo apt install tftpd-hpa，本机已经装过了，现状咱们照实交代：

```bash
# 主机 ~/imx-forge
dpkg -l tftpd-hpa 2>/dev/null | tail -1
which tftpd tftp in.tftpd 2>/dev/null
ls /var/lib/tftpboot 2>&1 | head -3
```

```text
ii  tftpd-hpa      5.2+20150808-1.4build1 amd64        HPA's tftp server
/usr/sbin/in.tftpd
ls: cannot access '/var/lib/tftpboot': No such file or directory
```

有意思的在后两行。教程里常提的默认目录 /var/lib/tftpboot 不存在，服务端二进制却好好待着。目录不在，服务是不是就死了？咱们把配置和进程翻出来看：

```bash
# 主机 ~/imx-forge
cat /etc/default/tftpd-hpa
ps -o pid,user,cmd -C in.tftpd
```

```text
# /etc/default/tftpd-hpa

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/home/charliechen/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
    PID USER     CMD
    333 root     /usr/sbin/in.tftpd --listen --user tftp --address 0.0.0.0:69 --secure /home/charliechen/tftp
```

答案在配置里：这台机器的服务目录被指到了 /home/charliechen/tftp，不是包的默认值，所以默认目录不存在不奇怪。服务也活着，root 起的 in.tftpd 进程监听 0.0.0.0:69，选项里带着 --secure，目录跟配置一致。这一幕的教训值得咱们记下：默认目录别背，拿配置文件说话，/etc/default/tftpd-hpa 这四行把用户、目录、地址、选项交代得清清楚楚。

端口也核一下，顺手拿一次真实下载把链路走通。tftp 命令行的客户端这台机器上没装（前面那个 which 只翻出了 in.tftpd），curl 反而会说 tftp 这门话，咱们拿它当探针，从本机拉一个服务目录里现成的文件：

```bash
# 主机 ~/imx-forge
ss -ulnp | grep ":69"
curl -s tftp://127.0.0.1/hello_app -o /dev/null -w 'downloaded %{size_download} bytes via tftp\n'
```

```text
UNCONN 0      0               0.0.0.0:69         0.0.0.0:*
downloaded 2701288 bytes via tftp
```

2701288 字节，跟服务目录里那个 hello_app 的实际大小一致，一次完整的 tftp 会话在主机上跑通了。主机侧到这里只剩一件事，咱们把内核产物放进服务目录，名字起对。仓库的 out/release-latest/images/ 里放着两个软链，指回内核树的构建结果：

```bash
# 主机 ~/imx-forge
ls -lL out/release-latest/images/
```

```text
total 9084
-rw-r--r-- 1 charliechen charliechen   35519 Nov  4 00:19 imx6ull-aes.dtb
-rwxr-xr-x 1 charliechen charliechen 9261464 Nov  4 00:22 zImage
```

zImage 9261464 字节，设备树 35519 字节，一会儿板端拉完，对得上的就是这两个数。

```bash
# 主机 ~/imx-forge
cp out/release-latest/images/zImage /home/charliechen/tftp/zImage
cp out/release-latest/images/imx6ull-aes.dtb /home/charliechen/tftp/imx6ull-aes.dtb
```

名字不是随便起的。头文件里 image=zImage、fdt_file=imx6ull-aes.dtb（include/configs/mx6ull_aes_emmc.h 第 52、56 行），咱们把目录里的名字起对，板端 tftpboot 按名字要文件才要得着。本机的服务目录权限是开放的，cp 不用 sudo，换成包默认目录时它归 root 属主，拷贝就得带上 sudo。

::: warning --secure 的边界
in.tftpd 带着 --secure 跑，意思是服务端把根限制在服务目录里，出不去。文件放在目录外面，或者请求里带上 ../ 这类路径，服务端直接回 File not found。后果是板端拉文件永远失败，根因多半在路径上，排查时咱们看 TFTP_DIRECTORY 指到哪，再核对文件名在不在那个目录里。
:::

::: warning 服务启停与防火墙，按发行版对表
systemctl restart tftpd-hpa、ufw allow 69/udp 这类命令在本机没有执行过（本机 ufw 没装），咱们不把它们写成跑过的样子。换到全新安装的 Ubuntu，包默认目录是 /var/lib/tftpboot，服务默认开机自启，动手时以发行版的包文档为准。
:::

WSL2 与 Windows 的场景咱们单独说一句。WSL2 的网络形态跟物理机不同，Windows 防火墙拦 UDP 入站是高频翻车点——tftp 会话由板端发起，第一个入站包落在主机侧就被丢了，板端看到的是下载卡在同一处反复重试。WSL2 的网络与文件系统差异，工作流卷的 [WSL2 环境配置](../workflow/01_wsl2_env_config.md) 有交代。WSL2 加 tftp 的完整搭建与防火墙排查，内核卷有一篇专门的 [网络启动（WSL2）](../kernel/15_wsl_network_boot.md)。

## 四、板端三连

### 拿地址

第一连是拿地址。四个关键值各有出处，咱们先列成表：

| 名字 | 值 | 出处 |
|------|------|------|
| ${loadaddr}（内核落点） | 0x82000000 | 顶层 Kconfig 的 SYS_LOAD_ADDR 默认值，defconfig 没有覆盖 |
| ${fdt_addr}（设备树落点） | 0x83000000 | include/configs/mx6ull_aes_emmc.h 第 57 行 |
| ${console} 与波特率 | ttymxc0、115200 | 同上文件第 53 行，波特率来自 baudrate 变量 |
| U-Boot 自身驻留 | 0x87800000 起 | board/nxp/mx6ull_aes_emmc/Kconfig 的 TEXT_BASE |

${loadaddr} 的来历值得展开一眼，因为它不在任何头文件里——defconfig 里咱们 grep 不到 SYS_LOAD_ADDR，退出码 1，一行都没有，于是 Kconfig 的默认值生效：

```bash
# 主机 ~/imx-forge
grep -n "SYS_LOAD_ADDR" third_party/uboot-mainline/configs/mx6ull_aes_emmc_defconfig; echo rc=$?
grep -n "default 0x82000000" third_party/uboot-mainline/Kconfig
```

```text
rc=1
626:	default 0x82000000 if ARCH_KEYSTONE || ARCH_OMAP2PLUS || ARCH_K3
627:	default 0x82000000 if ARCH_MX6 && (MX6SL || MX6SLL  || MX6SX || MX6UL || MX6ULL)
```

0x82000000 在顶层 Kconfig 里有两条 default，MX6ULL 命中的是第 627 行这条，条件列表里带着 MX6UL 与 MX6ULL，默认落点 0x82000000。内核在 0x82000000，设备树在 0x83000000，U-Boot 自己住在 0x87800000 往上，三块互不踩脚。这张小地图咱们记熟，tftpboot 的回显里马上打照面。

拿地址有两条路。板子和主机插在同一个有 DHCP 的局域网里，咱们敲一条 dhcp 就行，地址、掩码、网关一起回来。板子跟主机网线直连，中间没有 DHCP 服务器，就手动给：

```bash
# 板端 /（U-Boot 命令行）
setenv ipaddr 192.168.1.123
setenv serverip 192.168.1.5
```

192.168.1.5 就是咱们这台开发主机在内网的地址（hostname -I 里就有它，同机另一张网卡是 10.147.20.122），板端的 ipaddr 跟主机同网段即可。还有一个 autoload 变量：dhcp 拿完地址后，U-Boot 会看 autoload 的值，默认接着把 bootfile 变量指定的文件也 tftp 下来，net/net.c 的 net_auto_load 函数管这件事。autoload 设成 no，dhcp 就只管拿地址，文件咱们自己拉，节奏在自己手里。

地址到手，链路通不通当场验一下，板端敲 ping：

```text
=> ping 192.168.1.5
Using ethernet@20b4000 device
host 192.168.1.5 is alive
```

看到 is alive 就算通，这段回显是期望形态，手边没板子没有实际敲过。

### 拉文件与引导

拉文件两连，落点都按表来。tftpboot 不带地址参数时落在 ${loadaddr}，设备树咱们显式给到 ${fdt_addr}：

```bash
# 板端 /（U-Boot 命令行）
tftpboot ${loadaddr} zImage
tftpboot ${fdt_addr} imx6ull-aes.dtb
```

引导这一步咱们不发明新地址，直接对齐仓库里现成的引导脚本。头文件里 eMMC 那套 emmcbootaes 搬运的就是同一对变量，拿 grep 翻出来看：

```bash
# 主机 ~/imx-forge
grep -n "fdt_addr\|loadaddr\|bootz\|mmcargs\|mmcroot\|console=" third_party/uboot-mainline/include/configs/mx6ull_aes_emmc.h | head -20
```

```text
30:	"mfgtool_args=setenv bootargs console=${console},${baudrate} " \
32:	"kboot=bootz \0" \
53:	"console=ttymxc0\0" \
57:	"fdt_addr=0x83000000\0" \
63:	"mmcroot=/dev/mmcblk1p2 rootwait rw\0" \
65:	"mmcargs=setenv bootargs console=${console},${baudrate} " \
66:		"root=${mmcroot}\0" \
67:	"emmcargs=setenv bootargs console=${console},${baudrate} " \
69:	"loademmcimage=ext4load mmc ${emmc_dev}:1 ${loadaddr} /zImage\0" \
70:	"loademmcfdt=ext4load mmc ${emmc_dev}:1 ${fdt_addr} /imx6ull-aes.dtb\0" \
72:		"run emmcargs; " \
76:		"bootz ${loadaddr} - ${fdt_addr};\0" \
77:	"sdargs=setenv bootargs console=${console},${baudrate} " \
79:	"loadsdimage=ext4load mmc ${sd_dev}:1 ${loadaddr} /zImage\0" \
80:	"loadsdfdt=ext4load mmc ${sd_dev}:1 ${fdt_addr} /imx6ull-aes.dtb\0" \
86:		"bootz ${loadaddr} - ${fdt_addr};\0" \
88:		"fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} ${script};\0" \
91:	"loadimage=fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} ${image}\0" \
92:	"loadfdt=fatload mmc ${mmcdev}:${mmcpart} ${fdt_addr} ${fdt_file}\0" \
94:		"run mmcargs; " \
```

第 69、70 行是 eMMC 的搬运，第 76 行是引导，bootz ${loadaddr} - ${fdt_addr}，中间那个减号表示这一段没有 initrd。网络加载跟它只差搬运通道，咱们把 ext4load 换成 tftpboot，文件就从 eMMC 分区换到网线上。bootargs 也不能少，第 65 行的 mmcargs 把 console 与 root 拼好，root 还是 eMMC 第二分区的 /dev/mmcblk1p2，也就是说网络只替掉内核与设备树这两件行李的搬运，根文件系统还在原位。

完整命令串咱们按顺序放这，dhcp 与 setenv 二选一：

```bash
# 板端 /（U-Boot 命令行）
dhcp
tftpboot ${loadaddr} zImage
tftpboot ${fdt_addr} imx6ull-aes.dtb
run mmcargs
bootz ${loadaddr} - ${fdt_addr}
```

回显的期望形态咱们贴出来，拿它对表。tftpboot 会报出服务器与板子的地址、文件名、落点，进度条走完给出字节数，这个数应该跟主机侧文件一致：

```text
Using ethernet@20b4000 device
TFTP from server 192.168.1.5; our IP address is 192.168.1.123
Filename 'zImage'.
Load address: 0x82000000
Loading: ################################################################
done
Bytes transferred = 9261464 (8d5198 hex)
```

9261464 就是第三节 ls 里看到的那个 zImage 大小，括号里的十六进制是 U-Boot 的习惯写法。ethernet@20b4000 这个设备名的来历咱们也顺一下，0x020b4000 是 fec2 的寄存器基地址，ETHPRIME 指定的 eth1 就是它，内核卷的 [网络启动（WSL2）](../kernel/15_wsl_network_boot.md) 贴过的串口记录里正是这个设备名。速度也有一层依据：教科书里的 tftp 一块 512 字节（net/tftp.c 第 123 行的基础值），U-Boot 会跟服务端协商更大的块，net/Kconfig 里 TFTP_BLOCKSIZE 的默认值给到 1468，9 MB 的 zImage 六千多块就搬完了，进度条不会磨蹭。

咱们敲下 bootz，末尾几行回显落到设备树，然后是那句 Starting kernel：

```text
## Flattened Device Tree blob at 83000000
Booting using the fdt blob at 0x83000000
Starting kernel ...
```

::: warning Starting kernel 之后黑屏
bootz 一过，U-Boot 收声，接下来该内核自己说话。屏幕从此不动，根因多半是 bootargs 没设，内核不知道控制台在 ttymxc0，也不知道根文件系统在哪，run mmcargs 那一步跳不得。再一种可能是落点冲突，咱们拿前面那张小地图把 0x82000000、0x83000000、0x87800000 三块核对一遍再重启。
:::

## 五、迭代工作流

循环本身很轻，咱们把四样东西串起来：改内核，编，cp 进服务目录，板端四行命令。zImage 与 dtb 的构建在内核卷的 [编译、外挂模块与 QEMU 首启验收](../kernel/08_dts_build_boot.md) 完成，产物落在 out/linux/arch/arm/boot/zImage 与 arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb，第三节那两个软链指的就是它们。主机侧的搬运是一条 cp：

```bash
# 主机 ~/imx-forge
cp out/release-latest/images/zImage /home/charliechen/tftp/zImage
```

只动了驱动没动设备树的日子，dtb 不用拷，板端也不用拉它，一条 tftpboot 就够。咱们判断两边谁该动，标准是设备树源文件改没改，别靠感觉。

咱们把板端的地址存下来，serverip 与 ipaddr 用 saveenv 写进环境变量，环境变量住在 eMMC 上，defconfig 第 6 到 8 行交代了位置：CONFIG_ENV_OFFSET 是 0x400000（4 MB），CONFIG_ENV_SIZE 是 0x2000（8 KB），也就是从 eMMC 起始数 4 MB 的地方留着 8 KB，特意放在 U-Boot 镜像之后。存完之后，咱们每次上电（BOOTDELAY -1 让板子直接停在命令行）只剩四行：

```bash
# 板端 /（U-Boot 命令行）
tftpboot ${loadaddr} zImage
tftpboot ${fdt_addr} imx6ull-aes.dtb
run mmcargs
bootz ${loadaddr} - ${fdt_addr}
```

这轮设备树没改，咱们删掉第二行，四行变三行。saveenv 的命令细节，[调试命令速查](14_debug_reference.md) 的环境变量一节有现成条目。

排错的入口也交代清楚。板端 ping 不通、下载卡在同一处、File not found，命令级的排查都在 [调试命令速查](14_debug_reference.md) 的网络启动一节，dhcp 与 tftp 的参数、printenv 核对那边都有。主机侧咱们先回第三节的 curl 探针，服务活着还是死了，一条命令见分晓。往后咱们要是连根文件系统也不想再烧，NFS root 把它也搬上网络，rootfs 卷的 [NFS 网络启动排查](../rootfs/05_nfs_wsl_troubleshoot.md) 是入口。循环走到熟，主机侧的全部动作就是一次 cp，板端就是四行命令，eMMC 第二分区里的根文件系统一动不动。

## 继续学习

- U-Boot 命令级的排错与速查（tftp、dhcp、bootz、printenv、saveenv）：[调试命令速查](14_debug_reference.md)
- zImage 与 dtb 是怎么编出来的：[编译、外挂模块与 QEMU 首启验收](../kernel/08_dts_build_boot.md)
- WSL2 下搭 tftp 与防火墙排查的完整走查：[网络启动（WSL2）](../kernel/15_wsl_network_boot.md)
- 主机与板子之间 scp、rsync、NFS root 三条通道的选法：[主机与板子传文件](../workflow/06_host_board_transfer.md)
