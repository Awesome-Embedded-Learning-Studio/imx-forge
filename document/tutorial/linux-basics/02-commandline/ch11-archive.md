# 第 11 章  压缩归档

> **Part: Part 2 · 命令行生存**

---

## 引子

你要下载一个开源项目，压缩包是 `.tar.gz` 结尾的。
你要把一整个目录传给同事，发过去之前得先打个包。

压缩和归档是两件事——但在 Linux 的世界里，它们经常被绑在一起做。`tar` 负责打包，`gzip` 负责压缩，两个工具配合出来的 `.tar.gz` 格式，是嵌入式开发中你会遇到最多的文件格式。

那个解压命令 `tar -xzf something.tar.gz`——你大概率已经照抄过很多次了。但 `-xzf` 这三个字母到底在说什么？为什么有时候又冒出来一个 `-czf`？`z` 是什么意思，能不能省掉？

这些问题背后藏着一个更根本的设计：为什么 Linux 不像 Windows 那样给一个"右键 → 压缩"就完事的工具，而是把打包和压缩拆成了两步？

理解这件事，是你和开源社区打交道的基本功。

---

## 背景与动机

如果你做过嵌入式开发，以下场景一定不陌生：

- 下载 Linux 内核源码，文件名是 `linux-6.1.tar.xz`
- 下载 U-Boot 源码，拿到的是 `u-boot-2023.10.tar.bz2`
- 交叉编译工具链，安装包是 `gcc-arm-10.3.tar.xz`
- 给同事发一整个工程目录，你得先打个包

这些 `.tar.gz`、`.tar.bz2`、`.tar.xz` 后缀不是随便起的——它们精确地描述了这个文件经历了什么：先用 `tar` 把一堆文件打成一个大文件（归档），再用某种压缩算法把它缩小（压缩）。

Windows 用户习惯了 `.zip` 和 `.rar`——一个工具同时搞定打包和压缩。Linux 的哲学不一样：一个工具只做一件事，做到极致。打包是打包，压缩是压缩，各管各的。这种拆分看起来多了一步，但它带来了极大的灵活性——你可以自由选择打包工具和压缩工具的组合。

对于嵌入式开发者来说，这是日常操作。不会解压 `.tar.gz`，你连源码都拿不到。

---

## 概念层

### 两件事：归档与压缩

先把这个最根本的区别钉死。

**归档（Archiving）**：把一堆文件和目录合并成一个文件。不减小体积，只是把它们"捆"在一起，方便传输和管理。

**压缩（Compression）**：用算法减小单个文件的体积。只能处理一个文件。

你可以把归档想象成**把散落的东西装进一个纸箱**——纸箱本身不会让东西变小，只是方便搬运。压缩则是**用真空袋把衣服里的空气抽掉**——体积确实变小了，但真空袋只能装一件东西。

但这个比喻有一个地方会让人产生误解：真正的纸箱装完就结束了，而 `tar` 打出来的包还能被压缩工具二次处理。纸箱和真空袋是两道独立的工序——`tar` 不会帮你压缩，`gzip` 也不会帮你打包。它们各自只负责一道工序。

这正是 `.tar.gz` 这个后缀的含义：`.tar` 说明它先被 `tar` 归档了，`.gz` 说明归档之后又被 `gzip` 压缩了。两步工序，两个工具，一个文件。

回到那个纸箱的类比：你现在应该能看出来，`tar` 就是那个纸箱（把散落的东西装进去），`gzip` 就是那个真空袋（把纸箱里的空气抽掉）。如果你只用 `tar` 不压缩，你得到的就是一个原大小的箱子。如果你只用 `gzip` 不打包，你只能压缩单个文件——散落在桌面上的十件衣服，你得一件一件地装真空袋，十件衣服十个袋，运输起来照样麻烦。

所以日常操作中，打包和压缩几乎总是一起出现的。

### tar：打包机

`tar` 这个名字来自 **T**ape **AR**chiver——磁带归档器。它的原始用途是把文件备份到磁带上。磁带是顺序读写的介质，所以 `tar` 的格式天然就是"把所有文件首尾相连拼成一个流"。这个设计一直沿用到了今天。

`tar` 的核心参数就那么几个，但组合起来容易让人晕。先把骨架列出来：

| 参数 | 含义 | 记忆方式 |
|:---:|:---|:---|
| `-c` | **c**reate，创建归档 | 创建 = 打包 |
| `-x` | e**x**tract，提取归档 | 提取 = 解包 |
| `-t` | lis**t**，列出归档内容 | 先看看里面有什么 |
| `-v` | **v**erbose，显示过程 | 让它边干边说 |
| `-f` | **f**ile，指定文件名 | 后面跟的是文件名 |
| `-z` | 用 **g**zip 压缩/解压 | `.tar.gz` 的 `z` |
| `-j` | 用 **b**zip2 压缩/解压 | `.tar.bz2` 的 `j` |
| `-J` | 用 **x**z 压缩/解压 | `.tar.xz` 的 `J` |

> ⚠️ **关于 `-` 前缀**
>
> `tar` 是一个很古老的命令，它诞生在还没有参数标准化的年代。所以 `tar` 的参数前面加不加 `-` 都行：`tar -czf` 和 `tar czf` 效果完全一样。你会两种写法都见到，别被搞混了。
>
> 但 `-f` 有一个要求：它后面必须紧跟文件名，中间不能加别的参数。所以 `-f` 通常放在最后：`tar -czf archive.tar.gz dir/`——`-f` 后面的 `archive.tar.gz` 是文件名，`dir/` 是要打包的目录。

把上面的参数组合起来，日常最高频的操作就三组：

**打包 + 压缩**：

```bash
# 把 project/ 目录打包并压缩成 .tar.gz
$ tar -czf project.tar.gz project/
```

**解压**：

```bash
# 把 .tar.gz 解开
$ tar -xzf project.tar.gz
```

**查看内容**（不解压）：

```bash
# 看看压缩包里有什么
$ tar -tzf project.tar.gz
```

`-c`（创建）、`-x`（提取）、`-t`（列表）是互斥的——每次只能选一个。`-z`、`-j`、`-J` 也是互斥的——选哪种压缩算法就写哪个字母。`-v` 和 `-f` 是辅助选项，前者让你看到过程，后者指定文件名。

这就是 `-xzf` 的全部含义：`x` 解包，`z` 用 gzip 解压，`f` 后面跟文件名。不是乱码，是三个独立功能的缩写拼在一起。

### gzip 与 bzip2：压缩机

`gzip` 和 `bzip2` 是两个独立的压缩工具。它们只做一件事：压缩**单个文件**。

```bash
# 用 gzip 压缩一个文件（原文件会被替换）
$ gzip bigfile.bin
$ ls
bigfile.bin.gz    # 原文件消失了，变成了 .gz

# 解压
$ gunzip bigfile.bin.gz
$ ls
bigfile.bin       # 恢复原样
```

`gzip` 压缩之后，原文件会被 `.gz` 文件替换。`gunzip` 解压之后，`.gz` 文件又会消失，恢复原文件。这个行为是可预测的——不会同时保留两个版本。

`bzip2` 的用法几乎一样，只是后缀变成了 `.bz2`：

```bash
# 用 bzip2 压缩
$ bzip2 bigfile.bin
$ ls
bigfile.bin.bz2

# 解压
$ bunzip2 bigfile.bin.bz2
$ ls
bigfile.bin
```

两者的区别在于压缩率和速度的权衡：

| 工具 | 压缩率 | 压缩速度 | 解压速度 | 后缀 |
|:---:|:---:|:---:|:---:|:---:|
| gzip | 中等 | 快 | 快 | `.gz` |
| bzip2 | 较高 | 慢 | 中等 | `.bz2` |
| xz | 最高 | 最慢 | 慢 | `.xz` |

在日常开发中，`.tar.gz` 是最常见的格式——它在压缩率和速度之间取得了最好的平衡。`.tar.bz2` 偶尔出现在对体积敏感的场景（比如发布大版本源码）。`.tar.xz` 压缩率最高但最慢，Linux 内核源码现在默认用 `.xz` 发布——几百 MB 的源码树，多花几分钟压缩换来少下载几十 MB，在分发场景下是划算的。

对于你来说，现阶段记住一点就够：**解压时看后缀选参数**。`.tar.gz` 用 `-z`，`.tar.bz2` 用 `-j`，`.tar.xz` 用 `-J`。其他操作都一样。

### zip 与 unzip：跨平台桥梁

`zip` 和 `unzip` 是 Linux 上处理 `.zip` 格式的工具——这个格式在 Windows 世界里是绝对的统治者。

`zip` 和 `tar` 的关键区别在于：`zip` 自己就同时做了打包和压缩，不需要额外调用 `gzip`。所以它的命令更简单：

```bash
# 把整个 project/ 目录压缩成 .zip
$ zip -r project.zip project/

# 解压
$ unzip project.zip
```

`-r` 表示递归——把目录下的所有东西都打包进去。不加 `-r`，`zip` 只会打包目录本身（一个空壳）。

什么时候用 `zip` 而不是 `tar.gz`？当你需要把文件发给 Windows 用户，或者和 Windows 环境做文件交换的时候。嵌入式开发中 `.tar.gz` 更常见，但 `.zip` 也不时出现。

---

## 实践层

### 4.1 打包与解包——tar 的基本功

先建一个练习用的目录结构：

```bash
$ mkdir -p ~/tar-lab/project/src
$ echo "hello world" > ~/tar-lab/project/src/main.c
$ echo "BUILD_DIR = build" > ~/tar-lab/project/Makefile
$ echo "v1.0" > ~/tar-lab/project/README
$ cd ~/tar-lab
```

**打包——不带压缩**

```bash
# 把 project/ 打包成一个 .tar 文件
$ tar -cf project.tar project/
$ ls -lh project.tar
# 预期输出
-rw-r--r-- 1 charlie charlie 10K  6月 11 10:00 project.tar
```

`-c` 创建归档，`-f project.tar` 指定输出文件名。没有 `-z` 或 `-j`，所以这只是纯粹的打包——体积不会变小。

**查看归档内容**

```bash
$ tar -tf project.tar
# 预期输出
project/
project/src/
project/src/main.c
project/Makefile
project/README
```

`-t` 列出内容，不打扰原文件。在解压之前先 `-t` 看一眼是个好习惯——尤其是当你不确定压缩包里是什么的时候。

**解包**

```bash
# 先删掉原目录，模拟"拿到一个 .tar 文件"的场景
$ rm -rf project/
$ tar -xf project.tar
$ ls project/
# 预期输出
Makefile  README  src
```

`-x` 解包，`-f project.tar` 指定归档文件。文件恢复了。

这里有一个细节值得注意：`tar -xf` 会按照归档时的目录结构原样还原。如果归档时打包的是 `project/`（顶层目录名），解压后就会在当前目录下创建一个 `project/` 目录。如果归档时打包的是一堆散文件（没有顶层目录），解压后这些文件就会散落在当前目录里——和当前目录已有的文件混在一起。

> ⚠️ **踩坑预警：解压前先看一眼**
>
> 不是所有的 `.tar` 包都有一个整洁的顶层目录。有些压缩包直接把文件散装在根目录下——如果你在 `~` 下解压，这些文件会散落在你的家目录里，清理起来很头疼。
>
> 养成习惯：**解压之前，`tar -tf` 先看一眼目录结构**。如果顶层没有一个统一的文件夹，就先建一个目录，把压缩包移进去再解。

### 4.2 打包 + 压缩——合二为一

刚才的 `.tar` 文件 10KB，太小了看不出压缩效果。我们来造一个大一点的文件：

```bash
# 生成一个 1MB 左右的测试文件
$ dd if=/dev/urandom of=~/tar-lab/project/src/bigdata.bin bs=1K count=900
$ cd ~/tar-lab
```

**打包并压缩成 .tar.gz**

```bash
$ tar -czf project.tar.gz project/
$ ls -lh project.tar project.tar.gz
# 预期输出（.tar.gz 会明显小于 .tar）
-rw-r--r-- 1 charlie charlie 900K  6月 11 10:00 project.tar
-rw-r--r-- 1 charlie charlie 900K  6月 11 10:00 project.tar.gz
```

随机数据的压缩效果很差（它本来就是"满的"，没什么冗余可压缩）。换成源码或文本文件，压缩率会非常明显——通常能压缩到原大小的 20%-30%。

加上 `-v` 看看过程：

```bash
$ tar -czvf project.tar.gz project/
# 预期输出
project/
project/src/
project/src/main.c
project/src/bigdata.bin
project/Makefile
project/README
```

`-v` 让 `tar` 输出正在处理的每个文件名。打包文件少的时候无所谓，文件多了可以让你确认它没有漏掉什么。

**解压 .tar.gz**

```bash
$ rm -rf project/
$ tar -xzf project.tar.gz
$ ls project/src/
# 预期输出
bigdata.bin  main.c
```

注意 `tar -xzf` 会自动判断压缩格式——实际上，现代版本的 `tar` 足够聪明，你可以省略 `-z`：

```bash
# 现代 tar 可以自动检测压缩格式
$ tar -xf project.tar.gz
```

但显式写上 `-z` 是更保险的做法——在脚本里尤其如此，明确比隐晦好。

**打包并压缩成 .tar.bz2**

```bash
$ tar -cjf project.tar.bz2 project/
$ ls -lh project.tar.gz project.tar.bz2
# 预期输出
-rw-r--r-- 1 charlie charlie 900K  6月 11 10:00 project.tar.bz2
-rw-r--r-- 1 charlie charlie 900K  6月 11 10:00 project.tar.gz
```

对于随机数据，`bzip2` 和 `gzip` 差不多。但对于源码和文本，`bzip2` 通常能多压 10%-20%，代价是压缩时间更长。

### 4.3 解压到指定目录

默认情况下，`tar -xzf` 会在**当前目录**下解压。如果你想解压到别的地方：

```bash
# 解压到指定目录
$ mkdir -p ~/tar-lab/output
$ tar -xzf project.tar.gz -C ~/tar-lab/output/
$ ls ~/tar-lab/output/
# 预期输出
project
```

`-C`（大写）告诉 `tar`：在动手之前，先切到这个目录。

这里顺带提一个容易踩的坑：如果你用绝对路径打包，`tar` 会自动剥离前导的 `/`，并输出一条警告：

```bash
$ tar -czf etc-backup.tar.gz /etc/hosts
# 预期输出（含警告）
tar: Removing leading '/' from member names
```

这不是报错，而是 `tar` 的安全机制——它怕你解压时意外覆盖系统文件。所以压缩包里存的是 `etc/hosts`（没有前导 `/`），解压时会在当前目录下创建 `etc/hosts`。如果你确实想保留绝对路径，加 `-P`（`--absolute-names`）参数——但一般不需要。

另一个有用的参数是 `--strip-components=N`——解压时跳过前 N 层目录。比如压缩包里是 `project-v1/src/main.c`，但你只想解出 `src/main.c`：

```bash
$ tar -xzf project-v1.tar.gz --strip-components=1
# 解压出来是 src/main.c，去掉了顶层的 project-v1/
```

这在嵌入式开发中很常用：下载的源码压缩包通常带一个版本号目录（如 `linux-6.1/`），而你只需要内容不要那层目录。

这个选项在交叉编译工具链解压时也经常出现。比如你下载了一个工具链压缩包，想把它解压到 `/opt` 目录下：

```bash
$ sudo tar -xzf gcc-arm-10.3-x86_64-arm-none-linux-gnueabihf.tar.xz -C /opt/
```

### 4.4 zip 与 unzip

当你需要和 Windows 环境交换文件时，`.zip` 是最安全的选择：

```bash
# 压缩成 .zip
$ cd ~/tar-lab
$ zip -r project.zip project/
# 预期输出
  adding: project/ (stored 0%)
  adding: project/src/ (stored 0%)
  adding: project/src/main.c (stored 0%)
  adding: project/Makefile (stored 0%)
  adding: project/README (stored 0%)

# 解压 .zip
$ rm -rf project/
$ unzip project.zip
# 预期输出
Archive:  project.zip
   creating: project/
   creating: project/src/
  inflating: project/src/main.c
  inflating: project/Makefile
  inflating: project/README
```

`zip -r` 递归打包目录，`unzip` 解压。操作比 `tar` 简单，但功能也没那么细——日常够用。

### 4.5 查看压缩信息

有时候你想知道一个压缩包里有什么，又不想解压：

```bash
# .tar.gz 查看
$ tar -tzf project.tar.gz

# .zip 查看
$ unzip -l project.zip
# 预期输出
Archive:  project.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  06-11-2026 10:00   project/
        0  06-11-2026 10:00   project/src/
       12  06-11-2026 10:00   project/src/main.c
       19  06-11-2026 10:00   project/Makefile
        5  06-11-2026 10:00   project/README
---------                     -------
       36                     5 files
```

`unzip -l` 会列出每个文件的大小和修改时间——在决定要不要解压之前，先看看里面有什么。

---

## 练习题

走到这里，归档和压缩的机制应该已经清楚了。下面几道题递进难度，建议先自己试，卡住了再翻提示。

**练习 11.1** ⭐（理解）

`tar -czf archive.tar.gz dir/` 这条命令中，如果把 `-f` 放到最前面写成 `tar -fcz archive.tar.gz dir/`，会发生什么？为什么？

> **提示**：回忆 `-f` 参数的要求——它后面必须紧跟文件名。

**练习 11.2** ⭐⭐（应用）

你下载了一个文件 `u-boot-2023.10.tar.bz2`，写出完整的命令完成以下操作：
1. 不解压，查看压缩包里的顶层目录结构（只看第一级）
2. 把它解压到 `~/src/` 目录下

> **提示**：`.tar.bz2` 用 `-j` 参数。查看顶层目录可以用 `tar -tjf ... | head -n 20`。

**练习 11.3** ⭐⭐⭐（思考）

`gzip` 只能压缩单个文件，`tar` 只负责打包不压缩。那为什么 Linux 不设计一个同时做这两件事的工具？这种"一个工具只做一件事"的设计哲学，优势和代价分别是什么？

> **提示**：想想如果你发明了一种新的压缩算法，在两种架构下分别需要做什么。

---

## 本章回响

这一章的核心认知只有一件事：**归档和压缩是两道独立的工序，`tar` 和 `gzip` 各负责一道**。

理解了这一点，`.tar.gz` 这个后缀就不再神秘——它只是一个 `.tar` 文件被 `gzip` 又压缩了一遍。`-xzf` 也不再是乱码：`x` 解包，`z` 解压，`f` 后面跟文件名。三个字母各管各的，拼在一起就是一整条流水线。

还记得开头那个问题吗——为什么 Linux 不像 Windows 那样给一个"右键→压缩"就完事？因为拆开之后，你可以自由组合：今天用 `gzip`，明天换 `xz`，打包工具不用改。你可以给 `tar` 配任何压缩算法，甚至不压缩——只打包传给磁带备份。这种灵活性在嵌入式开发中尤其重要：不同的板子、不同的带宽限制、不同的存储约束，你可能需要不同的压缩策略。一个全能工具做不到这件事，两个各管一摊的工具可以。

下一章我们要进入一个新的 Part——文本与编辑。你要学的第一个工具是 Vim：在终端里改文件。压缩包解开了，里面的配置文件要改、源码要看，这些操作都离不开一个趁手的编辑器。

---

[← 上一章](ch10-search.md)
[下一章 →](../03-text/ch12-vim.md)
