# build_driver.sh - 驱动构建统一入口脚本

## 脚本概述

`build_driver.sh` 是 IMX-Forge 驱动开发基建系统的顶层构建脚本。它提供统一的命令行接口来构建、清理和管理所有驱动模块。

### 核心功能

- **统一构建入口**：单个命令构建任何驱动
- **批量构建**：支持一键构建所有驱动
- **内核类型切换**：支持 mainline 和 imx 两种内核
- **清理管理**：支持普通清理和深度清理
- **自动部署提示**：构建成功后询问是否部署

### 设计理念

这个脚本是驱动构建系统的"前端"，它不直接执行编译，而是调用共享库 `driver_buildlib.sh` 中的函数完成实际工作。这种设计使得构建逻辑集中管理，多个脚本可以复用。

### 依赖关系

```
build_driver.sh
    ├─ scripts/lib/driver_buildlib.sh (核心构建库)
    ├─ driver/*/Makefile (各驱动的 Makefile)
    ├─ third_party/linux-*/ (内核源码)
    └─ scripts/driver_helper/driver_helper.conf (可选配置)
```

## 参数说明

### 命令语法

```bash
./scripts/driver_helper/build_driver.sh [选项] [驱动] [板卡]
```

### 选项列表

| 选项 | 说明 |
|------|------|
| `--list` | 列出所有可用的驱动 |
| `--all` | 构建所有驱动 |
| `--clean` | 清理构建产物（仅最终产物） |
| `--deep-clean` | 深度清理（包括中间文件） |
| `--board=NAME` | 只构建指定板卡的驱动 |
| `--kernel=TYPE` | 选择内核类型 (mainline\|imx) |
| `--help, -h` | 显示帮助信息 |

### 位置参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `驱动` | 驱动名称 (如: led, framework) | - |
| `板卡` | 板卡名称 (如: alpha-board) | `alpha-board` |

### 内核类型

| 类型 | 说明 | 内核源码 |
|------|------|----------|
| `mainline` | 主线内核 | `linux_mainline` |
| `imx` | NXP BSP 内核 | `linux-imx` |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  参数解析与验证                                              │
│  - 解析命令行选项                                           │
│  - 验证内核类型                                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  操作分发                                                    │
│  - list: 列出驱动                                           │
│  - all: 批量构建                                            │
│  - clean/deep_clean: 清理                                   │
│  - build: 单驱动构建                                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  调用 driver_buildlib.sh                                    │
│  - ensure_kernel_configured()                               │
│  - check_kernel_built()                                     │
│  - build_driver_module()                                    │
│  - build_device_tree()                                      │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### list_drivers()

**作用**：列出所有可用的驱动和板卡配置。

**扫描规则**：

- 跳过 `base_driver`、`device_tree`、`firmwares`、`application` 目录
- 检查是否有 Makefile 或源码文件

**输出示例**：

```
========================================
可用驱动列表
========================================

📦 example-driver
  └─ alpha-board [✓ Makefile ✓ 源码]

📦 led
  └─ alpha-board [✓ Makefile]

📦 chardev_base_00
  └─ alpha-board [✓ 源码]

========================================
总计: 3 个驱动, 3 个板卡配置
========================================
```

#### build_specific_driver()

**作用**：构建指定的驱动。

**执行流程**：

1. 调用 `driver_build()` 函数
2. 构建成功后询问是否部署
3. 如确认，调用 `deploy_driver.sh`

#### build_all_drivers()

**作用**：批量构建所有驱动。

**特性**：

- 支持板卡过滤 (`--board` 选项)
- 显示构建进度和统计
- 失败后继续构建其他驱动

**输出示例**：

```
========================================
批量构建所有驱动
板卡过滤: alpha-board
内核: mainline
========================================

[1] 构建: example-driver/alpha-board
  ✓ 成功

[2] 构建: led/alpha-board
  ✓ 成功

[3] 构建: chardev_base_00/alpha-board
  ✗ 失败

========================================
构建完成
总计: 3 | 成功: 2 | 失败: 1
========================================
```

#### clean_specific_driver()

**作用**：清理指定驱动的最终产物。

**清理内容**：

- `out/driver_artifacts/<驱动>/<板卡>/` 目录
- 驱动目录中的 `.o`、`.ko` 等编译产物

#### deep_clean_specific_driver()

**作用**：深度清理，包括中间构建文件。

**额外清理**：

- `.tmp_versions/` 目录
- `*.mod`、`*.mod.c`、`*.cmd` 文件
- `Module.symvers`、`modules.order` 文件

## 配置选项

### 默认配置

```bash
ACTION="build"
DRIVER_NAME=""
BOARD_NAME=""
KERNEL_TYPE="${DEFAULT_KERNEL_TYPE:-mainline}"
```

### 目录结构

```
PROJECT_ROOT/
├── driver/                          # 驱动源码
│   ├── example-driver/
│   │   └── alpha-board/
│   │       ├── Makefile
│   │       └── *.c
│   └── ...
├── out/
│   └── driver_artifacts/            # 构建产物
│       └── <驱动>/
│           └── <板卡>/
│               ├── *.ko
│               ├── *.dtb
│               └── build_info.txt
├── scripts/
│   ├── driver_helper/
│   │   ├── build_driver.sh          # 本脚本
│   │   ├── deploy_driver.sh
│   │   ├── review_driver.sh
│   │   └── driver_helper.conf       # 可选配置
│   └── lib/
│       └── driver_buildlib.sh       # 核心构建库
└── third_party/
    ├── linux_mainline/              # 主线内核
    └── linux-imx/                   # BSP 内核
```

## 使用示例

### 列出可用驱动

```bash
./scripts/driver_helper/build_driver.sh --list
```

### 构建单个驱动

```bash
# 完整命令
./scripts/driver_helper/build_driver.sh example-driver alpha-board

# 使用默认板卡
./scripts/driver_helper/build_driver.sh example-driver

# 使用 imx 内核
./scripts/driver_helper/build_driver.sh example-driver --kernel=imx
```

### 批量构建

```bash
# 构建所有驱动
./scripts/driver_helper/build_driver.sh --all

# 只构建 alpha 板的驱动
./scripts/driver_helper/build_driver.sh --all --board=alpha-board
```

### 清理驱动

```bash
# 普通清理（清理产物）
./scripts/driver_helper/build_driver.sh --clean example-driver

# 深度清理（包括中间文件）
./scripts/driver_helper/build_driver.sh --deep-clean example-driver

# 清理所有驱动
./scripts/driver_helper/build_driver.sh --clean --all
```

## 输出示例

### 单驱动构建

```
========================================
构建驱动: example-driver/alpha-board
内核: mainline
========================================
[INFO] 🔨 构建驱动: example-driver/alpha-board
[INFO] ========================================
[INFO] ✓ 内核配置完成
[INFO] 编译驱动模块...
[INFO] ✓ 编译完成 (1 个模块)
[INFO] 编译设备树...
[INFO] ✓ 编译完成 (1 个设备树)
[INFO] ========================================
[INFO] ✓ 构建完成: out/driver_artifacts/example-driver/alpha-board

✅ 构建成功！
是否部署驱动? [Y/n]: y

[INFO] 开始部署驱动...
```

### 构建失败

```
========================================
构建驱动: example-driver/alpha-board
内核: mainline
========================================
[ERROR] 内核未正确编译
[ERROR] ========================================
[ERROR] ❌ 内核未正确编译
[ERROR] ========================================
[ERROR] 内核类型: 主线内核 (linux_mainline)
[ERROR] 内核目录: third_party/linux_mainline
[ERROR] 输出目录: out/mainline/linux
[ERROR]
[ERROR] 缺少以下文件：
[ERROR]   - Module.symvers (需要运行 modules_prepare)
[ERROR]
[ERROR] 💡 解决方案：
[ERROR]    1. 完整编译内核：
[ERROR]       cd third_party/linux_mainline
[ERROR]       make O=out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)
```

## 故障排除

### 常见错误

#### 错误 1：驱动目录不存在

```
[ERROR] 驱动目录不存在: driver/unknown-driver/alpha-board
```

**解决方法**：

1. 检查驱动名称是否正确
2. 使用 `--list` 查看可用驱动

#### 错误 2：内核未配置

```
[ERROR] 内核未配置，正在自动配置...
[ERROR] 内核配置失败
```

**解决方法**：

确保内核源码存在：

```bash
ls third_party/linux_mainline
```

#### 错误 3：内核未编译

```
[ERROR] 内核未正确编译
[ERROR] 缺少以下文件：
[ERROR]   - Module.symvers (需要运行 modules_prepare)
```

**解决方法**：

编译内核或运行 modules_prepare：

```bash
cd third_party/linux_mainline
make O=../../out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
ln -s vmlinux.symvers ../../out/mainline/linux/Module.symvers
```

#### 错误 4：编译失败

```
[ERROR] 驱动编译失败
[ERROR] 编译错误:
error: implicit declaration of function 'xxx'
```

**解决方法**：

检查驱动源码和 Makefile，确保：
1. 源码语法正确
2. 依赖的头文件可用
3. 内核配置正确

## 相关文档

- [driver_buildlib.sh](../lib/driver_buildlib.sh) - 核心构建库详解
- [deploy_driver.sh](./deploy_driver.sh.md) - 驱动部署脚本
- [review_driver.sh](./review_driver.sh.md) - 驱动审查脚本
- [驱动开发工作流程](./workflow.md)
