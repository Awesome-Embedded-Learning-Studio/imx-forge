# 第 21 章  网络配置

> **Part 5 · 网络与远程**

---

## 引子

你的 Ubuntu 虚拟机能上网了——但它是通过 NAT 上的。
你想让开发板通过网络连到虚拟机，NAT 把它们隔开了。

嵌入式开发对网络的要求比日常上网高得多：
你需要固定 IP 让开发板能找到你，需要桥接模式让设备在同一网段，
需要配置 DNS 让域名解析正常工作。

ip 命令、netplan 配置文件、NetworkManager——
Ubuntu 有不止一种配置网络的方式，
它们各自管辖的范围不同，混用会出问题。

---

## 背景与动机

如果你搜过「Linux 配置 IP」，你会发现一个奇怪的现象——
一半教程在讲 `ifconfig`，另一半在讲 `ip addr`；
一半教你改 `/etc/network/interfaces`，另一半给你一个 YAML 文件。

这不是社区分裂，是时代的断层。

`ifconfig` 属于 `net-tools` 软件包，它最后一个版本停在 2001 年。
二十多年了。
`ip` 命令来自 `iproute2`，从 Linux 2.2 内核时代起就是官方推荐的替代品，
但因为 `ifconfig` 太深入人心，它硬是又活了二十年。
 Ubuntu 20.04 及之后的版本默认不再预装 `net-tools`——你敲 `ifconfig`，系统会告诉你「command not found」。

`ifconfig` 不止是被替代了，是连安装源都快没了。

网络配置文件同样经历了一轮换血。Ubuntu 17.10 引入了 **netplan**——
一个用 YAML 描述网络配置的系统。
在此之前，`/etc/network/interfaces` 是配置网络的唯一入口，
那个文件的语法……怎么说呢，能用，但不够灵活，更不够声明式。
netplan 的设计思路是：你写一份「我要什么样的网络」，它帮你翻译给底层去执行。

但这里有一个我们回避不了的问题——WSL2 和虚拟机的网络架构不同，开发板和主机的网络需求也不同。如果你在做嵌入式开发，NAT 模式下开发板根本找不到你的虚拟机。
你需要桥接，你需要固定 IP，你需要理解这些概念之间的关系。

---

## 概念层

### 网络接口：eth0、ens33 和朋友们

Linux 里每一个网络连接都对应一个「接口」（interface）。
有线网卡通常叫 `eth0` 或 `ens33`，无线网卡叫 `wlan0` 或 `wlp2s0`。

你可能会好奇：为什么有的是 `eth0`，有的是 `ens33`？

这是 systemd 的「可预测命名」（Predictable Network Interface Names）。
老的 `eth0`、`eth1` 是按驱动加载顺序编号的——如果你有两张网卡，换个插槽顺序就变了。
`ens33` 这种名字基于硬件拓扑（总线编号、插槽位置），无论重启多少次都一样。
对服务器和嵌入式设备来说，可预测性至关重要——你不会希望写好的网络配置因为重启后网卡换了名字而失效。

### ip 命令家族：一个命令管一类事

`ip` 是 `iproute2` 工具集的核心。它的设计哲学和 `ifconfig` 完全不同——不是用一个命令管所有事，而是用子命令分工：

```bash
ip addr    → 地址管理（取代 ifconfig 的地址部分）
ip link    → 链路层管理（启停接口、查看 MAC 地址）
ip route   → 路由管理（取代 route 命令）
ip neigh   → ARP 表管理（取代 arp 命令）
```

`ifconfig` 把地址、统计、标志位搅在一块输出，
`ip addr` 只管地址，`ip link` 只管链路状态，`ip -s link` 才显示统计——
信息分层更清晰，脚本解析也更容易。

### netplan：声明式配置的翻译官

你可以把 netplan 想象成一位**翻译官**——
你用 YAML 写一份「我想要什么样的网络」，netplan 帮你翻译给底层的 networkd 或 NetworkManager 去执行。

但「翻译官」这个比喻有一个地方是不准确的：
真正的翻译官是在两种语言之间双向转换，netplan 的翻译是**单向**的——
你写 YAML，netplan 生成 backend 配置，但反过来不会自动同步。
这意味着，如果你用 `nmcli` 直接改了 NetworkManager 的配置，netplan 那边的 YAML 并不知道。
下次 `netplan apply` 一跑，你的修改就被覆盖了。

混用是踩坑的根源。

netplan 的配置文件放在 `/etc/netplan/` 目录下，文件名以 `.yaml` 结尾。
如果有多个文件，按字母顺序合并。Ubuntu 默认只给一个，具体是哪个取决于安装方式：

- **服务器版**（Ubuntu Server）：`00-installer-config.yaml`（22.04）或 `50-cloud-init.yaml`（24.04），renderer 默认是 `networkd`
- **桌面版**（Ubuntu Desktop）：`00-network-manager-all.yaml`，renderer 是 `NetworkManager`

WSL2 的情况比较特殊——WSL2 的网络由 Windows 侧管理，
`/etc/resolv.conf` 和 IP 地址都是动态生成的，一般不需要手动配置 netplan。
如果你在 WSL2 里做嵌入式开发，网络拓扑需要在 Windows 侧解决（比如端口转发或 WSL 的 mirrored 网络模式）。

### DNS 解析：systemd-resolved

Ubuntu 22.04 和 24.04 默认使用 `systemd-resolved` 管理 DNS。
`/etc/resolv.conf` 实际上是一个符号链接，指向 `/run/systemd/resolve/stub-resolv.conf`——
你不需要直接编辑它，DNS 服务器地址由 netplan 配置注入。

查看当前 DNS 状态：

```bash
$ resolvectl status
# 预期输出（截取关键部分）
Global
       Protocols: -LLMNR -mDNS -DNSOverTLS DNS=yes/no
Link 2 (ens33)
    Current Scopes: DNS
         DNS Servers: 8.8.8.8 114.114.114.114
```

### NAT 与桥接：嵌入式开发的分水岭

这里有一个贯穿整章的概念：NAT 和桥接的区别。

你可以把 **NAT**（Network Address Translation）想象成一栋**公寓楼**——
楼里每户人家有自己的内部编号（内网 IP），但对外只有一个大门（一个公网 IP）。
外面的人想寄信给你，只能寄到大楼门口，由物业（NAT 网关）转交。
如果你在公寓楼里，你想让隔壁楼的朋友直接走到你房间——做不到，他只能看到你们楼的大门。

**桥接**（Bridge）则像是**同一街区里的独栋别墅**——
每户人家都有自己的门牌号，而且都在同一条街上（同一网段）。
任何人都可以直接走到你家门口敲门，不需要经过物业。

对于嵌入式开发来说，这个区别是决定性的：
开发板和你的开发机必须在同一网段才能直接通信。
NAT 模式下，开发板看不到虚拟机的内网 IP——
就像你没法给公寓楼里某个房间直接寄信一样。
桥接模式让虚拟机拿到一个和你物理网络同网段的 IP，
开发板就能直接 `ping` 到它，直接 `ssh` 上去。

---

## 实践层

### 4.1  查看当前网络状态

动手改配置之前，先搞清楚现在是什么状况。

```bash
# 查看所有网络接口及其 IP 地址
$ ip addr show
# 预期输出
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:0c:29:ab:cd:ef brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.105/24 brd 192.168.1.255 scope global dynamic ens33
       valid_lft 86123sec preferred_lft 86123sec
```

`lo` 是回环接口（loopback），`127.0.0.1` 永远指向本机。
`ens33` 是你的网卡（名字可能不同），`192.168.1.105/24` 里的 `/24` 是 CIDR 表示法——
子网掩码是 `255.255.255.0`，前 24 位是网络号，后 8 位是主机号。
`dynamic` 说明这个地址是 DHCP 分配的，`valid_lft` 是租约剩余时间。

```bash
# 查看路由表——默认网关在哪
$ ip route show
# 预期输出
default via 192.168.1.1 dev ens33
192.168.1.0/24 dev ens33 proto kernel scope link src 192.168.1.105
```

`default via 192.168.1.1` 就是你的默认网关。
所有不知道往哪发的包，都扔给这个地址——通常是你路由器的内网 IP。

```bash
# 查看接口链路状态
$ ip link show
# 预期输出
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 ...
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
    link/ether 00:0c:29:ab:cd:ef brd ff:ff:ff:ff:ff:ff
```

`UP` 说明接口已启用。如果显示 `DOWN`，要么网线没插，要么接口被手动关了（`ip link set ens33 down`）。

### 4.2  用 netplan 配置静态 IP

DHCP 分配的 IP 每次重启都可能变。对开发板来说，它需要一个稳定的地址来连接你的开发机。

先看一下当前 netplan 目录里有什么：

```bash
$ ls /etc/netplan/
# Ubuntu 22.04 服务器版常见输出
00-installer-config.yaml
# Ubuntu 24.04 服务器版常见输出
50-cloud-init.yaml
# 桌面版常见输出
00-network-manager-all.yaml
```

动它之前，先备份。这是一条铁律。

```bash
# 备份当前配置（文件名以实际为准）
$ sudo cp /etc/netplan/00-installer-config.yaml \
           /etc/netplan/00-installer-config.yaml.bak
```

> ⚠️ **netplan 配置写错了，网络直接断。** 如果你是 SSH 连上去操作的，改完 `netplan apply` 之后连不上就尴尬了。建议在虚拟机控制台（而非 SSH）里操作，或者改完先 `sudo netplan try`——它会等你在 120 秒内按回车确认，超时自动回滚到旧配置。

编辑配置文件：

```bash
$ sudo vim /etc/netplan/00-installer-config.yaml
```

把 `ens33` 配成静态 IP `192.168.1.100`：

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 114.114.114.114
```

> ⚠️ **YAML 对缩进极度敏感。** 用空格，不要用 Tab。每一层缩进 2 个空格。少一个空格或多一个空格，`netplan apply` 就报解析错误。YAML 不像 Python 会告诉你哪一行出了问题——它只会说 `Invalid YAML`，让你自己找。

应用配置：

```bash
# 安全方式：等待确认，超时自动回滚
$ sudo netplan try
# 预期输出
Do you want to keep these settings?

Press ENTER before the timeout to accept the new configuration

Changes will revert in 119 seconds
Configuration accepted.

# 或者直接应用（没有回滚保护）
$ sudo netplan apply
```

验证新配置生效了：

```bash
$ ip addr show ens33
# 预期输出应包含
inet 192.168.1.100/24 brd 192.168.1.255 scope global ens33

$ ip route show
# 预期输出
default via 192.168.1.1 dev ens33
192.168.1.0/24 dev ens33 proto kernel scope link src 192.168.1.100
```

### 4.3  配置桥接模式

如果你用的是 VMware 或 VirtualBox，第一步是在虚拟机软件的设置里把网络适配器从「NAT」切换到「桥接」（Bridged）。
这是在虚拟机软件里改的，不是在 Ubuntu 里改。

改完之后重启虚拟机网络（或直接重启虚拟机），虚拟机就像一台独立设备接在你的物理路由器上，
通过 DHCP 拿到和你物理机同网段的 IP。

但有时候你需要手动配桥接。比如你在做 KVM 虚拟化，或者你的开发环境需要软件网桥。
这时候可以在 netplan 里创建一个 `br0` 网桥，把物理接口桥接进来：

```yaml
network:
  version: 2
  renderer: networkd
  bridges:
    br0:
      interfaces:
        - ens33
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 114.114.114.114
```

这段配置的意思是：创建一个网桥 `br0`，把 `ens33` 桥接进来，给 `br0` 分配静态 IP。
此时 `ens33` 不再持有独立 IP——它只是一个桥接成员，所有流量走 `br0`。

```bash
$ sudo netplan apply
$ ip addr show br0
# 预期输出
3: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
    inet 192.168.1.100/24 brd 192.168.1.255 scope global br0
```

回到那个公寓楼和别墅的比喻。你可能注意到了，桥接之后虚拟机和物理网络在同一个网段——这就像把公寓楼里的住户搬到了独栋别墅区。
但这个比喻有一个地方需要修正：桥接不仅仅是「换了个地址」那么简单，它是在**数据链路层（L2）** 层面把多个接口合并成一个广播域。
这意味着桥接后的设备不仅能互相 ping 通，还能看到彼此的 ARP 广播——在 NAT 模式下这是不可能的。
对于嵌入式开发中常见的 TFTP 启动、NFS 挂载根文件系统等操作，L2 可达性是前提条件。

### 4.4  NetworkManager：桌面环境的选择

如果你的 Ubuntu 是桌面版，网络由 NetworkManager 管理。
虽然改 netplan YAML 也能生效，但 `nmcli` 更方便——它是 NetworkManager 的命令行前端。

```bash
# 查看设备状态
$ nmcli device status
# 预期输出
DEVICE  TYPE      STATE         CONNECTION
ens33   ethernet  connected     有线连接 1
lo      loopback  unmanaged     --
```

```bash
# 查看当前连接的详细配置
$ nmcli connection show "有线连接 1"
# 输出很长，重点关注这几个字段
connection.type:             802-3-ethernet
ipv4.method:                 auto
ipv4.addresses:              --
ipv4.gateway:                --
ipv4.dns:                    --
```

`ipv4.method: auto` 说明当前是 DHCP。改成静态 IP：

```bash
$ sudo nmcli connection modify "有线连接 1" \
    ipv4.method manual \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8 114.114.114.114"

$ sudo nmcli connection up "有线连接 1"
# 预期输出
Connection successfully activated (D-Bus active path: /org/freedesktop/NetworkManager/ActiveConnection/1)
```

回到那个「翻译官」的比喻：现在你应该能看出来了——
netplan 的 YAML 是你交给翻译官的「需求文档」，`networkd` 和 `NetworkManager` 是真正干活的「施工队」。
`nmcli` 是直接找施工队下指令，跳过了翻译官。
如果你同时给翻译官递文档又直接找施工队改图纸——两边配置冲突，网络就乱了。
在桌面版上选一种方式用到底，不要混。

---

## 练习题

走到这里，网络配置的基本机制应该已经清楚了——或者你以为清楚了。
下面几道题难度递进，建议先不看提示独立做，卡住了再翻。
第三题如果做出来了，说明你已经能应付嵌入式开发中的网络场景了。

**练习 21.1** ⭐（理解）

`ip addr show` 的输出中，`inet 192.168.1.100/24` 里的 `/24` 代表什么？
如果把子网掩码改成 `255.255.255.128`，CIDR 表示法应该写成 `/xx`？

> **提示**：把子网掩码转成二进制，数一下有多少个连续的 1。`255.255.255.0` 是 24 个 1，那 `255.255.255.128` 呢？

**练习 21.2** ⭐⭐（应用）

你的 Ubuntu 虚拟机当前通过 DHCP 获取 IP。
请写一份完整的 netplan 配置，将网卡 `ens33` 设为静态 IP `10.0.0.100/16`，网关 `10.0.0.1`，DNS 使用 `223.5.5.5` 和 `223.6.6.6`。
写完后说明你会在执行前做什么来保护自己。

> **提示**：参考 4.2 节的 YAML 格式，注意缩进。保护措施想想 `netplan try`。

**练习 21.3** ⭐⭐⭐（思考）

在嵌入式开发中，开发板的 IP 是 `192.168.10.50`，你的 Ubuntu 虚拟机在 NAT 模式下拿到 `10.0.2.15`。
为什么开发板无法 SSH 到虚拟机？给出至少两种解决方案，并分析各自的优缺点。

> **提示**：回顾 NAT 和桥接的区别。除了桥接，还有没有别的办法让两个不同网段的设备通信？想想路由和端口转发。

---

## 本章回响

这一章真正在建立的东西，是一种对「网络配置」的结构性理解。
表面上我们在敲 `ip addr`、写 YAML、配桥接，实际上我们在理解 Linux 网络的分层控制逻辑：
`ip` 命令看状态，netplan 写配置，NetworkManager 管桌面，networkd 管服务器——它们不冲突，只要你不在同一个接口上同时指挥两支施工队。

还记得开头那个问题吗——NAT 把开发板和虚拟机隔开了？
现在你应该能回答了：把虚拟机切到桥接模式，让它拿到和物理网络同网段的 IP，
开发板和虚拟机就像住在同一条街上的邻居，可以直接敲门，不需要物业转交。
而那个「公寓楼 vs 别墅」的比喻，现在你不仅知道它描述了什么，还知道它在哪里简化了现实——桥接不仅是换了个地址，而是真正打通了数据链路层的广播域。

但网络配好了，不等于网一定通。配了静态 IP 却 ping 不出去、DNS 配了却解析不了域名——这种事太常见了。
下一章我们会拿起诊断工具箱——当「网不通」三个字出现的时候，你需要知道从哪一层的哪一环开始查。

---

[← 上一章](../04-system/ch20-systemd.md)
[下一章 →](ch22-netdiag.md)
