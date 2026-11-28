---
title: 架构
---

<PageHeader icon="🏛️" title="架构文档" description="深入了解 IMX-Forge 的设计和实现" />

<ChapterNav>
  <ChapterLink num="01" href="SYSTEM_ARCHITECTURE.md">系统架构 —— 整体架构设计说明</ChapterLink>
  <ChapterLink num="02" href="BUILD_SYSTEM.md">构建系统 —— 构建脚本详解</ChapterLink>
  <ChapterLink num="03" href="PATCH_SYSTEM.md">补丁系统 —— U-Boot 与 QEMU 补丁管理</ChapterLink>
</ChapterNav>

## 核心概念

<InfoCard icon="🧩" title="单轨内核">
内核只有上游主线一条轨（mainline v7.2.9）。板级设备树由 `driver/device_tree/alpha-board/linux/` 的 dtsi 模板在构建时拷入，内核侧零补丁；补丁只用于 U-Boot（`patches/uboot-mainline/`）与 QEMU（`patches/qemu/`）。
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
