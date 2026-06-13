---
title: 架构
---

<PageHeader icon="🏛️" title="架构文档" description="深入了解 IMX-Forge 的设计和实现" />

<ChapterNav>
  <ChapterLink num="01" href="SYSTEM_ARCHITECTURE.md">系统架构 —— 整体架构设计说明</ChapterLink>
  <ChapterLink num="02" href="BUILD_SYSTEM.md">构建系统 —— 构建脚本详解</ChapterLink>
  <ChapterLink num="03" href="PATCH_SYSTEM.md">补丁系统 —— 双轨补丁管理</ChapterLink>
</ChapterNav>

## 核心概念

<InfoCard icon="🔀" title="双轨内核策略">
patches/ 目录下 NXP BSP 6.12.3 ← 稳定推荐 · 上游主线内核 ← 已完成
</InfoCard>

<InfoCard icon="🏗️" title="构建流程">
工具链 → U-Boot → 内核 → Rootfs → 镜像
</InfoCard>

::: tip 阅读建议
- **初学者** —— 先完成教程系列，再看这些文档
- **贡献者** —— 建议仔细阅读构建系统和补丁系统
- **架构师** —— 系统架构文档是必读的
:::

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回文档首页</ChapterLink>
</ChapterNav>
