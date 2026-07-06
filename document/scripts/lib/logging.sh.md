# logging.sh - 日志工具库详解

## 脚本概述

`logging.sh` 是 IMX-Forge 项目的共享日志工具库，为所有构建脚本提供统一的日志输出格式和颜色支持。它是一个轻量级的日志抽象层，使脚本输出更加一致和易读。

### 核心功能

- **彩色输出**：支持不同日志级别的颜色显示
- **统一格式**：所有脚本使用相同的日志格式
- **调试支持**：可选的调试日志级别
- **向后兼容**：提供带 `LOG_` 前缀和不带前缀的两种颜色变量
- **命令记录**：专门用于记录执行的命令

### 设计理念

这个库遵循"简单即美"的设计原则。它只做一件事：格式化日志输出。不涉及日志文件、日志轮转等复杂功能，保持脚本轻量和易于理解。

**为什么需要统一的日志库**：

1. **一致性**：所有脚本的输出风格统一
2. **可读性**：颜色和格式让输出更易读
3. **可维护性**：修改日志格式只需改一个文件
4. **可复用**：所有构建脚本都可以使用

### 依赖关系

```
logging.sh
    └─ (无依赖，完全独立)
```

使用方：

```
├─ build-linux.sh
├─ build-uboot.sh
├─ build-busybox.sh
└─ ... (其他脚本)
```

## 使用方法

### 基本用法

```bash
#!/bin/bash

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/../lib"

# 加载日志库
if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    echo "Error: logging.sh not found"
    exit 1
fi

# 使用日志函数
log_info "Starting build process..."
log_warn "This is a warning"
log_error "This is an error"
log_debug "This is debug info"
log_cmd "make -j8"
```

### 后备模式

如果 `logging.sh` 不可用，构建脚本会使用内嵌的备用定义：

```bash
if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    # 后备定义
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_debug() { if [[ "${DEBUG:-0}" == "1" ]]; then echo -e "${BLUE}[DEBUG]${NC} $1"; fi; }
    log_cmd() { echo -e "${YELLOW}[CMD]${NC} $1"; }
fi
```

这种设计确保即使日志库缺失，脚本也能正常工作。

## API 参考

### 颜色常量

#### 导出的颜色变量

| 变量名 | ANSI 转义序列 | 颜色 | 用途 |
|--------|--------------|------|------|
| `LOG_RED` | `\033[0;31m` | 红色 | 错误信息 |
| `LOG_GREEN` | `\033[0;32m` | 绿色 | 一般信息 |
| `LOG_YELLOW` | `\033[1;33m` | 黄色 | 警告信息 |
| `LOG_BLUE` | `\033[0;34m` | 蓝色 | 调试信息 |
| `LOG_NC` | `\033[0m` | 无颜色 | 重置颜色 |

#### 向后兼容的别名

为了向后兼容，同时导出不带 `LOG_` 前缀的版本：

| 别名 | 指向 |
|------|------|
| `RED` | `LOG_RED` |
| `GREEN` | `LOG_GREEN` |
| `YELLOW` | `LOG_YELLOW` |
| `BLUE` | `LOG_BLUE` |
| `NC` | `LOG_NC` |

**为什么需要两套变量**：

- `LOG_*` 前缀：避免与脚本中可能定义的同名变量冲突
- 无前缀版本：保持与旧代码的兼容性

### 日志函数

#### log_info()

**作用**：输出一般信息（绿色）。

**语法**：

```bash
log_info "message"
```

**参数**：

- `$1`：要输出的消息字符串

**输出格式**：

```
[INFO] message
```

**颜色**：绿色

**使用场景**：

- 构建步骤的开始和完成
- 检查通过的信息
- 一般性进度信息

**示例**：

```bash
log_info "Starting U-Boot build..."
log_info "All dependencies found"
log_info "Build completed successfully"
```

#### log_error()

**作用**：输出错误信息（红色），重定向到 stderr。

**语法**：

```bash
log_error "message"
```

**参数**：

- `$1`：要输出的错误消息字符串

**输出格式**：

```
[ERROR] message
```

**颜色**：红色

**输出流**：stderr (`>&2`)

**使用场景**：

- 致命错误
- 检查失败
- 构建失败

**示例**：

```bash
log_error "Cross compiler not found"
log_error "Defconfig file not found"
log_error "Build failed"

# 通常后跟 exit 1
log_error "Cannot continue"
exit 1
```

**为什么重定向到 stderr**：

按照 Unix 惯例，正常输出到 stdout，错误信息到 stderr。这样用户可以分别捕获：

```bash
# 只捕获正常输出
./script.sh 2>/dev/null

# 分别保存
./script.sh > output.log 2> error.log
```

#### log_warn()

**作用**：输出警告信息（黄色）。

**语法**：

```bash
log_warn "message"
```

**参数**：

- `$1`：要输出的警告消息字符串

**输出格式**：

```
[WARN] message
```

**颜色**：黄色

**使用场景**：

- 非致命问题
- 可选依赖缺失
- 配置建议

**示例**：

```bash
log_warn "Optional package not found: ccache"
log_warn "Using existing configuration"
log_warn "This operation may take a while"
```

#### log_debug()

**作用**：输出调试信息（蓝色），仅在启用调试模式时输出。

**语法**：

```bash
log_debug "message"
```

**参数**：

- `$1`：要输出的调试消息字符串

**输出格式**：

```
[DEBUG] message
```

**颜色**：蓝色

**触发条件**：`DEBUG` 环境变量设置为 `"1"`

**使用场景**：

- 详细的执行流程
- 变量值输出
- 跟踪复杂逻辑

**示例**：

```bash
log_debug "Configuration file: ${CONFIG_FILE}"
log_debug "Toolchain version: ${GCC_VERSION}"
log_debug "Skipping distclean (fast build mode)"
```

**启用调试模式**：

```bash
# 方法1：环境变量
DEBUG=1 ./scripts/build_helper/build-linux.sh

# 方法2：在脚本中设置
export DEBUG=1
./scripts/build_helper/build-linux.sh
```

#### log_cmd()

**作用**：输出将要执行的命令（黄色）。

**语法**：

```bash
log_cmd "command"
```

**参数**：

- `$1`：要显示的命令字符串

**输出格式**：

```
[CMD] command
```

**颜色**：黄色

**使用场景**：

- 显示即将执行的 make 命令
- 显示复杂的命令行
- 调试构建问题

**示例**：

```bash
local cmd="make -C ${SRC_DIR} ARCH=arm -j8"
log_cmd "${cmd}"
${cmd}
```

**设计考虑**：

为什么需要单独的 `log_cmd()` 而不是用 `log_info()`？

1. **视觉区分**：命令输出与普通信息有视觉区别
2. **可复制性**：用户可以直接复制命令执行
3. **一致性**：所有脚本使用相同格式显示命令

## 设计决策

### 为什么使用 ANSI 转义序列

ANSI 转义序列是终端控制的标准方式：

```bash
\033[0;31m  # 红色
\033[0;32m  # 绿色
\033[1;33m  # 粗体黄色
\033[0m     # 重置
```

**为什么不使用 tput**：

`tput` 是更高级的终端控制工具，但它：

1. 依赖外部命令
2. 性能稍差
3. 对于简单的颜色支持，ANSI 转义序列足够

ANSI 转义序列被几乎所有现代终端支持。

### 为什么错误信息输出到 stderr

这是 Unix 的标准做法：

1. **管道友好**：`./script.sh | grep something` 不会包含错误信息
2. **日志分离**：可以分别保存标准输出和错误输出
3. **工具兼容**：与各种 Unix 工具配合良好

示例：

```bash
# 只保存正常输出
./script.sh > output.log 2>/dev/null

# 分别保存
./script.sh 1>output.log 2>error.log

# 合并保存
./script.sh &> combined.log
```

### 为什么导出颜色变量

使用 `export` 导出颜色变量，让子进程也能访问：

```bash
export LOG_RED='\033[0;31m'
```

**好处**：

1. **子脚本可用**：被调用的脚本可以直接使用
2. **避免重复定义**：不需要在每个脚本中重新定义
3. **一致性**：所有脚本使用相同的颜色

**示例**：

```bash
# 主脚本
source scripts/lib/logging.sh
./subscript.sh  # 子脚本可以访问 LOG_RED 等变量
```

### 为什么调试信息默认关闭

调试信息可能会：

1. **干扰正常输出**：大量调试信息让用户难以找到关键信息
2. **影响性能**：频繁的输出（尤其是终端）有性能开销
3. **不必要**：大多数情况下用户不需要这些信息

使用环境变量控制而不是修改脚本：

1. **不需要修改代码**：启用/禁用不需要改脚本
2. **临时调试**：`DEBUG=1 ./script.sh` 临时调试
3. **生产环境**：默认关闭，保持输出干净

## 颜色设计

### 颜色选择理由

| 级别 | 颜色 | ANSI | 理由 |
|------|------|------|------|
| INFO | 绿色 | `0;32` | 表示正常、成功 |
| ERROR | 红色 | `0;31m` | 表示错误、停止（通用约定） |
| WARN | 黄色 | `1;33m` | 表示注意（高亮黄更醒目） |
| DEBUG | 蓝色 | `0;34m` | 表示信息性、技术性 |
| CMD | 黄色 | `1;33m` | 与 WARN 相同，表示"注意这个" |

**颜色心理学**：

- **绿色**：安全、成功、继续
- **红色**：危险、错误、停止
- **黄色**：注意、警告、重要
- **蓝色**：信息、技术、中性

### 颜色对比度

所有颜色都经过选择，确保在深色和浅色终端背景上都有良好的对比度：

```bash
# 绿色 - 深色背景
LOG_GREEN='\033[0;32m'

# 红色 - 深色背景
LOG_RED='\033[0;31m'

# 黄色 - 使用粗体增强对比
LOG_YELLOW='\033[1;33m'
```

**无颜色模式**：

如果需要禁用所有颜色，可以设置：

```bash
export LOG_RED=''
export LOG_GREEN=''
export LOG_YELLOW=''
export LOG_BLUE=''
export LOG_NC=''
```

这在某些情况下很有用：

1. 日志文件
2. CI/CD 环境
3. 不支持颜色的终端

## 扩展和定制

### 添加新的日志级别

如果需要添加新的日志级别（如 TRACE）：

```bash
# 编辑 logging.sh
# 添加颜色
export LOG_CYAN='\033[0;36m'

# 添加函数
log_trace() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${LOG_CYAN}[TRACE]${LOG_NC} $1"
    fi
}
```

### 添加时间戳

如果需要日志带时间戳：

```bash
# 修改 log_info 等函数
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${LOG_GREEN}[${timestamp}][INFO]${LOG_NC} $1"
}
```

### 添加文件输出

如果需要同时输出到文件：

```bash
# 添加日志文件变量
export LOG_FILE="${PROJECT_ROOT}/build.log"

# 修改 log_info 等函数
log_info() {
    local msg="[INFO] $1"
    echo -e "${LOG_GREEN}${msg}${LOG_NC}"
    echo "${msg}" >> "${LOG_FILE}"
}
```

### 格式化输出

如果需要结构化输出（如 JSON）：

```bash
log_json() {
    local level=$1
    local message=$2
    echo "{\"level\":\"${level}\",\"message\":\"${message}\",\"timestamp\":\"$(date -Iseconds)\"}"
}
```

## 最佳实践

### 何时使用 log_info()

- 构建步骤的开始和结束
- 检查通过的信息
- 进度信息
- 成功操作的确认

### 何时使用 log_error()

- 致命错误（会导致脚本退出）
- 必需的依赖缺失
- 无法恢复的失败

**最佳实践**：log_error() 后通常跟 exit 1

### 何时使用 log_warn()

- 非致命问题
- 可选依赖缺失
- 使用默认值
- 可能的注意事项

### 何时使用 log_debug()

- 开发调试信息
- 变量值输出
- 详细执行流程
- 复杂逻辑跟踪

**不要在正常输出中使用 log_debug()**，保持正常输出的简洁。

### 何时使用 log_cmd()

- 显示即将执行的命令
- 复杂的构建命令
- 调试命令执行问题

**最佳实践**：在执行命令前调用 log_cmd() 显示命令

```bash
local cmd="make -j8"
log_cmd "${cmd}"
${cmd}
```

## 常见问题

### Q: 为什么我的终端没有颜色？

A: 可能的原因：

1. 终端不支持 ANSI 颜色
2. 使用了管道或重定向
3. 环境变量禁用了颜色

解决方案：

```bash
# 检查终端类型
echo $TERM

# 强制启用颜色（某些情况）
export TERM=xterm-256color
```

### Q: 如何完全禁用颜色？

A: 设置环境变量：

```bash
export NO_COLOR=1
# 或者
export TERM=dumb
```

然后修改 logging.sh 检查这些变量：

```bash
if [[ -n "${NO_COLOR}" || "${TERM}" == "dumb" ]]; then
    LOG_RED=''
    LOG_GREEN=''
    LOG_YELLOW=''
    LOG_BLUE=''
    LOG_NC=''
fi
```

### Q: 为什么 log_error() 输出到 stderr？

A: 这是 Unix 标准做法，便于：

```bash
# 分离正常输出和错误
./script.sh > output.txt 2> error.txt

# 只看错误
./script.sh 2>&1 >/dev/null
```

### Q: 可以在非脚本环境中使用吗？

A: 可以，在交互式 shell 中：

```bash
source /path/to/imx-forge/scripts/lib/logging.sh
log_info "Hello from interactive shell!"
```

## 相关文档

- [build-linux.sh](../build_helper/build-linux.sh) - 使用 logging.sh 的脚本示例
- [build-uboot.sh](../build_helper/build-uboot.sh) - 使用 logging.sh 的脚本示例
- [build-buildroot.sh](../build_helper/build-buildroot.sh) - 使用 logging.sh 的脚本示例
