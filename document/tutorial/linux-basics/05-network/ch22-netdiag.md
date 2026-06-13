# 第 22 章  网络诊断

> **Part 5 · 网络与远程**

---

## 引子

网不通。就这么三个字，你排除了半个小时还是不知道问题在哪。

是 IP 配错了？DNS 挂了？网关不通？防火墙拦了？网线松了？
网络问题之所以难查，是因为排查链路太长——
从应用到传输层到网络层到物理层，任何一环出问题都是「网不通」。

ping 测连通性，traceroute 查路径，ss 看端口，
nslookup 查 DNS，tcpdump 抓包——
这些工具不是为了让你成为网络工程师，
而是让你在「网不通」的时候，能在五分钟内定位到是哪一层的锅。

---

## 背景与动机

上一章我们配好了网络——静态 IP 写了，桥接模式切了，DNS 填了。
但配好不等于通。你可能遇到这些场景：

开发板 `ping 192.168.1.100` 没回应；
虚拟机 `ping baidu.com` 报 `Name or service not known`；
`ssh` 连开发板超时；
`curl` 访问不了仓库地址。

这些症状的表象都一样——「不通」。
但病因可能完全不同。

网络诊断的核心思路是**分层排查**——从底层往上层逐层验证，
哪一层断了，问题就在哪一层。这不是什么高深的理论，是一个方法论：
先确认 IP 层通不通（ping），再确认路由对不对（traceroute），
再确认端口开没开（ss），再确认域名解析对不对（nslookup），
最后看应用层（curl）。绝大多数问题在前三步就能定位。

---

## 概念层

### 管道检修：每个工具查哪一环

你可以把网络想象成一套**管道系统**——
数据包是水流，路由器是管道分叉口，防火墙是阀门，DNS 是地址簿。

`ping` 就像拧开水龙头看有没有水——有水说明主管道通畅，没水说明某个地方堵了。
`traceroute` 是沿着管道一段一段地敲，找出水到底在哪一段断了。
`ss` 是查看你家里哪些水龙头正在开着（哪些端口在监听）。
`nslookup` 是翻地址簿——你记得朋友家在哪条街，但忘了门牌号。
`tcpdump` 则是把管道剖开，放一个摄像头进去看每一滴水具体长什么样。

但「管道」这个比喻有一个地方会误导你：
水流是连续的、没有结构的；而网络数据包是有结构的——
每个包有头部（header）和载荷（payload），头部里装着源地址、目标地址、协议类型等信息。
tcpdump 看到的不是浑水或清水，而是一个个有标签的信封。
而且网络里「管道堵塞」更常见的原因不是物理断路，而是配置错误——
防火墙规则、路由表项、DNS 设置，这些「阀门」开没开对，才是大多数「网不通」的真正原因。

### ping：第一道关卡

ping 使用 **ICMP**（Internet Control Message Protocol）发送 Echo Request 报文，
目标收到后回复 Echo Reply。

如果 ping 通了，说明从你的机器到目标的 **IP 层（Layer 3）** 链路是通的——
网卡没坏、网线没松、路由能到达、没有被防火墙拦住。

如果 ping 不通——事情就复杂了。可能是目标真的不可达，可能是被防火墙拦截了，
也可能是目标服务器配置了忽略 ICMP（出于安全考虑，很多公网服务器这么干）。
所以 ping 不通不代表网络一定有问题，但 ping 通了代表网络一定没问题。

### traceroute：定位断点

traceroute 利用 IP 包头的 **TTL**（Time To Live）字段逐跳探测。
每经过一个路由器，TTL 减 1；TTL 降到 0 时，路由器丢弃这个包，并回复一个 ICMP Time Exceeded。
traceroute 从 TTL=1 开始，逐个递增，这样每一跳都会有一个路由器报告「我到了」，
从而画出一条完整的路径。

如果路径在某一跳之后断了——问题就在那一跳和下一跳之间。

### ss：端口和连接的窗口

`ss`（Socket Statistics）来自 `iproute2` 工具集，取代了老旧的 `netstat`（来自 `net-tools`，和 `ifconfig` 一样是 2001 年停更的那一批）。
`ss` 直接读取内核的 socket 表，速度比 netstat 快得多——
在连接数很多的服务器上，netstat 可能要跑好几秒，ss 几乎是瞬间返回。

### nslookup / dig：DNS 诊断

当你用域名而不是 IP 地址访问时，系统会先做 DNS 查询——把域名翻译成 IP。
如果 DNS 服务器不可达或者配置的域名不存在，这一步就会失败。
`nslookup` 是最简单的 DNS 查询工具，`dig` 功能更强大（输出更详细）。

### tcpdump：终极武器

tcpdump 直接从网卡抓取原始数据包。它能看到所有经过网卡的数据——
包括正常通信的包、被拒绝的包、重传的包。
它是网络诊断的最后手段：当你用尽了 ping、traceroute、ss 都找不到问题时，
用 tcpdump 抓包，真相就在数据里。

---

## 实践层

### 4.1  第一步：ping 测连通性

拿到一个网络问题，第一步永远是 ping。

```bash
# ping 一个 IP 地址（测试 IP 层连通性）
$ ping -c 4 192.168.1.1
# 预期输出
PING 192.168.1.1 (192.168.1.1) 56(84) bytes of data.
64 bytes from 192.168.1.1: icmp_seq=1 ttl=64 time=0.352 ms
64 bytes from 192.168.1.1: icmp_seq=2 ttl=64 time=0.298 ms
64 bytes from 192.168.1.1: icmp_seq=3 ttl=64 time=0.311 ms
64 bytes from 192.168.1.1: icmp_seq=4 ttl=64 time=0.305 ms

--- 192.168.1.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3072ms
rtt min/avg/max/mdev = 0.298/0.317/0.352/0.021 ms
```

`-c 4` 表示发 4 个包就停。不加的话 ping 会一直跑下去，直到你按 `Ctrl+C`。

关键看三个东西：
- **packet loss**：0% 说明没丢包，完全通畅
- **time**：延迟，单位毫秒。局域网通常 < 1ms，公网 10-100ms
- **ttl**：每经过一个路由器减 1，可以据此估算经过了多少跳

```bash
# ping 一个域名（同时测试 DNS 解析和连通性）
$ ping -c 4 baidu.com
# 预期输出
PING baidu.com (110.242.68.66) 56(84) bytes of data.
64 bytes from 110.242.68.66: icmp_seq=1 ttl=51 time=28.3 ms
...
```

如果域名能解析出 IP（括号里显示了 IP 地址），说明 DNS 是通的。
如果连解析都失败了——问题在 DNS，不在连通性。

```bash
# ping 失败的情况
$ ping -c 4 192.168.99.99
# 预期输出
PING 192.168.99.99 (192.168.99.99) 56(84) bytes of data.

--- 192.168.99.99 ping statistics ---
4 packets transmitted, 0 received, 100% packet loss, time 3060ms
```

100% 丢包。先别急——检查 IP 有没有配错，目标机器有没有开机，防火墙有没有拦 ICMP。

### 4.2  第二步：traceroute 查路径

ping 发现不通了，但不知道断在哪一跳。traceroute 来定位。

```bash
$ traceroute 8.8.8.8
# 预期输出
traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 60 byte packets
 1  _gateway (192.168.1.1)  0.352 ms  0.298 ms  0.311 ms
 2  10.0.0.1 (10.0.0.1)     1.235 ms  1.189 ms  1.201 ms
 3  61.149.212.1             5.342 ms  5.298 ms  5.311 ms
 ...
 8  8.8.8.8 (8.8.8.8)      28.345 ms 28.298 ms 28.311 ms
```

每一行代表一跳。如果某一行之后全是 `* * *`，说明从那一跳开始就不通了——
问题就在那一跳和上一跳之间。

```bash
# 如果系统没有 traceroute，安装它
$ sudo apt install traceroute
```

> ⚠️ traceroute 在某些网络环境下可能被防火墙拦截，导致结果不准确。如果看到大量 `* * *`，不一定代表真的不通——也可能是 ICMP 被过滤了。可以尝试 `traceroute -T` 使用 TCP 方式探测（需要 root 权限）。

### 4.3  第三步：ss 查端口

如果你的服务起不来，或者远程连不上某个端口——查一下本机到底有没有在监听。

```bash
# 查看所有 TCP 监听端口及其对应的进程
$ ss -tlnp
# 预期输出
State   Recv-Q  Send-Q   Local Address:Port    Peer Address:Port   Process
LISTEN  0       128      0.0.0.0:22            0.0.0.0:*           users:(("sshd",pid=1234,fd=3))
LISTEN  0       511      127.0.0.1:631         0.0.0.0:*           users:(("cupsd",pid=567,fd=7))
LISTEN  0       128      *:80                  *:*                  users:(("nginx",pid=890,fd=6))
```

逐列解释：

| 列 | 含义 |
|---|---|
| `State` | LISTEN 表示正在监听，ESTAB 表示已建立连接 |
| `Recv-Q` | 接收队列中尚未被应用程序读取的字节数 |
| `Send-Q` | 发送队列中尚未被对方确认的字节数 |
| `Local Address:Port` | 本地监听的地址和端口。`0.0.0.0` 表示所有接口，`127.0.0.1` 表示仅本机 |
| `Peer Address:Port` | 远端地址。LISTEN 状态下显示 `*:*` |
| `Process` | 占用这个端口的进程名和 PID |

如果你发现某个端口没有在 LISTEN——要么服务没启动，要么启动失败了。
先 `systemctl status <服务名>` 看一下。

```bash
# 查看所有已建立的 TCP 连接
$ ss -tnp
# 预期输出
State  Recv-Q Send-Q  Local Address:Port   Peer Address:Port   Process
ESTAB  0      0       192.168.1.100:22     192.168.1.50:52341  users:(("sshd",pid=5678,fd=3))
```

`ESTAB` 说明有一个从 `192.168.1.50` 连过来的 SSH 连接。

常用 ss 选项速查：

```bash
ss -tlnp    # TCP 监听端口 + 进程信息
ss -tunlp   # TCP + UDP 监听端口 + 进程信息
ss -tnp     # 所有 TCP 连接 + 进程信息
ss -s       # 连接统计摘要
```

### 4.4  第四步：DNS 和应用层诊断

ping 和端口都正常，但域名访问不了——查 DNS。

```bash
# 查询域名对应的 IP
$ nslookup baidu.com
# 预期输出
Server:         127.0.0.53
Address:        127.0.0.53#53

Non-authoritative answer:
Name:   baidu.com
Address: 110.242.68.66
```

`Server: 127.0.0.53` 是本机的 systemd-resolved stub，它会把查询转发给真正的 DNS 服务器。
如果这里报 `connection timed out` 或 `server can't find`——DNS 配置有问题。
回到上一章，检查 netplan 里的 `nameservers` 配置。

应用层测试——curl 和 wget：

```bash
# 测试 HTTP 连通性（只看响应头，不下载内容）
$ curl -I https://baidu.com
# 预期输出
HTTP/1.1 200 OK
Content-Type: text/html
...

# 下载文件
$ wget -O /dev/null https://baidu.com
# 预期输出（截取关键行）
... saved [xxx/xxx]
```

`curl -I` 只获取 HTTP 头部，不下载正文。
如果看到 `HTTP/1.1 200 OK`，说明从 DNS 到 TCP 到 HTTP 全链路通畅。
如果看到 `Connection timed out`——结合前面的 ping 和 ss 结果，定位是哪一层的锅。

### 4.5  终极武器：tcpdump 抓包

当你用尽了所有工具还是找不到问题时，tcpdump 会告诉你真相。

```bash
# 抓取 ens33 接口上的所有包（按 Ctrl+C 停止）
$ sudo tcpdump -i ens33
# 预期输出
tcpdump: verbose output suppressed, use -v for full decode
listening on ens33, link-type EN10MB (Ethernet), snapshot length 262144 bytes
12:34:56.789012 IP 192.168.1.100 > 192.168.1.1: ICMP echo request, id 1234, seq 1, length 64
12:34:56.789234 IP 192.168.1.1 > 192.168.1.100: ICMP echo reply, id 1234, seq 1, length 64
```

但这个输出量太大了。实际使用时需要过滤：

```bash
# 只抓 ICMP 包（ping 用的协议）
$ sudo tcpdump -i ens33 icmp

# 只抓某个端口的包
$ sudo tcpdump -i ens33 port 22

# 只抓 10 个包就停
$ sudo tcpdump -i ens33 -c 10 port 80

# 保存到文件（用 Wireshark 打开分析）
$ sudo tcpdump -i ens33 -w capture.pcap -c 100
```

最后一个命令把抓到的包保存为 `.pcap` 文件，可以用 Wireshark 图形化分析。
在嵌入式开发中，这个操作特别常见——
开发板的网络行为有时候在终端里看不清楚，抓成 pcap 拖到 Wireshark 里一目了然。

回到那个管道系统的比喻：现在你应该能看出来，
ping 是拧开水龙头看有没有水，traceroute 是一段段敲管子找断点，
ss 是看你家哪些龙头开着，tcpdump 则是把管子剖开放了摄像头。
每一种工具查的是管道系统的不同环节，合在一起才能覆盖从水源到你水龙头的整条链路。
而大多数「网不通」的真实原因——不是管子爆了，而是某个阀门（防火墙规则、路由配置、DNS 设置）关了或者拧错了。

---

## 练习题

走到这里，分层排查的思路应该清楚了——但真遇到「网不通」的时候能不能冷静地按层排查，是另一回事。
下面几道题模拟真实故障场景，建议先独立分析，再对照工具验证。

**练习 22.1** ⭐（理解）

`ping 8.8.8.8` 通了，但 `ping baidu.com` 报 `Name or service not known`。
问题出在哪一层？你会用什么工具进一步确认？

> **提示**：一个通 IP，一个不通域名——中间差了什么环节？

**练习 22.2** ⭐⭐（应用）

你的开发板 IP 是 `192.168.1.50`，从 Ubuntu 虚拟机 `ping 192.168.1.50` 显示 `100% packet loss`。
请列出你将使用的排查步骤和对应的工具，按顺序写出来。

> **提示**：先确认本机网络配置是否正确（ip addr），再查路由（ip route），然后逐步排查。

**练习 22.3** ⭐⭐⭐（思考）

`ss -tlnp` 显示 `0.0.0.0:80` 处于 LISTEN 状态，但从另一台机器 `curl http://192.168.1.100:80` 连接超时。
ping 是通的。请给出至少三种可能的原因，以及对应的验证方法。

> **提示**：服务在监听、网络是通的，但连不上——中间还有什么东西可能拦截？想想防火墙、绑定地址、云安全组……

---

## 本章回响

这一章建立的不是某个具体工具的用法，而是一种**分层排查的思维习惯**。
当你遇到「网不通」的时候，本能反应不应该是随机尝试，而是从底层往上层逐层验证：
ping 通了就跳过 IP 层，traceroute 通了就跳过路由，ss 显示端口在听就跳过传输层，
直到找到第一个「断点」——问题就在那里。

还记得开头那个场景吗——「网不通」三个字排除了半个小时？
如果你按 ping → traceroute → ss → nslookup → curl 的顺序走一遍，
大多数问题五分钟就能定位。不是因为你学会了更多命令，而是因为你有了方法。

管道系统的比喻现在可以收起来了：你不再需要「水龙头」和「阀门」来理解网络——
ICMP、TTL、socket、DNS 查询，这些就是网络本身的语言。
比喻帮你上了手，真正的机制帮你走了远路。

但网络通了，只是基础设施就位了。
你现在的 Ubuntu 可以被开发板访问到了——但怎么操作那块板子？
它没有显示器，没有键盘，只有一根网线。你需要远程登录上去。
下一章我们就讲 SSH——Secure Shell，
它将让你坐在 Ubuntu 终端前，直接操作开发板的命令行。

---

[← 上一章](ch21-netconfig.md)
[下一章 →](ch23-ssh.md)
