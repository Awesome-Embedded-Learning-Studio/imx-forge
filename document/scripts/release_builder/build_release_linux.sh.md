# build_release_linux.sh - Linux内核发布构建脚本详解

## 脚本概述

`build_release_linux.sh` 是 IMX-Forge 项目中用于创建可重现的 Linux 内核发布版本的工具。与普通构建不同，发布构建强调可重现性、隔离性和完整的构建信息记录。

### 核心功能

- **完整的子模块重置**：清理所有未提交的更改
- **从默认分支重建**：确保基于干净的上游状态
- **补丁应用**：在干净的基础上应用定制补丁
- **发布分支创建**：为每次发布创建独立的分支
- **构建信息记录**：生成详细的构建元数据
- **可重现构建支持**：使用 SOURCE_DATE_EPOCH 确保二进制一致性

### 设计理念

发布构建与开发构建有本质区别：

| 方面 | 开发构建 | 发布构建 |
|------|----------|----------|
| 源码状态 | 可能有未提交更改 | 完全干净 |
| 构建环境 | 可能残留旧文件 | 完全清理 |
| 产物版本 | 时间戳变化 | 可重现 |
| 构建信息 | 简单 | 详细记录 |
| 分支管理 | 功能分支 | 发布分支 |

**发布构建的设计原则**：

1. **可重现性**：相同输入产生相同输出
2. **可追溯性**：每步操作都有记录
3. **隔离性**：不影响开发环境
4. **验证性**：可验证构建的正确性

### 依赖关系

```
build_release_linux.sh
    ├─ scripts/build_helper/build-linux.sh (实际构建脚本)
    ├─ patches/linux-imx/linux-imx-latest.patch (定制补丁)
    └─ third_party/linux-imx (Linux 内核子模块)
```

## 参数说明

### 命令行参数

```bash
./scripts/release_builder/build_release_linux.sh [release_version]
```

| 参数 | 必需 | 说明 | 默认值 |
|------|------|------|--------|
| `release_version` | 否 | 发布版本号 | `unknown` |

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `SOURCE_DATE_EPOCH` | 构建时间戳（秒） | `1609459200` (2021-01-01) |
| `LC_ALL` | 区域设置 | `C` |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  1. 初始化阶段                                               │
│     - 设置目录路径                                           │
│     - 设置环境变量（可重现构建）                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 子模块重置阶段                                           │
│     - 检测默认分支 (lf-6.12.y)                               │
│     - 获取最新状态                                           │
│     - 切换到默认分支                                         │
│     - 重置到上游版本                                         │
│     - 清理未跟踪文件                                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 子模块验证阶段                                           │
│     - 记录当前提交                                           │
│     - 记录 Linux 版本                                        │
│     - 记录分支信息                                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 发布分支创建阶段                                         │
│     - 生成发布分支名                                         │
│     - 删除已存在的同名分支                                   │
│     - 创建并切换到发布分支                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. 补丁应用阶段                                             │
│     - 检查补丁文件 (linux-imx-latest.patch)                  │
│     - 应用补丁或警告继续                                     │
│     - 记录修改的文件数                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  6. 构建阶段                                                 │
│     - 委托给 build-linux.sh                                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  7. 构建信息生成阶段                                         │
│     - 生成 build_info.txt                                    │
│     - 记录所有元数据                                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  8. 报告阶段                                                 │
│     - 显示构建产物                                           │
│     - 显示构建信息                                           │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### Step 1: 重置 Linux 子模块

**作用**：将 Linux 内核子模块完全重置到上游状态。

**执行步骤**：

```bash
# 1. 检测默认分支
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
: "${DEFAULT_BRANCH:=lf-6.12.y}"  # 失败时的后备值

# 2. 获取最新状态
git fetch origin || true

# 3. 清理当前工作目录
git reset --hard HEAD 2>/dev/null || true
git clean -ffdx

# 4. 切换到默认分支
git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"

# 5. 重置到上游
git reset --hard "origin/${DEFAULT_BRANCH}"

# 6. 再次清理
git clean -ffdx
```

**命令解释**：

- `git fetch origin`：获取远程仓库的最新状态（使用 || true 忽略网络错误）
- `git checkout -B`：强制创建或重置分支到 origin 分支
- `git reset --hard`：硬重置到上游提交，丢弃所有本地更改
- `git clean -ffdx`：
  - `-f`：强制删除文件
  - `-f`：两次（更强制）
  - `-d`：也删除目录
  - `-x`：也删除通常忽略的文件（.gitignore 中的）

**为什么这样彻底**：

发布构建需要确保：

1. 没有残留的更改
2. 没有未跟踪的文件
3. 完全基于上游状态
4. 构建环境可重现

**输出示例**：

```
[STEP] 1/5: Resetting Linux Submodule
[INFO] Detecting default branch...
[INFO] Default branch: lf-6.12.y
[INFO] Fetching from upstream...
[INFO] Cleaning working directory...
[INFO] Switching to lf-6.12.y...
[INFO] Resetting to origin/lf-6.12.y...
[INFO] Linux submodule reset complete
```

#### Step 2: 验证子模块状态

**作用**：记录子模块的详细状态信息。

**记录内容**：

```bash
# 当前提交的 SHA-1
LINUX_COMMIT=$(git rev-parse HEAD)

# Linux 版本描述
LINUX_DESCRIBE=$(git describe --tags --always 2>/dev/null || echo "no-tags")

# 当前分支名
LINUX_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

**输出示例**：

```
[STEP] 2/5: Verifying Submodule State
[INFO] Linux commit: a1b2c3d4e5f6789...
[INFO] Linux version: lf-6.12.y-10-ga1b2c3d4
[INFO] Linux branch: lf-6.12.y
```

**这些信息的作用**：

1. **提交 SHA**：精确定位上游版本
2. **版本描述**：人类可读的版本标识
3. **分支名**：确认在正确的分支上

#### Step 3: 创建发布分支

**作用**：为本次发布创建独立的分支。

**分支命名规则**：

```bash
BRANCH_NAME="release-build-$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
```

**格式**：`release-build-YYYYMMDD-SHORTSHA`

**示例**：

- `release-build-20250315-a1b2c3d`
- `release-build-20250315-e5f6g7h`

**分支处理**：

如果同名分支已存在，先删除再创建：

```bash
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    log_info "Branch ${BRANCH_NAME} already exists, deleting it..."
    git branch -D "$BRANCH_NAME"
fi

git checkout -b "$BRANCH_NAME"
```

**为什么需要发布分支**：

1. **隔离**：不影响其他分支
2. **可追溯**：可以从分支名反推构建时间
3. **可验证**：可以检查分支状态确认构建

**输出示例**：

```
[STEP] 3/5: Creating Release Branch
[INFO] Creating branch: release-build-20250315-a1b2c3d
[INFO] Release branch created
```

#### Step 4: 应用补丁

**作用**：将定制补丁应用到干净的上游状态。

**补丁路径**：

```bash
PATCH="${PROJECT_ROOT}/patches/linux-imx/linux-imx-latest.patch"
```

**应用流程**：

```bash
# 1. 检查补丁文件是否存在
if [ ! -f "$PATCH" ]; then
    log_warn "Patch file not found: $PATCH"
    log_warn "Continuing build without patch..."
    PATCHED_FILES=0
    PATCH_NAME="None"
else
    # 2. 尝试直接应用
    if git apply --check "$PATCH" 2>/dev/null; then
        git apply "$PATCH"
        log_info "Patch applied successfully"
    else
        # 3. 失败时使用三向合并
        log_warn "Patch check failed. Trying with --3way..."
        if git apply --3way "$PATCH"; then
            log_info "Patch applied with --3way"
        else
            log_error "Failed to apply patch"
            exit 1
        fi
    fi

    # 4. 统计修改
    PATCHED_FILES=$(git diff --name-only HEAD 2>/dev/null | wc -l)
    PATCH_NAME=$(basename $PATCH)
    log_info "Modified files: ${PATCHED_FILES}"
fi
```

**两种应用方式**：

1. **git apply**：直接应用补丁，要求干净的基准
2. **git apply --3way**：三向合并，处理冲突

**与 U-Boot 脚本的差异**：

Linux 脚本在补丁不存在时发出警告但继续构建，而不是直接退出。这使得构建可以在没有补丁的情况下进行。

**输出示例**：

```
[STEP] 4/5: Applying Patch
[INFO] Applying patch: linux-imx-latest.patch
[INFO] Patch applied successfully
[INFO] Modified files: 25
```

**补丁冲突处理**：

如果 `--3way` 也失败，说明补丁与上游有严重冲突。需要：

1. 手动解决冲突
2. 更新补丁文件
3. 重新运行发布构建

#### Step 5: 构建 Linux

**作用**：委托给标准构建脚本执行实际编译。

**执行命令**：

```bash
cd "$PROJECT_ROOT"
log_info "Calling build-linux.sh..."
"${BUILD_HELPER_DIR}/build-linux.sh"
```

**为什么委托而不是直接构建**：

1. **代码复用**：避免重复构建逻辑
2. **一致性**：确保发布和开发使用相同的构建过程
3. **维护性**：构建逻辑只在一个地方

**输出**：

`build-linux.sh` 的完整输出，包括：

- 依赖检查
- 工具链验证
- 设备树检查
- 内核配置
- 编译过程
- 模块构建
- 产物验证

#### Step 6: 生成构建信息

**作用**：记录构建的完整元数据。

**生成位置**：

```bash
BUILD_INFO_FILE="${PROJECT_ROOT}/out/linux/build_info.txt"
```

**生成内容**：

```
========================================
Linux Release Build Information
========================================
Release Version: v0.1.0
Build Date: Fri Jan  1 00:00:00 UTC 2021
Source Date Epoch: 1609459200

Linux Information:
-------------------
Commit: a1b2c3d4e5f6789...
Version: lf-6.12.y-10-ga1b2c3d4
Branch: lf-6.12.y

Patch Information:
------------------
Patch: linux-imx-latest.patch
Files Modified: 25

Build Environment:
------------------
Build Host: build-server
User: builduser
Toolchain: arm-none-linux-gnueabihf-

========================================
```

**这些信息的用途**：

1. **版本追溯**：知道确切构建了什么
2. **问题复现**：可以重建相同版本
3. **质量保证**：验证构建的正确性

**输出示例**：

```
[INFO] Generating build info...
[INFO] Build info saved to: /home/user/imx-forge/out/linux/build_info.txt
```

## 可重现构建

### SOURCE_DATE_EPOCH

**作用**：设置构建的时间戳。

**为什么需要**：

通常构建过程会嵌入当前时间戳：

```
Built by user@host on 2025-03-15 10:30:45
```

这导致：

1. 每次构建产生不同的二进制
2. 无法验证构建是否可重现
3. 难以进行二进制比较

**解决方案**：

设置固定的时间戳：

```bash
export SOURCE_DATE_EPOCH=1609459200  # 2021-01-01 00:00:00 UTC
```

**如何工作**：

现代构建工具（gcc、make 等）会检查 `SOURCE_DATE_EPOCH`：

1. 如果设置，使用这个时间
2. 如果未设置，使用当前时间

**更新时间戳**：

每次发布应该更新：

```bash
# 2021-01-01 00:00:00 UTC
export SOURCE_DATE_EPOCH=1609459200

# 2025-03-15 00:00:00 UTC
export SOURCE_DATE_EPOCH=1740988800
```

**计算 SOURCE_DATE_EPOCH**：

```bash
date +%s --date='2025-03-15 00:00:00 UTC'
```

### LC_ALL=C

**作用**：设置区域为 C（标准 POSIX）。

**为什么需要**：

不同区域设置会影响：

1. 错误消息的语言
2. 日期和时间的格式
3. 字符排序顺序

这些差异会导致：

1. 不同的日志输出
2. 不同的错误处理
3. 不可预测的行为

**设置方法**：

```bash
export LC_ALL=C
```

## 使用示例

### 基本用法

```bash
# 创建发布版本
./scripts/release_builder/build_release_linux.sh v0.1.0
```

### 指定时间戳

```bash
# 使用特定时间戳
SOURCE_DATE_EPOCH=1740988800 ./scripts/release_builder/build_release_linux.sh v0.1.0
```

### 输出示例

```
[STEP] 1/5: Resetting Linux Submodule
[INFO] Detecting default branch...
[INFO] Default branch: lf-6.12.y
[INFO] Fetching from upstream...
[INFO] Cleaning working directory...
[INFO] Switching to lf-6.12.y...
[INFO] Resetting to origin/lf-6.12.y...
[INFO] Linux submodule reset complete

[STEP] 2/5: Verifying Submodule State
[INFO] Linux commit: a1b2c3d4e5f6789...
[INFO] Linux version: lf-6.12.y-10-ga1b2c3d4
[INFO] Linux branch: lf-6.12.y

[STEP] 3/5: Creating Release Branch
[INFO] Creating branch: release-build-20250315-a1b2c3d
[INFO] Release branch created

[STEP] 4/5: Applying Patch
[INFO] Applying patch: linux-imx-latest.patch
[INFO] Patch applied successfully
[INFO] Modified files: 25

[STEP] 5/5: Building Linux
[INFO] Calling build-linux.sh...
[INFO] Starting Linux kernel build for imx_aes_defconfig
...
[INFO] Build completed successfully!

[INFO] Generating build info...
[INFO] Build info saved to: out/linux/build_info.txt

========================================
Release Build Complete!
========================================

Build artifacts:
  - out/linux/arch/arm/boot/zImage
  - out/linux/vmlinux
  - out/linux/System.map

Build info:
  - out/linux/build_info.txt

For reproducible builds, use:
  SOURCE_DATE_EPOCH=1609459200
========================================
```

## 配置选项

### 硬编码路径

```bash
LINUX_DIR="${PROJECT_ROOT}/third_party/linux-imx"
PATCH_DIR="${PROJECT_ROOT}/patches/linux-imx"
PATCH="${PATCH_DIR}/linux-imx-latest.patch"
BUILD_INFO_FILE="${PROJECT_ROOT}/out/linux/build_info.txt"
```

### 默认分支后备值

```bash
: "${DEFAULT_BRANCH:=lf-6.12.y}"
```

## 故障排除

### 常见错误

#### 错误 1：补丁文件不存在

```
[WARN] Patch file not found: patches/linux-imx/linux-imx-latest.patch
[WARN] Continuing build without patch...
```

**说明**：这与 U-Boot 脚本不同，Linux 脚本会继续构建而不是退出。

**解决方法**：

```bash
# 检查补丁文件
ls -la patches/linux-imx/

# 如果需要补丁，使用 patch_maker.sh 生成
./scripts/patch_maker.sh --submodule_path=linux-imx
```

#### 错误 2：补丁应用失败

```
[ERROR] Failed to apply patch
```

**可能原因**：

1. 上游版本变化，补丁不兼容
2. 补丁格式错误

**解决方法**：

```bash
# 手动检查补丁
cd third_party/linux-imx
git apply --check ../../patches/linux-imx/linux-imx-latest.patch

# 查看冲突
git apply --stat ../../patches/linux-imx/linux-imx-latest.patch

# 手动解决冲突
git apply --3way ../../patches/linux-imx/linux-imx-latest.patch
# 解决冲突后
git add .
```

#### 错误 3：无法检测默认分支

```
[WARN] Could not detect default branch from origin/HEAD
```

**原因**：origin/HEAD 未设置

**解决方法**：

```bash
# 手动设置 origin/HEAD
cd third_party/linux-imx
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/lf-6.12.y

# 或修改脚本使用特定的默认分支
```

#### 错误 4：构建失败

```
[ERROR] Build failed
```

**可能原因**：

1. 工具链不正确
2. 依赖缺失
3. 配置错误

**解决方法**：

```bash
# 检查构建日志
cat out/linux/build.log

# 手动运行构建脚本调试
./scripts/build_helper/build-linux.sh
```

## 设计决策说明

### 为什么重置子模块而不是克隆新的

两种选择：

1. **重置现有子模块**：`git reset --hard && git clean`
2. **克隆新的子模块**：删除子模块目录，重新 clone

选择重置的原因：

1. **更快**：不需要重新下载对象
2. **节省带宽**：重用现有对象
3. **保留配置**：保持远程设置

### 为什么创建发布分支

而不是直接在默认分支上构建：

1. **可追溯**：发布分支有明确的命名
2. **不污染**：不影响默认分支
3. **可回滚**：可以返回到特定发布

### 为什么补丁缺失时继续构建

Linux 脚本与 U-Boot 脚本的行为差异：

- U-Boot 脚本：补丁缺失时退出
- Linux 脚本：补丁缺失时警告并继续

这个设计选择是因为：

1. **灵活性**：允许纯净的上游构建
2. **测试**：便于测试上游版本
3. **开发**：开发过程中可能不需要补丁

### 为什么委托给 build-linux.sh

而不是直接运行 make 命令：

1. **代码复用**：避免重复
2. **一致性**：使用相同的构建流程
3. **维护性**：构建逻辑在一处
4. **验证**：自动进行产物验证

## 与 build_release_uboot.sh 的差异

| 特性 | build_release_uboot.sh | build_release_linux.sh |
|------|------------------------|------------------------|
| 默认分支 | lf_v2025.04 | lf-6.12.y |
| 补丁文件 | charlies_board.patch | linux-imx-latest.patch |
| 补丁缺失行为 | 退出 | 警告并继续 |
| 产物目录 | out/uboot/ | out/linux/ |
| 构建产物 | u-boot-dtb.imx 等 | zImage, vmlinux 等 |

## 扩展和定制

### 添加构建后步骤

在脚本末尾添加自定义步骤：

```bash
# 在脚本最后添加
log_step "6/6: Post-build steps"

# 例如：计算校验和
cd out/linux
sha256sum arch/arm/boot/zImage > zImage.sha256

# 例如：复制到发布目录
mkdir -p releases/v0.1.0
cp arch/arm/boot/zImage releases/v0.1.0/
```

### 添加签名步骤

```bash
# 对构建产物签名
log_step "Signing build artifacts"
gpg --detach-sign --armor out/linux/arch/arm/boot/zImage
```

### 添加归档步骤

```bash
# 创建发布归档
log_step "Creating release archive"
tar czf releases/linux-v0.1.0.tar.gz \
    -C out/linux \
    arch/arm/boot/zImage \
    vmlinux \
    System.map \
    build_info.txt
```

### 添加模块打包步骤

```bash
# 打包内核模块
log_step "Packaging kernel modules"
cd out/linux
make modules_install INSTALL_MOD_PATH=../linux-modules
tar czf ../releases/linux-modules-v0.1.0.tar.gz -C ../linux-modules .
```

## 相关文档

- [Linux 构建脚本](../build_helper/build-linux.sh) - 实际使用的构建脚本
- [补丁生成工具](../patch_maker.sh) - 用于生成补丁的工具
- Linux 编译教程 - Linux 编译的详细原理
- [U-Boot 发布构建](./build_release_uboot.sh) - U-Boot 发布构建脚本文档
