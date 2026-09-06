---
title: 第一次上电与串口检查
---

# 第一次上电与串口检查

> 本篇是咱们第一次给板子上电的检查清单——该看什么、日志卡在哪意味着什么。配合 [practical/03 启动与调试](../practical/03_boot_and_debug.md) 食用。

## 一、上电前检查清单

- [ ] 电源 5V/2A 接好，极性正确
- [ ] 拨码开关指向目标启动介质（SD/eMMC/NFS，见 [flash/04](../flash/04_imx6ull_boot_flow_and_offsets.md)）
- [ ] SD 卡 / eMMC 已烧录镜像（见 [flash/09](../flash/09_sd_card_flashing.md)、[flash/10](../flash/10_uuu_ums_emmc_flashing.md)）
- [ ] 串口线接好：GND-GND、TX-RX、RX-TX（交叉，见 [串口工具](04_serial_tools_minicom.md)）
- [ ] 串口工具已开，波特率 115200 8N1，流控关闭
- [ ] （NFS 启动）TFTP/NFS 服务已起、防火墙已放行

## 二、上电流程

咱们按三步走：

1. 您先打开串口工具（`minicom` 或 `picocom -b 115200 /dev/ttyUSB0`）；
2. 给板子上电；
3. 观察串口输出。

## 三、启动日志检查点

您会看到正常启动依次经过这几个阶段，卡在哪个阶段就查哪个：

### 1. U-Boot 阶段

```text
U-Boot 2024.x ...
CPU: Freescale i.MX6ULL
DRAM: 512 MiB
...
Hit any key to stop autoboot:  0
```

- **没有 U-Boot 输出** → 串口接错 / 波特率错 / 流控没关 / 拨码启动介质错
- **卡在 DRAM** → 硬件问题（内存）
- **autoboot 倒计时** → 按 Enter 进 U-Boot 命令行调试

### 2. 内核阶段

```text
Starting kernel ...
Booting Linux on physical CPU 0x0
Linux version 7.1.0 ...
```

- **Starting kernel 后无输出** → 内核镜像/DTB 没加载、console 参数错
- **kernel panic** → 看 panic 信息，常见是 rootfs 没挂载上（见下）

### 3. rootfs 挂载

```text
VFS: Mounted root (nfs filesystem) on device 0:10.
Freeing unused kernel memory
```

- **VFS: Unable to mount root fs** → NFS/SD/eMMC 没准备好、`root=` 参数错
- **NFS 超时** → 见 [WSL2 NFS 踩坑](../rootfs/05_nfs_wsl_troubleshoot.md)

### 4. 登录提示符

```text
Welcome to Buildroot
imx6ull login:
```

看到这个就成了！您输入 `root`（无密码，或按 rootfs 配置）登录。

## 四、常见上电问题速查

| 现象 | 排查方向 |
|------|----------|
| 串口完全无输出 | 串口接线、波特率、流控、拨码开关 |
| U-Boot 起来但内核不起 | 内核/DTB 镜像损坏、bootargs、加载地址 |
| kernel panic: VFS | rootfs 未就绪、`root=` 参数、NFS 服务 |
| 启动到一半重启 | 电源不足（换 5V/2A）、看门狗复位 |
| 网络启动 TFTP 超时 | 防火墙、TFTP 目录权限、Mirrored 模式 |
| 串口乱码 | 波特率不是 115200 |

::: tip 救命稻草：U-Boot 命令行
咱们在启动倒计时时按 Enter 进入 U-Boot 命令行，可以 `printenv` 看环境变量、`bootd` 重新启动、手动 `tftp`/`load` 测试镜像。见 [U-Boot 教程](../uboot/)。
:::

## 继续学习

- 串口工具：[串口工具使用（minicom）](04_serial_tools_minicom.md)
- 启动流程详解：[flash/04 启动流程与偏移](../flash/04_imx6ull_boot_flow_and_offsets.md)
- 实战启动调试：[practical/03 启动与调试](../practical/03_boot_and_debug.md)
- 启动失败排查：[kernel/mainline/11 常见问题](../kernel/mainline/11_common_issues.md)
- 出问题了从哪篇读起：[调试与排错卷的路标表](../debug/)
