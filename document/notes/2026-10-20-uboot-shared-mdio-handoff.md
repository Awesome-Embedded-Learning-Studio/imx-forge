---
title: U-Boot 2026.10 与 Linux SD 启动修复
description: "AES 板镜像布局、默认环境、共享 MDIO、LCDIF 交接及 Linux 电源依赖与 Goodix 排查记录"
---

# U-Boot 2026.10 与 Linux：AES SD 启动修复记录

U-Boot 修复后的真板结果：应用共享 MDIO 和 LCDIF 清理顺序修复后，U-Boot 已成功交接
Linux。SD 卡被识别为 `mmcblk0`，根分区 `mmcblk0p2` 在约 13.83 秒挂载，
BusyBox init 执行成功，进入 `imx6ull-minimal#` 串口 shell。

正式变更集中在 `patches/uboot-mainline/charlies_board.patch`：修正 U-Boot
SNVS 引脚归属、PHY 复位引脚组和电源启动状态；环境偏移移至 4 MiB；删除
提前截断默认环境的额外 NUL；启用 DM MDIO；移除 LCDIF 提前关钟操作。

交接阶段的故障：AES 双网口使用 FEC2 节点下的同一条 MDIO 总线。两个网口均能
枚举，SD 内核和 DTB 均能加载，但打印 `Starting kernel ...` 后重新进入
U-Boot，尚无 Linux 串口输出。

## 镜像布局与默认环境

最初的日志停在 `Net:`，有时重新打印 U-Boot 横幅；之后还出现过能进入
命令行，但 `run sdbootaes` 提示未定义的情况。这些现象需要分开定位：
环境 CRC、默认环境内容、引脚初始化和 OS 交接各有独立问题。
`Reset cause: POR` 本身不足以证明是供电故障。

### 环境区不能覆盖 U-Boot

原 `CONFIG_ENV_OFFSET=0xE0000`，即磁盘 896 KiB，环境区大小为 8 KiB。
本次带内置 Logo 的 `u-boot-dtb.imx` 约 1.62 MiB，从磁盘 1 KiB 写入；
因此旧环境区位于 U-Boot 文件内部。此前在 896 KiB 清零 8 KiB 的手工制卡
步骤会覆盖镜像内容，后续 `saveenv` 也会写入同一区域。

AES defconfig 已改为 `CONFIG_ENV_OFFSET=0x400000`，仍使用
`CONFIG_ENV_SIZE=0x2000`。本次最小诊断镜像的布局如下：

| 区域 | 起点 | 大小或边界 |
| --- | --- | --- |
| MBR 分区表 | 0 | 512 B |
| U-Boot | 1 KiB | 必须结束于 4 MiB 环境区之前 |
| MMC 环境 | 4 MiB | 8 KiB |
| p1：ext4，标签 boot | 8 MiB，扇区 16384 | 64 MiB，含 zImage 和 imx6ull-aes.dtb |
| p2：ext4，标签 rootfs | 72 MiB，扇区 147456 | 64 MiB，最小 BusyBox 根文件系统 |
| 镜像末尾 | 144 MiB | 本次诊断镜像总大小 |

这是本次 `out/sdcard/` 诊断镜像的布局，其他镜像生成器的默认分区起点
应以各自产物为准。写环境之前必须同时核对编译配置和实际分区表，不能继续
沿用旧的 896 KiB 清零命令。

`bad CRC, using default environment` 表示没有读到有效的持久化环境，
U-Boot 会回退到编译时默认值；这条警告本身不是重启原因。本次打包写入
CRC 有效的 MMC 环境，并校验环境区与 U-Boot、p1 均不重叠。

### sdbootaes 未定义来自默认环境被提前截断

`include/configs/mx6ull_aes_emmc.h` 的 `CFG_MFG_ENV_SETTINGS` 在
`sd_dev=0\0` 后多拼接了一个 `\0`，形成环境结束标记。后续
`CFG_EXTRA_ENV_SETTINGS` 中的启动别名因此没有进入有效默认环境。
已删除多余 NUL；检查构建产物时，默认变量从 21 项恢复到 49 项，包含
`sdbootaes`、`sdargs`、`console` 和 `fdt_addr`。

镜像内持久化环境与编译时默认环境是两个检查对象：有效的旧环境不会因
更换 U-Boot 自动变成新默认值。本次诊断镜像沿用可启动的变量集合，显式加入
`sdbootaes`，而不是仅依赖编译时默认值。当前镜像保留 `bootdelay=-1`，
需要在提示符执行 `run sdbootaes`。

### U-Boot 的 SNVS 引脚归属

i.MX6ULL 的 SNVS 引脚属于独立的 `0x02290000` 控制器。
板级 DTS 将外设电源使能、BOOT_MODE GPIO、PHY 复位和耳机检测引脚组
移入 `&iomuxc_snvs`，使用 `MX6ULL_PAD_*` 偏移；两个 FEC 的 pinctrl
显式加入各自 PHY 复位组，耳机检测从 SAI2 的普通引脚组拆出。
外设电源补充 `regulator-boot-on`，与 U-Boot 初始化时需要保持供电的状态一致。
这些修改与下述 MDIO/LCDIF 修复一起保存在正式板级补丁中。

## 共享 MDIO 的清理问题

`boot/bootm.c:bootm_final()` 先打印 `Starting kernel ...`，随后执行
`board_quiesce_devices()` 和 `dm_remove_devices_active()`。这条横幅本身不能
证明已经调用内核入口。

未启用 `CONFIG_DM_MDIO` 时，`drivers/net/fec_mxc.c:fecmxc_remove()` 对每个
FEC 都执行 `mdio_unregister(priv->bus)` 和 `mdio_free(priv->bus)`。
`CONFIG_DM_ETH_PHY` 又使两个 FEC 取得相同的总线对象，因此存在重复清理问题。

上游 Kontron i.MX6UL 板已有同类配置修复：
[8377214282d0](https://github.com/u-boot/u-boot/commit/8377214282d00989722e1ff0ea83e6234f99564d)
（`imx: kontron-sl-mx6ul: Enable CONFIG_DM_MDIO to fix boot abort`）。

AES defconfig 同样启用 `CONFIG_DM_MDIO=y`，由 MDIO uclass 管理总线生命周期。
板级补丁 `patches/uboot-mainline/charlies_board.patch` 已同步。

## 产物与验证范围

MDIO 单项修复阶段的镜像：`out/sdcard/aes-sd-v2026.10-minimal-mdio-fix.img`。
这是历史排查产物；还需合入后述 LCDIF 修复，才能完成已验证的真板交接。
镜像共 144 MiB，保留此前最小 BusyBox 镜像的内核、Linux DTB 和根文件系统，
更新 U-Boot，并沿用可进入控制台的 MMC 环境，在 `sdbootaes` 中添加 earlycon。
环境位于 4 MiB，boot 分区始于 8 MiB，rootfs 分区始于 72 MiB。

已完成编译、镜像载荷和环境 CRC 校验，以及补丁在锁定上游源码上的应用检查。
对比旧、新 ELF 的 `fecmxc_remove` 反汇编，确认新分支调用设备移除接口，
不再直接调用 `mdio_unregister` / `mdio_free`。
默认环境中的 `sdbootaes`、`console`、`sdargs`、`fdt_addr` 亦已核对。

最小 BusyBox 根文件系统此前已通过直接加载内核的 QEMU 启动验证；该验证
覆盖 Linux 到串口 shell。真板完整交接最终由下述联合修复后的日志版验证。

## 后续真板结果：LCDIF 清理顺序

启用 DM MDIO 后，真板仍停在 `Starting kernel ...`，本次日志没有再次打印
U-Boot 横幅。`dm tree` 确认 `mxs_video` 和 vidconsole 都处于已探测状态。

AES 的 `board_quiesce_devices()` 原先提前关闭 LCDIF 时钟，而后续
`dm_remove_devices_active()` 会调用 `mxs_video_remove()`。该驱动仍需写入
帧缓冲寄存器、等待 VSYNC 并复位 LCDIF，因此时钟必须维持到驱动清理完成。
板级 hook 已移除提前关钟操作，由驱动完成控制器停止。

独立的 `out/uboot-handoff-trace-src` 增加了直接写 UART1 的串口标记，覆盖
板级 quiesce、设备移除、缓存清理及内核入口分支。诊断补丁保存在
`out/uboot-handoff-trace` 供历史排查参考，不加入正式板级补丁；诊断源码中的
打印已在后续日志清理中移除。此日志版用于确认真板最后
执行到的阶段。`aes-sd-v2026.10-minimal-handoff-trace.img` 已由用户在真板
验证到最小 BusyBox shell；普通构建包含相同正式修复，但没有诊断串口标记。

## 最小 BusyBox 根文件系统

为缩小启动排查范围，本次用静态 ARM BusyBox `v1.37.0.git` 制作独立 rootfs。
BusyBox 可执行文件为 718068 B，文件树约 808 KiB，装入 64 MiB ext4 分区。
`/sbin/init` 使用 BusyBox init；`rcS` 挂载 proc、sysfs、devtmpfs、devpts，
并为 `/tmp`、`/run` 挂载 tmpfs，最后输出 `AES_MINIMAL_ROOTFS_READY`。
根文件系统包含 `/dev/console` 与 `/dev/null`，不依赖动态链接库。

串口通过以下 inittab 项进入 root shell，不经过登录认证：

```text
::sysinit:/etc/init.d/rcS
ttymxc0::respawn:-/bin/sh
::shutdown:/bin/sync
::shutdown:/bin/umount -a -r
```

真板日志依次出现 `VFS: Mounted root`、`Run /sbin/init`、
`AES_MINIMAL_ROOTFS_READY` 和 `imx6ull-minimal#`，才说明 SD 根分区、init
和串口 shell 这一条启动路径完成。这个 rootfs 用于诊断；Qt、完整 Buildroot
服务、音视频应用等整板功能不在这次验证范围内。

## Linux 延迟探测与 Goodix 修复（2026-10-20）

旧内核的 `CONFIG_REGULATOR` 未开启，模板只写了子驱动选项，这些选项被
Kconfig 丢弃。设备树中存在固定电源供应关系，设备只能在 10 秒 deferred-probe
超时后继续探测。模板已补 `CONFIG_REGULATOR=y`，重新生成配置，确认
FIXED_VOLTAGE、ANATOP、GPIO regulator 等所需驱动实际内建。
保留 `CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`，没有缩短超时或关闭依赖检查。

本次同步并重编当前 Linux DTS，镜像 DTB 不再包含 GPIO1_IO09 控制 SD 电源
的旧属性。该引脚只用于 GT9147 INT。Linux 中电源使能、PHY 复位、SPI GPIO、
蜂鸣器、耳机检测的 SNVS 引脚组也移入 `&iomuxc_snvs`，改用 i.MX6ULL SNVS
偏移，避免新启用的电源驱动访问旧的错误地址。

Goodix 修正包含：

- 节点改为 `touchscreen@14`，`reg = <0x14>`，采用本板历史验证过的地址。
- RESET/INT 都描述为 `GPIO_ACTIVE_HIGH`，匹配主线驱动的物理电平序列：
  RESET 拉低 → INT 拉高选择 0x14 → RESET 拉高 → INT 同步后切输入。
  原 `GPIO_ACTIVE_LOW` 会将这两个输出序列反相。
- 电源属性改为绑定要求的 `VDDIO-supply`、`AVDD28-supply`，移除不支持的
  `goodix,gt9xx` 兼容串；中断提供有效的下降沿类型。

依据：[Goodix 驱动](https://github.com/torvalds/linux/blob/master/drivers/input/touchscreen/goodix.c)
和 [绑定](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/input/touchscreen/goodix.yaml)。
六月笔记中的 INT 地址选择表原先写反，已一并更正，并更新当前单一 DTS 源构建流程。

### 验证与新镜像

内核和板级 DTB 编译通过，DTB 属性检查确认 SD 无 GPIO1_IO09 电源控制、
Goodix 地址/极性/电源名称正确、SNVS 偏移正确。QEMU 对比直接启动 Linux，
相同最小 BusyBox 根文件系统挂在 SD0：

- 旧内核：SD 控制器 12.245 秒完成探测，根文件系统 12.354 秒挂载。
- 新内核：SD 控制器 1.654 秒完成探测，根文件系统 1.899 秒挂载，进入串口 shell。
- 新内核的模拟触摸设备在 `1-0014` 识别 ID 911，注册 Goodix 输入设备。

QEMU 的 `mcimx6ul-evk` 没有 i.MX6ULL SNVS MMIO，且内置 GT911 固定在 0x5d，
不模拟 RESET/INT 地址选择。测试单独复制 DTB，将 SNVS 映射至模拟 DRAM 末尾
16 KiB，并以 `mem=511M` 将其排除在 Linux 内存之外；另加一个地址为 0x14
的 GT911 模型。这个环境验证 regulator 依赖、MMC 启动与 Goodix probe，
不能验证真实 SNVS 寄存器、RESET 电平、触摸 IRQ 或实际触摸坐标。
这些模拟适配没有进入 SD 镜像。

新镜像：`out/sdcard/aes-sd-v2026.10-minimal-linux-fix.img`（144 MiB）。
沿用已经真板启动成功的 handoff-trace U-Boot 和最小 BusyBox rootfs，更新
Linux/DTB；从 `sdbootaes` 移除 `keep_bootcon`，消除正式串口接管后整段日志重复。
环境仍位于 4 MiB，分区布局保持原样；镜像不自动启动，在 U-Boot 执行
`run sdbootaes`。

完成环境 CRC、分区边界、ext4 检查，以及镜像内核/DTB 与新构建载荷一致性校验。
确认 boot 分区与环境区域之外的数据（含 U-Boot 与整个 rootfs）和已验证镜像
逐字节一致。校验值、组成和验证范围保存在镜像旁的 `.sha256` / `.manifest.json`。
复现打包和 QEMU 对比脚本保存在 `out/linux-power-touch-fix/`。

新镜像尚未在真板复测。烧录后仍需确认 SD 提前枚举、根分区挂载，以及
`Goodix-TS 1-0014: ID ...`、输入设备注册和实际触摸事件。
这次完成的是上述 Linux 配置与 DTB 修复，整板外设验收仍需逐项进行。

## 变更落点与验收记录

| 维护文件 | 本次内容 |
| --- | --- |
| [U-Boot 板级补丁](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/patches/uboot-mainline/charlies_board.patch) | SNVS、环境偏移、默认环境 NUL、DM MDIO、LCDIF 时钟清理顺序 |
| [Linux 板级 DTS](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi) | SNVS、Goodix 地址与 GPIO 极性、电源属性和启动状态 |
| [Linux 配置模板](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template) | 补开 CONFIG_REGULATOR，使已有子驱动选项生效 |
| [Goodix 历史排查笔记](2026-06-29-goodix-touch-i2c-addr-0x14.md) | 更正 INT 地址选择表，更新主线 GPIO 语义和现行构建流程 |

Linux 的长期维护源是超项目中的 DTS 与配置模板；构建脚本将它们复制、生成到
`third_party/linux_mainline`。只改内核树副本，下次构建会被覆盖。
在已应用 AES 板级补丁的 U-Boot 源码树上，可使用现有构建入口：

```bash
# 项目根目录，工具链已加入 PATH
scripts/build_helper/build-uboot.sh
scripts/build_helper/build-linux.sh --fast-build
```

这两个命令构建引导程序和内核，不等同于生成本次最小 BusyBox SD 镜像。
本次打包脚本、最小 rootfs 与 QEMU 检查脚本保存在 `out/`，属于本地排查产物；
完整发行镜像仍应按发行流程生成。`scripts/build_helper/build-uboot.sh` 本身
已按用户要求恢复，没有为上述板级修复增加脚本改动。

| 镜像或检查 | 已有证据 | 验证边界 |
| --- | --- | --- |
| minimal-handoff-trace.img | 用户真板日志到达 BusyBox shell，根分区约 13.83 秒挂载 | 证明 U-Boot 到 Linux、SD rootfs、init 和串口 shell；当时仍有延迟和 Goodix 错误 |
| minimal-linux-fix.img | 新 Linux/DTB 编译、镜像校验通过；QEMU 的 SD 探测 12.245 → 1.654 秒，挂载 12.354 → 1.899 秒 | QEMU 绕过 U-Boot，且使用前述模型适配；不能当作真板耗时或实际触摸验收 |
| Goodix 软件修正 | 驱动/绑定核对、DTB 属性检查、QEMU 在 0x14 注册输入设备 | 本次 GT9147 实物的复位电平、IRQ、坐标和多点触摸仍待真板复测 |

上述镜像均位于 `out/sdcard/`，旁边的 `.manifest.json` 与 `.sha256` 记录组成、
校验值及验证范围。日志清理后的镜像名称见下一节，不应将历史诊断镜像与最新
产物混用。

真板复测时，记录启动到 SD 枚举、根分区挂载的时间，并检查：

```sh
dmesg | grep -E 'mmc|Mounted root|Goodix|deferred'
cat /proc/bus/input/devices
cat /proc/interrupts
```

Goodix 应能读出芯片 ID 并注册输入设备；操作触摸屏后，还要确认对应中断计数
与事件数据变化。网络、显示、音频、USB 等其余外设需要各自验证，不能仅凭
进入 BusyBox shell 判断整板验收完成。

## 移除交接调试日志

`[AES-REMOVE]` / `[AES-HANDOFF]` 是此前独立诊断源码中的直接 UART 打印，
不受普通日志等级控制。正式 `third_party/uboot-mainline` 与板级补丁中没有
这些插桩。已从诊断副本的 `boot/bootm.c`、`arch/arm/lib/bootm.c`、
`drivers/core/device-remove.c` 移除全部打印、跟踪状态变量和 include，并删除
`include/aes_handoff_trace.h`。三个实现文件已与正式源码逐字节核对一致。

重新构建普通 U-Boot，并更新打包脚本为默认使用该产物。
最新无调试日志镜像为 `out/sdcard/aes-sd-v2026.10-minimal-clean.img`；
它包含此前的 Linux/DTB 修复和最小 BusyBox rootfs。在 U-Boot 执行
`run sdbootaes` 启动。二进制及整张镜像已检查不含上述调试标记，启动问题的
MDIO/LCDIF 修复仍保留。旧日志版镜像和补丁仅作为历史诊断产物保留。
