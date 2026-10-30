---
title: 环境与基础
---

<PageHeader title="环境与基础" description="Linux 底子 + 一套开箱即用的开发环境,后面所有章节的地基" />

## 有无Linux基础

没基础：先**补 Linux 基本功**(不会命令行,后面每条命令都是黑箱),然后再配置环境。

有基础：直接**把开发环境一次配好**(工具链、远程编辑、串口、传文件),避免学到一半被环境问题劝退。

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="../linux-basics/">Linux 基础预备营</ChapterLink>
  <ChapterLink num="02" href="../docker/">Docker 教程</ChapterLink>
  <ChapterLink num="03" href="../workflow/">开发环境配置</ChapterLink>
</ChapterNav>

### Linux 基础预备营

从「怎么打开终端」讲到交叉编译入门:环境与目录结构、命令行、文本处理、系统与进程、网络、Shell 脚本、开发工具、综合练习。零基础读者的第一站。

### Docker 教程

用 Docker 把 ARM GNU Toolchain 15.2 和整套构建依赖封进镜像。一条命令起环境,不污染本机,Windows + WSL2 尤其省事。

### 开发环境配置

WSL2 环境配置、VSCode Remote-SSH 远程开发、串口终端双通道、clangd 交叉索引、tasks 模板、主机与板子之间传文件 —— 把环境一块块配齐。

## 学完往哪走

→ [系统构建](../system-build/):从工具链到能开机的完整镜像。
