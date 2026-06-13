# 第 13 章  文本处理三剑客

> **Part 3 · 文本与编辑**

---

## 引子

日志文件三万行，报错信息藏在第 17842 行。你要把所有包含「error」的行揪出来，按时间排序，去重之后统计每种错误出现了多少次。

手动翻？翻到天亮也翻不完。

`sed`、`awk`、`sort`、`uniq`、`cut`、`tr`——这套文本处理工具链，就是终端里的「Excel 数据透视表」。它们各自只做一件事，但组合起来能解决 90% 的文本处理问题。

但这里有一个问题：为什么 Linux 不直接给你一个全能的文本处理工具？为什么是六七个各管一摊的小命令，而不是一个「超级文本处理器」？

答案在下一章。但这一章，我们先把每个工具的用法搞扎实。

---

## 背景与动机

嵌入式开发中，你要处理的"文本"比你想象的多得多：

- 编译输出的几百行日志，你想只看 `error` 行
- `.csv` 格式的传感器数据，你要提取第二列和第五列
- 配置文件里有一个 IP 地址写错了，你要批量替换
- `dmesg` 输出里混杂着信息和警告，你要筛出关键几行

在 Windows 上，你可能打开 Excel 处理数据，用 Notepad++ 搜索替换。在终端里没有 GUI，但有一套更强大的工具——`sed` 做替换，`awk` 做字段提取，`sort`/`uniq`/`cut`/`tr` 做各种辅助处理。

这套工具的设计哲学和 `tar`/`gzip` 一样：每个工具只做一件事。`sed` 不负责排序，`awk` 不负责去重。但下一章你会学到管道——把这些工具串起来，它们的组合能力远超任何单一工具。

---

## 概念层

### sed：流编辑器

`sed` 的名字来自 **S**tream **Ed**itor——流编辑器。它做的事情很单一：对文本流进行编辑操作——替换、删除、插入。

"流"是关键。`sed` 不需要把整个文件加载到内存里，它逐行处理，读一行、改一行、输出一行。这意味着哪怕文件有几 GB，`sed` 也能工作——只要你不需要跨行操作。

`sed` 最常用的操作是**替换**：

```bash
# 把每行中第一个 "old" 替换成 "new"
$ echo "hello old world" | sed 's/old/new/'
# 预期输出
hello new world
```

`s` 表示替换（**s**ubstitute），三段式结构：`s/被替换的内容/替换后的内容/`。

默认只替换每行中的**第一个**匹配。要替换所有出现，加 `g`（**g**lobal）：

```bash
$ echo "old old old" | sed 's/old/new/g'
# 预期输出
new new new
```

`sed` 可以直接处理文件：

```bash
# 替换文件中的内容，结果输出到屏幕（文件本身不变）
$ cat colors.txt
red blue green
blue red yellow
$ sed 's/red/RED/g' colors.txt
# 预期输出
RED blue green
blue RED yellow

# 文件内容没变
$ cat colors.txt
red blue green
blue red yellow
```

这里有一个关键的机制：`sed` 默认把处理结果输出到 stdout，**不动原文件**。这是一种安全设计——你可以先在屏幕上看到效果，满意了再写入文件。

但如果你想让修改直接生效，就需要 `-i` 参数：

```bash
# -i：直接修改原文件（in-place）
$ sed -i 's/red/RED/g' colors.txt
$ cat colors.txt
# 预期输出
RED blue green
blue RED yellow
```

> ⚠️ **踩坑预警：`sed -i` 是一把双刃剑**
>
> `-i` 会直接修改原文件，没有撤销，没有回收站。如果你写错了正则表达式，原文件就被改坏了。
>
> 一个保护措施：`sed -i.bak` 会在修改之前先把原文件备份为 `colors.txt.bak`：
>
> ```bash
> $ sed -i.bak 's/red/RED/g' colors.txt
> $ ls
> colors.txt  colors.txt.bak    # 自动备份
> ```
>
> 这样就算改坏了，还有 `.bak` 文件可以恢复。
>
> 另外注意：macOS 的 `sed` 和 Linux 的 `sed` 行为不同。macOS 自带的 BSD `sed` 要求 `-i` 后面必须跟一个参数（备份后缀），即使是空字符串也要写：`sed -i '' 's/old/new/g' file`。Linux 的 GNU `sed` 不需要。如果你在 macOS 上工作，装一个 GNU `sed`（`brew install gnu-sed`）可以避免这个差异。

`sed` 除了替换，还能做删除和插入：

```bash
# 删除空行
$ sed '/^$/d' file.txt

# 删除第 3 行
$ sed '3d' file.txt

# 在第 2 行后面插入一行
$ sed '2a\inserted line' file.txt
```

`d` 表示删除（**d**elete），`a` 表示追加（**a**ppend），`i` 表示在前面插入（**i**nsert）。这些操作在处理日志和配置文件时很常用。

### awk：字段提取器

如果说 `sed` 是「文本替换器」，那 `awk` 就是「文本分析器」。它的名字来自三位作者的首字母（Aho、Weinberger、Kernighan），它最擅长的操作是**按列处理文本**。

你可以把 `awk` 想象成一把手术刀——它把每一行文本按分隔符切成一个个字段，然后你告诉它要哪个字段。

**默认行为：按空格切分，`$1` 是第一列，`$2` 是第二列……**

```bash
$ echo "Alice 85 92 78" | awk '{print $2}'
# 预期输出
85
```

`$1` 是 `Alice`，`$2` 是 `85`，`$3` 是 `92`，`$4` 是 `78`。`$0` 是整行。

几个高频用法：

```bash
# 提取第一列和第三列
$ echo "Alice 85 92 78" | awk '{print $1, $3}'
# 预期输出
Alice 92

# 打印行号（NR = Number of Records = 当前行号）
$ echo -e "line1\nline2\nline3" | awk '{print NR, $0}'
# 预期输出
1 line1
2 line2
3 line3

# 打印字段数（NF = Number of Fields = 当前行的字段数）
$ echo "a b c d" | awk '{print NF}'
# 预期输出
4

# 打印最后一个字段（$NF 是动态的——第几列取决于这一行有几个字段）
$ echo "one two three four" | awk '{print $NF}'
# 预期输出
four
```

`NR` 和 `NF` 是 `awk` 里最重要的两个内置变量。`NR` 告诉你"现在是第几行"，`NF` 告诉你"这一行有几个字段"。配合条件判断，就能做更有用的事：

```bash
# 只打印第二列大于 80 的行
$ cat scores.txt
Alice 85
Bob 72
Carol 90
$ awk '$2 > 80 {print $1, $2}' scores.txt
# 预期输出
Alice 85
Carol 90
```

`awk` 会把 `$2 > 80` 当作条件——只有满足条件的行才会执行 `{print $1, $2}`。

`awk` 默认按空格和 Tab 分隔字段。如果你的数据是用其他分隔符的（比如 CSV 文件用逗号），用 `-F` 指定：

```bash
# -F 指定分隔符为逗号
$ echo "name,age,city" | awk -F',' '{print $3}'
# 预期输出
city
```

以上这些——字段提取、条件过滤、分隔符指定——覆盖了 `awk` 80% 的使用场景。`awk` 其实是一门完整的编程语言，支持变量、循环、函数、数组。但那些高级功能在日常开发中用得不多，等你遇到了再去查文档也来得及。

> **Ubuntu 上的 awk 实现**：Ubuntu 22.04/24.04 默认安装的 `awk` 指向的是 **mawk**（而不是 GNU awk 即 gawk）。mawk 更快，但不支持 GNU 扩展（如 `gensub()`、时间函数等）。本章的示例全部使用 POSIX 标准功能，在 mawk 上可以正常运行。如果你后续需要 GNU 扩展，`sudo apt install gawk` 即可。

### sort / uniq / cut / tr / tee：辅助工具链

这几个工具单独看都不复杂，但它们是构建管道的基本积木。

**sort：排序**

```bash
# 默认按字母序排序
$ echo -e "banana\napple\ncherry" | sort
# 预期输出
apple
banana
cherry

# -n 按数值排序（否则 "9" 会排在 "10" 后面）
$ echo -e "9\n10\n1\n100" | sort -n
# 预期输出
1
9
10
100

# -r 倒序
$ echo -e "banana\napple\ncherry" | sort -r
# 预期输出
cherry
banana
apple
```

**uniq：去重**

`uniq` 只能去除**相邻的**重复行。所以它几乎总是跟在 `sort` 后面：

```bash
$ echo -e "apple\nbanana\napple\ncherry\nbanana" | sort | uniq
# 预期输出
apple
banana
cherry
```

一个高频组合是 `sort | uniq -c`——统计每个值出现的次数：

```bash
$ echo -e "error\nwarn\nerror\nerror\ninfo\nwarn" | sort | uniq -c
# 预期输出
      3 error
      1 info
      2 warn
```

再接一个 `sort -rn`，就得到了频次排名：

```bash
$ echo -e "error\nwarn\nerror\nerror\ninfo\nwarn" | sort | uniq -c | sort -rn
# 预期输出
      3 error
      2 warn
      1 info
```

这条 `sort | uniq -c | sort -rn` 是文本分析中出场率最高的管道之一——记住它。

**cut：按列截取**

`cut` 比 `awk` 简单，但对付固定格式的文本很好用：

```bash
# -d 指定分隔符，-f 指定第几列
$ echo "Alice:85:Beijing" | cut -d':' -f2
# 预期输出
85

# 提取多列
$ echo "Alice:85:Beijing" | cut -d':' -f1,3
# 预期输出
Alice:Beijing
```

**tr：字符替换**

`tr`（**tr**anslate）做的是单字符级别的替换或删除：

```bash
# 把小写转大写
$ echo "hello" | tr 'a-z' 'A-Z'
# 预期输出
HELLO

# 删除所有数字
$ echo "abc123def456" | tr -d '0-9'
# 预期输出
abcdef

# 把连续的空格压缩成一个
$ echo "too    many    spaces" | tr -s ' '
# 预期输出
too many spaces
```

**tee：分流器**

`tee` 我们在重定向那一章已经见过，它在这里的角色是一个管道中的"三通接头"——把数据流分成两路，一路继续往下传，一路写入文件：

```bash
$ cat scores.txt | tee backup.txt | awk '$2 > 80 {print $1}'
# 屏幕上显示 Alice 和 Carol
# 同时 backup.txt 保存了原始的 scores.txt 内容
```

---

## 实践层

### 4.1 sed 替换实战

先准备一个练习文件：

```bash
$ mkdir -p ~/textproc-lab
$ cat > ~/textproc-lab/config.txt << 'EOF'
server_ip=192.168.1.100
port=8080
debug=false
log_level=INFO
server_ip=192.168.1.100
EOF
$ cd ~/textproc-lab
```

**场景一：替换 IP 地址**

```bash
# 把 192.168.1.100 替换为 10.0.0.1
$ sed 's/192.168.1.100/10.0.0.1/g' config.txt
# 预期输出
server_ip=10.0.0.1
port=8080
debug=false
log_level=INFO
server_ip=10.0.0.1
```

注意 `.` 在正则表达式里有特殊含义（匹配任意字符）。严格来说应该写成 `192\.168\.1\.100`。但在这个例子中，因为字符串足够特殊，不会误匹配。正式场景中还是建议转义。

**场景二：删除空行和注释行**

```bash
$ cat > sample.conf << 'EOF'
# 这是注释
server=on

# 另一个注释
port=443

timeout=30
EOF

# 删除空行和 # 开头的注释行
$ sed -e '/^$/d' -e '/^#/d' sample.conf
# 预期输出
server=on
port=443
timeout=30
```

`-e` 允许你串联多个编辑命令。`/^$/d` 删除空行，`/^#/d` 删除以 `#` 开头的行。

**场景三：安全地原地修改**

```bash
# 先备份，再修改
$ sed -i.bak 's/INFO/DEBUG/g' config.txt
$ cat config.txt
# 预期输出
server_ip=192.168.1.100
port=8080
debug=false
log_level=DEBUG
server_ip=192.168.1.100

# 备份文件保留了原始内容
$ cat config.txt.bak
# 预期输出（原始内容）
server_ip=192.168.1.100
port=8080
debug=false
log_level=INFO
server_ip=192.168.1.100
```

### 4.2 awk 字段提取实战

准备一份模拟的传感器日志：

```bash
$ cat > ~/textproc-lab/sensor.log << 'EOF'
timestamp temp humidity pressure
2024-01-10 22.5 45 1013
2024-01-10 23.1 48 1012
2024-01-10 24.8 52 1010
2024-01-10 21.3 41 1015
2024-01-10 25.1 55 1009
2024-01-10 20.9 39 1016
EOF
$ cd ~/textproc-lab
```

**提取特定列**

```bash
# 只看温度（第二列，跳过标题行）
$ awk 'NR > 1 {print $2}' sensor.log
# 预期输出
22.5
23.1
24.8
21.3
25.1
20.9
```

`NR > 1` 跳过第一行（标题行）。

**过滤 + 格式化输出**

```bash
# 找出温度超过 23 度的记录，格式化输出
$ awk 'NR > 1 && $2 > 23 {printf "温度: %.1f°C  湿度: %d%%\n", $2, $3}' sensor.log
# 预期输出
温度: 23.1°C  湿度: 48%
温度: 24.8°C  湿度: 52%
温度: 25.1°C  湿度: 55%
```

`printf` 的用法和 C 语言一样——`%.1f` 保留一位小数，`%d` 整数，`%%` 输出一个 `%` 符号本身。

**统计平均值**

```bash
# 计算平均温度
$ awk 'NR > 1 {sum += $2; count++} END {printf "平均温度: %.1f°C (共 %d 条记录)\n", sum/count, count}' sensor.log
# 预期输出
平均温度: 22.9°C (共 6 条记录)
```

这里出现了 `awk` 的 `BEGIN`/`END` 模式。`END` 块在所有行处理完之后执行一次——适合做汇总统计。`sum += $2` 累加温度，`count++` 计数，最后 `sum/count` 算平均值。

### 4.3 经典管道组合

这些工具真正的威力在组合。以下是几个高频实战场景。

**场景一：日志错误频次统计**

```bash
$ cat > ~/textproc-lab/app.log << 'EOF'
[2024-01-10 08:01:23] INFO server started
[2024-01-10 08:05:11] WARN disk space low
[2024-01-10 08:12:45] ERROR connection timeout
[2024-01-10 08:15:00] INFO user login
[2024-01-10 08:20:33] ERROR connection timeout
[2024-01-10 08:25:00] ERROR disk read fail
[2024-01-10 08:30:11] WARN memory usage high
[2024-01-10 08:35:22] ERROR connection timeout
EOF
$ cd ~/textproc-lab

# 统计每种错误出现的次数，按频次排序
$ grep "ERROR" app.log | awk '{print $4}' | sort | uniq -c | sort -rn
# 预期输出
      3 connection
      1 disk
```

拆解这条管道：`grep` 滤出 ERROR 行 → `awk` 提取错误类型（第 4 个字段）→ `sort` 排序让相同错误相邻 → `uniq -c` 计数 → `sort -rn` 按次数从大到小排列。每一层只做一件事，但串起来就是一个完整的分析流程。

**场景二：提取 CSV 中的特定列**

```bash
$ cat > ~/textproc-lab/data.csv << 'EOF'
name,age,city,score
Alice,25,Beijing,88
Bob,30,Shanghai,92
Carol,28,Beijing,76
David,35,Shenzhen,95
Eve,22,Beijing,81
EOF
$ cd ~/textproc-lab

# 提取所有在北京的人的姓名和分数
$ awk -F',' '$3 == "Beijing" {print $1, $4}' data.csv
# 预期输出
Alice 88
Carol 76
Eve 81
```

**场景三：处理 dmesg 输出**

```bash
# 从 dmesg 中提取 USB 相关信息，去掉时间戳，只看设备名
$ dmesg | grep -i usb | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | head -5
# 实际输出取决于你的系统
# 这里只是演示组合方式
```

这条管道展示了 `awk` 的一个进阶用法：`for` 循环打印从第 3 列到最后一列的内容——相当于"去掉前两列"。这种"扔掉前几列，保留后面所有"的需求很常见，`awk` 的 `$i` 循环是最干净的做法。

---

## 练习题

工具用法学完了，但真正的理解在于组合。下面几道题递进难度，建议先自己动手试。

**练习 13.1** ⭐（理解）

以下两条命令的输出有什么区别？

```bash
$ echo "hello world" | sed 's/o/O/'
$ echo "hello world" | sed 's/o/O/g'
```

> **提示**：不加 `g` 和加了 `g` 的区别——回忆"全局替换"的含义。

**练习 13.2** ⭐⭐（应用）

给定以下文件 `access.log`：

```
192.168.1.10 - GET /index.html
192.168.1.20 - POST /api/login
192.168.1.10 - GET /about.html
192.168.1.30 - GET /index.html
192.168.1.10 - POST /api/data
192.168.1.20 - GET /index.html
```

写一条管道命令，统计每个 IP 地址出现的次数，按次数从多到少排序。

> **提示**：`awk '{print $1}'` 提取第一列 → `sort | uniq -c | sort -rn`。

**练习 13.3** ⭐⭐⭐（思考）

本章开头问了一个问题：为什么 Linux 不提供一个全能的文本处理工具？结合本章学到的 `sed`、`awk`、`sort`、`uniq`，说说你的理解。如果你要设计一个"超级文本处理器"来替代它们，你会遇到什么困难？

> **提示**：想想当你需要"统计某个字段的出现频次并按数值排序"时，你用了几个工具。如果是一个全能工具，它的接口会是什么样的？

---

## 本章回响

这一章我们一口气学了六个工具。但如果你只能记住三样东西，记住这些：

**`sed` 做替换，`awk` 做字段提取，`sort | uniq -c | sort -rn` 做频次统计。**

这三样覆盖了日常文本处理的绝大多数场景。`cut`、`tr`、`tee` 是补充——它们各自只有一两个高频用法，用到的时候再查也来得及。

还记得开头那个问题吗——为什么 Linux 不给你一个全能的文本处理工具？答案其实已经藏在每个工具的设计里了：`sed` 不需要知道你的数据有几列，`awk` 不需要知道你要不要排序，`sort` 不需要知道你的数据是什么格式。每个工具只关心自己擅长的那一件事，通过标准输入输出交换数据。

这种设计的代价是你得多敲几条管道。但好处是：当一种新的需求出现时，你不需要等某个全能工具升级——你只需要用现有的小工具拼一条新的管道出来。组合的力量远大于单个工具的功能叠加。

这恰好也是下一章要讲的核心——管道和重定向。`sed` 的输出怎么变成 `awk` 的输入？`awk` 的输出怎么同时显示在屏幕上又存进文件？答案都是一个字符的事。

下一章，我们把管道接上。

---

[← 上一章](ch12-vim.md)
[下一章 →](ch14-redirect.md)
