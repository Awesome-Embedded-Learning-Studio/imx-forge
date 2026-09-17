# patch_maker.sh - 补丁生成工具详解

## 脚本概述

`patch_maker.sh` 是 IMX-Forge 项目中用于从子模块更改生成补丁文件的工具。它自动检测子模块的当前分支与默认分支的差异，并生成可应用的补丁文件。

### 核心功能

- **自动分支检测**：自动检测子模块的默认分支
- **差异生成**：基于当前分支与默认分支的差异生成补丁
- **灵活的输出位置**：支持自定义补丁输出目录
- **友好的命名**：自动生成包含子模块名、分支名和日期的补丁文件名
- **提交统计**：显示补丁中包含的提交数量

### 设计理念

这个工具的核心设计思想是"从分支到补丁"的工作流：

1. 开发者在子模块中创建功能分支
2. 进行修改和提交
3. 使用 `patch_maker.sh` 将分支的更改导出为补丁文件
4. 补丁文件可以被版本控制和共享

这种工作流的好处：

- **版本控制友好**：补丁文件可以被 git 管理
- **可追溯**：补丁文件名包含日期和分支信息
- **可复现**：补丁可以应用到相同的上游版本
- **可审查**：补丁内容可以被审查和评论

### 依赖关系

```
patch_maker.sh
    ├─ git (版本控制工具)
    └─ 子模块目录 (third_party/linux_mainline, uboot-imx, busybox)
```

## 参数说明

### 命令行参数

```bash
./scripts/patch_maker.sh --submodule_path=<name> [--output=<dir>]
```

| 参数 | 必需 | 说明 | 默认值 |
|------|------|------|--------|
| `--submodule_path=<name>` | 是 | 子模块名称或路径 | 无 |
| `--output=<dir>` | 否 | 补丁输出目录 | `patches/<submodule>/` |
| `-h, --help` | 否 | 显示帮助信息 | 无 |

### 子模块名称格式

支持以下格式：

| 输入格式 | 解析结果 |
|----------|----------|
| `linux_mainline` | `linux_mainline` |
| `third_party/linux_mainline` | `linux_mainline` (移除前缀) |
| `uboot-imx` | `uboot-imx` |
| `busybox` | `busybox` |

脚本先按输入的原始名字找 `third_party/` 下的目录；找不到时才尝试把下划线换成连字符再找一次（兼容 `uboot-imx` 这类连字符目录）。`linux_mainline` 目录本身就是下划线命名，保持原名不动。脚本 usage 列出的子模块只有 `linux_mainline`、`uboot-imx`、`busybox` 三个。

### 输出目录规则

| 指定方式 | 结果 |
|----------|------|
| 未指定 | `patches/<submodule>/` |
| 相对路径 | `PROJECT_ROOT/<relative_path>/` |
| 绝对路径 | `<absolute_path>` |

## 执行流程

### 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│  1. 参数解析阶段                                             │
│     - 解析命令行参数                                         │
│     - 验证必需参数                                           │
│     - 规范化子模块名称                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 子模块验证阶段                                           │
│     - 检查子模块目录是否存在                                 │
│     - 检查是否为 git 仓库                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 分支检测阶段                                             │
│     - 检测默认分支 (origin/HEAD)                             │
│     - 获取当前分支                                           │
│     - 验证分支差异                                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 补丁生成阶段                                             │
│     - 创建输出目录                                           │
│     - 生成补丁文件名                                         │
│     - 执行 git format-patch                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. 报告阶段                                                 │
│     - 显示补丁信息                                           │
│     - 显示文件大小                                           │
└─────────────────────────────────────────────────────────────┘
```

### 函数详解

#### 参数解析

**作用**：解析和验证命令行参数。

**处理流程**：

```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --submodule_path=*)
            SUBMODULE_PATH="${1#*=}"
            shift
            ;;
        --output=*)
            OUTPUT_DIR="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            usage
            ;;
    esac
done
```

**参数验证**：

1. `--submodule_path` 是必需的
2. 未提供时显示错误和用法
3. 未知选项时显示错误和用法

#### 子模块名称规范化

**作用**：将用户输入的子模块名称转换为标准格式。

**处理步骤**：

```bash
# 1. 移除 third_party/ 前缀
SUBMODULE_NAME="${SUBMODULE_PATH#third_party/}"

# 2. 构造完整路径（先按原名找）
SUBMODULE_FULL_PATH="$REPO_BASE_DIR/third_party/$SUBMODULE_NAME"

# 3. 找不到时把下划线转连字符再试一次（兼容连字符目录）
if [[ ! -d "$SUBMODULE_FULL_PATH" ]]; then
    SUBMODULE_NAME_HYPHEN="${SUBMODULE_NAME//_/-}"
    ...
fi
```

**示例**：

| 输入 | SUBMODULE_NAME | SUBMODULE_FULL_PATH |
|------|----------------|---------------------|
| `linux_mainline` | `linux_mainline` | `PROJECT_ROOT/third_party/linux_mainline` |
| `third_party/linux_mainline` | `linux_mainline` | `PROJECT_ROOT/third_party/linux_mainline` |
| `third_party/uboot-imx` | `uboot-imx` | `PROJECT_ROOT/third_party/uboot-imx` |

**为什么需要规范化**：

1. 用户可能使用不同的命名约定
2. 统一格式避免路径问题
3. 支持从项目根目录或脚本目录的相对路径

#### 默认分支检测

**作用**：检测子模块的默认分支。

**检测方法**：

```bash
# 优先从 origin/HEAD 获取
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

# 失败时尝试常见的默认分支名
if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo -e "${YELLOW}Warning: Could not detect default branch from origin/HEAD${NC}"
    echo -e "${YELLOW}Trying 'main' or 'master'...${NC}"
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
        DEFAULT_BRANCH="main"
    elif git rev-parse --verify origin/master >/dev/null 2>&1; then
        DEFAULT_BRANCH="master"
    else
        echo -e "${RED}Error: Could not determine default branch${NC}"
        exit 1
    fi
fi
```

**检测顺序**：

1. `origin/HEAD` 符号引用（推荐）
2. `origin/main`（现代标准）
3. `origin/master`（传统标准）

**为什么 origin/HEAD 是首选**：

`origin/HEAD` 是远程仓库的默认分支指针，它指向实际的默认分支（main 或 master）。这是最可靠的检测方式。

#### 当前分支验证

**作用**：获取并验证当前所在的分支。

**检查内容**：

```bash
# 获取当前分支
CURRENT_BRANCH=$(git branch --show-current)

# 检查是否在分支上（不是 detached HEAD）
if [[ -z "$CURRENT_BRANCH" ]]; then
    echo -e "${RED}Error: Not on any branch (detached HEAD state)${NC}"
    exit 1
fi

# 检查是否与默认分支相同
if [[ "$CURRENT_BRANCH" == "$DEFAULT_BRANCH" ]]; then
    echo -e "${YELLOW}Warning: Current branch '$CURRENT_BRANCH' is the same as default branch${NC}"
    echo -e "${YELLOW}No patches will be generated${NC}"
    exit 0
fi
```

**Detached HEAD 状态**：

当 HEAD 直接指向提交而不是分支时，称为 "detached HEAD"。这种状态下：

- 无法生成有意义的补丁（没有分支名）
- 补丁应用后没有分支上下文

脚本会拒绝在这种状态下生成补丁。

#### 补丁生成

**作用**：使用 git format-patch 生成补丁文件。

**执行的命令**：

```bash
git format-patch "origin/$DEFAULT_BRANCH..$CURRENT_BRANCH" --stdout > "$PATCH_FULL_PATH"
```

**命令解释**：

- `format-patch`：git 的补丁生成命令
- `origin/$DEFAULT_BRANCH..$CURRENT_BRANCH`：提交范围（从默认分支到当前分支）
- `--stdout`：输出到标准输出（用于合并到单个文件）
- `> "$PATCH_FULL_PATH"`：重定向到文件

**为什么使用 --stdout**：

默认的 `format-patch` 会为每个提交生成一个单独的文件：

```
0001-first-commit.patch
0002-second-commit.patch
0003-third-commit.patch
```

使用 `--stdout` 将所有合并到一个文件，更易于管理：

```
linux_mainline-feature-branch-20250315.patch
```

#### 补丁文件命名

**作用**：生成包含信息的补丁文件名。

**命名格式**：

```bash
PATCH_FILENAME="${SUBMODULE_NAME}-${CURRENT_BRANCH}-${DATE}.patch"
```

**格式说明**：

```
<子模块名>-<分支名>-<日期>.patch
```

**示例**：

| 子模块 | 分支 | 日期 | 文件名 |
|--------|------|------|--------|
| `linux_mainline` | `feature-uart` | `20250315` | `linux_mainline-feature-uart-20250315.patch` |
| `uboot-imx` | `fix-emmc` | `20250315` | `uboot-imx-fix-emmc-20250315.patch` |

**为什么这种命名格式**：

1. **包含子模块名**：明确补丁适用于哪个项目
2. **包含分支名**：描述补丁的功能或用途
3. **包含日期**：区分不同时间生成的补丁

## 使用示例

### 基本用法

```bash
# 为 linux_mainline 子模块的当前分支生成补丁
./scripts/patch_maker.sh --submodule_path=linux_mainline
```

### 指定输出目录

```bash
# 输出到自定义目录
./scripts/patch_maker.sh --submodule_path=linux_mainline --output=my_patches/
```

### 使用不同的名称格式

```bash
# 使用完整路径（自动去除前缀）
./scripts/patch_maker.sh --submodule_path=third_party/linux_mainline

# 连字符目录（如 uboot-imx）直接用连字符名
./scripts/patch_maker.sh --submodule_path=uboot-imx
```

### 输出示例

```
=== Patch Generation Summary ===
Submodule:     linux_mainline
Default branch: master
Current branch: feature-custom-driver
Commits:        3
Output:         /home/user/imx-forge/patches/linux_mainline/linux_mainline-feature-custom-driver-20250315.patch

Generating patch...
✓ Patch generated successfully!
  File: /home/user/imx-forge/patches/linux_mainline/linux_mainline-feature-custom-driver-20250315.patch
  Size: 15K
```

## 工作流程示例

### 典型使用场景

**场景**：为 Linux 内核添加自定义驱动

```bash
# 1. 进入子模块目录
cd third_party/linux_mainline

# 2. 创建功能分支
git checkout -b feature-custom-driver

# 3. 进行修改和提交
vim drivers/mydriver.c
git add drivers/mydriver.c
git commit -m "Add custom driver"

# 4. 回到项目根目录
cd ../..

# 5. 生成补丁
./scripts/patch_maker.sh --submodule_path=linux_mainline

# 6. 补丁现在在 patches/linux_mainline/ 目录
ls patches/linux_mainline/
# linux_mainline-feature-custom-driver-20250315.patch
```

### 应用补丁

**场景**：在其他地方应用生成的补丁

```bash
# 1. 确保子模块在正确的基准版本
cd third_party/linux_mainline
git checkout master
git pull

# 2. 应用补丁
git am ../../patches/linux_mainline/linux_mainline-feature-custom-driver-20250315.patch

# 3. 如果有冲突，解决后继续
git add .
git am --continue
```

## 配置选项

### 默认目录结构

```
PROJECT_ROOT/
├── patches/
│   ├── linux_mainline/
│   │   ├── linux_mainline-feature-xxx-20250315.patch
│   │   └── linux_mainline-fix-yyy-20250316.patch
│   ├── uboot-imx/
│   │   └── uboot-imx-feature-zzz-20250315.patch
│   └── busybox/
│       └── busybox-config-20250315.patch
└── third_party/
    ├── linux_mainline/    # 子模块
    ├── uboot-imx/    # 子模块
    └── busybox/      # 子模块
```

### 支持的子模块

| 名称 | 说明 |
|------|------|
| `linux_mainline` | 上游主线 Linux 内核 |
| `uboot-imx` | NXP U-Boot |
| `busybox` | BusyBox 工具集 |

## 故障排除

### 常见错误

#### 错误 1：子模块未找到

```
[ERROR] Submodule 'linux_mainline' not found at third_party/linux_mainline
```

**原因**：子模块目录不存在

**解决方法**：

```bash
# 初始化并更新子模块
git submodule update --init --recursive

# 检查子模块列表
ls third_party/
```

#### 错误 2：不是 git 仓库

```
[ERROR] 'third_party/linux_mainline' is not a git repository
```

**原因**：目录存在但不是 git 仓库

**解决方法**：

```bash
# 检查 .git 是否存在
ls -la third_party/linux_mainline/.git

# 如果是文件（子模块），读取内容
cat third_party/linux_mainline/.git

# 重新初始化子模块
git submodule deinit third_party/linux_mainline
git submodule update --init third_party/linux_mainline
```

#### 错误 3：Detached HEAD 状态

```
[ERROR] Not on any branch (detached HEAD state)
```

**原因**：HEAD 不在分支上

**解决方法**：

```bash
# 创建或切换到分支
cd third_party/linux_mainline
git checkout -b my-feature-branch

# 或切换到现有分支
git checkout existing-branch
```

#### 错误 4：当前分支与默认分支相同

```
[WARN] Current branch 'master' is the same as default branch
[WARN] No patches will be generated
```

**原因**：在默认分支上工作

**解决方法**：

```bash
# 创建功能分支
cd third_party/linux_mainline
git checkout -b my-feature-branch

# 进行修改...

# 然后生成补丁
cd ../..
./scripts/patch_maker.sh --submodule_path=linux_mainline
```

#### 错误 5：无提交差异

```
[WARN] No commits found between master and my-branch
```

**原因**：当前分支没有新的提交

**解决方法**：

```bash
# 确保有提交
cd third_party/linux_mainline
git log master..my-branch

# 如果没有输出，说明没有新提交
# 进行一些修改和提交
echo "test" > test.txt
git add test.txt
git commit -m "Test commit"
```

## 设计决策说明

### 为什么使用 git format-patch 而不是 git diff

`git format-patch` 和 `git diff` 都可以生成补丁，但 `format-patch` 更适合这个场景：

| 特性 | git format-patch | git diff |
|------|------------------|----------|
| 包含提交信息 | 是 | 否 |
| 保留作者信息 | 是 | 否 |
| 可用 git am 应用 | 是 | 否 |
| 适合邮件提交 | 是 | 否 |
| 文件大小 | 较大 | 较小 |

`format-patch` 保留了完整的提交历史和元数据，更适合版本控制和代码审查。

### 为什么检测 origin/HEAD

`origin/HEAD` 是远程仓库的默认分支指针，它始终指向实际的默认分支：

```bash
$ git symbolic-ref refs/remotes/origin/HEAD
refs/remotes/origin/main
```

这种方法：

1. **不假设分支名**：不假设是 main 还是 master
2. **跟随上游**：上游改变默认分支时自动适应
3. **符合 Git 惯例**：这是 Git 推荐的方式

### 为什么在当前分支与默认分支相同时退出

如果当前分支与默认分支相同，生成的补丁没有意义：

1. **补丁为空**：没有差异
2. **应用会失败**：会导致冲突
3. **表明工作流错误**：应该在功能分支上工作

脚本会检测这种情况并优雅退出，而不是生成无用的补丁。

### 为什么合并所有提交到一个文件

有两种选择：

1. **每个提交一个文件**：`0001-xxx.patch`, `0002-yyy.patch`
2. **所有提交一个文件**：`feature-xxx.patch`

脚本选择第二种，因为：

1. **易于管理**：一个文件包含整个功能
2. **易于应用**：一次性应用所有更改
3. **易于分享**：只需要分享一个文件

如果需要单独的补丁文件，可以不使用 `--stdout`：

```bash
# 生成多个文件
git format-patch origin/master..HEAD
```

## 扩展和定制

### 添加补丁头部信息

如果需要在补丁中添加额外的头部信息：

```bash
# 在生成补丁后，添加自定义头部
cat > "$PATCH_FULL_PATH.tmp" << EOF
From: $(git config user.name) <$(git config user.email)>
Subject: [PATCH] Custom patch header
Date: $(date -R)

EOF

cat "$PATCH_FULL_PATH" >> "$PATCH_FULL_PATH.tmp"
mv "$PATCH_FULL_PATH.tmp" "$PATCH_FULL_PATH"
```

### 压缩补丁文件

如果补丁文件较大，可以压缩：

```bash
# 在脚本最后添加
gzip "$PATCH_FULL_PATH"
echo "Compressed patch: ${PATCH_FULL_PATH}.gz"
```

### 生成补丁统计信息

```bash
# 添加补丁统计
git diff --stat "origin/$DEFAULT_BRANCH..$CURRENT_BRANCH" >> "${PATCH_FULL_PATH}.stat"
```

### 支持其他版本控制系统

虽然脚本当前只支持 git，但可以扩展：

```bash
# 检测 VCS 类型
if [[ -d "${SUBMODULE_FULL_PATH}/.git" ]]; then
    # git
elif [[ -d "${SUBMODULE_FULL_PATH}/.hg" ]]; then
    # mercurial
elif [[ -d "${SUBMODULE_FULL_PATH}/.svn" ]]; then
    # subversion
fi
```

## 相关文档

- [Linux 内核补丁工作流](https://www.kernel.org/doc/html/latest/process/submitting-patches.html) - 内核补丁提交规范
- [git format-patch 文档](https://git-scm.com/docs/git-format-patch) - Git 补丁生成命令
- [git am 文档](https://git-scm.com/docs/git-am) - Git 补丁应用命令
