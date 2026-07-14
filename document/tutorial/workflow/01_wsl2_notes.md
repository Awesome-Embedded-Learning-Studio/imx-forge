---
title: WSL2 开发注意事项
---

# WSL2 开发注意事项

> 本篇是 WSL2 下做 i.MX6ULL 开发的**踩坑速查**，不重复 WSL2 入门（见 [linux-basics/ch01-wsl2](../linux-basics/01-environment/ch01-wsl2.md)）。只讲四类反复出问题的地方：网络模式、文件系统性能、TFTP 启动、NFS rootfs。

## 一、网络模式：必须切到 Mirrored

WSL2 和 Windows 是"毗邻而非共享"——各有各的网络栈。默认 **NAT 模式**下，WSL2 藏在 Windows 后面（`172.x.x.x` 内网），开发板**看不到** WSL2，TFTP/NFS 启动直接不通。

切换到 **Mirrored 模式**，WSL2 镜像 Windows 网卡，开发板才能直连 WSL2 里的 TFTP/NFS 服务。

新建/编辑 Windows 用户目录下的 `.wslconfig`：

```ini
# %USERPROFILE%\.wslconfig  即 C:\Users\你的用户名\.wslconfig
[wsl2]
networkingMode=mirrored
```

生效：

```powershell
wsl --shutdown
wsl
```

::: warning Mirrored 不是万能
Mirrored 模式会把 Windows 防火墙规则同步生效到 WSL2 这一侧，反而可能把原本能通的 NFS/TFTP 端口挡掉（见第四节）。切换后务必复查防火墙。
:::

详细原理与 NAT/Mirrored 对比见 [kernel/06_wsl_network_boot](../kernel/06_wsl_network_boot.md)。

## 二、文件系统性能：源码别放 /mnt/c/

WSL2 访问 `/mnt/c/`（Windows 文件系统）走 9P 协议，比 WSL2 原生文件系统（`~/`）慢 **5 倍以上**。编译内核/驱动源码**必须放在 WSL2 文件系统内**（如 `~/imx-forge`），不要放在 `/mnt/c/`。

更隐蔽的坑：Linux 内核源码里有同名但大小写不同的文件（如 `Makefile` 与 `makefile`）。`/mnt/c/` 所在的 Windows 文件系统大小写不敏感，会把它们当成同一个文件，导致构建错乱。

::: danger
内核源码、buildroot 源码、任何 git 仓库——一律 clone 到 WSL2 原生路径（`~/`），**不要**放到 `/mnt/c/` 或 `/mnt/d/`。
:::

详见 [kernel/mainline/02_env_setup](../kernel/mainline/02_env_setup.md)。

## 三、TFTP 网络启动

开发板从 WSL2 拉 DTB/内核时，两个坑：

### 1. Windows 防火墙拦 UDP 69

TFTP 用 UDP 69，Windows 防火墙默认拦截入站。以**管理员**身份开 PowerShell：

```powershell
New-NetFirewallRule -DisplayName 'TFTP-UDP-69' -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow -Profile Any
```

::: tip 一定用 -Profile Any
Mirrored 模式下网桥可能被识别为 Public 网络，而默认规则只对 Private 生效。`-Profile Any` 保证三种网络类型都放行。这个坑同样适用于下面的 NFS。
:::

### 2. TFTP 目录权限

开发板以匿名用户访问 TFTP，TFTP 根目录（如 `/home/charliechen/tftp`）必须让其他用户可进入：

```bash
chmod o+x /home/charliechen
```

完整 TFTP 启动流程见 [kernel/06_wsl_network_boot](../kernel/06_wsl_network_boot.md)。

## 四、NFS rootfs：端口、防火墙、网桥

NFS 比 TFTP 更容易踩坑，因为 mountd/lockd/statd 默认用**随机端口**，Windows 防火墙没法预先放行。

### 1. 固定 NFS 随机端口

编辑 `/etc/nfs.conf`（或 `/etc/default/nfs-kernel-server` 视发行版），把三个随机端口钉死：

```ini
[mountd]
port=20048
[lockd]
port=32803
udp-port=32769
[statd]
port=32765
```

### 2. 放行 Windows 防火墙

管理员 PowerShell，TCP 端口要放行（NFS v3 同时用 TCP/UDP，UDP 同理补一套）：

```powershell
New-NetFirewallRule -DisplayName 'NFS-TCP-111'   -Direction Inbound -Protocol TCP -LocalPort 111   -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-TCP-2049'  -Direction Inbound -Protocol TCP -LocalPort 2049  -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-mountd'    -Direction Inbound -Protocol TCP -LocalPort 20048 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-lockd-TCP' -Direction Inbound -Protocol TCP -LocalPort 32803 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName 'NFS-statd-TCP' -Direction Inbound -Protocol TCP -LocalPort 32765 -Action Allow -Profile Any
```

### 3. 网桥被识别为 Public

Mirrored 模式下，Windows 网桥常被归为 **Public** 网络，而前面建的规则若没带 `-Profile Any` 就只对 Private 生效。两个解法二选一：

- 规则统一加 `-Profile Any`（推荐，见上）；
- 或把网桥改成 Private：

```powershell
Set-NetConnectionProfile -InterfaceAlias "网桥别名" -NetworkCategory Private
```

### 4. Fallback：nfs-ganesha

极少数 WSL2 内核环境下，`nfs-kernel-server` 的 export 表为空（`cat /proc/fs/nfsd/exports` 空），内核 NFS 服务直接失效。这时改用用户态 **NFS-Ganesha + VFS FSAL**，绕开内核 nfsd。

完整 Ganesha 配置见 [notes/2026-06-08-wsl2-nfsroot-ganesha-troubleshoot](../../notes/2026-06-08-wsl2-nfsroot-ganesha-troubleshoot.md)。

::: warning 换 rootfs 源要重启 ganesha
用 bind-mount 换 NFS 源目录后，必须 `restart nfs-ganesha`，否则开发板挂载会 ESTALE。详见 [notes/2026-06-23-nfs-ganesha-bindmount-estale](../../notes/2026-06-23-nfs-ganesha-bindmount-estale.md)。
:::

NFS 完整踩坑记见 [rootfs/05_nfs_wsl_troubleshoot](../rootfs/05_nfs_wsl_troubleshoot.md)。

## 五、踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| 开发板 ping 不到 WSL2 | NAT 模式，WSL2 藏在内网 | `.wslconfig` 切 `networkingMode=mirrored` |
| TFTP 超时拉不到 DTB | Windows 防火墙拦 UDP 69 | 加 `-Profile Any` 的 UDP 69 放行规则 |
| TFTP 报 Permission denied | TFTP 根目录父目录无 o+x | `chmod o+x /home/用户名` |
| NFS 挂载超时/拒绝 | mountd 随机端口被防火墙挡 | `/etc/nfs.conf` 固定端口 + 防火墙放行 |
| NFS 规则建了仍不通 | 网桥被识别为 Public | 规则加 `-Profile Any` 或改网桥为 Private |
| 编译慢 5 倍以上 | 源码在 `/mnt/c/` | 移到 WSL2 原生 `~/` |
| 内核构建文件错乱 | `/mnt/c/` 大小写不敏感，Makefile/makefile 冲突 | 源码移出 `/mnt/c/` |
| nfs-kernel-server export 表空 | WSL2 内核 nfsd 失效 | 换 nfs-ganesha + VFS FSAL |
| 换 NFS 源后挂载 ESTALE | ganesha 未重载 bind-mount | `restart nfs-ganesha` |

## 继续学习

- WSL2 系统入门：[linux-basics/ch01-wsl2](../linux-basics/01-environment/ch01-wsl2.md)
- TFTP 启动全流程：[kernel/06_wsl_network_boot](../kernel/06_wsl_network_boot.md)
- NFS 踩坑完整记：[rootfs/05_nfs_wsl_troubleshoot](../rootfs/05_nfs_wsl_troubleshoot.md)
- 下一篇：[clangd 交叉编译配置](02_clangd_cross_compile.md)
