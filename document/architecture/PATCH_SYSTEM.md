# IMX-Forge 补丁管理系统

> **本文档描述 IMX-Forge 项目中补丁管理的完整机制**
> 版本: v1.0
> 最后更新: 2026-03-15

---

## 目录

1. [系统概述](#系统概述)
2. [format-patch 与 series 规划](#format-patch-与-series-规划)
3. [补丁目录组织规范](#补丁目录组织规范)
4. [补丁版本管理](#补丁版本管理)
5. [自动化工具使用](#自动化工具使用)
6. [最佳实践](#最佳实践)
7. [故障排除](#故障排除)

---

## 系统概述

IMX-Forge 项目采用 **Git Submodule + Patch** 的混合管理模式，将第三方源码作为子模块引入，同时通过补丁文件跟踪所有定制修改。

### 设计理念

```
                    ┌─────────────────────────────────────┐
                    │         IMX-Forge 主仓库            │
                    │  (补丁 + 构建脚本 + 文档 + 板卡配置) │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │         Git Submodule 引用          │
                    │  ┌───────────────────────────────┐  │
                    │  │ third_party/linux-imx         │  │
                    │  │ third_party/uboot-imx         │  │
                    │  │ third_party/busybox           │  │
                    │  └───────────────────────────────┘  │
                    └──────────────────────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │       补丁应用流程 (Patch Apply)     │
                    │  patches/linux-imx/*.patch           │
                    │  patches/uboot-imx/*.patch           │
                    │  patches/busybox/*.patch             │
                    └──────────────────────────────────────┘
```

### 核心优势

| 特性 | 说明 |
|------|------|
| **可追溯性** | 每个补丁都关联到具体的 Git 提交，包含完整的变更上下文 |
| **上游同步** | 子模块可独立更新上游代码，补丁可重新应用 |
| **版本锁定** | 通过 `.gitmodules` 锁定子模块的具体提交 |
| **双轨并行** | 同时支持 linux-imx (NXP BSP) 和 mainline 内核两套补丁集 |
| **自动化** | 提供脚本自动化补丁生成和应用流程 |

---

## format-patch 与 series 规划

::: info 当前实现状态
当前 `scripts/apply_patches.sh` 采用简化策略：按文件名排序，仅应用目标补丁目录中最新的 `.patch` 文件。下文描述的 `series` 顺序应用机制是推荐架构和后续增强方向，不代表当前脚本已经完整实现。
:::

### Git format-patch 原理

`git format-patch` 是 Git 内置的补丁生成工具，能够将提交历史转换为标准邮箱格式的补丁文件。

#### 基本语法

```bash
# 生成单个提交的补丁
git format-patch -1 <commit-hash>

# 生成多个提交的补丁
git format-patch <start-commit>..<end-commit>

# 生成合并补丁（stdout 输出）
git format-patch <base>..<branch> --stdout > combined.patch

# 覆盖特定文件路径的补丁
git format-patch <base>..<branch> -- drivers/net/ethernet/
```

#### 补丁文件格式

```diff
From 638449c65d51b1c627eb6a447af5615fbfb6daea Mon Sep 17 00:00:00 2001
From: Charliechen114514 <725610365@qq.com>
Date: Sat, 14 Mar 2026 10:28:28 +0800
Subject: [PATCH 1/2] Patch OK

---
 arch/arm/boot/dts/nxp/imx/Makefile         |   1 +
 arch/arm/boot/dts/nxp/imx/imx6ull-aes.dts  |  44 ++
 arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi | 754 +++++++++++++++++++++
 arch/arm/configs/imx_aes_defconfig         | 600 ++++++++++++++++
 4 files changed, 1399 insertions(+)
 create mode 100644 arch/arm/boot/dts/nxp/imx/imx6ull-aes.dts
 create mode 100644 arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi
 create mode 100644 arch/arm/configs/imx_aes_defconfig

diff --git a/arch/arm/boot/dts/nxp/imx/Makefile b/arch/arm/boot/dts/nxp/imx/Makefile
index 89171be84f27..b35ddc6e8ddb 100644
--- a/arch/arm/boot/dts/nxp/imx/Makefile
+++ b/arch/arm/boot/dts/nxp/imx/Makefile
@@ -379,6 +379,7 @@ dtb-$(CONFIG_SOC_IMX6UL) += \
 	imx6ul-tx6ul-mainboard.dtb \
 	imx6ull-14x14-evk.dtb \
 	imx6ull-14x14-evk-emmc.dtb \
+	imx6ull-aes.dtb \
 	imx6ull-14x14-evk-btwifi.dtb \
 	imx6ull-14x14-evk-gpmi-weim.dtb \
```

#### 补丁文件结构说明

| 部分 | 说明 |
|------|------|
| **From 行** | 原始提交的完整 SHA1 哈希值 |
| **Author** | 提交者姓名和邮箱 |
| **Date** | 提交时间戳 |
| **Subject** | 补丁标题（支持 `[PATCH n/m]` 序号标记） |
| **统计行** | 变更文件数量和代码行增减 |
| **diff 块** | 具体的代码变更内容 |

### 系列文件 (Series) 机制

系列文件（`series`）是补丁应用顺序的配置文件，类似于 quilt 和 stgit 的管理方式。

#### Series 文件格式

```bash
# patches/linux-imx/series
# 格式: <patch-filename> [<options>]

# 001-050: 基础平台支持
0001-platform-base-support.patch
0002-device-tree-core.patch

# 051-100: 外设驱动
0051-ethernet-driver.patch -p1
0052-gpio-expansion.patch

# 101-150: 板卡特定
0101-alpha-board-config.patch
0102-alpha-display.patch
```

#### Series 文件选项

| 选项 | 说明 | 示例 |
|------|------|------|
| `-p<n>` | 设置路径前缀剥离层级 | `-p1` (默认), `-p0` |
| `--directory=<dir>` | 应用补丁前先切换目录 | `--directory=drivers` |
| `--strip=<n>` | 等同于 `-p` | `--strip=1` |
| `--postfix=<suffix>` | 文件扩展名后缀 | `--postfix=.orig` |

#### Series 文件的作用

1. **应用顺序控制**: 确保补丁按正确顺序应用
2. **条件应用**: 通过注释分组管理补丁
3. **版本追踪**: 在补丁文件名中嵌入版本信息
4. **自动化集成**: 后续构建脚本可读取 series 文件批量应用补丁

### 补丁命名规范

IMX-Forge 采用严格的补丁命名规范，确保可读性和可管理性。

#### 命名格式

```
[<轨道标签>-]<序号>-<组件>-<描述>-<版本信息>.patch
```

#### 命名示例

```
# linux-imx 轨道补丁
[linux-imx]-001-ethernet-fec-driver-v1.patch
[linux-imx]-002-device-tree-imx6ull-alpha.patch

# mainline 轨道补丁
[mainline]-001-arm-dts-imx6ull-basic.patch
[mainline]-002-clock-imx6ull-fix.patch

# U-Boot 补丁
[uboot-imx]-001-spl-board-init.patch
[uboot-imx]-002-mmc-support.patch
```

#### 命名规范详解

| 部分 | 说明 | 取值范围 | 示例 |
|------|------|----------|------|
| **轨道标签** | 标识补丁所属轨道 | `[linux-imx]`, `[mainline]`, `[uboot-imx]` | `[linux-imx]` |
| **序号** | 三位数字，控制应用顺序 | 001-999 | `001` |
| **组件** | 受影响的子系统 | `ethernet`, `gpio`, `mmc`, `dts` | `ethernet` |
| **描述** | 简短描述补丁目的 | 小写英文，用连字符连接 | `fec-driver` |
| **版本信息** | 可选版本标识 | `v1`, `v2`, `-YYYYMMDD` | `-v1` |

---

## 补丁目录组织规范

### 标准目录结构

```
patches/
├── .gitkeep                    # 保持空目录被 Git 跟踪
├── busybox/                    # Busybox 补丁集
│   ├── .gitkeep
│   ├── series                  # 补丁序列文件
│   └── *.patch                 # 具体补丁文件
├── linux-imx/                  # NXP BSP 内核补丁
│   ├── .gitkeep
│   ├── series
│   ├── [linux-imx]-001-*.patch
│   └── [linux-imx]-002-*.patch
├── linux-mainline/             # 主线内核补丁
│   ├── .gitkeep
│   ├── series
│   └── [mainline]-*.patch
├── uboot/                      # 主线 U-Boot 补丁
│   ├── .gitkeep
│   ├── series
│   └── *.patch
└── uboot-imx/                  # NXP U-Boot 补丁
    ├── .gitkeep
    ├── series
    └── [uboot-imx]-*.patch
```

### 目录组织原则

#### 1. 按上游来源分类

```
patches/
├── linux-imx/         # NXP 官方 linux-imx 仓库
├── linux-mainline/    # Linux 内核主线 (kernel.org)
├── uboot-imx/         # NXP 官方 uboot-imx 仓库
├── uboot/             # U-Boot 主线 (denx.de)
└── busybox/           # Busybox 官方仓库
```

#### 2. 按功能模块分组

对于大量补丁的情况，可在子目录内进一步分组：

```
patches/linux-imx/
├── 001-base/              # 基础平台支持
│   ├── 001-cpu.patch
│   └── 002-clock.patch
├── 002-drivers/           # 驱动支持
│   ├── 001-ethernet.patch
│   └── 002-gpio.patch
└── 003-board/             # 板卡特定
    ├── 001-alpha.patch
    └── 002-custom.patch
```

#### 3. 按版本组织

当需要维护多个版本的补丁时：

```
patches/linux-imx/
├── v5.15/
│   ├── series
│   └── *.patch
├── v6.1/
│   ├── series
│   └── *.patch
└── v6.6/
    ├── series
    └── *.patch
```

### 补丁轨道标签规范

补丁轨道标签用于区分不同上游来源的补丁。

| 标签 | 用途 | 对应上游 | 优先级 |
|------|------|----------|--------|
| `[linux-imx]` | NXP BSP 内核 | github.com/nxp-imx/linux-imx | 高（当前默认） |
| `[mainline]` | Linux 主线内核 | kernel.org | 中（长期目标） |
| `[uboot-imx]` | NXP U-Boot | github.com/nxp-imx/uboot-imx | 高（当前默认） |
| `[uboot]` | U-Boot 主线 | denx.de/u-boot | 低（未来支持） |

---

## 补丁版本管理

### 补丁版本追踪

#### 1. 基于 Git 的追踪

每个补丁文件应包含原始提交信息，确保可追溯到上游。

```bash
# 查看补丁对应的提交
git log --oneline --grep="补丁标题"

# 查看补丁影响的文件
git show --stat <commit-hash>

# 查看补丁的完整 diff
git show <commit-hash>
```

#### 2. 补丁版本号规范

补丁版本号采用语义化版本控制（Semantic Versioning）的简化形式：

```
<主版本>.<次版本>.<修订版本>
```

| 版本类型 | 说明 | 示例 |
|----------|------|------|
| **主版本** | 不兼容的 API 变更 | 1.0.0 -> 2.0.0 |
| **次版本** | 向下兼容的功能新增 | 1.0.0 -> 1.1.0 |
| **修订版本** | 向下兼容的问题修正 | 1.0.0 -> 1.0.1 |

#### 3. 变更日志维护

在补丁目录中维护 `CHANGELOG.md`：

```markdown
# Linux-imx 补丁变更日志

## [1.2.0] - 2026-03-15

### 新增
- FEC 以太网驱动 DMA 优化补丁
- 新增 i.MX6ULL Alpha 板卡设备树

### 变更
- GPIO 驱动补丁更新适配新内核版本

### 修复
- 修复 eMMC 补丁在 5.15 内核的编译警告

## [1.1.0] - 2026-02-01
...
```

### 补丁更新流程

#### 场景 1: 上游代码更新后补丁失效

```bash
# 1. 更新子模块到新版本
cd third_party/linux-imx
git fetch origin
git checkout rel/imx-5.15.72-2.1.0

# 2. 尝试应用补丁，识别冲突
cd ../../patches/linux-imx
git checkout 001-ethernet-driver.patch
patch -p1 < 001-ethernet-driver.patch --dry-run

# 3. 手动解决冲突后重新生成补丁
cd ../../third_party/linux-imx
# ... 手动编辑解决冲突 ...
git add -u
git commit -m "ethernet: update for new upstream version"

# 4. 使用自动化工具生成新补丁
cd ../../
./scripts/patch_maker.sh --submodule_path=linux-imx --output=patches/linux-imx/
```

#### 场景 2: 补丁内容需要修改

```bash
# 1. 在子模块分支上进行修改
cd third_party/linux-imx
git checkout -b my-feature-branch
# ... 进行代码修改 ...
git commit -am "fix: resolve memory leak"

# 2. 生成新版本补丁
cd ../../
./scripts/patch_maker.sh --submodule_path=linux-imx

# 3. 更新 series 文件和版本号
# 编辑 patches/linux-imx/series
# 将 001-ethernet-driver.patch 重命名为 001-ethernet-driver-v2.patch
```

### 冲突解决策略

#### 1. 自动重定基准

```bash
# 使用 git rebase 自动调整补丁基准
cd third_party/linux-imx
git rebase origin/master
```

#### 2. 三方合并

```bash
# 使用三方合并解决冲突
git merge -X theirs origin/master
```

#### 3. 手动编辑

当自动合并失败时，需要手动编辑冲突文件：

```
<<<<<<< HEAD
本地修改的内容
=======
上游新版本的内容
>>>>>>> origin/master
```

编辑后标记为已解决：

```bash
git add <resolved-file>
git commit
```

---

## 自动化工具使用

### patch_maker.sh 脚本详解

`patch_maker.sh` 是 IMX-Forge 提供的自动化补丁生成工具。

#### 脚本位置

```
/home/charliechen/imx-forge/scripts/patch_maker.sh
```

#### 功能概述

该脚本自动完成以下任务：

1. 检测子模块的默认分支
2. 比较当前分支与默认分支的差异
3. 使用 `git format-patch` 生成补丁文件
4. 按照命名规范自动命名补丁文件
5. 输出到指定的补丁目录

#### 参数说明

| 参数 | 必需 | 说明 | 默认值 |
|------|------|------|--------|
| `--submodule_path=<name>` | 是 | 子模块名称或路径 | - |
| `--output=<dir>` | 否 | 输出目录 | `patches/<submodule>/` |
| `-h, --help` | 否 | 显示帮助信息 | - |

#### 使用示例

##### 示例 1: 基本用法

```bash
# 为 linux-imx 子模块生成补丁
./scripts/patch_maker.sh --submodule_path=linux-imx

# 输出示例:
# === Patch Generation Summary ===
# Submodule:     linux-imx
# Default branch: master
# Current branch: feature-alpha-board
# Commits:        3
# Output:         /home/charliechen/imx-forge/patches/linux-imx/linux-imx-feature-alpha-board-20260315.patch
#
# Generating patch...
# ✓ Patch generated successfully!
#   File: /home/charliechen/imx-forge/patches/linux-imx/linux-imx-feature-alpha-board-20260315.patch
#   Size: 24K
```

##### 示例 2: 指定输出目录

```bash
# 将补丁输出到自定义目录
./scripts/patch_maker.sh --submodule_path=linux-imx --output=custom_patches/

# 输出到 custom_patches/linux-imx-<branch>-<date>.patch
```

##### 示例 3: 为 U-Boot 生成补丁

```bash
./scripts/patch_maker.sh --submodule_path=uboot-imx

# 输出到 patches/uboot-imx/uboot-imx-<branch>-<date>.patch
```

##### 示例 4: 生成 Busybox 补丁

```bash
./scripts/patch_maker.sh --submodule_path=busybox

# 输出到 patches/busybox/busybox-<branch>-<date>.patch
```

#### 工作流程

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 参数解析与验证                                             │
│    - 解析 --submodule_path 和 --output 参数                  │
│    - 验证子模块路径是否存在                                   │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│ 2. 子模块状态检测                                             │
│    - 检测子模块是否为 Git 仓库                               │
│    - 获取当前分支名称                                         │
│    - 检测默认分支 (origin/HEAD)                              │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│ 3. 差异分析                                                   │
│    - 计算当前分支与默认分支的提交数                           │
│    - 如果没有差异则退出                                       │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│ 4. 生成补丁文件                                               │
│    - 使用 git format-patch 生成补丁                          │
│    - 按命名规范生成文件名                                     │
│    - 输出到指定目录                                           │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│ 5. 结果输出                                                   │
│    - 显示补丁文件路径和大小                                   │
│    - 彩色输出提升可读性                                       │
└─────────────────────────────────────────────────────────────┘
```

#### 脚本特性

| 特性 | 说明 |
|------|------|
| **彩色输出** | 使用 ANSI 颜色代码区分不同状态信息 |
| **路径规范化** | 自动处理下划线和连字符的转换 |
| **分支自动检测** | 从 `origin/HEAD` 检测默认分支 |
| **空补丁检测** | 当没有差异时优雅退出 |
| **错误处理** | 详细的错误信息和可用子模块列表 |

#### 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 成功生成补丁或没有差异 |
| 1 | 参数错误或子模块不存在 |

### 补丁应用脚本

虽然目前项目尚未提供完整的补丁应用脚本，但以下是推荐的实现方式：

#### 推荐实现

```bash
#!/bin/bash
# scripts/apply_patches.sh

set -e

PATCH_DIR="$1"
TARGET_DIR="$2"

if [[ -z "$PATCH_DIR" || -z "$TARGET_DIR" ]]; then
    echo "Usage: $0 <patch-dir> <target-dir>"
    exit 1
fi

if [[ -f "$PATCH_DIR/series" ]]; then
    # 使用 series 文件按顺序应用
    while read -r patch_file; do
        # 跳过注释和空行
        [[ "$patch_file" =~ ^#.*$ || -z "$patch_file" ]] && continue

        echo "Applying: $patch_file"
        patch -d "$TARGET_DIR" -p1 < "$PATCH_DIR/$patch_file"
    done < "$PATCH_DIR/series"
else
    # 按文件名排序应用所有补丁
    for patch in "$PATCH_DIR"/*.patch; do
        echo "Applying: $(basename "$patch")"
        patch -d "$TARGET_DIR" -p1 < "$patch"
    done
fi
```

#### 使用示例

```bash
# 应用 linux-imx 补丁
./scripts/apply_patches.sh patches/linux-imx/ third_party/linux-imx/

# 应用 uboot-imx 补丁
./scripts/apply_patches.sh patches/uboot-imx/ third_party/uboot-imx/
```

---

## 最佳实践

### 补丁提交规范

#### 1. 提交信息格式

```
<组件>: <简短描述> (<50 字符)

<详细描述> (<72 字符/行)

<可选的额外信息>

Signed-off-by: 姓名 <邮箱>
```

#### 2. 提交信息示例

```
ethernet: FEC driver DMA optimization for i.MX6ULL

优化 FEC 以太网驱动的 DMA 描述符管理，提高网络吞吐量约 15%。

主要变更:
- 增加环形缓冲区大小到 256 个描述符
- 优化 DMA 一致性内存访问
- 添加自适应中断合并

测试环境:
- i.MX6ULL @ 528MHz
- iperf3 测试吞吐量从 85Mbps 提升到 98Mbps

Fixes: abc123def456 ("ethernet: initial FEC driver support")
Signed-off-by: 张三 <zhangsan@example.com>
```

#### 3. 提交标签使用

| 标签 | 用途 |
|------|------|
| `Fixes:` | 指明修复的问题对应的提交 |
| `Cc:` | 抄送相关人员审阅 |
| `Acked-by:` | 审阅者确认 |
| `Reviewed-by:` | 审阅者审核通过 |
| `Tested-by:` | 测试者验证 |
| `Suggested-by:` | 建议者 |

### 代码审查流程

#### 1. 补丁自检清单

提交补丁前，确保满足以下条件：

- [ ] 编译通过（无警告）
- [ ] 遵循项目代码风格
- [ ] 添加必要的注释
- [ ] 更新相关文档
- [ ] 通过测试验证
- [ ] 提交信息符合规范
- [ ] 添加 `Signed-off-by` 标签

#### 2. Pull Request 流程

```bash
# 1. 创建特性分支
git checkout -b feature/my-new-patch

# 2. 进行修改并提交
# ... 编辑代码 ...
git commit -as

# 3. 推送到远程仓库
git push origin feature/my-new-patch

# 4. 创建 Pull Request
# 通过 GitHub Web UI 创建 PR
```

#### 3. PR 描述模板

```markdown
## 变更概述
<!-- 简要描述此 PR 的目的 -->

## 变更类型
- [ ] Bug 修复
- [ ] 新功能
- [ ] 代码重构
- [ ] 文档更新
- [ ] 性能优化

## 测试计划
- [ ] 本地编译测试
- [ ] 板卡功能测试
- [ ] 回归测试

## 补丁信息
- 轨道: [linux-imx] / [mainline]
- 上游版本: rel/imx-5.15.72-2.1.0
- 补丁数量: X 个

## 相关 Issue
Closes #XXX
```

### 向上游提交流程

#### 1. 准备上游补丁

```bash
# 1. 从上游创建干净的分支
git checkout -b upstream-feature origin/master

# 2. 挑选相关提交
git cherry-pick <commit-hash>

# 3. 生成补丁文件
git format-patch -o /tmp/upstream-patches/ origin/master..HEAD
```

#### 2. 补丁清洗

使用 `scripts/checkpatch.pl` 检查代码风格：

```bash
# Linux 内核提供
./scripts/checkpatch.pl --strict /tmp/upstream-patches/*.patch
```

#### 3. 发送到上游邮件列表

```bash
# 使用 git send-email
git send-email \
  --to=linux-arm-kernel@lists.infradead.org \
  --cc=shawnguo@kernel.org \
  --cc=s.hauer@pengutronix.de \
  /tmp/upstream-patches/*.patch
```

#### 4. 跟进反馈

- 关注邮件列表的回复
- 根据维护者的意见修改补丁
- 发送新版本（v2, v3...）
- 在提交信息中添加版本历史

---

## 故障排除

### 常见问题

#### 问题 1: 补丁应用失败

```
patch: **** strip mismatch
```

**原因**: 路径前缀层级不匹配

**解决方案**:
```bash
# 尝试不同的 -p 值
patch -p0 < file.patch
patch -p1 < file.patch
patch -p2 < file.patch

# 或使用 --dry-run 预览
patch -p1 --dry-run < file.patch
```

#### 问题 2: 补丁冲突

```
Hunk #1 FAILED at 123.
```

**原因**: 目标文件已修改，与补丁内容冲突

**解决方案**:
```bash
# 使用 .rej 文件手动解决
patch -p1 < file.patch
# 检查生成的 .rej 文件，手动合并冲突

# 或使用三向合并
patch -p1 --merge < file.patch
```

#### 问题 3: 换行符问题

```
patch: **** Only garbage was found in the patch input.
```

**原因**: Windows 换行符 (CRLF) 导致

**解决方案**:
```bash
# 转换换行符
dos2unix file.patch

# 或使用 git 自动转换
git config core.autocrlf input
```

#### 问题 4: 空白字符差异

```
patch: **** Line 5 has trailing spaces.
```

**解决方案**:
```bash
# 忽略空白差异
patch -p1 -l < file.patch

# 或使用 git apply
git apply --ignore-whitespace file.patch
```

### 调试技巧

#### 1. 查看补丁统计

```bash
# 查看补丁影响的文件和行数
git apply --stat file.patch

# 查看补丁摘要
git diff --stat origin/master..HEAD
```

#### 2. 测试补丁应用

```bash
# 检查补丁是否可以干净应用
git apply --check file.patch

# 预览应用效果（不实际修改）
git apply --numstat file.patch
```

#### 3. 补丁回滚

```bash
# 反向应用补丁
patch -p1 -R < file.patch

# 或使用 git
git apply -R file.patch
```

---

## 附录

### A. Git Submodule 常用命令

```bash
# 初始化子模块
git submodule update --init --recursive

# 更新子模块到最新提交
git submodule update --remote

# 查看子模块状态
git submodule status

# 在子模块中操作
cd third_party/linux-imx
git checkout <branch>
git pull origin <branch>
```

### B. 补丁管理工具对比

| 工具 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **git format-patch** | Git 原生，保留完整提交信息 | 需要分支管理 | 日常开发 |
| **quilt** | 独立管理，不依赖 Git | 学习曲线陡峭 | 大规模补丁集 |
| **stgit** | 交互式管理，易于修改 | 需要额外安装 | 复杂补丁维护 |
| **patch + diff** | 简单直接 | 无版本信息 | 快速修补 |

### C. 相关资源

- **Git 官方文档**: https://git-scm.com/docs/git-format-patch
- **Linux 内核补丁提交指南**: https://www.kernel.org/doc/html/latest/process/submitting-patches.html
- **NXP i.MX 论坛**: https://community.nxp.com/t5/i-MX-Processors/bd-p/imx
- **IMX-Forge 项目**: https://github.com/Awesome-Embedded-Learning-Studio/imx-forge

---

<div align="center">

**IMX-Forge 补丁管理系统文档**

Copyright © 2026 IMX-Forge Project

</div>
