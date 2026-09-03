---
title: 调试与排错
---

<PageHeader icon="🐞" title="调试与排错" description="gdbserver 远程调试、strace/日志/coredump、串口日志阅读——板子出问题时，咱们从零到定位的三篇" />

## 为什么需要一卷调试

板子出问题的时候，咱们手里剩下的交互界面往往只有一个串口。程序崩了，shell 里留下一行 Segmentation fault；驱动 insmod 完悄无声息，dmesg 里翻不出 probe 的痕迹；更狠的是内核停在启动半路，连登录提示符都不出来。没有弹窗，没有任务管理器，串口吐出来的那几屏文本就是全部线索。读不出病灶，剩下的事全靠猜。能不能从日志里把病灶挑出来，决定咱们是半小时收工，还是通宵换着法子试。

其实咱们这个仓库的调试素材一直都有，只是散落各处：Buildroot 卷有构建侧排错，内核卷教启动日志怎么看，驱动卷讲 kgdb 这类内核态手段，QEMU 卷存了一篇完整的触摸排查实录，宿主 gdb 的基本功 Linux 基础卷也教过了。

缺的是一条把它们串起来的主线：程序在板子上崩了，咱们该从哪下手；断点怎么跨过交叉编译打到板子上；启动卡住时，怎么把日志切成一段一段定位。本卷补的就是这条线，三篇，只管用户态与串口可见的证据；别的卷已经讲清楚的内容，直接给链接，您按需跳过去看。

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_gdbserver_remote_debug.md">gdbserver 远程调试全链</ChapterLink>
  <ChapterLink num="02" href="02_strace_log_coredump.md">strace、日志与 coredump</ChapterLink>
  <ChapterLink num="03" href="03_serial_log_reading.md">串口日志阅读路线</ChapterLink>
</ChapterNav>

::: tip 专栏定位（路径上下文规范）
本卷每章开头交代清楚在哪个目录、对哪棵源码、用什么工具链操作；正文每个命令块的首行注释标明执行位置：主机命令默认在仓库根 ~/imx-forge，虚拟机或板端命令默认在 / 或 /root，交叉工具链在 /opt/arm-gnu-toolchain。命令离开路径上下文就没法照抄。这是 Issue #101 里提的第一条诉求，本卷把它定为必须遵守的规矩；咱们照着走，命令才能原样落地。
:::

::: info 前置知识
咱们得走过 [Buildroot 构建](../buildroot/)——gdbserver 与 strace 的部署要动 Buildroot 配置；宿主 gdb 的基本功在 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md) 里教过；串口工具您按 [串口工具使用](../start/04_serial_tools_minicom.md) 备好就行。手边没有板子的朋友，走 [QEMU 板级模拟](../emu/) 也能完成本卷各篇的等价验证。
:::

## 三篇怎么走

01 是整卷的地基。远程链路打通之后，宿主的交叉 gdb 与板端的 gdbserver 就都握在咱们手里：02 分析 coredump 用的正是同一支交叉 gdb，03 里读到的可疑行为，您也随时可以用断点停下来对质。把 01 走通，后面两篇要用的工具就都是现成的。

02 与 03 互相独立，您按症状跳读：程序能跑但行为不对，或者干脆崩掉，去 02；板子进不了 shell、卡在启动半路，去 03。两篇没有先后依赖，缺哪补哪。

## 出问题了从哪篇读起

排查从对号入座开始，咱们把常见症状的入口列成一张表：

| 症状 | 先去哪 | 为什么 |
|------|------|------|
| 程序崩了、结果不对 | [02 strace、日志与 coredump](02_strace_log_coredump.md) | 先日志再 strace 最后 core，便宜的在前面 |
| 要断点单步 | [01 gdbserver 远程调试全链](01_gdbserver_remote_debug.md) | 远程链路是唯一途径 |
| 板子启动不了、卡在某段 | [03 串口日志阅读路线](03_serial_log_reading.md) | 分段地图先定位卡在哪 |
| 构建挂了 | [Buildroot 调试与排错](../buildroot/10_debugging.md) | 构建侧排错是它的主场 |
| 内核态、Oops 深入 | [内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) 与 [驱动开发入门](../kernel/07_driver_basic.md) | kgdb 与内核调试 |
| 串口连不上 | [串口工具使用](../start/04_serial_tools_minicom.md) | minicom 配置与排障 |
| NFS、TFTP 起不来 | [WSL2 开发注意事项](../workflow/01_wsl2_env_config.md) 与 [NFS 挂载](../rootfs/05_nfs_wsl_troubleshoot.md) | 网络与挂载 |

表里 NFS 那行的落点，笔者在本机核实过：rootfs 卷的目录与卷索引里，它都叫 05_nfs_wsl_troubleshoot，您照着链过去不会扑空：

```bash
# 主机 ~/imx-forge
ls document/tutorial/rootfs/
grep -n "nfs" document/tutorial/rootfs/index.md | head -5
```

```text
01_rootfs_overview.md
02_busybox_compile.md
03_inittab_init.md
04_rootfs_structure.md
05_nfs_wsl_troubleshoot.md
06_apps_integration.md
07_module_autoload.md
index.md
14:  <ChapterLink num="05" href="05_nfs_wsl_troubleshoot">NFS 挂载</ChapterLink>
```

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../practical/" variant="sub">← 实战演练</ChapterLink>
  <ChapterLink href="../project/" variant="sub">应用项目 →</ChapterLink>
</ChapterNav>
