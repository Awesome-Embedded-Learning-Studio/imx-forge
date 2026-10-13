---
title: 内核
---

<PageHeader icon="🐧" title="内核教程" description="从零把主线 Linux 7.2.9 带上 i.MX6ULL：环境、配置、设备树、编译首启与外设驱动" />

## 这一套卷讲什么

一句话：不依赖任何厂商补丁，从 kernel.org 的主线源码出发，把 Linux 7.2.9 移植到正点原子的 i.MX6ULL 板子上并跑通全部外设。主线内核原生支持这块板子的 18 项验收功能，咱们要亲手做的只有三件事：配置、设备树、编译。每条命令的输出都实跑采集，您照着做应当能复现同样的结果。

| 项目 | 说明 |
|------|------|
| **内核源码** | 您自己克隆的 stable 树（02/03 篇动手，落在 ~/experiments/linux-mainline） |
| **版本** | Linux 7.2.9，stable 团队 2026-10-03 发布，已在板子实测：LCD、触摸、双网口、音频全通 |
| **补丁** | 内核侧零补丁；板级差异全部落在您自己写的设备树与配置里 |
| **BSP 轨道** | 已退役（项目早期用过 NXP BSP 6.12.x，2026-09 单轨化） |

## 章节目录

| 文件 | 标题 | 说明 |
|------|------|------|
| [00_kernel_overview.md](00_kernel_overview) | 内核概述 | 内核是什么、主线与 BSP 的分野、源码目录地图、启动流程 |
| [01_why_mainline.md](01_why_mainline) | 为什么要折腾主线内核 | 主线与厂商 BSP 的根本差异与取舍 |
| [02_env_setup.md](02_env_setup) | 编译环境搭建 | 依赖安装、交叉工具链配置 |
| [03_source_fetch.md](03_source_fetch) | 取源码 v7.2.9 | stable 树与主树的分工、浅克隆、版本验证 |
| [04_bsp_vs_mainline.md](04_bsp_vs_mainline) | BSP vs 主线对比 | DRM 显示子系统、设备树 binding 变化 |
| [05_defconfig.md](05_defconfig) | 读懂一份 defconfig | 配置机制、基线铺建、差距盘点 |
| [06_defconfig_customize.md](06_defconfig_customize) | 做出自己的 defconfig | menuconfig、savedefconfig、内置与模块取舍 |
| [07_dts_writing.md](07_dts_writing) | 设备树：从参考板改出 AES 板 | 参考板方法、节点精读、板级文件写作 |
| [08_dts_build_boot.md](08_dts_build_boot) | 编译、外挂模块与 QEMU 首启 | zImage/dtb 编译、模块首编、15 项断言验收 |
| [09_display_drm.md](09_display_drm) | DRM 显示系统移植 | eLCDIF/mxsfb 驱动深读，LCD 链路逐段拆解 |
| [10_touch_gt9xx.md](10_touch_gt9xx) | 触摸屏移植 | GT9147/Goodix 驱动配置与双轨地址口径 |
| [11_network_dual_phy.md](11_network_dual_phy) | 双网口移植 | FEC + KSZ8081 以太网配置 |
| [12_debug_tricks.md](12_debug_tricks) | 调试技巧 | dmesg 分析、设备树验证、DRM 调试 |
| [13_common_issues.md](13_common_issues) | 常见问题 | 报错速查表、GPIO 冲突解决 |
| [14_kernel_modules.md](14_kernel_modules) | 内核模块 | 模块机制深入：加载、符号、依赖 |
| [15_wsl_network_boot.md](15_wsl_network_boot) | 网络启动 | WSL2 里的 TFTP/NFS 启动链路 |
| [16_driver_basic.md](16_driver_basic) | 驱动基础 | 字符设备 Concepts，驱动开发的入场姿势 |
| [17_kernel_boot_debug.md](17_kernel_boot_debug) | 启动调试 | 启动逐阶段排查与调试手段 |

等您想把内核机制钻深一层，[core-functional/](core-functional/) 子卷就是第二条线：并发、原子操作、自旋锁、中断、时间管理与阻塞 I/O 模型，共 11 章，咱们建议配合驱动篇一起吃。

## 快速开始

1. 读 [00_kernel_overview.md](00_kernel_overview)，跟咱们建立内核整体地图
2. 读 [01_why_mainline.md](01_why_mainline)，明白这套卷为什么押主线
3. 跟 [02_env_setup.md](02_env_setup) 备齐工具链，按 [03_source_fetch.md](03_source_fetch) 把 v7.2.9 克隆到手
4. 按 [05](05_defconfig)/[06](06_defconfig_customize) 两篇做出您自己板子的 defconfig，按 [07](07_dts_writing)/[08](08_dts_build_boot) 两篇写出板级设备树并完成 QEMU 首启
5. 外设深读按需进 [09](09_display_drm)/[10](10_touch_gt9xx)/[11](11_network_dual_phy)，您卡住了就翻 [12](12_debug_tricks)/[13](13_common_issues)
6. 想深入模块与驱动，走 [14](14_kernel_modules)/[16](16_driver_basic)；真板部署走 [15](15_wsl_network_boot)/[17](17_kernel_boot_debug)

## 硬件平台

- **芯片**：NXP i.MX6ULL (ARM Cortex-A7, 528MHz)
- **开发板**：正点原子 i.MX6ULL
- **显示**：7 寸 LCD (1024×600)
- **触摸**：Goodix GT9147
- **网络**：双 KSZ8081 PHY (RMII)

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="00_kernel_overview" variant="sub">从内核概述开始</ChapterLink>
  <ChapterLink href="../" variant="sub">← 返回教程总目录</ChapterLink>
</ChapterNav>
