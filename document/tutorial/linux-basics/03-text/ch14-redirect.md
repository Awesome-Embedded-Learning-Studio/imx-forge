# 第 14 章  重定向与管道

> **Part: Part 3 · 文本与编辑**

---

## 引子

上一章末尾留了一个问题：怎么把 `sed`、`awk`、`sort` 这些工具组合起来？

答案是一个字符：`|`。

管道符。左边的命令吐出结果，右边的命令直接吃进去，不需要临时文件，不需要复制粘贴。一条管道串起来，几十个工具像流水线一样协作。

而管道只是故事的一半。`>` 把输出写进文件，`<` 从文件读入输入，`2>` 把错误信息单独保存——重定向和管道一起，构成了 Linux 命令行最核心的「数据流」机制。

理解了数据流，你就理解了为什么 Linux 的工具设计哲学是「做好一件事」。

---

## 背景与动机

你已经能用 `ls` 列文件、用 `grep` 搜内容、用 `find` 找文件了。但每次命令的输出都只能看一眼就滚过去了——你想保存怎么办？

最直觉的办法：用鼠标选中，复制粘贴到记事本里。

但在终端里没有鼠标可用（或者你 SSH 连着远程服务器），这个办法行不通。更关键的是，你经常需要把一个命令的输出**直接喂给**另一个命令当输入。比如：

- 找到所有 `.log` 文件，然后在里面搜 `error`
- 把编译日志里的警告信息单独存到一个文件里
- 统计当前目录下有多少个 `.c` 文件

这些操作都涉及同一件事：**让数据在命令之间流动**。这就是重定向和管道要解决的问题。

> **嵌入式开发中的真实场景**：交叉编译一个内核模块，编译输出混着警告和错误。你想只看错误，不想手动翻几百行日志。一条 `make 2>&1 | grep -i error` 就能把错误行筛出来——但只有理解了 `2>&1` 在做什么，你才能写出这条命令。

---

## 概念层

### 三个数据通道

每个 Linux 命令在运行时，都会自动打开三个通道：

| 通道 | 编号 | 默认连接 | 作用 |
|:---:|:---:|:---:|:---|
| 标准输入（stdin） | 0 | 键盘 | 命令读取输入的地方 |
| 标准输出（stdout） | 1 | 终端屏幕 | 命令输出正常结果的地方 |
| 标准错误（stderr） | 2 | 终端屏幕 | 命令输出错误信息的地方 |

默认情况下，stdout 和 stderr 都流向终端屏幕——所以你在终端里看到的内容，其实混合了两种性质完全不同的东西：正常的输出结果和报错信息。它们混在一起，肉眼看不出区别，但在数据流层面，它们走的是两条管道。

> **类比 1/3 —— 工厂的两条流水线**
>
> 你可以把一个 Linux 命令想象成一座小工厂。原料从正门进来（stdin），成品从南门出去（stdout），废品和报警信息从北门扔出来（stderr）。
>
> 平时南门和北门都通向同一个地方（终端屏幕），所以你看到的输出是成品和废品混在一起的。重定向做的事，就是给这两条流水线接上不同的管子，把它们引向不同的目的地。

### 重定向：给数据流换管子

**输出重定向 `>` 和 `>>`**——改变 stdout 的去向：

```bash
# > 覆盖写入（文件原有内容被清空）
$ echo "Hello" > output.txt
$ cat output.txt
# 预期输出
Hello

# >> 追加写入（在文件末尾添加）
$ echo "World" >> output.txt
$ cat output.txt
# 预期输出
Hello
World
```

这里有一个细节值得注意：`>` 的覆盖是**无条件的**。哪怕 `>` 右边的文件不存在，它也会被创建；哪怕里面有重要数据，它也会被清空。

> ⚠️ **踩坑预警：`>` 的毁灭性**
>
> `$ cat important.conf > wrong_file.txt`——如果你搞混了方向，或者文件名写错了，`wrong_file.txt` 会被立即清空并写入 `cat` 的输出。如果 `wrong_file.txt` 里原本有重要内容，它们已经回不来了。
>
> 一个保护措施：在 Bash 中执行 `set -o noclobber`，之后 `>` 就不会覆盖已有文件。需要强制覆盖时用 `>|`。但这个设置只对当前 Shell 会话有效。

**错误重定向 `2>`**——只捕获 stderr：

```bash
# ls 一个不存在的文件，错误信息正常输出到屏幕
$ ls /nonexistent
# 预期输出（到 stderr）
ls: cannot access '/nonexistent': No such file or directory

# 把错误信息写入文件，屏幕上不再显示
$ ls /nonexistent 2> errors.log
$ cat errors.log
# 预期输出
ls: cannot access '/nonexistent': No such file or directory
```

注意 `2>` 中间没有空格——`2` 是 stderr 的编号，`>` 是重定向符号，它们连在一起表示「把 stderr 重定向」。

**合并重定向 `2>&1`**——把 stderr 合并到 stdout：

```bash
# 把正常输出和错误信息都写入同一个文件
$ ls /home /nonexistent > all.log 2>&1
$ cat all.log
# 预期输出（stdout 和 stderr 混在一起）
/home:
charlie

ls: cannot access '/nonexistent': No such file or directory
```

`2>&1` 的含义是「把编号 2 的通道重定向到编号 1 当前指向的地方」。这个写法初看很别扭，但它解决了一个实际问题：当你想把所有输出（无论正常还是报错）都存到一个文件时，只写 `> file` 是不够的——它只捕获 stdout，stderr 仍然会漏到屏幕上。

还有一个更简洁的写法（Bash 4+ 支持）：

```bash
$ ls /home /nonexistent &> all.log
# &> 等价于 > file 2>&1
```

**输入重定向 `<`**——从文件读取 stdin：

```bash
# sort 默认从键盘读输入，用 < 可以让它从文件读
$ sort < output.txt
# 预期输出（文件内容按行排序后输出）
Hello
World
```

输入重定向在处理批量数据时很有用——你可以把一个命令设计成「从 stdin 读数据」，然后用 `<` 喂给它不同的文件，而不需要在命令行上指定文件名。

> **类比 2/3 —— 揭示距离**
>
> 回到那座工厂。重定向确实像「换管子」——但有一个地方这个比喻会失效：工厂的管子可以同时接很多目的地，而 Linux 的重定向是**有顺序的**。
>
> `> file 2>&1` 和 `2>&1 > file` 的效果完全不同。前者是「先把 stdout 指向文件，再把 stderr 指向 stdout 当前指向的地方（即文件）」——两条流都进了文件。后者是「先把 stderr 指向 stdout 当前指向的地方（终端），再把 stdout 指向文件」——stderr 留在了终端，stdout 进了文件。
>
> Bash 从左到右依次处理重定向符号。顺序决定了一切。这不是管子怎么接的问题，而是**先接哪根管子**的问题。

### 管道：命令之间的传送带

重定向解决的是「命令和文件之间」的数据流。管道解决的是「命令和命令之间」的数据流。

```bash
$ command1 | command2
# command1 的 stdout 直接变成 command2 的 stdin
```

管道符 `|` 做的事很简单：把左边命令的 stdout 接到右边命令的 stdin 上。数据不经过文件，不经过屏幕，直接在内存中流动。

一个简单的例子：

```bash
# 列出当前目录的文件，按名称排序
$ ls | sort
# 预期输出（文件名按字母序排列）
desktop
documents
downloads
music
pictures
```

`ls` 输出的文件列表没有经过任何文件，直接被 `sort` 读走了。

管道可以串联：

```bash
# 找出 /etc 下所有 .conf 文件，按名字排序，只看前 10 个
$ find /etc -name "*.conf" | sort | head -10
# 预期输出（前 10 个按字母序排列的 .conf 文件路径）
/etc/adduser.conf
/etc/appstream.conf
/etc/ca-certificates.conf
/etc/debconf.conf
/etc/deluser.conf
/etc/fuse.conf
/etc/gai.conf
/etc/hdparm.conf
/etc/kernel-img.conf
/etc/ld.so.conf
```

> **类比 3/3 —— 回到那座工厂**
>
> 现在把视角拉远。你面前不是一座工厂，而是一整条产业链。`find` 是矿场，负责挖出原材料（文件路径）；`sort` 是分拣车间，把原材料按顺序排列；`head` 是截取车间，只取前 10 件成品。
>
> 三座工厂之间没有仓库、没有卡车、没有中间文件——全靠管道直接对接。这就是 Linux 哲学的核心：「每个工具做好一件事，然后通过管道组合出无限可能。」
>
> 而重定向是产业链的两端——矿场的入口（`<`）从文件读原料，截取车间的出口（`>`）把成品写回文件。管道管中间，重定向管两头。

---

## 实践层

### 4.1 重定向基础操作

先建一个工作目录：

```bash
$ mkdir -p ~/redirect-lab
$ cd ~/redirect-lab
```

**场景一：保存命令输出到文件**

```bash
$ echo "First line" > demo.txt
$ echo "Second line" >> demo.txt
$ cat demo.txt
# 预期输出
First line
Second line
```

`>` 创建（或覆盖）文件，`>>` 在文件末尾追加。记住这个区别——用错的话，要么丢了数据，要么多了一堆重复内容。

**场景二：分离正常输出和错误信息**

```bash
# 同时访问一个存在的和一个不存在的目录
$ ls /home /nonexistent
# 预期输出（混在屏幕上）
/home:
charlie

ls: cannot access '/nonexistent': No such file or directory
```

用重定向把它们分开：

```bash
$ ls /home /nonexistent > result.txt 2> error.txt
$ cat result.txt
# 预期输出
/home:
charlie

$ cat error.txt
# 预期输出
ls: cannot access '/nonexistent': No such file or directory
```

正常输出进了 `result.txt`，错误信息进了 `error.txt`。互不干扰。

**场景三：丢弃不需要的输出**

```bash
# /dev/null 是一个特殊的设备文件——写入它的数据全部消失
$ ls /nonexistent 2> /dev/null
# 屏幕上什么都没有——错误信息被"黑洞"吞掉了

$ echo "this goes nowhere" > /dev/null
# 同样什么都没有——正常输出也被吞掉了
```

`/dev/null` 在脚本中极为常用：当你只关心命令是否成功（通过返回值 `$?`），而不关心输出内容时，把输出丢进 `/dev/null` 就行。

### 4.2 管道实战

管道的威力在组合——单个命令平平无奇，串起来就能解决复杂问题。

**实战一：统计文件数量**

```bash
$ ls /etc | wc -l
# 预期输出（数字，表示 /etc 下的条目数）
253
```

`ls` 列出文件，`wc -l` 统计行数。两个命令各自只做一件事，管道把它们连成了一把尺。

**实战二：查找并排序**

```bash
# 找出 /etc 下所有包含 "network" 的配置文件
$ grep -rl "network" /etc 2>/dev/null | sort | head -5
# 预期输出（前 5 个匹配文件，按路径排序）
# 实际输出取决于你的系统配置
/etc/dbus-1/system.d/org.freedesktop.NetworkManager.conf
/etc/dhcp/dhclient.conf
/etc/hosts
/etc/netplan/01-network-manager-all.yaml
/etc/nsswitch.conf
```

这里 `2>/dev/null` 是因为 `grep -r` 扫描 `/etc` 时会遇到「权限不足」的目录，stderr 会输出一堆 `Permission denied`——丢掉它们，只看有用结果。

**实战三：提取日志中的关键信息**

```bash
# 模拟一个日志文件
$ cat > syslog.sample << 'EOF'
Jan 10 08:01:23 server sshd[1234]: Accepted password for user1
Jan 10 08:05:11 server kernel: [INFO] USB device connected
Jan 10 08:12:45 server sshd[5678]: Failed password for root
Jan 10 08:15:00 server kernel: [WARN] Disk space low on /dev/sda1
Jan 10 08:20:33 server sshd[1234]: Failed password for admin
EOF

# 提取所有 "Failed" 行，只显示时间戳和用户名
$ grep "Failed" syslog.sample | awk '{print $1, $2, $3, $NF}'
# 预期输出
Jan 10 08:12:45 root
Jan 10 08:20:33 admin
```

虽然 `awk` 还没正式讲（那是下一章的内容），但这条管道的意图应该很清晰：`grep` 过滤出失败的登录记录，`awk` 提取其中的时间和用户名字段。这就是管道的威力——你不需要一个「超级日志分析工具」，只需要把两个小工具串起来。

### 4.3 tee：分流的十字路口

有时候你想把输出**同时**存到文件里**并且**显示在屏幕上。单用 `>` 不行——它会吞掉屏幕输出。

这时候用 `tee`：

```bash
$ ls | tee filelist.txt | wc -l
# 屏幕上显示文件数量
# 同时 filelist.txt 里有完整的文件列表
```

`tee` 的名字来自水管的 T 形接头——水流进来，分成两路，一路继续往前，一路流向旁边。

一个更实用的例子——编译内核模块时，既想看编译过程，又想把日志存下来：

```bash
$ make 2>&1 | tee build.log
# 编译输出同时在屏幕上显示，也被写入 build.log
# 如果有报错，你可以事后 grep build.log 来排查
```

### 4.4 xargs：把标准输入变成命令参数

管道传递的是「数据流」，但有些命令不接受数据流——它们要的是命令行参数。

比如 `rm`。`rm` 不从 stdin 读文件名——你得把文件名写在命令行上。

```bash
# 这行不通！find 的输出不会变成 rm 的参数
$ find . -name "*.tmp" | rm
# rm 报错：rm: missing operand
```

`xargs` 就是桥梁——它把 stdin 的每一行变成下一个命令的参数：

```bash
$ find . -name "*.tmp" | xargs rm
# find 找到的每个 .tmp 文件名，被 xargs 传给 rm 当参数
```

但这里有一个坑。

> ⚠️ **踩坑预警：文件名里的空格**
>
> 如果文件名里有空格（比如 `my file.tmp`），`xargs` 默认会把它拆成两个参数 `my` 和 `file.tmp`，然后 `rm` 分别尝试删除这两个不存在的文件。
>
> 解决方案：让 `find` 用 `\0`（null 字符）分隔输出，让 `xargs` 用 `\0` 分隔读取：
>
> ```bash
> $ find . -name "*.tmp" -print0 | xargs -0 rm
> ```
>
> `-print0` 让 `find` 用 `\0` 而非换行分隔结果，`-0` 让 `xargs` 以 `\0` 为分隔符解析输入。这一对选项就是为了对付文件名中的空格和特殊字符而设计的。
>
> 另一个替代方案是 `find -exec`，它不需要 `xargs`：
>
> ```bash
> $ find . -name "*.tmp" -exec rm {} \;
> # {} 会被替换为 find 找到的每个文件名
> # \; 表示 -exec 命令结束
> ```
>
> 两种方案各有取舍：`xargs` 更快（它会把多个文件名合并成一次 `rm` 调用），`find -exec {} \;` 更安全（每个文件名单独处理，天然支持空格），但稍慢。
>
> 还有第三种写法——`find -exec {} +`——它兼得两者优点：像 `xargs` 一样批量处理（把多个文件名合并成一次命令调用），同时像 `find -exec {} \;` 一样安全（不需要字符串解析，不会在空格处断裂）：
>
> ```bash
> $ find . -name "*.tmp" -exec rm {} +
> # + 号代替 \;，find 会把多个文件名合并成一个 rm 调用
> ```
>
> 简单选择：如果文件名可能有空格，用 `find -exec {} +` 或 `find -print0 | xargs -0`；如果确定没有空格，裸 `xargs` 也够用。

### 4.5 Here Document：把多行文本直接喂给命令

最后一个实用技巧——当你需要把好几行文本写进文件时，`echo` 一行行写很烦。Bash 提供了 Here Document（此处文档）语法：

```bash
$ cat > config.ini << 'EOF'
[database]
host=127.0.0.1
port=3306
name=mydb

[server]
port=8080
debug=false
EOF
```

`<< 'EOF'` 的意思是：从这里开始，直到遇到独占一行的 `EOF` 为止，中间所有内容都作为 stdin 传给 `cat`。而 `cat > config.ini` 又把 stdin 写入文件——所以这几行文本直接进了 `config.ini`。

注意 `EOF` 两边加了**单引号**。加引号意味着 Here Document 里的 `$变量` 和 `` `命令` `` 不会被展开——原样写入。不加引号的话，Bash 会先做变量替换再传给命令。

---

## 练习题

走到这里，数据流的机制应该已经清楚了——或者你以为清楚了。下面几道题递进难度，建议先不看提示自己试。

**练习 14.1** ⭐（理解）

下面两条命令的输出有什么区别？

```bash
$ ls /home /nonexistent > out.txt 2>&1
$ ls /home /nonexistent 2>&1 > out.txt
```

> **提示**：回忆一下重定向的顺序——Bash 从左到右依次处理。

**练习 14.2** ⭐⭐（应用）

写一条管道命令，完成以下任务：找出 `/var/log` 下所有包含 `error`（不区分大小写）的文件名，去重后按字母排序，只显示前 10 个。要求不显示 `Permission denied` 等错误信息。

> **提示**：`grep -ril` 可以递归搜索文件内容并只输出文件名，`-i` 忽略大小写。用 `2>/dev/null` 丢弃权限错误。去重用 `sort -u`。

**练习 14.3** ⭐⭐⭐（思考）

在 Bash 中执行 `echo "hello" | read word; echo $word`，输出是什么？为什么？这说明管道有一个什么特性？如果要解决这个问题，有什么替代方案？

> **提示**：管道右边的命令运行在一个**子 Shell** 里。变量赋值在子 Shell 中完成，对当前 Shell 不可见。

---

## 本章回响

这一章建立的核心认知是：**Linux 命令不是孤岛，它们可以通过数据流连接成管道系统**。

stdin、stdout、stderr 是三条通道，重定向是给通道换目的地，管道是把两条通道对接。掌握了这套机制，你就能理解那些看起来很复杂的「一行命令」到底在做什么——它们不过是一条条数据在管道里流动，经过一个个处理站。

还记得开头说的那句话吗——「理解了数据流，你就理解了为什么 Linux 的工具设计哲学是『做好一件事』」？现在你应该能回答了：因为每个工具只需要处理 stdin 到 stdout 这一条线，至于上游是谁、下游是谁——管道来操心。`grep` 不需要知道它的输入来自 `find` 还是 `cat`，`sort` 不需要知道它的输出是要显示在屏幕还是要写进文件。这种解耦让每个工具都保持简单，同时通过组合获得无穷的灵活性。

下一章我们会从文本处理转向系统管理——学习 Linux 的用户与组管理。到时候你会发现，今天学的重定向和管道依然会频繁出场：处理用户列表、分析权限配置、批量修改系统设置，都离不开它们。

---

[← 上一章](ch13-textproc.md)
[下一章 →](../04-system/ch15-user.md)
