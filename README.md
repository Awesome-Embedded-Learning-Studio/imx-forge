<div align="center">

```
██╗███╗   ███╗██╗  ██╗      ███████╗ ██████╗ ██████╗  ██████╗ ███████╗
██║████╗ ████║╚██╗██╔╝      ██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
██║██╔████╔██║ ╚███╔╝ █████╗█████╗  ██║   ██║██████╔╝██║  ███╗█████╗
██║██║╚██╔╝██║ ██╔██╗ ╚════╝██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
██║██║ ╚═╝ ██║██╔╝ ██╗      ██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
╚═╝╚═╝     ╚═╝╚═╝  ╚═╝      ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
```

**面向 NXP i.MX6ULL 的嵌入式 Linux 开发工坊 —— 从工具链到驱动的完整学习路径**

[![CI](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions/workflows/ci-build.yml/badge.svg)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions/workflows/ci-build.yml)
[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)
[![Contributors](https://img.shields.io/github/contributors/Awesome-Embedded-Learning-Studio/imx-forge?style=flat-square)](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/graphs/contributors)
[![Docker](https://img.shields.io/badge/Docker-supported%20%EF%83%8B-blue?style=flat-square)](docker/README.md)
[![WSL2](https://img.shields.io/badge/WSL2-Tested%20%26%20OK-brightgreen?style=flat-square)](QUICK_START.md)
[![Kernel](https://img.shields.io/badge/Kernel-dual%20track%20(6.12.3%20%2B%207.0rc)-blue?style=flat-square)](#-为什么选择-imx-forge)
[![Mainline](https://img.shields.io/badge/Mainline-migrated%20%EF%83%A0-brightgreen?style=flat-square)](#-为什么选择-imx-forge)

</div>

---

## ✨ 为什么选择 IMX-Forge？

### 🐳 开箱即用的开发环境

> **5分钟配置完成，跨平台支持**

- ✅ 预装 ARM GNU Toolchain 15.2.rel1 和所有依赖
- ✅ 无需配置工具链 PATH，无需担心版本冲突
- ✅ 国内优化版本（Dockerfile.cn）加速下载
- ✅ 支持烧录和网络启动（USB/NFS）
- ✅ **WSL2 深度友好** —— Mirrored 网络模式，Windows 用户无需双系统

**详细文档**: [Docker 开发环境指南](docker/README.md) | [WSL2 配置教程](document/tutorial/docker/01_docker_basics.md#wsl2-安装)

### 🔧 双轨内核策略

> **紧跟上游，学习最新内核技术**

- 📦 **NXP BSP 轨道** —— 基于 6.12.3，稳定可靠
- 🚀 **Mainline 轨道** —— 基于 7.0rc，紧跟上游最新特性
- 🔄 完整的迁移指南和对比分析

### 📚 完整的 0→1 学习路径

> **持续增长的教程体系，从入门到实战**

```
工具链 → U-Boot → 内核 → Rootfs → 驱动开发 → 实战项目
```

每一步都有详细的文档和实战示例，不再是"这里略去一万字"的坑人教程。

**在线阅读**: [https://awesome-embedded-learning-studio.github.io/imx-forge/](https://awesome-embedded-learning-studio.github.io/imx-forge/)

### 🔥 活跃开发中

> **持续更新，内容不断完善**

- 🆕 **系统驱动教程** —— 从硬件实现到驱动实战，一点不落下！
- 📝 **43+ 篇驱动相关教程** —— 涵盖字符设备、设备树、内核模块等。
- ✅ **CI/CD 完善** —— 自动化构建测试，确保代码质量。

---

## 🚀 快速开始

IMX-Forge 支持 **Docker** 和 **WSL2 + Docker** 两种开发环境：

### 🐳 Docker 环境（推荐 ⭐）

跨平台支持，5 分钟配置完成，开箱即用。

#### 方式一：直接拉取镜像（最简单）

我们提供预构建的 Docker 镜像，包含完整的开发环境。`v1.0.0` 是首个轻量可用版本，重点完成正点原子阿尔法 i.MX6ULL 的构建、镜像、烧录、启动闭环；历史 `v0.5` 仅作为路线图里程碑编号保留。

| 标签 | 说明 | 适用场景 |
|------|------|----------|
| `latest` | 稳定版本 | 日常开发推荐 |
| `preview` | 预览版本 | 测试新功能 |
| `v1.0.0` 等 | 版本号 | 锁定特定版本 |

```bash
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge

# 拉取稳定版镜像
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:latest

# 启动开发环境
docker run -it --rm -v $(pwd):/workspace ghcr.io/awesome-embedded-learning-studio/imx-forge:latest
```

使用特定版本：
```bash
docker pull ghcr.io/awesome-embedded-learning-studio/imx-forge:v1.0.0
```

> **镜像说明**: 基于 Ubuntu 24.04，预装 ARM GNU Toolchain 15.2.rel1 及所有开发依赖，截至文档更新时约 2GB（实际大小可能存在波动）。详见 [Docker 发布文档](document/ci/docker-publish.md)

#### 方式二：本地构建

如需自定义或使用国内镜像优化版：
```bash
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git
cd imx-forge/docker && docker build -t imx-forge:latest . && cd ..
docker run -it --rm -v $(pwd):/workspace imx-forge:latest
./scripts/release-all.sh
```

`release-all.sh` 默认生成 eMMC 镜像；发布或回归 SD/eMMC 双介质时推荐：

```bash
./scripts/release-all.sh --boot-media both
```

v1.0.0 的 SD 卡启动与 UUU + UMS eMMC 启动流程，已由仓库主作者 CharlieChen114514 在正点原子阿尔法 i.MX6ULL 开发板上完成实验验证。

> **国内用户加速**: 如果 ghcr.io 拉取较慢，可配置 Docker 镜像加速，详见 [Docker 文档](docker/README.md#国内用户加速)

### 🪟 WSL2 + Docker（Windows 用户首选）

无需双系统，Windows 下原生开发体验。支持 Mirrored 网络模式直接访问开发板，USB 设备直通用于烧录和串口调试。

---

📖 **详细配置指南**: [QUICK_START.md](QUICK_START.md)

---

## 📖 学习路径

| 阶段 | 主题 | 内容 | 状态 |
|------|------|------|------|
| 0️⃣ | [Docker 基础](document/tutorial/docker) | Docker 基础知识与 IMX-Forge 开发指南 | ✅ |
| 1️⃣ | [工具链](document/tutorial/start) | ARM GNU Toolchain 15.2 安装与配置 | ✅ |
| 2️⃣ | [U-Boot](document/tutorial/uboot) | U-Boot 原理、编译、移植、Logo 定制 | ✅ |
| 3️⃣ | [内核开发](document/tutorial/kernel) | 设备树、内核配置、驱动开发、网络启动 | ✅ |
| 4️⃣ | [Rootfs](document/tutorial/rootfs) | BusyBox、inittab、NFS 挂载、应用集成 | ✅ |
| 5️⃣ | [驱动开发](document/tutorial/driver) | 字符设备、设备树、pinctrl/gpio、platform、key/input 子系统 | ✅ 持续扩展 |
| 6️⃣ | [实战演练](document/tutorial/practical) | 完整系统构建与调试 | ✅ |

---

## 🎯 支持的开发板

| 板卡 | 芯片 | 状态 |
|------|------|------|
| 正点原子阿尔法 | i.MX6ULL | ✅ 完整支持 |

其他开发板（如野火等）欢迎提交 PR！

---

## ✅ CI/CD

项目通过 GitHub Actions 实现自动化构建测试：
- 组件构建验证 —— 每次提交自动检测变更并触发相关组件构建
- 智能缓存 —— 使用 ccache 加速构建
- 多轨支持 —— 同时验证 U-Boot、Linux NXP BSP、Linux Mainline、BusyBox

[查看 CI 状态](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/actions)

---

## 🤝 贡献指南

我们欢迎各种形式的贡献！

**完整贡献指南**: [CONTRIBUTING.md](CONTRIBUTING.md)

**快速开始**：
- 🐛 [报告 Bug](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)
- ✨ [提出功能请求](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)
- 📝 [改进文档](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/CONTRIBUTING.md#-如何贡献)
- 🔧 [提交代码](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/CONTRIBUTING.md#-开发工作流)

**补丁命名规范**：
- `[linux-imx]` 前缀 —— NXP BSP 轨道补丁
- `[mainline]` 前缀 —— 上游内核轨道补丁
- `[uboot]` 前缀 —— U-Boot 补丁

---

## 👥 贡献者

感谢所有为本项目做出贡献的开发者！

[完整列表](CONTRIBUTORS.md) · [GitHub Contributors](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/graphs/contributors)

---

## 📄 开源协议

MIT LICENSE —— 详见 [LICENSE](LICENSE)

若补丁源自 GPL 授权的 linux-imx 或 NXP U-Boot，则保留其原始 GPL-2.0 许可证。

---

## 🔗 相关链接

- **快速开始**: [QUICK_START.md](QUICK_START.md)
- **教程目录**: [document/tutorial/](document/tutorial/)
- **项目规划**: [document/todo/todo.md](document/todo/todo.md)
- **问题反馈**: [GitHub Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)

---

<div align="center">

**用 🔥 和无数串口终端堆出来的工程。希望我们可以更方便地自定义自己的 i.MX6ULL 系统。**

[⭐ Star](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge) · [🍴 Fork](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/fork) · [📢 Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)

</div>
