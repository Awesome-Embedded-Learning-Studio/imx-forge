---
title: 教程
---

<PageHeader title="教程系列" description="七个学习分区,按「你现在想解决什么」组织,而不是按目录结构" />

## 七个分区

<ChapterNav>
  <ChapterLink num="1" href="start/">快速上手 —— 三条最短路径,先跑起来再说</ChapterLink>
  <ChapterLink num="2" href="linux-basics/">环境与基础 —— Linux 底子 + 一套开箱即用的开发环境</ChapterLink>
  <ChapterLink num="3" href="start/">系统构建 —— 工具链 → U-Boot → 内核 → rootfs → Buildroot → 整机启动</ChapterLink>
  <ChapterLink num="4" href="driver/">驱动与实战 —— 字符设备到板级外设,收口到产品级项目</ChapterLink>
  <ChapterLink num="5" href="emu/">模拟与调试 —— 没有板子怎么跑,跑不通怎么查</ChapterLink>
  <ChapterLink num="6" href="flash/">烧录与进阶 —— 镜像写进卡或 eMMC,构建流程工程化</ChapterLink>
  <ChapterLink num="7" href="commands/">速查与参考 —— 命令、脚本、参数,不按顺序读</ChapterLink>
</ChapterNav>

## 怎么选

| 你的状态 | 直接去 |
| --- | --- |
| 第一次接触,不知道从哪开始 | [快速上手](start/) |
| 会写代码,但 Linux 命令行不熟 | [环境与基础](linux-basics/) |
| 想从零做出一个能开机的镜像 | [系统构建](start/) |
| 已经能开机,想写驱动 | [驱动与实战](driver/) |
| 板子还没到 / 卡住查不出来 | [模拟与调试](emu/) |
| 要烧到板子上 / 想改构建流程 | [烧录与进阶](flash/) |

## 分区详情

### 快速上手

同一个目标 —— 让一块 i.MX6ULL 板子把系统跑起来。依照手上的条件选一条最短路径，先看到结果，再回头补原理。

<ChapterNav variant="sub">
  <ChapterLink href="start/03_hardware_quick_reference">手上有板子 —— 先对硬件接口,再装工具链</ChapterLink>
  <ChapterLink href="start/06_docker_basics">没有板子 —— Docker 装好工具链,再用 QEMU 跑起来</ChapterLink>
  <ChapterLink href="uboot/">环境已配好 —— 直接进系统构建主线</ChapterLink>
</ChapterNav>

不确定从哪开始，先看 [学习路线图](start/00_roadmap)，它把「嵌入式 Linux 到底是什么」和整条路径讲了一遍。

::: tip 一条经验
不要从「驱动开发」直接开始。驱动章节默认你已经能独立编内核、烧镜像、看串口日志 —— 这些能力在「系统构建」分区里。
:::

### 环境与基础

Linux 底子 + 一套开箱即用的开发环境，后面所有章节的地基。没基础先补 Linux 基本功，不会命令行后面每条命令都是黑箱；有基础就把开发环境一次配好，避免学到一半被环境问题劝退。

<ChapterNav variant="sub">
  <ChapterLink href="linux-basics/">Linux 基础预备营 —— 零基础读者的第一站</ChapterLink>
  <ChapterLink href="start/06_docker_basics">Docker 教程 —— ARM GNU Toolchain 15.2 一条命令起环境</ChapterLink>
  <ChapterLink href="workflow/">开发环境配置 —— WSL2 / Remote-SSH / 串口 / clangd / 传文件</ChapterLink>
</ChapterNav>

### 系统构建

这是整站的主线，六步环环相扣。前一步的产物是后一步的输入，不建议跳序。

<ChapterNav variant="sub">
  <ChapterLink href="start/">01 入门准备 —— 路线图、工具链、硬件速查、首启检查</ChapterLink>
  <ChapterLink href="uboot/">02 U-Boot 移植 —— 先把屏幕点亮、把网络拉起来</ChapterLink>
  <ChapterLink href="kernel/">03 内核移植 —— 主线单轨，取源码、写设备树、自定义配置</ChapterLink>
  <ChapterLink href="rootfs/">04 根文件系统 —— BusyBox 手搓最小 rootfs</ChapterLink>
  <ChapterLink href="buildroot/">05 Buildroot 构建 —— br2-external 树与自定义包的工程化方案</ChapterLink>
  <ChapterLink href="build/04_full_system_build">06 完整系统构建 —— 把前面所有产物装配成一次完整启动</ChapterLink>
</ChapterNav>

### 驱动与实战

本教程的核心重头戏：从字符设备到板级外设，最后收口到一个可交付的产品级项目。前置要求是能独立编内核、改设备树、烧镜像、看串口日志，没做到就先回系统构建把主线走通一次。

<ChapterNav variant="sub">
  <ChapterLink href="driver/">驱动开发 —— 基础段 / 子系统段 / 板级外设段十四组章节</ChapterLink>
  <ChapterLink href="project/">应用项目 light-meter —— 收口成一次交付</ChapterLink>
</ChapterNav>

### 模拟与调试

两条退路：没有板子怎么跑，跑不通怎么查。不必等学完才来，遇到情况直接跳进来。

<ChapterNav variant="sub">
  <ChapterLink href="emu/">QEMU 板级模拟 —— 同一份设备树、同一个 mainline 内核、同一套 rootfs</ChapterLink>
  <ChapterLink href="debug/">调试与排错 —— gdbserver / strace / core dump / 串口日志读法</ChapterLink>
</ChapterNav>

| 症状 | 去哪 |
| --- | --- |
| 板子还没到,想先动手 | [QEMU 板级模拟](emu/01_why_emulation) |
| 内核启动卡在某个阶段 | [启动调试](kernel/17_kernel_boot_debug) |
| 驱动 `insmod` 后无反应 | [gdbserver 远程调试](debug/01_gdbserver_remote_debug) |
| 进程莫名退出 / 段错误 | [strace 与 core dump](debug/02_strace_log_coredump) |
| 串口一堆乱码或刷屏 | [串口日志读法](debug/03_serial_log_reading) |

### 烧录与进阶

把产物变成能开机的卡或 eMMC，再把手工流程变成可信的构建工程。

<ChapterNav variant="sub">
  <ChapterLink href="flash/">镜像与烧录 —— 介质、分区、启动偏移、整包镜像、SD 与 UUU 烧录</ChapterLink>
  <ChapterLink href="build/">构建进阶 —— 产出目录、patch 工作流、rootfs overlay</ChapterLink>
</ChapterNav>

### 速查与参考

不按教程顺序读的那一类，用浏览器搜索（Ctrl K）直接搜命令名或函数名，命中率比翻侧栏高。

<ChapterNav variant="sub">
  <ChapterLink href="commands/">命令速查 —— 构建 / 检查 / 存储 / 烧录四组,每条配真实输出</ChapterLink>
  <ChapterLink href="third_party/">第三方支持 —— 芯片手册与设备树规范</ChapterLink>
  <ChapterLink href="../engineering/scripts/">脚本手册 —— 每个构建脚本的逐篇说明</ChapterLink>
  <ChapterLink href="../reference/">参考手册 —— 配置项、参数与接口索引</ChapterLink>
</ChapterNav>

## 其他

<ChapterNav variant="sub">
  <ChapterLink href="contrib/">来稿 —— 社区贡献的环境与工具稿</ChapterLink>
  <ChapterLink href="../community/notes/">技术笔记 —— 排查记录与临时结论</ChapterLink>
  <ChapterLink href="../community/qa/">问答</ChapterLink>
  <ChapterLink href="../community/team/">贡献者</ChapterLink>
</ChapterNav>
