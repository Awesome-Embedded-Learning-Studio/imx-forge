---
title: Rootfs 目录结构
---

# Rootfs 目录结构创建：Linux 文件系统的"骨架"

## 前面的话

在上一章中，我们成功编译并安装了 BusyBox。如果你现在去看 `rootfs/nfs/` 目录，会发现里面已经有了 `bin/`、`sbin/`、`usr/` 这些目录，以及一大堆指向 BusyBox 的软链接。看起来挺热闹的，对吧？

但是，别高兴得太早。如果你现在就把这个目录扔给开发板去启动，你会得到一个令人失望的结果——系统可能连启动都启动不了，或者启动后什么都做不了。为什么？因为一个真正可用的 Linux 系统，光有命令是不够的，还需要一个完整的目录结构"骨架"来支撑。

这就好比盖房子：你有了砖头和水泥（BusyBox 提供的命令），但还得有地基、承重墙、水电管道这些基础设施，房子才能真正住人。今天这篇文章，我们就来一步步搭建这个"骨架"。

## Linux 标准目录结构：FHS 是什么

在开始动手之前，我们需要先了解一下 Linux 目录结构的标准——FHS（Filesystem Hierarchy Standard，文件系统层次结构标准）。这个标准定义了 Linux 系统中各个目录应该放什么内容，目的是让不同的 Linux 发行版有一个统一的目录结构，这样软件在各个发行版之间移植起来就方便多了。

FHS 定义的目录有很多，但对于嵌入式 Rootfs 来说，我们只需要关注其中最核心的一部分：

| 目录 | 作用 | 必需性 |
|------|------|--------|
| `/bin` | 基本用户命令 | 必需 |
| `/sbin` | 系统管理命令 | 必需 |
| `/etc` | 配置文件 | 必需 |
| `/lib` | 共享库文件 | 必需 |
| `/dev` | 设备文件 | 必需 |
| `/proc` | 虚拟文件系统（进程信息） | 必需 |
| `/sys` | 虚拟文件系统（内核信息） | 必需 |
| `/tmp` | 临时文件 | 推荐 |
| `/var` | 可变数据 | 可选 |
| `/home` | 用户主目录 | 可选 |
| `/root` | root 用户主目录 | 可选 |
| `/usr` | 次要层级（更多命令和库） | 可选 |
| `/mnt` | 临时挂载点 | 可选 |

## 逐个目录详解：每个目录是干什么的

### `/bin`：基本命令目录

这个目录存放的是所有用户（包括普通用户和 root 用户）都能使用的基本命令。BusyBox 安装后，这里会有一个 `busybox` 可执行文件，以及一大堆指向它的符号链接，比如 `ls`、`cat`、`cp`、`mv` 等等。

**踩坑经验**：`/bin` 必须独立存在，不能和 `/usr/bin` 合并。为什么？因为系统启动的早期阶段，`/usr` 可能还没有挂载（比如 `usr` 是单独分区的时候），如果基本命令放在 `/usr/bin` 里，系统就没法启动了。对于嵌入式系统，通常 `/usr` 不会单独分区，但保持这个结构是个好习惯。

### `/sbin`：系统管理命令目录

`sbin` 是 "system binary" 的缩写，存放的是系统管理命令，比如 `ifconfig`、`route`、`reboot`、`halt` 等。这些命令通常只有 root 用户才需要使用。

在 BusyBox 的安装结果中，`/sbin` 和 `/bin` 里其实都是指向同一个 `busybox` 的软链接。BusyBox 不区分用户命令和系统命令，但为了保持目录结构的标准性，我们还是把它们分开存放。

### `/etc`：配置文件目录

这是整个 Rootfs 中最重要的目录之一，存放系统的所有配置文件。没有配置文件，很多程序就没法正常工作。

对于最小化的 Rootfs，`/etc` 目录下至少需要这些文件：

```
/etc/
├── inittab          # init 进程配置（BusyBox init 专用）
├── fstab            # 文件系统挂载表
├── init.d/          # 启动脚本目录
│   └── rcS          # 系统初始化脚本
├── profile          # Shell 环境变量配置
├── passwd           # 用户数据库
├── group            # 用户组数据库
├── shadow           # 用户密码（可选）
└── networks         # 网络名称数据库（可选）
```

其中 `inittab`、`fstab` 和 `rcS` 是系统启动必需的，我们后面会详细讲解。

### `/lib`：共享库目录

这个目录存放的是程序运行时需要的动态链接库文件。如果你编译的程序是动态链接的，就需要把依赖的库文件复制到这个目录里。

如何判断一个程序需要哪些库？用 `arm-none-linux-gnueabihf-readelf` 命令：

```bash
arm-none-linux-gnueabihf-readelf -d rootfs/nfs/bin/busybox | grep NEEDED
```

BusyBox 如果编译成静态链接（`CONFIG_STATIC=y`），就不需要任何库文件。但如果你要添加其他程序，大概率需要库文件支持。

### `/dev`：设备文件目录

这个目录存放的是设备文件，是 Linux 和 Unix 系统的一个特色——"一切皆文件"。在 Linux 中，硬件设备也被抽象成文件，程序可以通过读写这些文件来操作硬件。

`/dev` 目录下有一些关键的设备文件是系统启动必需的，我们稍后会详细讲解如何创建它们。

### `/proc`：进程信息虚拟文件系统

`/proc` 是一个虚拟文件系统，它不是存储在硬盘上的真实文件，而是内核在内存中动态生成的。通过读取 `/proc` 下的文件，可以查看系统的各种信息，比如 CPU 信息、内存信息、进程列表等。

这个目录不需要手动创建任何文件，只需要挂载 `proc` 文件系统即可：

```bash
mount -t proc proc /proc
```

### `/sys`：内核对象虚拟文件系统

`/sys` 也是一个虚拟文件系统，用于导出内核对象（kobjects）的层次结构。它是 Linux 2.6 内核引入的，主要用于设备管理和电源管理。

同样，这个目录不需要手动创建文件，只需要挂载：

```bash
mount -t sysfs sysfs /sys
```

### `/tmp`：临时文件目录

这个目录存放临时文件。由于嵌入式系统通常使用 Flash 存储，频繁写入会缩短 Flash 寿命，所以建议把 `/tmp` 挂载成 `tmpfs`（内存文件系统）：

```bash
mount -t tmpfs tmpfs /tmp
```

这样 `/tmp` 里的文件实际上存储在内存中，重启后会丢失，但不会损耗 Flash。

### `/usr`：次要层级

`/usr` 目录结构是 FHS 中比较复杂的一部分。它的设计理念是：`/` 下面的内容是系统启动必需的，而 `/usr` 下面的内容是系统启动后用户空间程序需要的。

对于嵌入式 Rootfs，`/usr` 通常包含：

```
/usr/
├── bin/          # 非必需的用户命令
├── sbin/         # 非必需的系统命令
└── lib/          # 非必需的共享库
```

BusyBox 安装后会在 `/usr` 下面创建一些目录，但大多数情况下是空的。

## 设备文件创建：mknod 命令详解

设备文件的创建使用 `mknod` 命令，基本语法是：

```bash
mknod [选项] 设备文件名 {b|c|p} 主设备号 次设备号
```

- `b`：块设备（block device），比如硬盘、Flash
- `c`：字符设备（character device），比如串口、键盘
- `p`：FIFO 管道
- 主设备号：标识设备驱动程序
- 次设备号：标识同一个驱动程序下的不同设备

**踩坑经验**：在支持 `devtmpfs` 的内核（2.6.32 以后）中，内核会自动创建大部分基础设备文件。但对于嵌入式系统，尤其是最小化配置的内核，手动创建一些关键设备文件是个好习惯。

## /dev 目录下的关键设备

下面这些设备文件是系统启动和运行时最常用的：

### 控制台设备：`/dev/console`

```bash
mknod -m 600 console c 5 1
```

这是系统控制台设备，内核日志和启动信息会输出到这里。如果缺少这个设备，系统启动时可能会看到 "Warning: unable to open an initial console" 的错误。

### null 设备：`/dev/null`

```bash
mknod -m 666 null c 1 3
```

这是一个"黑洞"设备，写入的数据会被丢弃。经常用来丢弃不需要的输出，或者作为需要输出但不关心结果的程序的输出目标。

### zero 设备：`/dev/zero`

```bash
mknod -m 666 zero c 1 5
```

这个设备会源源不断地输出零字节。经常用来清空文件或者初始化数据。

### 随机数设备：`/dev/random` 和 `/dev/urandom`

```bash
mknod -m 444 random c 1 8
mknod -m 444 urandom c 1 9
```

这两个设备提供随机数。`/dev/random` 是真随机数（从硬件熵池获取），熵耗尽会阻塞；`/dev/urandom` 是伪随机数，不会阻塞。对于嵌入式系统，通常使用 `/dev/urandom`。

### 内存设备：`/dev/mem`

```bash
mknod -m 640 mem c 1 1
```

这个设备提供对物理内存的访问。某些调试工具（如 `devmem`）需要它。

### tty 设备：`/dev/tty*`

```bash
mknod -m 666 tty c 5 0
mknod -m 620 tty0 c 4 0
mknod -m 620 tty1 c 4 1
# ... 更多虚拟终端
```

`tty` 是控制台终端设备的统称，`tty0`、`tty1` 等是虚拟终端设备。

### loop 设备：`/dev/loop*`

```bash
mknod -m 640 loop0 b 7 0
mknod -m 640 loop1 b 7 1
# ... 更多 loop 设备
```

loop 设备用来把普通文件模拟成块设备，比如挂载 ISO 镜像文件。

### 零内存设备：`/dev/zero`

```bash
mknod -m 666 full c 1 7
```

这是一个永远"满"的设备，写入永远不会失败，读取永远得到满的数据。可以用来测试磁盘满的情况。

## 配置文件模板

### `/etc/inittab`：init 进程配置

`inittab` 是 BusyBox `init` 进程的配置文件，定义了系统启动时的各种行为。格式是：

```
<id>:<runlevels>:<action>:<process>
```

一个最小化的配置示例：

```bash
# /etc/inittab - init process configuration

# 系统初始化
::sysinit:/etc/init.d/rcS

# 启动 getty（askfirst = 启动前提示用户按回车）
console::askfirst:-/bin/sh

# 重启处理
::restart:/sbin/init

# Ctrl+Alt+Del 处理
::ctrlaltdel:/sbin/reboot

# 关机时的操作
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
```

**各字段解释**：

- `<id>`：设备名（比如 `console`），现代 init 通常忽略这个字段
- `<runlevels>`：运行级别（BusyBox init 不支持，留空）
- `<action>`：触发条件：
  - `sysinit`：系统启动时最先执行的脚本
  - `wait`：执行后等待进程结束
  - `once`：执行一次，不等待
  - `respawn`：进程结束后自动重启
  - `askfirst`：类似 `respawn`，但启动前提示用户按回车
  - `shutdown`：关机时执行
  - `restart`：重启 init 时执行
  - `ctrlaltdel`：按下 Ctrl+Alt+Del 时执行
- `<process>`：要执行的程序或脚本

**踩坑经验**：`askfirst` 这个选项很实用，它可以防止启动时的日志输出把登录提示淹没。用户需要按一下回车才会看到 shell 提示符。

### `/etc/fstab`：文件系统挂载表

`fstab` 定义了系统启动时需要挂载的文件系统：

```bash
#<file system>  <mount point>   <type>  <options>   <dump>  <pass>
proc            /proc           proc    defaults    0       0
tmpfs           /tmp            tmpfs   defaults    0       0
sysfs           /sys            sysfs   defaults    0       0
devpts          /dev/pts        devpts  defaults    0       0
```

**各字段解释**：

- `<file system>`：要挂载的文件系统或设备
- `<mount point>`：挂载点目录
- `<type>`：文件系统类型（`proc`、`sysfs`、`tmpfs`、`devpts` 等）
- `<options>`：挂载选项，多个选项用逗号分隔
- `<dump>`：dump 备份工具的设置（0 表示不备份）
- `<pass>`：fsck 检查顺序（0 表示不检查）

### `/etc/init.d/rcS`：系统初始化脚本

这是系统启动时执行的第一个脚本，负责基本的初始化工作：

```bash
#!/bin/sh
#
# System initialization script
#

PATH=/sbin:/bin:/usr/sbin:/usr/bin:$PATH
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib:/usr/lib
export LD_LIBRARY_PATH

# 挂载 fstab 中定义的所有文件系统
mount -a

# 创建并挂载 devpts（伪终端支持）
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

# 使用 mdev 创建设备节点
mdev -s

# 配置网络接口（可选）
ifconfig lo 127.0.0.1 up

# 打印欢迎信息
echo ""
echo "Welcome to i.MX6ULL Embedded Linux!"
echo ""
```

**脚本解释**：

1. 设置 `PATH` 和 `LD_LIBRARY_PATH` 环境变量
2. 执行 `mount -a` 挂载 `fstab` 中定义的所有文件系统
3. 创建并挂载 `/dev/pts`，这是伪终端文件系统，SSH 等程序需要
4. 执行 `mdev -s`，`mdev` 是 BusyBox 的设备管理工具，`-s` 选项表示扫描 `/sys` 目录并创建相应的设备文件
5. 启动本地回环网络接口
6. 打印欢迎信息

**踩坑经验**：别忘了给这个脚本添加可执行权限：

```bash
chmod +x rootfs/nfs/etc/init.d/rcS
```

### `/etc/profile`：Shell 环境配置

这个文件在用户登录时被执行，用于设置 Shell 环境：

```bash
# /etc/profile - System-wide environment settings

# 设置路径
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# 设置库路径
export LD_LIBRARY_PATH=/lib:/usr/lib

# 设置提示符
export PS1='\u@\h:\w\$ '

# 设置语言环境
export LANG=C

# 定义一些有用的别名
alias ll='ls -l'
alias la='ls -A'
alias ..='cd ..'

# 用户登录时显示系统信息
echo ""
echo "System uptime:"
uptime
echo ""
```

### `/etc/passwd`：用户数据库

即使是最小化的嵌入式系统，也建议有一个基本的 `passwd` 文件：

```bash
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/var/empty:/bin/false
```

**格式**：`用户名:密码:UID:GID:用户信息:主目录:Shell`

- 密码字段存放 `x` 表示密码在 `/etc/shadow` 文件中（如果不用 shadow，可以存放加密后的密码）
- 对于最小化系统，可以直接把密码字段留空或设置为 `*`，这样就不需要密码了

### `/etc/group`：用户组数据库

```bash
root:x:0:
nogroup:x:65534:
```

## 完整的目录创建脚本

下面是一个完整的脚本，可以自动创建所有必需的目录和文件：

```bash
#!/bin/bash
#
# create_rootfs_structure.sh
# 创建最小化 Rootfs 目录结构
#

set -e

ROOTFS_DIR="rootfs/nfs"

echo "Creating Rootfs directory structure..."

# 创建基础目录结构
mkdir -p "${ROOTFS_DIR}/bin"
mkdir -p "${ROOTFS_DIR}/sbin"
mkdir -p "${ROOTFS_DIR}/etc/init.d"
mkdir -p "${ROOTFS_DIR}/lib"
mkdir -p "${ROOTFS_DIR}/usr/bin"
mkdir -p "${ROOTFS_DIR}/usr/sbin"
mkdir -p "${ROOTFS_DIR}/usr/lib"
mkdir -p "${ROOTFS_DIR}/dev"
mkdir -p "${ROOTFS_DIR}/proc"
mkdir -p "${ROOTFS_DIR}/sys"
mkdir -p "${ROOTFS_DIR}/tmp"
mkdir -p "${ROOTFS_DIR}/mnt"
mkdir -p "${ROOTFS_DIR}/var"
mkdir -p "${ROOTFS_DIR}/root"
mkdir -p "${ROOTFS_DIR}/home"
mkdir -p "${ROOTFS_DIR}/dev/pts"

echo "Creating device files..."

# 创建关键设备文件
mknod -m 600 "${ROOTFS_DIR}/dev/console" c 5 1
mknod -m 666 "${ROOTFS_DIR}/dev/null" c 1 3
mknod -m 666 "${ROOTFS_DIR}/dev/zero" c 1 5
mknod -m 444 "${ROOTFS_DIR}/dev/random" c 1 8
mknod -m 444 "${ROOTFS_DEV}/dev/urandom" c 1 9
mknod -m 640 "${ROOTFS_DIR}/dev/mem" c 1 1
mknod -m 666 "${ROOTFS_DIR}/dev/tty" c 5 0
mknod -m 620 "${ROOTFS_DIR}/dev/tty0" c 4 0
mknod -m 666 "${ROOTFS_DIR}/dev/full" c 1 7

echo "Creating configuration files..."

# 创建 inittab
cat > "${ROOTFS_DIR}/etc/inittab" << 'EOF'
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
EOF

# 创建 fstab
cat > "${ROOTFS_DIR}/etc/fstab" << 'EOF'
#<file system>  <mount point>   <type>  <options>   <dump>  <pass>
proc            /proc           proc    defaults    0       0
tmpfs           /tmp            tmpfs   defaults    0       0
sysfs           /sys            sysfs   defaults    0       0
devpts          /dev/pts        devpts  defaults    0       0
EOF

# 创建 rcS
cat > "${ROOTFS_DIR}/etc/init.d/rcS" << 'EOF'
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

# Configure loopback interface
ifconfig lo 127.0.0.1 up

# Print welcome message
echo ""
echo "Welcome to i.MX6ULL Embedded Linux!"
echo ""
EOF
chmod +x "${ROOTFS_DIR}/etc/init.d/rcS"

# 创建 profile
cat > "${ROOTFS_DIR}/etc/profile" << 'EOF'
# /etc/profile - System-wide environment settings

export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LD_LIBRARY_PATH=/lib:/usr/lib
export PS1='\u@\h:\w\$ '
export LANG=C

# Useful aliases
alias ll='ls -l'
alias la='ls -A'
alias ..='cd ..'
EOF

# 创建 passwd
cat > "${ROOTFS_DIR}/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/var/empty:/bin/false
EOF

# 创建 group
cat > "${ROOTFS_DIR}/etc/group" << 'EOF'
root:x:0:
nogroup:x:65534:
EOF

echo "Rootfs directory structure created successfully!"
echo ""
echo "Directory structure:"
ls -lR "${ROOTFS_DIR}"
```

把这个脚本保存为 `create_rootfs_structure.sh`，然后运行：

```bash
chmod +x create_rootfs_structure.sh
./create_rootfs_structure.sh
```

## 验证目录结构

创建完成后，可以验证一下目录结构是否正确：

```bash
# 查看目录结构
tree -L 2 rootfs/nfs/

# 如果没有 tree 命令，用 find 也可以
find rootfs/nfs/ -type d | sort

# 查看设备文件
ls -l rootfs/nfs/dev/

# 查看配置文件
cat rootfs/nfs/etc/inittab
cat rootfs/nfs/etc/fstab
```

## 下一步：NFS 网络启动踩坑

现在我们已经创建了一个完整的 Rootfs 目录结构。但是，这个 Rootfs 还在我们的开发机上，怎么让开发板使用它呢？

最简单的方法是使用 NFS（网络文件系统），让开发板通过网络挂载这个目录作为根文件系统。这样我们就不需要每次修改后都把 Rootfs 烧录到开发板的存储设备上，开发效率大大提高。

但是，NFS 网络启动的配置过程也是各种坑——U-Boot 的 `bootargs` 怎么写、NFS 服务端怎么配置、Windows 防火墙怎么设置、各种挂载失败的错误怎么排查……

下一章，我们将详细讲解 NFS 网络启动的完整配置过程，以及我踩过的各种坑和对应的解决方案。准备好了吗？我们继续！
