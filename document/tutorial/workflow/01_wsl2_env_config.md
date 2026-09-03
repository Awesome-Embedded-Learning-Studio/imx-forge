---
title: WSL2 环境配置：网络、防火墙与存储位置
---

# WSL2 环境配置：网络、防火墙与存储位置

> 本篇是开发环境配置卷的第一篇，只管 WSL2 本身的配置：网络模式、防火墙放行、存储位置。这几块配好之后，下一篇的编辑器接入、板子的 NFS/TFTP 启动才有落脚点。边界也说清楚：编辑器接入归 02、串口归 03、clangd 与构建任务归 04/05、文件传输归 06；NFS 服务端全流程与内核侧网络启动分别在 rootfs/05 和 kernel/06，每块给到链接，细节您跳过去看。

::: info 您将学到
- 把 WSL2 切到 mirrored 网络模式，并用 WSL 侧 `ip addr` 与 Windows 侧 `ipconfig` 的地址对照验证生效
- 给 TFTP（UDP 69）与 NFS 建带 `-Profile Any` 的 Windows 防火墙放行规则，理解规则的 Profile 覆盖与 Public 网桥的关系
- 在 `/etc/nfs.conf` 里固定 mountd/lockd/statd 端口，并用 `rpcinfo` 核对
- 用实测数据决定源码放哪：9P 的顺序吞吐并不慢，海量小文件慢几十倍
- 识别内核 nfsd 失效的情形，知道 nfs-ganesha 备选路线的存在
:::

::: tip 前置知识·环境
- 前置：WSL2 的安装与基本操作，见 [linux-basics 专栏](../linux-basics/) 的环境篇，本篇不重复入门内容。
- 仓库实路径：`~/imx-forge`（本机即 `/home/charliechen/imx-forge`）。
- 路径上下文声明：本篇的命令分三处执行——WSL 的 Ubuntu 发行版（块首标 `# WSL ~/`）、Windows 的管理员 PowerShell（标 `# Windows PowerShell`）、板端串口（标 `# 板端 /`，咱们只做连通验证）；用不到交叉工具链，需要的只是 WSL2 本身和 Windows 管理员权限。
:::

## 一、为什么网络模式是第一块基石

咱们最容易犯的直觉错误，是把 WSL2 当成 Windows 里的一个程序。它其实是一台完整的虚拟机：自己的内核、自己的网络栈，本机 `uname -r` 看得明明白白（6.18.33.2-microsoft-standard-WSL2）。默认的 NAT 模式下，这台虚拟机藏在 Windows 身后的一段内网地址里，Windows 访问它要过一道地址转换；而咱们真正的客户端是开发板，板子在局域网里发出 TFTP 请求，请求根本到不了 WSL 里面，ping 不通、挂不上，后面一切免谈。

mirrored 模式解决的就是这件事：WSL2 直接镜像 Windows 的网卡，两边共享同一组地址，localhost 也互相直通。02 篇咱们要做的 ssh 接入、板子要走的 NFS/TFTP 启动，全都立在这块地基上；地基不稳，后面每一篇的排障都会平白多一层噪声。

配置写在 Windows 用户目录下的 `.wslconfig`，本机的实文件 131 字节，笔者原样贴出来：

```ini
# Windows 用户目录：C:\Users\CharlieChen\.wslconfig（本机实文件原样）
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=false

[wsl2]
memory=54GB
processors=16
swap=16GB
```

您大概注意到了文件里有两段同名的 `[wsl2]`，这是不同时间两次编辑留下的痕迹。两组键互不重叠，因此都在生效，咱们可以用两条命令核实：`free -h` 显示总内存 52Gi、`nproc` 输出 16，对应第二段的资源限制；第一段的 mirrored 是否生效，看下面的地址对照。新建文件时写成一个块更清爽。

改完配置要重启 WSL 才生效：

```powershell
# Windows PowerShell
wsl --shutdown
wsl
```

::: warning 未实测标注
`wsl --shutdown` 会终止整个 WSL 实例，包括咱们正在里面跑的采集会话，这两条无法在本环境演示；步骤本身是微软文档的标准流程，以它为准。
:::

生效与否，咱们用两侧对照来验证。WSL 侧：

```bash
# WSL ~/
ip -4 addr show
```

```text
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 2800 ...
    altname enxf217449dda20
    inet 10.147.20.122/24 brd 10.147.20.255 scope global noprefixroute eth1
5: eth2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
    altname enxf8ce210052ea
    inet 192.168.1.5/24 brd 192.168.1.255 scope global noprefixroute eth2
# ……lo 与其余字段省略……
```

Windows 侧咱们不用切窗口，WSL 里可以直接调 Windows 自带的 ipconfig.exe（在 Windows 终端里跑就没有编码问题）：

```bash
# WSL ~/
/mnt/c/Windows/System32/ipconfig.exe
```

```text
# 原始输出的中文标签是 GBK 编码，在 WSL 终端里显示为乱码；以下只保留能原样核对的字段：
ZeroTier One [9bee8941b5706ef3]
IPv4 地址 10.147.20.122   子网掩码 255.255.255.0   默认网关 25.255.255.254
```

对照的结果很直观：同一个地址 10.147.20.122，同时挂在 Windows 的 ZeroTier 适配器和 WSL 的 eth1 上；WSL 侧另有 eth2 拿着局域网地址 192.168.1.5，这是 Windows 实体网卡的镜像。mirrored 生效的形态就是这样；若还在 NAT 模式，咱们只会看到一块持着 172.x 地址的 eth0，Windows 侧也找不到任何与它重合的地址。

::: warning Mirrored 不是万能
Mirrored 模式下，Windows 防火墙的过滤会作用到 WSL 这一侧的入站流量，原本能通的端口反而可能被挡掉。本机的 `.wslconfig` 里写的还是 `firewall=false`，但既有的 NFS 排查记录（rootfs/05）表明放行规则一条都省不了。咱们切换完务必按下一节复查防火墙。
:::

模式原理与 NAT/mirrored 的完整对比，咱们放到 kernel 卷去讲，深读见 [kernel/06_wsl_network_boot](../kernel/06_wsl_network_boot.md)。

## 二、防火墙放行：TFTP 与 NFS

板子能看到 WSL 之后，第二道门是 Windows 防火墙。TFTP 走 UDP 69，防火墙默认拦入站，这条好办，直接放行；NFS 麻烦在 mountd、lockd、statd 默认拿随机端口，咱们没法预先放行一个不知道的端口号。所以手法分两条：TFTP 直接放行，NFS 固定端口再放行。

### TFTP：放行 UDP 69

以管理员身份开 PowerShell：

```powershell
# Windows PowerShell（管理员）
New-NetFirewallRule -DisplayName 'TFTP-UDP-69' -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow -Profile Any
```

::: tip 一定用 -Profile Any
规则只在其 Profile 覆盖当前活动网络类别时生效。Mirrored 模式下，Windows 网桥可能被归类为 Public 网络，`-Profile Any` 把 Domain/Private/Public 三种一次兜住，还让 `Get-NetFirewallRule` 的 Profile 字段一眼可核对；用 GUI 或照抄别处教程建的规则可能没勾全 Public，别依赖默认。规则建了却不通，咱们的第一怀疑就是它；下面 NFS 那组规则同理。
:::

TFTP 还有一个目录权限的坑：板子以匿名用户访问 TFTP 根目录（本机是 `/home/charliechen/tftp`），路径上的父目录必须有其他用户可进入的权限，咱们补一条：

```bash
# WSL ~/
chmod o+x /home/charliechen
```

TFTP 服务端的完整配置与启动流程归 [kernel/06_wsl_network_boot](../kernel/06_wsl_network_boot.md)，咱们不在这里重复。

### NFS：把随机端口固定住

为什么必须固定端口，咱们看一眼没做固定时的 `rpcinfo` 就明白了，本机当前恰好处于这个状态：

```bash
# WSL ~/
rpcinfo -p localhost
```

```text
   program vers proto   port  service
    100000    4   tcp    111  portmapper
    100000    4   udp    111  portmapper
    100024    1   udp  46272  status
# ……其余行省略……
```

status（即 statd）落在 46272，一个每次重启都会变的口子。防火墙规则是静态的，端口却在滚动，这套组合注定时通时不通。咱们把端口固定进 `/etc/nfs.conf`（部分发行版在 `/etc/default/nfs-kernel-server`）：

```ini
# WSL /etc/nfs.conf
[mountd]
port=20048
[lockd]
port=32803
udp-port=32769
[statd]
port=32765
```

改完重启 nfs-server，咱们再跑一次 `rpcinfo`，mountd、status、nlockmgr 应当稳定落在 20048、32765、32803，rootfs/05 里有完整的验证输出可对照。本机的 NFS 走的是第四节的 ganesha 路线，`/etc/nfs.conf` 里因此没有这些 port 行（只剩 `[mountd]` 段的 `manage-gids=y`），上面那份 rpcinfo 就是未固定的现状，缘由第四节展开。道理是同一个：服务端用什么端口，防火墙就放行什么端口。

### 对应端口逐个放行

```powershell
# Windows PowerShell（管理员）
New-NetFirewallRule -DisplayName 'NFS-TCP-111'   -Direction Inbound -Protocol TCP -LocalPort 111   -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-UDP-111'   -Direction Inbound -Protocol UDP -LocalPort 111   -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-TCP-2049'  -Direction Inbound -Protocol TCP -LocalPort 2049  -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-mountd'    -Direction Inbound -Protocol TCP -LocalPort 20048 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-lockd-TCP' -Direction Inbound -Protocol TCP -LocalPort 32803 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-statd-TCP' -Direction Inbound -Protocol TCP -LocalPort 32765 -Action Allow -Profile Any
```

NFS v3 同时用 TCP 与 UDP，上面补了 UDP 的 111，其余 UDP 端口您按同样格式追加即可。

### Public 网桥与验证

放行了仍不通，咱们回到主机侧查网桥的网络类别：`Get-NetConnectionProfile` 若显示某适配器的 NetworkCategory 为 Public，而规则的 Profile 没盖住 Public（GUI 或照抄别处教程建的规则常没勾全），规则就不生效。补救有两条路：把网桥改成 Private（`Set-NetConnectionProfile -InterfaceAlias "网桥别名" -NetworkCategory Private`），或者给既有规则补 Profile（`Get-NetFirewallRule | Where-Object {$_.DisplayName -like "NFS*"} | Set-NetFirewallRule -Profile Any`）；后者不动网络类别，更省事，也是本仓采用的写法。板子上的验证更硬：咱们在 U-Boot 里 ping 主机、tftp 拉一个文件，比任何主机侧检查都更接近最终目标。

::: warning 未实测标注
本节的 `New-NetFirewallRule`、`Set-NetConnectionProfile` 与 `Get-` 系验证要在 Windows 的管理员 PowerShell 里执行，采集环境是 WSL 内的普通 shell，咱们开不了管理员会话；命令与参数以 [rootfs/05](../rootfs/05_nfs_wsl_troubleshoot.md) 的历史验证记录为准（含 NetworkCategory 显示 Public、规则补 Profile Any 后恢复连通的完整输出）。
:::

::: warning 未实测标注
从板子 ping 主机、tftp 拉文件、挂载 NFS 需要实际的板子与串口线，咱们在本环境验证不了；验证参数以 rootfs/05 的记录为准：主机 192.168.60.1、板子 192.168.60.200，bootargs 的 nfsroot 指向 `/home/charliechen/imx-forge/rootfs/nfs`。
:::

## 三、存储位置：源码别放 /mnt/c

网络配好之后还剩一块容易被忽视的配置：代码放哪。`/mnt/c` 看着最顺手，Windows 里直接能看，但它是 9P 文件系统，咱们用 `findmnt` 看原样输出：

```bash
# WSL ~/
findmnt -n -o FSTYPE,SOURCE /mnt/c
```

```text
9p     C:\
```

9P 的坏名声是慢，咱们拿真实数字说话。先看容易误导人的顺序大文件：64MiB 的 dd 同步写，原生 ext4 的家目录 144 MB/s，`/mnt/c` 反而跑出 216 MB/s——这个测试照不出差距，甚至倒挂，一个说得通的解法是同步标志的透传：`oflag=dsync` 下 ext4 每次写都等到数据真正落到盘上，9P 这边可能没把 O_DSYNC 透传给 Windows，216 MB/s 里或许掺着对面缓存的成分。想验证可以再跑一条不带 oflag 的对照，若 /mnt/c 速度不变而家目录明显变快，就支持这个解释；您要是拿顺序写当证据，结论会正好反掉：

```bash
# WSL ~/（测 /mnt/c 时输出文件要放到它下面用户可写的目录里：/mnt/c 根就是 C:\ 根，普通用户没有在那里建文件的权限）
dd if=/dev/zero of=~/ddtest bs=1M count=64 oflag=dsync
dd if=/dev/zero of=/mnt/c/Users/CharlieChen/ddtest bs=1M count=64 oflag=dsync
```

两行输出咱们按执行顺序对号：第一行是 `~/` 家目录（ext4），第二行是 `/mnt/c`（9P）：

```text
67108864 bytes (67 MB, 64 MiB) copied, 0.466311 s, 144 MB/s
67108864 bytes (67 MB, 64 MiB) copied, 0.310476 s, 216 MB/s
```

真正的差距在海量小文件。咱们在同一台机器上连续创建 1000 个小文件，家目录与 `/mnt/c` 两处各跑一遍同一条循环：

```bash
# WSL ~/（测 /mnt/c 时把这条循环挪到 /mnt/c 的任一可写目录下执行）
time (for i in $(seq 1 1000); do echo x > f$i; done)
```

家目录 0.034 秒（CPU 占比 89%），`/mnt/c` 要 1.910 秒（CPU 占比只有 9%），咱们拿到的是五十多倍的差距，而且 `/mnt/c` 那边 CPU 大部分时间在闲着，时间全耗在 9P 协议的往返上。编译内核、编译 buildroot 恰好就是这种负载，几万个源文件反复 stat、open、write，每个动作都要跨一次协议边界；源码放 `/mnt/c` 编译慢 5 倍以上，是本仓此前记录的经验值（见 [linux-basics ch01](../linux-basics/01-environment/ch01-wsl2.md)，不是计时实测），说的正是这种工作负载，方向与这组数字一致。

比慢更隐蔽的是大小写。Linux 内核源码里存在同目录、仅大小写不同的文件，比如 `net/netfilter/` 下 `xt_DSCP.c` 与 `xt_dscp.c` 并存，uapi 头文件里还有 `xt_CONNMARK.h`/`xt_connmark.h` 一类；Windows 文件系统大小写不敏感，会把它们折叠成同一个文件，构建直接错乱；而且报错的位置离根因很远，咱们排查时得多绕几步。

::: danger
内核源码、buildroot 源码、任何 git 仓库，一律 clone 到 WSL 原生路径（`~/`），不要放到 `/mnt/c/` 或 `/mnt/d/`。本仓就在 `~/imx-forge`（即 `/home/charliechen/imx-forge`）。Windows 侧您偶尔要看文件，走 `\\wsl$` 路径访问，别把工作目录反过来搬过去。
:::

## 四、内核 NFS 不可用时的备选：nfs-ganesha

绝大多数环境到第二节就通了，极少数 WSL2 内核环境下 `nfs-kernel-server` 的 export 表是空的，内核 NFS 服务直接失效。咱们判断只要一条命令，本机当前实测的结果连文件都不存在：

```bash
# WSL ~/
cat /proc/fs/nfsd/exports
```

```text
cat: /proc/fs/nfsd/exports: No such file or directory
```

这台机器因此改走过用户态的 nfs-ganesha 加 VFS FSAL，绕开内核 nfsd，端口同样要固定：本机 `/etc/ganesha/ganesha.conf` 里写着 `NFS_Port = 2049`、`MNT_Port = 20048`，防火墙规则沿用第二节那套。这台机器的现状有点绕，得拆开说。这一段得按排查记录读，不能当现状：当前会话里 nfs-ganesha 没有在跑，本次开机它启动 6 秒就以 status=2 退出（`journalctl -u nfs-ganesha` 可查），localhost 上应答的 mountd 也还在随机端口滚动。起不来的死因，笔者在 `/var/log/ganesha/ganesha.log` 的结尾翻到了：`Cannot bind NFS tcp6 socket, error 98 (Address already in use)`，随后一行 `FATAL ... Error binding to V6 interface. Cannot continue.`——2049 的 tcp6 端口已被占用，`rpcinfo` 里 nfs 恰好注册在 2049 上，两边互为印证。真要排查就照下面那份记录的路数走。

有一个已经验证过的坑，咱们最好提前记下：用 bind-mount 换过 NFS 源目录之后必须 restart nfs-ganesha，否则板子挂载会报 ESTALE。ganesha 的完整配置与排查过程在 [notes/2026-06-08 的 ganesha 排查记录](../../notes/2026-06-08-wsl2-nfsroot-ganesha-troubleshoot.md)，ESTALE 重启坑的完整验证记录在 [notes/2026-06-23](../../notes/2026-06-23-nfs-ganesha-bindmount-estale.md)，本篇不展开；内核 nfsd 路线的 NFS 排查全景仍是 [rootfs/05](../rootfs/05_nfs_wsl_troubleshoot.md)。

## 踩坑速查表

下面九条里，七条来自本仓已验证的排查记录，编译慢 5 倍以上那条是既有章节的经验值，构建文件错乱那条是大小写折叠的机制推演，这两条没有排查实测兜底；按现象归类排序，咱们遇到问题时从第一列对号入座：

| 现象 | 根因 | 解法 |
|------|------|------|
| 开发板 ping 不到 WSL2 | NAT 模式，WSL2 藏在内网 | `.wslconfig` 切 `networkingMode=mirrored` |
| TFTP 超时拉不到 DTB | Windows 防火墙拦 UDP 69 | 加 `-Profile Any` 的 UDP 69 放行规则 |
| TFTP 报 Permission denied | TFTP 根目录父目录无 o+x | `chmod o+x /home/用户名` |
| NFS 挂载超时/拒绝 | mountd 随机端口被防火墙挡 | `/etc/nfs.conf` 固定端口 + 防火墙放行 |
| NFS 规则建了仍不通 | 网桥 Public，规则的 Profile 没盖住它 | 规则补 `-Profile Any` 或改网桥为 Private |
| 编译慢 5 倍以上 | 源码在 `/mnt/c/` | 移到 WSL2 原生 `~/` |
| 内核构建文件错乱 | `/mnt/c/` 大小写不敏感，xt_DSCP.c/xt_dscp.c 冲突 | 源码移出 `/mnt/c/` |
| nfs-kernel-server export 表空 | WSL2 内核 nfsd 失效 | 换 nfs-ganesha + VFS FSAL |
| 换 NFS 源后挂载 ESTALE | ganesha 未重载 bind-mount | `restart nfs-ganesha` |

## 继续学习

- 下一篇：[02_vscode_remote_ssh.md](02_vscode_remote_ssh.md)，环境的地基打好，接着把编辑器搬进 WSL。
- 深读 NFS 服务端全流程：[../rootfs/05_nfs_wsl_troubleshoot.md](../rootfs/05_nfs_wsl_troubleshoot.md)
- 深读 TFTP 启动与内核侧网络：[../kernel/06_wsl_network_boot.md](../kernel/06_wsl_network_boot.md)
- WSL2 与 Linux 基础入门：[../linux-basics/](../linux-basics/)
