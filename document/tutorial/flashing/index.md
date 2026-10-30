---
title: 烧录与进阶
---

<PageHeader title="烧录与进阶" description="把产物变成能开机的卡或 eMMC,再把手工流程变成可信的构建工程" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="../flash/">镜像与烧录</ChapterLink>
  <ChapterLink num="02" href="../build/">构建进阶</ChapterLink>
</ChapterNav>

### 镜像与烧录

从介质本身讲起,进而到 `dd` 命令:

- 存储介质基础、分区与文件系统、常见镜像与压缩格式;
- i.MX6ULL 启动流程与各段偏移 —— 为什么必须是整包镜像;
- 镜像布局设计、构建脚本、体积与容量核算;
- SD 卡烧录、UUU + UMS 烧 eMMC 两条落地路径。

### 构建进阶

- 输出目录结构:构建产物到底落在哪、谁引用了谁;
- patch 工作流实战:怎么给上游代码打补丁、怎么维护自己的 BSP 差异;
- rootfs overlay:不改 Buildroot 包定义,往根文件系统里塞自有文件。

## 配套

- 命令记不住?→ [命令速查](../cheatsheet/)
- 想改构建脚本本身?→ [脚本手册](../../scripts/)
