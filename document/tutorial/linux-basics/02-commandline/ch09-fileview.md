# 第 9 章  文件查看

> **Part 2 · 命令行生存**

---

## 引子

文件找到了，也搬到了该在的地方。

但里面写了什么？

在 Windows 里你双击打开。在终端里，你需要另一套工具。而且这套工具比你想象的要精细——有的命令适合看短文件，有的命令适合翻长日志，有的命令只看开头，有的只看结尾。

选错工具不是大问题，但会浪费你的时间。选对工具，一行命令就能省下你十分钟上下翻页的功夫。

但这里还藏着一个容易忽略的顺序问题：拿到一个文件，第一步该做什么？直接打开看内容？还是先搞清楚它到底是什么类型的文件？

先别急着回答，看完这章的工具再说。

---

## 背景与动机

在嵌入式开发中，「看文件」是一件高频到几乎每分钟都在发生的事。

编译报错了，你需要看编译日志的最后几十行。设备树（Device Tree）改了，你需要确认改动是否生效。交叉编译工具链下载好了，你需要确认那个 `gcc` 可执行文件的架构确实是目标板子的架构。开发板通过串口输出日志，你想实时盯着看——不等它写完，一边跑一边看。

这些场景有一个共同特征：**你不需要编辑文件，只需要看它**。Windows 里双击会打开编辑器，但编辑器太重了——加载慢、占内存，而且对于二进制文件直接给你一屏乱码。Linux 的做法更直接：用专门的查看命令，只读不写，看完就走。

但还有一个问题比「怎么看」更基础：**你拿到的东西到底是不是你以为的那个东西**。Linux 不依赖文件扩展名——一个叫 `config` 的文件可能是纯文本，可能是个二进制 blob，也可能是个软链接指向另一个文件。一个叫 `image.bin` 的文件可能确实是个二进制镜像，但也可能只是一段被错误命名的文本日志。光看文件名猜，迟早踩坑。

所以 Linux 提供了一整套「看」文件的命令，各有各的专长。它们的分工不是随意的——而是针对不同大小、不同类型、不同查看需求做了精确的优化。

---

## 概念层

你可以把这套命令想象成对待书架上的一本书——面对不同的书，你自然有不同的「阅读策略」：

- `file` 是看书脊和封面，先判断这是什么类型的书
- `cat` 是把书摊平一口气翻完，适合薄册子
- `less` 是坐下来慢慢翻，想看哪页翻哪页，适合大部头
- `head` / `tail` 是只翻封面和封底——看开头几行或最后几行
- `wc` 是看版权页的「共 XX 页」，只关心数量不翻内容
- `diff` 是把两本书并排，逐行找不同

但这个比喻有一个地方是错的。这些命令不只是「阅读策略」不同——它们在**加载策略**上有本质区别。`cat` 把整个文件读进内存一股脑输出到终端；`less` 只加载当前屏幕的内容，按需读取后续数据；`head` 读到指定行数就停；`tail` 则从文件末尾开始倒着定位。这不是「怎么看」的差异，是「读多少、怎么读」的架构差异。对几百 MB 的日志文件来说，`cat` 会让终端刷屏到你什么都看不到，而 `less` 打开只需要零点几秒。

### file —— 先确认你拿的是什么

`file` 命令通过读取文件头部的特征字节（称为「魔数」，magic number）来判断文件类型。它不依赖文件名，只看内容。

```bash
# 普通文本文件
$ file ~/.bashrc
# 预期输出
/home/charlie/.bashrc: ASCII text

# 可执行文件（ELF 格式）
$ file /bin/ls
# 预期输出
/bin/ls: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked ...

# 软链接
$ file /usr/bin/python3
# 预期输出（具体版本号因系统而异）
/usr/bin/python3: symbolic link to python3.12

# 压缩文件
$ file ~/Downloads/archive.tar.gz
# 预期输出
/home/charlie/Downloads/archive.tar.gz: gzip compressed data, from Unix, original size modulo 2^32 ...
```

`file` 的输出信息量很大：文本还是二进制、什么编码、链接指向哪里、可执行文件的架构——全都在一行里。在嵌入式开发中，你拿到一个不确定类型的二进制文件，`file` 是第一手情报。比如你编译出一个 ARM 可执行文件，`file` 能直接告诉你它的目标架构是 `ARM aarch64` 还是 `x86-64`——搞错了架构，程序根本跑不起来。

### cat —— 一口气看完

`cat`（concatenate，拼接）把文件的完整内容直接输出到终端。

```bash
# 查看一个短文件
$ cat /etc/hostname
# 预期输出
ubuntu
```

只有一行的文件，`cat` 是最快的方式。

但面对长文件，`cat` 有一个致命的问题：**内容全部一次性刷过屏幕，你只能看到最后一屏**。前面几十页全滚走了，来不及看。

几个有用的选项：

```bash
# 显示行号
$ cat -n /etc/hostname
# 预期输出
     1  ubuntu

# 显示不可见字符（调试格式问题时能救命）
$ cat -A mystery.txt
# 预期输出（$ 表示行尾，^I 表示 Tab）
Hello^Iworld$
$
```

`cat -n` 给每行加行号——看代码或配置时很实用。`cat -A` 把 Tab、行尾符等不可见字符全暴露出来。当你遇到「看起来一模一样但就是报错」的格式问题时，这个选项能帮你揪出藏在暗处的 Tab 或多余的空行。

### less —— 长文件的正确打开方式

`cat` 的刷屏问题，`less` 来解决。

`less` 是一个**分页器（pager）**——它一次只显示一屏内容，你可以在文件里前后翻动、搜索关键字、跳到任意位置。

```bash
$ less /var/log/syslog
```

进入 `less` 之后，终端被它接管。以下是最关键的操作：

| 按键 | 作用 |
|------|------|
| `空格` 或 `Page Down` | 向下翻一页 |
| `b` 或 `Page Up` | 向上翻一页 |
| `j` 或 `↓` | 向下一行 |
| `k` 或 `↑` | 向上一行 |
| `g` | 跳到文件开头 |
| `G` | 跳到文件末尾 |
| `/关键字` | 向下搜索 |
| `n` | 下一个搜索结果 |
| `N` | 上一个搜索结果 |
| `q` | 退出 |

`less` 这个名字来自一句程序员冷幽默：`less is more`——它是早期分页器 `more` 的升级版。`more` 只能往下翻，`less` 前后都能翻，功能更强，所以说「less 比 more 还多」。

但真正让 `less` 优于 `cat` 的不是功能多，而是**架构不同**：`less` 不把整个文件加载进内存，它按需读取——只加载当前屏幕需要显示的那几 KB。所以即使面对几百 MB 的日志文件，`less` 也能在零点几秒内打开，而 `cat` 会试图把全部内容塞进终端的输出缓冲区，刷屏好几分钟。

### head 与 tail —— 只看头尾

`head` 默认显示前 10 行，`tail` 默认显示最后 10 行。

```bash
# 看文件开头
$ head /etc/passwd
# 预期输出（前 10 行）
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
...

# 指定行数
$ head -n 5 /etc/passwd
# 预期输出（只显示前 5 行）

# 看文件末尾
$ tail -n 5 /etc/passwd
# 预期输出（最后 5 行，因系统而异）
```

`head` 简单直接。`tail` 则有一个在嵌入式开发中几乎每天都要用的模式——**实时跟踪**：

```bash
# 实时监控日志——新内容自动出现
$ tail -f /var/log/syslog
```

`-f`（follow）让 `tail` 不退出，而是持续监听文件：有新内容写入，立刻显示出来。调试程序、看串口日志、监控编译输出——这个模式几乎是必备技能。按 `Ctrl+C` 停止。

> ⚠️ **tail -f 和 tail -F 的区别**
> `tail -f` 跟踪的是文件的**文件描述符**。如果日志系统把旧日志重命名（比如 `syslog` 变成 `syslog.1`）然后创建新文件，`tail -f` 还在跟着旧文件走——你看到的新内容其实是旧文件的尾巴。
>
> `tail -F`（等价于 `--follow=name --retry`）跟踪的是**文件名**。当文件被替换或重建时，它会自动重新打开新文件。在监控会轮转（rotation）的日志时，`tail -F` 比 `tail -f` 更可靠。

### wc —— 数数

`wc`（word count）统计文件的行数、单词数和字节数。

```bash
$ wc /etc/passwd
# 预期输出（具体数字因系统而异）
  42  78 2345 /etc/passwd
```

三个数字依次是：**行数、单词数、字节数**。

常用选项：

```bash
# 只看行数——最高频的用法
$ wc -l /etc/passwd
# 预期输出
42 /etc/passwd

# 只看单词数
$ wc -w /etc/passwd

# 只看字节数
$ wc -c /etc/passwd
```

「这个日志有多少行」「源码目录下有几个 .c 文件」这类问题，`wc -l` 一行搞定。

### diff —— 找不同

`diff` 逐行比较两个文件，输出差异。

```bash
# 准备两个测试文件
$ echo -e "apple\nbanana\ncherry" > fruits_v1.txt
$ echo -e "apple\nblueberry\ncherry\ndate" > fruits_v2.txt

# 比较
$ diff fruits_v1.txt fruits_v2.txt
# 预期输出
2c2
< banana
---
> blueberry
3a4
> date
```

`diff` 的原始输出格式需要适应一下：

- `2c2`：第一个文件第 2 行**改变**（c = change）为了第二个文件第 2 行
- `< banana`：左边文件（`fruits_v1.txt`）的内容
- `> blueberry`：右边文件（`fruits_v2.txt`）的内容
- `3a4`：第一个文件第 3 行之后**添加**（a = add）了第二个文件第 4 行

更易读的格式是 **unified diff**（`-u` 选项）：

```bash
$ diff -u fruits_v1.txt fruits_v2.txt
# 预期输出
--- fruits_v1.txt
+++ fruits_v2.txt
@@ -1,3 +1,4 @@
 apple
-banana
+blueberry
 cherry
+date
```

`-u` 格式是 Git 和各种版本控制工具使用的标准差异格式。`-` 开头的行是旧内容，`+` 开头的行是新内容。你在第 34 章学 Git 时会频繁看到这种格式。

只想知道两个文件「一不一样」，不关心细节：

```bash
$ diff -q fruits_v1.txt fruits_v2.txt
# 预期输出
Files fruits_v1.txt and fruits_v2.txt differ
```

---

## 实践层

### 4.1 建一个练习场

先创建安全区域，随便折腾不用担心搞坏系统：

```bash
$ cd ~
$ mkdir -p ~/lab/fileview
$ cd ~/lab/fileview
```

准备几个不同类型的测试文件：

```bash
# 短文本文件
$ echo "Hello, Linux file viewing!" > short.txt

# 较长的文件（复制系统文件）
$ cp /etc/passwd passwd_copy.txt

# 一个二进制文件
$ cp /bin/ls ls_copy
```

### 4.2 第一步——判断类型

还记得引子里那个问题吗——拿到一个文件，第一步该做什么？

先用 `file` 看看手里拿的是什么。

```bash
$ file short.txt
# 预期输出
short.txt: ASCII text

$ file passwd_copy.txt
# 预期输出
passwd_copy.txt: ASCII text

$ file ls_copy
# 预期输出
ls_copy: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked ...
```

三个文件，`file` 一眼告诉你：前两个是文本，可以放心用 `cat` 或 `less` 看；第三个是 ELF 可执行文件——直接 `cat` 会刷出一堆乱码。

不信？试试看（按 `Ctrl+C` 终止乱码输出）：

```bash
$ cat ls_copy
# 预期输出（一堆乱码，终端显示可能异常）
```

这就是为什么 `file` 应该是你面对陌生文件时的第一步。确认了是文本，再选择查看方式；确认是二进制，就别用 `cat` 折腾终端了。

### 4.3 短文件和长文件——两种打开方式

短文件直接 `cat`：

```bash
$ cat short.txt
# 预期输出
Hello, Linux file viewing!
```

一目了然。加上行号看 `passwd`：

```bash
$ cat -n passwd_copy.txt | head -n 5
# 预期输出
     1  root:x:0:0:root:/root:/bin/bash
     2  daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
     3  bin:x:2:2:bin:/bin:/usr/sbin/nologin
     4  sys:x:3:3:sys:/dev:/usr/sbin/nologin
     5  sync:x:4:65534:sync:/bin:/bin/sync
```

这里用到了 `|`（管道），把 `cat -n` 的输出传给 `head` 只看前 5 行。管道的详细用法在第 14 章讲，现在只需要知道 `|` 的意思是「把前面的输出当作后面的输入」。

对于长文件，`less` 是更好的选择：

```bash
$ less passwd_copy.txt
```

进去之后按顺序试一遍关键操作：
1. `空格` → 翻到下一页
2. `b` → 翻回上一页
3. `/root` 回车 → 搜索 `root` 关键字
4. `n` → 跳到下一个匹配
5. `G` → 跳到文件末尾
6. `g` → 跳回文件开头
7. `q` → 退出

### 4.4 只看头尾——head 与 tail

```bash
# 看开头 3 行
$ head -n 3 passwd_copy.txt
# 预期输出
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin

# 看最后 3 行
$ tail -n 3 passwd_copy.txt
# 预期输出（因系统而异）
```

`tail -f` 需要两个终端配合。在当前终端里先创建一个日志文件：

```bash
$ touch test.log
```

然后**新开一个终端标签页**（终端菜单里选「新建标签页」，或按 `Ctrl+Shift+T`），在第二个终端里运行：

```bash
$ tail -f ~/lab/fileview/test.log
```

回到第一个终端，往文件里追加内容：

```bash
$ echo "First event at $(date)" >> test.log
$ echo "Second event at $(date)" >> test.log
```

切到第二个终端——新内容自动出现了。这就是 `tail -f` 的实时跟踪效果。

实验完了，在第二个终端里按 `Ctrl+C` 停止 `tail -f`。

### 4.5 统计与对比——wc 和 diff

```bash
# 数一下 passwd 有多少行
$ wc -l passwd_copy.txt
# 预期输出（因系统而异）
42 passwd_copy.txt

# 创建一个修改版
$ cp passwd_copy.txt passwd_modified.txt
$ echo "testuser:x:1001:1001:Test User:/home/testuser:/bin/bash" >> passwd_modified.txt

# 对比差异
$ diff passwd_copy.txt passwd_modified.txt
# 预期输出
42a43
> testuser:x:1001:1001:Test User:/home/testuser:/bin/bash
```

`42a43` 意味着：左边文件第 42 行之后，右边文件添加了第 43 行。

用 `-u` 格式看得更清楚：

```bash
$ diff -u passwd_copy.txt passwd_modified.txt
# 预期输出
--- passwd_copy.txt
+++ passwd_modified.txt
@@ -40,3 +40,4 @@
 (原文件最后几行的内容)
+testuser:x:1001:1001:Test User:/home/testuser:/bin/bash
```

`+` 开头的那行就是新增内容。

### 4.6 清理

实验做完了，收拾干净：

```bash
$ cd ~
$ rm -rf ~/lab
```

> ⚠️ **提醒**
> `rm -rf` 不进回收站。确认路径正确后再执行。这里删的是我们自己建的 `~/lab`，没问题。

---

## 练习题

走到这里，七个命令都应该上手试过了。下面几道题难度递进，建议先独立做，卡住了再翻提示。第三题如果做出来了，说明你对 Linux 文件系统的理解又深了一层。

**练习 9.1** ⭐（理解）

`cat` 和 `less` 都能查看文件内容。如果对一个 10000 行的日志文件分别执行 `cat log.txt` 和 `less log.txt`，你在终端里看到的信息有什么区别？为什么？

**练习 9.2** ⭐⭐（应用）

在 `/tmp` 下创建一个文件 `watchme.txt`，在一个终端里运行 `tail -f /tmp/watchme.txt`，然后在另一个终端里用 `echo` 往这个文件追加几行内容，观察 `tail -f` 的输出变化。

接下来做这样一个实验：把 `watchme.txt` 改名为 `watchme_old.txt`，再创建一个新的 `watchme.txt` 并写入内容——`tail -f` 还能跟踪到新内容吗？换成 `tail -F` 再试一次，观察区别。

> **提示**：`tail -f` 跟踪文件描述符，`tail -F` 跟踪文件名并自动重试。

**练习 9.3** ⭐⭐⭐（思考）

`file` 命令是如何判断文件类型的？它依据的是文件名、文件内容，还是其他什么？试着手动创建一个文件命名为 `image.png`，但内容写入一段纯文本。用 `file` 检查它——结果是什么？这说明 Linux 的文件类型判断和 Windows 有什么本质区别？

> **提示**：`file` 读取的是文件头部的特征字节序列（magic number），而非文件名。可以查看 `man file` 了解原理。

---

## 本章回响

本章表面上是七个文件查看命令的用法，实际上在建立一种更底层的工作习惯：**面对陌生文件，先判断类型，再选择工具**。`file` 命令是你面对任何未知文件时的第一道关卡——确认了类型，才知道该用什么方式打开它。

回到那个「看书」的比喻：现在你应该能看出来，选哪个命令不是看心情，而是取决于文件的大小和你想看多少。短文件 `cat` 一眼看完，长日志用 `less` 翻，编译输出只看最后几行用 `tail`，对比两份配置用 `diff`——每种策略背后是对应的加载策略，选错不是致命的，但效率天差地别。这就是为什么 Linux 不给你一个「通用的文件查看器」——没有一个工具能同时在所有场景下做到最优。Unix 的哲学是每个工具只做一件事，做到极致，然后通过组合来解决复杂问题。

还记得引子里那个问题吗——拿到一个文件，第一步该做什么？答案是 `file`。先搞清楚它是什么，再决定怎么看它。这个顺序在嵌入式开发中尤为重要——你拿到的 `.bin` 文件可能是镜像，可能是压缩包，甚至可能只是一段被错误命名的文本。`file` 一下就知道了。

文件能看了，但还有一个问题一直没碰：文件太多，找不到怎么办？下一章我们就来解决它——`find` 在文件系统里按名字和属性搜索，`grep` 在文件内容里搜索关键字。它们是你在终端里最强大的两把搜索武器。

---

[← 上一章](ch08-fileops.md)
[下一章 →](ch10-search.md)
