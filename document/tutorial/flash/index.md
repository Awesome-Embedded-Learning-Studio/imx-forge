---
title: 镜像与烧录
---

<PageHeader icon="💾" title="镜像构建与烧录准备" description="从构建产物到完整 SD/eMMC 镜像，理解 IMX-Forge 如何把 U-Boot、内核、设备树和 Rootfs 打包到一起" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_storage_media_basics">存储介质基础</ChapterLink>
  <ChapterLink num="02" href="02_image_partition_filesystem_basics">镜像、分区和文件系统</ChapterLink>
  <ChapterLink num="03" href="03_imx6ull_boot_flow_and_offsets">i.MX6ULL 启动链路与偏移</ChapterLink>
  <ChapterLink num="04" href="04_why_full_image">为什么需要完整镜像</ChapterLink>
  <ChapterLink num="05" href="05_image_layout_design">镜像布局设计</ChapterLink>
  <ChapterLink num="06" href="06_build_imx6ull_image_script">脚本设计拆解</ChapterLink>
  <ChapterLink num="07" href="07_image_size_and_usage">镜像大小与使用</ChapterLink>
  <ChapterLink num="08" href="08_sd_card_flashing">SD 卡烧录实战</ChapterLink>
  <ChapterLink num="09" href="09_uuu_ums_emmc_flashing">UUU + UMS eMMC 烧录</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解完整 `.img` 镜像的组成、分区布局、脚本设计思路和实际烧录路径，能够根据 SD/eMMC 目标介质生成合适的镜像文件，并把它写进真实存储设备。
:::

::: info 重点边界
这一组教程先把“镜像怎么构建出来”讲清楚，再展开 SD 卡直写和 UUU/UMS 写 eMMC。真实烧录会涉及主机磁盘设备选择、板卡启动模式、读卡器、USB 线和主机权限，命令里的设备名一定要按现场重新确认。
此外提示下，笔者的板卡是 eMMC 分到了标号 1，SD 卡是 0。你不确定，自己上 U-Boot 用 `mmc list` 看看，别完全照抄。
:::

## 推荐学习顺序

建议按顺序读。前 3 章是概念地基：先分清 SD/eMMC 和块设备，再理解 `.img`、分区、文件系统，最后看 i.MX6ULL 的启动链路和 1 KiB 偏移。

如果你已经熟悉分区和块设备，可以从第 4 章开始。第 4 章先聊为什么不再手工拷贝 `zImage`、DTB 和 rootfs；第 5 章拆开 `.img` 看里面的偏移和分区；第 6 章回到脚本本身，看看 Bash 是怎么把这些东西拼起来的；第 7 章处理最实际的问题：镜像到底要多大、SD/eMMC 参数怎么选、报错时先看哪里。

如果你已经有镜像了，可以直接看第 8 章的 SD 卡直写。目标是板载 eMMC 的话，看第 9 章：先用 UUU 把 U-Boot 跑进 RAM，再用 UMS 把 eMMC 暴露给主机。

如果你只是想快速查命令，可以直接跳到 [镜像构建命令速查](../commands/01_image_builder_commands) 或 [烧录命令速查](../commands/04_flashing_commands)。

## 延伸笔记

- [SD 卡烧录 Bring-up 笔记](../../notes/2026-06-08-sd-card-flashing-bringup.md)
- [UUU + UMS + eMMC Bring-up 笔记](../../notes/2026-06-08-uuu-ums-emmc-bringup.md)

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../build/" variant="sub">← 构建进阶</ChapterLink>
  <ChapterLink href="../commands/" variant="sub">命令速查 →</ChapterLink>
</ChapterNav>
