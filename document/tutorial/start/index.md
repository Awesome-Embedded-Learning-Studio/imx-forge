---
title: 入门准备
---

<PageHeader icon="👋" title="入门准备" description="欢迎开始你的嵌入式 Linux 之旅" />

## 章节

<ChapterNav>
  <ChapterLink num="00" href="00_roadmap">学习路线图 —— 嵌入式Linux是什么？</ChapterLink>
  <ChapterLink num="01" href="01_start_from_toolchain">工具链安装 —— ARM GNU Toolchain 15.2</ChapterLink>
  <ChapterLink num="02" href="02_env_init_guide">环境初始化指南</ChapterLink>
  <ChapterLink num="03" href="03_hardware_quick_reference">板子硬件接口速查表</ChapterLink>
  <ChapterLink num="04" href="04_serial_tools_minicom">串口工具使用（minicom）</ChapterLink>
  <ChapterLink num="05" href="05_first_boot_check">第一次上电与串口检查</ChapterLink>
  <ChapterLink num="06" href="06_docker_basics">Docker 基础知识 —— 容器概念、安装与常用命令</ChapterLink>
  <ChapterLink num="07" href="07_imx_forge_docker_guide">IMX-Forge Docker 开发指南 —— 一键构建环境</ChapterLink>
</ChapterNav>

## 装环境的三条路线

同一套 imx-forge 源码，把编译环境搭起来有三条路：

| 路线 | 做法 | 适合谁 |
|------|------|--------|
| 手动路线（01 章） | 宿主机逐项安装工具链与依赖 | 想把环境每一层都弄明白的您 |
| WSL2 + Remote-SSH 路线（[开发环境配置](../workflow/)） | 环境装在本地 WSL，编辑器经 SSH 接入 | 想把编辑器、串口、传文件配成顺手开发台的朋友 |
| Docker 路线（06、07 章） | 拉取或构建镜像，容器内自带工具链与依赖 | 求快、宿主机要干净、Windows + WSL2 用户 |

三条路殊途同归。求快就走上 Docker 路线：镜像里预装 ARM GNU Toolchain 15.2.rel1，宿主机保持干净；想把依赖亲手过一遍，走手动路线。

::: tip 欢迎
这是嵌入式 Linux 开发之旅的第一步。完成工具链安装后，您就具备了交叉编译的能力。
:::

::: info 前置要求
您需要已安装 Ubuntu 22.04+ 或 WSL2、具有 sudo 权限，并会基本的命令行操作
:::

::: details 延伸阅读
- [ARM 官方工具链文档](https://developer.arm.com/downloads/-/gnu-rm)
- [交叉编译简介](https://en.wikipedia.org/wiki/Cross_compiler)
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../workflow/" variant="sub">开发环境配置 →</ChapterLink>
  <ChapterLink href="../uboot/" variant="sub">U-Boot 教程 →</ChapterLink>
</ChapterNav>
