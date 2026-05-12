<PageHeader icon="📁" title="根文件系统" description="根文件系统 (Rootfs) 是 Linux 运行时挂载的第一个文件系统，包含系统运行所需的所有程序和配置" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_rootfs_overview">Rootfs 概述</ChapterLink>
  <ChapterLink num="02" href="02_busybox_compile">BusyBox 编译</ChapterLink>
  <ChapterLink num="03" href="03_inittab_init">inittab 与 init</ChapterLink>
  <ChapterLink num="04" href="04_rootfs_structure">目录结构</ChapterLink>
  <ChapterLink num="05" href="05_nfs_wsl_troubleshoot">NFS 挂载</ChapterLink>
  <ChapterLink num="06" href="06_apps_integration">应用集成</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解根文件系统的作用，使用 BusyBox 构建最小 Rootfs，掌握 init 进程和 NFS 网络挂载配置。
:::

::: info 前置知识
Linux 文件系统基础 · Shell 脚本基础 · 网络基本概念
:::

::: details 延伸阅读
- [BusyBox 官方文档](https://busybox.net/FAQ.html)
- [Linux 文件系统层次标准](https://refspecs.linuxfoundation.org/FHS_3.0/)
- [init 系统](https://en.wikipedia.org/wiki/Init)
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../kernel/" variant="sub">← 内核教程</ChapterLink>
  <ChapterLink href="../driver/" variant="sub">驱动开发 →</ChapterLink>
</ChapterNav>
