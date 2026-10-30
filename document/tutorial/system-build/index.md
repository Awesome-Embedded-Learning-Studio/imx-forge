---
title: 系统构建
---

<PageHeader title="系统构建" description="从一块裸板到能登录的系统:工具链 → U-Boot → 内核 → rootfs → Buildroot → 整机启动" />

## 这个分区的顺序

这是整站的主线,六步环环相扣。前一步的产物是后一步的输入,不建议跳序。

<ChapterNav>
  <ChapterLink num="01" href="../start/">入门准备</ChapterLink>
  <ChapterLink num="02" href="../uboot/">U-Boot 移植</ChapterLink>
  <ChapterLink num="03" href="../kernel/">内核移植</ChapterLink>
  <ChapterLink num="04" href="../rootfs/">根文件系统</ChapterLink>
  <ChapterLink num="05" href="../buildroot/">Buildroot 构建</ChapterLink>
  <ChapterLink num="06" href="../practical/">实战演练</ChapterLink>
</ChapterNav>

### 01 入门准备

路线图、工具链安装（ARM GNU Toolchain 15.2）、环境初始化、硬件接口速查、串口工具、首次上电检查。

### 02 U-Boot 移植

Bootloader 原理 → 编译与配置 → 移植概述 → 板级配置 → 设备树基础 → LCD 与网卡移植 → Logo 定制。目标:让板子先把屏幕点亮、把网络拉起来。

### 03 内核移植

主线单轨,统一收敛到上游 Mainline Linux。内核概述 → 取源码与配置 → 设备树写作与编译首启 → 显示/触摸/双网口 → 常用调试技巧与踩坑记录 → 模块开发与网络启动。

### 04 根文件系统

BusyBox 手搓最小 rootfs:rootfs 概述 → BusyBox 编译 → inittab 与 init → 目录结构 → NFS 挂载排错 → 应用集成 → 模块自动加载。

### 05 Buildroot 构建

现行 rootfs 方案:br2-external 树、自定义包、Qt6 集成、ccache 与调试,从手搓迁移到工程化。

### 06 实战演练

把前面所有产物装配成一次完整启动:构建系统、启动与调试、NFS 实战体验。

## 学完往哪走

→ [烧录与进阶](../flashing/) 把镜像写进 SD 卡或 eMMC;
→ [驱动与实战](../driver-dev/) 开始写第一个字符设备驱动。
