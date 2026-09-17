# build_driver.sh - 驱动构建脚本

## 概述

`build_driver.sh` 是 IMX Forge 项目中统一的驱动构建入口脚本，用于编译驱动模块和设备树文件。该脚本支持批量构建、单个构建、清理操作，始终基于主线内核（mainline 单轨）构建。

## 功能特性

- ✅ 支持单个驱动构建和批量构建
- ✅ 支持多板卡配置
- ✅ 基于主线内核（mainline）单轨构建，无需选内核
- ✅ 自动列出所有可用驱动
- ✅ 支持清理构建产物
- ✅ 详细的构建日志和错误提示

## 语法

```bash
./scripts/driver_helper/build_driver.sh [选项] [驱动] [板卡]
```

## 参数说明

### 位置参数

| 参数 | 说明 | 默认值 | 必需 |
|------|------|--------|------|
| 驱动 | 驱动名称（如：led、example-driver、spi） | - | 是（构建时） |
| 板卡 | 板卡名称（如：alpha-board、beta-board） | alpha-board | 否 |

### 选项参数

| 选项 | 说明 | 示例 |
|------|------|------|
| `--list` | 列出所有可用的驱动和板卡配置 | `--list` |
| `--all` | 构建所有驱动 | `--all` |
| `--clean` | 清理构建产物 | `--clean example-driver` |
| `--board=NAME` | 只构建指定板卡的驱动 | `--board=alpha-board` |
| `--help, -h` | 显示帮助信息 | `--help` |

### 内核类型

只有主线内核一条（单轨），`--kernel` 参数已退役，调用时不需要选内核：

| 类型 | 说明 | 配置文件 | 内核目录 |
|------|------|----------|----------|
| mainline | 主线内核（默认且唯一） | imx_aes_mainline_defconfig | third_party/linux_mainline |

## 使用示例

### 1. 列出所有可用驱动

```bash
./scripts/driver_helper/build_driver.sh --list
```

输出示例：
```
========================================
可用驱动列表
========================================

📦 example-driver
  └─ alpha-board [✓ Makefile 源码]

📦 led
  └─ alpha-board [✓ Makefile 源码]

========================================
总计: 2 个驱动, 2 个板卡配置
========================================
```

### 2. 构建单个驱动

```bash
# 构建指定驱动的默认板卡
./scripts/driver_helper/build_driver.sh example-driver

# 构建指定板卡的驱动
./scripts/driver_helper/build_driver.sh led alpha-board
```

### 3. 批量构建所有驱动

```bash
# 构建所有驱动的所有板卡
./scripts/driver_helper/build_driver.sh --all

# 只构建 alpha-board 的所有驱动
./scripts/driver_helper/build_driver.sh --all --board=alpha-board
```

### 4. 清理构建产物

```bash
# 清理指定驱动的构建产物
./scripts/driver_helper/build_driver.sh --clean example-driver

# 清理指定板卡的驱动
./scripts/driver_helper/build_driver.sh --clean example-driver alpha-board

# 清理所有驱动的构建产物
./scripts/driver_helper/build_driver.sh --clean --all
```

### 5. 组合使用

```bash
# 构建 alpha-board 的所有驱动
./scripts/driver_helper/build_driver.sh --all --board=alpha-board

# 查看可用驱动
./scripts/driver_helper/build_driver.sh --list
```

## 构建产物

构建成功后，产物将存放在：

```
out/driver_artifacts/<驱动>/<板卡>/
├── <驱动名>.ko              # 编译后的内核模块
├── <设备树>.dtb             # 编译后的设备树
└── build_info.txt           # 构建信息文件
```

示例：
```
out/driver_artifacts/example-driver/alpha-board/
├── example-driver.ko
├── imx6ull-aes-example-driver.dtb
└── build_info.txt
```

## 构建信息

`build_info.txt` 包含以下信息：

- 构建时间
- 构建用户
- 内核类型
- 驱动目录
- 产物文件列表及大小

## 常见问题

### 1. 内核未配置错误

**错误信息**：
```
❌ 内核未正确编译
缺少以下文件：
  - 内核配置文件: .config
  - Module.symvers (需要运行 modules_prepare)
```

**解决方案**：
```bash
# 方案1: 完整编译内核
cd third_party/linux_mainline
make O=../../out/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)

# 方案2: 快速编译（仅生成必要文件）
cd third_party/linux_mainline
make O=../../out/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
```

### 2. 交叉编译工具链未找到

**错误信息**：
```
arm-none-linux-gnueabihf-gcc: command not found
```

**解决方案**：
```bash
# 安装交叉编译工具链
sudo apt-get install gcc-arm-none-linux-gnueabihf
```

### 3. 设备树编译失败

**错误信息**：
```
✗ imx6ull-aes-example-driver.dts 编译失败
```

**解决方案**：
```bash
# 检查设备树编译器是否安装
sudo apt-get install device-tree-compiler

# 检查设备树文件语法
dtc -I dts -O dtb -o /dev/null driver/device_tree/alpha-board/example-driver/*.dts
```

### 4. 驱动目录不存在

**错误信息**：
```
❌ 驱动目录不存在: driver/example-driver/alpha-board
```

**解决方案**：
```bash
# 检查驱动目录结构
ls -la driver/

# 使用 --list 查看可用的驱动和板卡
./scripts/driver_helper/build_driver.sh --list
```

### 5. 构建失败但日志不清晰

**解决方案**：
```bash
# 启用调试模式
DEBUG=1 ./scripts/driver_helper/build_driver.sh example-driver

# 查看详细的编译输出
cd driver/example-driver/alpha-board
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -C ../../../third_party/linux_mainline M=$(pwd) O=../../../out/linux modules
```

## 与其他脚本的配合

### 1. 构建后审查

```bash
# 构建驱动
./scripts/driver_helper/build_driver.sh example-driver

# 审查构建产物
./scripts/driver_helper/review_driver.sh example-driver
```

### 2. 构建后部署

```bash
# 构建驱动
./scripts/driver_helper/build_driver.sh example-driver

# 部署到目标系统
./scripts/driver_helper/deploy_driver.sh out/driver_artifacts/example-driver/alpha-board
```

### 3. 查看设备树

```bash
# 构建驱动
./scripts/driver_helper/build_driver.sh example-driver

# 查看设备树内容
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/example-driver/alpha-board/*.dtb
```

## 注意事项

1. **首次构建前**：确保内核已配置和编译
2. **批量构建**：使用 `--all` 时会构建所有驱动，可能需要较长时间
3. **清理操作**：`--clean` 会删除所有构建产物，但保留源码
4. **板卡名称**：板卡名称必须与目录结构匹配
5. **产物位置**：构建产物统一存放在 `out/driver_artifacts/` 目录

## 高级用法

### 1. 自定义构建环境

```bash
# 设置交叉编译工具链
export CROSS_COMPILE=arm-none-linux-gnueabihf-

# 设置架构
export ARCH=arm

# 构建驱动
./scripts/driver_helper/build_driver.sh example-driver
```

### 2. 并行构建

```bash
# 使用 make 的并行构建功能
cd driver/example-driver/alpha-board
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -C ../../../third_party/linux_mainline M=$(pwd) O=../../../out/linux modules
```

### 3. 增量构建

```bash
# 修改源码后重新构建（只重新编译修改的文件）
./scripts/driver_helper/build_driver.sh example-driver

# 清理后重新构建（完全重新编译）
./scripts/driver_helper/build_driver.sh --clean example-driver
./scripts/driver_helper/build_driver.sh example-driver
```

## 相关文档

- [deploy_driver.md](./deploy_driver.md) - 驱动部署脚本
- [review_driver.md](./review_driver.md) - 驱动审查脚本
- [show_device_tree.md](./show_device_tree.md) - 设备树查看脚本
- [configuration.md](./configuration.md) - 配置文件说明
- [driver_buildlib.md](../lib/driver_buildlib.md) - 构建库说明
