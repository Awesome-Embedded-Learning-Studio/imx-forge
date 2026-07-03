---
title: Goodix 触摸屏 I2C 地址错（0x5d vs 0x14）
---

# 2026-06-29 Goodix GT9147 触摸屏 -6 ENXIO：地址写成 0x5d，实测在 0x14

netboot 启动 `imx6ull-aes.dtb` 时，Goodix 触摸屏驱动 probe 失败，串口日志一片
`Error ... -6`。这篇记一个**反复会踩**的坑：Goodix 的 I2C 从地址不是固定的，而
设备树（和很多教程）默认写 `0x5d`，但本板实测在 `0x14`。只要换板子、换 INT/RESET
上电时序，地址就可能落到另一个值——所以把**排查方法**记下来比记答案更值。

## Context

- 触摸芯片：正点原子 i.MX6ULL AES 板上的 Goodix **GT9147**，挂在 **i2c-1**。
- 驱动：mainline `drivers/input/touchscreen/goodix.c`（分析型章节路线，拆现成驱动
  不重写，见 [触摸章节](../tutorial/kernel/mainline/08_touch_gt9xx.md)）。
- 设备树：netboot base 镜像 `imx6ull-aes.dtb` 由 `linux/imx6ull-aes.dts`
  `#include "imx6ull-aes.dtsi"` 编出，goodix 节点就在这个**共享 dtsi** 里。

## Symptom

内核起来后，触摸驱动连试两次读寄存器都失败，然后放弃 probe：

```text
[   12.006241] Goodix-TS 1-005d: Error reading 1 bytes from 0x8140: -6
[   12.035073] Goodix-TS 1-005d: Error reading 1 bytes from 0x8140: -6
[   12.064510] Goodix-TS 1-005d: I2C communication failure: -6
```

之后 `/dev/input/eventX` 不出现，触摸不可用。**注意：probe 失败不是 fatal**，
后面 DHCP、继续启动都正常——别把它和「起不来」混淆。

## Key Insight —— `-6` 是「设备没应答」，先别怪驱动

逐字段拆这一行 `Goodix-TS 1-005d: Error reading 1 bytes from 0x8140: -6`：

- `1-005d` = Linux i2c **bus 1**、从**地址 0x5d**（这是设备树 `reg` 给的）。
- `0x8140` = Goodix 的 **Product ID 寄存器**（`GT9147_PRODUCT_ID`）。驱动 probe 时
  第一步就是读它来辨认芯片型号。
- **`-6 = -ENXIO`** = I2C 传输层最经典的「**No ACK**」：master 在 0x5d 发起读，
  总线上**没有任何设备在那个地址应答**。

所以问题不在驱动、不在中断、不在供电时序——而是**驱动去找设备的那个地址上没有设备**。
最该先做的一步不是读代码，是**扫总线**。

## Investigation

### Step 1 —— `i2cdetect` 直接看芯片在哪个地址

板子进 shell 后（这个 probe 是内核侧、boot 早期就发生，跟 rootfs/init 无关，
哪怕 NFS root 还没修好也能验）：

```bash
i2cdetect -y 1
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:          -- -- -- -- -- -- -- -- -- -- -- -- --
# 10: -- -- -- -- 14 -- -- -- -- -- -- -- -- -- -- --
# 20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# ...（其余全 --）
```

整条 i2c-1 上**只有 0x14 那一格有应答**。同总线的 `ov5640@3c` 是
`status="disabled"`，所以 0x14 必然就是 GT9147，没有歧义。**芯片在 0x14，
驱动却去 0x5d 找** → -6。

### Step 2 —— 反编译正在 boot 的 dtb，确认 `reg`

```bash
dtc -I dtb -O dts /home/charliechen/tftp/imx6ull-aes.dtb 2>/dev/null | grep -A3 'gt9147@'
# 				gt9147@5d {
# 					compatible = "goodix,gt9147\0goodix,gt9xx";
# 					reg = <0x5d>;
```

果然 `reg = <0x5d>`。源在
[imx6ull-aes.dtsi](../../driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi)
的 goodix 节点。

### Step 3 —— 为什么是 0x14 不是 0x5d

Goodix GT9xx 系列的 **7-bit I2C 从地址不是固定的**，由 **RESET 上升沿那一刻 INT
引脚的电平**决定：

| INT @ RESET 上升沿 | 7-bit 地址 | 8-bit 写/读 |
|---|---|---|
| 高 | `0x5d` | `0xBA / 0xBB` |
| **低** | **`0x14`** | `0x28 / 0x29` |

本板的 INT 网络在复位瞬间是低电平 → 芯片落在 **0x14**。很多教程/NXP EVK 的 dts
默认写 0x5d（INT 上拉的情况），照抄到这块板就对不上。**换板子或改 INT/RESET 上拉，
地址就可能变**——这正是要写这篇笔记的原因。

## Root Cause

设备树 goodix 节点 `reg = <0x5d>` 与芯片实际地址 `0x14` 不符 → 驱动在 0x5d 读
Product ID 寄存器（0x8140）得不到 ACK → `-ENXIO` → probe 失败。

## Fix

把 `reg` 和节点名 `@` 后的地址从 `0x5d` 改成 `0x14`。**netboot base 镜像的源在三处，
要同步改**（光改一处会被构建流程覆盖回去）：

1. **patch**（构建真正 `git apply` 的，最权威）：
   `patches/linux_mainline/linux_mainline-feat-imx6ull_patches-20260616.patch`
2. **镜像副本**（人读的工作源）：
   `driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi`
3. **树里已 apply 的副本**（重编前必改这个，否则编出的还是旧的）：
   `third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi`

三处都是：

```diff
-		gt9147: gt9147@5d {
+		gt9147: gt9147@14 {
 			compatible = "goodix,gt9147", "goodix,gt9xx";
-			reg = <0x5d>;
+			reg = <0x14>;
```

> 节点名 `@5d`→`@14` 不是内核必需（内核用 `reg`），但 dtc 会因 unit-address 与
> `reg` 不一致而 warning，顺手改干净。label `gt9147:` 不变，`&gt9147` 引用不受影响。

### 快速重编 dtb（不用整编内核、不用交叉工具链）

```bash
cd third_party/linux_mainline
make ARCH=arm imx_aes_mainline_defconfig        # 一次性生成 .config
make ARCH=arm nxp/imx/imx6ull-aes.dtb           # ⚠ 必须带 nxp/imx/ 子路径
```

> **坑**：mainline 7.1 把 imx 的 dts 挪到了 `arch/arm/boot/dts/nxp/imx/` 子目录，
> 裸 `make imx6ull-aes.dtb` 会报
> `No rule to make target 'arch/arm/boot/dts/imx6ull-aes.dtb'`。目标名得带子路径。
> 编 dtb 只用到 host 的 dtc，不需要 `CROSS_COMPILE`，几十秒完成。

### 部署 + 验证

```bash
# 备份旧 dtb（沿用 -before-*-fix 命名习惯）
cp -n /home/charliechen/tftp/imx6ull-aes.dtb \
      /home/charliechen/tftp/imx6ull-aes-before-goodix-fix.dtb
# 拷新的上去
cp arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb /home/charliechen/tftp/imx6ull-aes.dtb
# 验证 reg 已变
dtc -I dtb -O dts /home/charliechen/tftp/imx6ull-aes.dtb 2>/dev/null | grep -A2 'gt9147@'
```

然后**重启板子**（netboot 开机才重新 tftp 拉 dtb，各章 dtb 互斥，见
[DTB Deploy & Boot](../../document/notes/) 相关约定）。

## Operational Rule（真正的 takeaway）

1. **Goodix 报 `-6`，第一步永远是 `i2cdetect -y <bus>`**，看芯片实际在哪个地址。
   别急着翻驱动、查中断、调时序——地址不对一切白搭。
2. **Goodix 地址由 INT@RESET 决定**，0x5d / 0x14（乃至 0x5e / 0x15）都合法。换板、
   换上电时序后地址可能变，**以 `i2cdetect` 实测为准**，别迷信 dts/教程里的值。
3. 改 netboot base 镜像的节点，**patch + 镜像 + 树里副本三处同步**，否则构建回退。
4. 改完只编单个 dtb 走 `make ARCH=arm nxp/imx/imx6ull-aes.dtb`，拷 tftp，重启板子。

## Triage One-Liner

> `Goodix-TS <bus>-<addr>: Error reading ... -6` → `-6 = ENXIO = 没 ACK`。
> 先 `i2cdetect -y <bus>` 看芯片真实地址，再 `dtc` 反编译 dtb 对 `reg`。两边对不上
> 就是地址写错——别查驱动、别查中断。

## Command Cheat-Sheet

```bash
# 1) 扫总线，看 Goodix 实际在哪个地址（排查首选）
i2cdetect -y 1

# 2) 反编译正在 boot 的 dtb，看 goodix 节点 reg
dtc -I dtb -O dts /home/charliechen/tftp/imx6ull-aes.dtb 2>/dev/null | grep -A3 'gt9147@'

# 3) 改完三处源后，快速重编单个 dtb
cd third_party/linux_mainline
make ARCH=arm imx_aes_mainline_defconfig
make ARCH=arm nxp/imx/imx6ull-aes.dtb

# 4) 备份 + 部署 + 验证
cp -n /home/charliechen/tftp/imx6ull-aes.dtb /home/charliechen/tftp/imx6ull-aes-before-goodix-fix.dtb
cp arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb /home/charliechen/tftp/imx6ull-aes.dtb
dtc -I dtb -O dts /home/charliechen/tftp/imx6ull-aes.dtb 2>/dev/null | grep -A2 'gt9147@'

# 5) 重启板子后，确认 probe 成功
dmesg | grep -i goodix          # 期望 Goodix-TS 1-0014，无 -6
ls /dev/input/event*
cat /proc/bus/input/devices
```

## Verified (2026-06-29)

`reg` 改为 `0x14`、重编部署、重启板子后，触摸驱动正常 probe，`/dev/input/eventX`
出现，`Goodix-TS 1-005d ... -6` 消失。修复端到端确认。

> 附注：本次部署的 dtb 来自「只 apply 了触摸 patch」的内核树，比之前的 tftp dtb
> 少了 `icm20608@0`（SPI 加速度计）和 `sim@021b4000` 两个节点。纯测触摸无影响；
> 需要那些节点的话，把对应章节的 patch 也 apply 进树再重编。回退用
> `imx6ull-aes-before-goodix-fix.dtb`。

## See Also

- [2026-06-08 WSL2 NFS Rootfs 排查记录](2026-06-08-wsl2-nfsroot-ganesha-troubleshoot.md) —— 另一个「内核侧症状、根因在 host/配置」的排查范例。
- [设备树基础](../tutorial/uboot/05_device_tree_basics.md) —— dts/dtsi/dtb 的关系与编译。
- [触摸章节（mainline goodix 分析）](../tutorial/kernel/mainline/08_touch_gt9xx.md) —— GT9147 驱动分析型章节。
