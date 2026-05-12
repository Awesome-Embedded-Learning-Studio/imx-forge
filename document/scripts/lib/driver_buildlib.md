# driver_buildlib.sh - 核心构建库

> **目标读者**：开发者、项目维护者 | **难度**：🟡-🔴

## 概述

`driver_buildlib.sh` 是IMX-Forge驱动开发基建系统的核心构建库，提供所有底层构建逻辑。该库被所有顶层脚本调用，实现了驱动的编译、设备树处理、构建信息生成等核心功能。

## 设计原则

### 🎯 核心设计理念

1. **单一职责**：每个函数只负责一个具体功能
2. **配置驱动**：通过配置文件控制行为，避免硬编码
3. **错误处理**：详细的错误检查和友好的错误信息
4. **日志记录**：统一的日志接口和调试支持

### 📦 库的特点

- ✅ **可复用**：被多个脚本调用
- ✅ **可测试**：函数独立，易于单元测试
- ✅ **可扩展**：配置化的内核类型管理
- ✅ **可维护**：清晰的代码结构和注释

## 核心配置

### 内核类型配置

```bash
declare -A KERNEL_CONFIGS
KERNEL_CONFIGS[mainline]="linux_mainline|out/mainline/linux|imx_aes_mainline_defconfig|主线内核"
KERNEL_CONFIGS[imx]="linux-imx|out/linux|imx_aes_defconfig|NXP BSP内核"
```

**配置格式**：
```
内核类型名 = 内核目录名|输出目录|defconfig文件名|描述
```

**添加新内核类型**：
```bash
# 在脚本中添加新配置
KERNEL_CONFIGS[rt-linux]="linux-rt|out/rt/linux|imx_aes_rt_defconfig|实时内核"

# 立即可用
driver_build "driver" "board" "build" "rt-linux"
```

### 环境变量

| 变量 | 默认值 | 说明 |
|-----|-------|------|
| `ARCH` | `arm` | 目标架构 |
| `CROSS_COMPILE` | `arm-none-linux-gnueabihf-` | 交叉编译工具链前缀 |
| `DEFAULT_KERNEL_TYPE` | `mainline` | 默认内核类型 |
| `DEFAULT_BOARD` | `alpha-board` | 默认板卡名称 |

## 核心函数

### 1. driver_build()

**功能**：统一的驱动构建入口

**签名**：
```bash
driver_build <driver_name> <board> <action> <kernel_type>
```

**参数**：
- `driver_name`：驱动名称
- `board`：板卡名称（默认：alpha-board）
- `action`：操作类型（build/clean）
- `kernel_type`：内核类型（默认：mainline）

**示例**：
```bash
# 构建驱动
driver_build "example-driver" "alpha-board" "build" "mainline"

# 清理驱动
driver_build "example-driver" "alpha-board" "clean" ""
```

**实现流程**：
```
driver_build()
  ├── 检查驱动目录存在
  ├── 根据action分发
  │   ├── build)
  │   │   ├── ensure_kernel_configured()
  │   │   ├── check_kernel_built()
  │   │   ├── build_driver_module()
  │   │   ├── build_device_tree()
  │   │   └── generate_build_info()
  │   └── clean)
  │       ├── clean_driver_artifacts()
  │       └── make clean
  └── 返回结果
```

### 2. ensure_kernel_configured()

**功能**：确保内核已配置

**签名**：
```bash
ensure_kernel_configured <kernel_type>
```

**实现逻辑**：
```bash
ensure_kernel_configured() {
    local kernel_type="$1"
    local IFS='|'
    read -r kernel_name kobj_dir defconfig kernel_desc <<< "${KERNEL_CONFIGS[$kernel_type]}"

    local kdir="${DRIVER_PROJECT_ROOT}/third_party/${kernel_name}"
    local kobj="${DRIVER_PROJECT_ROOT}/${kobj_dir}"

    # 检查是否已配置
    if [[ -f "${kobj}/.config" ]]; then
        return 0
    fi

    # 自动配置
    mkdir -p "$kobj"
    cd "$kdir"
    make O="$kobj" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$defconfig"

    return $?
}
```

**错误处理**：
- 检查内核源码目录是否存在
- 检查defconfig文件是否存在
- 配置失败时返回错误码

### 3. check_kernel_built()

**功能**：检查内核是否已编译

**签名**：
```bash
check_kernel_built <kernel_type>
```

**检查项目**：
```bash
# 关键文件检查
- ${kobj}/.config                    # 内核配置
- ${kobj}/include/generated/autoconf.h  # 自动配置头文件
- ${kobj}/Module.symvers             # 模块符号表
- ${kobj}/arch/arm/boot/zImage       # 内核镜像（可选）
```

**错误输出**：
```
========================================
❌ 内核未正确编译
========================================
内核类型: mainline (linux_mainline)
内核目录: /path/to/third_party/linux_mainline
输出目录: /path/to/out/mainline/linux

缺少以下文件：
  - 内核配置文件: .config
  - autoconf.h
  - Module.symvers (需要运行 modules_prepare)

💡 解决方案：
   1. 完整编译内核：
      cd /path/to/third_party/linux_mainline
      make O=/path/to/out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)

   2. 或者使用快速编译（仅生成必要文件）：
      cd /path/to/third_party/linux_mainline
      make O=/path/to/out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare

========================================
```

### 4. build_driver_module()

**功能**：编译驱动模块

**签名**：
```bash
build_driver_module <driver_dir> <output_dir> <kernel_type>
```

**实现逻辑**：
```bash
build_driver_module() {
    local driver_dir="$1"
    local output_dir="$2"
    local kernel_type="$3"

    # 获取内核配置
    local IFS='|'
    read -r kernel_name kobj_dir defconfig kernel_desc <<< "${KERNEL_CONFIGS[$kernel_type]}"

    local kdir="${DRIVER_PROJECT_ROOT}/third_party/${kernel_name}"
    local kobj="${DRIVER_PROJECT_ROOT}/${kobj_dir}"

    # 编译
    cd "$driver_dir"
    make ARCH="$ARCH" \
         CROSS_COMPILE="$CROSS_COMPILE" \
         -C "$kdir" \
         M="$driver_dir" \
         O="$kobj" \
         modules

    # 复制产物
    for ko_file in *.ko; do
        cp "$ko_file" "$output_dir/"
    done
}
```

**编译参数说明**：
- `-C "$kdir"`：指定内核源码目录
- `M="$driver_dir"`：指定要编译的模块目录
- `O="$kobj"`：指定输出目录
- `modules`：编译模块目标

### 5. build_device_tree()

**功能**：编译设备树（两阶段编译）

**签名**：
```bash
build_device_tree <driver_dir> <output_dir> <kernel_type>
```

**编译流程**：
```bash
build_device_tree() {
    # 1. 查找设备树文件
    local dts_files=()
    if [[ -d "$device_tree_dir" ]]; then
        dts_files=($(find "$device_tree_dir" -maxdepth 1 -name "*.dts" -type f))
    fi

    # 2. 设置include路径
    local dts_include_dirs="${kdir}/arch/arm/boot/dts"
    dts_include_dirs="${dts_include_dirs} ${kdir}/arch/arm/boot/dts/nxp/imx"
    dts_include_dirs="${dts_include_dirs} ${kdir}/include"
    dts_include_dirs="${dts_include_dirs} $board_dts_dir"

    # 3. 编译每个设备树文件
    for dts_file in "${dts_files[@]}"; do
        # 阶段1：gcc预处理
        gcc -E -nostdinc -P -x assembler-with-cpp \
            -I "${kdir}/arch/arm/boot/dts" \
            -I "${kdir}/arch/arm/boot/dts/nxp/imx" \
            -I "${kdir}/include" \
            -I "$board_dts_dir" \
            -undef -D__DTS__ \
            -o "$dtc_tmp" "$dts_file"

        # 阶段2：dtc编译
        dtc -I dts -O dtb \
            -i "${kdir}/arch/arm/boot/dts" \
            -i "${kdir}/arch/arm/boot/dts/nxp/imx" \
            -o "$dtb_file" "$dtc_tmp"

        # 清理临时文件
        rm -f "$dtc_tmp"
    done
}
```

**两阶段编译详解**：

| 阶段 | 工具 | 输入 | 输出 | 作用 |
|-----|------|------|------|------|
| 1 | gcc | .dts | 预处理后的.dts | 处理宏定义、include |
| 2 | dtc | 预处理后的.dts | .dtb | 生成二进制设备树 |

**设备树查找策略**：
```
优先级1: driver/device_tree/<board>/<driver>/*.dts  (新位置)
优先级2: driver/<driver>/<board>/*.dts              (旧位置)
```

### 6. generate_build_info()

**功能**：生成构建信息文件

**签名**：
```bash
generate_build_info <driver_dir> <output_dir> <kernel_type>
```

**输出格式**：
```txt
驱动构建信息
================
构建时间: 2026-04-07 19:00:00
构建用户: user@hostname
内核类型: mainline (linux_mainline)
驱动目录: /path/to/driver/example-driver/alpha-board

产物文件:
  - example-driver.ko (12K)
  - imx6ull-aes-example-driver.dtb (1K)
```

### 7. clean_driver_artifacts()

**功能**：清理构建产物

**签名**：
```bash
clean_driver_artifacts <output_dir>
```

## 日志系统

### 日志函数

```bash
log_info()  # 信息 - 绿色
log_error() # 错误 - 红色
log_warn()  # 警告 - 黄色
log_debug() # 调试 - 蓝色 (需要DEBUG=1)
```

### 使用示例

```bash
# 启用调试输出
DEBUG=1 ./scripts/driver_helper/build_driver.sh driver

# 在脚本中
log_debug "当前驱动目录: $driver_dir"
log_info "开始编译驱动..."
log_warn "设备树文件不存在，跳过"
log_error "编译失败"
```

## 调用示例

### 被build_driver.sh调用

```bash
# 在build_driver.sh中
source "${SCRIPT_DIR}/../lib/driver_buildlib.sh"

# 调用构建函数
build_specific_driver() {
    local driver="$1"
    local board="${2:-alpha-board}"
    local kernel="${3:-$DEFAULT_KERNEL_TYPE}"

    driver_build "$driver" "$board" "build" "$kernel"
}
```

### 被自定义脚本调用

```bash
#!/bin/bash
# 自定义构建脚本

# 加载构建库
source /path/to/imx-forge/scripts/lib/driver_buildlib.sh

# 批量构建
for driver in driver1 driver2 driver3; do
    driver_build "$driver" "alpha-board" "build" "mainline"
done
```

## 扩展开发

### 添加新的构建步骤

```bash
# 在driver_buildlib.sh中添加新函数
build_custom_artifact() {
    local driver_dir="$1"
    local output_dir="$2"

    log_info "构建自定义产物..."
    # 自定义构建逻辑
    cp "$driver_dir/custom.txt" "$output_dir/"
}

# 在driver_build()中调用
driver_build() {
    # ... 现有逻辑
    build_custom_artifact "$driver_dir" "$output_dir"
}
```

### 添加新的内核类型

```bash
# 在脚本开头添加配置
KERNEL_CONFIGS[custom-kernel]="linux_custom|out/custom|custom_defconfig|自定义内核"

# 立即可用
driver_build "driver" "board" "build" "custom-kernel"
```

## 最佳实践

### 1. 错误处理

```bash
# ❌ 不好的做法
my_function() {
    some_command
}

# ✅ 好的做法
my_function() {
    if ! some_command; then
        log_error "命令执行失败"
        return 1
    fi
}
```

### 2. 日志记录

```bash
# ❌ 不好的做法
echo "building driver"

# ✅ 好的做法
log_info "构建驱动: $driver_name"
log_debug "驱动目录: $driver_dir"
```

### 3. 参数验证

```bash
# ❌ 不好的做法
my_function() {
    cd "$1"
}

# ✅ 好的做法
my_function() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_error "目录不存在: $dir"
        return 1
    fi
    cd "$dir"
}
```

## 故障排查

### 常见问题

#### 1. 内核未配置

**症状**：
```
[ERROR] 内核未配置
```

**解决**：
```bash
# 自动配置（脚本会自动执行）
cd third_party/linux_mainline
make O=../../out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx_aes_mainline_defconfig
```

#### 2. 内核未编译

**症状**：
```
[ERROR] 内核未正确编译
缺少以下文件：
  - Module.symvers
```

**解决**：
```bash
# 快速准备
cd third_party/linux_mainline
make O=../../out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare

# 或完整编译
make O=../../out/mainline/linux ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)
```

#### 3. 设备树编译失败

**症状**：
```
[WARN] 设备树编译失败
```

**解决**：
```bash
# 启用调试输出
DEBUG=1 ./scripts/driver_helper/build_driver.sh driver

# 查看详细错误信息
```

## 相关文档

- **[系统总览](../driver_helper/overview.md)** - 系统概况
- **[架构设计](../driver_helper/architecture.md)** - 架构原理
- **[工作流程](../driver_helper/workflow.md)** - 使用指南

---

**返回目录** → [README](../driver_helper/README.md)
