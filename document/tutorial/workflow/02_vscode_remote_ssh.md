---
title: VSCode Remote-SSH 连 WSL：把编辑器搬进开发环境
---

# VSCode Remote-SSH 连 WSL：把编辑器搬进开发环境

> 咱们的源码、交叉工具链、构建产物全在 WSL 的文件系统里，VSCode 却开在 Windows 桌面上，这层别扭怎么解？本篇把编辑器搬进开发环境：WSL 侧装好并启动 sshd,Windows 侧配好 Host 别名与 ed25519 免密，Remote-SSH 一线牵通。这是工作流卷第二篇，上一篇把 WSL2 网络模式调成了 mirrored,本篇直接复用那条结论；下一篇接上串口终端，两扇窗口拼成完整的开发台。

::: info 您将学到
- 在 WSL 里安装、配置 openssh-server,分清 systemd 套接字激活、systemd 常驻服务与非 systemd 三种开机自启形态
- Windows 侧 %USERPROFILE%\.ssh\config 的 Host 别名写法，ed25519 密钥免密的完整链路
- Remote-SSH 打开仓库后，clangd 索引与构建任务为什么原样生效，扩展该装远端还是本地
- Remote-SSH 与官方 WSL 扩展的机制差别，您拿什么依据做选择
- 连不上时的排查顺序：服务在不在、端口归谁、网络模式对不对，逐项对号
:::

::: tip 前置知识 · 咱们的环境
- WSL2 网络模式(mirrored 切换、防火墙放行手法)归 [01_wsl2_env_config.md](01_wsl2_env_config.md),本篇只复用其结论，配置步骤回那篇看
- 串口侧的参数与工具(115200 8N1 无流控、minicom 用法)在 [串口工具使用](../start/04_serial_tools_minicom.md),是下一篇的储备
- WSL 与 Linux 的基本功，您回 [Linux 基础专栏](../linux-basics/) 按需补
- 路径上下文：本篇操作横跨两侧。Windows 侧只动 %USERPROFILE%\.ssh\ 下的几个文件；WSL 侧就是仓库所在的开发机(~/imx-forge,交叉工具链在 /opt/arm-gnu-toolchain)。每个命令块首行注释标了执行位置
:::

## 一、开发台的形状

动手之前，咱们把要拼的东西画出来。Issue #101 里那位朋友的留言本身就是一张拓扑图，一句话说尽：VSCode 用 ssh 连 WSL 改代码，MobaXterm 开着串口连板子看输出。本篇与下一篇各接一条线，接完就是这位朋友要的开发台。

```text
                        一台 Windows 物理机
┌─────────────────────────┬─────────────────────────┐
│  窗口一:VSCode           │  窗口二:串口终端         │
│  Remote-SSH 扩展         │  MobaXterm / Xshell 等   │
└────────────┬────────────┴────────────┬────────────┘
             │ ssh(TCP 22)           │ USB 转串口线
             ▼                        ▼
┌─────────────────────────┐ ┌────────────────────────┐
│ WSL2(Ubuntu)           │ │ i.MX6ULL 开发板         │
│   ~/imx-forge 源码      │ │   debug 口 = UART1      │
│   /opt/arm-gnu-toolchain│ │   115200 8N1 无流控     │
│   out/ 构建产物          │ │                        │
└─────────────────────────┘ └────────────────────────┘
```

为什么这么分，两边各有各的道理。源码、工具链、构建产物必须在 WSL 原生文件系统里，这是 01 篇铺过的结论：/mnt/c 走 9P 协议慢五倍以上，大小写不敏感还会把内核 net/netfilter 下同目录的 xt_DSCP.c 与 xt_dscp.c 搅成同一个文件；编辑器要贴着代码干活，那就只能进 WSL 那一侧。USB 转串口则插在 Windows 上，设备枚举归 Windows 管，串口终端留在 Windows 侧最省事；WSL 也能靠 usbipd 把 USB 设备转发进去，但那要多装一整套工具，咱们不绕这个弯。

于是两个窗口各守一段：VSCode 管代码与构建，身体活在 WSL 里；串口终端管板子的输出，活在 Windows 桌面上。两条通道互不依赖，坏了一条另一条照常干活，排查时也好定位。至于免掉 sshd 的另一条路(官方 WSL 扩展)，第五节专门对比，这里咱们先把主线走通。

## 二、WSL 里把 sshd 装好并启动

### 本机没装 openssh-server

笔者这台 WSL 没装 openssh-server,安装与启停的回显本机采集不了，本节凡是贴不出的输出都会标注，咱们以命令与判据为主。

```bash
# WSL ~/
which sshd; dpkg -l openssh-server 2>/dev/null | tail -1
```

```text
sshd not found
un  openssh-server <none>       <none>       (no description available)
```

which 无果，dpkg 状态字 un 就是未安装。这份输出正好当咱们验证环节的阴性对照：服务没装时连接长什么样，后面有实测。

### 安装与关键配置

```bash
# WSL ~/
sudo apt update
sudo apt install openssh-server
```

::: warning 未实测标注
apt 安装的回显本机采集不了：这台机器没装 openssh-server,真去装会改变机器现状，还会跟别的发行版在 22 口上跑着的 sshd 撞车，笔者不真装，也不编造安装日志。命令按 Ubuntu 标准流程给出，您执行时以自己机器的回显为准。
:::

装完后咱们只关心 /etc/ssh/sshd_config 里的三项，够用就好：

| 配置项 | 本篇取值 | 说明 |
|---|---|---|
| Port | 22(默认) | 与 Windows 侧 Host 配置里的 Port 对应；提醒：Ubuntu 22.10+ 默认 ssh.socket 套接字激活，监听端口归 socket 管，改 Port 的正确步骤按 Ubuntu 版本分了岔(24.04 与 22.10–23.10 不是一回事，见下文验证一节的警示框) |
| PasswordAuthentication | yes | 首连靠密码；免密配好后可改回 no 收紧 |
| PermitRootLogin | 不动(默认 prohibit-password) | 咱们用普通用户登录 |

您可以用 grep 查看现值；Ubuntu 出厂这几行常是注释形态，比如 #PasswordAuthentication yes,注释着不等于关闭，默认行为仍是 yes:

```bash
# WSL ~/
grep -E '^(Port|PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config
```

您要改就用顺手的编辑器改完保存，起服务那步会按新配置来。

### 起服务，三种自启形态

起服务用哪套命令，取决于这台 WSL 开没开 systemd;开了 systemd 的，Ubuntu 22.10 起 apt 装完 openssh-server 默认走 ssh.socket 套接字激活，监听归 socket 管，还得再分 socket 与常驻服务两支。看 /etc/wsl.conf,下面是笔者机器上的实测输出：

```bash
# WSL ~/
cat /etc/wsl.conf
```

```ini
[boot]
systemd=true

[user]
default=charliechen

[interop]
appendWindowsPath=false
```

[boot] 段的 systemd=true 说明咱们这台走了 systemd,服务管理就是标准的 systemctl。两支的判别一条命令：

```bash
# WSL ~/
systemctl status ssh.socket --no-pager
```

active (listening) 就是 socket 形态，咱们这台 24.04 装完 openssh-server 就落在这支：监听已由 ssh.socket 持有，sshd 要等第一个连接进来才会被启动，平时 systemctl status ssh 显示 inactive (dead) 属于常态，别误读成服务没起来，直接照下一节的法子连 localhost 验证即可；您要是想换成常驻的服务形态，工序在下文验证一节的警示框里：systemctl disable --now ssh.socket 在前，systemctl enable --now ssh.service 在后。ssh.socket 不存在或 inactive 的机器(比如 Ubuntu 22.10 之前的老版本)，才轮到直接起服务形态：

```bash
# WSL ~/
sudo systemctl enable --now ssh
systemctl status ssh --no-pager
```

enable --now 一条命令做两件事：现在就起，之后每次开机也自动起。systemctl 这套服务管理的基本功，Linux 基础卷里有成套分册，咱们实际跑一遍，看一眼目录：

```bash
# 主机 ~/imx-forge
ls document/tutorial/linux-basics/ | head -8
```

```text
01-environment
02-commandline
03-text
04-system
05-network
06-script
07-devtools
index.md
```

七个分册从环境一路排到开发工具，哪块薄弱您对号回补。另一种形态是发行版没开 systemd,这时 systemctl 会报 System has not been booted with systemd 之类的错，咱们别慌，换 service 手动起，再把自启写进 /etc/wsl.conf 的 [boot] 段：

```bash
# WSL ~/
sudo service ssh start
```

```ini
# /etc/wsl.conf 里已有的 [boot] 段追加一行(别写第二个 [boot])
command = service ssh start
```

三种形态的判别两条：cat /etc/wsl.conf 看 [boot] 段定 systemd 有无，systemctl status ssh.socket 再分 socket 还是常驻服务。咱们这台有 systemd,走 systemctl。

### 验证：连自己，还要确认应答的是谁

服务起来后，咱们拿 ssh 客户端连本机。这里有个笔者没料到的实测发现，值得原样展示：一台没装 openssh-server 的机器，这条命令居然不是 Connection refused:

```bash
# WSL ~/
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=3 localhost true
```

```text
Warning: Permanently added 'localhost' (ED25519) to the list of known hosts.
charliechen@localhost: Permission denied (publickey,password).
```

两个选项是免交互用的：BatchMode 不弹密码提示，StrictHostKeyChecking 自动收下指纹，咱们拿纯判据。输出说明 22 端口上确实有 SSH 服务在应答——只是它不认识 charliechen 这个用户。它是谁？加 -v 抓对端横幅：

```bash
# WSL ~/
ssh -v -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=3 localhost true 2>&1 | grep -i 'remote software'
```

```text
debug1: Remote protocol version 2.0, remote software version OpenSSH_9.6p1 Ubuntu-3ubuntu13.18
```

横幅说应答的是个 Ubuntu 的 sshd,可本发行版没有 sshd 进程，咱们再看监听：22 端口有 LISTEN,却查不到属主进程：

```bash
# WSL ~/
ps aux | grep '[s]shd'; ss -tlnp 2>/dev/null | grep -E ':22\s'
```

```text
# ……前半条 ps 没有任何输出，只有 ss 的两行……
LISTEN 0      4096          0.0.0.0:22         0.0.0.0:*
LISTEN 0      4096             [::]:22            [::]:*:*
```

一台没有 sshd 进程的发行版，却在应答 ssh,答案在机器层面：这台物理机上不止一个 WSL 发行版在跑，咱们拉名单：

```bash
# WSL ~/(调 Windows 侧的 wsl.exe,它输出 UTF-16,所以有 tr 这一步)
/mnt/c/Windows/System32/wsl.exe -l -v 2>/dev/null | tr -d '\0'
```

```text
  NAME              STATE           VERSION
* LinuxWSL          Running         2
  H618              Stopped         2
  RK3506            Stopped         2
  RKSeries          Running         2
  SimpleChips       Stopped         2
  IMX6ULL           Running         2
  AI                Stopped         2
  docker-desktop    Stopped         2
  Android           Stopped         2
```

星号标的 LinuxWSL 是默认发行版——wsl.exe 不带参数时落进去的就是它；咱们脚下这台其实是 IMX6ULL(echo $WSL_DISTRO_NAME 可自证)。Running 名单里另外还有 LinuxWSL 与 RKSeries,RKSeries 这类名字一看就是为各块板子单开的小环境。把这些事实串起来：mirrored 模式把运行中各发行版的监听共享到同一份 localhost 上，另一个发行版里跑着的 sshd,在咱们这台的 localhost:22 照样应答。哪个发行版真正持有 22 得挨个进去查，这一步笔者没做，机制推断如实标注；但事实链已经够咱们吸取教训：

::: warning 端口有人应答，不代表应答的是咱们自己立的服务
mirrored 模式下，Windows 与所有运行中的 WSL 发行版共享同一份 localhost。多发行版机器上，22 端口可能早已被别的发行版的 sshd 占住，您的连接会落进别人的系统，症状正是密码怎么输都不对。判据：连上后看提示符里的用户名与主机名，或抓横幅对版本。绕开冲突最直接的办法是给本发行版的 sshd 换私有端口(如 Port 2222),Windows 侧 Host 配置同步写 Port 2222。只是换端口这步在 Ubuntu 上得认版本，因为 22.10 起 openssh-server 默认 systemd 套接字激活，监听端口由 ssh.socket 持有。查自己那台归哪套：systemctl status ssh.socket,active (listening) 就是 socket 在管端口。在咱们这台 24.04 上，systemd 的 sshd-socket-generator 会动态从 sshd_config 读 Port,正解是 sshd_config 写 Port 2222,sudo systemctl daemon-reload 让 generator 重新生成 socket 的监听口，sudo systemctl restart ssh.socket,最后 ss -tlnp 验证；只 systemctl restart ssh.service 换不了口，sshd 是收到连接才被 socket 启动的进程，换监听口的钥匙不在它手里。22.10–23.10(以及从 22.04 升级上来、/etc/systemd/system/ssh.socket.d/addresses.conf 还留着的机器)才是真的被架空：那几个版本把 Port 一次性迁进了 addresses.conf,光改 sshd_config,端口纹丝不动仍听 22。这套机制下步骤不干净，弄不好 22 与 2222 两个口同时在听，改完 ss -tlnp 对一眼再收工。不想留在 socket 形态，备选两条：要么 systemctl disable --now ssh.socket,再 systemctl enable --now ssh.service,让 sshd 回到自己监听，Port 直归 sshd_config 管；要么 systemctl edit ssh.socket,写 ListenStream=(清空默认那行)加 ListenStream=2222,再 systemctl daemon-reload 并 systemctl restart ssh.socket。
:::

所以完整的验证姿势是：ssh 能握手、密码能过、落地的提示符里用户名与主机名对得上。第三条在多发行版机器上千万别省，笔者这台就是活例子。至于装好 sshd 后登进自己机器的成功回显，本机同样采集不了，判据就按这三条来。

### 网络这一跳：mirrored 还是 NAT

ssh 这条线要从 Windows 跨进 WSL,网络模式是 01 篇铺好的地基，咱们只把那篇的锚点翻出来对个眼：

```bash
# 主机 ~/imx-forge
grep -n 'mirrored\|防火墙\|Firewall' document/tutorial/workflow/01_wsl2_env_config.md | head -6
```

```text
20:networkingMode=mirrored
31:Mirrored 模式会把 Windows 防火墙规则同步生效到 WSL2 这一侧，反而可能把原本能通的 NFS/TFTP 端口挡掉（见第四节）。切换后务必复查防火墙。
52:### 1. Windows 防火墙拦 UDP 69
54:TFTP 用 UDP 69，Windows 防火墙默认拦截入站。以**管理员**身份开 PowerShell：
57:New-NetFirewallRule -DisplayName 'TFTP-UDP-69' -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow -Profile Any
74:## 四、NFS rootfs：端口、防火墙、网桥
```

第 20 行是 mirrored 开关本体，第 31 行的防火墙提醒对本篇同样要记着，第 57 行就是放行手法本体。这台机器的现状咱们也实际验证过，Windows 侧的配置文件与网卡各留了一份证据：

```bash
# WSL ~/(跨过去读 Windows 用户目录)
cat /mnt/c/Users/CharlieChen/.wslconfig
```

```ini
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

```bash
# WSL ~/
ip -4 addr show | grep inet
```

```text
    inet 127.0.0.1/8 scope host lo
    inet 10.255.255.254/32 brd 10.255.255.254 scope global lo
    inet 10.147.20.122/24 brd 10.147.20.255 scope global noprefixroute eth1
    inet 192.168.1.5/24 brd 192.168.1.255 scope global noprefixroute eth2
```

配置里 networkingMode=mirrored 与 01 篇的开关对上了(这文件还写了重复的 [wsl2] 段，WSL 两个段的键都认，不算整洁但能跑)；网卡侧，eth2 上那个 192.168.1.5 是 Windows 局域网卡镜像进来的地址，NAT 模式下咱们只会看到一张 172.x 的 eth0,mirrored 的判据就这两条。lo 上多出的 10.255.255.254 则是 .wslconfig 里 dnsTunneling=true 的 DNS 隧道端点(本机 /etc/resolv.conf 的 nameserver 就是它)，NAT 模式开了 dnsTunneling 也会有，不能拿它当 mirrored 的判据。模式对了，Windows 侧连 localhost:22 就能落到 WSL 的服务上，不用查地址。

防火墙层面看您机器的写法：笔者这台的 .wslconfig 里另有 firewall=false,WSL 侧不叠 Hyper-V 防火墙，22 畅通；您那边要是没这么写，放行就照 01 篇那条 TFTP 规则换端口与协议：

```powershell
# Windows PowerShell(管理员)
New-NetFirewallRule -DisplayName 'SSH-TCP-22' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any
```

要是您的 .wslconfig 还停在默认 NAT,localhost 转发(localhostForwarding)默认是开着的，但常被 Hyper-V 防火墙与各类 VPN 搅得时通时不通；不稳就连 WSL 的 172.x 地址，或照 01 篇把模式切到 mirrored,NAT 下别把 localhost 当稳定通道。咱们统一按 mirrored 讲，下一节 HostName 才敢固定写 localhost。

## 三、Windows 侧：连接与免密

### Host 别名

Windows 10 1809 之后系统自带 OpenSSH 客户端，PowerShell 里 ssh 直接可用，咱们不装第三方。连接参数固化进 %USERPROFILE%\.ssh\config(即 C:\Users\用户名\.ssh\config,文件不存在就新建)：

```text
# %USERPROFILE%\.ssh\config
Host wsl-imx
    HostName localhost
    Port 22
    User charliechen
```

Host 是您起的别名，之后 VSCode 与命令行都用它；HostName 敢写 localhost,依据是上一节的 mirrored;User 换成您 WSL 里的登录名；要是多发行版那个坑命中了您，Port 就换成 2222 这类私有端口(Ubuntu 22.10+ 换端口的正确步骤按版本分了岔，照上一节警示框来：24.04 上 daemon-reload 后 restart ssh.socket 即可，22.10–23.10 才需要先停掉 socket 激活)。配好后验连通：

```powershell
# Windows PowerShell
ssh wsl-imx
```

首连会问要不要收下主机指纹，您答 yes,再输一次 WSL 密码，落进 WSL 的 shell 就是通。

::: warning 未实测标注
Windows 侧的全部回显(指纹询问、密码提示、登录后的 shell 界面)在笔者的采集环境里跑不了，本环境只有 WSL 一侧。流程按 OpenSSH 通用行为描述，您以自己屏幕上的回显为准。
:::

### 免密：ed25519 密钥

```powershell
# Windows PowerShell
ssh-keygen -t ed25519
```

您一路回车就行(口令留空即纯免密；想更稳妥可以给密钥设口令，那属于另一个话题)。接着把公钥送进 WSL,这一条还得输最后一次密码：

```powershell
# Windows PowerShell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh wsl-imx "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

此后 ssh wsl-imx 不再问密码。末尾那两个 chmod 不是走过场：.ssh 与 authorized_keys 的权限一松，sshd 会直接拒用这把钥匙，还不给明显报错，是您排障时最气人的静默坑。

### VSCode 里连

GUI 流程咱们一句话带过：扩展市场装 Remote-SSH(微软官方，ms-vscode-remote 出品)，F1 调命令面板，Remote-SSH: Connect to Host,选 wsl-imx;新窗口左下角出现绿角标 SSH: wsl-imx 即连上，Open Folder 打开 /home/您的用户名/imx-forge。

::: warning 未实测标注
VSCode 的图形流程(装扩展、命令面板、绿角标)无法在笔者的采集环境里自动化验证，步骤按 Remote-SSH 扩展的标准界面描述；连不上时回到踩坑速查表逐项对。
:::

## 四、连上之后的工程体验

### 索引与任务，原样生效

Remote-SSH 的机制说穿了不值钱：连接建立后，VSCode 在 WSL 里装一份服务端进程，咱们窗口里开的每个文件、每个终端都实际跑在 WSL 侧；对仓库来说，这和坐在 WSL 里开发没有区别。所以 [04_clangd_cross_compile.md](04_clangd_cross_compile.md) 配的 .clangd 与 compile_commands.json、[05_tasks_json.md](05_tasks_json.md) 配的 tasks.json,打开就有，一个字不用改。配置跟着文件系统走，不跟着窗口走——这正是把编辑器搬进来的意义。

### 扩展装远端还是本地

连接之后扩展面板会分成两栏，本地一份，SSH: wsl-imx 一份，Windows 侧已装的扩展想在 WSL 生效得再点一次安装。判断口径一条就够：要读文件、起进程的(语言服务、调试器前端这类)装远端，纯界面的(主题、快捷键)留本地。咱们这条链路上最要紧的是 clangd:扩展装到远端，本体也得在 WSL 里(sudo apt install clangd)。装错了边的症状是跳转补全全无，而面板上没有任何报错；您排查时看扩展装在哪一侧，再看本体在不在。

### 终端就是 WSL shell

Ctrl + ` 拉出的内置终端就是 WSL 的 shell,咱们的工作目录落在仓库根，构建直接跑：

```bash
# VSCode 内置终端(WSL shell) ~/imx-forge
./scripts/build_helper/build-mainline-linux.sh --release
```

配好 05 篇的 tasks.json 之后 Ctrl+Shift+B 一键触发，编译告警还能跳回源码行。写代码、跑构建、看输出在同一个窗口里转圈，这是咱们换到 Remote-SSH 之后最容易回不去的地方。

## 五、Remote-SSH 与 WSL 官方扩展怎么选

写到这儿有个绕不开的问题：微软还有个官方 WSL 扩展，免 sshd,在 WSL 里敲 code . 就能唤起 Windows 侧的 VSCode 直连进去，咱们为什么绕 Remote-SSH 这一大圈？

机制差别就一层。WSL 扩展走 VSCode 与 WSL 之间的专用通道，不依赖 sshd,集成深，连服务端安装都是自动的；代价是这条路只通 WSL,而且只认 VSCode 自己。Remote-SSH 多装一个 sshd,换来一条标准 ssh 通道：命令行的 ssh 与 scp、别的编辑器、咱们将来连虚拟机或服务器，全是同一套 Host 配置与同一份肌肉记忆。Issue #101 那位朋友的用法本身就是标准 ssh 生态的形态，这也是本篇拿 Remote-SSH 当主轴的原因。

选择依据很直白，您对号入座：只用 VSCode、嫌装 sshd 麻烦，官方 WSL 扩展更省事；想统一远程开发的套路，今天 WSL、明天虚拟机、后天服务器，Remote-SSH 一次到位。两条路不互斥，同一台机器上两个扩展并存毫无冲突，顺手就好。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| ssh wsl-imx 超时或 Connection refused | sshd 没起，或 22 端口没放行 | systemctl status ssh 查服务；防火墙照 01 篇手法放行 TCP 22(-Profile Any) |
| 密码输对仍被拒(Permission denied) | 连到了别的发行版的 sshd,或 sshd_config 限制登录 | 抓横幅确认应答者；多发行版就换私有端口(换端口的步骤按 Ubuntu 版本分岔，见第二节警示框)；grep 查 PasswordAuthentication |
| 扩展装不上、远端下载慢 | 远端要下载 VSCode Server 服务端组件，WSL 内网络慢会卡在这一步(回显停在 Setting up SSH Host 一类字样) | 重试；必要时给 WSL 配代理(https_proxy),或手动下载对应版本放进 ~/.vscode-server;确认 clangd 这类语言服务装在远端 |
| Windows 连 localhost 不通 | WSL 还在 NAT 模式 | .wslconfig 切 networkingMode=mirrored,见 [01_wsl2_env_config.md](01_wsl2_env_config.md) |

## 继续学习

- 上一篇:[01_wsl2_env_config.md](01_wsl2_env_config.md),网络模式与防火墙的地基都在那边
- 下一篇:[03_serial_terminal.md](03_serial_terminal.md),把开发台的第二扇窗口(串口终端)接上
- 深读：索引配置看 [04_clangd_cross_compile.md](04_clangd_cross_compile.md);一键构建看 [05_tasks_json.md](05_tasks_json.md)
- 编辑器接上之后，下一步是把断点也接上:[gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md)
