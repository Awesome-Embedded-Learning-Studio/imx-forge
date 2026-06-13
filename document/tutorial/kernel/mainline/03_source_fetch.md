---
title: 获取主线内核源码
---

# 获取主线内核源码：从 kernel.org 到你的硬盘

## 前言：为什么这一章很重要

你可能会觉得，下载源码有什么好讲的？不就是 `git clone` 一下吗？但事情没那么简单。Linux 内核的源码管理有一套约定俗成的工作流程，如果你按照正确的方式做，后续更新、打补丁、切换版本都会很顺。反之，如果你把源码下载到一个乱七八糟的目录，或者用了错误的分支，后面会有很多麻烦。

这篇文章会教你如何以"正确的方式"获取主线内核源码，并应用 i.MX6ULL 的移植补丁。我们用的版本是 Linux 7.0-rc4，这是 2026 年初的候选版本。

## 第一步——从 kernel.org 克隆源码

主线内核的官方仓库在 kernel.org，你用 git 克隆就行。但内核仓库很大（超过 3GB），完整克隆会很慢。我们用 `--depth=1` 只克隆最新版本：

```bash
# 创建工作目录
git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git linux-mainline
```

如果你想要完整的历史记录（可以切换到任意版本），去掉 `--depth=1`：

```bash
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git linux-mainline
```

这会花比较长的时间，但你可以自由切换到任意版本。

### 验证源码版本

克隆完成后，确认一下版本：

```bash
cd linux-mainline
git describe
```

我这跟的是Master分支，此时此刻，你应该看到类似 `v7.0-rc4` 的输出。之后可能就不是了，7.0到底是candidate版本，没发呢还！

## 第二步——理解内核目录结构

现在你已经有了一份完整的内核源码，第一次看到这个庞大的目录树，可能会有点懵。我们来快速认识一下关键目录：

```
linux-mainline/
├── arch/           # 架构相关代码（ARM、x86 等）
├── block/          # 块设备层
├── certs/          # 签名证书
├── crypto/         # 加密算法
├── drivers/        # 设备驱动（最大的目录之一）
├── fs/             # 文件系统
├── include/        # 头文件
├── init/           # 内核初始化
├── ipc/            # 进程间通信
├── kernel/         # 内核核心代码
├── lib/            # 通用库函数
├── mm/             # 内存管理
├── net/            # 网络协议栈
├── samples/        # 示例代码
├── scripts/        # 构建脚本和工具
├── security/       # 安全框架
├── sound/          # ALSSA 音频子系统
├── tools/          # 各种工具
├── usr/            # initramfs 相关
├── virt/           # 虚拟化支持
├── .gitignore      # Git 忽略文件
├── .mailmap        # 邮件列表映射
├── COPYING         # GPL 许可证
├── CREDITS         # 贡献者列表
├── Kbuild          # 构建系统文件
├── Kconfig         # 根配置文件
├── Makefile        # 主 Makefile
├── README.md       # 项目说明
└── ...             # 还有很多文件
```

对于 i.MX6ULL 移植，我们主要关心：

- **arch/arm/**：ARM 架构相关代码，包括 mach-imx（i.MX 系列 SoC 代码）
- **drivers/**：所有驱动代码，显示、网络、触摸等都在这里
- **drivers/gpu/drm/mxsfb/**：eLCDIF 的 DRM 驱动
- **arch/arm/boot/dts/**：设备树源文件

## 第三步——应用移植补丁

这个项目里有一个完整的移植补丁：`patches/linux_mainline/linux_mainline-feat-imx6ull_patches-20260322.patch`。这个补丁包含了设备树文件和 defconfig 的改动。

### 补丁格式说明

这是一个标准的 git 格式补丁，你可以用 `git am` 或 `patch -p1` 应用：

```bash
# 方法一：使用 git am（推荐，会保留 commit 信息）
cd ~/linux-kernel/linux-mainline
git am /path/to/imx-forge/patches/linux_mainline/linux_mainline-feat-imx6ull_patches-20260322.patch
```

如果 `git am` 报错（比如冲突），可以尝试：

```bash
# 方法二：使用 patch（更宽容，但不会保留 commit 信息）
cd ~/linux-kernel/linux-mainline
patch -p1 < /path/to/imx-forge/patches/linux_mainline/linux_mainline-feat_imx6ull_patches-20260322.patch
```

### 验证补丁应用结果

补丁应用后，你应该能看到新增的文件：

```bash
# 检查设备树文件是否添加
ls arch/arm/boot/dts/nxp/imx/imx6ull-aes*
```

你应该看到 `imx6ull-aes.dts` 和 `imx6ull-aes.dtsi` 两个文件。

```bash
# 检查 defconfig 是否添加
ls arch/arm/configs/imx_aes_mainline_defconfig
```

如果这些文件都存在，说明补丁应用成功了。

## 第四步——使用 git worktree 管理多个版本

如果你想同时维护多个内核版本（比如主线和 BSP），git worktree 是个很好的工具。它允许你在同一个仓库里检出多个分支到不同的目录，不需要克隆多份源码。

```bash
# 在主线内核仓库里创建一个新的 worktree
cd ~/linux-kernel/linux-mainline
git worktree add ../linux-mainline-v7.0 v7.0-rc4

# 现在你有两个工作目录：
# ~/linux-kernel/linux-mainline（主工作区）
# ~/linux-kernel/linux-mainline-v7.0（v7.0-rc4 分支）
```

每个 worktree 都是独立的，你可以在一个里编译，另一个里调试，互不影响。

### 列出所有 worktree

```bash
git worktree list
```

### 删除 worktree

```bash
git worktree remove ../linux-mainline-v7.0
```

## 第五步——对比 BSP 内核和主线内核

如果你已经有一份 NXP BSP 内核的源码（这个项目的 `third_party/linux-imx`），可以用 `diff` 对比一下差异：

```bash
# 对比设备树文件（示例）
diff ~/linux-kernel/linux-mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi \
     ~/imx-forge/third_party/linux-imx/arch/arm/boot/dts/imx6ull-xxx.dtsi
```

你会发现主线内核的设备树写法有很多不同，这就是我们下一章要讲的内容。

## 常见问题排查

### 问题一：git am 失败

如果 `git am` 报错 `Patch does not have a valid e-mail address`，可能是补丁格式问题。尝试用 `patch -p1`：

```bash
patch -p1 < /path/to/patch.diff
```

### 问题二：克隆速度太慢

kernel.org 的镜像在国内可能比较慢，你可以用国内的镜像：

```bash
# 使用清华镜像
git clone --depth=1 --branch v7.0-rc4 https://mirrors.tuna.tsinghua.edu.cn/git/linux.git linux-mainline
```

### 问题三：补丁冲突

如果补丁和应用后的代码有冲突，`git am` 会失败。你需要手动解决冲突：

```bash
# 查看冲突文件
git status

# 编辑冲突文件，解决冲突后标记为已解决
git add <冲突文件>
git am --continue
```

## 下一章预告

到这里，你已经有了主线内核的源码，并且应用了 i.MX6ULL 的移植补丁。下一篇文章，我们会深入分析 BSP 内核和主线内核的根本差异：

- DRM 显示子系统 vs 旧 Framebuffer
- 设备树 binding 的变化
- 时钟驱动差异
- 其他子系统的对比

理解这些差异，是成功迁移的关键。我们下一章见。

---

**参考命令速查**

```bash
# 克隆主线内核（v7.0-rc4）
git clone --depth=1 --branch v7.0-rc4 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-mainline

# 应用补丁
git am /path/to/patch.diff

# 或使用 patch
patch -p1 < /path/to/patch.diff

# 验证补丁
ls arch/arm/boot/dts/nxp/imx/imx6ull-aes*
ls arch/arm/configs/imx_aes_mainline_defconfig

# git worktree 管理
git worktree add ../linux-worktree <branch>
git worktree list
git worktree remove ../linux-worktree
```

**延伸阅读**

- [Linux Kernel Git Workflow](https://www.kernel.org/doc/html/latest/process/submitting-patches.html) - 内核补丁提交流程
- [kernel.org repositories](https://git.kernel.org/) - 内核仓库列表
