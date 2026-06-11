# 第 18 章  磁盘管理

> **Part: Part 4 · 系统管理**

---

## 引子

你插了一个 U 盘。在 Windows 里，它自动弹出来了。在 Linux 里……什么都没发生。

不是 Linux 识别不了 U 盘，而是它需要你手动「挂载」。Linux 的哲学是：设备存在是一回事，你想不想用它另一回事。你得告诉系统「把这个设备接到文件系统的这棵树上」。

`fdisk` 分区、`mkfs` 格式化、`mount` 挂载——这套流程在嵌入式开发里会反复出现：给 SD 卡分区、给 eMMC 烧录系统、给 NFS 准备共享目录……每一步都离不开磁盘管理。

但首先，有一个概念必须搞清楚：为什么 Linux 不像 Windows 那样给你一个「D 盘」？为什么它要用「挂载」这么别扭的方式？这个问题的答案，藏着 Linux 文件系统设计的核心逻辑。

---

## 背景与动机

如果你是从 Windows 转过来的，你可能习惯了这样想：C 盘装系统，D 盘放数据，E 盘是 U 盘。每个盘符对应一块物理设备，路径从盘符开始。

Linux 不这么干。在 Linux 的世界里，只有一个根——`/`。所有东西都挂在这棵树上。硬盘的某个分区可以是 `/home`，U 盘可以是 `/mnt/usb`，网络存储可以是 `/mnt/nfs`。你看到的路径和物理设备之间没有固定的盘符对应关系——它们通过「挂载」动态绑定。

这种设计在嵌入式开发中尤其重要。想象一块 i.MX 开发板：它的 eMMC 上可能有三个分区——一个放 U-Boot，一个放 Linux 内核，一个放根文件系统。在 Linux 眼里，它们就是 `/dev/mmcblk0p1`、`/dev/mmcblk0p2`、`/dev/mmcblk0p3`——通过挂载接到目录树的不同位置上。理解这套机制，是你在开发板上烧录系统、调试存储的基础。

---

## 概念层

### 没有「盘符」的世界

在 Linux 里，你看不到 C 盘、D 盘。取而代之的是一棵从 `/` 出发的目录树。硬盘、U 盘、网络存储——所有设备都只是这棵树上的某个节点。

设备文件住在 `/dev` 目录下。你可以把它们理解为硬件的「身份证」：

```bash
$ ls /dev/sd*
# 预期输出（具体因机器而异）
/dev/sda  /dev/sda1  /dev/sda2
```

命名规则很规律：

- `sd` 表示 SATA/SCSI/USB 存储设备
- 字母 `a`、`b`、`c`…… 表示第几块设备（第一块、第二块……）
- 数字 `1`、`2`、`3`…… 表示这块设备上的第几个分区

所以 `/dev/sda` 是整块硬盘，`/dev/sda1` 是这块硬盘的第一个分区。`/dev/sdb` 是第二块设备（比如你刚插的 U 盘），`/dev/sdb1` 是它的第一个分区。

你可以把 `/dev/sdb1` 想象成一栋**建筑**——它客观存在，有具体的物理地址。但这栋建筑还没有挂门牌号——你没法通过"路径"找到它。

「挂载」就是给它挂门牌号的过程。你告诉系统：把 `/dev/sdb1` 这栋建筑，挂到 `/mnt/usb` 这个地址上。从此以后，访问 `/mnt/usb` 就是访问 U 盘。

但这个比喻有一个地方需要修正：真实世界里的门牌号是固定的——建设路 108 号永远在那里。而 Linux 的挂载是**动态的**——你可以随时把 `/dev/sdb1` 从 `/mnt/usb` 摘下来，挂到 `/media/flash` 上。门牌号和建筑之间的绑定关系，由你决定。

回到那个「建筑与门牌号」的类比：你现在应该能看出来，`/dev/sdb1` 是那栋建筑（物理设备），`/mnt/usb` 是门牌号（挂载点），`mount` 命令就是把门牌号钉到建筑上去的那个动作。如果你不挂载，建筑还在那里（`/dev/sdb1` 可以被 `ls` 看到），但没人知道怎么走进去——因为没有门牌号。

### 分区与格式化

一块新硬盘（或者一张新 SD 卡）插上来，不能直接用。它需要经历两步：

**第一步：分区**——把整块硬盘切成一个或几个区域。每个区域可以独立管理，有自己的文件系统。

**第二步：格式化**——在分区上建立文件系统。没有文件系统的分区就像一间没装修的毛坯房——能放东西，但没人知道东西放在哪里。

分区工具最经典的是 `fdisk`。它只支持 MBR（Master Boot Record）分区表——一种从 DOS 时代沿用至今的格式，最多支持 4 个主分区，单分区最大 2TB。

现代系统更多使用 GPT（GUID Partition Table）分区表。GPT 没有主分区数量限制，支持超过 2TB 的分区。处理 GPT 分区表的工具是 `gdisk`。

这里有一个容易混淆的地方：新版本的 `fdisk` 其实也支持 GPT 了。但如果你明确知道要用 GPT，`gdisk` 是更专业的选择。在嵌入式开发中，给 SD 卡分区时两种都可能遇到——U-Boot 的传统教程很多还在用 MBR，但新板子越来越多地使用 GPT。

格式化的命令是 `mkfs`（**M**a**k**e **F**ile **S**ystem）：

```bash
# 把 /dev/sdb1 格式化为 ext4（Linux 原生文件系统）
$ sudo mkfs -t ext4 /dev/sdb1

# 或者格式化为 FAT32（Windows 和 Linux 都能读写）
$ sudo mkfs -t vfat /dev/sdb1
```

选什么文件系统取决于用途：只在 Linux 上用，选 `ext4`；需要和 Windows 交换数据，选 `vfat`（FAT32）。嵌入式开发中，U-Boot 分区通常用 FAT32（因为 U-Boot 本身经常以 raw 或者 FAT 方式读取），根文件系统分区用 `ext4`。

### /etc/fstab：开机自动挂载

每次开机都手动 `mount` 太烦了。Linux 提供了一个配置文件 `/etc/fstab` 来实现自动挂载：

```bash
$ cat /etc/fstab
# <file system>  <mount point>  <type>  <options>  <dump>  <pass>
UUID=xxxx-xxxx   /              ext4    defaults   0       1
UUID=yyyy-yyyy   /home          ext4    defaults   0       2
```

六个字段分别是：

| 字段 | 含义 | 示例 |
|:---:|:---|:---|
| 设备 | 设备文件路径或 UUID | `UUID=xxxx-xxxx` 或 `/dev/sda1` |
| 挂载点 | 挂载到目录树的哪个位置 | `/`、`/home`、`/mnt/usb` |
| 文件系统类型 | ext4、vfat、ntfs 等 | `ext4`、`vfat` |
| 挂载选项 | 权限和行为控制 | `defaults` |
| dump | `dump` 备份工具是否备份（0 = 不备份） | `0` |
| pass | 开机时 `fsck` 检查的顺序（0 = 不检查） | `0`、`1`、`2` |

其中 `defaults` 是一组默认挂载选项的缩写，包含 `rw`（可读写）、`suid`（允许 SUID 位生效）、`dev`（允许设备文件）、`exec`（允许执行程序）、`auto`（开机自动挂载）、`nouser`（只有 root 能挂载）、`async`（异步 I/O）。日常使用不需要改这个。

`UUID` 是设备的全局唯一标识符——比 `/dev/sda1` 这种名字更可靠，因为设备名可能因为你插拔顺序不同而变化，但 UUID 是刻在分区里的，不会变。查看设备的 UUID：

```bash
$ sudo blkid /dev/sda1
# 预期输出
/dev/sda1: UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" TYPE="ext4" PARTUUID="12345678-01"
```

### df 与 du：看空间

挂载完了，怎么看磁盘用了多少空间？

**`df`（disk free）**：查看文件系统的整体使用情况。

```bash
$ df -h
# 预期输出
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       100G   30G   66G  31% /
/dev/sda2       500G  200G  275G  42% /home
tmpfs           3.9G  1.2M  3.9G   1% /tmp
```

`-h` 表示人类可读（**h**uman-readable）——用 GB、MB 显示而不是用块数。

**`du`（disk usage）**：查看某个目录占用了多少空间。

```bash
# 查看 ~/projects 目录下每个子目录的大小
$ du -h --max-depth=1 ~/projects
# 预期输出
4.0K    /home/charlie/projects/docs
1.2G    /home/charlie/projects/kernel
850M    /home/charlie/projects/u-boot
2.1G    /home/charlie/projects

# 查看某个目录的总大小
$ du -sh ~/projects
# 预期输出
2.1G    /home/charlie/projects
```

`-s` 表示汇总（**s**ummary）——只显示总计，不展开每个子目录。`-sh` 合用就是"给我这个目录总共多大"。

两者的区别：`df` 看的是文件系统级别的空间（"这块硬盘还剩多少"），`du` 看的是目录级别的空间（"这个文件夹占了多少"）。

---

## 实践层

### 4.1 查看系统中的存储设备

先看看当前系统里有哪些存储设备：

```bash
# 列出所有块设备
$ lsblk
# 预期输出
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda      8:0    0   100G  0 disk
├─sda1   8:1    0    50G  0 part /
├─sda2   8:2    0    49G  0 part /home
└─sda3   8:3    0     1G  0 part [SWAP]
sr0     11:0    1  1024M  0 rom
```

`lsblk`（**l**i**s**t **bl**oc**k** devices）以树形结构显示所有块设备和它们的分区。`RM` 列表示是否可移除（1 = 可移除，比如 U 盘），`MOUNTPOINTS` 显示挂载位置。

比 `ls /dev/sd*` 更直观——它直接告诉你每个分区挂在了哪里。

### 4.2 给 U 盘分区和格式化

> ⚠️ **危险操作警告**
>
> 以下操作会**彻底清除** U 盘上的所有数据。
> **反复确认设备名**——如果你不小心操作了 `/dev/sda`（系统硬盘），你的系统就没了。
> 操作之前，用 `lsblk` 确认你的 U 盘是哪个设备。

假设你的 U 盘是 `/dev/sdb`（用 `lsblk` 确认）。

**用 fdisk 分区**

```bash
$ sudo fdisk /dev/sdb

# 进入 fdisk 交互界面后：
# 输入 p 查看当前分区
Command (m for help): p
# 显示当前的分区表

# 输入 d 删除已有分区（如果有的话）
Command (m for help): d
# 如果有多个分区，会问你要删哪个

# 输入 n 新建分区
Command (m for help): n
Partition type:
   p   primary (0 primary, 0 extended, 4 free)
   e   extended
Select (default p): p        # 选主分区
Partition number (1-4, default 1): 1    # 第一个分区
First sector (2048-xxx, default 2048):  # 直接回车，用默认值
Last sector (xxx-xxx, default xxx):     # 直接回车，用全部空间

# 输入 w 写入分区表并退出
Command (m for help): w
# 预期输出
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.
```

`fdisk` 里做的所有操作，在按下 `w` 之前都只是"草稿"——存在内存里，没碰硬盘。感觉搞砸了？按 `q` 退出，什么都不会发生。

**格式化分区**

```bash
# 把新分区格式化为 FAT32（跨平台兼容性最好）
$ sudo mkfs -t vfat /dev/sdb1
# 预期输出
mkfs.fat 4.2 (2021-01-31)
```

几秒钟就完成了。现在这个分区有了文件系统，可以存数据了。

### 4.3 挂载与卸载

**挂载**

```bash
# 创建挂载点
$ sudo mkdir -p /mnt/usb

# 挂载
$ sudo mount /dev/sdb1 /mnt/usb

# 验证——现在可以访问 U 盘了
$ ls /mnt/usb
# 预期输出（如果是空的 U 盘，什么都没有）
$ df -h /mnt/usb
# 预期输出
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb1       7.5G  4.0K  7.5G   1% /mnt/usb
```

现代 Linux 通常能自动检测文件系统类型，所以 `mount /dev/sdb1 /mnt/usb` 不需要加 `-t vfat`。但如果自动检测失败，手动指定：`mount -t vfat /dev/sdb1 /mnt/usb`。

**写入数据**

```bash
$ echo "Hello from Linux" > /mnt/usb/test.txt
$ cat /mnt/usb/test.txt
# 预期输出
Hello from Linux
```

**卸载**

```bash
$ sudo umount /mnt/usb
```

注意是 `umount`，不是 `unmount`——少一个 `n`。这个拼写坑了无数新手。

卸载之后，`/mnt/usb` 又变成了一个空目录。U 盘上的数据还在，只是从目录树上断开了。

> ⚠️ **常见报错：target is busy**
>
> 如果你当前就在 `/mnt/usb` 目录里（终端的工作目录是它），系统会拒绝卸载：
>
> ```
> umount: /mnt/usb: target is busy.
> ```
>
> 解决方法：`cd` 到别的目录，比如 `cd ~`，然后再 `umount`。或者用 `lsof /mnt/usb` 看看是谁在占用。

### 4.4 配置自动挂载

如果你有一块硬盘想每次开机自动挂载，编辑 `/etc/fstab`。

先查 UUID：

```bash
$ sudo blkid /dev/sdb1
# 预期输出
/dev/sdb1: UUID="ABCD-1234" TYPE="vfat" PARTUUID="12345678-01"
```

然后在 `/etc/fstab` 末尾加一行：

```bash
$ sudo tee -a /etc/fstab << 'EOF'
UUID=ABCD-1234  /mnt/usb  vfat  defaults,noauto,users  0  0
EOF
```

这里用了几个选项：`noauto`（不自动挂载——避免开机时如果 U 盘没插导致启动卡住），`users`（允许普通用户挂载）。如果希望开机自动挂载，把 `noauto` 去掉。

测试配置是否正确——不重启，直接挂载：

```bash
$ mount /mnt/usb
# 如果 fstab 配置正确，这条命令不需要指定设备名——它会从 fstab 里查
```

### 4.5 磁盘空间排查

当系统提示「No space left on device」时，用 `df` 和 `du` 定位问题：

```bash
# 先看哪个文件系统满了
$ df -h
# 找到 Use% 接近 100% 的那个分区

# 然后进去 du 找大文件
$ sudo du -h --max-depth=1 / | sort -rh | head -10
# 预期输出（从大到小列出 / 下的一级目录）
8.5G    /usr
5.2G    /home
3.1G    /var
1.2G    /snap
...
```

`sort -rh` 按**人类可读**的数值从大到小排序——`5.2G` 排在 `3.1G` 前面。不加 `-h` 选项的话，`sort -n` 会把 `5.2G` 当成字符串而不是数字，排序结果会乱。

逐级缩小范围：

```bash
# 发现 /var 占了 3.1G，进去看看
$ sudo du -h --max-depth=1 /var | sort -rh | head -5
# 预期输出
2.8G    /var/log
200M    /var/cache
50M     /var/lib
...

# /var/log 占了 2.8G——日志太多了
$ sudo du -h /var/log/*.log | sort -rh | head -5
# 预期输出
1.2G    /var/log/syslog
800M    /var/log/kern.log
500M    /var/log/syslog.1
```

找到了——`syslog` 一个文件就占了 1.2G。清理方案：

```bash
# 轮转日志（不会直接删除，而是压缩旧日志）
$ sudo logrotate -f /etc/logrotate.conf

# 或者直接清空某个日志文件（文件还在，内容清空）
$ sudo truncate -s 0 /var/log/syslog
```

> ⚠️ **不要用 `rm` 删日志文件**
>
> 有些新手会直接 `rm /var/log/syslog`，然后发现磁盘空间没有释放。原因是：如果某个进程还在往这个文件写数据，即使你 `rm` 了文件名，文件描述符还开着——磁盘空间不会被释放，直到那个进程关闭文件描述符或重启。
>
> 用 `truncate -s 0` 清空文件内容比 `rm` 安全——文件还在，进程继续写，但内容归零。

---

## 练习题

磁盘管理的操作涉及硬件，没法在每台机器上都练。下面几道题侧重理解和推理。

**练习 18.1** ⭐（理解）

在 `/etc/fstab` 中，`defaults` 挂载选项包含哪些子选项？如果要让一个分区只读挂载，应该把 `defaults` 改成什么？

> **提示**：`defaults` 包含 `rw,suid,dev,exec,auto,nouser,async`。只读就是把 `rw` 改成 `ro`。

**练习 18.2** ⭐⭐（应用）

你有一块 2TB 的硬盘，需要分成两个分区：一个 500GB 的 ext4 分区挂载到 `/data`，一个 1.5TB 的 ext4 分区挂载到 `/backup`。写出完整的操作步骤（分区 → 格式化 → 挂载 → 配置 fstab）。

> **提示**：用 `fdisk` 创建两个主分区，分别 `mkfs.ext4`，编辑 `/etc/fstab` 添加两行。

**练习 18.3** ⭐⭐⭐（思考）

`/etc/fstab` 中设备标识可以用 `/dev/sda1` 也可以用 `UUID=xxxx`。为什么推荐使用 UUID？在什么场景下 `/dev/sda1` 这种写法会出问题？

> **提示**：想象一台机器上插了两块 USB 硬盘，启动时它们的识别顺序可能因插口位置而改变——`/dev/sda` 和 `/dev/sdb` 可能互换。

---

## 本章回响

这一章的核心概念只有一个词：**挂载**。

分区也好，格式化也好，它们都是准备工作。真正的核心操作是 `mount`——它把一个物理设备（`/dev/sdb1`）绑定到目录树的一个节点（`/mnt/usb`）上。这个绑定是动态的、可逆的、由你决定的。Linux 不替你做这个决定，它只给你工具。

还记得开头那个问题吗——为什么 Linux 不像 Windows 那样自动弹出一个盘符？因为 Linux 的文件系统是一棵统一的树。如果你有十个设备，Windows 给你 C 到 L 十个盘符——十棵独立的树。Linux 把它们全部嫁接在同一棵树上——只有一个根，但可以无限生长。这种设计的代价是你得手动管理嫁接点（挂载），好处是你可以在任何一个位置接入任何一种设备，路径永远从 `/` 开始，不需要记盘符。

`df` 和 `du` 是挂载之后的管理工具——一个看全局，一个看局部。当你遇到磁盘空间不足时，`df -h` 定位是哪个分区满了，`du -h --max-depth=1` 逐级追踪是哪个目录在吃空间。这两个命令会陪伴你整个开发生涯。

下一章我们要看的是进程管理——程序跑起来了，怎么查看它、怎么控制它、跑崩了怎么收拾。磁盘是静态的存储，进程是动态的运行——理解了这两层，你就掌握了 Linux 系统管理的地基。

---

[← 上一章](ch17-software.md)
[下一章 →](ch19-process.md)
