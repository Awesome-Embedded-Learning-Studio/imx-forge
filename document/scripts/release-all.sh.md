# release-all.sh - 迷你 Linux 发行版统一构建脚本详解

## 脚本概述

`release-all.sh` 是 IMX-Forge 项目中用于构建完整迷你 Linux 发行版的统一构建脚本。它按照分阶段的方式依次构建 U-Boot、Linux 内核、BusyBox 用户空间和完整的 RootFS，最终生成可以直接用于启动开发板的系统镜像。

### 核心功能

- **分阶段构建**：将完整的系统构建分为 4 个独立阶段，便于调试和增量构建
- **快速构建支持**：支持 Linux 内核的快速构建模式（跳过 distclean）
- **单阶段执行**：可以只执行特定阶段，方便单独重建某个组件
- **自动归档**：每次构建前自动归档旧的 release-latest 目录
- **便捷链接**：在 images/ 目录创建所有可烧录镜像的符号链接
- **NFS 导出**：自动将构建的 rootfs 导出为 rootfs/nfs，便于 NFS 启动

### 设计理念

`release-all.sh` 遵循"自动化、可追溯、易调试"的设计原则：

1. **自动化**：一条命令完成从 bootloader 到 rootfs 的完整构建
2. **可追溯**：构建产物组织清晰，每个组件有独立目录
3. **易调试**：支持单阶段构建和快速构建，提高开发效率
4. **非侵入式**：归档旧构建而不是删除，保留历史

### 构建流程概览

```
release-all.sh
    ├─ Stage 1: U-Boot Bootloader
    │   └─ build_release_uboot.sh
    ├─ Stage 2: Linux Kernel
    │   └─ build_release_linux.sh [--fast-build]
    ├─ Stage 3: BusyBox Userland
    │   └─ build_release_busybox.sh
    └─ Stage 4: RootFS Completion
        ├─ varified_rootfs_ok.sh
        └─ merge_overlay_rootfs.sh
```

### 依赖关系

```
release-all.sh
    ├─ scripts/release_builder/build_release_uboot.sh
    ├─ scripts/release_builder/build_release_linux.sh
    ├─ scripts/release_builder/build_release_busybox.sh
    ├─ scripts/varified_rootfs_ok.sh
    ├─ scripts/merge_overlay_rootfs.sh
    ├─ scripts/lib/logging.sh
    └─ third_party/
        ├─ uboot-imx/
        ├─ linux-imx/
        └─ busybox/
```

## 参数说明

### 命令行参数

```bash
./scripts/release-all.sh [OPTIONS]
```

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--fast-build` | 传递给 Linux 构建，跳过 distclean 以加快构建速度 | 关闭 |
| `--stage N` | 仅执行指定阶段（1-4），不指定则执行所有阶段 | 全部执行 |
| `--help, -h` | 显示帮助信息 | - |

### 构建阶段说明

| 阶段 | 名称 | 说明 | 主要产物 |
|------|------|------|----------|
| 1 | U-Boot | 构建 U-Boot 引导程序 | `u-boot-dtb.imx` |
| 2 | Linux | 构建 Linux 内核 | `zImage`, `.dtb` |
| 3 | BusyBox | 构建并安装 BusyBox 用户空间 | `busybox`, rootfs 基础结构 |
| 4 | RootFS | 完成 RootFS（配置、第三方依赖） | 完整的 rootfs |

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `OUTPUT_DIR` | 各阶段的输出目录（由脚本自动设置） | `out/release-latest/<component>` |
| `INSTALL_DIR` | BusyBox 安装目录 | `out/release-latest/rootfs` |
| `ROOTFS_DIR` | RootFS 目录 | `out/release-latest/rootfs` |
| `BUILD_OUTPUT_DIR` | 总构建输出目录 | `out/release-latest` |
| `CROSS_COMPILE` | 交叉编译器前缀 | `arm-none-linux-gnueabihf-` |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  0. 初始化阶段                                               │
│     - 解析命令行参数                                         │
│     - 设置目录路径                                           │
│     - 加载日志库                                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  1. 确定构建阶段                                             │
│     - 检查 --stage 参数                                      │
│     - 验证阶段号有效性（1-4）                                │
│     - 确定要执行的阶段列表                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 准备输出目录                                             │
│     - 检查 release-latest 是否存在                           │
│     - 存在则归档为 release-YYYYMMDD-HHMMSS                   │
│     - 创建新的 release-latest 目录                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 执行构建阶段                                             │
│     - Stage 1: 构建 U-Boot                                  │
│     - Stage 2: 构建 Linux                                   │
│     - Stage 3: 构建 BusyBox                                 │
│     - Stage 4: 完成 RootFS                                  │
│   （如果指定 --stage 则只执行对应阶段）                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 创建便捷链接                                             │
│     - 在 images/ 目录创建所有镜像的符号链接                  │
│     - 创建 rootfs/nfs 符号链接用于 NFS 导出                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. 显示构建摘要                                             │
│     - 显示构建产物位置                                       │
│     - 显示可烧录镜像列表                                     │
│     - 显示使用说明                                           │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### show_usage()

**作用**：显示脚本的使用帮助信息。

**输出内容**：

```bash
Usage: ./scripts/release-all.sh [OPTIONS]

Options:
  --fast-build      Pass --fast-build to linux build (skip distclean)
  --stage N         Run only specific stage (1-4)
  --help, -h        Show this help message

Stages:
  1  U-Boot bootloader
  2  Linux kernel
  3  BusyBox userland
  4  RootFS completion with third-party dependencies

Examples:
  ./scripts/release-all.sh                          # Build all stages
  ./scripts/release-all.sh --stage 1                # Build U-Boot only
  ./scripts/release-all.sh --fast-build             # Build all with fast build mode
  ./scripts/release-all.sh --stage 2 --fast-build   # Build Linux with fast build mode

Output directory: out/release-latest/
```

#### stage_1_uboot()

**作用**：构建 U-Boot 引导程序。

**执行流程**：

```bash
# 1. 设置输出目录
export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/uboot"

# 2. 调用 U-Boot 发布构建脚本
bash "${SCRIPT_DIR}/release_builder/build_release_uboot.sh"

# 3. 验证构建产物
if [[ -f "${OUTPUT_DIR}/u-boot-dtb.imx" ]]; then
    log_info "U-Boot build successful"
else
    log_error "U-Boot build failed - u-boot-dtb.imx not found"
    exit 1
fi
```

**输出示例**：

```
[build-all] ========================================
[build-all] Stage 1/4: Building U-Boot
[build-all] ========================================
[build-all] Output directory: /home/user/imx-forge/out/release-latest/uboot

[STEP] 1/5: Resetting U-Boot Submodule
...
[build-all] U-Boot build successful
```

**关键产物**：

| 文件 | 说明 |
|------|------|
| `u-boot-dtb.imx` | 带设备树的 U-Boot 镜像（用于 i.MX） |
| `u-boot-dtb.bin` | 原始二进制格式 |
| `u-boot.dtb` | 设备树文件 |
| `build_info.txt` | 构建信息 |

#### stage_2_linux()

**作用**：构建 Linux 内核。

**执行流程**：

```bash
# 1. 设置输出目录
export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/linux"

# 2. 根据 FAST_BUILD 决定构建模式
if [[ ${FAST_BUILD} -eq 1 ]]; then
    log_info "Fast build mode enabled"
    bash "${SCRIPT_DIR}/release_builder/build_release_linux.sh" --fast-build
else
    bash "${SCRIPT_DIR}/release_builder/build_release_linux.sh"
fi

# 3. 验证构建产物
if [[ -f "${OUTPUT_DIR}/arch/arm/boot/zImage" ]]; then
    log_info "Linux build successful"
else
    log_error "Linux build failed - zImage not found"
    exit 1
fi
```

**快速构建模式**：

当使用 `--fast-build` 时：
- 跳过 `make distclean`
- 保留之前的编译配置和中间文件
- 适用于小修改后的快速重编译

**输出示例**：

```
[build-all] ========================================
[build-all] Stage 2/4: Building Linux Kernel
[build-all] ========================================
[build-all] Output directory: /home/user/imx-forge/out/release-latest/linux
[build-all] Fast build mode enabled

[STEP] 1/5: Resetting Linux Submodule
...
[build-all] Linux build successful
```

**关键产物**：

| 文件 | 说明 |
|------|------|
| `arch/arm/boot/zImage` | 压缩的内核镜像 |
| `arch/arm/boot/dts/*.dtb` | 设备树文件 |
| `vmlinux` | 未压缩的内核 ELF 文件 |
| `System.map` | 内核符号表 |
| `build_info.txt` | 构建信息 |

#### stage_3_busybox()

**作用**：构建 BusyBox 用户空间并安装到 rootfs。

**执行流程**：

```bash
# 1. 设置输出和安装目录
export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/busybox"
export INSTALL_DIR="${BUILD_OUTPUT_DIR}/rootfs"

# 2. 调用 BusyBox 发布构建脚本
bash "${SCRIPT_DIR}/release_builder/build_release_busybox.sh"

# 3. 验证构建产物
if [[ -f "${OUTPUT_DIR}/busybox" ]]; then
    log_info "BusyBox build successful"
else
    log_error "BusyBox build failed - busybox binary not found"
    exit 1
fi

if [[ -f "${INSTALL_DIR}/bin/busybox" ]]; then
    log_info "BusyBox installed to rootfs"
else
    log_warn "BusyBox installation may have issues"
fi
```

**输出示例**：

```
[build-all] ========================================
[build-all] Stage 3/4: Building BusyBox
[build-all] ========================================
[build-all] Output directory: /home/user/imx-forge/out/release-latest/busybox
[build-all] Install directory: /home/user/imx-forge/out/release-latest/rootfs

[STEP] 1/5: Resetting BusyBox Submodule
...
[build-all] BusyBox build successful
[build-all] BusyBox installed to rootfs
```

**关键产物**：

| 文件 | 说明 |
|------|------|
| `busybox/busybox` | BusyBox 二进制文件 |
| `busybox/.config` | BusyBox 配置文件 |
| `rootfs/` | 安装后的 rootfs 目录结构 |

#### stage_4_rootfs()

**作用**：完成 RootFS，包括配置文件和第三方依赖。

**执行流程**：

```bash
# 1. 设置 rootfs 目录
export ROOTFS_DIR="${BUILD_OUTPUT_DIR}/rootfs"
mkdir -p "$ROOTFS_DIR"

# 2. 验证并补全 rootfs
bash "${SCRIPT_DIR}/varified_rootfs_ok.sh" --rootfs-dir="${ROOTFS_DIR}"

# 3. 合并 overlay rootfs
bash "${SCRIPT_DIR}/merge_overlay_rootfs.sh" --rootfs-dir="${ROOTFS_DIR}" --overlay-name=rootfs

log_info "RootFS completion successful"
```

**这个阶段做了什么**：

1. **验证目录结构**：检查 bin、sbin、usr 等必需目录
2. **创建配置文件**：fstab、inittab、rcS 等
3. **安装第三方依赖**：执行 third_party_install 下的脚本
4. **合并 overlay**：将 rootfs/overlay/rootfs 的内容合并进来

**输出示例**：

```
[build-all] ========================================
[build-all] Stage 4/4: Completing RootFS
[build-all] ========================================
[build-all] RootFS directory: /home/user/imx-forge/out/release-latest/rootfs
[build-all] Running Command: scripts/varified_rootfs_ok.sh --rootfs-dir=out/release-latest/rootfs

[INFO] Step 1: Safety checks...
[INFO] Step 2: Verifying required directories...
[INFO] Step 3: Creating directory structure...
[INFO] Step 4: Creating configuration files...
[INFO] Step 5: Running third-party installations...
[INFO] Step 6: Verifying completion...

[build-all] Merging Rootfs Overlay from rootfs/overlay/rootfs to out/release-latest/rootfs
[build-all] RootFS completion successful
```

#### create_symlinks()

**作用**：创建便捷的符号链接，方便访问构建产物。

**创建的链接**：

```bash
# 1. 创建 images 目录
local images_dir="${BUILD_OUTPUT_DIR}/images"
mkdir -p "${images_dir}"

# 2. U-Boot 镜像链接
if [[ -f "${BUILD_OUTPUT_DIR}/uboot/u-boot-dtb.imx" ]]; then
    ln -sf "../uboot/u-boot-dtb.imx" "${images_dir}/"
fi

# 3. Linux 内核链接
if [[ -f "${BUILD_OUTPUT_DIR}/linux/arch/arm/boot/zImage" ]]; then
    ln -sf "../linux/arch/arm/boot/zImage" "${images_dir}/"
fi

# 4. 设备树链接
if [[ -f "${BUILD_OUTPUT_DIR}/linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb" ]]; then
    ln -sf "../linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb" "${images_dir}/"
fi

# 5. NFS rootfs 导出
local nfs_dir="${PROJECT_ROOT}/rootfs/nfs"
rm -rf "${nfs_dir}"
mkdir -p "$(dirname "${nfs_dir}")"
ln -sf "${BUILD_OUTPUT_DIR}/rootfs" "${nfs_dir}"
```

**输出示例**：

```
[build-all] ========================================
[build-all] Creating convenience symlinks
[build-all] ========================================
[build-all]   + images/u-boot-dtb.imx
[build-all]   + images/zImage
[build-all]   + images/imx6ull-14x14-evk-emmc.dtb
[build-all] Symlinks created in out/release-latest/images/
[build-all] Exporting NFS rootfs...
[build-all]   + rootfs/nfs/ -> out/release-latest/rootfs/ (NFS export ready)
```

#### show_summary()

**作用**：显示构建完成后的摘要信息。

**显示内容**：

```bash
# 1. 构建产物位置
log_info "Build artifacts location: ${BUILD_OUTPUT_DIR}/"

# 2. 目录结构
log_info "Directory structure:"
log_info "  uboot/        - U-Boot bootloader"
log_info "  linux/        - Linux kernel"
log_info "  busybox/      - BusyBox userland"
log_info "  rootfs/       - Complete root filesystem"
log_info "  images/       - Flashable images (symlinks)"

# 3. 可烧录镜像列表
log_info "Flashable images:"
for f in "${images_dir}"/*; do
    log_info "  - $(basename "$f")"
done

# 4. 使用说明
log_info "To use the rootfs:"
log_info "  1. Export via NFS: ${BUILD_OUTPUT_DIR}/rootfs"
log_info "  2. Or copy to SD card"
```

**输出示例**：

```
[build-all] ========================================
[build-all] Build Summary
[build-all] ========================================
[build-all]
[build-all] Build artifacts location: out/release-latest/
[build-all]
[build-all] Directory structure:
[build-all]   uboot/        - U-Boot bootloader
[build-all]   linux/        - Linux kernel
[build-all]   busybox/      - BusyBox userland
[build-all]   rootfs/       - Complete root filesystem
[build-all]   images/       - Flashable images (symlinks)
[build-all]
[build-all] Flashable images:
[build-all]   - u-boot-dtb.imx
[build-all]   - zImage
[build-all]   - imx6ull-14x14-evk-emmc.dtb
[build-all]
[build-all] To use the rootfs:
[build-all]   1. Export via NFS: out/release-latest/rootfs
[build-all]   2. Or copy to SD card
```

#### main()

**作用**：主函数，协调整个构建流程。

**执行步骤**：

```bash
# 1. 确定要执行的阶段
if [[ -n "${SPECIFIC_STAGE}" ]]; then
    if [[ "${SPECIFIC_STAGE}" =~ ^[1-4]$ ]]; then
        stages=("${SPECIFIC_STAGE}")
        log_info "Running stage ${SPECIFIC_STAGE} only"
    else
        log_error "Invalid stage number: ${SPECIFIC_STAGE} (must be 1-4)"
        exit 1
    fi
else
    stages=(1 2 3 4)
    log_info "Running all stages (1-4)"
fi

# 2. 归档旧的构建
if [[ -d "${BUILD_OUTPUT_DIR}" ]]; then
    local datetime=$(date +%Y%m%d-%H%M%S)
    local archive_dir="${PROJECT_ROOT}/out/release-${datetime}"
    log_info "Archiving existing ${BUILD_OUTPUT_DIR} -> ${archive_dir}"
    mv "${BUILD_OUTPUT_DIR}" "${archive_dir}"
fi
mkdir -p "${BUILD_OUTPUT_DIR}"

# 3. 执行各阶段
for stage in "${stages[@]}"; do
    case "${stage}" in
        1) stage_1_uboot ;;
        2) stage_2_linux ;;
        3) stage_3_busybox ;;
        4) stage_4_rootfs ;;
    esac
done

# 4. 创建便捷链接
create_symlinks

# 5. 显示摘要
show_summary
```

## 输出目录结构

### 完整目录树

```
out/release-latest/
├── uboot/                         # U-Boot 构建产物
│   ├── u-boot-dtb.imx            # 可烧录的 U-Boot 镜像
│   ├── u-boot-dtb.bin
│   ├── u-boot.dtb
│   ├── SPL                       # SPL 镜像（如果使用）
│   └── build_info.txt            # 构建信息
│
├── linux/                         # Linux 内核构建产物
│   ├── arch/arm/boot/
│   │   ├── zImage                # 压缩内核镜像
│   │   └── dts/
│   │       ├── imx6ull-14x14-evk-emmc.dtb
│   │       └── ...
│   ├── vmlinux                   # 未压缩内核
│   ├── System.map                # 符号表
│   └── build_info.txt
│
├── busybox/                       # BusyBox 构建产物
│   ├── busybox                   # BusyBox 二进制
│   ├── .config                   # 配置文件
│   ├── busybox_unstripped        # 未剥离符号的版本
│   └── build_info.txt
│
├── rootfs/                        # 完整的根文件系统
│   ├── bin/                      # 基本命令（BusyBox 链接）
│   │   ├── busybox
│   │   ├── ls
│   │   ├── sh
│   │   └── ...
│   ├── sbin/                     # 系统管理命令
│   ├── lib/                      # 共享库
│   ├── usr/                      # 用户程序
│   │   └── lib/
│   ├── etc/                      # 配置文件
│   │   ├── fstab
│   │   ├── inittab
│   │   ├── init.d/
│   │   │   └── rcS
│   │   └── profile
│   ├── dev/                      # 设备文件（空）
│   ├── proc/                     # proc 挂载点
│   ├── sys/                      # sysfs 挂载点
│   ├── tmp/                      # 临时文件
│   └── linuxrc -> bin/busybox    # 初始化链接
│
└── images/                        # 便捷符号链接目录
    ├── u-boot-dtb.imx -> ../uboot/u-boot-dtb.imx
    ├── zImage -> ../linux/arch/arm/boot/zImage
    └── imx6ull-14x14-evk-emmc.dtb -> ../linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb
```

### 归档目录

每次构建前，旧的 `release-latest` 会被归档：

```
out/
├── release-20250315-143022/       # 第一次构建的归档
├── release-20250315-150518/       # 第二次构建的归档
└── release-latest/                # 当前构建（符号链接或实际目录）
```

### NFS 导出

脚本自动创建 `rootfs/nfs` 符号链接指向当前构建的 rootfs：

```
rootfs/nfs -> out/release-latest/rootfs
```

这可以直接用于 NFS 导出，无需修改 NFS 服务器配置。

## 使用示例

### 基本用法

#### 构建完整系统

```bash
# 构建所有阶段
./scripts/release-all.sh
```

#### 只构建特定组件

```bash
# 只构建 U-Boot
./scripts/release-all.sh --stage 1

# 只构建 Linux 内核
./scripts/release-all.sh --stage 2

# 只构建 BusyBox
./scripts/release-all.sh --stage 3

# 只完成 RootFS
./scripts/release-all.sh --stage 4
```

#### 快速构建

```bash
# 使用快速构建模式构建所有组件
# Linux 阶段会跳过 distclean
./scripts/release-all.sh --fast-build

# 快速重建 Linux 内核
./scripts/release-all.sh --stage 2 --fast-build
```

### 典型工作流程

#### 首次完整构建

```bash
# 1. 确保子模块已初始化
git submodule update --init --recursive

# 2. 执行完整构建
./scripts/release-all.sh

# 3. 查看构建产物
ls -la out/release-latest/images/
```

#### 增量开发

```bash
# 1. 修改 Linux 驱动代码
vim third_party/linux-imx/drivers/xxx/my_driver.c

# 2. 快速重建 Linux
./scripts/release-all.sh --stage 2 --fast-build

# 3. 更新 rootfs（如果需要）
./scripts/release-all.sh --stage 4
```

#### 只更新配置

```bash
# 1. 修改 rootfs overlay
vim rootfs/overlay/rootfs/etc/myconfig.conf

# 2. 只执行 RootFS 完成阶段
./scripts/release-all.sh --stage 4
```

### 输出示例

#### 完整构建输出

```bash
$ ./scripts/release-all.sh
[build-all] ========================================
[build-all] Mini Distribution Build
[build-all] ========================================
[build-all] Project root: /home/user/imx-forge
[build-all] Build output: /home/user/imx-forge/out/release-latest
[build-all] Cross compiler: arm-none-linux-gnueabihf-gcc
[build-all] ========================================
[build-all]
[build-all] Running all stages (1-4)
[build-all]

[build-all] ========================================
[build-all] Stage 1/4: Building U-Boot
[build-all] ========================================
[build-all] Output directory: /home/user/imx-forge/out/release-latest/uboot

[STEP] 1/5: Resetting U-Boot Submodule
[INFO] Detecting default branch...
[INFO] Default branch: lf_v2025.04
...
[build-all] U-Boot build successful

[build-all] ========================================
[build-all] Stage 2/4: Building Linux Kernel
[build-all] ========================================
[build-all] Output directory: /home/user/imx-forge/out/release-latest/linux

[STEP] 1/5: Resetting Linux Submodule
...
[build-all] Linux build successful

[build-all] ========================================
[build-all] Stage 3/4: Building BusyBox
[build-all] ========================================
[build-all] Output directory: /home/user/imx-forge/out/release-latest/busybox
[build-all] Install directory: /home/user/imx-forge/out/release-latest/rootfs

[STEP] 1/5: Resetting BusyBox Submodule
...
[build-all] BusyBox build successful
[build-all] BusyBox installed to rootfs

[build-all] ========================================
[build-all] Stage 4/4: Completing RootFS
[build-all] ========================================
[build-all] RootFS directory: /home/user/imx-forge/out/release-latest/rootfs
[build-all] Running Command: scripts/varified_rootfs_ok.sh --rootfs-dir=out/release-latest/rootfs

[INFO] Step 1: Safety checks...
[INFO] Step 2: Verifying required directories...
[INFO] Step 3: Creating directory structure...
[INFO] Step 4: Creating configuration files...
[INFO] Step 5: Running third-party installations...
[INFO] Step 6: Verifying completion...

[build-all] Merging Rootfs Overlay from rootfs/overlay/rootfs to out/release-latest/rootfs
[build-all] RootFS completion successful

[build-all] ========================================
[build-all] Creating convenience symlinks
[build-all] ========================================
[build-all]   + images/u-boot-dtb.imx
[build-all]   + images/zImage
[build-all]   + images/imx6ull-14x14-evk-emmc.dtb
[build-all] Symlinks created in out/release-latest/images/
[build-all] Exporting NFS rootfs...
[build-all]   + rootfs/nfs/ -> out/release-latest/rootfs/ (NFS export ready)

[build-all] ========================================
[build-all] Build Summary
[build-all] ========================================
[build-all]
[build-all] Build artifacts location: out/release-latest/
[build-all]
[build-all] Directory structure:
[build-all]   uboot/        - U-Boot bootloader
[build-all]   linux/        - Linux kernel
[build-all]   busybox/      - BusyBox userland
[build-all]   rootfs/       - Complete root filesystem
[build-all]   images/       - Flashable images (symlinks)
[build-all]
[build-all] Flashable images:
[build-all]   - u-boot-dtb.imx
[build-all]   - zImage
[build-all]   - imx6ull-14x14-evk-emmc.dtb
[build-all]
[build-all] To use the rootfs:
[build-all]   1. Export via NFS: out/release-latest/rootfs
[build-all]   2. Or copy to SD card
[build-all]

[build-all] ========================================
[build-all] Build completed successfully!
[build-all] ========================================
```

## 配置选项

### 硬编码配置

```bash
# 交叉编译器前缀
CROSS_COMPILE=arm-none-linux-gnueabihf-

# 构建输出目录
BUILD_OUTPUT_DIR="${PROJECT_ROOT}/out/release-latest"

# 构建选项
FAST_BUILD=0              # 快速构建标志
SPECIFIC_STAGE=""         # 特定阶段号
```

### 自定义配置

#### 修改交叉编译器

编辑脚本中的 `CROSS_COMPILE` 变量：

```bash
# 修改这一行
CROSS_COMPILE=aarch64-linux-gnu-
```

#### 修改输出目录

编辑 `BUILD_OUTPUT_DIR`：

```bash
# 修改这一行
BUILD_OUTPUT_DIR="${PROJECT_ROOT}/out/my-release"
```

#### 修改阶段顺序

编辑 `main()` 函数中的阶段顺序：

```bash
# 例如先构建 rootfs 组件，再构建内核
stages=(3 4 2 1)  # BusyBox -> RootFS -> Linux -> U-Boot
```

## 故障排除

### 常见错误

#### 错误 1：子模块未初始化

```
fatal: not a git repository: /home/user/imx-forge/third_party/linux-imx/.git
```

**原因**：子模块未初始化。

**解决方法**：

```bash
# 初始化并更新子模块
git submodule update --init --recursive

# 或者单独初始化
cd third_party/linux-imx
git submodule init
git submodule update
```

#### 错误 2：U-Boot 构建失败

```
[ERROR] U-Boot build failed - u-boot-dtb.imx not found
```

**可能原因**：

1. 工具链不正确
2. 配置文件缺失
3. 设备树文件缺失

**解决方法**：

```bash
# 检查 U-Boot 构建日志
ls -la out/release-latest/uboot/

# 手动运行 U-Boot 构建调试
./scripts/release_builder/build_release_uboot.sh
```

#### 错误 3：Linux 构建失败

```
[ERROR] Linux build failed - zImage not found
```

**可能原因**：

1. 配置错误
2. 编译错误
3. 架构不匹配

**解决方法**：

```bash
# 检查 Linux 构建日志
ls -la out/release-latest/linux/arch/arm/boot/

# 使用快速构建查看详细错误
./scripts/release-all.sh --stage 2 --fast-build
```

#### 错误 4：BusyBox 构建失败

```
[ERROR] BusyBox build failed - busybox binary not found
```

**可能原因**：

1. 配置文件不存在
2. 交叉编译工具链问题
3. 安装目录权限问题

**解决方法**：

```bash
# 检查配置文件
ls -la out/release-latest/busybox/.config

# 检查安装目录
ls -la out/release-latest/rootfs/bin/

# 手动运行 BusyBox 构建调试
./scripts/release_builder/build_release_busybox.sh
```

#### 错误 5：RootFS 验证失败

```
[ERROR] Missing required directories: bin sbin usr
```

**原因**：BusyBox 未正确安装。

**解决方法**：

```bash
# 重新构建 BusyBox
./scripts/release-all.sh --stage 3

# 验证安装
ls -la out/release-latest/rootfs/bin/busybox
```

#### 错误 6：阶段号无效

```
[ERROR] Invalid stage number: 5 (must be 1-4)
```

**原因**：指定的阶段号超出范围。

**解决方法**：

```bash
# 使用有效的阶段号 (1-4)
./scripts/release-all.sh --stage 1  # 正确
./scripts/release-all.sh --stage 4  # 正确
```

#### 错误 7：归档目录已存在

```
mv: cannot move 'out/release-latest' to 'out/release-20250315-143022': Directory not empty
```

**原因**：归档目标目录已存在（罕见情况）。

**解决方法**：

```bash
# 手动删除或移动冲突目录
rm -rf out/release-20250315-143022

# 或者手动归档
mv out/release-latest out/release-$(date +%Y%m%d-%H%M%S)
```

### 调试技巧

#### 查看详细构建信息

```bash
# 使用 bash 调试模式运行
bash -x ./scripts/release-all.sh
```

#### 只构建特定阶段进行调试

```bash
# 只构建问题阶段
./scripts/release-all.sh --stage 2
```

#### 检查构建产物

```bash
# 检查 U-Boot
ls -la out/release-latest/uboot/

# 检查 Linux
ls -la out/release-latest/linux/arch/arm/boot/

# 检查 BusyBox
ls -la out/release-latest/busybox/

# 检查 rootfs
ls -la out/release-latest/rootfs/
```

#### 手动执行子脚本

```bash
# 单独执行 U-Boot 构建
cd /home/user/imx-forge
./scripts/release_builder/build_release_uboot.sh

# 单独执行 Linux 构建
./scripts/release_builder/build_release_linux.sh

# 单独执行 BusyBox 构建
./scripts/release_builder/build_release_busybox.sh

# 单独执行 rootfs 验证
./scripts/varified_rootfs_ok.sh --rootfs-dir=out/release-latest/rootfs

# 单独执行 overlay 合并
./scripts/merge_overlay_rootfs.sh --rootfs-dir=out/release-latest/rootfs --overlay-name=rootfs
```

## 设计决策说明

### 为什么分阶段构建

分阶段构建的好处：

1. **灵活性**：可以单独重建某个组件
2. **调试性**：问题定位更容易
3. **效率**：修改代码后只重建相关部分
4. **可维护性**：每个阶段职责清晰

### 为什么自动归档旧构建

1. **历史保留**：可以回退到之前的构建
2. **对比分析**：比较不同版本的差异
3. **非破坏性**：不会因为误操作丢失构建
4. **可追溯**：从时间戳可以知道构建时间

### 为什么创建符号链接

1. **便捷访问**：所有可烧录文件集中在一个目录
2. **固定路径**：images/ 目录内容稳定，脚本/工具可以硬编码
3. **节省空间**：不复制文件，只创建链接
4. **NFS 导出**：rootfs/nfs 链接方便直接使用

### 为什么支持快速构建

1. **开发效率**：小修改后快速重编译
2. **节省时间**：跳过清理，只重编译修改的文件
3. **保持配置**：保留之前 .config 和编译状态

### 为什么委托给子脚本

1. **代码复用**：子脚本可独立使用
2. **关注分离**：各组件构建逻辑独立维护
3. **一致性**：确保发布构建和单独构建使用相同逻辑

## 扩展和定制

### 添加新的构建阶段

```bash
# 在脚本中添加新阶段
stage_5_mycomponent() {
    log_info "========================================="
    log_info "Stage 5/5: Building My Component"
    log_info "========================================="

    export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/mycomponent"

    bash "${SCRIPT_DIR}/build_mycomponent.sh"

    log_info "My component build successful"
}

# 在 main() 中添加调用
main() {
    # ...
    stages=(1 2 3 4 5)  # 添加阶段 5
    # ...

    case "${stage}" in
        1) stage_1_uboot ;;
        2) stage_2_linux ;;
        3) stage_3_busybox ;;
        4) stage_4_rootfs ;;
        5) stage_5_mycomponent ;;  # 新增
    esac
    # ...
}
```

### 添加构建后操作

```bash
# 在 main() 函数末尾添加
main() {
    # ... 现有代码 ...

    # 添加自定义后处理
    post_build_steps
}

post_build_steps() {
    log_info "Running post-build steps..."

    # 例如：计算校验和
    cd "${BUILD_OUTPUT_DIR}"
    sha256sum images/* > images/SHA256SUMS

    # 例如：生成构建报告
    ./scripts/generate_build_report.sh "${BUILD_OUTPUT_DIR}"

    log_info "Post-build steps completed"
}
```

### 添加构建前检查

```bash
# 在 main() 函数开头添加
main() {
    # 添加预检查
    pre_build_checks

    # ... 现有代码 ...
}

pre_build_checks() {
    log_info "Running pre-build checks..."

    # 检查磁盘空间
    local available=$(df -BM . | tail -1 | awk '{print $4}' | sed 's/M//')
    if [[ $available -lt 5000 ]]; then
        log_error "Insufficient disk space: ${available}MB < 5000MB"
        exit 1
    fi

    # 检查工具链
    if ! which ${CROSS_COMPILE}gcc &>/dev/null; then
        log_error "Cross compiler not found: ${CROSS_COMPILE}gcc"
        exit 1
    fi

    log_info "Pre-build checks passed"
}
```

### 添加并行构建支持

```bash
# 修改 main() 函数支持并行构建
main() {
    # ... 现有代码 ...

    # 并行执行某些阶段（例如 U-Boot 和 Linux 可以并行）
    if [[ "${PARALLEL_BUILD}" -eq 1 ]]; then
        # Stage 1 和 2 并行
        stage_1_uboot &
        local uboot_pid=$!

        stage_2_linux &
        local linux_pid=$!

        # 等待两个阶段完成
        wait $uboot_pid
        wait $linux_pid

        # 继续后续阶段
        stage_3_busybox
        stage_4_rootfs
    else
        # 串行执行
        for stage in "${stages[@]}"; do
            # ...
        done
    fi
}
```

### 添加构建缓存

```bash
# 添加 ccache 支持
stage_2_linux() {
    log_info "Stage 2/4: Building Linux Kernel"

    export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/linux"

    # 启用 ccache
    export CCACHE_DIR="${PROJECT_ROOT}/.ccache"
    export PATH="/usr/lib/ccache:${PATH}"

    # ... 现有代码 ...
}
```

## 最佳实践

### 开发工作流

1. **首次构建**：完整构建所有组件
   ```bash
   ./scripts/release-all.sh
   ```

2. **代码修改**：只重建修改的组件
   ```bash
   # 修改 Linux 代码后
   ./scripts/release-all.sh --stage 2 --fast-build
   ```

3. **配置修改**：只重建 rootfs
   ```bash
   ./scripts/release-all.sh --stage 4
   ```

4. **完整测试**：定期完整重建
   ```bash
   ./scripts/release-all.sh
   ```

### 版本管理

```bash
# 构建特定版本
git checkout v0.1.0
./scripts/release-all.sh

# 归档版本
mv out/release-latest out/release-v0.1.0

# 构建开发版本
git checkout develop
./scripts/release-all.sh
```

### 持续集成

在 CI/CD 中使用：

```bash
#!/bin/bash
set -e

# CI 构建脚本
export NPROC=$(nproc)

# 完整构建
./scripts/release-all.sh

# 验证构建产物
test -f out/release-latest/images/u-boot-dtb.imx
test -f out/release-latest/images/zImage
test -f out/release-latest/rootfs/bin/busybox

# 计算校验和
cd out/release-latest
sha256sum images/* > images/SHA256SUMS

# 归档
tar czf ../release-${CI_COMMIT_TAG:-latest}.tar.gz .
```

## 相关文档

- [build_release_uboot.sh](release_builder/build_release_uboot.sh) - U-Boot 发布构建脚本
- [build_release_linux.sh](release_builder/build_release_linux.sh) - Linux 发布构建脚本
- [build_release_busybox.sh](release_builder/build_release_busybox.sh) - BusyBox 发布构建脚本
- [varified_rootfs_ok.sh](./varified_rootfs_ok.sh) - RootFS 验证脚本
- [merge_overlay_rootfs.sh](./merge_overlay_rootfs.sh) - RootFS 叠加层合并脚本
- 构建系统概述 - 构建系统总体介绍
- 快速入门 - 项目快速入门指南

## 更新日志

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-03-19 | 1.0 | 初始文档版本 |

---

> **文档生成时间**: 2026-03-19
> **对应脚本版本**: commit a1b2c3d
