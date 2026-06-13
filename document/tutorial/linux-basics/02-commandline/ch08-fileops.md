# 第 8 章  文件操作

> **Part 2 · 命令行生存**

---

## 引子

你能在这棵树上爬了。但光会爬还不够——你得能在上面建房子、搬家、拆旧房。

创建文件、建目录、复制、移动、删除，这些是文件系统的基本操作，也是你每天要重复几十次的动作。如果每一次都要翻手册查参数，你的开发效率会低到让人崩溃。这几个命令必须练成肌肉记忆。

但本章还有一个不那么显而易见的任务：链接。软链接（symbolic link）和硬链接（hard link）听起来像一回事——不都是「快捷方式」吗？但它们的底层机制完全不同。理解它们的区别，是理解 Linux 文件系统设计哲学的第一个窗口：**文件名和文件数据，其实是两回事。**

---

## 背景与动机

在嵌入式开发中，文件操作是家常便饭：

- 编译之前，你需要创建目录来组织源码（`mkdir`）
- 编译之后，你需要把二进制文件复制到特定位置（`cp`）
- 调试驱动时，你可能需要给设备文件建一个软链接，让应用程序用固定的路径访问它（`ln -s`）
- 清理旧编译产物时，你需要批量删除中间文件（`rm`）

这些操作在 GUI 里就是拖拽、复制、删除，但在终端里全部是命令。更关键的是——终端里的删除没有回收站。敲完回车，文件就真的没了。所以这些命令不仅要会用，还得用得准。

---

## 概念层

### 文件名 ≠ 文件内容

这是本章最重要的认知前提。

在 Windows 的思维模型里，「文件名」和「文件」是一体的——你删除了桌面上的 `report.docx`，这个文件就不存在了。

在 Linux 里，事情不是这样运作的。

Linux 文件系统的底层设计把「文件名」和「文件数据」分开了。文件数据存在磁盘的数据块里，由一个叫 **inode（索引节点）** 的结构来管理——inode 记录了文件的权限、大小、时间戳，以及数据块在磁盘上的位置。而「文件名」，只不过是挂在某个目录下、指向某个 inode 的一个**指针**。

你可以把 inode 想象成一个人——一个有血有肉、住在某个地址的实体。而文件名，只是挂在门口的**门牌号**。

但「门牌号」这个比喻需要修正：真正的门牌号是一对一的，一个门牌对应一个住户。而 Linux 的文件名和 inode 之间是多对多的——**同一个 inode 可以被多个文件名指向**。就好比同一栋房子，正面挂一个门牌「1 号」，后门再挂一个门牌「1 号后门」，两个门牌指的都是同一栋房子。

这就是硬链接的本质。理解了这一点，后面软链接和硬链接的区别就水到渠成了。

### 创建空文件—— touch

`touch` 的本职工作是**更新文件的时间戳**。如果文件不存在，它会顺手创建一个空文件——这个「副作用」反而是我们用它最多的场景。

```bash
# 创建一个空文件
$ touch readme.txt

# 验证
$ ls -l readme.txt
-rw-r--r-- 1 charlie charlie 0 Jun 11 15:00 readme.txt
```

注意文件大小是 `0`——空文件，里面什么都没有。

### 创建目录—— mkdir

`mkdir`（make directory）用来建目录。

```bash
# 创建一个目录
$ mkdir projects

# 进去看看
$ cd projects
$ pwd
/home/charlie/projects
```

但有一个常见的坑——你想建一个多层嵌套的目录：

```bash
$ mkdir projects/driver/src
# 预期输出（报错）
mkdir: cannot create directory 'projects/driver/src': No such file or directory
```

报错了。因为 `projects/driver` 这个父目录还不存在，`mkdir` 默认不会自动帮你创建中间层级。加 `-p`（parents）才行：

```bash
$ mkdir -p projects/driver/src
# 没有报错，三层目录一次性建好了
```

**`-p` 是 `mkdir` 最常用的选项，没有之一。** 每次建嵌套目录都要用到它。

### 复制—— cp

`cp`（copy）的基本格式：

```bash
cp [选项] 源文件 目标
```

几个典型场景：

```bash
# 场景 1：复制文件到同目录，顺便改名
$ cp readme.txt readme_backup.txt

# 场景 2：复制文件到另一个目录
$ cp readme.txt projects/

# 场景 3：复制整个目录（必须加 -r）
$ cp -r projects projects_backup
```

这里有一个容易踩的坑：**复制目录必须加 `-r`**（recursive），否则会报错 `cp: omitting directory`。

常用选项：

| 选项 | 作用 |
|------|------|
| `-r` | 递归复制目录及其内容 |
| `-i` | 目标已存在时询问是否覆盖 |
| `-v` | 显示复制过程 |

### 移动和改名—— mv

`mv`（move）既能移动文件，也能给文件改名。本质上是一回事——改变文件的路径。

```bash
# 改名（源和目标在同一个目录下）
$ mv readme.txt README.md

# 移动（从当前目录移到 projects 目录下）
$ mv README.md projects/

# 移动并改名
$ mv projects/README.md projects/readme_v2.txt
```

`mv` 的一个实用选项：

| 选项 | 作用 |
|------|------|
| `-i` | 目标已存在时询问是否覆盖 |

### 删除—— rm

这是整个命令行里**最危险的命令，没有之一**。

```bash
# 删除文件
$ rm readme_backup.txt

# 删除目录（必须加 -r）
$ rm -r projects_backup
```

> ⚠️ **危险命令**
> `rm` 删除的文件**不进回收站，不可恢复**。执行前务必确认路径正确。
>
> `rm -rf` 组合尤其致命：`-r` 递归删除，`-f` 强制删除（不询问确认）。如果路径写错了，比如 `rm -rf / tmp`（`/` 和 `tmp` 之间多了一个空格），系统会尝试删除根目录下的一切。
>
> **建议**：删除前先用 `ls` 预览一下要删的内容，确认无误再执行 `rm`。

常用选项：

| 选项 | 作用 |
|------|------|
| `-r` | 递归删除目录及其内容 |
| `-f` | 强制删除，不询问 |
| `-i` | 每删一个文件前都询问确认 |

### 链接—— ln（本章的认知亮点）

这里要讲的东西，是理解 Linux 文件系统设计哲学的关键一步。

`ln`（link）用来创建链接。它有两种模式：

#### 硬链接

```bash
# 创建硬链接
$ ln original.txt hardlink.txt
```

硬链接创建的是一个**直接指向 inode 的新文件名**。它和原文件共享完全相同的数据块——没有主次之分，两个文件名是平等的。

```bash
# 创建一个测试文件
$ echo "Hello, inode" > original.txt

# 创建硬链接
$ ln original.txt hardlink.txt

# 用 ls -i 查看 inode 编号
$ ls -li original.txt hardlink.txt
# 预期输出
1234567 -rw-r--r-- 2 charlie charlie 13 Jun 11 15:30 hardlink.txt
1234567 -rw-r--r-- 2 charlie charlie 13 Jun 11 15:30 original.txt
```

注意看：
1. **inode 编号相同**（第一列的 `1234567`）——它们指向同一个 inode。
2. **链接计数是 2**（第三列）——说明有两个文件名指向这个 inode。

删掉原文件会怎样？

```bash
$ rm original.txt

# 硬链接还能正常访问
$ cat hardlink.txt
# 预期输出
Hello, inode
```

文件数据毫发无损。因为 inode 还有一个文件名（`hardlink.txt`）指着它，系统不会回收它的数据块。

#### 软链接（符号链接）

```bash
# 创建软链接（注意 -s 选项）
$ ln -s target.txt symlink.txt
```

软链接创建的是一个**独立的文件**，里面存的是目标文件的路径字符串。它不直接指向 inode，而是指向一个路径。

```bash
# 创建测试文件
$ echo "I am the target" > target.txt

# 创建软链接
$ ln -s target.txt symlink.txt

# 查看 inode 编号
$ ls -li target.txt symlink.txt
# 预期输出
1234568 -rw-r--r-- 1 charlie charlie 16 Jun 11 15:35 target.txt
1234569 lrwxrwxrwx 1 charlie charlie 10 Jun 11 15:35 symlink.txt -> target.txt
```

关键区别：
1. **inode 编号不同**（`1234568` vs `1234569`）——它们是完全独立的两个文件。
2. 软链接的文件类型是 `l`（link），而且用 `->` 标出了它指向的路径。
3. 软链接的大小是目标路径字符串的长度（`target.txt` 共 10 个字节）。

删掉原文件会怎样？

```bash
$ rm target.txt

# 软链接变成了「断链」
$ cat symlink.txt
# 预期输出
cat: symlink.txt: No such file or directory
```

文件数据没了——因为软链接只是一个「指路牌」，它指向的那栋房子被拆了，路牌还在，但已经无路可走。

#### 软链接 vs 硬链接：一张对比表

| 维度 | 硬链接 | 软链接 |
|------|--------|--------|
| 本质 | 指向 inode 的另一个文件名 | 一个独立的文件，内容是目标路径 |
| inode 编号 | 和原文件**相同** | 和原文件**不同** |
| 删除原文件后 | 数据仍在，可正常访问 | 链接失效（断链） |
| 能否跨文件系统 | **不能** | 能 |
| 能否链接目录 | **不能**（通常） | 能 |
| 创建命令 | `ln 原文件 链接名` | `ln -s 原文件 链接名` |

回到那个「门牌号」的比喻：硬链接是给同一栋房子再加一块门牌——拆掉任何一块门牌，房子还在。软链接是一张写有「往东走 50 米到 1 号楼」的指路牌——1 号楼拆了，指路牌还在，但按它走过去什么都找不到。

但这个比喻也有失效的地方：硬链接不能跨文件系统——就像你不能把一栋房子的门牌挂到另一条街上的空地上。每个文件系统有自己独立的 inode 表，硬链接要求两个文件名在同一张 inode 表里，所以只能在同一个分区内。

---

## 实践层

### 4.1 建一个练习场

先在家目录下建一个安全区域，随便折腾不用担心搞坏系统：

```bash
# 确保在家目录
$ cd ~

# 创建练习目录
$ mkdir -p ~/lab/fileops

# 进去
$ cd ~/lab/fileops
```

### 4.2 文件创建和目录操作

```bash
# 创建几个空文件
$ touch a.txt b.txt c.txt

# 建一个子目录
$ mkdir subdir

# 用 tree 看一下当前结构
$ tree
# 预期输出
.
├── a.txt
├── b.txt
├── c.txt
└── subdir

1 directory, 3 files
```

### 4.3 复制、移动、改名

```bash
# 复制 a.txt 到子目录
$ cp a.txt subdir/

# 把 b.txt 改名为 b_backup.txt
$ mv b.txt b_backup.txt

# 把 c.txt 移到子目录并改名
$ mv c.txt subdir/c_renamed.txt

# 看看现在的结构
$ tree
# 预期输出
.
├── a.txt
├── b_backup.txt
└── subdir
    ├── a.txt
    └── c_renamed.txt

1 directory, 4 files
```

### 4.4 链接实验

这是本章的重点实验。我们用一个文件来观察硬链接和软链接的行为差异。

```bash
# 创建一个测试文件
$ echo "This is the original content." > original.txt

# 创建硬链接
$ ln original.txt hard.txt

# 创建软链接
$ ln -s original.txt soft.txt

# 第一步：观察 inode 编号
$ ls -li original.txt hard.txt soft.txt
# 预期输出
1234567 -rw-r--r-- 2 charlie charlie 28 Jun 11 15:50 hard.txt
1234569 lrwxrwxrwx 1 charlie charlie 12 Jun 11 15:50 soft.txt -> original.txt
1234567 -rw-r--r-- 2 charlie charlie 28 Jun 11 15:50 original.txt
```

`original.txt` 和 `hard.txt` 的 inode 编号相同（`1234567`），链接计数为 2。`soft.txt` 的 inode 编号不同（`1234569`），类型是 `l`。

```bash
# 第二步：通过硬链接修改内容
$ echo "Appended via hard link." >> hard.txt

# 看看原文件的内容——变化了
$ cat original.txt
# 预期输出
This is the original content.
Appended via hard link.

# 软链接也能看到变化
$ cat soft.txt
# 预期输出
This is the original content.
Appended via hard link.
```

不管是通过硬链接还是原文件名修改，内容都是同步的——因为它们指向同一份数据。软链接通过路径找到原文件，所以也能看到最新内容。

```bash
# 第三步：删掉原文件
$ rm original.txt

# 硬链接不受影响
$ cat hard.txt
# 预期输出
This is the original content.
Appended via hard link.

# 软链接断了
$ cat soft.txt
# 预期输出
cat: soft.txt: No such file or directory

# 看看 ls 怎么显示断链
$ ls -l soft.txt
lrwxrwxrwx 1 charlie charlie 12 Jun 11 15:50 soft.txt -> original.txt
```

软链接依然存在，指向的路径依然写着 `original.txt`——只是那个文件已经不在了。红色高亮（在彩色终端里）就是 Shell 在提醒你：这是一条断链。

### 4.5 清理练习场

实验做完了，收拾干净：

```bash
# 回到家目录
$ cd ~

# 删除整个练习目录
$ rm -rf ~/lab
```

> ⚠️ **提醒**
> `rm -rf` 不进回收站。确认路径正确后再执行。这里删的是我们自己建的 `~/lab`，没问题。

---

## 练习题

硬链接和软链接的区别是本章的认知亮点——如果你能回答下面几道题，说明你真的理解了。

**练习 8.1** ⭐（理解）

创建一个文件 `test.txt`，写入一些内容，然后给它创建一个硬链接 `hard.txt` 和一个软链接 `soft.txt`。现在执行 `echo "new line" >> hard.txt`，用 `cat` 分别查看 `hard.txt` 和 `soft.txt` 的内容。两个文件内容一样吗？为什么？

**练习 8.2** ⭐⭐（应用）

在 `/tmp` 下创建一个目录 `testdir`，在里面创建一个文件。然后给这个文件分别创建一个硬链接和一个软链接，都放在 `/tmp` 下（不在 `testdir` 里）。现在 `rm -rf /tmp/testdir`——硬链接和软链接各是什么状态？为什么？

> **提示**：回忆 inode 链接计数的机制。删掉目录里的那个文件名时，inode 的链接计数会怎样变化？

**练习 8.3** ⭐⭐⭐（思考）

为什么硬链接不能跨文件系统，而软链接可以？试从 inode 的设计角度解释这个限制。进一步思考：如果未来 Linux 要支持跨文件系统的硬链接，需要做什么改动？这个改动值得吗？

> **提示**：每个文件系统有自己独立的 inode 表。inode 编号只在同一文件系统内有意义。

---

## 本章回响

本章真正在做的事情，表面上是教你六个命令（touch / mkdir / cp / mv / rm / ln），实际上是在建立一个更底层的认知：**文件名和文件数据是两回事**。文件名指向 inode，inode 管理数据——这个分离设计是 Linux 文件系统的基石。硬链接是给同一个 inode 加一块门牌，软链接是建一个指向路径的新文件。理解了这一点，你就不再把「删除文件」理解成「数据消失了」，而是「一个文件名不再指向那个 inode 了」——当所有文件名都消失，系统才会回收数据块。

`touch`、`mkdir`、`cp`、`mv`、`rm` 这五个命令需要练成肌肉记忆。不是因为它们复杂，而是因为你用得太频繁了。每次编译代码、整理项目、清理临时文件，都要用到它们。手速上不去，开发效率就上不去。

还记得开头说的那个问题吗——软链接和硬链接「听起来像一回事，但底层机制完全不同」？现在你应该能回答了：硬链接是 inode 级别的别名，软链接是文件系统级别的重定向。它们一个住在同一张 inode 表里，一个住在自己的独立 inode 里。表面上的相似，掩盖了底层两个完全不同的世界。

下一章我们要解决另一个问题：文件建好了、搬好了，怎么快速看里面的内容？`cat`、`less`、`head`、`tail`——这些查看文件的命令，是连接文件操作和文本处理的桥梁。

---

[← 上一章](ch07-navigate.md)
[下一章 →](ch09-fileview.md)
