---
title: NFS 网络启动排查
---

# WSL + NFS 网络启动踩坑记：从挂载失败到成功启动的完整历程

## 前言：为什么选择 NFS

在嵌入式 Linux 开发中，Rootfs 的部署方式有好几种：

1. **烧录到 Flash**：把 Rootfs 打包成镜像，烧录到 eMMC、SD 卡或 NAND Flash。缺点是每次修改都要重新烧录，开发效率低。
2. **UBI 文件系统**：使用 UBI/UBIFS 管理原始 Flash 设备。适合量产阶段，但配置复杂。
3. **NFS 网络挂载**：开发板通过网络从主机挂载 Rootfs。修改立即生效，无需重新烧录。

对于开发阶段，NFS 是最方便的选择——你可以在主机上修改文件、添加程序，开发板重启后立即看到效果。但是，NFS 的配置也是出了名的坑多，尤其是当你使用 WSL2 作为开发环境时，各种问题接踵而至。

这一章，我会分享我从 NFS 挂载失败到成功启动的完整排查过程，以及中间踩过的各种坑。

## 环境说明

- 开发板：i.MX6ULL
- 主机环境：WSL2（Ubuntu 22.04），Windows 11
- 网络模式：WSL2 `networkingMode=mirrored`
- 内核版本：Linux 6.12
- BusyBox 版本：1.37.0

## 最终工作配置速查

在你被各种问题折磨得想砸键盘之前，先给你一个"最终答案"——这是我经过无数次尝试后验证可用的完整配置：

### U-Boot bootargs 配置

```bash
setenv bootargs "console=ttymxc0,115200 root=/dev/nfs nfsroot=192.168.60.1:/home/charliechen/imx-forge/rootfs/nfs,vers=3,proto=tcp rw ip=192.168.60.200:192.168.60.1:192.168.60.1:255.255.255.0::eth0:off"
saveenv
```

**参数解析**：

- `console=ttymxc0,115200`：控制台设备和波特率
- `root=/dev/nfs`：指定根文件系统是 NFS
- `nfsroot=<主机IP>:<rootfs路径>,vers=3,proto=tcp`：NFS 服务器地址、路径、版本和协议
- `ip=<板子IP>:<主机IP>:<网关IP>:<子网掩码>::<网卡>:off`：网络配置

### /etc/exports 配置

```bash
/home/charliechen/imx-forge/rootfs/nfs  192.168.60.0/24(rw,sync,no_root_squash,no_subtree_check)
```

**选项说明**：

- `rw`：读写权限
- `sync`：同步写入（数据更安全）
- `no_root_squash`：不压缩 root 用户权限（客户端 root 用户就是服务端 root 用户）
- `no_subtree_check`：不检查子目录（提高性能）

### /etc/nfs.conf 端口固定

```ini
[mountd]
port=20048

[lockd]
port=32803
udp-port=32769

[statd]
port=32765
```

### Windows 防火墙规则

```powershell
# 在管理员 PowerShell 中执行
New-NetFirewallRule -DisplayName 'NFS-TCP-111'      -Direction Inbound -Protocol TCP -LocalPort 111   -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-UDP-111'      -Direction Inbound -Protocol UDP -LocalPort 111   -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-TCP-2049'     -Direction Inbound -Protocol TCP -LocalPort 2049  -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-mountd-20048' -Direction Inbound -Protocol TCP -LocalPort 20048 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-lockd-32803'  -Direction Inbound -Protocol TCP -LocalPort 32803 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-statd-32765'  -Direction Inbound -Protocol TCP -LocalPort 32765 -Action Allow -Profile Any

# 网桥网卡改为 Private（如果被识别为 Public 网络）
Set-NetConnectionProfile -InterfaceAlias "网桥" -NetworkCategory Private
```

## NFS 服务端配置详解

### 安装 NFS 服务器

```bash
sudo apt update
sudo apt install nfs-kernel-server
```

### 配置 /etc/exports

`/etc/exports` 是 NFS 服务器的主配置文件，定义了哪些目录可以被哪些客户端挂载。

**基本语法**：

```
<导出目录>   <客户端1>(选项) <客户端2>(选项) ...
```

**客户端地址格式**：

- `192.168.1.100`：单个 IP
- `192.168.1.0/24`：IP 网段（推荐）
- `*.example.com`：域名通配符
- `*`：所有客户端（不推荐，安全隐患）

**常用选项**：

| 选项 | 作用 | 推荐值 |
|------|------|--------|
| `ro` | 只读 | - |
| `rw` | 读写 | 开发阶段推荐 |
| `sync` | 同步写入（数据更安全） | 推荐 |
| `async` | 异步写入（性能更好） | 不推荐 |
| `no_root_squash` | 不压缩 root 权限 | 开发阶段推荐 |
| `root_squash` | 压缩 root 权限为 nfsnobody | 生产环境推荐 |
| `no_subtree_check` | 禁用子树检查（提高性能） | 推荐 |
| `subtree_check` | 启用子树检查 | 不推荐 |

**配置示例**：

```bash
# /etc/exports
/home/charliechen/imx-forge/rootfs/nfs  192.168.60.0/24(rw,sync,no_root_squash,no_subtree_check)
```

配置完成后，应用更改：

```bash
sudo exportfs -ra
```

**验证配置生效**：

```bash
sudo exportfs -v
```

输出示例：

```
/home/charliechen/imx-forge/rootfs/nfs
	192.168.60.0/24(rw,wdelay,no_root_squash,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash)
```

### 配置 /etc/nfs.conf 固定端口

这是 **WSL2 环境下最关键的一步**！因为 Windows 防火墙默认阻止所有端口，而 NFS 的 mountd、lockd、statd 服务默认使用随机端口，每次重启都会变化，根本无法提前配置防火墙规则。

**编辑 /etc/nfs.conf**：

```bash
sudo nano /etc/nfs.conf
```

添加以下内容：

```ini
[nfsd]
debug=0
port=2049

[mountd]
debug=0
port=20048

[lockd]
port=32803
udp-port=32769

[statd]
debug=0
port=32765
```

**重启 NFS 服务**：

```bash
sudo systemctl restart nfs-server
```

**验证端口固定**：

```bash
rpcinfo -p localhost
```

输出示例：

```
   program vers proto   port  service
    100000    4   tcp    111  portmapper
    100000    3   tcp    111  portmapper
    100000    2   tcp    111  portmapper
    100000    4   udp    111  portmapper
    100005    1   tcp  20048  mountd
    100005    3   tcp  20048  mountd
    100024    1   tcp  32765  status
    100021    1   tcp  32803  nlockmgr
    100003    3   tcp   2049  nfs
```

如果 `mountd`、`status`、`nlockmgr` 的端口固定了，说明配置成功。

## Windows 防火墙配置

### WSL2 mirrored 模式的特殊性

WSL2 有两种网络模式：

1. **NAT 模式**（默认）：WSL2 有自己的虚拟网络，端口通过 NAT 映射
2. **Mirrored 模式**：WSL2 直接镜像主机的网络栈，看起来像是和主机在同一网络

在 `mirrored` 模式下，如果 `firewall=true`，Windows 防火墙规则会同步到 WSL2。这意味着如果 Windows 防火墙阻止了某个端口，WSL2 里的服务也无法从外部访问。

**检查 WSL2 网络模式**：

在 Windows 用户目录下创建或编辑 `.wslconfig` 文件：

```ini
[wsl2]
networkingMode=mirrored
firewall=true
```

### 创建防火墙规则

在 **管理员 PowerShell** 中执行：

```powershell
# 基础 NFS 端口
New-NetFirewallRule -DisplayName 'NFS-TCP-111'      -Direction Inbound -Protocol TCP -LocalPort 111   -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-UDP-111'      -Direction Inbound -Protocol UDP -LocalPort 111   -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-TCP-2049'     -Direction Inbound -Protocol TCP -LocalPort 2049  -Action Allow -Profile Any

# mountd、lockd、statd 端口（需与 /etc/nfs.conf 一致）
New-NetFirewallRule -DisplayName 'NFS-mountd-20048' -Direction Inbound -Protocol TCP -LocalPort 20048 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-lockd-32803'  -Direction Inbound -Protocol TCP -LocalPort 32803 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-statd-32765'  -Direction Inbound -Protocol TCP -LocalPort 32765 -Action Allow -Profile Any
```

**验证规则创建**：

```powershell
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "NFS*"} | Format-Table -AutoSize
```

**测试端口连通性**：

```powershell
Test-NetConnection -ComputerName 192.168.60.1 -Port 2049
```

如果 `TcpTestSucceeded : True`，说明端口已放行。

## 踩坑案例 1：bootargs 中 nfsroot 路径写错

### 现象

开发板启动后内核日志显示：

```
IP-Config: Complete:
      device=eth0, hwaddr=02:aa:bb:cc:dd:ee, ipaddr=192.168.60.200, mask=255.255.255.0, gw=192.168.60.1
      host=192.168.60.200, domain=, nis-domain=(none)
      bootserver=192.168.60.1, rootserver=192.168.60.1, rootpath=
Root-NFS: No NFS server available
```

注意 `rootpath=` 是空的！

### 原因

`bootargs` 中的 `nfsroot` 参数格式错误，或者 IP 地址配置错误。

### 排查步骤

在 U-Boot 命令行中：

```bash
printenv bootargs
printenv ipaddr
printenv serverip
```

确认：
1. `nfsroot` 中的 IP 和路径是否正确
2. `ip=` 参数中的 IP 配置是否正确
3. 网络是否通畅（可以 `ping` 主机）

### 解决方法

重新设置 `bootargs`，确保格式正确：

```bash
setenv bootargs "console=ttymxc0,115200 root=/dev/nfs nfsroot=192.168.60.1:/home/charliechen/imx-forge/rootfs/nfs,vers=3,proto=tcp rw ip=192.168.60.200:192.168.60.1:192.168.60.1:255.255.255.0::eth0:off"
saveenv
```

**经验**：每次 `setenv` 后必须用 `printenv bootargs` 逐字核对，逗号前后不能有空格！

## 踩坑案例 2：bootargs 字符串被截断

### 现象

`printenv bootargs` 输出：

```
bootargs=console=ttymxc0,115200 root=/dev/nfs nfsroot=192.168.60.1:/home/.../rootfs/ip=192.168.60.200:...
```

注意 `/nfs,vers=3,proto=tcp rw` 整段丢失，`ip=` 直接拼到路径后面！

### 原因

`setenv` 输入时漏掉了参数之间的空格，或者 `nfsroot` 选项格式错误。

### 解决方法

确保 `nfsroot` 的格式是：

```
nfsroot=<IP>:<路径>,<选项>
```

选项之间用逗号分隔，**不能有空格**。

正确示例：

```bash
nfsroot=192.168.60.1:/home/charliechen/imx-forge/rootfs/nfs,vers=3,proto=tcp
```

错误示例：

```bash
nfsroot=192.168.60.1:/home/charliechen/imx-forge/rootfs/nfs, vers=3, proto=tcp
#                                                   ^ 有空格！
```

## 踩坑案例 3：/etc/exports 文件不存在

### 现象

NFS 服务启动日志报错：

```
exportfs: can't open /etc/exports for reading
```

重启后导出规则丢失，`exportfs -v` 输出为空。

### 原因

只用了 `exportfs` 命令临时导出，没有写入 `/etc/exports` 文件。

### 解决方法

必须把配置写入 `/etc/exports` 文件：

```bash
sudo bash -c 'cat > /etc/exports << EOF
/home/charliechen/imx-forge/rootfs/nfs  192.168.60.0/24(rw,sync,no_root_squash,no_subtree_check)
EOF'
```

然后应用配置：

```bash
sudo exportfs -ra
sudo systemctl restart nfs-server
```

**验证**：

```bash
sudo exportfs -v
```

应该看到你的导出规则。

**经验**：临时导出只在当前会话有效，重启后丢失。配置必须持久化到 `/etc/exports`。

## 踩坑案例 4：WSL2 mirrored 模式下防火墙拦截 NFS

### 现象

- 主机本地挂载 NFS 正常：`sudo mount -t nfs 127.0.0.1:/home/.../nfs /mnt`
- 开发板连接超时
- 内核日志在 IP 配置完成后停止输出：
  ```
  IP-Config: Complete: ...
  VFS: Mounted root (nfs filesystem).
  Freeing unused kernel memory: 1024K
  # 然后就没反应了...
  ```

### 原因

WSL2 `networkingMode=mirrored` + `firewall=true` 模式下，Windows 防火墙规则同步到 WSL，开发板发来的 NFS 请求被拦截。

### 排查步骤

**1. 在 Windows PowerShell 中测试端口连通性**：

```powershell
Test-NetConnection -ComputerName 192.168.60.1 -Port 2049
```

如果输出：

```
WARNING: TCP connect to (192.168.60.1 : 2049) failed
```

说明端口被拦截。

**2. 检查 WSL2 防火墙日志**（可选）：

```bash
sudo dmesg | grep -i firewall
```

### 解决方法

按照前面的步骤创建 Windows 防火墙规则，确保端口 111、2049、20048、32803、32765 全部放行。

## 踩坑案例 5：mountd / lockd 使用动态随机端口

### 现象

放行 111 和 2049 后仍然挂载失败。

**排查**：

```bash
rpcinfo -p | grep mountd
```

输出：

```
    100005    1   tcp  46611  mountd
    100005    3   tcp  48315  mountd
```

端口每次重启都变，根本无法提前配置防火墙！

### 原因

NFS mountd、lockd、statd 默认使用随机端口。

### 解决方法

在 `/etc/nfs.conf` 中固定端口：

```ini
[mountd]
port=20048

[lockd]
port=32803
udp-port=32769

[statd]
port=32765
```

重启 NFS 服务：

```bash
sudo systemctl restart nfs-server
```

验证：

```bash
rpcinfo -p | grep mountd
```

输出：

```
    100005    1   tcp  20048  mountd
    100005    3   tcp  20048  mountd
```

端口固定了！

然后在 Windows 防火墙中放行这些端口。

**经验**：WSL2 环境下必须固定 NFS 相关端口，否则防火墙配置无法生效。

## 踩坑案例 6：防火墙规则 Profile 为 Public 导致不生效

### 现象

防火墙规则已添加，`Get-NetFirewallRule` 可以查到，但端口仍然不通。

**排查**：

```powershell
Get-NetConnectionProfile
```

输出：

```
Name             : 网桥
InterfaceAlias   : 网桥
InterfaceIndex   : 27
NetworkCategory  : Public    ← 问题所在！
Domain           : False
IPv4Connectivity : Internet
IPv6Connectivity : Internet
```

### 原因

网桥网卡被 Windows 识别为「公用网络（Public）」，而新建防火墙规则默认只对「专用网络（Private）」生效。

### 解决方法

**方法 1：把网卡改为 Private**

```powershell
Set-NetConnectionProfile -InterfaceAlias "网桥" -NetworkCategory Private
```

**方法 2：防火墙规则覆盖所有 Profile**

```powershell
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "NFS*"} | Set-NetFirewallRule -Profile Any
```

**验证**：

```powershell
Get-NetFirewallRule -DisplayName "NFS-TCP-2049" | Select-Object DisplayName, Profile
```

输出：

```
DisplayName      Profile
-----------      -------
NFS-TCP-2049    Any
```

**经验**：WSL2 mirrored 模式下，网桥可能被识别为 Public 网络，防火墙规则需要覆盖所有 Profile。

## NFS 挂载完整流程图

理解 NFS 挂载的完整流程有助于快速定位问题：

```
┌─────────────────────────────────────────────────────────────────────┐
│                         开发板上电                                    │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  U-Boot 阶段                                                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ 1. 配置网络：ipaddr, serverip                                │   │
│  │ 2. TFTP 下载内核：tftp 0x82000000 zImage                    │   │
│  │ 3. TFTP 下载设备树：tftp 0x83000000 imx6ull-14x14-evk.dtb  │   │
│  │ 4. 设置 bootargs：包含 nfsroot 和 ip 参数                    │   │
│  │ 5. 启动内核：bootz 0x82000000 - 0x83000000                  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  内核启动阶段                                                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ 1. 解析 bootargs 中的 ip 参数，配置 eth0 网卡                │   │
│  │ 2. 输出：IP-Config: Complete: ...                           │   │
│  │ 3. 发起 NFS 挂载请求                                        │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  NFS 挂载阶段                                                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Step 1: 连接 rpcbind (TCP 111)                              │   │
│  │         └─ 获取 mountd 端口 (20048)                         │   │
│  │                                                              │   │
│  │ Step 2: 连接 mountd (TCP 20048)                             │   │
│  │         └─ 获取 NFS 文件句柄                                │   │
│  │                                                              │   │
│  │ Step 3: 连接 nfsd (TCP 2049)                                │   │
│  │         └─ 挂载根文件系统                                    │   │
│  │                                                              │   │
│  │ 成功：VFS: Mounted root (nfs filesystem)                    │   │
│  │ 失败：Root-NFS: No NFS server available                     │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  启动 /sbin/init                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ 1. 执行 /etc/inittab 中的 sysinit 动作                       │   │
│  │ 2. 运行 /etc/init.d/rcS 初始化脚本                          │   │
│  │ 3. 挂载 /proc, /sys, /tmp 等                                │   │
│  │ 4. 运行 mdev -s 创建设备节点                                 │   │
│  │ 5. 启动 getty / sh                                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  系统就绪，出现 shell 提示符                                          │
│  Welcome to i.MX6ULL Embedded Linux!                                 │
│  / #                                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

## 排查工具速查

### 主机侧命令

| 命令 | 作用 |
|------|------|
| `sudo exportfs -v` | 查看当前 NFS 导出规则 |
| `sudo ss -tnlp \| grep -E '2049\|111'` | 确认端口监听 |
| `rpcinfo -p localhost` | 查看所有 RPC 服务端口 |
| `sudo mount -t nfs -o vers=3,proto=tcp <IP>:<路径> /mnt` | 本地验证挂载 |
| `sudo tail -f /var/log/syslog` | 查看 NFS 服务日志 |

### Windows PowerShell 命令

| 命令 | 作用 |
|------|------|
| `Get-NetConnectionProfile` | 查看网卡网络类别 |
| `Get-NetFirewallRule \| Where-Object {$_.DisplayName -like "NFS*"}` | 查看 NFS 防火墙规则 |
| `Test-NetConnection -ComputerName <IP> -Port 2049` | 测试端口连通性 |
| `Set-NetConnectionProfile -InterfaceAlias "网桥" -NetworkCategory Private` | 改变网络类别 |

### U-Boot 命令

| 命令 | 作用 |
|------|------|
| `printenv bootargs` | 查看 bootargs 配置 |
| `printenv ipaddr` | 查看开发板 IP |
| `printenv serverip` | 查看主机 IP |
| `ping <主机IP>` | 测试网络连通性 |

### 内核启动日志关键字

| 关键字 | 含义 |
|--------|------|
| `IP-Config: Complete` | 网络配置成功 |
| `Root-NFS: No NFS server available` | NFS 服务器无法访问 |
| `VFS: Mounted root (nfs filesystem)` | NFS 挂载成功 |
| `Kernel panic - not syncing: No init found` | 找不到 /sbin/init |

## 常见错误信息汇总

### NFS 服务器侧

| 错误信息 | 原因 | 解决方法 |
|----------|------|----------|
| `exportfs: can't open /etc/exports` | /etc/exports 不存在或格式错误 | 检查文件语法 |
| `fsid 0: no export entry` | 导出路径不匹配 | 检查 /etc/exports 中的路径 |
| `refused mount request from 192.168.60.200` | 客户端 IP 未授权 | 检查 /etc/exports 中的客户端范围 |

### 开发板侧

| 错误信息 | 原因 | 解决方法 |
|----------|------|----------|
| `Root-NFS: No NFS server available` | 网络不通或防火墙拦截 | 检查网络、防火墙 |
| `NFS: server 192.168.60.1 not responding` | NFS 服务未启动或端口未放行 | 检查 NFS 服务状态、防火墙 |
| `nfs: server 192.168.60.1 OK` | 成功！ | - |
| `VFS: Mounted root (nfs filesystem) on device 0:15` | 成功！ | - |

## 验证 NFS 挂载成功

当你看到内核日志输出以下内容时，恭喜你，NFS 挂载成功了！

```
IP-Config: Complete:
      device=eth0, hwaddr=02:aa:bb:cc:dd:ee, ipaddr=192.168.60.200, mask=255.255.255.0, gw=192.168.60.1
      host=192.168.60.200, domain=, nis-domain=(none)
      bootserver=192.168.60.1, rootserver=192.168.60.1, rootpath=/home/charliechen/imx-forge/rootfs/nfs
Looking up port of RPC 100003/2 on 192.168.60.1
Looking up port of RPC 100005/2 on 192.168.60.1
VFS: Mounted root (nfs filesystem).
Freeing unused kernel memory: 1024K

Welcome to i.MX6ULL Embedded Linux!

/ #
```

看到 `/ #` 提示符，说明你已经成功进入了开发板的 shell！

## 下一步：应用集成

现在 Rootfs 已经通过 NFS 成功挂载，系统可以正常启动了。但是，这个 Rootfs 还是最小化的，只有 BusyBox 提供的基本命令。实际应用中，我们还需要添加更多的命令、库文件、自定义程序等。

下一章，我们将讲解：
- 如何添加更多常用命令和工具
- 静态链接 vs 动态链接的选择
- 如何处理库文件依赖
- 如何添加自定义应用程序
- 如何配置系统启动服务

准备好了吗？让我们继续完善这个 Rootfs！
