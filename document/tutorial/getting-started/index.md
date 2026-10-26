---
title: 快速上手
---

<PageHeader title="快速上手" description="按你手上的条件选一条最短路径,先看到结果,再回头补原理" />

## 三种路径：系统先跑起来

同一个目标 —— 让一块 i.MX6ULL 板子把系统跑起来。依照个人情况自行选择

<ChapterNav>
  <ChapterLink num="A" href="../start/03_hardware_quick_reference">手上有板子 —— 先对硬件接口,再装工具链</ChapterLink>
  <ChapterLink num="B" href="../docker/">没有板子 —— Docker 装好工具链,再用 QEMU 跑起来</ChapterLink>
  <ChapterLink num="C" href="../system-build/">环境已配好 —— 直接进系统构建主线</ChapterLink>
</ChapterNav>

## 不确定从哪开始?

先看 [学习路线图](../start/00_roadmap),它把「嵌入式 Linux 到底是什么」和整条路径讲了一遍。或者去 [教程总览](../) 按分区浏览。

::: tip 一条经验
不要从「驱动开发」直接开始。驱动章节默认你已经能独立编内核、烧镜像、看串口日志 —— 这些能力在「系统构建」分区里。
:::
