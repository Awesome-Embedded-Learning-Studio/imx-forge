---
title: 网络启动（WSL2）
---

# WSL2 + TFTP + 网络启动：那些年我们一起踩过的防火墙坑

## 为什么要写这一章

如果你在做嵌入式开发，网络启动几乎是绕不开的技能。烧录 SD 卡太慢？网络启动。调试内核频繁更新？网络启动。没有 SD 卡槽？还是网络启动。

但网络启动的环境搭建，尤其是用 WSL2 做开发环境，真不是一件轻松的事。我当初踩过的坑，说出来都是泪：WSL2 和开发板网络不通、TFTP 一直超时、Windows 防火墙默默丢包、目录权限不够导致 Abort……

这些坑看似简单，但每个都可能让你折腾半天。而且网上教程大多只给命令，不解释背后的原理，你照着敲能成功，但下次出问题了还是不知道怎么排查。

所以这一章，我们完整地走一遍 WSL2 + TFTP + 网络启动的搭建过程。每一步都有原理解释，每个坑都有排查方法。读完之后，你不仅能成功搭建环境，更重要的是——下次出问题时，你知道怎么排查。

## 网络拓扑分析：第一步搞清楚物理连接

在开始配置之前，我们先搞清楚网络是怎么连的。这听起来简单，但很多人第一步就搞错。

### Windows 网卡情况

打开 Windows 的 PowerShell，运行 `ipconfig`：

```powershell
ipconfig
```

输出类似：

```
以太网适配器 网桥:

   连接特定的 DNS 后缀 . . . . . . . :
   本地链接 IPv6 地址. . . . . . . . : fe80::xxxx:xxxx:xxxx:xxxx%17
   IPv4 地址 . . . . . . . . . . . . : 192.168.60.1
   子网掩码  . . . . . . . . . . . : 255.255.255.0
   默认网关. . . . . . . . . . . . . :

以太网适配器 以太网 2:

   媒体状态  . . . . . . . . . . . . : 媒体已断开
```

这里有两条关键信息：

1. **网桥**：IP 是 `192.168.60.1`，这是开发板实际连接的网卡
2. **以太网 2**：媒体状态是"已断开"，说明没插网线

> **踩坑提醒**：很多人以为开发板接在"以太网 2"上，但实际上"以太网 2"可能是开发板的 USB 网口（用于 ADB 或其他用途），真正的以太网连接是通过"网桥"。搞错这一点，后面怎么 ping 都不通。

### 开发板网络配置

在 U-Boot 命令行中，先 ping 一下网关：

```bash
=> ping 192.168.60.1
Using ethernet@20b4000 device
host 192.168.60.1 is alive
```

如果看到 `is alive`，说明物理链路是通的。如果超时，检查：

1. 网线是否插好
2. 开发板和 Windows 是否在同一网段
3. Windows 防火墙是否允许 ping（ICMP）

## WSL2 网络模式：NAT vs Mirrored

WSL2 有两种网络模式：NAT（默认）和 Mirrored。理解它们的区别是关键。

### NAT 模式的问题

WSL2 默认是 NAT 模式，它的网络结构是这样的：

```
开发板 (192.168.60.x)
    ↓
Windows 网桥 (192.168.60.1)
    ↓
Windows NAT (虚拟交换机)
    ↓
WSL2 (172.x.x.x)
```

在 NAT 模式下，WSL2 处于一个独立的虚拟网段（通常是 172.x.x.x），和开发板的 192.168.60.0/24 网段完全隔离。这就导致：

1. 开发板无法直接访问 WSL2
2. WSL2 的 TFTP 服务对开发板不可见
3. 每次重启 WSL2，IP 可能会变化

### Mirrored 模式的优势

Mirrored 模式让 WSL2 直接镜像 Windows 的所有网卡：

```
开发板 (192.168.60.x)
    ↓
Windows 网桥 (192.168.60.1)
    ↓
WSL2 (能看到 192.168.60.1/24)
```

在 Mirrored 模式下，WSL2 可以直接访问 Windows 的每一块网卡，包括 192.168.60.1 这个网桥。

### 切换到 Mirrored 模式

在 Windows 用户目录下创建或编辑 `.wslconfig` 文件：

**文件位置**：`C:\Users\<你的用户名>\.wslconfig`

**内容**：

```ini
[wsl2]
networkingMode=mirrored
```

保存后，重启 WSL：

```powershell
wsl --shutdown
wsl
```

### 验证网络模式

重启 WSL 后，在 WSL 中运行：

```bash
ip addr
```

你应该能看到类似这样的网卡：

```
11: eth9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether xx:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    inet 192.168.60.1/24 brd 192.168.60.255 scope global noprefixroute eth9
       valid_lft forever preferred_lft forever
```

关键点是 `inet 192.168.60.1/24`，这说明 WSL2 现在能看到开发板所在的网段了。

> **经验**：`.wslconfig` 是全局配置，会影响到机器上所有 WSL2 发行版。但对于普通开发使用，这通常没有副作用，上网也不受影响。

## TFTP 服务搭建

现在网络通了，我们来搭建 TFTP 服务。

### 安装 tftpd-hpa

```bash
sudo apt update
sudo apt install tftpd-hpa
```

### 配置 TFTP

编辑配置文件：

```bash
sudo nano /etc/default/tftpd-hpa
```

修改为：

```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/home/charliechen/tftp"
TFTP_ADDRESS="192.168.60.1:69"
TFTP_OPTIONS="--secure"
```

**配置说明**：

- `TFTP_USERNAME`：运行 TFTP 服务的用户
- `TFTP_DIRECTORY`：TFTP 根目录，存放可传输的文件
- `TFTP_ADDRESS`：监听地址，必须绑定到 192.168.60.1（开发板能访问的地址）
- `TFTP_OPTIONS`：
  - `--secure`：安全模式，限制访问范围在 TFTP_DIRECTORY 内
  - 可选：`--create`：允许上传文件（如果需要）

### 准备 TFTP 目录

```bash
# 创建目录
mkdir ~/tftp

# 设置权限
sudo chmod 777 ~/tftp
```

> **踩坑提醒**：只改目录权限不够！tftp 用户还需要能进入你的 home 目录：
>
> ```bash
> sudo chmod o+x /home/charliechen
> ```
>
> 否则 TFTP 会报 "Permission denied" 错误。

### 创建测试文件

```bash
echo "Hello from TFTP!" > ~/tftp/test.txt
sudo chmod 777 ~/tftp/test.txt
```

> **踩坑提醒**：文件本身也要有读权限！很多人改了目录权限忘记改文件权限，导致 TFTP 传输 Abort。

### 启动 TFTP 服务

```bash
sudo service tftpd-hpa start
```

### 验证 TFTP 服务

首先确认服务在监听正确的端口：

```bash
sudo ss -ulnp | grep 69
```

输出应该包含：

```
UNCONN 0 0 192.168.60.1:69  0.0.0.0:*  users:(("in.tftpd",pid=xxxx,fd=...))
```

关键是 `192.168.60.1:69`，说明服务绑定到了正确的网卡。

然后在 WSL 内部测试一下：

```bash
# 安装 tftp 客户端（如果没安装）
sudo apt install tftp-hpa

# 测试
echo "get test.txt" | tftp 192.168.60.1
cat test.txt
```

如果能看到 "Hello from TFTP!"，说明 TFTP 服务本身没问题。

## Windows 防火墙配置（最隐蔽的坑！）

好，TFTP 服务在 WSL 里测试通过了。现在在开发板 U-Boot 里测试：

```bash
=> tftp 0x80800000 test.txt
Using ethernet@20b4000 device
TFTP from server 192.168.60.1; our IP address is 192.168.60.200
Filename 'test.txt'.
Load address: 0x80800000
Loading: T T T T T T T T T T
Retry count exceeded; starting again
```

看到了吗？`T T T T` 表示超时重试。但我们的服务明明在运行，为什么就是传不了？

**答案：Windows 防火墙默默地丢掉了 UDP 69 端口的入站包。**

这就是最隐蔽的坑——服务配置正确、端口监听正常、权限也没问题，但就是传不了。因为 WSL2 的网络实际上是走 Windows 的网络栈，Windows 防火墙会拦截入站流量。

### 添加防火墙规则

以管理员身份打开 PowerShell，运行：

```powershell
New-NetFirewallRule -DisplayName "WSL TFTP" `
                    -Direction Inbound `
                    -Protocol UDP `
                    -LocalPort 69 `
                    -Action Allow
```

**参数说明**：

- `-DisplayName`：规则名称，方便识别
- `-Direction Inbound`：入站规则（允许外部访问内部）
- `-Protocol UDP`：TFTP 使用 UDP 协议
- `-LocalPort 69`：TFTP 端口
- `-Action Allow`：允许通过

### 验证防火墙规则

```powershell
Get-NetFirewallRule -DisplayName "WSL TFTP" | Format-List
```

或者查看防火墙日志（如果启用了日志）：

```powershell
Get-NetFirewallRule -DisplayName "WSL TFTP" | Get-NetFirewallPortFilter
```

### 再次测试

现在回到 U-Boot，再试一次：

```bash
=> tftp 0x80800000 test.txt
Using ethernet@20b4000 device
TFTP from server 192.168.60.1; our IP address is 192.168.60.200
Filename 'test.txt'.
Load address: 0x80800000
Loading: #
         1.5 KiB/s
Bytes transferred = 6 (6 hex)
```

成功了！`#` 表示传输进行中，最后显示传输的字节数。

## U-Boot 网络配置

现在 TFTP 通了，我们来完整配置 U-Boot 的网络参数。

### 配置网络参数

在 U-Boot 命令行中：

```bash
setenv ipaddr 192.168.60.200
setenv netmask 255.255.255.0
setenv gatewayip 192.168.60.1
setenv serverip 192.168.60.1
saveenv
```

**参数说明**：

- `ipaddr`：开发板的 IP 地址
- `netmask`：子网掩码
- `gatewayip`：网关地址（通常和 serverip 相同）
- `serverip`：TFTP 服务器地址（即 WSL/Windows 的 IP）

> **踩坑提醒**：`serverip` 是很多人踩的坑。我之前有一次 `serverip` 被设成了 `192.168.60.129`（不知道哪里来的旧配置），导致 TFTP 一直连到错误的 IP。
>
> 每次修改后务必确认：
> ```bash
> printenv serverip
> ```
>
> 如果值不对，重新 `setenv` 然后 `saveenv`。

### 验证网络连接

```bash
=> ping 192.168.60.1
Using ethernet@20b4000 device
host 192.168.60.1 is alive
```

如果 ping 不通，检查：
1. 网线是否连接
2. IP 地址是否在同一网段
3. Windows 防火墙是否允许 ICMP（ping）

## TFTP 下载内核实战

测试文件成功后，我们来下载真正的内核和设备树。

### 准备文件

把编译好的内核和设备树复制到 TFTP 目录：

```bash
# 假设你的编译输出在 ~/linux-imx-build
cp ~/linux-imx-build/arch/arm/boot/zImage ~/tftp/
cp ~/linux-imx-build/arch/arm/boot/dts/imx6ull-14x14-evk.dtb ~/tftp/
```

确保文件权限正确：

```bash
sudo chmod 777 ~/tftp/zImage
sudo chmod 777 ~/tftp/imx6ull-14x14-evk.dtb
```

### 下载并启动

在 U-Boot 中：

```bash
# 下载内核
tftp 0x80800000 zImage

# 下载设备树
tftp 0x83000000 imx6ull-14x14-evk.dtb

# 启动
bootz 0x80800000 - 0x83000000
```

**地址说明**：

- `0x80800000`：内核加载地址（i.MX6ULL DDR 起始地址 + 偏移）
- `0x83000000`：设备树加载地址（需要在内核加载地址之后，且不冲突）
- `-`：表示没有 initramfs

### 启动自动化

每次手动敲命令太累，可以把它写成启动脚本：

```bash
setenv bootcmd 'tftp 0x80800000 zImage; tftp 0x83000000 imx6ull-14x14-evk.dtb; bootz 0x80800000 - 0x83000000'
setenv bootdelay 3
saveenv
```

这样 U-Boot 启动时会自动执行 `bootcmd`，3 秒内按任意键可以中断。

## 踩坑排查汇总表

我们总结一下这一章遇到的所有坑和解决方法：

| 坑 | 现象 | 根本原因 | 解决方法 |
|----|------|----------|----------|
| WSL2 NAT 隔离 | WSL 和开发板 ping 不通 | WSL2 在独立网段 | 切换 mirrored 模式 |
| Windows 防火墙 | TFTP 全程 `T T T` 超时 | UDP 69 入站被拦截 | 添加防火墙规则 |
| home 目录权限 | TFTP `* Abort` | tftp 用户无法进入 home | `chmod o+x /home/用户名` |
| 文件权限不足 | TFTP `* Abort` | 文件不可读 | `chmod 777 ~/tftp/*` |
| serverip 旧值 | 连接错误的 IP | 环境变量残留 | `setenv serverip` 重新配置 |
| 绑定地址错误 | WSL 内测试通，外部不通 | TFTP 绑定到 127.0.0.1 | `TFTP_ADDRESS="192.168.60.1:69"` |
| 网线插错口 | 物理层不通 | 混淆网桥和以太网 2 | 检查 `ipconfig`，确认网桥 |
| WSL 重启失效 | 配置丢失 | .wslconfig 没生效 | `wsl --shutdown` 完全重启 |

## TFTP 传输失败的各种表现

TFTP 传输失败有几种典型表现，每种对应不同的问题：

### 现象一：全程 `T T T`

```
Loading: T T T T T T T T T T
Retry count exceeded; starting again
```

**原因**：服务器完全没收到请求，或者响应被丢包。

**排查**：
1. Windows 防火墙（最常见）
2. TFTP 服务是否启动
3. IP 地址是否正确
4. 网络物理连接

### 现象二：`*` 后 `Abort`

```
Loading: *
Abort
```

**原因**：服务器收到请求并响应，但传输中断。

**排查**：
1. 文件权限（最常见）
2. 目录权限
3. 磁盘空间

### 现象三：传输很慢或频繁重传

```
Loading: ##########T#######T#####T###
```

**原因**：网络质量问题。

**排查**：
1. 换一根网线
2. 检查网络拥塞
3. 减小 MTU（U-Boot 中 `setenv mtu 600`）

## 进阶：NFS 根文件系统

网络启动的下一步通常是 NFS 根文件系统，这样开发板可以直接从网络挂载根文件系统，开发时修改文件不需要重新烧录。

### NFS 服务端搭建

在 WSL 中：

```bash
sudo apt install nfs-kernel-server
```

编辑 `/etc/exports`：

```
/home/charliechen/nfsroot *(rw,sync,no_subtree_check,no_root_squash)
```

创建根文件系统目录：

```bash
mkdir ~/nfsroot
# 复制根文件系统内容到 ~/nfsroot
```

启动服务：

```bash
sudo service nfs-kernel-server start
```

### U-Boot NFS 配置

```bash
setenv nfsroot 192.168.60.1:/home/charliechen/nfsroot
setenv bootargs 'console=ttymxc0,115200 root=/dev/nfs rw nfsroot=${nfsroot},v3,tcp ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}::eth0:off'
saveenv
```

### 内核配置

确保内核支持 NFS：

```
File systems  --->
    Network File Systems  --->
        <*> NFS client support
        [*]   Root file system on NFS
```

## 写在最后

这一章我们完整地走了一遍 WSL2 + TFTP + 网络启动的搭建过程。从网络拓扑分析、WSL2 镜像模式配置、TFTP 服务搭建，到最隐蔽的 Windows 防火墙坑，每个环节都有详细的解释和排查方法。

网络启动是嵌入式开发中非常实用的技能。它让你能够快速迭代内核和设备树，不需要每次都烧录 SD 卡。当你习惯了 `tftp` → `bootz` 的工作流，再回到烧录 SD 卡简直是折磨。

下一章，我们将进入驱动开发的实战环节。你会看到如何从零开始编写一个字符设备驱动，如何实现 `open`、`read`、`write`、`ioctl` 等操作，如何通过设备树传递硬件信息。那是从"会用内核"到"会写驱动"的关键一步。

准备好了吗？让我们继续。
