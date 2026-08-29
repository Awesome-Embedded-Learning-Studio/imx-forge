# run-qemu.sh - QEMU 板级模拟启动脚本详解

## 脚本概述

`run-qemu.sh` 在 QEMU `mcimx6ul-evk` 机器上启动 AES 板的完整软件栈：我们
的 mainline 内核 zImage + QEMU 变体 dtb + Buildroot rootfs ext4 镜像。
支持交互模式（默认）和 `--smoke` 非交互冒烟模式（CI 用），冒烟模式断言
串口出现登录提示符，exit 0/1 可直接被 CI 消费。

这是「无板体验」的核心入口：没有开发板的用户在完成内核/buildroot 构建后，
三条命令即可在自己的机器上把整套系统跑起来。

### 两种启动模式

- **交互模式**：`-nographic` 前台跑，串口即当前终端（Ctrl-A X 退出，
  Ctrl-A C 切 QEMU monitor），可以登录（root/root）、跑命令、`poweroff -f`
  干净关机（SNVS poweroff 模型支持，QEMU 会自动退出）
- **`--smoke` 冒烟**：`timeout` 包住 QEMU，串口重定向到日志文件，结束后
  `grep -E` 断言期望关键字（默认 `buildroot login:`，可用 `--expect`
  自定义/叠加），适合 CI 的 boot 测试判定（与 QEMU 官方 functional test、
  Buildroot runtime test 的串口关键字判定范式一致）

### 在开发工作流中的位置

三件套的最后一步：

```bash
scripts/qemu_helper/make-rootfs-img.sh      # 1. rootfs → ext4
scripts/qemu_helper/make-qemu-dtb.sh        # 2. 编 QEMU 变体 dtb
scripts/qemu_helper/run-qemu.sh --smoke     # 3a. CI 冒烟
scripts/qemu_helper/run-qemu.sh             # 3b. 交互体验
```

## 用法示例

```bash
# 交互（登录 root / root）
scripts/qemu_helper/run-qemu.sh

# CI 冒烟：等 login 提示符，240s 超时
scripts/qemu_helper/run-qemu.sh --smoke --timeout=240 --log=out/qemu/uart.log

# 自定义断言链（例如同时要求内核版本与登录提示符）
scripts/qemu_helper/run-qemu.sh --smoke \
    --expect='Linux version 7\.1\.0' --expect='buildroot login:'

# 附加内核参数（如 init=/bin/sh 跳过 init 做内核调试）
scripts/qemu_helper/run-qemu.sh --append='init=/bin/sh'

# 跳过自动重建（CI 缓存场景等，产物必须已存在）
scripts/qemu_helper/run-qemu.sh --no-build
```

## 自动重建（防启动到旧产物）

陈旧产物是这条链路最经典的坑：改了 `imx6ull-aes.dtsi` 或重跑了 buildroot
构建，`out/qemu/` 里的 dtb / rootfs 镜像还是旧的，QEMU 起的是没刷新的系统。
默认情况下 `run-qemu.sh` 启动前按依赖顺序自检并重建（加 `--no-build` 跳过）：

| 产物 | 触发条件 | 动作 |
|---|---|---|
| `out/qemu/imx6ull-aes-qemu.dtb` | 变体 dts 或内核树 `nxp/imx/` 下任一 dts/dtsi 比现有 dtb 新；或 dtb 不存在 | 调 `make-qemu-dtb.sh` |
| `out/qemu/rootfs.ext4` | `out/release-latest/rootfs/` 树内**任何文件**比镜像新（`find -newer`，捕捉 buildroot 原地覆写）；或镜像不存在 | 调 `make-rootfs-img.sh` |

判定规则：

- 只有**默认路径**参与自动重建；显式 `--dtb=`/`--rootfs-img=` 指定的产物
  原样使用、绝不重建（自己管理）
- `--no-build` 下产物缺失直接报错退出，不会偷偷构建——CI 里防止意外覆盖
  缓存产物
- 内核 zImage 不在自动重建范围（重编内核是显式的重活，脚本不越界替你跑
  `build-mainline-linux.sh`）

## 关键实现细节

- **直启路径**：`-kernel zImage -dtb`。stock QEMU 没有 i.MX boot ROM/HAB
  模型，`-bios u-boot-dtb.imx`（带 IVT 头）不可用；U-Boot 完整链需要
  QEMU ≥ 11.1（2026-08 Bin Meng 系列），后续 Phase 用
  `-device loader,file=u-boot.bin,addr=0x87800000` 解锁
- **SD 卡挂 USDHC2**：`-drive if=sd,index=1` → guest `/dev/mmcblk1`，
  rootfs 镜像无分区表，故 `root=/dev/mmcblk1`（整卡）
- **`-nic user`**：机器模型用 `qemu_configure_nic_device()` 自动把 netdev
  接到 fec 控制器（无需显式 `-device`）；guest 侧 DHCP 拿 10.0.2.15
- **`-no-reboot`**：guest `poweroff`/`reboot` 后 QEMU 退出而不是复位重跑
  （冒烟测试不会死循环）
- **超时即成功路径**：冒烟正常结束时 QEMU 停在 login 提示符等输入，被
  timeout 杀掉（rc=124）是预期终点；rc 0（guest 主动 poweroff）也接受，
  其余退出码都算失败
- **earlycon 技巧**：内核死于 uart 驱动 probe 之前时完全无输出，加
  `--append='earlycon'` 可看到 ec_imx6q earlycon 的最早期日志（调试
  device tree 问题的第一手段）

## 已知限制（P0 时点）

- **FEC 网卡 deferred**：两个 ethernet 节点 probe deferred（疑似
  `phy-supply` regulator 或 ENET_REF 时钟链在 QEMU 里不 ready），
  `ifplugd` 起来了但 eth0 无 IP——待 Phase 2 排查（设备树里去掉
  phy-supply 引用或改 qemu 变体 phy 节点）
- **I2C 传感器 timeout**：ap3216c/wm8960/gt9147 探测 -110——总线上没有
  器件模型，预期行为；Phase 3 补 QEMU 器件模型后消除
- **无显示**：lcdif 在变体里 disabled（8.2.2 是地址空洞）；QEMU ≥ 11.1
  后从 disable 列表移除即可出画面
- **FlexCAN 失败**：CAN 控制器 QEMU 未建模，`-110` 软失败
