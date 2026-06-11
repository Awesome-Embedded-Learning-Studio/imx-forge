# 第 4 章  Windows 与 Linux 文件互传

> **Part: Part 1 · 环境搭建**

---

## 引子

你的代码在 Windows 上，编译要在 Linux 上跑，编译好的固件又要传回 Windows 去烧录。

两个系统之间隔着一堵墙。文件像被困在两个世界里，来来回回全靠 U 盘或者网盘——这效率，很快就会让你抓狂。

这堵墙的本质是什么？不是技术壁垒，而是**两套完全不同的文件系统**——Windows 的 NTFS 和 Linux 的 ext4，各自守着自己的领地，谁也不认识谁。但因为嵌入式开发的工作流天然是跨系统的，文件必须流动起来。

这堵墙有很多种穿法。有的快，有的稳，有的两者兼备。但每一种穿墙术都有它自己的代价——有的是性能上的，有的是配置上的，有的是适用场景上的。

搞清楚哪种方案适合你现在的场景，是这一章要解决的问题。

---

## 背景与动机

如果你走的是 WSL2 路线（第 1 章），你的 Linux 和 Windows 其实共享同一块硬盘，但它们看到的文件系统是分开的——Linux 有自己的根文件系统，Windows 有 C 盘 D 盘。两者之间需要一座桥。

如果你走的是虚拟机路线（第 2 章），隔离就更彻底了：虚拟机有自己虚拟的磁盘，和宿主机的硬盘在物理层面就是分开的。想把文件搬过去，得显式地建一条通道。

在嵌入式开发里，这种文件流转每天都在发生：

- 代码编辑在 Windows 上（VS Code、Source Insight），编译在 Linux 上
- 编译产物（`.bin`、`.img`）需要传回 Windows，用烧录工具刷进开发板
- 开发板抓的日志、内核配置文件，需要在 Linux 里处理后再传回来分析

说白了，只要你的工作流跨了两个系统，文件互传就不是「偶尔用用」的功能，而是每天都要走的基础设施。

---

## 概念层

三种穿墙术，对应三种不同的技术思路。

### 三扇门

你可以把这三种方案想象成两个房间之间的三扇门：

- **内置门**（WSL2 文件系统互访）——两个房间本来就连在一起，门是现成的，推开就用。但只有 WSL2 用户才有这扇门。
- **翻窗**（VMware 共享文件夹）——没有现成的门，但可以在墙上开一个口子，把指定目录「透」过去。需要动手装，但装好之后也很方便。
- **地道**（Samba 网络共享）——不走墙了，直接挖一条地道，通过网络协议连接两台机器。通用性最强，但工程量也最大。

### WSL2：两个文件系统的天然桥梁

WSL2 的架构决定了它天然具备跨文件系统访问的能力。Linux 内核跑在 Hyper-V 虚拟机里，但这个虚拟机和 Windows 之间有一条特殊的通信通道，叫做 **9P 协议**（Plan 9 File Protocol）。

通过这条通道，Linux 可以访问 Windows 的文件系统——你在 WSL2 里输入 `ls /mnt/c/`，看到的就是你 Windows 的 C 盘。反过来，Windows 资源管理器的地址栏里输入 `\\wsl$\<发行版名>`（Windows 11 较新版本是 `\\wsl.localhost\<发行版名>`），就能直接浏览 Linux 的文件系统。

但「能访问」和「好用」之间有一段距离——这一点我们在实践层会踩到。

### VMware 共享文件夹：显式打通

VMware 的共享文件夹机制比较直白：你在 VMware 里指定一个 Windows 目录，VMware 通过自己的内核模块把这个目录挂载到虚拟机的 Linux 里。

这个方案的关键在于：它只让你共享你指定的目录，而不是把整个文件系统都暴露出来。粒度可控，但也意味着你需要提前想好哪些目录需要共享。

### Samba：网络级别的万能方案

Samba 是一个实现了 SMB/CIFS 协议的服务。它的思路是：把 Linux 上的目录通过网络协议暴露出去，Windows 像访问网络邻居一样来连接。

但「地道」这个比喻有一个地方是错的：Samba 本质上不是在墙上面挖洞，而是在两台独立的机器之间拉了一条网线。它完全依赖网络，性能受网络带宽影响，而且配置项很多——防火墙、用户认证、权限映射，每一个都可能卡住你。

对于只需要在自己电脑上做开发的场景来说，Samba 通常是杀鸡用牛刀。但如果你需要让局域网里的其他机器也能访问你的 Linux 文件，它就是唯一的选择。

回到那「三扇门」的类比：你现在应该能看出来了，选择哪种方案取决于你站在哪个房间里。WSL2 用户直接走内置门，VMware 用户翻窗，Samba 则是给需要网络级共享的场景准备的。三扇门不存在谁优谁劣——它们服务的是不同的场景。

---

## 实践层

### 4.1 WSL2 文件系统互访

WSL2 提供了双向的文件访问能力，而且零配置。但这里面有一些性能细节值得注意。

#### 从 Linux 访问 Windows

打开 WSL2 终端，你的 Windows 文件系统已经挂载在 `/mnt/` 下面了：

```bash
# 查看 Windows 的 C 盘
$ ls /mnt/c/
# 预期输出（部分）
'$Recycle.Bin'   'Documents and Settings'   ProgramData   'Program Files'   'Program Files (x86)'   Users   Windows

# 进入你的 Windows 用户目录
$ cd /mnt/c/Users/$USER/
# 预期输出（进入成功，无报错）

# 在 Linux 里直接读取 Windows 上的文件
$ cat /mnt/c/Users/$USER/Desktop/test.txt
# 预期输出
Hello from Windows!
```

很好——Linux 这边没有障碍。

#### 从 Windows 访问 Linux

反过来也行。在 Windows 的资源管理器地址栏里，输入：

```
\\wsl$\Ubuntu
```

> 如果你的 WSL2 版本比较新（Windows 11 22H2 之后的更新），路径可能变成了 `\\wsl.localhost\Ubuntu`。两个路径都能用，`\\wsl.localhost` 是新格式，微软推荐用新的。

敲回车，你会看到 WSL2 的整个 Linux 根文件系统——`/home`、`/etc`、`/usr`，全都在里面。你可以直接在 Windows 里拖拽文件进出。

如果你用的是 Windows Terminal，更简单的办法是：在 WSL2 终端里输入：

```bash
# 用 Windows 资源管理器打开当前目录
$ explorer.exe .
```

这条命令会在 Windows 里打开一个资源管理器窗口，直接定位到你在 Linux 里的当前目录。

#### 性能陷阱

这里有一个坑，而且几乎每个 WSL2 用户都会踩到。

WSL2 通过 `/mnt/c/` 访问 Windows 文件系统时，性能**明显低于**访问 Linux 自己的文件系统。原因在于 9P 协议的转换层——Linux 的文件操作要先翻译成 9P 协议，再由 Windows 端的 9P 服务器处理，中间多了一整层转换。对于大量小文件的操作（比如 `git clone`、`npm install`、`make`），这个性能差距会非常明显。

```bash
# 在 /mnt/c/ 下执行 git clone（慢）
$ cd /mnt/c/Users/$USER/projects
$ time git clone https://github.com/torvalds/linux.git
# 预期耗时：可能在数分钟甚至更长

# 在 Linux 原生文件系统下执行同样的操作（快得多）
$ cd ~
$ time git clone https://github.com/torvalds/linux.git
# 预期耗时：通常快数倍
```

> ⚠️ **性能建议**
> 如果你在 WSL2 上做开发（编译、git 操作、运行脚本），**把项目放在 Linux 原生文件系统里**（`~/` 下面的某个目录），而不是放在 `/mnt/c/` 下面。用 `\\wsl$` 从 Windows 端来编辑这些文件，反过来会快得多。

这听起来有点反直觉——「把文件放在 Linux 里，用 Windows 来访问」比「把文件放在 Windows 里，用 Linux 来访问」更快。但事实就是如此。记住这个规则，能省掉你很多等待时间。

### 4.2 VMware 共享文件夹

VMware 用户没有 WSL2 那样的天然通道，需要手动配置。但只要配置好了，使用起来也很方便。

#### 安装 open-vm-tools

VMware 共享文件夹的底层依赖是 `open-vm-tools`——这是 VMware 官方提供的开源工具包，负责宿主机和虚拟机之间的各种交互，共享文件夹只是其中一项功能。

```bash
# 安装 open-vm-tools 和桌面组件
$ sudo apt update
$ sudo apt install -y open-vm-tools open-vm-tools-desktop
# 预期输出
# ...（安装过程）
# Setting up open-vm-tools (2:12.x.x-xxx) ...
```

安装完成后，重启一下虚拟机确保所有模块加载完毕：

```bash
$ sudo reboot
```

#### 在 VMware 里启用共享文件夹

这一步在宿主机的 VMware 界面里操作（不是在虚拟机里）：

1. 虚拟机关机状态下（或已安装 open-vm-tools 后运行中也可以），点击 **虚拟机 → 设置（Settings）**
2. 选择 **选项（Options）** 标签页
3. 点击 **共享文件夹（Shared Folders）**
4. 选择 **总是启用（Always enabled）**
5. 点击 **添加（Add）**，选择你要共享的 Windows 目录，给它起个名字（比如 `shared`）

配置完成后，在虚拟机里查看：

```bash
# 共享文件夹的挂载点
$ ls /mnt/hgfs/
# 预期输出
shared

# 如果什么都没有，手动挂载一下
$ sudo vmhgfs-fuse .host:/ /mnt/hgfs -o subtype=vmhgfs-fuse,allow_other
# 预期输出（无报错即成功）

# 验证——你应该能看到共享目录里的文件
$ ls /mnt/hgfs/shared/
# 预期输出：你在 Windows 共享目录里的文件列表
```

> ⚠️ **挂载点不存在？**
> 如果 `/mnt/hgfs/` 目录不存在，先手动创建它：`sudo mkdir -p /mnt/hgfs`。如果 `vmhgfs-fuse` 命令找不到，说明 `open-vm-tools` 没装成功，回去重装一遍。

#### 开机自动挂载

手动挂载重启之后就没了。要让它开机自动挂载，编辑 `/etc/fstab`：

```bash
# 在 /etc/fstab 末尾添加一行
$ echo '.host:/ /mnt/hgfs fuse.vmhgfs-fuse allow_other,defaults 0 0' | sudo tee -a /etc/fstab
```

> ⚠️ **fstab 写错会导致起不来**
> `fstab` 是系统启动时读取的挂载配置表。如果里面写了错误的条目，系统可能启动失败，直接进入 emergency mode。
> 添加之前，建议先备份：`sudo cp /etc/fstab /etc/fstab.bak`。
> 添加之后，用 `sudo mount -a` 测试一下——如果有报错，说明写错了，赶紧改回来。

### 4.3 Samba 网络共享

Samba 是三种方案里最重的。如果你只是在自己电脑上做 WSL2 或 VMware 开发，**前两种方案完全够用，不需要看这一节**。

但如果你遇到以下场景，Samba 就派上用场了：

- 虚拟机是跑在另一台机器上的，需要通过网络访问
- 团队里其他人需要访问你 Linux 上的文件
- 你用的虚拟化方案不支持共享文件夹（比如某些 KVM/QEMU 场景）

下面给出最小配置。

#### 安装 Samba

```bash
$ sudo apt install -y samba
# 预期输出
# ...（安装过程）
# Setting up samba (2:4.x.x-xxx) ...
```

#### 最小配置

Samba 的配置文件在 `/etc/samba/smb.conf`。我们不改动全局配置，只在末尾添加一个共享段：

```bash
# 备份原配置
$ sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

# 添加共享段（注意：这里用 EOF 而不是 'EOF'，让 Shell 自动展开 $USER）
$ sudo tee -a /etc/samba/smb.conf << EOF
[workspace]
   path = /home/$USER/workspace
   browseable = yes
   read only = no
   guest ok = no
   valid users = $USER
EOF
```

> 如果你不确定自己的用户名，先 `echo $USER` 看一下。上面的命令会自动把 `$USER` 替换成你的实际用户名——因为 `EOF` 没有加引号，Shell 会展开变量。

然后给 Samba 设置一个密码（这个密码和系统登录密码是独立的）：

```bash
$ sudo smbpasswd -a $USER
# 预期输出
# New SMB password:（输入你想设置的密码）
# Retype new SMB password:（再输一遍）
# Added user xxx.
```

重启 Samba 服务让配置生效：

```bash
$ sudo systemctl restart smbd nmbd
```

#### 从 Windows 连接

在 Windows 资源管理器的地址栏里输入：

```
\\<虚拟机的IP地址>\workspace
```

虚拟机的 IP 地址可以在 Linux 里用 `ip addr` 查看。如果不确定，输入：

```bash
$ ip addr show | grep 'inet ' | grep -v '127.0.0.1'
# 预期输出
# inet 192.168.xxx.xxx/24 brd 192.168.xxx.255 scope global dynamic eth0
```

找到那个 `192.168.xxx.xxx`，填到 Windows 的地址栏里。弹出认证窗口时，输入刚才用 `smbpasswd` 设置的用户名和密码。

> ⚠️ **连不上？检查防火墙**
> 如果 Windows 提示找不到网络路径，先检查 Ubuntu 的防火墙是否放行了 Samba：
> ```bash
> $ sudo ufw allow samba
> ```
> 如果用的是 VMware NAT 模式，确保虚拟机和宿主机在网络层能互相 ping 通。

---

## 练习题

走到这里，三种方案的机制应该清楚了——或者你以为清楚了。下面几道题难度递进，建议先不看提示独立想，卡住了再翻。

**练习 4.1** ⭐（理解）

你在 WSL2 里执行 `cd /mnt/c/Users/` 能正常访问 Windows 文件，但执行一个大型项目的编译（比如 `make -j8`）时，编译速度明显比在 Linux 原生文件系统下慢。为什么？应该怎么做？

**练习 4.2** ⭐⭐（应用）

你的 VMware 虚拟机重启之后，发现 `/mnt/hgfs/` 下面的共享文件夹不见了。已知你已经配置过 `/etc/fstab`。列出两种可能导致这个问题的原因，以及对应的排查步骤。

> **提示**：想一想 `open-vm-tools` 服务和 `fstab` 条目格式这两个方向。

**练习 4.3** ⭐⭐⭐（思考）

WSL2 的 `/mnt/c/` 访问和 VMware 的共享文件夹，底层机制完全不同（9P 协议 vs VMware 的内核模块），但都会遇到「跨文件系统访问的性能损耗」问题。这种损耗的本质是什么？有没有可能设计一种「零损耗」的跨文件系统访问方案？为什么？

---

## 本章回响

本章真正在做的事情，是理解跨文件系统访问的本质——它不是「搬文件」，而是「翻译文件操作」。

每一次你从 Windows 访问 Linux 的文件，或者反过来，中间都有一层翻译在工作。9P 协议在做这件事，VMware 的 vmhgfs 模块在做这件事，Samba 的 SMB 协议也在做这件事。翻译就有代价——性能的代价，配置的代价，或者灵活性的代价。理解了这一点，选哪种方案就不再是拍脑袋的决定，而是基于你的场景做出的理性选择。

还记得开头那堵墙吗？两个系统之间的墙，本质上就是两套文件系统之间的语义鸿沟。WSL2 的内置门最方便，但只属于 WSL2 用户；VMware 的翻窗需要安装配置，但适合虚拟机场景；Samba 的地道最通用，但也是最重的工程。三种穿墙术没有高下之分，只有合适与否。

下一章我们会碰到一个相关但更深层的问题——如果不只是文件需要在两个系统间流转，而是**整个开发环境**都需要隔离呢？当你不想在自己干净的系统上装一堆编译工具和依赖时，Docker 会给你一个用完即扔的干净空间。文件互传解决的是「墙」的问题，Docker 要解决的是「别在房间里搞乱」的问题。

---

[← 上一章](ch03-init.md)
[下一章 →](ch05-docker.md)
