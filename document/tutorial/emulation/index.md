---
title: 模拟与调试
---

<PageHeader title="模拟与调试" description="两条退路:没有板子怎么跑,跑不通怎么查" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="../emu/">QEMU 板级模拟</ChapterLink>
  <ChapterLink num="02" href="../debug/">调试与排错</ChapterLink>
</ChapterNav>

### QEMU 板级模拟

把 AES 板「搬」进 QEMU:mcimx6ul-evk 机器模型解剖、rootfs 镜像制作、外设模型补丁、GT911 触摸联调、与真机的一致性验证。用的是同一份设备树、同一个 mainline 内核、同一套 Buildroot rootfs。

没有板子的读者,这条路能走通启动链和绝大多数驱动行为;有板子的读者,它可以当回归测试基线。

### 调试与排错

gdbserver 远程调试内核与模块、`strace` / 日志 / core dump 三板斧、串口日志的正确读法。三篇都是「卡住时自查」的内容。

## 建议的使用时机

不必等学完才来。遇到下列情况直接跳进来:

| 症状 | 去哪 |
| --- | --- |
| 板子还没到,想先动手 | [QEMU 板级模拟](../emu/01_why_emulation) |
| 内核启动卡在某个阶段 | [启动调试](../kernel/17_kernel_boot_debug) |
| 驱动 `insmod` 后无反应 | [gdbserver 远程调试](../debug/01_gdbserver_remote_debug) |
| 进程莫名退出 / 段错误 | [strace 与 core dump](../debug/02_strace_log_coredump) |
| 串口一堆乱码或刷屏 | [串口日志读法](../debug/03_serial_log_reading) |
