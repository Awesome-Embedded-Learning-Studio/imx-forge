# 第 28 章  函数与实战案例

> **Part 6 · 脚本与自动化**

---

## 引子

脚本写了两百行，你发现其中有三段代码几乎一模一样——只是参数不同。复制粘贴能解决，但改一处就得改三处。

函数是脚本的「压缩器」：把重复逻辑封装起来，一个名字代替十行代码。调用时传参，内部有局部变量，还可以返回结果——和 C 语言的函数概念基本一致，只是写法更简陋。

但「基本一致」四个字又出现了。Shell 函数没有参数列表，参数通过 `$1` `$2` 传入。返回值只能是 0-255 的整数，想返回字符串得绕路。变量默认全是全局的——不加 `local`，你在函数里赋的值会泄露到外面。这三点和 C 语言完全不同。

这章我们把函数学明白，然后用它组装一个实战项目——一键编译脚本。从环境检查到编译打包，一条命令搞定。

---

## 背景与动机

回顾 Ch27 的 `batch_build.sh`——那个批量编译脚本里，「检查目录是否存在、不存在就创建」这个操作出现了两次，「打印错误信息并退出」出现了三次。如果以后还要加新的编译步骤，这些重复代码会越来越多。

这不是审美问题，是维护问题。某天你决定把错误信息格式从 `[ERROR]` 改成 `✗`——如果复制粘贴了十处，你得改十遍，漏一处就不一致。

函数解决的就是这个问题：定义一次，到处调用。改一处，所有调用点都跟着变。

在嵌入式开发中，函数的典型使用场景包括：

- 封装编译步骤（clean → configure → build → package）
- 封装环境检查（工具链是否存在、依赖是否安装）
- 封装日志输出（带时间戳、带颜色、写文件）

---

## 概念层

### 函数定义与调用

Shell 函数的定义非常简单：

```bash
# 语法一（最常用）
function_name() {
    # 函数体
    commands
}

# 语法二（带 function 关键字，效果一样）
function function_name() {
    commands
}
```

调用函数就像调用命令一样——直接写函数名：

```bash
#!/bin/bash
# 定义
greet() {
    echo "Hello, $1!"
}

# 调用
greet "world"
greet "Shell scripting"
# 预期输出
Hello, world!
Hello, Shell scripting!
```

函数必须**先定义后调用**——bash 是从上到下逐行解析的，这一点和 C 语言不同（C 语言有函数声明）。如果把调用写在定义前面，bash 会报 `command not found`。

### 参数传递——没有参数列表的函数

Shell 函数没有参数列表。调用时传的参数，在函数内部通过 `$1`、`$2`、`$#`、`$@` 等特殊变量获取——和脚本接收命令行参数的机制完全一样。

```bash
#!/bin/bash
check_dir() {
    local dir="$1"        # 第一个参数
    local desc="$2"       # 第二个参数

    if [[ ! -d "$dir" ]]; then
        echo "[INFO] $desc not found, creating: $dir"
        mkdir -p "$dir"
    else
        echo "[OK] $desc exists: $dir"
    fi
}

# 调用——每次传不同的参数
check_dir "$HOME/build" "Build directory"
check_dir "$HOME/output" "Output directory"
check_dir "$HOME/logs"   "Log directory"
# 预期输出
[OK] Build directory exists: /home/charlie/build
[INFO] Output directory not found, creating: /home/charlie/output
[INFO] Log directory not found, creating: /home/charlie/logs
```

三段重复的「检查目录」代码，现在变成了一处定义、三次调用。这就是「压缩」。

但关于「压缩器」这个比喻，有一个地方需要澄清。真正的压缩器是**无损**的——解压后和压缩前完全一样。Shell 函数的「压缩」是**有损**的：

- 你无法在函数签名里看到它需要几个参数、每个参数是什么类型
- 你无法通过函数名看出它返回什么（是退出码？还是 echo 的字符串？）
- 如果函数内部忘了加 `local`，变量会「泄漏」到调用者的作用域

这些信息在 C 语言里是编译器帮你检查的——函数签名明确告诉你参数类型和返回值类型。Shell 函数的「压缩」更像是用橡皮筋捆一捆文件——管用，但不精致。你多出来的自由需要用自律来弥补：给函数加注释，说清楚参数和返回值。

### 返回值——0 到 255 的天花板

Shell 函数的 `return` 只能返回 0-255 的整数退出码：

```bash
is_file_empty() {
    local file="$1"
    if [[ ! -s "$file" ]]; then
        return 0    # 文件为空或不存在，返回「真」
    else
        return 1    # 文件非空，返回「假」
    fi
}

# 使用——函数可以直接放在 if 条件里
if is_file_empty "/tmp/test.txt"; then
    echo "File is empty or missing"
fi
```

这种模式适合做布尔判断。但如果想返回一个字符串——比如获取编译输出文件的路径——`return` 做不到。

标准的替代方案是 `echo` + 命令替换：

```bash
get_image_path() {
    local board="$1"
    local base="/opt/build/output"
    echo "$base/${board}/zImage"
}

# 用 $(...) 捕获 echo 的输出
IMAGE=$(get_image_path "imx6ull")
echo "Image: $IMAGE"
# 预期输出
Image: /opt/build/output/imx6ull/zImage
```

这里有一个性能问题：`$(...)` 会创建一个子 Shell。在循环里大量使用会有可测量的开销。对于绝大多数脚本这不是问题，但如果你在一个循环里调用几千次，需要注意。

另外一个陷阱：如果你的函数里既有 `echo` 输出调试信息，又用 `echo` 返回值，它们会混在一起被 `$(...)` 全部捕获。解决方法是让调试信息走 stderr：

```bash
debug() {
    echo "[DEBUG] $*" >&2    # 重定向到 stderr
}

get_image_path() {
    local board="$1"
    debug "Looking for image of $board"    # debug 输出到 stderr
    echo "/opt/output/$board/zImage"       # 返回值走 stdout
}

# $(...) 只捕获 stdout，stderr 直接显示在终端
IMAGE=$(get_image_path "imx6ull")
# 预期终端输出
[DEBUG] Looking for image of imx6ull    ← stderr，直接显示
# $IMAGE 的值
echo "$IMAGE"
# 预期输出
/opt/output/imx6ull/zImage              ← 被 $(...) 捕获
```

stdout 和 stderr 的分流，是 Ch14（重定向与管道）里建立的知识。在函数里，stdout 留给返回值，stderr 留给日志——这是一个很实用的约定。

### `local`——作用域的防火墙

Shell 函数里的变量**默认是全局的**。这一点和 C 语言完全不同：

```bash
#!/bin/bash
dangerous_func() {
    RESULT="modified inside function"    # 没有 local，这是全局变量！
}

RESULT="original"
echo "Before: $RESULT"
dangerous_func
echo "After: $RESULT"
# 预期输出
Before: original
After: modified inside function
```

`RESULT` 被函数内部修改了——因为 Shell 的变量默认没有作用域隔离。加上 `local` 就好了：

```bash
safe_func() {
    local RESULT="modified inside function"    # local 限制在函数内部
}

RESULT="original"
safe_func
echo "After: $RESULT"
# 预期输出
After: original
```

`local` 的行为是：在当前函数内创建一个同名变量，屏蔽外部的全局变量。函数返回后，局部变量消失，全局变量恢复原值。

在嵌套函数中，`local` 变量是否隔离？是的——每一层函数都可以有自己的 `local`：

```bash
#!/bin/bash
outer() {
    local X="outer"
    echo "outer: X=$X"
    inner
    echo "outer after inner: X=$X"
}

inner() {
    local X="inner"
    echo "inner: X=$X"
}

X="global"
outer
echo "global: X=$X"
# 预期输出
outer: X=outer
inner: X=inner
outer after inner: X=outer
global: X=global
```

每一层的 `local X` 都是独立的。内层修改不影响外层。但如果不加 `local`——内层直接修改的就是外层的变量。

> ⚠️ **注意**
> Shell 函数里的每一个变量，除非你有明确的理由让它全局可见，否则**一律加 `local`**。这不是建议，是规则。不加 `local` 的变量会像幽灵一样在脚本里飘来飘去，制造你永远找不到原因的 bug。

### source：引入外部脚本

当脚本越来越长，把函数拆到单独的文件里是自然的做法。`source`（或 `.`）命令可以在当前 Shell 中执行另一个脚本——不是启动子进程，而是直接在当前环境里运行：

```bash
# lib.sh —— 公共函数库
log_info() {
    echo "[INFO] $(date '+%H:%M:%S') $*"
}

log_error() {
    echo "[ERROR] $(date '+%H:%M:%S') $*" >&2
}

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required tool not found: $1"
        return 1
    fi
    log_info "Found: $1"
}
```

```bash
#!/bin/bash
# main.sh —— 主脚本

source ./lib.sh    # 引入函数库

log_info "Starting build..."
check_tool "make"
check_tool "arm-linux-gnueabihf-gcc"
```

`source` 和直接运行脚本的区别在于：`source` 不创建子 Shell，所以被引入脚本里的变量、函数定义都会在当前环境中生效。这就是为什么我们在 Ch26 里说 `source env.sh` 能改变当前终端的环境变量——它是在当前 Shell 里直接执行的，不是在子 Shell 里。

---

## 实践层

### 4.1 一键编译脚本——完整版

现在我们把 Ch26、Ch27、Ch28 的所有知识整合到一个脚本里。这个脚本做四件事：**检查编译环境 → 清理旧文件 → 编译 → 打包输出**。

```bash
#!/bin/bash
# one_click_build.sh —— 一键编译脚本
# 整合 Ch26-28 所有知识

set -e            # 任何命令失败立即退出
set -o pipefail   # 管道中任一命令失败，整个管道算失败

# ==========================================
# 函数定义区
# ==========================================

# ----- 日志函数 -----
log_info()  { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_ok()    { echo "[OK] $*"; }

# ----- 检查必要工具是否安装 -----
check_environment() {
    local tools=("make" "gcc" "arm-linux-gnueabihf-gcc")
    local missing=()

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_error "Missing tools: ${missing[*]}"
        log_error "Install: sudo apt install gcc-arm-linux-gnueabihf build-essential"
        return 1
    fi

    log_ok "All tools available"
    log_info "GCC: $(gcc --version | head -1)"
    log_info "Cross: $(arm-linux-gnueabihf-gcc --version | head -1)"
}

# ----- 清理旧编译产物 -----
clean_build() {
    local build_dir="$1"
    log_info "Cleaning: $build_dir"

    if [[ -d "$build_dir" ]]; then
        # ${build_dir:?} 防止变量为空时 rm -rf /*
        rm -rf "${build_dir:?}"/*
        log_ok "Cleaned"
    else
        mkdir -p "$build_dir"
        log_info "Created: $build_dir"
    fi
}

# ----- 执行编译 -----
do_build() {
    local board="$1"
    local jobs="$2"
    local build_dir="$3"

    log_info "Building $board with $jobs jobs..."
    cd "$build_dir" || return 1

    make "BOARD=$board" -j"$jobs" 2>&1 | tee build.log
    log_ok "Build succeeded for $board"
}

# ----- 打包输出 -----
package_output() {
    local board="$1"
    local output_dir="$2"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    mkdir -p "$output_dir"

    local archive="${output_dir}/${board}_${timestamp}.tar.gz"

    if tar -czf "$archive" -C build/ .; then
        log_ok "Packaged: $archive"
        md5sum "$archive" > "${archive}.md5"
        log_ok "MD5: ${archive}.md5"
    else
        log_error "Failed to package"
        return 1
    fi
}

# ==========================================
# 主流程
# ==========================================

main() {
    local board="${1:-imx6ull}"
    local build_dir="$HOME/build/${board}"
    local output_dir="$HOME/output/${board}"
    local jobs
    jobs=$(nproc)

    log_info "===== One-Click Build ====="
    log_info "Board: $board | Jobs: $jobs"

    # 第一步：环境检查
    check_environment

    # 第二步：清理
    clean_build "$build_dir"

    # 第三步：编译
    do_build "$board" "$jobs" "$build_dir"

    # 第四步：打包
    package_output "$board" "$output_dir"

    log_ok "===== All Done ====="
}

# 执行主函数，把所有命令行参数传进去
main "$@"
```

`set -e` 让任何命令失败时脚本自动退出——不需要在每个函数后面都写 `|| exit 1`。`set -o pipefail` 确保管道中 `make` 的失败能被 `set -e` 捕获（否则 `set -e` 只看管道最后一个命令 `tee` 的退出码）。

这个脚本用到了我们三章学过的几乎所有知识点：

| 技术点 | 出现位置 |
|--------|----------|
| shebang + `set -e` / `set -o pipefail` | 文件开头 |
| `${var:-default}` 默认值语法 | `main` 里的 `board` |
| `$()` 命令替换 | `$(nproc)`, `$(date +%Y%m%d_%H%M%S)` |
| `if [[ ]]` 条件判断 | 各函数内部 |
| `for` 循环遍历数组 | `check_environment` |
| `(( ))` 算术运算 | `${#missing[@]} > 0` |
| 函数定义 + `local` | 所有函数 |
| `echo` + `$()` 返回字符串 | `$(gcc --version \| head -1)` |
| `$1` `$2` 参数传递 | 所有函数 |
| `$@` 传递所有参数 | `main "$@"` |
| `return` 退出码 | 错误分支 |
| 字符串拼接 | archive 文件名 |
| `${var:?}` 防空保护 | `rm -rf` 命令 |

### 4.2 运行与验证

```bash
$ chmod +x one_click_build.sh

# 默认编译 imx6ull
$ ./one_click_build.sh

# 指定板子
$ ./one_click_build.sh imx8mm
```

正常输出：

```
[INFO] ===== One-Click Build =====
[INFO] Board: imx6ull | Jobs: 8
[OK] All tools available
[INFO] GCC: gcc (Ubuntu 11.4.0) 11.4.0
[INFO] Cross: arm-linux-gnueabihf-gcc (Ubuntu 11.4.0) 11.4.0
[INFO] Cleaning: /home/charlie/build/imx6ull
[OK] Cleaned
[INFO] Building imx6ull with 8 jobs...
[编译输出...]
[OK] Build succeeded for imx6ull
[OK] Packaged: /home/charlie/output/imx6ull/imx6ull_20260611_143025.tar.gz
[OK] MD5: /home/charlie/output/imx6ull/imx6ull_20260611_143025.tar.gz.md5
[OK] ===== All Done =====
```

如果环境中缺少工具：

```
[INFO] ===== One-Click Build =====
[INFO] Board: imx6ull | Jobs: 8
[ERROR] Missing tools: arm-linux-gnueabihf-gcc
[ERROR] Install: sudo apt install gcc-arm-linux-gnueabihf build-essential
```

`set -e` 会捕获 `check_environment` 的 `return 1`，脚本到此终止。

验证打包结果：

```bash
$ ls ~/output/imx6ull/
# 预期输出
imx6ull_20260611_143025.tar.gz  imx6ull_20260611_143025.tar.gz.md5

$ md5sum -c ~/output/imx6ull/*.md5
# 预期输出
imx6ull_20260611_143025.tar.gz: OK
```

### 4.3 拆分到多个文件

当脚本超过 200 行，就该拆分了。把公共函数抽到 `lib.sh`，主脚本 `source` 进来：

```
scripts/
├── lib.sh              ← 公共函数（日志、环境检查）
├── one_click_build.sh  ← 主脚本
└── build_imx6ull.sh    ← 板子特定配置
```

```bash
# lib.sh —— 公共函数库
log_info()  { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_ok()    { echo "[OK] $*"; }

check_environment() {
    # ... 同上 ...
}
```

```bash
#!/bin/bash
# one_click_build.sh（精简版主脚本）
set -eo pipefail

# 获取脚本自身所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

main() {
    local board="${1:-imx6ull}"
    # ... 主流程，日志和环境检查函数来自 lib.sh ...
    main "$@"
}
```

`SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` 是一个经典技巧——不管你从哪个目录运行脚本，`source` 都能找到同目录下的 `lib.sh`。`dirname "$0"` 提取脚本所在目录，`cd` 进去后 `pwd` 拿到绝对路径。这个技巧在 Ch26 的字符串操作部分我们已经具备了理解它的能力。

---

## 练习题

函数本身不难，难的是在真实脚本中合理地使用它们。下面三道题分别考察定义、传参和设计。

**练习 28.1** ⭐（理解）

下面这个脚本的输出是什么？为什么？

```bash
#!/bin/bash
count() {
    COUNTER=$((COUNTER + 1))
    echo "Inside: $COUNTER"
}

COUNTER=0
count
count
echo "Outside: $COUNTER"
```

> **提示**：注意 `count` 函数里的 `COUNTER` 没有 `local`。

**练习 28.2** ⭐⭐（应用）

写一个函数 `backup_file()`，功能是：接收一个文件路径作为参数，如果文件存在，把它复制到 `~/backup/` 目录下，文件名加上日期后缀（如 `config.txt.20260611.bak`）。如果文件不存在，打印错误信息并返回非零退出码。

> **提示**：`$(date +%Y%m%d)` 获取日期。`basename` 或 `${path##*/}` 提取文件名。

**练习 28.3** ⭐⭐⭐（思考）

下面的函数试图返回两个值——编译产物的路径和大小。它有一个设计缺陷。是什么？你会怎么改？

```bash
#!/bin/bash
get_build_info() {
    local board="$1"
    local path="/opt/output/$board/zImage"
    local size
    size=$(stat -c%s "$path" 2>/dev/null || echo 0)

    echo "$path"
    echo "$size"
}

# 调用
INFO=$(get_build_info "imx6ull")
echo "Result: $INFO"
```

> **提示**：两次 `echo` 的输出会被 `$()` 合并成一个字符串。想想怎么把 path 和 size 分开获取。

---

## 练习参考答案

**练习 28.1**

```
Inside: 1
Inside: 2
Outside: 2
```

`count` 函数里没有 `local COUNTER`，`COUNTER` 是全局变量。每次调用都在修改同一个变量。如果加上 `local COUNTER=$((COUNTER + 1))`，外部的 `COUNTER` 会始终是 0——因为 `local` 创建了函数内部的独立副本。

**练习 28.2**

```bash
backup_file() {
    local src="$1"

    if [[ ! -f "$src" ]]; then
        echo "[ERROR] File not found: $src" >&2
        return 1
    fi

    local backup_dir="$HOME/backup"
    mkdir -p "$backup_dir"

    local filename
    filename=$(basename "$src")
    local dest="${backup_dir}/${filename}.$(date +%Y%m%d).bak"

    cp "$src" "$dest" && echo "Backed up: $dest"
}
```

**练习 28.3**

两次 `echo` 的输出被 `$()` 合并成一个字符串，中间用换行分隔。`$INFO` 里存的是：

```
/opt/output/imx6ull/zImage
123456
```

`echo "Result: $INFO"` 输出两行，不是一个干净的值。

改进方案一（用全局变量返回多个值）：

```bash
get_build_info() {
    local board="$1"
    BUILD_PATH="/opt/output/$board/zImage"
    BUILD_SIZE=$(stat -c%s "$BUILD_PATH" 2>/dev/null || echo 0)
}

get_build_info "imx6ull"
echo "Path: $BUILD_PATH, Size: $BUILD_SIZE"
```

改进方案二（用固定分隔符，调用者解析）：

```bash
get_build_info() {
    local board="$1"
    local path="/opt/output/$board/zImage"
    local size
    size=$(stat -c%s "$path" 2>/dev/null || echo 0)
    echo "${path}:${size}"
}

IFS=: read -r path size <<< "$(get_build_info 'imx6ull')"
echo "Path: $path, Size: $size"
```

两种方案各有取舍：全局变量更直观但污染命名空间，分隔符方案更干净但需要调用者知道格式。在 Shell 脚本里，**全局变量方案更常用**——简单、直接，适合 Shell 这种「不设防」的哲学。

---

## 本章回响

函数表面上只是一段可以被复用的代码块。但理解函数的关键在于理解 Shell 的**作用域模型**：默认全局、`local` 显式声明、`return` 只返回退出码。这三点和 C 语言的函数模型截然不同，但恰好映射了 Shell 的设计哲学——简单、透明、不设防。Shell 信任你知道自己在做什么，所以它默认所有变量都是全局的，默认函数没有参数约束，默认返回值只是一个退出码。

回到开头那个「压缩器」的比喻。现在应该看清楚了：Shell 函数对代码的「压缩」不是无损的——你丢掉了参数类型信息、返回值类型信息、作用域隔离。这些信息在 C 语言里是编译器帮你检查的，在 Shell 里全靠你自己保证。这种「有损压缩」换来的是极低的语法开销——三行就能定义一个函数，不需要头文件，不需要类型声明。

回到那张「剧本」——我们现在给演员（bash）的不只是台词，还有舞台指示：这里有判断（if），这里有循环（for），这里调用另一段戏（函数）。演员照着演就行，只是每次演出前你得自己检查道具有没有准备好（`local` 防泄漏、引号防空值、`$?` 及时存）。

对于日常的自动化脚本来说，这个代价是值得的。你用几十行 Shell 函数就能把一个复杂的编译流程封装成一条命令——`./build.sh imx6ull`，剩下的全自动。但当脚本复杂到需要传递多个返回值、需要嵌套作用域、需要类型检查的时候，那就是该考虑换 Python 的信号了。

这三章我们完成了 Shell 脚本的基础三部曲：变量与语法（Ch26）→ 流程控制（Ch27）→ 函数与实战（Ch28）。下一章我们来看 Shell 的另一个基础能力——定时任务。怎么让编译脚本每天凌晨自动跑？怎么让日志清理脚本每周执行一次？那是 `crontab` 的领地。

---

[← 上一章](ch27-flow.md)
[下一章 →](ch29-cron.md)
