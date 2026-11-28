# env-init.sh - 主机依赖检查脚本

## 脚本概述

`env-init.sh` 是 IMX-Forge 项目的主机依赖检查脚本。它统一管理所有构建脚本的依赖检查，确保主机系统具备构建所需的所有工具和库。

### 核心功能

- **统一依赖管理**：集中管理所有构建脚本的依赖检查
- **按阶段检查**：支持按构建阶段检查特定依赖
- **自动安装提示**：检测缺失依赖并提供安装命令
- **可选自动安装**：交互式询问是否自动安装缺失的依赖
- **多目标支持**：支持 U-Boot、Linux、BusyBox 等不同构建目标

### 设计理念

这个脚本的设计目标是"可被 source"和"可独立运行"两种模式。作为库被 source 时，提供检查函数供其他脚本调用；独立运行时，执行完整的依赖检查。

### 依赖关系

```
env-init.sh
    ├─ bash (解释器)
    ├─ dpkg (包管理检查)
    ├─ command (命令检查)
    └─ python3 (Python 模块检查)
```

## 参数说明

### 命令语法

```bash
./scripts/init/env-init.sh [选项]

# 或作为库 source
source scripts/init/env-init.sh
check_linux_dependencies
```

### 选项列表

| 选项 | 说明 |
|------|------|
| `--stage <1|2|3>` | 检查特定构建阶段的依赖包 |
| `-h, --help` | 显示帮助信息 |

### 阶段说明

| 阶段 | 构建目标 | 说明 |
|------|----------|------|
| 1 | U-Boot | U-Boot 引导程序 |
| 2 | Linux | NXP BSP & Mainline 内核 |
| 3 | BusyBox | BusyBox 工具集 |

## 依赖包列表

### 所有依赖包

| 包名 | 用途 |
|------|------|
| `build-essential` | 编译工具链 (gcc, make) |
| `bc` | 配置计算器 |
| `bison` | 语法分析器生成器 |
| `flex` | 词法分析器生成器 |
| `device-tree-compiler` | 设备树编译器 (dtc) |
| `python3` | Python 环境 |
| `python3-pyelftools` | ELF 文件解析 |
| `swig` | 简化包装接口生成器 |
| `libssl-dev` | OpenSSL 开发库 |
| `libgnutls28-dev` | GnuTLS 开发库 |
| `libncurses-dev` | ncurses 开发库 |
| `imagemagick` | 图像转换工具 (U-Boot) |

### U-Boot 依赖

包含所有依赖包 + `imagemagick`

### Linux 依赖

不包含 `swig` 和 `imagemagick`

### BusyBox 依赖

仅 `build-essential` 和 `libncurses-dev`

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  参数解析                                                    │
│  - 解析选项和阶段参数                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  依赖检查                                                    │
│  - 遍历依赖包列表                                           │
│  - 执行相应的检查方法                                       │
│    - check_cmd(): 命令检查                                  │
│    - check_dpkg(): 包检查                                   │
│    - check_header(): 头文件检查                             │
│    - check_python_module(): Python 模块检查                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  结果处理                                                    │
│  - 显示已安装和缺失的包                                     │
│  - 提供安装命令                                             │
│  - 询问是否自动安装                                         │
└─────────────────────────────────────────────────────────────┘
```

### 检查函数详解

#### check_cmd()

**作用**：检查命令是否存在。

```bash
check_cmd <命令> <包名>
```

**示例**：

```bash
check_cmd gcc build-essential
# 如果 gcc 存在，FOUND_PKGS += build-essential
# 否则，MISSING_PKGS += build-essential
```

#### check_dpkg()

**作用**：检查 dpkg 包是否已安装。

```bash
check_dpkg <包名>
```

**示例**：

```bash
check_dpkg libssl-dev
# 如果 dpkg -s libssl-dev 成功，FOUND_PKGS += libssl-dev
# 否则，MISSING_PKGS += libssl-dev
```

#### check_header()

**作用**：检查头文件是否存在。

```bash
check_header <头文件路径> <包名>
```

**示例**：

```bash
check_header /usr/include/ncursesw/ncurses.h libncurses-dev
```

#### check_python_module()

**作用**：检查 Python 模块是否可导入。

```bash
check_python_module <模块名> <包名>
```

**示例**：

```bash
check_python_module elftools python3-pyelftools
# 如果 import elftools 成功，FOUND_PKGS += python3-pyelftools
# 否则，MISSING_PKGS += python3-pyelftools
```

## 使用示例

### 检查所有依赖

```bash
./scripts/init/env-init.sh
```

**输出示例**：

```
[INFO] 检查 所有 依赖包...
[INFO]   ✓ build-essential
[INFO]   ✓ bc
[INFO]   ✓ bison
[INFO]   ✓ flex
[INFO]   ✓ device-tree-compiler
[INFO]   ✓ python3
[INFO]   ✓ libssl-dev
[INFO]   ✓ libgnutls28-dev
[INFO]   ✓ libncurses-dev
[INFO] All 所有 dependencies found
```

### 按阶段检查

```bash
# 检查 U-Boot 依赖
./scripts/init/env-init.sh --stage 1

# 检查 Linux 依赖（NXP BSP & Mainline）
./scripts/init/env-init.sh --stage 2

# 检查 BusyBox 依赖
./scripts/init/env-init.sh --stage 3
```

### 作为库使用

```bash
# 在其他脚本中 source
source scripts/init/env-init.sh

# 调用特定检查函数
check_linux_dependencies
check_uboot_dependencies
check_busybox_dependencies
```

### 自动安装缺失依赖

```
[INFO] 检查 Linux 依赖包...
[INFO]   ✓ build-essential
[INFO]   ✓ bc
[WARN]   ✗ bison (not found)
[WARN]   ✗ flex (not found)
[INFO]   ✓ device-tree-compiler
[INFO]   ✓ python3
[INFO]   ✓ libssl-dev
[INFO]   ✓ libgnutls28-dev
[INFO]   ✓ libncurses-dev
[ERROR] Missing dependencies: bison flex

Install missing packages with:
  sudo apt install bison flex

Would you like to install these dependencies automatically? (y/n): y

[INFO] Installing dependencies...
[Hit:1 http://archive.ubuntu.com/ubuntu jammy InRelease]
...
[INFO] Dependencies installed successfully
```

## 故障排除

### 常见错误

#### 错误 1：无法自动安装

```
需要sudo权限来安装依赖包
```

**原因**：当前用户没有 sudo 权限。

**解决方法**：

1. 手动运行安装命令
2. 使用有 sudo 权限的用户

#### 错误 2：包管理器不是 apt

**解决方法**：

脚本目前只支持 Debian/Ubuntu 的 apt 包管理器。对于其他发行版，需要修改安装命令。

#### 错误 3：Python 模块检查失败

```
[WARN]   ✗ python3-pyelftools (not found)
```

**解决方法**：

```bash
sudo apt install python3-pyelftools
```

## 集成说明

### 在其他脚本中使用

```bash
#!/bin/bash

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source 依赖检查脚本
source "${SCRIPT_DIR}/../init/env-init.sh"

# 检查依赖
check_linux_dependencies || exit 1

# 继续执行构建...
```

### 检查结果变量

脚本执行后会设置以下变量：

```bash
FOUND_PKGS=()     # 已安装的包列表
MISSING_PKGS=()   # 缺失的包列表
```

## 相关文档

- [build-linux.sh](../build_helper/build-linux.sh.md) - Linux 内核构建脚本
- [build-uboot.sh](../build_helper/build-uboot.sh.md) - U-Boot 构建脚本
- 环境初始化指南
