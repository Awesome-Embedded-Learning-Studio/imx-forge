# 第 26 章  Shell 脚本基础

> **Part: Part 6 · 脚本与自动化**

---

## 引子

你每天早上到工位，要敲二十条命令才能把开发环境启动起来。

第一条设置交叉编译工具链路径，第二条拉取最新代码，第三条编译 bootloader，第四条编译内核……二十条命令，顺序不能错，漏一条就白编译。

如果这二十条命令能写在一个文件里，一条命令执行全部呢？

这就是 Shell 脚本。

但当你第一次打开一个 `.sh` 文件的时候，你会看到一种奇怪的语法——变量前面要加 `$`，赋值的时候又不能加；等号两边不能有空格；字符串的引号有时单有时双，行为还不一样。和 C 语言比起来，这套语法简直丑得不像话。

这个「丑」不是偶然的。Shell 脚本的语法之所以长成这样，是因为它和终端之间有一条割不断的脐带——bash 同时要当交互式命令行和脚本解释器，每一个语法怪癖都是这个双重身份的副产品。这章我们就来理清这条脐带。

---

## 背景与动机

如果你之前照着教程敲过几条命令，那你已经写过「单行脚本」了——你在终端里敲的每一条命令，本质上就是脚本的一行。

问题是这些命令没法保存。关掉终端，一切归零。第二天来，从头敲。

Shell 脚本解决的就是这个问题——把你在终端里做的事写进文件，需要的时候一键执行。

> 「那为什么不直接用 Python？」

这个问题迟早会出现。答案是：Python 需要安装，Shell 不需要。每台 Linux 机器上都自带 bash，嵌入式开发板上也多半有 busybox ash。当你需要写一个编译脚本、一个环境初始化脚本、一个日志清理脚本——Shell 是最直接的选择。它不需要任何额外依赖，直接和系统命令对话。

当然，Shell 的表达能力有天花板。复杂的数据结构、网络编程、大量数学计算——这些交给 Python。但日常的系统自动化任务，Shell 恰好够用，而且写起来最快。

还有一个原因你可能没意识到：**读懂别人的 Shell 脚本是嵌入式开发中的刚需**。Makefile 里嵌着 Shell，Dockerfile 里全是 Shell，CI/CD 的 pipeline 本质上也是 Shell。不学 Shell 脚本，这三样东西你只能猜。

---

## 概念层

### 脚本是什么——一张「会变的剧本」

你可以把 Shell 脚本理解为一张**演员的剧本**——bash 是演员，脚本是你写给它的台词。脚本里写的每一条命令，都是你希望 bash 依次「说」出来并执行的东西。

```bash
#!/bin/bash
echo "Setting up environment..."
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
echo "Done."
```

这段脚本和你在终端里依次敲四条命令，效果完全一样。bash 从第一行读到最后一样，逐行执行——就像演员照着剧本念台词。

但「剧本」这个比喻有一个地方是错的：真正的剧本是固定的，台词印在纸上不会变。Shell 脚本不是——它有变量、有输入、有条件判断。同一个脚本，不同的输入，不同的行为。它不是「播放录像」，更像「带占位符的自动演奏」——`$PROJECT` 不是台词本身，而是「到这里查一下 PROJECT 的值再念出来」的指令。

这就是那条脐带的来源。bash 的语法设计必须同时服务于两种场景：一个人坐在终端前实时敲命令，和一个人写好脚本让 bash 自动执行。这两个场景的需求不完全一致，但 bash 只有一套语法。于是你会看到很多「在终端里很自然、在脚本里很别扭」的设定——等号两边不能有空格就是最典型的一个。

### Shebang：告诉系统「谁来演这出戏」

脚本的第一行几乎总是长这样：

```bash
#!/bin/bash
```

这行叫 **shebang**（`#!` 的连读）。它的作用很简单：告诉操作系统，用哪个程序来执行这个文件。

当你运行 `./build.sh` 的时候，操作系统做的第一件事不是执行脚本内容，而是读第一行。它看到 `#!/bin/bash`，就调用 `/bin/bash` 来解释后面的内容。如果没有这行呢？系统会用当前 Shell 来执行——可能是 bash，也可能是 dash、zsh，取决于你的环境。

这里有一个容易踩的坑。在 Ubuntu 上，`/bin/sh` **不是 bash**——它指向 `dash`，一个更小更快的 POSIX Shell：

```bash
# 查看 Ubuntu 上 /bin/sh 指向谁
$ ls -l /bin/sh
# 预期输出
lrwxrwxrwx 1 root root 4 Jan 15 10:00 /bin/sh -> dash
```

`dash` 不支持 bash 的很多扩展语法（比如 `[[ ]]`、数组、`(( ))` 算术）。所以如果你的脚本用了 bash 特有的语法，shebang 就必须写 `#!/bin/bash`，不能写 `#!/bin/sh`，否则在 Ubuntu 上会报语法错误。这是一个经典的「在我的机器上能跑」陷阱——macOS 的 `/bin/sh` 默认行为和 Ubuntu 不同，某些发行版的 `/bin/sh` 指向 bash 而非 dash。

### 变量：脚本的「记忆」

Shell 里的变量不需要声明类型，赋值就是定义：

```bash
# 定义变量——等号两边不能有空格
PROJECT="imx-forge"
VERSION="1.0"
BUILD_DIR="$HOME/build"
```

等号两边不能有空格这件事，是 Shell 语法里被吐槽最多的设计之一。`PROJECT = "imx-forge"` 在 C 语言里完全合法，但在 Shell 里——bash 会把 `PROJECT` 当成命令来执行，然后报 `command not found`。为什么？因为在终端里，空格是命令和参数的分隔符。bash 看到 `PROJECT = "imx-forge"`，认为 `PROJECT` 是命令名，`=` 和 `"imx-forge"` 是两个参数。

回到那张「剧本」——演员看到 `PROJECT = "imx-forge"` 这行台词，不会理解为「把 imx-forge 赋值给 PROJECT」，而是理解成「执行一个叫 PROJECT 的命令，带上 = 和 imx-forge 两个参数」。这就是那条脐带——交互式命令行的解析规则被原封不动地搬到了脚本里。

使用变量的时候，在变量名前面加 `$`：

```bash
echo "Project: $PROJECT"
echo "Build dir: $BUILD_DIR"
# 预期输出
Project: imx-forge
Build dir: /home/charlie/build
```

这里有一个微妙之处：**`$PROJECT` 发生的是文本替换**。bash 在执行 `echo` 之前，先把 `$PROJECT` 替换成 `imx-forge`，然后才把完整的字符串传给 `echo`。这和 C 语言的变量完全不同——C 变量是一块命名的内存，Shell 变量是一段命名的文本。

#### 三种变量

Shell 的变量有三种来源，理解它们的区别对后面写脚本至关重要。

**自定义变量**——你自己定义和赋值的：

```bash
TOOLCHAIN_PATH="/opt/arm-toolchain/bin"
OUTPUT_DIR="$HOME/build_output"
JOBS=4
```

**环境变量**——用 `export` 导出后，子进程能继承的变量：

```bash
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
export PATH="$TOOLCHAIN_PATH:$PATH"
```

`export` 做了什么？它把变量从「只有当前 Shell 能看到」变成「当前 Shell 和它启动的所有子进程都能看到」。当你写 `export PATH=...` 的时候，后面启动的编译器、Make 工具——它们都能读到这个 `PATH`。不加 `export`，子进程看不到。

这就是为什么交叉编译工具链的设置脚本里总是有 `export`——编译器是在子进程里运行的，它需要通过环境变量知道工具链在哪。

**特殊变量**——bash 自动设置的，你不需要也不能赋值：

| 变量 | 含义 |
|------|------|
| `$0` | 脚本自身的文件名（严格说是调用时写的命令） |
| `$1` ~ `$9` | 第 1 到第 9 个位置参数 |
| `$#` | 位置参数的个数 |
| `$@` | 所有位置参数（每个参数独立） |
| `$?` | 上一条命令的退出码（0 表示成功） |
| `$$` | 当前脚本的进程号 |

特殊变量在写通用脚本时极为常用。假设你写了一个编译脚本，需要接收目标板名称作为参数：

```bash
#!/bin/bash
echo "Script: $0"
echo "Target board: $1"
echo "Total arguments: $#"

# 如果没传参数，提醒用户
if [ $# -eq 0 ]; then
    echo "Usage: $0 <board_name>"
    exit 1
fi
```

```bash
$ ./build.sh imx6ull
# 预期输出
Script: ./build.sh
Target board: imx6ull
Total arguments: 1

$ ./build.sh
# 预期输出
Script: ./build.sh
Target board:
Total arguments: 0
Usage: ./build.sh <board_name>
```

`$?` 是调试时最常用的特殊变量。每条命令执行完后都会返回一个 0-255 的退出码，0 代表成功，非零代表失败：

```bash
$ ls /tmp/some_dir
# 预期输出
ls: cannot access '/tmp/some_dir': No such file or directory

$ echo $?
# 预期输出
2

$ echo "hello"
# 预期输出
hello

$ echo $?
# 预期输出
0
```

### 字符串操作

Shell 对字符串的处理能力比大多数人想象的要强。不需要调用外部命令，bash 内建就能做拼接、截取和替换。

**拼接**——直接把变量写在双引号字符串里：

```bash
BOARD="imx6ull"
KERNEL_VERSION="5.15"
IMAGE_NAME="zImage-${BOARD}-kernel-${KERNEL_VERSION}.bin"

echo "$IMAGE_NAME"
# 预期输出
zImage-imx6ull-kernel-5.15.bin
```

双引号里的 `$变量` 会被替换，单引号里的不会——这是 Shell 里最经典的陷阱之一：

```bash
NAME="world"
echo "Hello, $NAME"    # 双引号：变量会被替换
echo 'Hello, $NAME'    # 单引号：原样输出
# 预期输出
Hello, world
Hello, $NAME
```

> ⚠️ **注意**
> 在 Shell 脚本里，字符串几乎永远用双引号——除非你明确需要「原样输出、不做任何替换」。单引号的使用场景远少于双引号。

**截取**——`${变量:起始:长度}`，注意下标从 0 开始：

```bash
VERSION="v5.15.32"
echo "${VERSION:1}"      # 从第 1 个字符截取到末尾（跳过 'v'）
# 预期输出
5.15.32

echo "${VERSION:1:4}"    # 从第 1 个字符截取 4 个字符
# 预期输出
5.15
```

**模式删除**——`#` 从头部删，`%` 从尾部删：

```bash
GIT_TAG="rel-v5.15.32-stable"

# 删掉 "rel-" 前缀
echo "${GIT_TAG#rel-}"
# 预期输出
v5.15.32-stable

# 删掉 "-stable" 后缀
echo "${GIT_TAG%-stable}"
# 预期输出
rel-v5.15.32
```

`#` 删最短前缀匹配，`##` 删最长前缀匹配。这个区别在处理文件路径时特别有用：

```bash
IMAGE_PATH="/home/charlie/build/zImage-imx6ull.bin"

# 提取文件名：从头部删掉最长匹配 */（所有目录层级）
echo "${IMAGE_PATH##*/}"
# 预期输出
zImage-imx6ull.bin

# 提取目录部分：从尾部删掉最短匹配 /*（文件名部分）
echo "${IMAGE_PATH%/*}"
# 预期输出
/home/charlie/build
```

**替换**——`${变量/旧/新}` 替换第一个匹配，`${变量//旧/新}` 替换所有：

```bash
FILE_PATH="/home/user/project/build/output/image.bin"
echo "${FILE_PATH/output/final}"
# 预期输出
/home/user/project/build/final/image.bin
```

这些操作在处理文件路径、版本号、配置项的时候极为实用，后面写编译脚本时我们会大量用到。它们比调用 `basename`、`dirname` 等外部命令快得多——因为是 bash 内建操作，不启动子进程。

### read：让脚本等你说话

到目前为止，脚本里的所有值都是写死的。但有时候你需要在运行时获取用户的输入——比如问用户要编译哪个板子。

`read` 命令从标准输入读取一行，存到变量里：

```bash
#!/bin/bash
echo "Which board to build?"
read BOARD
echo "Building for $BOARD..."
```

```bash
$ ./build.sh
# 预期输出
Which board to build?
imx6ull           ← 用户输入
Building for imx6ull...
```

`read` 有几个常用选项：

```bash
# 带提示符，不用单独 echo
read -p "Board name: " BOARD

# 带超时（秒），超时后继续执行
read -t 10 -p "Board name (10s timeout): " BOARD

# 读取密码，不回显输入
read -s -p "Password: " PASSWD
```

`read` 和管道配合的时候有一个常见的坑：

```bash
# ⚠️ 这样写，ANSWER 拿不到值
echo "yes" | read ANSWER
echo "$ANSWER"    # 输出为空！
```

原因是管道会在子 Shell 中执行 `read`，变量赋值在子 Shell 里完成后就丢了——当前 Shell 里 `ANSWER` 仍然是空的。这个坑我们到 Ch28 函数那一章再展开解决方案，这里先记住它的存在。

---

## 实践层

### 4.1 写第一个脚本

从零开始，写一个真正能跑的脚本。

```bash
# 创建工作目录
$ mkdir -p ~/scripts
$ cd ~/scripts
$ vim hello.sh
```

在 vim 里输入以下内容：

```bash
#!/bin/bash
# 我的第一个 Shell 脚本
echo "Hello from shell script!"
echo "Current user: $USER"
echo "Current directory: $(pwd)"
echo "Script location: $0"
echo "Today is: $(date +%Y-%m-%d)"
```

保存退出（`:wq`），然后给它加上可执行权限：

```bash
$ chmod +x hello.sh
```

没有 `chmod +x` 这一步，系统会拒绝执行——哪怕文件内容完全正确。这是 Linux 权限模型的一部分：一个文件能不能被执行，取决于它有没有执行权限位（`x`），和后缀名无关。`.sh` 后缀只是给人看的约定，对系统没有任何意义。

```bash
$ ./hello.sh
# 预期输出
Hello from shell script!
Current user: charlie
Current directory: /home/charlie/scripts
Script location: ./hello.sh
Today is: 2026-06-11
```

成功了。但先别急着往下走——注意 `$0` 输出的是 `./hello.sh`，也就是你运行脚本时写的那条命令本身。换一种方式运行，`$0` 就变：

```bash
$ bash hello.sh         # $0 = hello.sh
$ ~/scripts/hello.sh    # $0 = /home/charlie/scripts/hello.sh
```

`$0` 不是脚本文件的绝对路径，而是你「怎么调用它」的原始字符串。

还有一种运行方式需要特别提一下：

```bash
$ source hello.sh
# 或者
$ . hello.sh
```

`source`（或 `.`）不会启动新的 bash 进程，而是**在当前 Shell 里直接执行**脚本内容。这意味着脚本里的变量赋值、环境变量设置会直接影响你的当前终端。这也是为什么我们安装交叉编译工具链后总要 `source env.sh`——那些 `export` 需要在当前 Shell 生效，不能在子 Shell 里设完就丢。

### 4.2 用变量写一个编译配置

把变量用起来，写一个稍微有实际意义的脚本。

```bash
#!/bin/bash
# build_config.sh —— 编译配置管理

# ===== 项目配置 =====
PROJECT="imx-forge"
BOARD="imx6ull"
KERNEL_VERSION="5.15.32"
TOOLCHAIN_PREFIX="arm-linux-gnueabihf-"
JOBS=$(nproc)                          # 自动获取 CPU 核心数

# ===== 路径配置 =====
BASE_DIR="$HOME/projects/$PROJECT"
BUILD_DIR="$BASE_DIR/build"
OUTPUT_DIR="$BASE_DIR/output/${BOARD}"

# ===== 打印配置信息 =====
echo "===== Build Configuration ====="
echo "Project:    $PROJECT"
echo "Board:      $BOARD"
echo "Kernel:     $KERNEL_VERSION"
echo "Toolchain:  $TOOLCHAIN_PREFIX"
echo "Jobs:       $JOBS"
echo "Build dir:  $BUILD_DIR"
echo "Output dir: $OUTPUT_DIR"
echo "==============================="
```

注意 `JOBS=$(nproc)` 这行。`$()` 是**命令替换**——bash 先执行 `nproc`（输出 CPU 核心数），然后把结果赋给 `JOBS`。这比写死 `JOBS=4` 灵活得多——换个机器不用改脚本。

```bash
$ chmod +x build_config.sh && ./build_config.sh
# 预期输出
===== Build Configuration =====
Project:    imx-forge
Board:      imx6ull
Kernel:     5.15.32
Toolchain:  arm-linux-gnueabihf-
Jobs:       8
Build dir:  /home/charlie/projects/imx-forge/build
Output dir: /home/charlie/projects/imx-forge/output/imx6ull
===============================
```

如果想让用户自己选板子，加一个 `read` 和「默认值」语法：

```bash
#!/bin/bash
# build_config_interactive.sh —— 交互式编译配置

DEFAULT_BOARD="imx6ull"
read -p "Target board [$DEFAULT_BOARD]: " BOARD
BOARD="${BOARD:-$DEFAULT_BOARD}"    # 用户直接回车则使用默认值

echo "Building for: $BOARD"
```

`${变量:-默认值}` 是 Shell 的「默认值语法」——如果 `BOARD` 为空（用户直接按了回车），就用 `$DEFAULT_BOARD`。这个小技巧在脚本里用得非常多。

### 4.3 字符串操作实战

编译嵌入式系统时，处理版本号和文件路径是家常便饭。

```bash
#!/bin/bash
# string_demo.sh —— 字符串操作实战

# 场景 1：从 git tag 中提取版本号
GIT_TAG="rel-v5.15.32-stable"
VERSION="${GIT_TAG#rel-}"              # 去掉 "rel-" 前缀
echo "Version: $VERSION"
# 预期输出：Version: v5.15.32-stable

CLEAN_VERSION="${VERSION%-stable}"      # 去掉 "-stable" 后缀
echo "Clean version: $CLEAN_VERSION"
# 预期输出：Clean version: v5.15.32

# 场景 2：从完整路径提取文件名和目录
IMAGE_PATH="/home/charlie/build/zImage-imx6ull.bin"
FILENAME="${IMAGE_PATH##*/}"           # 删掉最长前缀 */（所有目录部分）
DIRNAME="${IMAGE_PATH%/*}"             # 删掉最短后缀 /*（文件名部分）
echo "Filename: $FILENAME"
echo "Directory: $DIRNAME"
# 预期输出：
# Filename: zImage-imx6ull.bin
# Directory: /home/charlie/build

# 场景 3：替换文件扩展名
BACKUP_NAME="${FILENAME/.bin/.bin.bak}"
echo "Backup name: $BACKUP_NAME"
# 预期输出：Backup name: zImage-imx6ull.bin.bak
```

这里用到了 `#`、`%`、`//` 三种模式匹配语法。整理一下：

| 语法 | 方向 | 匹配长度 | 用途举例 |
|------|------|----------|----------|
| `${var#pattern}` | 头部 | 最短 | 去前缀 |
| `${var##pattern}` | 头部 | 最长 | 提取文件名 |
| `${var%pattern}` | 尾部 | 最短 | 去后缀、提取目录 |
| `${var%%pattern}` | 尾部 | 最长 | 去所有层级后缀 |
| `${var/old/new}` | — | 第一个 | 替换扩展名 |
| `${var//old/new}` | — | 所有 | 全局替换 |

不用刻意背。写几个脚本之后，这些语法自然会记住。

---

## 练习题

走到这里，基本语法应该清楚了——或者你以为清楚了。下面几道题难度递进，建议先不看提示独立做，卡住了再翻。

**练习 26.1** ⭐（理解）

写出下面脚本的输出：

```bash
#!/bin/bash
A="hello"
B='$A world'
C="$A world"
echo "$B"
echo "$C"
```

> **提示**：回顾单引号和双引号对变量替换的区别。

**练习 26.2** ⭐⭐（应用）

写一个脚本 `info.sh`，运行时接收两个参数：用户名和项目名。脚本应该：
- 如果参数不够两个，打印用法提示并退出
- 参数齐全时，输出类似以下格式的信息：

```
User: charlie | Project: imx-forge | Home: /home/charlie | Cores: 8
```

> **提示**：`$#` 可以判断参数数量，`$HOME` 是当前用户的家目录。

**练习 26.3** ⭐⭐⭐（思考）

下面这段脚本的本意是：让用户输入一个路径，然后判断这个路径是否存在。但它在某些情况下会表现异常——什么情况？

```bash
#!/bin/bash
read -p "Enter a path: " PATH
if [ -e "$PATH" ]; then
    echo "Exists: $PATH"
else
    echo "Not found: $PATH"
fi
```

> **提示**：变量名叫 `PATH`。想想 Shell 里的 `PATH` 环境变量是干什么的。

---

## 练习参考答案

**练习 26.1**

```
$A world
hello world
```

`$B` 用单引号赋值，`$A` 不会被替换；`$C` 用双引号赋值，`$A` 被替换成 `hello`。

**练习 26.2**

```bash
#!/bin/bash
if [ $# -lt 2 ]; then
    echo "Usage: $0 <username> <project>"
    exit 1
fi
USER_NAME="$1"
PROJECT="$2"
echo "User: $USER_NAME | Project: $PROJECT | Home: $HOME | Cores: $(nproc)"
```

**练习 26.3**

变量名用了 `PATH`——覆盖了系统的 `PATH` 环境变量。赋值之后，Shell 就找不到 `ls`、`grep` 等外部命令了（除非用户输入的路径恰好包含了 `/usr/bin` 之类的系统目录）。自定义变量**不要和环境变量重名**，这是 Shell 脚本里最基本的命名规则之一。

---

## 本章回响

这一章表面上在讲 Shell 脚本的基础语法——变量、字符串、输入输出。但真正要建立的核心认知是：**Shell 脚本不是一门独立的编程语言，它是终端会话的自动化**。每一个语法特性——等号两边不能有空格、`$` 取值、单双引号行为不同——都是因为 bash 用同一套解析器处理交互式命令和脚本文件。

回到那张「剧本」——bash 是演员，你写的脚本是台词。现在你应该能理解为什么这个演员有时候看起来很笨了：它不是按照剧本优雅地表演，而是一行一行地、看到 `$` 就去查值、看到命令就执行、看到变量就替换。这种逐行解释的方式，正是它和终端共享同一条脐带的代价。但好处也很明显：你在终端里能用的所有东西，脚本里全能用，一个不少。

不过，到目前为止我们的脚本还是线性的——从第一行跑到最后一行，不拐弯。现实中的编译过程不是这样的：编译失败了要不要继续？哪个文件改了才需要重新编译？这些问题需要脚本做判断和循环。

下一章我们就来给脚本装上「大脑」——if 判断、for 循环、case 分支。届时你会发现，Shell 的流程控制和 C 语言长得很像，但那些微妙的差异，每一个都可能让你 debug 到半夜。

---

[← 上一章](../05-network/ch25-firewall.md)
[下一章 →](ch27-flow.md)
