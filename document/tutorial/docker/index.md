---
title: Docker 教程
---

<PageHeader icon="🐳" title="Docker 教程" description="使用 Docker 快速搭建统一的嵌入式 Linux 开发环境" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_docker_basics">Docker 基础知识</ChapterLink>
  <ChapterLink num="02" href="02_imx_forge_docker_guide">IMX-Forge Docker 开发指南</ChapterLink>
</ChapterNav>

## 为什么使用 Docker？

| 对比项 | 传统开发 | Docker 开发 |
|--------|----------|-------------|
| 工具链管理 | 版本冲突频繁 | 统一隔离环境 |
| 新手上手 | 配置繁琐 | 5 分钟完成 |
| 跨平台 | Linux only | Linux / Windows / macOS |
| 团队协作 | "在我机器上能跑" | 环境完全一致 |

### 传统开发的痛点

- ❌ 工具链版本冲突
- ❌ 依赖库混乱
- ❌ "在我机器上能跑"问题
- ❌ 跨平台开发困难
- ❌ 新手入门门槛高

### Docker 的优势

- ✅ 环境统一 - 所有开发者使用相同的环境
- ✅ 依赖隔离 - 避免版本冲突
- ✅ 快速上手 - 5分钟配置完成
- ✅ 跨平台支持 - Linux/Windows/macOS
- ✅ 团队协作友好 - 统一的开发环境

### IMX-Forge Docker 环境的价值

- 预装 ARM GNU Toolchain 15.2.rel1
- 所有编译依赖开箱即用
- 国内优化加速（Dockerfile.cn）
- 支持 USB 烧录和网络启动
- 与 WSL2 深度集成（Windows 用户）

::: tip Windows 用户
IMX-Forge 对 Windows + WSL2 环境深度友好！推荐配置：**WSL2 (Ubuntu 22.04/24.04) + Docker Desktop with WSL2 Integration**。
快速开始：[Docker 基础教程 - WSL2 安装](01_docker_basics#wsl2-安装)
:::

::: info 前置知识
基本的命令行操作能力 · Linux 基础概念（可选）
:::

::: details 延伸阅读
- [docker/README.md](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/docker/README.md) - Docker 环境参考手册
- [Docker 官方文档](https://docs.docker.com/)
:::

## 教程列表

### 1. Docker 基础知识

**文件**: [01_docker_basics.md](01_docker_basics.md)

- 什么是 Docker
- 容器与虚拟机的区别
- Docker 核心概念
- 安装与基本命令
- **WSL2 安装** ⭐ Windows 用户必读

### 2. IMX-Forge Docker 开发指南

**文件**: [02_imx_forge_docker_guide.md](02_imx_forge_docker_guide.md)

- 快速开始
- 高级用法
- 工作流示例
- 故障排除

## 学习路径

建议按以下顺序学习：

1. **Docker 基础知识** - 了解 Docker 核心概念和安装
2. **IMX-Forge Docker 指南** - 学习如何在项目中使用 Docker
3. **实践开发** - 开始你的嵌入式 Linux 开发之旅

### Windows 用户特别说明

IMX-Forge 对 Windows + WSL2 环境深度友好！

**推荐配置**：
- **WSL2 (Ubuntu 22.04/24.04)** + **Docker Desktop with WSL2 Integration**

**优势**：
- ✅ 无需双系统，Windows 下原生开发
- ✅ 完整的 Linux 工具链支持
- ✅ Docker 与 WSL2 无缝集成
- ✅ 支持 USB 设备直通（烧录、串口调试）
- ✅ Mirrored 网络模式直接访问开发板

**快速开始**：[Docker 基础教程 - WSL2 安装](01_docker_basics.md#wsl2-安装) ⭐

## 常见问题

### Q: 我需要 Docker 基础知识才能使用吗？

A: 不需要！如果你只是想快速开始开发，可以直接阅读 [IMX-Forge Docker 开发指南](02_imx_forge_docker_guide.md) 的快速开始部分。Docker 基础教程是为了帮助你更好地理解 Docker。

### Q: Docker 开发环境会影响性能吗？

A: 影响很小。容器技术接近原生性能，编译速度与主机环境几乎相同。对于嵌入式开发来说，Docker 带来的便利性远大于轻微的性能开销。

### Q: 我可以在 Docker 中进行调试吗？

A: 可以！Docker 完全支持 GDB 调试、串口通信、网络启动等开发调试功能。详见 [IMX-Forge Docker 开发指南](02_imx_forge_docker_guide.md) 的调试与烧录章节。

### Q: Windows 用户必须使用 WSL2 吗？

A: 强烈推荐。虽然可以在 Windows 上直接使用 Docker Desktop，但会面临路径转换、文件权限、性能等问题。WSL2 + Docker 提供了完整的 Linux 体验，是 Windows 用户进行嵌入式开发的最佳选择。

## 下一步

选择适合你的入口：

- **新手**：从 [Docker 基础知识](01_docker_basics.md) 开始
- **有经验者**：直接阅读 [IMX-Forge Docker 开发指南](02_imx_forge_docker_guide.md)
- **Windows 用户**：重点阅读 [WSL2 安装](01_docker_basics.md#wsl2-安装) 章节

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../start/" variant="sub">← 入门准备</ChapterLink>
  <ChapterLink href="../uboot/" variant="sub">U-Boot 教程 →</ChapterLink>
</ChapterNav>
