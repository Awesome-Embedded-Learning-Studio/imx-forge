# 环境初始化指南

## 概述

`env-init.sh` 脚本用于检查和安装构建 i.MX Forge 项目所需的主机依赖包。该脚本支持按构建阶段（Stage）检查依赖，并提供交互式安装功能。

## 使用方法

### 显示帮助信息

```bash
./scripts/init/env-init.sh --help
./scripts/init/env-init.sh -h
```

这将显示完整的使用说明，包括所有选项和示例。

### 检查所有依赖

```bash
./scripts/init/env-init.sh
```

这将检查所有构建阶段所需的依赖包。

### 按构建阶段检查依赖

```bash
# 检查 Stage 1 (U-Boot) 依赖
./scripts/init/env-init.sh --stage 1

# 检查 Stage 2 (Linux Kernel) 依赖
./scripts/init/env-init.sh --stage 2

# 检查 Stage 3 (BusyBox) 依赖
./scripts/init/env-init.sh --stage 3
```

## 依赖包列表

### Stage 1: U-Boot
- build-essential
- bc
- bison
- flex
- device-tree-compiler
- python3
- python3-pyelftools
- swig
- libssl-dev
- libgnutls28-dev
- libncurses-dev
- imagemagick

### Stage 2: Linux Kernel (Mainline/NXP BSP) 
目前，项目默认的选项为NXP BSP，不过两者使用的依赖完全一致！
- build-essential
- bc
- bison
- flex
- device-tree-compiler
- python3
- libssl-dev
- libgnutls28-dev
- libncurses-dev

### Stage 3: BusyBox
- build-essential
- libncurses-dev

## 交互式安装

当检测到缺失的依赖包时，脚本会提示：

```
Would you like to install these dependencies automatically? (y/n):
```

- 输入 `y` 或 `Y`：自动安装缺失的依赖包
- 输入 `n` 或 `N`：跳过安装，脚本返回错误码 1
- 输入其他字符：跳过安装，脚本返回错误码 1

## 在构建脚本中使用

`env-init.sh` 可以被其他构建脚本导入使用：

```bash
# 导入依赖检查脚本
source "${SCRIPT_DIR}/../init/env-init.sh"

# 检查 U-Boot 依赖
check_uboot_dependencies || {
    log_error "Dependency check failed"
    exit 1
}
```

### 可用的检查函数

- `check_all_dependencies()` - 检查所有依赖
- `check_uboot_dependencies()` - 检查 U-Boot 依赖
- `check_linux_dependencies()` - 检查 Linux 内核依赖
- `check_busybox_dependencies()` - 检查 BusyBox 依赖

## 示例输出

```
[INFO] 检查 U-Boot 依赖包...
[INFO]   ✓ bc
[INFO]   ✓ python3
[WARN]   ✗ bison (not found)
[WARN]   ✗ build-essential (not found)
[ERROR] Missing dependencies: bison build-essential

[INFO] Install missing packages with:
  sudo apt install bison build-essential

Would you like to install these dependencies automatically? (y/n): y
[INFO] Installing dependencies...
[INFO] Dependencies installed successfully
```

## 注意事项

1. **网络连接**：安装依赖需要网络连接
2. **Ubuntu**：脚本仅支持 Ubuntu 系统
3. **交互式终端**：脚本使用 `/dev/tty` 读取用户输入，确保在交互式终端中运行

## 故障排除

### 问题：脚本无法读取用户输入

**解决方案**：确保在交互式终端中运行脚本，而不是通过管道或重定向输入。

### 问题：依赖安装失败

**解决方案**：
1. 检查网络连接
2. 更新软件包列表：`sudo apt update`
3. 手动安装失败的依赖包

### 问题：找不到某个依赖包

**解决方案**：
1. 检查软件源配置
2. 启用 universe 仓库：`sudo add-apt-repository universe`
3. 更新软件包列表：`sudo apt update`

## 相关文件

- env-init.sh - 依赖检查脚本
- build-uboot.sh - U-Boot 构建脚本
- build-linux.sh - Linux 内核构建脚本
- build-busybox.sh - BusyBox 构建脚本
