# Patch 工作流实战指南

## 前言：为什么你需要补丁系统

如果你开始做项目，必然会遇到需要修改 U-Boot 或内核代码的情况。可能是为了适配新硬件，可能是修复某个 bug，也可能是添加自定义功能。

有的时候，我们可能改了东西，但是丝毫不希望提交——因为他只是纯粹的改一下，而不是提交到上游仓库的。这个时候，打patch显然更加合适（感谢我的同事，他教我这一招的），换而言之，把你的代码改动导出成 `.patch` 文件，放在项目的 `patches/` 目录下，让构建脚本自动应用。这样你的修改就能持久化，而且可以版本控制。

这一章，我们就来完整走一遍补丁工作流：从生成补丁、应用到 CI/CD 集成，手把手教你掌握这套机制。

---

## 补丁系统架构

### patches/ 目录组织

先来看一下项目的补丁目录结构：

```bash
tree patches/
```

你会看到：

```
patches/
├── busybox/
├── linux-imx/
├── linux_mainline/
├── uboot/
└── uboot-imx/
```

每个子模块对应一个补丁目录，存放针对该组件的补丁文件。这种组织方式的好处是补丁按组件分类，一目了然，而且多个补丁可以共存（比如你可以同时有 linux-imx 和 linux_mainline 的补丁）。

**看一下实际的补丁文件**：

```bash
ls patches/linux-imx/
```

你可能会看到类似：

```
linux-imx-latest.patch
linux-imx-patch_test-20260314.patch
```

补丁文件命名遵循 `组件名-分支名-日期.patch` 的格式，这样从文件名就能看出补丁的来源和时间。

---

### "仅应用最新补丁" 设计理念

IMX-Forge 的补丁系统有个特殊设计：**每个组件只应用最新的一个补丁**。

这听起来有点奇怪——为什么不应用所有补丁？原因很实际：

1. **避免冲突**：多个补丁可能有重叠，按顺序应用容易冲突
2. **简化管理**：你只需要维护一个"最新状态"的补丁，不用管历史版本
3. **加快构建**：不需要按顺序应用一堆补丁，节省时间

具体实现是按文件名排序，取最后一个（最新的）应用。所以补丁文件命名带日期很重要——`20260314` 会被认为比 `20260310` 新，从而优先应用。

**踩坑经验**：有一次我命名补丁时日期写错了，写成了 `20250101`（明年），结果这个补丁永远不会被应用，因为脚本认为它是"旧"的。所以日期一定要写对，或者干脆用 `latest` 这种特殊标识。

---

## 补丁生成实战

### 第一步：准备工作

在生成补丁之前，我们需要先创建一个工作分支，在这个分支上进行修改。

**确保子模块已初始化**：

```bash
cd /home/charliechen/imx-forge
git submodule update --init --recursive
```

**进入要修改的子模块**：

假设我们要修改 linux-imx 内核：

```bash
cd third_party/linux-imx
```

**查看当前分支**：

```bash
git branch -vv
```

你会看到类似：

```
* imx_v2022.04  abc1234 [origin/imx_v2022.04] Linux 6.1.x
```

当前在 `imx_v2022.04` 分支上，这是上游的默认分支。

**创建工作分支**：

```bash
# 基于当前分支创建新分支
git checkout -b my-feature origin/imx_v2022.04
```

分支名可以随便起，但建议用描述性的名字，比如 `fix-ethernet`、`add-spi-driver` 之类的。

**踩坑经验**：很多人习惯直接在 `imx_v2022.04` 分支上改，改完才发现这是个 detached HEAD 状态，提交都没地方提交。所以一定要先创建自己的工作分支。

---

### 第二步：进行代码修改

现在你可以在分支上进行修改了。

**示例修改：添加调试输出**

假设我们要给内核启动时加一句调试输出，修改 `init/main.c`：

```bash
vim init/main.c
```

在合适的位置添加：

```c
pr_info("IMX-Forge custom kernel build\n");
```

**提交修改**：

```bash
git add init/main.c
git commit -m "Add IMX-Forge boot signature"
```

可以提交多次，补丁会包含所有提交的改动。

**查看你的提交**：

```bash
git log --oneline origin/imx_v2022.04..HEAD
```

你会看到：

```
abc1234 Add IMX-Forge boot signature
```

冒号前面的 `abc1234` 是你的新提交，`origin/imx_v2022.04..HEAD` 表示"从上游分支到当前分支的差异"。

---

### 第三步：使用 patch_maker.sh 生成补丁

修改完成后，回到项目根目录生成补丁：

```bash
cd /home/charliechen/imx-forge
./scripts/patch_maker.sh --submodule_path=linux-imx
```

**脚本执行过程**：

```
=== Patch Generation Summary ===
Submodule:     linux-imx
Default branch: imx_v2022.04
Current branch: my-feature
Commits:        1
Output:         patches/linux-imx/linux-imx-my-feature-20260522.patch

Generating patch...
✓ Patch generated successfully!
  File: patches/linux-imx/linux-imx-my-feature-20260522.patch
  Size: 1.2K
```

脚本做了几件事：
1. 检测子模块的默认分支（`imx_v2022.04`）
2. 检测当前分支（`my-feature`）
3. 计算两个分支之间的提交差异
4. 生成补丁文件到 `patches/linux-imx/` 目录
5. 文件名包含分支名和当前日期

**看一下生成的补丁文件**：

```bash
cat patches/linux-imx/linux-imx-my-feature-20260522.patch
```

你会看到类似：

```
From abc1234def567890... Mon Sep 17 00:00:00 2026
From: Your Name <your.email@example.com>
Date: Thu, 22 May 2026 20:55:00 +0800
Subject: [PATCH] Add IMX-Forge boot signature

This patch adds a signature line to kernel boot output
to identify IMX-Forge builds.

---
 init/main.c | 1 +
 1 file changed, 1 insertion(+)

diff --git a/init/main.c b/init/main.c
index def1234..abc5678 100644
--- a/init/main.c
+++ b/init/main.c
@@ -123,6 +123,7 @@ static int __init init_post(void)
 {
+       pr_info("IMX-Forge custom kernel build\n");
        return 0;
 }
```

补丁文件格式解读：
- **头部**：包含提交信息（作者、日期、提交说明）
- **文件变更**：列出了修改的文件和行数统计
- **差异内容**：实际的代码改动（`-` 表示删除，`+` 表示添加）

**踩坑经验**：如果你的修改包含二进制文件（比如图片、固件），生成的补丁会很大，而且可能无法正确应用。这种情况最好不要用补丁，直接把二进制文件放在项目的其他目录里。

---

### 第四步：提交补丁到项目

补丁生成后，记得提交到 Git：

```bash
git add patches/linux-imx/linux-imx-my-feature-20260522.patch
git commit -m "Add linux-imx patch for boot signature"
```

这样你的补丁就跟着项目走了，其他人拉取代码后也能自动应用。

---

## 补丁应用实战

补丁应用有自动和手动两种方式。构建脚本会自动应用，但了解手动应用方法有助于调试问题。

### 自动应用：使用 apply_patches.sh

这是最常用的方式，构建脚本会自动调用。

**应用 linux-imx 补丁**：

```bash
./scripts/apply_patches.sh linux-imx
```

**执行输出**：

```
========================================
应用 linux-imx 补丁
========================================
补丁目录: patches/linux-imx
补丁数量: 2

应用: linux-imx-latest.patch (共 2 个补丁，仅应用最新)
  ✓ 成功

========================================
补丁应用完成
========================================
```

脚本做了几件事：
1. 扫描 `patches/linux-imx/` 目录，找到所有 `.patch` 文件
2. 按文件名字母排序，取最后一个（最新的）
3. 进入子模块目录，执行 `git apply --3way`
4. 报告应用结果

**`--3way` 参数的作用**：启用 3-way merge，如果补丁无法干净应用，会尝试合并三方内容，而不是直接失败。这在处理上游代码有变化时特别有用。

---

### 手动应用补丁

有时候你需要手动应用补丁，比如调试补丁冲突时。

**方法一：使用 git apply**

```bash
cd third_party/linux-imx

# 检查补丁（不实际应用）
git apply --stat ../../patches/linux-imx/linux-imx-latest.patch

# 应用补丁
git apply ../../patches/linux-imx/linux-imx-latest.patch
```

`--stat` 参数会显示补丁修改了哪些文件、多少行，但不实际应用。适合先预览一下。

**方法二：使用 patch 命令**

```bash
cd third_party/linux-imx
patch -p1 < ../../patches/linux-imx/linux-imx-latest.patch
```

`-p1` 表示忽略路径的第一层目录（`a/` 和 `b/`），这是 Git 生成补丁的标准格式。

---

### 处理补丁冲突

补丁冲突是补丁工作流中最头疼的问题，通常发生在上游代码更新后，补丁基于的代码已经过时。

**冲突的表现**：

```bash
./scripts/apply_patches.sh linux-imx
```

输出：

```
应用: linux-imx-latest.patch
  ✗ 失败

error: patch failed: init/main.c:123
error: init/main.c: patch does not apply
```

**解决方法**：

1. **进入子模块手动应用**

```bash
cd third_party/linux-imx
git apply --3way --reject ../../patches/linux-imx/linux-imx-latest.patch
```

`--reject` 参数会把无法应用的部分保存到 `.rej` 文件，手动解决冲突。

2. **查看冲突文件**

```bash
cat init/main.c.rej
```

你会看到类似：

```
--- a/init/main.c
+++ b/init/main.c
@@ -123,6 +123,7 @@
+
+pr_info("IMX-Forge custom kernel build\n");
```

3. **手动合并代码**

打开 `init/main.c`，找到对应位置，手动添加你的修改。

4. **更新补丁**

```bash
# 提交手动合并的修改
git add init/main.c
git commit -m "Manually resolved patch conflict"

# 回到项目根目录重新生成补丁
cd /home/charliechen/imx-forge
./scripts/patch_maker.sh --submodule_path=linux-imx
```

新补丁会基于最新的上游代码，以后就不会冲突了（除非上游又改了同一处）。

**踩坑经验**：补丁冲突解决起来很麻烦，所以最好的策略是**定期更新补丁**。每次上游更新后，重新应用一次补丁，如果有冲突就及时解决，不要拖到冲突累积得无法处理。

---

## CI/CD 集成

### CI 如何自动应用补丁

IMX-Forge 项目的 CI 流水线（`.github/workflows/ci-build.yml`）会在构建前自动应用所有补丁。

**CI 流程概览**：

```yaml
# .github/workflows/ci-build.yml（简化版）
name: CI Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive

      - name: Apply patches
        run: |
          ./scripts/apply_patches.sh linux-imx
          ./scripts/apply_patches.sh uboot-imx
          ./scripts/apply_patches.sh busybox

      - name: Build
        run: ./scripts/release-all.sh
```

每次推送代码或创建 PR，CI 会自动：
1. 检出代码（包括子模块）
2. 应用所有补丁
3. 执行完整构建

这意味着如果你的补丁有问题（比如语法错误、冲突），CI 会立即失败，你就能知道。

---

### 补丁变更触发构建

还有一个实用技巧：**让补丁变更专门触发构建验证**。

在 CI 配置中添加路径过滤：

```yaml
on:
  push:
    paths:
      - 'patches/**'
      - '.github/workflows/ci-build.yml'
```

这样只有当 `patches/` 目录下的文件变化时，才会触发 CI 构建。

**好处**：
- 节省 CI 资源（文档改动不触发构建）
- 补丁改动立即验证，避免错误补丁进入代码库

---

## 最佳实践

经过多次踩坑，我总结了几条补丁管理的最佳实践：

### 1. 补丁文件要有清晰的命名

不要用 `patch1.patch`、`fix.patch` 这种模糊的名字。使用 `组件名-功能描述-日期.patch` 格式：

```
linux-imx-fix-ethernet-20260522.patch
uboot-imx-add-spi-driver-20260522.patch
busybox-enable-telnet-20260522.patch
```

这样从文件名就能看出补丁的内容和时间。

---

### 2. 每个补丁只做一件事

不要把一堆改动塞进一个补丁，这样难以维护和回滚。

**❌ 不好**：一个补丁同时改了网络、存储、驱动

**✅ 好**：三个独立补丁，各改一个功能

```bash
linux-imx-fix-ethernet-20260522.patch
linux-imx-fix-storage-20260522.patch
linux-imx-add-gpio-driver-20260522.patch
```

---

### 3. 定期更新补丁

上游子模块会持续更新，长期不维护的补丁最终会无法应用。

建议每个月（或者上游更新后）重新生成一次补丁：

```bash
# 更新子模块
git submodule update --remote third_party/linux-imx

# 重新应用补丁
./scripts/apply_patches.sh linux-imx

# 如果有冲突，手动解决后重新生成
./scripts/patch_maker.sh --submodule_path=linux-imx
```

---

### 4. 补丁里要有清晰的说明

补丁文件的 commit message 要写清楚改了什么、为什么改。这样以后维护的人（包括未来的你自己）能理解补丁的用途。

**❌ 不好**：

```
fix stuff
```

**✅ 好**：

```
Fix Ethernet PHY reset timing issue on i.MX6ULL

The PHY chip requires a minimum 10ms delay after reset,
but the original code only waited 5ms, causing unstable
link initialization on some boards.

Tested on: Alpha i.MX6ULL eMMC board
Related issue: #123
```

---

### 5. 测试补丁是否可独立应用

新补丁生成后，在一个干净的环境测试一下是否能干净应用：

```bash
# 重置子模块到原始状态
cd third_party/linux-imx
git clean -fdx
git reset --hard origin/imx_v2022.04

# 回到项目根目录应用补丁
cd /home/charliechen/imx-forge
./scripts/apply_patches.sh linux-imx
```

如果这里失败了，说明补丁有问题，需要重新生成。

---

### 6. 使用 `.gitignore` 排除子模块的修改

在项目的 `.gitignore` 中添加：

```gitignore
# 子模块的修改应该通过补丁管理，不直接提交
third_party/linux-imx/
third_party/uboot-imx/
third_party/busybox/
```

这样你不小心提交子模块的修改时，Git 会警告你。

---

### 7. 补丁之间要有明确的依赖关系

如果补丁 B 依赖补丁 A（比如 B 修改了 A 添加的代码），要在补丁说明里注明：

```
Depends-on: linux-imx-base-driver-20260501.patch
```

这样应用补丁时就知道顺序。不过 IMX-Forge 的"仅应用最新补丁"策略下，这种情况应该合并成一个补丁，避免依赖问题。

---

## 总结：补丁工作流不再可怕

到这里，补丁工作流的完整流程你应该已经掌握了。让我们回顾一下核心要点：

- **不要直接修改子模块**：改动会被 `git submodule update` 覆盖
- **用补丁管理系统**：修改 → 生成补丁 → 提交补丁 → 自动应用
- **定期更新补丁**：上游更新后及时同步，避免冲突累积
- **补丁要有清晰说明**：方便以后维护和理解
- **测试补丁可应用性**：干净环境下一键应用，确保不依赖其他修改

掌握了这些，你就可以放心地修改 U-Boot、内核代码，而不用担心改动丢失。补丁系统会帮你持久化所有修改，而且版本控制、团队协作都更顺畅。

---

## 下一步：RootFS 定制

现在你已经掌握了补丁管理，可以安全地修改底层代码了。接下来你可能需要：

**[RootFS Overlay 使用指南](./03_rootfs_overlay_guide.md)** —— 学习如何灵活定制根文件系统，适配不同环境需求。

构建系统的进阶用法，最后一章了！
