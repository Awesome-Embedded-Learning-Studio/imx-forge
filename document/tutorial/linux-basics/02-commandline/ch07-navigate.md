# 第 7 章  目录导航

> **Part 2 · 命令行生存**

---

## 引子

你现在能在终端里打字了。但打完字之后呢？

「我在哪？」「文件放哪了？」「怎么去那个目录？」

在 Windows 里，你用鼠标点文件夹，地址栏里 `C:\Users\charlie\Documents` 一目了然。在终端里，这些动作全部变成文字。而且更让人困惑的是——你在 Linux 里找不到 C 盘，也找不到 D 盘。整个文件系统就是一棵倒挂的树，根在最上面，所有东西都挂在根下面。

学会在这棵树上爬，是命令行生存的第一课。

但这里有一个微妙的转折：这棵「树」的组织方式不是随意的——它遵循一套叫 FHS 的标准。理解了这套标准，你就不再是在黑暗中乱撞，而是有了一张地图。

---

## 背景与动机

做嵌入式开发的时候，你会频繁地在几个目录之间来回穿梭：源码在 `/home` 下，交叉编译工具链在 `/opt` 或 `/usr` 下，设备文件在 `/dev` 里，配置文件在 `/etc` 里，内核模块在 `/lib/modules` 下面……

如果你不知道这些目录各自是什么角色，每次找文件都像在陌生城市里瞎逛——靠运气。知道 FHS（Filesystem Hierarchy Standard，文件系统层次标准）之后，你就相当于拿到了这座城市的分区地图。

先认路，再干活。

---

## 概念层

### 一棵树，没有盘符

Windows 把不同的分区隔离成 C 盘、D 盘、E 盘——像几本独立的册子摆在书架上。

Linux 不是这样。**Linux 只有一个根目录 `/`，所有东西都在这一棵树下面。** 新硬盘、U 盘、网络存储——它们不是变成新的盘符，而是被「挂载」到这棵树的某个节点上，变成树的一部分。

你可以把 Linux 的文件系统想象成**一棵倒挂的树**——`/` 是树根，在最上面；各级目录是树枝，越分越细；文件是树叶，挂在最末端的枝条上。

但「倒挂的树」这个比喻有一个地方需要修正：真正的树，枝条和树根是固定长在一起的。而 Linux 的「树」是可拆卸的——你可以把一根枝条（一个分区）拔下来，换一根新的插上去，对整棵树的其他部分毫无影响。这就是「挂载」做的事情：把一个新的子树嫁接到主树的某个节点上。

### FHS：文件系统的城市分区图

根目录 `/` 下面那些默认的文件夹不是随便建的。它们遵循 **FHS（Filesystem Hierarchy Standard）**——一个规定了「什么文件应该放在什么位置」的标准。

了解这些目录的角色，就像拿到了一座城市的分区地图：

| 目录 | 是干嘛的 | 你的权限 |
|------|----------|----------|
| `/bin` | 基础命令（`ls`、`cp`、`mv` 等） | 只读 |
| `/sbin` | 系统管理命令（`reboot`、`fdisk` 等） | 需要 root |
| `/boot` | 内核和启动文件 | 别动，动完起不来 |
| `/dev` | 设备文件——**驱动开发的战场** | 可查看 |
| `/etc` | 系统配置文件 | 经常需要改 |
| `/home` | **你的家**——代码、文档全在这 | 随便折腾 |
| `/root` | 超级用户 root 的家 | 普通用户进不去 |
| `/lib` | 共享库文件（类似 Windows 的 DLL） | 只读 |
| `/mnt` | 临时挂载点 | 挂 U 盘时用 |
| `/opt` | 可选软件包 | 偶尔用到 |
| `/proc` | 虚拟目录，内核实时信息 | 只读 |
| `/tmp` | 临时文件，重启后可能清空 | 可读写 |
| `/usr` | 用户程序（二级层次，`/usr/bin` 下全是命令） | 只读为主 |
| `/var` | 可变数据（日志、缓存等） | 可查看 |

> ⚠️ **注意**
> 在 Ubuntu 22.04/24.04 中，`/bin`、`/sbin`、`/lib` 实际上是指向 `/usr/bin`、`/usr/sbin`、`/usr/lib` 的**符号链接**。这是从 Ubuntu 19.04 开始的统一改动（`usrmerge`），目的是简化文件系统布局。你用 `ls /bin` 看到的内容和 `ls /usr/bin` 是一样的——它们指向同一个地方。

回到那棵倒挂的树——你现在应该能看出来了：`/home` 是你的私人花园，你可以随便种花种草；`/etc` 是市政厅的文件柜，改配置要小心；`/boot` 是地基，动不得。每个目录都有自己的角色，各司其职。

### 绝对路径 vs 相对路径

在树上的任何一个位置，都有两种方式描述它：

**绝对路径**：从树根 `/` 开始，一级一级写下来。就像写一个完整的邮寄地址——「中国→北京→海淀区→中关村大街→1号」。

```bash
/home/charlie/projects/driver
```

不管你当前在哪个目录，绝对路径永远指向同一个位置。

**相对路径**：从你**当前位置**出发，描述目标在哪。就像说「往前走两步，右转进第三个门」。

```bash
# 假设你当前在 /home/charlie
projects/driver      # 往下走：进 projects，再进 driver
..                   # 往上走：回到 /home
../charlie/projects  # 先上再下：回到 /home/charlie/projects
```

几个特殊的路径符号：

| 符号 | 含义 |
|------|------|
| `.` | 当前目录 |
| `..` | 上一级目录（父目录） |
| `~` | 当前用户的家目录 |

绝对路径不会迷路，但打字多。相对路径省事，但你得清楚自己在哪。日常使用中两种混着来，哪个方便用哪个。

---

## 实践层

### 4.1 我在哪？—— pwd

迷路了，先搞清楚自己在哪里。`pwd`（Print Working Directory）不需要任何参数：

```bash
$ pwd
# 预期输出
/home/charlie
```

就这么简单。它永远告诉你绝对路径——你在树上的精确坐标。

刚打开终端时，你默认在家目录 `~`（即 `/home/你的用户名`）。

### 4.2 去哪？—— cd

`cd`（Change Directory）是你在树上爬来爬去的工具。

```bash
# 去根目录——树的最高点
$ cd /
$ pwd
/

# 去某个具体目录
$ cd /home/charlie
$ pwd
/home/charlie

# 去上一级
$ cd ..
$ pwd
/home

# 回家（三种写法效果相同）
$ cd ~
$ cd
$ pwd
/home/charlie
```

几个常用快捷操作：

```bash
# 回到上一次所在的目录（不是上一级，是"刚才那个地方"）
$ cd /usr
$ cd -
/home/charlie
# 再按一次 cd - 会回到 /usr，像开关一样来回跳
```

`cd -` 是一个容易被忽略但非常好用的技巧——当你在两个目录之间来回切换时，不用每次都打完整路径。

### 4.3 里面有什么？—— ls

`ls` 是你用得最多的命令之一。它有很多选项，这里挑最实用的讲。

```bash
# 最基本的：列出当前目录的文件名
$ ls
# 预期输出
Desktop  Documents  Downloads  Music  Pictures  Videos

# 加 -l：详细信息（权限、所有者、大小、时间）
$ ls -l
# 预期输出
total 24
drwxr-xr-x  2 charlie charlie 4096 Jun 10 10:00 Desktop
drwxr-xr-x  2 charlie charlie 4096 Jun 10 10:00 Documents
drwxr-xr-x  2 charlie charlie 4096 Jun 10 10:00 Downloads
-rw-r--r--  1 charlie charlie  220 Jun  9 09:00 .bash_logout
```

等等——第二条命令的输出里出现了 `.bash_logout`，但第一条没有？

在 Linux 里，以 `.` 开头的文件和目录是**隐藏的**。普通 `ls` 看不到它们。要看全部文件，加 `-a`（all）：

```bash
# 加 -a：显示隐藏文件
$ ls -a
# 预期输出
.  ..  .bash_history  .bash_logout  .bashrc  .profile
Desktop  Documents  Downloads  Music  Pictures  Videos
```

这里出现了两个特殊的目录：`.` 和 `..`。`.` 是当前目录自己，`..` 是上一级目录——就是上一节路径符号里讲的那两个。

**选项可以组合**。最常用的组合是 `-la`（或 `-al`，顺序无所谓）：

```bash
$ ls -la
# 预期输出
total 48
drwxr-xr-x  6 charlie charlie 4096 Jun 10 14:00 .
drwxr-xr-x  3 root    root    4096 Jun  9 09:00 ..
-rw-r--r--  1 charlie charlie  220 Jun  9 09:00 .bash_logout
-rw-r--r--  1 charlie charlie 3771 Jun  9 09:00 .bashrc
drwxr-xr-x  2 charlie charlie 4096 Jun 10 10:00 Desktop
```

还有两个实用选项：

```bash
# -h：人类可读的文件大小（用 K、M、G 代替字节数）
$ ls -lh
# 预期输出
total 24K
drwxr-xr-x  2 charlie charlie 4.0K Jun 10 10:00 Desktop
-rw-r--r--  1 charlie charlie  220 Jun  9 09:00 .bash_logout

# -R：递归列出所有子目录的内容（深目录慎用，输出会很长）
$ ls -R ~/Documents
# 预期输出
/home/charlie/Documents:
notes  projects

/home/charlie/Documents/notes:
todo.txt

/home/charlie/Documents/projects:
driver  kernel
```

### 4.4 看树的全貌—— tree

`ls -R` 虽然能递归显示，但输出是扁平的，不容易看层级关系。`tree` 命令会以树状图显示目录结构，一目了然：

```bash
$ tree ~/Documents
# 预期输出
/home/charlie/Documents
├── notes
│   └── todo.txt
└── projects
    ├── driver
    └── kernel

4 directories, 1 file
```

但有一个问题——Ubuntu 默认**没有安装** `tree`。需要先装一下：

```bash
$ sudo apt install tree
```

装完之后就可以用了。常用选项：

```bash
# 只显示目录结构，不显示文件
$ tree -d ~/Documents

# 限制显示深度（只看 2 层）
$ tree -L 2 ~
```

### 4.5 实战：逛一圈根目录

把前面学的命令串起来，在根目录下逛一圈，看看 FHS 标准下各目录里都装了什么：

```bash
# 先去根目录
$ cd /

# 看看根目录下有哪些文件夹
$ ls
# 预期输出
bin  boot  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var

# 看看 /etc 里有哪些配置文件（只看前几个）
$ ls /etc | head -10
# 预期输出（实际可能不同）
adduser.conf
aliases
alternatives
apt
bash.bashrc
cron.d
default
dpkg
fstab
group

# 看看 /home 下有哪些用户
$ ls /home
# 预期输出
charlie

# 看看 /dev 里的设备文件（只看前几个）
$ ls /dev | head -10
# 预期输出
autofs
block
btrfs-control
cdrom
char
console
core
cpu
cpu_dma_latency
```

逛完了，回家：

```bash
$ cd ~
```

---

## 练习题

到这里，你应该能在文件系统这棵树上认路了。下面几道题从认路到跑路，难度递进。

**练习 7.1** ⭐（理解）

执行 `cd /usr`，然后执行 `cd ..`，你现在在哪？再执行 `cd ../usr` 呢？用 `pwd` 验证你的判断。

**练习 7.2** ⭐⭐（应用）

不用 `cd`，只用 `ls` 的参数组合，完成以下任务：
1. 列出 `/etc` 下所有以 `.conf` 结尾的文件
2. 列出你 home 目录下所有隐藏文件（包括隐藏目录）的详细信息
3. 以人类可读格式列出 `/var/log` 下的文件大小

> **提示**：第 1 题可以用 `ls /etc/*.conf`；第 3 题需要组合两个选项。

**练习 7.3** ⭐⭐⭐（思考）

在 Ubuntu 22.04/24.04 上执行 `ls -la /bin` 和 `ls -la /usr/bin`，观察它们的第一行输出。你发现了什么？为什么会出现这种现象？这对你在编写 Shell 脚本时使用 `#!/bin/sh` vs `#!/bin/bash` 有什么影响？

> **提示**：回忆本章提到的 `usrmerge` 改动，以及第 6 章关于 `/bin/sh` 指向 dash 的讨论。

---

## 本章回响

本章建立的核心认知，是「Linux 的文件系统是一棵树」这个模型。这棵树的根是 `/`，所有文件、目录、设备、甚至内核的运行状态，都挂在这棵树的某个节点上。你不需要记住每一个目录里有什么——你需要记住的是那张 FHS 分区地图：`/home` 是你的私人领地，`/etc` 是配置文件的大本营，`/dev` 是硬件设备的入口，`/usr` 是用户程序的聚集地。记住这几条，你在文件系统里就不会迷路。

`pwd`、`cd`、`ls`、`tree`——这四个命令构成了你在树上认路的全部工具。`pwd` 告诉你在哪，`cd` 带你去别的地方，`ls` 让你看看周围有什么，`tree` 给你一张全景图。就这四个，够你在这棵树上自由移动了。

还记得开头那个问题吗——「我在哪？文件在哪？」现在你有了答案：你在 `/home/你的用户名`，文件在 FHS 标准规定的位置里，而绝对路径和相对路径是描述位置的两套语言。C 盘 D 盘的模型已经被拆掉了，取而代之的是一棵统一的、有秩序的目录树。

下一章我们要在这棵树上动手了——创建文件、建目录、复制、移动、删除，还有本章概念层里提到的那个「嫁接」操作的正式形态：链接。这些是文件操作的基本功，也是你每天要重复几十次的动作。

---

[← 上一章](ch06-shell.md)
[下一章 →](ch08-fileops.md)
