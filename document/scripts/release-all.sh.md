# release-all.sh - 迷你 Linux 发行版统一构建脚本详解

## 脚本概述

`release-all.sh` 是 IMX-Forge 项目中用于构建完整迷你 Linux 发行版的**唯一 release 编排入口**。它按 5 个阶段依次构建 U-Boot、Linux 内核、buildroot rootfs，并完成校验与镜像打包，最终生成可直接烧录的系统镜像。

`release-all.sh` 只负责**调度与产物校验**；真正的编译由 `scripts/build_helper/build-*.sh` 完成，release 编排（reset 净源码、打 patch、建 release 分支、可复现时间戳、build_info.txt）由这些脚本在 `--release` 模式下通过共享库 [`scripts/lib/release.sh`](./lib/release.sh) 触发。曾经存在的 `scripts/release_builder/` 编排层已并入这条统一链路，不再单独存在。

### 核心功能

- **分阶段构建**：将完整系统构建分为 5 个独立阶段，便于调试和增量构建
- **双内核轨**：支持 NXP BSP（`linux-imx`，默认）与上游 mainline（`--mainline`）
- **单阶段执行**：可以只执行特定阶段（`--stage N`），方便单独重建某个组件
- **断点续构**：`--continue` 跳过已完成的阶段
- **快速构建**：`--fast-build` 跳过 distclean
- **多介质镜像**：`--boot-media emmc|sd|both` 控制 Stage 5 产出
- **自动归档**：每次全量构建前自动归档旧的 `release-latest` 目录
- **便捷链接**：在 `images/` 目录创建可烧录镜像的符号链接

### 构建流程概览

```
release-all.sh
    ├─ Stage 1: U-Boot Bootloader   ── build_helper/build-uboot.sh        --release
    ├─ Stage 2: Linux Kernel        ── build_helper/build-{linux,mainline-linux}.sh --release [--fast-build]
    ├─ Stage 3: RootFS via buildroot── build_helper/build-buildroot.sh
    ├─ Stage 4: RootFS 验证闸门     ── varified_rootfs_ok.sh
    └─ Stage 5: SD/eMMC 镜像        ── image_builder/build_imx6ull_image.sh
```

> Stage 1/2 的 `--release` 让 `build-*.sh` 经 `lib/release.sh` 先做 release 编排（reset 净源码→打 patch→建 release 分支→设 SOURCE_DATE_EPOCH→写 build_info.txt），再走编译。Stage 3 的 rootfs 走 overlay，不需要这套 git 编排，直接由 buildroot 构建。

### 依赖关系

```
release-all.sh
    ├─ scripts/build_helper/build-uboot.sh          (Stage 1)
    ├─ scripts/build_helper/build-linux.sh          (Stage 2, NXP imx 轨)
    ├─ scripts/build_helper/build-mainline-linux.sh (Stage 2, mainline 轨)
    ├─ scripts/build_helper/build-buildroot.sh      (Stage 3)
    ├─ scripts/varified_rootfs_ok.sh                (Stage 4)
    ├─ scripts/image_builder/build_imx6ull_image.sh (Stage 5)
    ├─ scripts/lib/logging.sh
    ├─ scripts/lib/release.sh   (build-*.sh --release 调用的 release 编排库)
    └─ third_party/
        ├─ uboot-imx/
        ├─ linux-imx/          (默认轨)   或  linux_mainline/  (--mainline)
        └─ buildroot/
```

## 参数说明

### 命令行参数

```bash
./scripts/release-all.sh [OPTIONS]
```

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--fast-build` | 传递给 Linux 构建，跳过 distclean | 关闭 |
| `--mainline` | Stage 2 构建上游 mainline 内核（默认走 NXP BSP `linux-imx`） | 关闭 |
| `--boot-media M` | Stage 5 镜像介质：`emmc` / `sd` / `both` | `emmc`（或 `DEFAULT_BOOT_MEDIA`） |
| `--continue` | 从现有 `release-latest` 继续，跳过已完成的阶段 | 关闭 |
| `--stage N` | 仅执行指定阶段（1-5），不指定则执行所有阶段 | 全部执行 |
| `--help, -h` | 显示帮助信息 | - |

### 构建阶段说明

| 阶段 | 名称 | 调用 | 主要产物 / 校验 |
|------|------|------|-----------------|
| 1 | U-Boot | `build-uboot.sh --release` | `u-boot-dtb.imx` |
| 2 | Linux | `build-linux.sh` 或 `build-mainline-linux.sh`（`--release`） | `zImage`、`*.dtb`、`build_info.txt`（含 `Kernel Track:`） |
| 3 | RootFS（buildroot） | `build-buildroot.sh` | `rootfs/bin/busybox` |
| 4 | RootFS 验证闸门 | `varified_rootfs_ok.sh` | rootfs 完整性（失败即中止） |
| 5 | 镜像打包 | `build_imx6ull_image.sh` | `${device}-${media}.img` |

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DEFAULT_DEVICE_TREE` | 设备树名（软链 / dtb / 镜像命名） | `imx6ull-aes` |
| `DEFAULT_BOOT_MEDIA` | Stage 5 默认介质 | `emmc` |
| `DEFAULT_IMAGE_SIZE_MB` | 传给 image builder 的固定镜像大小（可选） | - |
| `OUTPUT_DIR` | 各阶段输出目录（由脚本为每个 stage 注入子进程） | `out/release-latest/<component>` |
| `BUILD_OUTPUT_DIR` | 总构建输出目录 | `out/release-latest` |
| `CROSS_COMPILE` | 交叉编译器前缀 | `arm-none-linux-gnueabihf-` |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  0. 初始化                                                   │
│     解析参数 → 设置目录 → 加载日志库                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  1. 确定构建阶段                                             │
│     --stage N(1-5) 校验 → 否则 stages=(1 2 3 4 5)            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 子模块就绪检查                                           │
│     ensure_submodules_initialized(按 stage/track)            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 准备输出目录                                             │
│     release-latest 存在 → --continue 续用 / 否则归档为        │
│     release-YYYYMMDD-HHMMSS(Stage 4/5 单跑时不归档)          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 依次执行阶段(--continue 时跳过已完成)                     │
│     Stage 1 → 2 → 3 → 4 → 5                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. create_symlinks + show_summary                           │
│     images/ 软链 → 产物清单 → 使用说明                        │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### show_usage()

显示帮助。关键示例：

```bash
./scripts/release-all.sh                            # 全量构建
./scripts/release-all.sh --stage 1                  # 仅 U-Boot
./scripts/release-all.sh --continue --stage 5       # 基于现有产物出镜像
./scripts/release-all.sh --continue --stage 5 --boot-media sd
./scripts/release-all.sh --mainline --stage 2       # mainline 内核入 release 布局
./scripts/release-all.sh --stage 2 --fast-build     # 跳过 distclean
```

#### ensure_submodules_initialized()

按要跑的 stage 与内核轨，检查所需子模块是否初始化（`third_party/uboot-imx`、`linux-imx` 或 `linux_mainline`、`buildroot`）。缺失则提示 `git submodule update --init --recursive <path>` 并退出。

#### stage_1_uboot()

```bash
export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/uboot"
bash "${SCRIPT_DIR}/build_helper/build-uboot.sh" --release
# 校验:${OUTPUT_DIR}/u-boot-dtb.imx 存在
```

`build-uboot.sh --release` 经 `lib/release.sh` 完成 reset→patch→release 分支→编译→`build_info.txt`。

#### stage_2_linux()

```bash
export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/linux"
local build_script="${SCRIPT_DIR}/build_helper/build-linux.sh"
[[ "${KERNEL_TRACK}" == "mainline" ]] && build_script="${SCRIPT_DIR}/build_helper/build-mainline-linux.sh"
local build_args=(--release)
[[ ${FAST_BUILD} -eq 1 ]] && build_args+=(--fast-build)
bash "${build_script}" "${build_args[@]}"
# 校验:zImage + dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb + build_info.txt(含 "Kernel Track: ${KERNEL_TRACK}")
```

mainline 轨下，`build_info.txt` 缺 `Kernel Track: mainline` 会**硬退出**。

#### stage_3_rootfs()

```bash
bash "${SCRIPT_DIR}/build_helper/build-buildroot.sh"
# 校验:${BUILD_OUTPUT_DIR}/rootfs/bin/busybox 可执行
```

buildroot 一次性构建 busybox + 用户空间（原手搓 rootfs / build-busybox.sh 已退役）。**默认产出最小 rootfs、不含 Qt6**（补 Qt6 见下文「Qt6 rootfs」小节）。

#### stage_4_rootfs()

```bash
bash "${SCRIPT_DIR}/varified_rootfs_ok.sh" --rootfs-dir="${BUILD_OUTPUT_DIR}/rootfs"
# 失败即 exit 1（issue #76：不再吞掉 rootfs 校验失败）
```

独立校验闸门。overlay 合并已由 buildroot `BR2_ROOTFS_OVERLAY` 在 Stage 3 完成，`merge_overlay_rootfs.sh` 已退役。

#### stage_5_image()

```bash
media_list=(emmc sd)  # --boot-media both;否则单个
for media in ...; do
    bash "${SCRIPT_DIR}/image_builder/build_imx6ull_image.sh" \
        --release-dir="${BUILD_OUTPUT_DIR}" \
        --device-tree="${DEFAULT_DEVICE_TREE}" \
        --boot-media="${media}"
done
# 产物:${DEFAULT_DEVICE_TREE}-${media}.img
```

#### create_symlinks() / show_summary()

`images/` 下创建 `u-boot-dtb.imx`、`zImage`、`${DEFAULT_DEVICE_TREE}.dtb` 软链（DTB 缺失只 warn 不致命）。summary 列出目录结构与镜像清单，并提示 NFS 挂载用 `scripts/manual_mount_nfs.sh`。

#### is_stage_completed()

`--continue` 模式下判断各 stage 是否已完成（Stage 2 要求 `build_info.txt` 含当前 `KERNEL_TRACK`，因此切轨重跑会被正确识别为未完成）。

#### main()

协调整流程：解析参数 → 校验 boot-media → 确定 stages → 子模块检查 → 输出目录处理（归档/续用）→ 循环跑 stage（`--continue` 跳过已完成）→ symlinks → summary。

## 输出目录结构

```
out/release-latest/
├── uboot/                         # U-Boot 产物
│   ├── u-boot-dtb.imx            # 可烧录 U-Boot 镜像
│   ├── u-boot-dtb.bin
│   ├── u-boot.dtb
│   └── build_info.txt            # (--release 生成)
├── linux/                         # Linux 内核产物
│   ├── arch/arm/boot/
│   │   ├── zImage
│   │   └── dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb
│   ├── vmlinux
│   ├── System.map
│   └── build_info.txt            # 含 Kernel Track: imx|mainline
├── buildroot/                     # buildroot 构建树(rootfs 源)
├── rootfs/                        # 完整根文件系统
│   ├── bin/busybox
│   ├── sbin/  lib/  usr/  etc/(inittab fstab ...)  ...
└── images/                        # 便捷符号链接
    ├── u-boot-dtb.imx -> ../uboot/u-boot-dtb.imx
    ├── zImage -> ../linux/arch/arm/boot/zImage
    ├── ${DEFAULT_DEVICE_TREE}.dtb -> ../linux/.../${DEFAULT_DEVICE_TREE}.dtb
    └── ${DEFAULT_DEVICE_TREE}-${media}.img   # Stage 5 产物
```

### 归档目录

全量构建（非 `--continue`、非单跑 Stage 4/5）时，旧 `release-latest` 归档为 `out/release-YYYYMMDD-HHMMSS`。

## 使用示例

### 基本用法

```bash
./scripts/release-all.sh                           # 全量构建（NXP imx 轨）
./scripts/release-all.sh --mainline                # 全量构建（mainline 轨）
./scripts/release-all.sh --stage 1                 # 仅 U-Boot
./scripts/release-all.sh --mainline --stage 2      # 仅 mainline 内核
./scripts/release-all.sh --stage 3                 # 仅 buildroot rootfs
./scripts/release-all.sh --continue --stage 5      # 基于现有产出打镜像
./scripts/release-all.sh --continue --stage 5 --boot-media both  # eMMC+SD
./scripts/release-all.sh --fast-build              # 跳过 distclean
```

### 典型工作流程

```bash
# 首次完整构建
git submodule update --init --recursive
./scripts/release-all.sh
ls -la out/release-latest/images/

# 改了内核驱动后快速重建
./scripts/release-all.sh --stage 2 --fast-build

# 断点续构（跳过已完成阶段）
./scripts/release-all.sh --continue
```

### Qt6 rootfs（可选，默认不含）

`release-all.sh` 默认产出最小 rootfs（不含 Qt6，约 15min）。需要 Qt6 全模块时，在**已有构建上增量补**——前面编译的 busybox / glibc / 各库全部保留，只新增编译 Qt6 及其依赖（约 2-4h）：

```bash
# 1. 增量补 Qt6 到 out/release-latest/rootfs（默认路径，与 release-all 一致）
./scripts/build_helper/build-buildroot.sh --with-qt6
#    或:BUILDROOT_QT6=1 ./scripts/build_helper/build-buildroot.sh

# 2. 用带 Qt6 的 rootfs 重打包镜像
./scripts/release-all.sh --continue --stage 5
```

要点：

- **不会白费前面的编译**：buildroot 增量构建，已构建的包跳过，只加 Qt6。
- **为什么不是 `release-all.sh --continue --qt6`**：`release-all.sh` 目前不透传 `--qt6`；且 `--continue` 见 `rootfs/bin/busybox` 存在会判定 Stage 3 已完成而跳过 rootfs 重建。所以直接调 `build-buildroot.sh --with-qt6` 重做 rootfs，再用 `--continue --stage 5` 出镜像。
- **想从干净状态全量重建**（更慢）：先 `./scripts/build_helper/build-buildroot.sh --clean`，再 `--with-qt6`。
- Qt6 fragment：`rootfs/buildroot/fragments/qt6.config`（CI 由 `compile-support-3rd-party` label 触发）。

### 自定义设备树

```bash
DEFAULT_DEVICE_TREE=custom-dtb ./scripts/release-all.sh
```

## 故障排除

### 子模块未初始化

```
[ERROR] <name> submodule is not initialized: <path>
```

```bash
git submodule update --init --recursive <path>
```

### Stage 2 build_info / Kernel Track 校验失败

mainline 轨下 `build_info.txt` 必须含 `Kernel Track: mainline`。该字段由 `lib/release.sh` 的 `release_finalize` 写入——仅在 `--release` 模式生成。若手动绕过 release 流程会出现此错，确认通过 `release-all.sh` 或 `build-*.sh --release` 调用。

### Stage 4 RootFS 验证失败

```
[ERROR] Stage 4: RootFS verification failed
```

buildroot rootfs 未构建完整。回到 Stage 3：`./scripts/release-all.sh --stage 3`，再重跑 Stage 4。Stage 4 失败会立即中止（不再吞错，见 issue #76）。

### 阶段号无效

```
[ERROR] Invalid stage number: 6 (must be 1-5)
```

阶段号范围是 1-5。

### 调试

```bash
bash -x ./scripts/release-all.sh --stage 2          # 跟踪执行
./scripts/build_helper/build-uboot.sh               # 分步裸跑(无 --release,不动源码)
```

## 设计决策说明

- **为什么 release-all 是唯一编排入口**：曾经存在 `scripts/release_builder/` 作为独立编排层，与 `build_helper/` 形成"双轨"。现已将编排能力下沉到 `scripts/lib/release.sh`，由 `build-*.sh --release` 触发，`release_builder/` 整层删除——分步构建与一键 release 共用同一套脚本，靠 `--release` 切换编排。
- **为什么分阶段**：灵活性（单独重建）、可调试、增量效率。
- **为什么自动归档**：非破坏性、可回退、可对比。
- **为什么 Stage 4 独立闸门**：rootfs 校验失败必须中止，避免带病 rootfs 进入镜像（issue #76）。

## 相关文档

- [build-uboot.sh](./build_helper/build-uboot.sh) - U-Boot 构建（`--release` 模式）
- [build-linux.sh](./build_helper/build-linux.sh) - NXP BSP 内核构建
- [build-mainline-linux.sh](./build_helper/build-mainline-linux.sh) - mainline 内核构建
- [build-buildroot.sh](./build_helper/build-buildroot.sh) - buildroot rootfs 构建
- [release.sh](./lib/release.sh) - release 编排共享库
- [varified_rootfs_ok.sh](./varified_rootfs_ok.sh) - RootFS 验证闸门
- [progress.sh](./lib/progress.sh) - buildmeter 进度条库

## 更新日志

| 日期 | 更新内容 |
|------|----------|
| 2026-07-10 | 全量重写：5 阶段、buildroot rootfs、build_helper --release + lib/release.sh 统一架构；删除已退役的 BusyBox/merge_overlay/release_builder 描述 |
