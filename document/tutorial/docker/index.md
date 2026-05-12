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

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../start/" variant="sub">← 入门准备</ChapterLink>
  <ChapterLink href="../uboot/" variant="sub">U-Boot 教程 →</ChapterLink>
</ChapterNav>
