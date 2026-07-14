---
title: Buildroot 根文件系统
---

<PageHeader icon="📦" title="Buildroot 根文件系统" description="用 Buildroot 2026.02 自动化构建 i.MX6ULL 的用户空间 rootfs:从工作原理到 Qt6 集成的完整实战" />

## 为什么要折腾 Buildroot

说实话，IMX-Forge 一开始也是手搓 BusyBox 起家的——自己 `menuconfig`、自己合并 overlay、自己写一堆 `merge_overlay_rootfs.sh`。这套路子跑通了没问题，但越往后越别扭:今天加个 alsa 配置要手改 rootfs,明天上 Qt6 又得手编一坨依赖,每次重建 rootfs 都像是在做手工活,稍微换个组件就得从头来一遍。折腾到后面你会发现,自己维护的那套脚本,本质上就是在重复造一个简陋版的 Buildroot。

那为什么不上 Yocto?Yocto 当然强大,但它那套 layer + recipe + bitbake 的体系对个人项目来说太重了,光是把环境拉起来就要半天,layer 之间的覆盖关系能让人研究一星期。我们的诉求很明确:要一个能一键重建、可复现、又不需要学一套新 DSL 的 rootfs 构建系统。Buildroot 正好卡在这个甜点位上,它就是一堆 Makefile + Kconfig,跟内核、U-Boot 的配置思路一脉相承,会 `make menuconfig` 基本就会用 Buildroot。

这里有一点必须先讲清楚,免得你产生误会:IMX-Forge 的 Buildroot **只管 Stage 3+4,也就是用户空间 rootfs**。kernel 和 U-Boot 仍然走 `scripts/build_helper/` 那套外部双轨构建,产物落在 `out/release-latest/{uboot,linux}/`;Buildroot 这边不设 `BR2_LINUX_KERNEL`、不设 `BR2_TARGET_UBOOT`,它只负责把用户空间这一摊打包好,吐到 `out/release-latest/rootfs/`,最后由 `build_imx6ull_image.sh` 把三部分组装成完整的烧录镜像。这种"各管一段、最后拼装"的分工,比让 Buildroot 一把梭去编内核要干净得多,也方便我们单独替换某一块。

这一章我们从 Buildroot 的工作原理讲起,走到 Qt6 集成和从手搓 rootfs 的迁移对照,12 章打通。

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_how_buildroot_works.md">Buildroot 工作原理</ChapterLink>
  <ChapterLink num="02" href="02_first_build.md">第一次构建 IMX-Forge rootfs</ChapterLink>
  <ChapterLink num="03" href="03_external_toolchain.md">External Toolchain 复用</ChapterLink>
  <ChapterLink num="04" href="04_kconfig_fragments.md">配置体系:Kconfig/menuconfig/fragments</ChapterLink>
  <ChapterLink num="05" href="05_br2_external_tree.md">br2-external tree 逐文件</ChapterLink>
  <ChapterLink num="06" href="06_rootfs_customization.md">Rootfs 定制三板斧</ChapterLink>
  <ChapterLink num="07" href="07_custom_package.md">添加自定义 package</ChapterLink>
  <ChapterLink num="08" href="08_init_system.md">Init 系统</ChapterLink>
  <ChapterLink num="09" href="09_ccache_rebuild.md">ccache 与重建策略</ChapterLink>
  <ChapterLink num="10" href="10_debugging.md">调试与排错</ChapterLink>
  <ChapterLink num="11" href="11_qt6_integration.md">Qt6 集成实战</ChapterLink>
  <ChapterLink num="12" href="12_migration_guide.md">手搓→Buildroot 迁移对照</ChapterLink>
</ChapterNav>

::: tip 学习目标
用 Buildroot 2026.02 一键构建 i.MX6ULL 的可复现 rootfs,理解 br2-external tree 的组织方式,掌握配置 fragments、自定义 package、init 系统选型,最终把 Qt6 应用跑起来,并能把旧的手搓 rootfs 平滑迁移过来。
:::

::: info 前置知识
建议先读 [手搓 Rootfs](../rootfs/) 那几章,至少对 BusyBox + inittab + overlay 的传统做法有点手感,这样你才能体会到 Buildroot 到底替你省了哪些事;构建工具链相关的内容可以看 [构建系统教程](../build/)。
:::

::: details 延伸阅读
- [Buildroot 官方手册](https://buildroot.org/downloads/manual/)——遇到任何拿不准的配置项,第一份资料就是它
- [IMX-Forge Buildroot External Tree README](https://github.com/Charliechen114514/imx-forge/blob/main/rootfs/buildroot/README.md)——本仓库 br2-external tree 的设计说明
:::

## 学习路径建议

这 12 章大致分成两段。**基础篇是 01 到 06**,从 Buildroot 到底在干什么讲起,然后带你跑通第一次构建;接着是 external toolchain 复用、Kconfig fragments 配置体系,再逐文件拆解我们仓库里的 br2-external tree,最后落到 rootfs 定制的三板斧:overlay、post-build 脚本、post-image 脚本。跑完这一段,你就具备了改 defconfig、加配置、定制文件系统的能力,日常使用基本够用。

**进阶篇是 07 到 12**,开始往深里走:加一个自己的 package、选 init 系统(BusyBox init 还是 SysV)、用 ccache 加速重建、排查那些一看就头大的构建错误,最后是两块硬骨头:把 Qt6 集成进 Buildroot rootfs,以及一份从手搓 rootfs 迁移过来的对照表。如果你是从旧版 IMX-Forge 升级过来的,可以直接跳到第 12 章看迁移对照,再按需回头补基础篇。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../rootfs/" variant="sub">← 手搓 Rootfs 原理</ChapterLink>
  <ChapterLink href="../kernel/" variant="sub">内核教程 →</ChapterLink>
</ChapterNav>
