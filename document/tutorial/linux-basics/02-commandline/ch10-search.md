# 第 10 章  搜索与查找

> **Part 2 · 命令行生存**

---

## 引子

「那个配置文件叫什么来着？放到哪去了？」

这个问题你会问自己无数遍。项目大了之后，文件数量很快超过你的记忆容量。

而在终端里，你没法像 Windows 那样在搜索框里敲个名字等结果——

等等，其实可以。而且终端里的搜索比 Windows 的搜索快得多、准得多。

`find` 在文件系统里按文件属性搜索——名字、类型、大小、修改时间。`grep` 在文件内容里搜关键字——逐行扫描，精确匹配。一个找文件，一个找内容，两个维度，两把武器。

但有一个容易忽略的问题：你知道文件名的时候用 `find`，知道文件内容的时候用 `grep`——那如果你两个都不知道呢？先别急，我们先搞清楚这两把武器各自怎么用，再回答这个问题。

---

## 背景与动机

嵌入式开发中，「找东西」的频率比你想的高得多。

拿到一份别人的 BSP（Board Support Package），里面几百个文件，你需要找到和 I2C 相关的配置——在哪个 `.dts` 文件里？哪个驱动源码里有 `i2c` 关键字？编译报了一个错，提到某个头文件找不到——这个头文件在工具链的哪个目录下？你记得上周改过一个 `Makefile`，但忘了是哪个——怎么快速找到最近修改过的文件？

这些场景有一个共同特征：你知道**一部分信息**（关键字、文件类型、大概的时间），但不知道**完整路径**。搜索命令的任务就是用你手里的那部分信息，帮你把完整路径找出来。

Windows 的搜索框也能干这事，但终端里的搜索有两个它做不到的优势：**精确**和**可组合**。`find` 可以按十几种条件精确筛选，`grep` 可以用正则表达式匹配任意模式——而且它们可以互相配合，像流水线一样把搜索条件一层层叠加。这种组合能力，是图形界面给不了的。

---

## 概念层

搜索文件就像在找人——你知道他的一些特征，但不知道他在哪。

- `find` 是拿着一张特征清单，在整栋楼里逐层找——按名字、按外貌、按职位
- `grep` 是让所有人报一遍自己知道的信息，找出提到某个关键词的人——按内容
- `which` / `whereis` 是查通讯录——找已经登记过的联系人
- `locate` 是查一本预印的通讯录——快，但可能已经过时了

但「找人」这个比喻掩盖了一个关键区别。`find` 和 `locate` 不只是「快一点」和「慢一点」的关系——它们的工作方式完全不同。`find` 是**实时遍历**文件系统，结果绝对准确但速度取决于目录大小；`locate` 是查询一个**预建的数据库**，速度快但结果是某个时间点的快照——昨天创建的文件如果数据库还没更新，就搜不到。这不是效率差异，是「实时」和「快照」的本质区别。

### find —— 按属性搜索文件

`find` 是 Linux 里最强大的文件搜索工具。它逐目录遍历文件系统，按你指定的条件筛选。

基本语法：

```bash
find 搜索路径 搜索条件
```

#### 按文件名搜索：-name

```bash
# 在当前目录下找所有 .txt 文件
$ find . -name "*.txt"
# 预期输出
./notes.txt
./projects/readme.txt
./lab/test.txt
```

> ⚠️ **通配符必须加引号**
> `find -name "*.txt"` 中的 `"*.txt"` **必须**用引号包裹。原因是 Shell 在执行命令之前会先展开通配符——如果你写 `find . -name *.txt`，Shell 会先把 `*.txt` 替换成当前目录下所有 `.txt` 文件的名字（比如 `notes.txt test.txt`），然后 `find` 收到的就不再是模式，而是一堆具体的文件名。结果要么报错，要么搜到的结果根本不是你要的。
>
> 加了引号之后，Shell 不展开，`*.txt` 原样传给 `find`，由 `find` 自己在搜索到的每个目录里做模式匹配。记住：**凡是给 `find` 传通配符模式，一律加引号**。

`-name` 是区分大小写的。如果你不确定大小写，用 `-iname`（insensitive name）：

```bash
$ find . -iname "README*"
# 同时匹配 README.md、readme.txt、Readme
```

#### 按文件类型搜索：-type

```bash
# 只找普通文件
$ find . -type f -name "*.conf"

# 只找目录
$ find . -type d -name "build"

# 只找软链接
$ find . -type l
```

`-type` 常用的值：

| 类型 | 含义 |
|------|------|
| `f` | 普通文件 |
| `d` | 目录 |
| `l` | 软链接 |
| `b` | 块设备（硬盘等） |
| `c` | 字符设备（串口等） |

在嵌入式开发中，`-type b` 和 `-type c` 很有用——找设备文件时直接用。

#### 按文件大小搜索：-size

```bash
# 找大于 10 MB 的文件
$ find . -size +10M

# 找小于 1 KB 的文件
$ find . -size -1k

# 找恰好 100 字节的文件（几乎用不到）
$ find . -size 100c
```

`+` 表示大于，`-` 表示小于，不加前缀表示恰好。单位可以是 `c`（字节）、`k`（KB）、`M`（MB）、`G`（GB）。

#### 按修改时间搜索：-mtime

```bash
# 最近 7 天内修改过的文件
$ find . -mtime -7

# 超过 30 天没修改过的文件
$ find . -mtime +30
```

`-mtime -7` 表示修改时间在 7 天以内，`-mtime +30` 表示修改时间在 30 天以前。这在清理旧编译产物时特别好用。

#### 组合条件

多个条件默认是「与」（AND）关系——所有条件都必须满足：

```bash
# 找 7 天内修改过的 .c 文件
$ find . -name "*.c" -mtime -7

# 找大于 1 MB 的普通文件
$ find . -type f -size +1M
```

### grep —— 按内容搜索

`find` 搜的是文件属性——名字、类型、大小。但很多时候你不知道文件名，只知道文件里应该有某个关键字。这时候该 `grep` 出场了。

`grep` 在文件内容中搜索匹配指定模式的行，并把匹配的行输出。

```bash
# 基本用法
$ grep "error" /var/log/syslog
# 预期输出（包含 "error" 的行）
Jun 11 10:23:45 ubuntu kernel: [  123.456] i2c i2c-0: transfer error
```

#### 常用选项

```bash
# -i：忽略大小写
$ grep -i "warning" logfile.txt
# 同时匹配 Warning、WARNING、warning

# -n：显示行号
$ grep -n "error" logfile.txt
# 预期输出
12:Jun 11 10:23:45 ubuntu kernel: transfer error

# -r：递归搜索目录
$ grep -r "TODO" ~/project/
# 在 ~/project/ 下所有文件中搜索 "TODO"

# -l：只输出匹配的文件名，不显示具体行
$ grep -rl "main" ~/project/src/
# 预期输出
/home/charlie/project/src/main.c
/home/charlie/project/src/test.c
```

在实际开发中，`grep -rn`（递归 + 行号）是最高频的组合：

```bash
$ grep -rn "i2c_probe" ~/project/driver/
# 预期输出
/home/charlie/project/driver/i2c_dev.c:45:int i2c_probe(struct i2c_client *client)
/home/charlie/project/driver/i2c_dev.c:120:    ret = i2c_probe(client);
```

输出格式是 `文件路径:行号:匹配内容`，双击就能定位到具体位置。

#### 正则表达式：基本 vs 扩展

`grep` 支持正则表达式，但默认使用的是**基本正则**（BRE，Basic Regular Expression）。在 BRE 里，`+`、`?`、`(`、`)` 都是普通字符——如果你想用它们的正则含义（「一次或多次」「零次或一次」「分组」），需要加反斜杠转义。

这在写复杂模式时很不直观。所以 `grep` 提供了 `-E` 选项来切换到**扩展正则**（ERE，Extended Regular Expression），这些符号不再需要转义：

```bash
# BRE：\+ 表示「一次或多次」
$ grep "err\+or" logfile.txt

# ERE：+ 直接表示「一次或多次」
$ grep -E "err+or" logfile.txt
```

上面两条命令效果相同——匹配 `error`、`errror`、`errrror`……（`r` 出现一次或多次）。区别只在于 BRE 里必须写 `\+`，ERE 里直接写 `+`。

一个更实际的例子——匹配 `error` 或 `err`：

```bash
# BRE 写法：需要转义 () 和 ?
$ grep "err\(or\)\?" logfile.txt

# ERE 写法：清晰直观
$ grep -E "err(or)?" logfile.txt
```

**实践建议**：当你需要用到 `+`、`?`、`()`、`|`（或）这些正则符号时，一律加 `-E`。BRE 的反斜杠写法容易出错，读起来也费劲。

### which / whereis —— 找命令的位置

这两个命令专门用来找**已安装的命令**在哪个路径。

```bash
# which：显示命令的可执行文件路径
$ which gcc
# 预期输出
/usr/bin/gcc

$ which python3
# 预期输出
/usr/bin/python3

# whereis：同时显示二进制、源码和手册页的位置
$ whereis gcc
# 预期输出
gcc: /usr/bin/gcc /usr/lib/gcc /usr/share/man/man1/gcc.1.gz
```

`which` 只找一个——它在你的 `PATH` 环境变量列出的目录里依次搜索，返回第一个匹配的可执行文件。`whereis` 找三个——二进制文件、源码文件、手册页。

当你装了多个版本的工具链，需要确认当前用的是哪个时，`which` 最直接。

### locate —— 快速查找（按数据库）

`locate` 通过查询一个预建的文件名数据库来搜索，速度比 `find` 快得多——因为它不需要遍历文件系统，直接查数据库索引。

```bash
$ locate stdio.h
# 预期输出（几乎所有包含 "stdio.h" 的路径）
/usr/include/stdio.h
/usr/include/bits/stdio.h
...
```

但 `locate` 有两个限制你需要知道：

**第一，它可能没有预装。** Ubuntu 22.04/24.04 默认不一定安装 `locate`。如果执行时报 `command not found`，需要手动安装：

```bash
$ sudo apt install mlocate
```

安装后需要等 `updatedb` 建完数据库（通常几分钟内自动完成），之后才能使用。

**第二，它的数据不是实时的。** `locate` 查询的数据库由 `updatedb` 命令更新，通常由系统的定时任务每天跑一次。这意味着：**今天刚创建的文件，`locate` 可能搜不到**——要等到下一次数据库更新。

```bash
# 手动更新数据库（需要 sudo）
$ sudo updatedb
```

所以 `locate` 适合「模糊搜索一个你知道应该存在的老文件」——快，但不保证最新。`find` 适合「精确搜索，结果必须可靠」——慢一点，但绝对准确。

---

## 实践层

### 4.1 准备实验环境

创建一个模拟项目目录：

```bash
$ cd ~
$ mkdir -p ~/lab/search/project/{src,include,driver,docs}
$ cd ~/lab/search

# 创建一些测试文件
$ echo '#include <stdio.h>' > project/src/main.c
$ echo 'int main() { printf("Hello"); return 0; }' >> project/src/main.c
$ echo '// TODO: fix error handling' > project/src/utils.c
$ echo '#define MAX_SIZE 1024' > project/include/config.h
$ echo '/* i2c driver implementation */' > project/driver/i2c.c
$ echo '// TODO: add i2c probe function' >> project/driver/i2c.c
$ echo "Project README" > project/docs/README.md
$ touch project/docs/CHANGELOG.md
```

### 4.2 find 实战——按属性搜

```bash
# 找所有 .c 文件
$ find ~/lab/search -name "*.c"
# 预期输出
/home/charlie/lab/search/project/src/main.c
/home/charlie/lab/search/project/src/utils.c
/home/charlie/lab/search/project/driver/i2c.c

# 只找目录
$ find ~/lab/search -type d
# 预期输出
/home/charlie/lab/search
/home/charlie/lab/search/project
/home/charlie/lab/search/project/src
/home/charlie/lab/search/project/include
/home/charlie/lab/search/project/driver
/home/charlie/lab/search/project/docs

# 组合条件：找所有 .c 文件，但只在 driver 目录下
$ find ~/lab/search/project/driver -name "*.c"
# 预期输出
/home/charlie/lab/search/project/driver/i2c.c
```

来验证一下引号的重要性。不加引号试试：

```bash
# 先确保当前目录下没有 .c 文件（这样 Shell 就不会展开 *.c）
$ cd ~/lab/search
$ find . -name *.c
# 在当前目录没有 .c 文件的情况下，Shell 没法展开 *.c，所以结果碰巧正确

# 但如果当前目录下有 .c 文件呢？
$ touch test.c
$ find . -name *.c
# 预期输出（Shell 把 *.c 展开成了 test.c，find 收到的变成了 -name test.c）
# 只会匹配名为 "test.c" 的文件，而不是所有 .c 文件！
```

这个坑很隐蔽——在当前目录没有匹配文件时碰巧不出错，一旦有匹配文件就会给出错误结果。所以养成习惯：**`find -name` 的模式一律加引号**。

### 4.3 grep 实战——按内容搜

```bash
# 搜索所有文件中的 "TODO"
$ grep -rn "TODO" ~/lab/search/project/
# 预期输出
/home/charlie/lab/search/project/src/utils.c:1:// TODO: fix error handling
/home/charlie/lab/search/project/driver/i2c.c:2:// TODO: add i2c probe function

# 忽略大小写搜 "readme"
$ grep -rni "readme" ~/lab/search/project/
# 预期输出
/home/charlie/lab/search/project/docs/README.md:1:Project README

# 只看哪些文件包含 "TODO"（不显示具体行）
$ grep -rl "TODO" ~/lab/search/project/
# 预期输出
/home/charlie/lab/search/project/src/utils.c
/home/charlie/lab/search/project/driver/i2c.c

# 用正则搜索：匹配 "i2c" 或 "I2C" 或 "I2c" 等
$ grep -rniE "i2c" ~/lab/search/project/
# -i 已经忽略大小写了，这里 -E 不是必须的
# 但如果模式更复杂，比如 "i2c" 或 "spi"：
$ grep -rnE "i2c|spi" ~/lab/search/project/
# 预期输出
/home/charlie/lab/search/project/driver/i2c.c:1:/* i2c driver implementation */
/home/charlie/lab/search/project/driver/i2c.c:2:// TODO: add i2c probe function
```

最后一个例子中 `|` 表示「或」——在 ERE 里直接用就行，在 BRE 里需要写成 `\|`。

### 4.4 找命令的位置

```bash
# find 命令本身在哪？
$ which find
# 预期输出
/usr/bin/find

# grep 命令的相关文件
$ whereis grep
# 预期输出
grep: /usr/bin/grep /usr/share/man/man1/grep.1.gz

# 你安装的编译器在哪？
$ which gcc
# 预期输出（如果安装了 gcc）
/usr/bin/gcc

# 如果没安装呢？
$ which arm-none-eabi-gcc
# 没有输出，说明没找到——命令不在 PATH 里
```

`which` 没有输出，就说明这个命令要么没装，要么不在你的 `PATH` 环境变量里。`PATH` 的概念我们在第 30 章详细讲。

### 4.5 清理

```bash
$ cd ~
$ rm -rf ~/lab
```

---

## 练习题

搜索是日常开发中用得最多的技能之一。下面几道题从简到难，建议全部动手做一遍——尤其是第二题，它涉及一个很多人踩过的坑。

**练习 10.1** ⭐（理解）

`find` 和 `locate` 都能按文件名搜索，它们的主要区别是什么？在什么场景下你会优先选择 `find`？什么场景下优先选择 `locate`？

**练习 10.2** ⭐⭐（应用）

在你的系统上执行以下两条命令，比较输出结果：

```bash
$ find /etc -name "*.conf" -type f | head -n 10
$ locate "*.conf" | head -n 10
```

它们的输出一样吗？为什么？再创建一个新文件 `/tmp/test_search.conf`，分别用 `find` 和 `locate` 搜索它——结果有什么不同？如何让 `locate` 也能找到这个新文件？

> **提示**：`locate` 的数据库不会实时更新。创建新文件后需要运行 `sudo updatedb` 手动更新。

**练习 10.3** ⭐⭐⭐（思考）

`find -name "*.txt"` 中的通配符为什么必须加引号？如果不加引号，Shell 会做什么？试着手动模拟这个过程：假设当前目录下有 `a.txt` 和 `b.txt` 两个文件，执行 `find . -name *.txt` 时 Shell 会把命令变成什么？`find` 收到的参数又是什么？

> **提示**：Shell 的通配符展开发生在命令执行之前。`find` 看到的永远是 Shell 展开之后的结果。

---

## 本章回响

本章建立的核心能力是**双维度搜索**：`find` 按文件属性搜，`grep` 按文件内容搜。这两个维度覆盖了你在终端里「找东西」的绝大部分需求——知道文件名（或部分特征）用 `find`，知道文件里应该有某个关键字用 `grep`。`which` 和 `whereis` 是快捷通道，专门找已安装命令的位置；`locate` 是速度优先的方案，代价是结果可能不是最新的。

还记得引子里那个问题吗——如果你既不知道文件名也不知道文件内容，该怎么办？答案是缩小范围：用 `find` 按时间和类型过滤出一批候选文件，再用 `grep` 在这批文件里搜索你可能记得的任何蛛丝马迹。两种工具配合使用，才是它们真正的威力。而「找人」的比喻——`find` 是逐层找人，`locate` 是翻旧通讯录——现在你应该能看出它们的本质差异了：实时遍历 vs 数据库快照。选哪个，取决于你的结果需要多准确。

`grep` 的能力其实远不止这一章讲的。它的输出可以被管道传给其他命令做进一步处理——比如统计匹配行数、筛选特定字段、按条件排序。这种组合能力是命令行最强大的地方，也是我们在第 14 章（重定向与管道）要正式展开的主题。届时你会发现，`grep` 配上管道，能做的不只是「搜」——它可以变成一个强大的文本分析工具。

下一章我们会从搜索转向另一个日常需求：打包和压缩。嵌入式开发中你每天都要和 `.tar.gz` 文件打交道——它们是怎么创建的，怎么解开的？我们下一章见。

---

[← 上一章](ch09-fileview.md)
[下一章 →](ch11-archive.md)
