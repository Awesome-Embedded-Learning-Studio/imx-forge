# lib_common.sh - IMX-Forge 脚本公共库

## 库概述

`lib_common.sh` 是 IMX-Forge 项目的 Bash 脚本公共库，提供统一的日志输出、颜色定义和工具函数。

### 核心功能

- **统一日志接口**：提供标准化的日志输出函数
- **颜色支持**：定义常用的终端颜色代码
- **工具函数**：分隔线、调试输出等辅助函数
- **可被 source**：设计为被其他脚本引用

### 设计理念

这个库的设计目标是提供一致的日志体验和可复用的工具函数，让所有脚本输出风格统一，易于阅读和调试。

## 使用方法

### 基本用法

```bash
#!/bin/bash

# Source 库文件
source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"

# 使用日志函数
log_info "这是一条信息"
log_success "操作成功"
log_warn "这是一条警告"
log_error "这是一条错误"

# 使用分隔线
log_separator "=" 50
```

### 位置独立性

库支持被不同位置的脚本 source：

```bash
# 从 scripts 目录引用
source "lib/bash/lib_common.sh"

# 从项目根目录引用
source "scripts/lib/bash/lib_common.sh"

# 使用相对于脚本的位置
source "$(dirname "${BASH_SOURCE[0]}")/../lib/bash/lib_common.sh"
```

## API 参考

### 颜色定义

| 颜色 | 变量名 | 代码 | 用途 |
|------|--------|------|------|
| 红色 | `RED` | `\033[0;31m` | 错误信息 |
| 绿色 | `GREEN` | `\033[0;32m` | 成功信息 |
| 黄色 | `YELLOW` | `\033[0;33m` | 警告信息 |
| 青色 | `CYAN` | `\033[0;36m` | 信息标记 |
| 灰色 | `GRAY` | `\033[0;90m` | 次要信息 |
| 无色 | `NC` | `\033[0m` | 重置颜色 |

**使用示例**：

```bash
echo -e "${RED}这是红色文本${NC}"
echo -e "${GREEN}这是绿色文本${NC}"
```

### 日志函数

#### log()

**通用日志函数**

```bash
log <消息> <级别>
```

**参数**：

- `消息`：要输出的消息内容
- `级别`：日志级别 (INFO, SUCCESS, WARNING, ERROR)，默认为 INFO

**示例**：

```bash
log "开始处理文件" "INFO"
log "处理完成" "SUCCESS"
log "配置缺失" "WARNING"
log "文件不存在" "ERROR"
```

**输出格式**：

```
[2026-04-29 12:34:56] [INFO] 开始处理文件
[2026-04-29 12:34:57] [SUCCESS] 处理完成
```

#### log_info()

**输出信息级别日志**

```bash
log_info <消息>
```

**示例**：

```bash
log_info "正在编译驱动..."
# 输出: [2026-04-29 12:34:56] [INFO] 正在编译驱动...
```

#### log_success()

**输出成功级别日志**

```bash
log_success <消息>
```

**示例**：

```bash
log_success "构建完成！"
# 输出: [2026-04-29 12:34:56] [SUCCESS] 构建完成！
```

#### log_warn()

**输出警告级别日志**

```bash
log_warn <消息>
```

**示例**：

```bash
log_warn "配置文件使用默认值"
# 输出: [2026-04-29 12:34:56] [WARNING] 配置文件使用默认值
```

#### log_error()

**输出错误级别日志**

```bash
log_error <消息>
```

**示例**：

```bash
log_error "无法找到内核源码"
# 输出: [2026-04-29 12:34:56] [ERROR] 无法找到内核源码
```

#### log_cyan()

**输出青色文本（无前缀）**

```bash
log_cyan <文本...>
```

**示例**：

```bash
log_cyan "=== 标题 ==="
# 输出: === 标题 === （青色）
```

#### log_debug()

**输出调试日志（仅 DEBUG 模式）**

```bash
log_debug <消息>
```

**行为**：

- 当 `DEBUG=true` 时输出消息
- 否则不输出

**示例**：

```bash
DEBUG=true log_debug "详细调试信息"
# 输出: [2026-04-29 12:34:56] [DEBUG] 详细调试信息

log_debug "这条不会显示"
# (无输出)
```

### 工具函数

#### log_separator()

**打印分隔线**

```bash
log_separator [字符] [宽度]
```

**参数**：

- `字符`：分隔线字符，默认 `=`
- `宽度`：分隔线宽度，默认 `40`

**示例**：

```bash
log_separator
# 输出: [INFO] ========================================

log_separator "-" 30
# 输出: [INFO] ------------------------------

log_separator "*" 50
# 输出: [INFO] **************************************************
```

## 使用示例

### 完整脚本示例

```bash
#!/bin/bash

# Source 公共库
source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"

# 主函数
main() {
    log_separator "=" 60
    log_info "开始执行脚本"
    log_separator "=" 60

    # 执行某些操作
    log_debug "调试信息: 当前目录 $(pwd)"
    log_info "处理文件中..."

    if some_command; then
        log_success "操作成功完成"
    else
        log_error "操作失败"
        exit 1
    fi

    log_separator "=" 60
    log_info "脚本执行完毕"
}

main "$@"
```

### 输出示例

```
[2026-04-29 12:34:56] [INFO] ============================================================
[2026-04-29 12:34:56] [INFO] 开始执行脚本
[2026-04-29 12:34:56] [INFO] ============================================================
[2026-04-29 12:34:56] [INFO] 处理文件中...
[2026-04-29 12:34:57] [SUCCESS] 操作成功完成
[2026-04-29 12:34:57] [INFO] ============================================================
[2026-04-29 12:34:57] [INFO] 脚本执行完毕
```

## 设计说明

### 为什么使用 readonly

所有颜色变量都使用 `readonly` 声明，防止被意外修改：

```bash
readonly RED='\033[0;31m'
```

### 时间戳格式

日志时间戳格式为 `YYYY-MM-DD HH:MM:SS`：

```bash
timestamp=$(date "+%Y-%m-%d %H:%M:%S")
```

### 颜色重置

每条日志后都使用 `${NC}` 重置颜色，避免颜色污染后续输出：

```bash
echo -e "${color}[$timestamp] [$level] $message${NC}"
```

## 最佳实践

### 日志级别选择

| 场景 | 使用函数 |
|------|----------|
| 正常流程信息 | `log_info` |
| 操作成功 | `log_success` |
| 非致命问题 | `log_warn` |
| 错误情况 | `log_error` |
| 调试信息 | `log_debug` |
| 标题/重点 | `log_cyan` |

### 错误处理

```bash
# 错误后退出
if ! some_command; then
    log_error "命令执行失败"
    exit 1
fi

# 警告后继续
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_warn "配置文件不存在，使用默认值"
    CONFIG_FILE="/etc/default/config"
fi
```

### 调试模式

```bash
# 启用调试模式
DEBUG=true ./myscript.sh

# 或在脚本中检查
if [[ "${DEBUG:-false}" == "true" ]]; then
    log_debug "详细调试信息"
fi
```

## 相关文档

- [driver_buildlib.sh](../driver_buildlib.sh.md) - 驱动构建库
- [logging.sh](../logging.sh) - 其他日志库（如果存在）
