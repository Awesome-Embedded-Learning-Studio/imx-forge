# 第 27 章  流程控制

> **Part: Part 6 · 脚本与自动化**

---

## 引子

脚本现在是线性的：从第一行执行到最后一行，中间不拐弯。

但现实不是线性的。你需要判断编译是否成功再决定下一步；你需要对目录下每一个 `.c` 文件做同样的操作；你需要不断重试直到网络恢复。

if/else 做判断，for/while 做循环，case 做多分支——流程控制让脚本从「播放录像」变成「真正的程序」。

语法和 C 语言很像。**但「很像」是这里最危险的两个字。**

Shell 的 `if` 不用圆括号，用方括号——而且方括号还有两种，行为不一样。`for` 循环的写法有三种，每一种的适用场景都不同。`=` 在 `if` 里不是赋值，是比较字符串——而在 `(( ))` 里又变成了数学比较。这些差异看起来是细节，但每一个都能让你 debug 到半夜。

这种相似性就像在异国开车：路标长得一样，`if`、`for`、`while`、`case` 都在那儿，但有些规则的细节变了。你只有在犯错的时候才发现。

---

## 背景与动机

上一章我们写的 `build_config.sh` 有一个明显的局限：它只能做一件事——打印配置。实际的编译过程不是这样的。

编译可能失败。你需要检查上一条命令的退出码，成功了才继续，失败了就停下来报错——这是 `if` 的活。

有时候你需要编译好几个板子的镜像——imx6ull、imx8mm、imx8mp，一个脚本跑完所有板子——这是 `for` 的活。

有时候你需要让用户选择编译模式——debug 还是 release，完整编译还是增量编译——这是 `case` 的活。

这些场景在嵌入式开发中几乎天天遇到。流程控制不是理论，是你写完第一个真正有用的脚本就必须用到的工具。

---

## 概念层

### 条件判断：`if` 和它的方括号

Shell 的 `if` 长这样：

```bash
if [ 条件 ]; then
    # 条件为真时执行
elif [ 另一个条件 ]; then
    # 另一个条件为真时执行
else
    # 以上都不满足时执行
fi
```

`fi` 是 `if` 倒过来写——Shell 用这种方式标记块的结束。后面你还会看到 `case` 用 `esac`（`case` 倒过来）、`do...done` 配对出现。

来看一个实际例子——检查编译是否成功：

```bash
#!/bin/bash
make
if [ $? -eq 0 ]; then
    echo "Build succeeded!"
else
    echo "Build failed with exit code $?"
fi
```

等等——这个脚本有一个 bug。

`$?` 只保存**上一条命令**的退出码。在 `else` 分支里，上一条命令已经不是 `make` 了，而是 `[ $? -eq 0 ]` 这个 `test` 命令本身。所以 `$?` 的值已经不是 `make` 的退出码了。

正确的写法是先存下来：

```bash
#!/bin/bash
make
RET=$?
if [ $RET -eq 0 ]; then
    echo "Build succeeded!"
else
    echo "Build failed with exit code $RET"
fi
```

这种「`$?` 只能用一次」的陷阱，在脚本里出现的频率高得离谱。

#### `[ ]` vs `[[ ]]`——方括号里的暗战

Shell 有两种方括号：`[ ]` 和 `[[ ]]`。它们看起来差不多，行为差别很大。

`[ ]` 是 POSIX 标准的写法，本质上是调用 `test` 命令。是的，`[` 就是一个命令——你甚至可以 `man [` 来查它的手册。因为它是一个普通命令，变量替换发生在命令执行之前。如果变量为空，会出大事：

```bash
X=""
if [ $X = "hello" ]; then
    echo "equal"
fi
# 报错：bash: [: =: unary operator expected
```

`$X` 为空时，`[ $X = "hello" ]` 展开成 `[ = "hello" ]`——`[` 命令只收到两个参数，它期待三个（左值 操作符 右值），所以语法错误。

解决方案是在 `[ ]` 里给变量加双引号：`[ "$X" = "hello" ]`。这样即使 `$X` 为空，展开后也是 `[ "" = "hello" ]`，三个参数齐全。

`[[ ]]` 是 bash 的扩展语法，没有这个问题：

```bash
X=""
if [[ $X = "hello" ]]; then    # 即使 $X 为空也不会报错
    echo "equal"
fi
```

回到那个「异国路标」——`[ ]` 和 `[[ ]]` 就是最典型的例子。它们看起来一模一样，但一个遇到变量为空的情况会直接短路报错，另一个不会。这种差异在 C 语言里不存在——C 的 `if` 不需要你操心「变量为空」这回事，因为 C 的变量总是有类型的。

`[[ ]]` 的优势不止于此：

| 特性 | `[ ]` | `[[ ]]` |
|------|-------|---------|
| 变量为空时需要加引号 | 是 | 否 |
| 逻辑运算 | `-a`（且）`-o`（或） | `&&` `||` |
| 模式匹配 `== pattern*` | 否 | 是 |
| 正则匹配 `=~` | 否 | 是 |
| POSIX 兼容 | 是 | 否（bash 扩展） |

> ⚠️ **注意**
> 如果你的脚本 shebang 写的是 `#!/bin/sh`，就不能用 `[[ ]]`——它在 dash 里不存在。在 Ubuntu 上，`#!/bin/sh` 跑的是 dash，不是 bash。所以前面 Ch26 反复强调的 shebang 写法，在这里直接影响了你能用什么语法。

在 bash 脚本里（shebang 是 `#!/bin/bash`），**推荐统一用 `[[ ]]`**——更安全、更强大。但如果你需要 POSIX 兼容性，就必须用 `[ ]`，而且记得给所有变量加双引号。

#### `[ ]` 里的常用条件

不管用 `[ ]` 还是 `[[ ]]`，判断条件本身是一样的。这里列出最常用的：

**数值比较**（注意：这些操作符在 `[ ]` 里用于整数）：

| 操作符 | 含义 |
|--------|------|
| `-eq` | 等于 |
| `-ne` | 不等于 |
| `-gt` | 大于 |
| `-lt` | 小于 |
| `-ge` | 大于等于 |
| `-le` | 小于等于 |

**字符串比较**：

| 操作符 | 含义 |
|--------|------|
| `=` | 字符串相等 |
| `!=` | 字符串不等 |
| `-z "$VAR"` | 字符串为空 |
| `-n "$VAR"` | 字符串非空 |

**文件判断**：

| 操作符 | 含义 |
|--------|------|
| `-e "$FILE"` | 文件/目录存在 |
| `-f "$FILE"` | 是普通文件 |
| `-d "$FILE"` | 是目录 |
| `-s "$FILE"` | 文件存在且非空 |

文件判断在编译脚本里用得非常多——检查输出文件是否生成、检查配置文件是否存在、检查目录是否就绪。

### 循环：`for`、`while`、`until`

#### for 循环——三种写法

**列表形式**——遍历一个空格分隔的列表：

```bash
for board in imx6ull imx8mm imx8mp; do
    echo "Building for $board..."
done
```

**命令替换形式**——遍历一个命令的输出：

```bash
for file in $(ls *.c); do
    gcc -c "$file"
done
```

这里有一个严重的陷阱。

`$(ls *.c)` 会按空格分割输出——如果文件名包含空格，一个文件名会被拆成多个。安全的写法是直接用 glob：

```bash
for file in *.c; do
    [[ -f "$file" ]] || continue    # 跳过非文件（如果没有 .c 文件，* 不会被展开）
    gcc -c "$file"
done
```

Shell 的 glob 模式 `*.c` 会正确处理包含空格的文件名，每个匹配结果是一个整体。而 `$(ls)` 会把输出当成纯文本按 `IFS`（Internal Field Separator，默认是空格/制表符/换行）切割。这个区别在处理真实文件时至关重要——嵌入式项目里的文件名很少带空格，但日志文件、用户输入的路径，这些都可能包含空格。

**C 风格形式**——用 `(( ))` 做数值循环：

```bash
for ((i=0; i<5; i++)); do
    echo "Pass $i"
done
# 预期输出
Pass 0
Pass 1
Pass 2
Pass 3
Pass 4
```

这种形式在做计数循环时最自然——批量生成配置文件、给镜像加版本号、迭代固定次数的重试。

#### while 和 until

`while` 在条件为真时反复执行：

```bash
# 等待设备节点出现（插上开发板时有用）
while [[ ! -e /dev/ttyUSB0 ]]; do
    echo "Waiting for device..."
    sleep 1
done
echo "Device found!"
```

`until` 正好相反——条件为假时反复执行，等条件变真才停：

```bash
# 重试直到网络通
until ping -c 1 192.168.1.1 &>/dev/null; do
    echo "Network not ready, retrying..."
    sleep 2
done
echo "Network is up!"
```

`while` 和 `until` 是同一件事的两种表述。选哪个取决于你怎样描述条件更自然——「当……时继续」用 `while`，「直到……为止」用 `until`。

### `(( ))` —— 算术运算

Shell 默认把所有变量当字符串。要做数学运算，需要用 `(( ))`：

```bash
COUNT=0
((COUNT++))            # 自增
echo "$COUNT"           # 1

((COUNT = COUNT * 2))  # 乘法
echo "$COUNT"           # 2
```

`(( ))` 内部不需要 `$` 前缀来取变量值——bash 知道里面的东西是数字运算：

```bash
TOTAL=10
ITEMS=3
((REMAINING = TOTAL - ITEMS))
echo "$REMAINING"       # 7
```

`(( ))` 也可以直接用在 `if` 里做数值比较，比 `[ ]` 里的 `-gt`、`-lt` 自然得多：

```bash
JOBS=$(nproc)
if ((JOBS > 4)); then
    echo "More than 4 cores, using parallel build"
fi
```

在 `(( ))` 里，比较运算符是 `>`、`<`、`>=`、`<=`、`==`、`!=`——数学符号。而在 `[ ]` 里，`>` 是重定向符，根本不能用来比较数字。这种「同一个符号在不同上下文中含义完全不同」的情况，正是 Shell 语法被吐槽的核心原因。

### case：多分支选择

当分支多于两个，`if/elif/else` 会变得又长又丑。`case` 是更好的选择：

```bash
#!/bin/bash
read -p "Build mode (debug/release): " MODE
case "$MODE" in
    debug)
        echo "Debug build enabled"
        export DEBUG=1
        ;;
    release)
        echo "Release build"
        export DEBUG=0
        ;;
    *)
        echo "Unknown mode: $MODE"
        exit 1
        ;;
esac
```

`case` 的匹配支持通配符——`*` 匹配任意字符串，`?` 匹配单个字符，`[abc]` 匹配字符集。这在处理板子型号时特别好用：

```bash
case "$BOARD" in
    imx6*)
        echo "i.MX6 series detected"
        ;;
    imx8m*)
        echo "i.MX8M series detected"
        ;;
    *)
        echo "Unsupported board: $BOARD"
        exit 1
        ;;
esac
```

注意每个分支末尾的 `;;`——它和 C 语言 `switch/case` 里的 `break` 类似，表示这个分支结束。漏掉 `;;` 会直接报语法错误，不像 C 语言忘了 `break` 会 fall-through。

### break 和 continue

和 C 语言一样，`break` 跳出循环，`continue` 跳过本次迭代：

```bash
for board in imx6ull imx8mm unknown imx8mp; do
    # 跳过不支持的板子
    case "$board" in
        unknown)
            echo "Skipping $board (unsupported)"
            continue
            ;;
    esac

    echo "Building $board..."
    # 编译逻辑...
done
```

---

## 实践层

### 4.1 智能编译脚本

把上一章的 `build_config.sh` 升级——加入流程控制，让它能判断编译是否成功、检查参数合法性。

```bash
#!/bin/bash
# smart_build.sh —— 带流程控制的编译脚本

BOARD="$1"
JOBS=$(nproc)

# ===== 参数检查 =====
if [[ -z "$BOARD" ]]; then
    echo "Usage: $0 <board_name>"
    echo "Supported: imx6ull, imx8mm, imx8mp"
    exit 1
fi

# ===== 板子合法性检查 =====
case "$BOARD" in
    imx6ull|imx8mm|imx8mp)
        echo "Target: $BOARD"
        ;;
    *)
        echo "Error: Unsupported board '$BOARD'"
        exit 1
        ;;
esac

# ===== 编译 =====
echo "Compiling with $JOBS parallel jobs..."
make -j"$JOBS" 2>&1 | tee build.log
BUILD_RESULT=${PIPESTATUS[0]}

if ((BUILD_RESULT == 0)); then
    echo "Build succeeded. Log saved to build.log"
else
    echo "Build failed (exit code: $BUILD_RESULT)"
    echo "Check build.log for details"
    exit "$BUILD_RESULT"
fi
```

这里出现了两个新东西。

`${PIPESTATUS[0]}`——管道中第一个命令（`make`）的退出码。如果用 `$?`，拿到的是 `tee` 的退出码，而 `tee` 几乎永远成功。这是管道中获取特定命令退出码的标准方式。

`2>&1 | tee build.log`——把标准错误合并到标准输出，然后通过管道传给 `tee`。`tee` 的作用是「数据流的三通管」：数据既显示在屏幕上，又写入文件。这是 Ch14（重定向与管道）里的知识。

```bash
$ ./smart_build.sh imx6ull
# 预期输出
Target: imx6ull
Compiling with 8 parallel jobs...
[编译输出...]
Build succeeded. Log saved to build.log
```

### 4.2 批量编译

如果想让一个脚本编译所有支持的板子：

```bash
#!/bin/bash
# batch_build.sh —— 批量编译多个板子

BOARDS=("imx6ull" "imx8mm" "imx8mp")
FAILED=()

for board in "${BOARDS[@]}"; do
    echo "==============================="
    echo "Building for $board..."
    echo "==============================="

    make clean &>/dev/null
    make "BOARD=$board" -j"$(nproc)"

    if (($? != 0)); then
        echo "Failed to build $board"
        FAILED+=("$board")
        continue    # 编译失败，跳到下一个板子
    fi

    echo "$board build succeeded"
done

# ===== 汇总结果 =====
if (( ${#FAILED[@]} == 0 )); then
    echo "All boards built successfully!"
else
    echo "Failed boards: ${FAILED[*]}"
    exit 1
fi
```

这里用到了 **bash 数组**——`BOARDS=("imx6ull" "imx8mm" "imx8mp")`。数组在 Ch26 没有专门讲，因为它属于 bash 扩展特性。简单说：

- `arr=("a" "b" "c")` —— 定义数组
- `"${arr[@]}"` —— 展开为每个元素独立的双引号字符串（遍历时必须用这个）
- `${#arr[@]}` —— 数组元素个数
- `arr+=("new")` —— 追加元素

注意 `"${BOARDS[@]}"` 外面的双引号——没有它，数组元素会按 IFS 再次分割，包含空格的元素会被拆开。这和前面说的 `for f in *` vs `for f in $(ls)` 是同一个问题。

### 4.3 等待设备连接

来一个 `while` 的实用场景——等待开发板通过 USB 串口连接：

```bash
#!/bin/bash
# wait_device.sh —— 等待串口设备出现

DEVICE="/dev/ttyUSB0"
TIMEOUT=30
ELAPSED=0

echo "Waiting for $DEVICE ..."
while [[ ! -e "$DEVICE" ]]; do
    sleep 1
    ((ELAPSED++))
    if ((ELAPSED >= TIMEOUT)); then
        echo "Timeout after ${TIMEOUT}s. Device not found."
        exit 1
    fi
    printf "\rElapsed: %ds" "$ELAPSED"
done

echo ""
echo "Device $DEVICE is ready!"
```

这段脚本每秒检查一次设备节点是否存在，超过 30 秒就放弃。在嵌入式开发中，这种「等待硬件就绪」的逻辑非常常见——插上开发板、等待 USB 枚举、然后才能开始烧录。

---

## 练习题

流程控制的语法不复杂，但组合起来容易出 bug。下面三道题递进式考察。

**练习 27.1** ⭐（理解）

下面这个脚本的输出是什么？

```bash
#!/bin/bash
X=""
if [ $X = "hello" ]; then
    echo "yes"
else
    echo "no"
fi
```

> **提示**：手动展开一下 `[ $X = "hello" ]`，看看实际传给 `[` 命令的参数是什么。

**练习 27.2** ⭐⭐（应用）

写一个脚本，接收一个目录路径作为参数，统计该目录下 `.c` 文件、`.h` 文件和其他文件各有多少个。要求：
- 如果没有传参数，提示用法并退出
- 如果传的路径不存在，报错并退出
- 用 `for` 循环遍历，`case` 判断文件类型

> **提示**：文件扩展名可以用 `${file##*.}` 提取。

**练习 27.3** ⭐⭐⭐（思考）

下面两段代码功能看起来一样，但在某些情况下行为不同——什么情况下？

```bash
# 版本 A
for f in $(ls); do
    echo "$f"
done

# 版本 B
for f in *; do
    echo "$f"
done
```

> **提示**：创建一个名字包含空格的文件试试。想想 `$(ls)` 和 `*` 在处理方式上的本质区别。

---

## 练习参考答案

**练习 27.1**

会报错：`bash: [: =: unary operator expected`。

`$X` 为空时，`[ $X = "hello" ]` 展开为 `[ = "hello" ]`——`[` 命令只收到两个参数，缺少左操作数。修正方法：`[ "$X" = "hello" ]`（加双引号）或改用 `[[ $X = "hello" ]]`。

**练习 27.2**

```bash
#!/bin/bash
if [[ -z "$1" ]]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

if [[ ! -d "$1" ]]; then
    echo "Error: '$1' is not a directory"
    exit 1
fi

C_COUNT=0
H_COUNT=0
OTHER=0

for f in "$1"/*; do
    [[ -f "$f" ]] || continue       # 跳过子目录等非文件
    EXT="${f##*.}"
    case "$EXT" in
        c)   ((C_COUNT++)) ;;
        h)   ((H_COUNT++)) ;;
        *)   ((OTHER++))   ;;
    esac
done

echo "C files: $C_COUNT"
echo "H files: $H_COUNT"
echo "Other files: $OTHER"
```

**练习 27.3**

当文件名包含空格时，版本 A 会把一个文件名拆成多个。例如，如果有文件 `my file.c`：

- 版本 A（`$(ls)`）：`f` 先等于 `my`，再等于 `file.c`——一个文件被拆成了两轮迭代
- 版本 B（`*`）：`f` 等于 `my file.c`——一个文件就是一轮迭代

根本原因：`$(ls)` 把输出当纯文本，按 `IFS` 分割；`*` 是 bash 原生的 glob 展开，每个匹配结果是一个独立单元，不受 `IFS` 影响。在处理文件名时，**永远用 glob 而不是 `$(ls)`**。

---

## 本章回响

这一章的核心认知是：**Shell 的流程控制语法和 C 语言「长得很像但不是同一个东西」**。每一个差异——`[ ]` 和 `[[ ]]` 的行为分歧、`=` 在不同上下文的意思变化、`$?` 只能用一次——都是 bash「既是命令行又是脚本语言」这个双重身份的产物。

回到那些「异国路标」——你现在应该知道了，每一个看起来和 C 语言一样的语法符号，背后可能藏着不同的规则。最危险的恰恰是最像的那些：`[ $X = "hello" ]` 在变量非空的时候完全正常，一旦变量为空就炸。这种「平时没问题、特定输入才炸」的 bug 是最难调的，因为它在你手动测试的时候大概率不会出现。

不过，到目前为止我们的脚本还有一个局限：所有逻辑都平铺在一个文件里。编译检查是一段代码，日志处理是一段代码，打包又是一段代码——其中有三处都在做「检查目录是否存在、不存在就创建」这个操作，复制粘贴了三次。

下一章我们来解决这个问题——用函数把重复逻辑封装起来。同时我们会把 Ch26 和 Ch27 学的所有东西整合成一个真正的一键编译脚本：检查环境 → 清理 → 编译 → 打包，一条命令搞定。

---

[← 上一章](ch26-bash-basic.md)
[下一章 →](ch28-function.md)
