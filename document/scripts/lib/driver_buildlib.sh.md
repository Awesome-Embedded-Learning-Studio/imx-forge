# driver_buildlib.sh - 驱动构建核心库

## 库概述

`driver_buildlib.sh` 是 IMX-Forge 驱动开发基建系统的核心构建库。它被顶层构建脚本（如 `build_driver.sh`）和驱动目录中的构建脚本共同使用，提供统一的驱动构建逻辑。

### 核心功能

- **内核配置管理**：自动配置和检查内核编译状态
- **驱动模块编译**：统一的内核模块编译接口
- **设备树编译**：设备树源码的编译支持
- **构建信息生成**：自动生成构建元数据
- **清理管理**：普通清理和深度清理功能

### 设计理念

这个库的设计目标是"集中化构建逻辑"。所有驱动构建相关的操作都在这个库中实现，其他脚本只需要调用相应的函数即可。

### 依赖关系

```
driver_buildlib.sh
    ├─ third_party/linux-*/ (内核源码)
    ├─ out/*/linux (内核输出目录)
    └─ arm-none-linux-gnueabihf-gcc (交叉编译工具链)
```

## 配置说明

### 内核类型配置

库支持多种内核类型，通过关联数组配置：

```bash
declare -A KERNEL_CONFIGS
KERNEL_CONFIGS[mainline]="linux_mainline|out/mainline/linux|imx_aes_mainline_defconfig|主线内核"
KERNEL_CONFIGS[imx]="linux-imx|out/linux|imx_aes_defconfig|NXP BSP内核"
```

| 字段 | 说明 |
|------|------|
| 内核名称 | 内核源码目录名 |
| 输出目录 | 编译产物输出目录 |
| defconfig | 使用的配置文件 |
| 描述 | 内核类型描述 |

### 默认配置

```bash
ARCH="${ARCH:-arm}"
CROSS_COMPILE="${CROSS_COMPILE:-arm-none-linux-gnueabihf-}"
DEFAULT_KERNEL_TYPE="${DEFAULT_KERNEL_TYPE:-mainline}"
DEFAULT_BOARD="${DEFAULT_BOARD:-alpha-board}"
```

## API 参考

### 核心函数

#### ensure_kernel_configured()

**确保内核已配置**

```bash
ensure_kernel_configured <内核类型>
```

**功能**：

1. 检查内核源码目录是否存在
2. 检查是否已配置（`.config` 文件）
3. 如果未配置，自动运行 make defconfig

**返回值**：

- `0`：成功
- `1`：失败

#### check_kernel_built()

**检查内核是否已编译**

```bash
check_kernel_built <内核类型>
```

**检查项目**：

| 文件 | 说明 |
|------|------|
| `.config` | 内核配置文件 |
| `include/generated/autoconf.h` | 自动配置头文件 |
| `Module.symvers` | 模块符号表 |

**错误处理**：

如果检查失败，输出详细的错误信息和解决建议。

#### build_driver_module()

**编译驱动模块**

```bash
build_driver_module <驱动目录> <输出目录> <内核类型>
```

**功能**：

1. 切换到驱动目录
2. 运行 make modules
3. 复制 `.ko` 文件到输出目录

**返回值**：

- `0`：成功
- `1`：失败

#### build_device_tree()

**编译设备树**

```bash
build_device_tree <驱动目录> <输出目录> <内核类型>
```

**搜索顺序**：

1. `driver/device_tree/<board>/<driver>/` (新位置)
2. `<驱动目录>/` (回退位置)

**编译流程**：

1. 查找 `.dts` 文件
2. 使用 gcc 预处理
3. 使用 dtc 编译为 `.dtb`

#### generate_build_info()

**生成构建信息**

```bash
generate_build_info <驱动目录> <输出目录> <内核类型>
```

**生成内容**：

```
驱动构建信息
================
构建时间: 2026-04-29 12:34:56
构建用户: user@hostname
内核类型: 主线内核 (linux_mainline)
驱动目录: /path/to/driver

产物文件:
  - driver.ko (12K)
  - driver.dtb (256)
```

#### clean_driver_artifacts()

**清理构建产物**

```bash
clean_driver_artifacts <输出目录>
```

**清理内容**：删除整个输出目录。

#### deep_clean_driver_artifacts()

**深度清理**

```bash
deep_clean_driver_artifacts <输出目录> <驱动目录>
```

**额外清理**：

- `.o`、`.ko`、`.mod`、`.cmd` 文件
- `.tmp_versions` 目录
- 运行 `make clean`

#### driver_build()

**主构建函数**

```bash
driver_build <驱动名> <板卡> <操作> <内核类型>
```

**操作类型**：

| 操作 | 说明 |
|------|------|
| `build` | 构建驱动 |
| `clean` | 清理产物 |
| `deep_clean` | 深度清理 |

**构建流程**：

```
ensure_kernel_configured()
    ↓
check_kernel_built()
    ↓
build_driver_module()
    ↓
build_device_tree()
    ↓
generate_build_info()
```

## 使用示例

### 在顶层脚本中使用

```bash
#!/bin/bash

# Source 构建库
source "scripts/lib/driver_buildlib.sh"

# 构建驱动
driver_build "example-driver" "alpha-board" "build" "mainline"

# 检查结果
if [ $? -eq 0 ]; then
    echo "构建成功"
else
    echo "构建失败"
fi
```

### 在驱动目录中使用

```bash
#!/bin/bash

# driver/my-driver/alpha-board/build.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../scripts/lib/driver_buildlib.sh"

# 获取驱动名和板卡名
DRIVER_NAME=$(basename $(dirname $(dirname $SCRIPT_DIR)))
BOARD_NAME=$(basename $SCRIPT_DIR)

# 构建当前驱动
driver_build "$DRIVER_NAME" "$BOARD_NAME" "build" ""
```

### 清理驱动

```bash
# 普通清理
driver_build "example-driver" "alpha-board" "clean" ""

# 深度清理
driver_build "example-driver" "alpha-board" "deep_clean" ""
```

## 目录结构

```
PROJECT_ROOT/
├── driver/
│   ├── example-driver/
│   │   └── alpha-board/
│   │       ├── Makefile
│   │       ├── driver.c
│   │       └── driver.dts
│   └── device_tree/
│       └── alpha-board/
│           └── example-driver/
│               └── overlay.dts
├── out/
│   └── driver_artifacts/
│       └── example-driver/
│           └── alpha-board/
│               ├── driver.ko
│               ├── driver.dtb
│               └── build_info.txt
├── scripts/
│   └── lib/
│       └── driver_buildlib.sh
└── third_party/
    ├── linux_mainline/
    └── linux-imx/
```

## 故障排除

### 常见错误

#### 错误 1：内核未配置

```
[ERROR] 内核未配置，正在自动配置...
[ERROR] 内核配置失败
```

**原因**：defconfig 文件不存在或内核源码有问题。

**解决方法**：

```bash
# 检查 defconfig
ls third_party/linux_mainline/arch/arm/configs/imx_aes_mainline_defconfig

# 手动配置内核
cd third_party/linux_mainline
make O=../../out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx_aes_mainline_defconfig
```

#### 错误 2：内核未编译

```
[ERROR] 内核未正确编译
[ERROR] 缺少以下文件：
[ERROR]   - Module.symvers (需要运行 modules_prepare)
```

**解决方法**：

```bash
cd third_party/linux_mainline
make O=../../out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
ln -s vmlinux.symvers ../../out/mainline/linux/Module.symvers
```

#### 错误 3：设备树编译失败

```
[WARN]   ✗ example.dts 编译失败
```

**原因**：设备树源码有语法错误或缺少头文件。

**解决方法**：

1. 检查 `.dts` 文件语法
2. 检查 include 路径是否正确
3. 使用 `dtc` 手动编译查看详细错误

## 设计说明

### 为什么使用关联数组配置

关联数组 `KERNEL_CONFIGS` 允许轻松添加新的内核类型：

```bash
KERNEL_CONFIGS[custom]="linux_custom|out/custom|custom_defconfig|自定义内核"
```

### 为什么分开检查配置和编译

配置和编译是两个独立的步骤：

1. **配置**：生成 `.config` 文件，只需要 defconfig
2. **编译**：需要完整的编译过程

分开检查允许更细粒度的错误提示。

### 为什么支持两个设备树位置

1. **新位置** (`driver/device_tree/`)：集中管理所有设备树
2. **旧位置** (`driver/<driver>/<board>/`)：向后兼容

## 相关文档

- [build_driver.sh](../driver_helper/build_driver.sh.md) - 顶层构建脚本
- [驱动开发工作流程](../driver_helper/workflow)
- 设备树编译机制
