---
title: U-Boot
---

<PageHeader icon="🚀" title="U-Boot 教程" description="主线十四站带你从官方源码走到自己板卡上的 Linux，扩展卷 boot-chain 十六篇拆 U-Boot 自己是怎样启动的" />

## 主线 · 十四站走通移植

<ChapterNav>
  <ChapterLink num="01" href="01_what_is_uboot">从0开始认识 U-Boot：启动全景</ChapterLink>
  <ChapterLink num="02" href="02_uboot_compile">源码与环境准备</ChapterLink>
  <ChapterLink num="03" href="03_first_build">第一次编译官方参考板</ChapterLink>
  <ChapterLink num="04" href="04_verify_and_flash">产物验证与烧录</ChapterLink>
  <ChapterLink num="05" href="05_serial_acceptance">串口验收：进命令行</ChapterLink>
  <ChapterLink num="06" href="06_aes_vs_evk_diff">净源码里没有咱们的板卡：逐行对账</ChapterLink>
  <ChapterLink num="07" href="07_board_porting">七步造出咱们的板卡</ChapterLink>
  <ChapterLink num="08" href="08_device_tree_aes">设备树：imx6ull-aes 来历</ChapterLink>
  <ChapterLink num="09" href="09_ddr_imxheader">DDR 初始化与镜像头</ChapterLink>
  <ChapterLink num="10" href="10_emmc_acceptance">存储验收：eMMC</ChapterLink>
  <ChapterLink num="11" href="11_env_bootcmd">环境变量与 bootcmd</ChapterLink>
  <ChapterLink num="12" href="12_boot_linux">启动 Linux</ChapterLink>
  <ChapterLink num="13" href="13_tftp_netboot">tftp 网络启动</ChapterLink>
  <ChapterLink num="14" href="14_debug_reference">调试命令速查与排错</ChapterLink>
</ChapterNav>

::: tip 学习目标
按主线顺序走完十四站，你手里会有一块跑着自己编译的 U-Boot、能进命令行、能存取 eMMC、能把 Linux 内核拉起来的板子；板卡适配的每一步都对着仓库补丁讲清为什么。
:::

::: info 前置知识
C 语言基础 · 嵌入式系统基本概念 · Linux 命令行操作 · 交叉编译工具链（start 卷有安装指引）
:::

手上暂时没有板子的朋友，从 [为什么要给开发板找替身](../emu/01_why_emulation.md) 走仿真路。

## 扩展卷 · boot-chain 启动深读

主线告诉你怎么做，扩展卷告诉你为什么：BootROM 怎么挑介质、IVT 与 DCD 逐字节是什么、U-Boot 怎么把自己搬进 DDR、交棒内核那一刻发生了什么。四段十六篇，入口在 [boot-chain 启动深读](./boot-chain/)。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../start/" variant="sub">← 入门准备</ChapterLink>
  <ChapterLink href="../kernel/" variant="sub">内核教程 →</ChapterLink>
</ChapterNav>
