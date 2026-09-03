---
title: 开发环境配置
---

<PageHeader icon="⚙️" title="开发环境配置" description="WSL2 环境配置、VSCode Remote-SSH、串口终端、clangd、tasks.json、主机与板子传文件——咱们把开发台配到位的六篇" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_wsl2_env_config">WSL2 环境配置：网络、防火墙与存储位置</ChapterLink>
  <ChapterLink num="02" href="02_vscode_remote_ssh">VSCode Remote-SSH 连 WSL：把编辑器搬进开发环境</ChapterLink>
  <ChapterLink num="03" href="03_serial_terminal">串口终端：开发台的第二块屏幕</ChapterLink>
  <ChapterLink num="04" href="04_clangd_cross_compile">clangd 交叉编译配置：让跳转又快又准</ChapterLink>
  <ChapterLink num="05" href="05_tasks_json">VSCode tasks.json：把构建绑到快捷键</ChapterLink>
  <ChapterLink num="06" href="06_host_board_transfer">主机与板子传文件：scp、rsync 与 NFS root</ChapterLink>
</ChapterNav>

::: tip 专栏定位（含路径上下文规范）
这一卷咱们把开发台的每一块配置写成可照抄的步骤：WSL2 的网络与存储怎么配、编辑器怎么接进来、串口走哪条通道、代码索引与构建任务怎么固化、产物怎么送到板子上。每章开头交代操作位置，正文命令块首行注明在主机、WSL 还是板端执行——命令离开路径上下文就没法照抄，这是 Issue #101 里朋友提的第一条诉求，本卷与调试卷一样把它定为规矩。
:::

## 为什么需要这一专栏

IMX-Forge 的主力开发环境是 WSL2 + VSCode + 串口终端，板子通过 NFS/TFTP 与主机配合。这套组合能跑通之后，您日常开发的摩擦集中在六处：WSL2 的网络模式与防火墙、编辑器与开发环境的接入、串口通道的选型、交叉源码的跳转索引、高频构建命令的固化、主机与板子之间怎么传文件。任何一处没配好，每次改动都要多花一遍时间。

咱们这一卷按配置域一篇一篇配齐，给出可复制的配置与踩坑速查；#101 里朋友期望的“VSCode 远程开发 + MobaXterm 串口”开发台形态，就是 02 与 03 两篇合起来的样子。

## 前置知识

- 已完成 [Docker 教程](../docker/) 或已配好交叉编译工具链
- 了解 [out/ 目录结构](../build/01_out_directory_structure.md)
- WSL2 系统入门见 [linux-basics/ch01-wsl2](../linux-basics/01-environment/ch01-wsl2.md)（本卷不重复入门内容，只讲配置）

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../build/" variant="sub">← 构建系统</ChapterLink>
  <ChapterLink href="../debug/" variant="sub">调试与排错 →</ChapterLink>
</ChapterNav>
