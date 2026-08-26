---
title: QEMU 板级模拟
---

<PageHeader icon="🖥️" title="QEMU 板级模拟" description="把 i.MX6ULL 开发板搬进 QEMU:从机器模型解剖、rootfs 镜像制作,到连环 panic 打地鼠与三件套工具链封装的完整实录" />

## 没有板子,也能把整条启动链跑通

咱们这个项目一路走来,所有验证都压在一件事上:手边得有真板。内核编完,烧板看串口;驱动写完,挂板量引脚;CI 只查「文件在不在、像不像 ARM 镜像」,至于产物能不能开机,机器替咱们试不了。没有板子的朋友更是被挡在门外——教程看得再明白,`insmod` 敲下去是什么手感,想象不出来。

这个卷解决的就是这件事:把 AES 板「搬」进 QEMU,跑咱们自己的 mainline 内核、自己的设备树、Buildroot 的 rootfs。这条路笔者在 2026 年 8 月完整走了一遍,从串口零输出,到 `buildroot login:` 登录进去跑命令,中间踩了一整串坑。本卷五章就是这次折腾的复盘,写法上偏向「跟着敲」:每一章的关键结论,前面都有一条咱们自己敲过的命令和它吐出来的真实输出兜底——打地鼠九轮的原始串口日志(`qemu3.log` 到 `qemu11.log`)、干净启动(`boot-clean.log`)、登录会话(`session-login.log`)全收在本卷 `assets/` 目录里,欢迎对照着读。

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_why_emulation.md">为什么要给开发板找替身:QEMU、Renode 与生态位</ChapterLink>
  <ChapterLink num="02" href="02_machine_model.md">QEMU 眼里的 i.MX6ULL:真模型、纸糊的桩与纯粹的空气</ChapterLink>
  <ChapterLink num="03" href="03_rootfs_image.md">rootfs 变 SD 卡:一张会被当场拒收的镜像</ChapterLink>
  <ChapterLink num="04" href="04_whack_a_mole.md">打地鼠八连:从串口死寂到 buildroot login</ChapterLink>
  <ChapterLink num="05" href="05_toolchain.md">三件套封装:run-qemu.sh 与防陈旧的自动重建</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解 QEMU 对 i.MX6ULL 的模拟边界(真模型、桩、地址空洞三档,以及 `info mtree` 怎么看家底),掌握 QEMU 变体设备树的设计与编译管线、rootfs 镜像制作与 SD 卡模拟的约束,吃透「external abort 杀内核」这类问题的完整读法(earlycon + PC/pte/寄存器三路互证),最后用一套带新鲜度检查的脚本把模拟环境固化下来。
:::

::: info 前置知识
需要咱们已经走过 [内核构建](../kernel/) 与 [Buildroot rootfs](../buildroot/) 的章节——`out/mainline/linux/arch/arm/boot/zImage`、`imx6ull-aes.dtb` 和 `out/release-latest/rootfs/` 这三样产物在手上,本卷的内容才有地方落地。设备树的 `status` 属性、`compatible` 匹配驱动这些概念不陌生(不熟的话先翻 [驱动教程](../driver/) 相关章节)。
:::

## 路线图:后面还有什么

本卷五章覆盖的是「直启链路」——内核 + dtb + rootfs 直接进 QEMU,用发行版自带的 QEMU 8.2 就能全链路跑通的部分。再往前还有两级,素材落地后继续补章:一级是 CI 冒烟,把 `run-qemu.sh --smoke` 挂进 GitHub Actions,让每次内核提交自动回答「能不能开机」;另一级是外设深潜,给 ap3216c、icm20608 这些教学传感器写 QEMU 器件模型,让驱动章节的 `.ko` 也能在模拟器里真跑。那是另一场折腾,笔者的手已经痒了。

::: info 配套产物
本卷所有脚本已进仓库 `scripts/qemu_helper/`(三个脚本的用法详解见 [run-qemu.sh 文档](../../scripts/qemu_helper/run-qemu.sh.md)、[make-rootfs-img.sh 文档](../../scripts/qemu_helper/make-rootfs-img.sh.md) 与 [make-qemu-dtb.sh 文档](../../scripts/qemu_helper/make-qemu-dtb.sh.md));选型调研的完整证据链(四路调研、版本时间线、外设覆盖矩阵)见开发笔记 [QEMU 板级模拟调研](../../notes/2026-08-25-qemu-board-emulation-research)。
:::
