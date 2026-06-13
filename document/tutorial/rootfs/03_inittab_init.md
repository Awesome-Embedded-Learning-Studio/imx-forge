---
title: inittab 与 init
---

# inittab 与 init 系统：Linux 启动的"第一号进程"全解析

## 为什么要写这篇文章

上一章我们成功编译并安装了 BusyBox，Rootfs 目录里已经有了数百个命令的符号链接。但如果这时候你试图启动系统，很可能会看到：

```
Kernel panic - not syncing: No init found.
```

或者更惨一点：

```
Please append a correct "root=" boot option; here are the available partitions:
...
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

即使你解决了这些问题，系统启动后可能会无限重启，或者卡在一个黑屏上什么都不显示。

我当初就遇到了这些问题，而且完全不知道该从哪里下手。init 这个词太模糊了——它是一个程序？一个进程？还是系统的一个状态？inittab 又是什么？为什么一定要有这个文件？

后来我花了整整两天时间，才搞清楚 init 在系统启动链条中的位置，以及 inittab 的每一个字段是什么意思。这篇文章就是为了帮你省下这两天时间。

我们会从最基础的问题开始：
- init 到底是什么，为什么它是 PID 1
- BusyBox init 与 systemd 等其他 init 系统有什么区别
- inittab 文件的格式和每个字段的含义
- 如何配置一个能正常工作的 inittab
- 常见的启动错误和排查方法

## init 是什么：PID 1 的重量

在 Linux 系统中，进程号 1（PID 1）是一个特殊的进程。它是内核启动后创建的第一个用户空间进程，所有其他进程都是它的子孙。

为什么 PID 1 如此重要？因为：
- **孤儿进程的收养者**：当父进程先于子进程死亡时，子进程会变成孤儿进程，被 init 收养。
- **系统初始化**：init 负责启动系统所需的各种服务。
- **关机管理**：init 负责优雅地关闭系统，发送信号给所有进程。
- **进程监控**：init 可以自动重启崩溃的服务。

### init 的位置在启动链条中

```
ROM Code → U-Boot → Linux Kernel → init (PID 1) → 用户空间服务
```

内核在完成硬件初始化后，会：
1. 挂载 Rootfs
2. 查找 init 程序（通常按以下顺序）
   - 内核参数 `init=` 指定的程序
   - `/sbin/init`
   - `/etc/init`
   - `/bin/init`
   - `/bin/sh`
3. 执行 execve 启动 init

如果找不到任何一个可执行的 init，内核就会 panic：

```
Kernel panic - not syncing: No init found.  Try passing init= option to kernel.
```

> [!经验] 为什么默认查找多个位置？
> 这是历史遗留问题。不同的 Unix 系统把 init 放在不同的位置，Linux 为了兼容性，会尝试多个常见位置。

## BusyBox init 与其他 init 系统

Linux 世界有多种 init 实现，各有特点：

| init 系统 | 特点 | 适用场景 |
|-----------|------|----------|
| BusyBox init | 简单、小巧、基于 inittab | 嵌入式设备、学习理解原理 |
| SysVinit | 传统 Unix init，基于运行级别 | 传统服务器、兼容性要求高的环境 |
| systemd | 现代、功能强大、争议大 | 现代桌面、服务器发行版 |
| OpenRC | 依赖型启动系统 | Gentoo、Alpine Linux |
| runit | 简单、快速、Unix 哲学 | Void Linux |

BusyBox init 的特点：
- **极简**：核心代码只有几千行
- **inittab 配置**：易于理解和修改
- **无依赖**：不依赖外部库
- **嵌入式友好**：资源占用极低

这让我们可以完全理解系统在做什么，没有黑盒操作。

## inittab 文件格式详解

inittab 是 BusyBox init 的配置文件，位于 `/etc/inittab`。它的每一行定义一个"动作"，init 会按照这些动作来启动和管理进程。

### 基本格式

```
<id>:<runlevels>:<action>:<process>
```

| 字段 | 含义 | BusyBox init 中的处理 |
|------|------|----------------------|
| `id` | 设备名或标识符 | 用于控制终端，BusyBox 大多忽略 |
| `runlevels` | 运行级别 | BusyBox 完全忽略此字段 |
| `action` | 动作类型 | 决定何时以及如何执行 process |
| `process` | 要执行的程序 | 完整路径或可执行文件名 |

> [!注意] BusyBox 与 SysVinit 的区别
> SysVinit 使用 runlevels（0-6）来定义不同的系统状态（单用户、多用户、图形界面等）。BusyBox init 为了简化，完全忽略 runlevels 字段，只关注 action。

### action 字段详解

这是 inittab 最核心的部分。BusyBox init 支持以下 actions：

| action | 含义 | 执行时机 |
|--------|------|----------|
| `sysinit` | 系统初始化 | 启动时最先执行，只执行一次 |
| `respawn` | 自动重启 | 进程退出后自动重启 |
| `askfirst` | 交互式启动 | 类似 respawn，但启动前提示用户按 Enter |
| `wait` | 等待完成 | 启动进程后等待其结束 |
| `once` | 执行一次 | 启动时不等待，退出后不重启 |
| `ctrlaltdel` | Ctrl+Alt+Del | 用户按下 Ctrl+Alt+Del 时执行 |
| `shutdown` | 关机时 | 系统关机/重启时执行 |
| `restart` | init 重启 | init 收到 SIGHUP 后重新执行 |

### 各 action 的执行顺序

```
启动阶段：sysinit → wait → once
正常运行阶段：respawn/askfirst（持续监控）
关机阶段：shutdown
```

## IMX-Forge 项目的 inittab 解析

让我们看看 IMX-Forge 项目中实际使用的 inittab：

```bash
$ cat rootfs/nfs/etc/inittab
# /etc/inittab - init process configuration

# System initialization
::sysinit:/etc/init.d/rcS

# Console getty (askfirst = prompt before starting shell)
console::askfirst:-/bin/sh

# Restart handling
::restart:/sbin/init

# Ctrl+Alt+Del handling
::ctrlaltdel:/sbin/reboot

# Shutdown actions
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
```

让我们逐行分析：

### 第 1 行：系统初始化

```bash
::sysinit:/etc/init.d/rcS
```

- `id`：空（不需要控制终端）
- `runlevels`：空（BusyBox 忽略）
- `action`：`sysinit` - 启动时首先执行
- `process`：`/etc/init.d/rcS` - 初始化脚本

这是系统启动后执行的第一条命令。rcS 脚本负责：
- 挂载文件系统（`mount -a`）
- 创建设备节点（`mdev -s`）
- 设置网络
- 其他初始化任务

### 第 2 行：控制台 Shell

```bash
console::askfirst:-/bin/sh
```

- `id`：`console` - 使用控制台设备
- `runlevels`：空
- `action`：`askfirst` - 交互式启动
- `process`：`-/bin/sh` - 登录 shell

`askfirst` 的特点：启动前会显示提示信息，等待用户按 Enter：

```
Please press Enter to activate this console.
```

前导的 `-` 告诉 init 将此进程作为登录 shell 处理（在某些实现中会设置环境变量）。

> [!经验] askfirst vs respawn
> 开发调试时用 `askfirst` 更好——你可以有时间看到启动信息，选择何时进入 shell。
> 生产环境可以用 `respawn` 自动进入 shell（但安全风险较高）。

### 第 3 行：重启处理

```bash
::restart:/sbin/init
```

当 init 收到 SIGHUP 信号时，会重新执行自己。这在重新加载配置时有用。

### 第 4 行：Ctrl+Alt+Del 处理

```bash
::ctrlaltdel:/sbin/reboot
```

用户按下 Ctrl+Alt+Del 三键时执行 reboot。在嵌入式系统中通常没有键盘，这行一般用不上。

### 第 5-6 行：关机处理

```bash
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
```

关机时执行：卸载所有文件系统，关闭交换分区。

## rcS 启动脚本详解

init 通过 inittab 调用 `/etc/init.d/rcS`，让我们看看这个脚本做了什么：

```bash
$ cat rootfs/nfs/etc/init.d/rcS
#!/bin/sh
#
# System initialization script
#

PATH=/sbin:/bin:/usr/sbin:/usr/bin:$PATH
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib:/usr/lib
export LD_LIBRARY_PATH

# Mount all filesystems specified in fstab
mount -a

# Create and mount devpts for pseudo-terminal support
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

# Populate /dev with device nodes
mdev -s
```

### 脚本逐行解析

1. **PATH 设置**：确保系统能找到常用命令
2. **LD_LIBRARY_PATH**：指定动态库搜索路径
3. **mount -a**：读取 `/etc/fstab`，挂载所有文件系统
4. **mkdir -p /dev/pts && mount -t devpts devpts /dev/pts**：挂载伪终端
5. **mdev -s**：创建设备节点

### fstab 文件系统挂载表

```bash
$ cat rootfs/nfs/etc/fstab
# /etc/fstab: static file system information

proc            /proc   proc    defaults          0       0
devpts          /dev/pts devpts  defaults          0       0
tmpfs           /tmp    tmpfs   defaults          0       0
```

每行的含义：
- 第 1 列：设备或虚拟文件系统
- 第 2 列：挂载点
- 第 3 列：文件系统类型
- 第 4 列：挂载选项
- 第 5-6 列：dump 和 fsck 选项（嵌入式一般设为 0）

## mdev：BusyBox 的设备管理器

`mdev -s` 是 BusyBox 的设备管理器，相当于精简版的 udev。它的作用：

- **扫描 `/sys` 目录**：读取内核设备信息
- **创建设备节点**：在 `/dev` 下创建对应的设备文件
- **热插拔支持**：配合内核的热插拔机制动态管理设备

`mdev -s` 中的 `-s` 表示"扫描"模式，启动时创建所有设备节点。

## 完整的启动流程

现在我们可以画出完整的启动流程图：

```
1. 内核完成初始化
   ↓
2. 内核查找 init 程序
   ↓
3. init 启动（PID 1）
   ↓
4. init 读取 /etc/inittab
   ↓
5. 执行 sysinit 动作：/etc/init.d/rcS
   ├─ mount -a（挂载 fstab 中的文件系统）
   ├─ mount devpts（挂载伪终端）
   └─ mdev -s（创建设备节点）
   ↓
6. 执行 wait/once 动作
   ↓
7. 执行 askfirst/respawn 动作
   ├─ 显示 "Please press Enter..."
   ├─ 用户按 Enter
   └─ 启动 /bin/sh
   ↓
8. 系统就绪，等待用户输入
   ↓
9. 关机时执行 shutdown 动作
```

## 常见启动错误排查

### 错误 1：No init found

```
Kernel panic - not syncing: No init found.
```

**原因**：
- Rootfs 没有正确挂载
- `/sbin/init`、`/bin/init`、`/bin/sh` 都不存在或不可执行
- Rootfs 架构不匹配（x86 的 busybox 在 ARM 上运行）

**排查**：
1. 检查 bootargs 中的 root 参数是否正确
2. 检查 Rootfs 目录中是否有 `/bin/busybox`
3. 确认 busybox 架构是否正确：

```bash
$ file rootfs/nfs/bin/busybox
rootfs/nfs/bin/busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV)
```

### 错误 2：inittab 格式错误

```
Bad inittab entry at line 5
```

**原因**：inittab 文件格式不正确

**排查**：检查 inittab 每行的格式：
- 是否有 4 个字段（用冒号分隔）
- 冒号数量是否正确（注意空字段也要有冒号）
- action 是否拼写正确

### 错误 3：rcS 脚本无法执行

```
exec: can't execute '/etc/init.d/rcS': Permission denied
```

**原因**：rcS 没有执行权限

**解决**：

```bash
chmod +x rootfs/nfs/etc/init.d/rcS
```

### 错误 4：设备节点缺失

```
sh: can't access tty; job control turned off
```

**原因**：`/dev/console` 或 `/dev/null` 等基本设备节点不存在

**解决**：确保 rcS 中有 `mdev -s`，或者手动创建基本节点：

```bash
# 在主机上（开发阶段）
sudo mknod rootfs/nfs/dev/console c 5 1
sudo mknod rootfs/nfs/dev/null c 1 3
```

### 错误 5：无限重启

系统启动后立即重启，循环往复。

**原因**：
- init 崩溃（内核会自动重启 PID 1）
- rcS 脚本中有导致系统重启的命令

**排查**：
1. 检查 rcS 脚本是否有错误
2. 使用内核参数 `init=/bin/sh` 跳过 inittab，直接进入 shell 排查

## 高级配置技巧

### 启动多个 getty（多个串口）

```bash
# Main console
ttyAMA0::askfirst:-/bin/sh

# Second console
ttyAMA1::askfirst:-/bin/sh

# USB serial
ttyUSB0::askfirst:-/bin/sh
```

### 自定义启动信息

在 rcS 中添加：

```bash
echo "==================================="
echo "Welcome to IMX-Forge Embedded Linux"
echo "Kernel: $(uname -r)"
echo "Hostname: $(hostname)"
echo "==================================="
```

### 网络自动配置

在 rcS 中添加：

```bash
# Bring up network interface
ifconfig eth0 up
udhcpc -i eth0 -n  # 获取 IP 地址
```

### 启动自定义服务

在 inittab 中添加：

```bash
# Start custom application
::once:/usr/bin/my_app --daemon
```

或者创建启动脚本：

```bash
::sysinit:/etc/init.d/rcS
::wait:/etc/init.d/S99myapp
```

## 调试技巧

### 查看 init 日志

BusyBox init 会将日志输出到系统控制台和 `/dev/log`（如果配置了 syslog）。你可以：

1. 启动时观察串口输出
2. 在内核参数中添加 `loglevel=8` 获取更详细的日志

### 手动测试 rcS

在主板上通过 NFS 挂载 Rootfs 后，可以手动测试：

```bash
# 手动执行 rcS
/etc/init.d/rcS

# 检查是否成功
echo $?
```

### 使用 strace 追踪 init

如果 init 有异常行为，可以：

```bash
# 在内核参数中使用 busybox init 的 strace 版本
init=/bin/busybox strace -f -o /tmp/init.trace /sbin/init
```

## 写在最后

通过这一章，你应该理解了：

- init 是 PID 1，是系统启动后的第一个用户空间进程
- inittab 是 init 的配置文件，定义了启动阶段要执行的各种动作
- BusyBox init 简单但功能完整，非常适合嵌入式系统
- rcS 脚本负责系统初始化，包括挂载文件系统和创建设备节点
- 常见的启动错误和排查方法

现在你已经有了一个可以启动的 BusyBox Rootfs（假设你按照前面的步骤完成了）。但启动后你会发现——目录结构还不完整，缺少很多必要的文件和目录。
