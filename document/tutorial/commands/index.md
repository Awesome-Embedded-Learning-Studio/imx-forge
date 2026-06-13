---
title: 命令速查
---

<PageHeader icon="⌨️" title="命令速查" description="把镜像构建、镜像检查和存储工具命令集中放在一起，方便复制、核对和排错" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_image_builder_commands">镜像构建命令</ChapterLink>
  <ChapterLink num="02" href="02_image_inspection_commands">镜像检查命令</ChapterLink>
  <ChapterLink num="03" href="03_storage_tool_commands">存储工具命令</ChapterLink>
  <ChapterLink num="04" href="04_flashing_commands">烧录命令</ChapterLink>
</ChapterNav>

::: tip 使用方式
这里不是长篇教程，而是速查表。每条命令都尽量保持短小，方便从终端复制使用。
:::

::: warning 安全提醒
涉及 `dd`、真实块设备、UUU/UMS 的命令有破坏性。这里提供的是速查和安全检查，不替代完整烧录 bring-up 记录。
:::

## 相关教程

- [存储介质基础](../flash/01_storage_media_basics)
- [镜像、分区和文件系统](../flash/02_image_partition_filesystem_basics)
- [i.MX6ULL 启动链路与偏移](../flash/03_imx6ull_boot_flow_and_offsets)
- [为什么需要完整镜像](../flash/04_why_full_image)
- [镜像布局设计](../flash/05_image_layout_design)
- [脚本设计拆解](../flash/06_build_imx6ull_image_script)
- [镜像大小与使用](../flash/07_image_size_and_usage)
- [SD 卡烧录实战](../flash/08_sd_card_flashing)
- [UUU + UMS eMMC 烧录实战](../flash/09_uuu_ums_emmc_flashing)

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../flash/" variant="sub">← 镜像构建教程</ChapterLink>
  <ChapterLink href="../build/" variant="sub">构建进阶 →</ChapterLink>
</ChapterNav>
