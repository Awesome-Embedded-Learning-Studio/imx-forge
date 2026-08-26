---
title: QEMU 板级模拟调研：选型、外设覆盖与分期落地
---

# 2026-08-25 QEMU 板级模拟调研：让无板用户和 CI 跑起来

目标：给 i.MX6ULL AES 板（正点原子 ALPHA 衍生）找一条**模拟器路线**，跑我们自己的
内核 + 设备树 + rootfs，进 CI 冒烟，并让没有板子的朋友直接上手体验——争取尽可能
全面地模拟外设。这篇笔记沉淀 2026-08-25 的四路调研结论（仓库现状 / QEMU 上游 /
Renode / 社区先例），并给出分期建议。**只调研，未动构建体系**。

## TL;DR

1. **主路线定 QEMU `-M mcimx6ul-evk`**：上游没有独立 6ULL 机器，但 6UL/6ULL 地址
   映射与外设集基本一致，社区通行做法就是「6UL 机器 + 6ULL dtb」。官方 2026-08
   刚补齐了 U-Boot 完整启动链文档和 Buildroot 靶机（Bin Meng 系列），我们的
   mainline v7.1 + Buildroot 栈与官方验证组合完全同构。
2. **开源 Renode 没有任何 i.MX6 系平台**（全量枚举仓库树 + git 历史验证），从零
   建 `.repl` 工作量大；但它的 CAN 双板互联 + Robot 测试框架是独有能力，可作
   **后期补充**而非主轴。
3. **外设覆盖天然分三档**：UART/I2C/SPI/USDHC/GPIO/FEC/USB/eLCDIF 有真模型；
   CAN 模型已进上游但没接线到 6UL SoC（约 20 行可接）；触摸/音频/PWM/ADC 两边
   都没有，需要自建（教学向可参考百问网「假 MMIO」先例）。
4. **CI 收益立即可得**：仓库现在零启动验证（CI 只查产物存在性），QEMU 直启
   （`-kernel zImage -dtb`）不需要任何上游新特性，装个 qemu-system-arm 就能做
   「boot 到 login」冒烟。
5. **驱动章节的隐藏红利**：我们的教学外设（ap3216c/icm20608/LED/beep/key）用
   自写 imxaes 驱动，如果给 QEMU 补这几个小器件模型，**驱动章节的 .ko 就能在
   CI 里真跑**（insmod → 读传感器值 → 断言），这是目前完全做不到的事。

## 一、我们手里的牌（仓库现状）

| 事实 | 细节 | 对模拟方案的意义 |
|---|---|---|
| 内核 mainline v7.1 | `imx_aes_mainline_defconfig`，产物 `out/mainline/linux/arch/arm/boot/zImage` + `dts/nxp/imx/imx6ull-aes.dtb` | 与 QEMU 官方验证组合（mainline kernel + imx_v6_v7 系）同构 |
| `CONFIG_CMDLINE_FROM_BOOTLOADER=y`（非 FORCE） | 已在 `out/mainline/linux/.config` 验证 | QEMU `-append` 的 `root=` 能生效，不用改内核 |
| `CONFIG_FEC=y`、`CONFIG_DRM_MXSFB=y` | .config 已解析；MXSFB 正是 eLCDIF 的 KMS 驱动 | 网络、LCD 显示内核侧就绪 |
| rootfs 三种形态 | 目录树 `out/release-latest/rootfs/`、Buildroot tar、SD/eMMC 整盘镜像 | 模拟可直接消费，或用 `mke2fs -t ext4 -d` 现做小镜像 |
| 板上 512MB DRAM @0x80000000 | dtsi `0x80000000 0x20000000` | 与 QEMU `-m 512M` 一致 |
| FEC PHY 是 micrel ksz8081，挂 fec2 mdio | dtsi 实况 | 恰好匹配 QEMU EVK 机型拓扑（`fec2-phy-num=1`），网络阻力小 |
| CI 零启动验证 | ci-build/ci-full 只做产物存在性检查 | QEMU 冒烟是纯增量，不冲突 |
| docker 容器无 qemu-system-arm | `docker/Dockerfile` | 需补包（apt 8.2.2）或自编 11.1+ |
| 设备树三处同步纪律 | patch + submodule + `driver/device_tree/alpha-board/linux/` 副本 | 任何「QEMU 变体 dts」都要遵守 |

板上启用外设（dtsi `status="okay"`，即模拟覆盖面清单）：uart1(console)、i2c1
(ap3216c + wm8960)、i2c2 (gt9147@0x5d、ov5640)、ecspi3 (icm20608)、qspi
(n25q256a)、lcdif + panel-dpi 1024x600 + pwm1 背光、fec1/fec2 (ksz8081)、can1、
usbotg1/2、usdhc1(SD)/usdhc2(eMMC 8-bit)、sai2+asrc、GPIO LED/beep/key、
snvs pwrkey/RTC。

## 二、QEMU 路线（主选）

### 2.1 机器与版本现实

- 上游**没有** `mcimx6ull-evk`，只有 `mcimx6ul-evk`（hw/arm/fsl-imx6ul.c，
  2018 年 J.C. Dubois 贡献）。6ULL 与 6UL 外设地址/中断号一致（6ULL 只是少了
  UART8/CAAM 等），compatible 带 `fsl,imx6ul` fallback——**直接 `-dtb
  imx6ull-aes.dtb` 可行**，CSDN 已有先例。
- 最新 release **11.1.0**（2026-08-11）。**eLCDIF 显示模型
  `hw/display/imx6ul_lcdif.c` 2026-04 才合入**（v11.0.0 tag 无此文件，404 验证；
  另有邮件列表口径称 11.0——反正都远新于 apt 的 8.2.2，要显示就得自编）。
  Ubuntu 24.04 apt 只有 **8.2.2**。
- **U-Boot 完整引导链**：Bin Meng 10 补丁系列（2026-08-12，SCU 兼容窗口 + MMDC
  几何 + 3 个 uSDHC quirk）已 patchew "applied" 但**尚未进 master**。在它落地
  前：直启路径（`-kernel`/`-dtb`）今天就能用；U-Boot 路线用
  `-device loader,file=u-boot.bin,addr=0x87800000` 载**无头** u-boot.bin
  （`-bios u-boot-dtb.imx` 不支持——QEMU 无 boot ROM/HAB 模型，IVT 头没人解析）。

### 2.2 官方验证过的启动命令（直启，今天可用）

来自 QEMU 官方文档 patch（Bin Meng 系列 09）：

```bash
qemu-system-arm -M mcimx6ul-evk -m 512M \
  -kernel zImage -dtb imx6ull-14x14-evk.dtb \
  -append "console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw" \
  -drive file=sdcard.img,if=sd,index=1,format=raw -nographic
```

要点：

- SD 卡挂 **USDHC2（`if=sd,index=1`）**，Linux 里是 `/dev/mmcblk1`；
- **SD 镜像必须 2 的幂容量**（QEMU SD 模型 CSD 编码限制，`qemu-img resize -f
  raw sdcard.img 128M`）——我们的整盘镜像 216M/369M 直接挂大概率出问题；
- `-dtb` 是整体替换：QEMU 只改写 `/memory`（以 `-m` 为准）和 `/chosen`，其余
  节点透传。dtb 里未建模外设（PWM/ADC/SAI/GT9147…）驱动 probe 会读到 0 而失败，
  打 "unimplemented" guest error 日志，**通常非致命**；真致命的是缺 clock/中断
  提供者（我们 dtb 的 provider——CCM/GPCv2/QSPI 时钟——都有模型，风险低）。
- 串口：uart1=serial_hd(0)，`-nographic`（Ctrl-A C 切 monitor）。2019 年经典
  翻车帖的教训：`-monitor stdio` 会吞串口，要么 `-nographic` 要么 `-serial
  mon:stdio`。

### 2.3 外设覆盖矩阵（QEMU，对照我们的 dtsi）

| 我们的外设 | QEMU 状态 | 备注 |
|---|---|---|
| uart1 console | ✅ 完整 | imx_serial |
| fec1/fec2 + ksz8081 | ✅ 完整 netdev | `-netdev user` 可上网/端口转发；拓扑匹配 |
| usdhc1/2 (SD/eMMC) | ✅ SDHCI | U-Boot 兼容性刚修复（master）；内核直启无碍 |
| i2c1/2、ecspi3、qspi* | ✅ 控制器完整 | 但机器上**没挂任何子设备**（EEPROM/NOR/传感器全无） |
| GPIO LED/beep/key | ✅ GPIO×5 完整 | 但无「按键注入/LED 可视化」板级胶水（要自己接 qemu_input） |
| eLCDIF + panel | ✅ 11.1+ | RGB565/XRGB8888 出图，frame-done IRQ |
| SNVS RTC | ✅ 基本可用 | LPSRTC 走 host 时钟 |
| WDOG/GPT/EPIT/USB(host) | ✅ | chipidea 仅 host 角色 |
| **can1 (FlexCAN)** | ⚠️ 模型已进 11.1（CTU Prague 出品），**未接线到 6UL SoC** | 参照 fsl-imx6.c 接线 ≈20 行 + Kconfig |
| **pwm1（背光）** | ❌ unimplemented | 全树无通用 PWM 框架可借 |
| **gt9147 触摸** | ❌ 无任何触摸模型 | 全树最接近的是 HID 键鼠；参考百问网假 MMIO 方案 |
| **sai2 + wm8960 音频** | ❌ 双断点 | SAI 和 **SDMA**（ASoC dmaengine 链路）都是桩；wm8750 是最近亲 |
| **adc、ap3216c、icm20608** | ❌ 桩/无器件 | ap3216c/icm20608 是我们的 imxaes 驱动，模型可以自己写（tmp105/m25p80 模板） |
| IOMUX/pinmux | ❌ unimplemented | 写入被忽略，通常无害（驱动照常跑，复用逻辑不真实） |

### 2.4 定制成本标尺（以本轮上游合入的同类为参考）

一个典型 SysBus MMIO 器件模型 = TypeInfo + MemoryRegionOps + registerfields +
接线 + Kconfig。参照 imx6ul_lcdif.c（454 行，单人一个 PR）：

- PWM/ADC 教学 stub → 可用：约 300–600 行/个
- ap3216c（I2C sensor，tmp105 模板）≈ 300 行；icm20608（SPI，m25p80 模板）≈ 400 行
- GT9147（I2C slave + qemu_input）：约 500–800 行
- WM8960（wm8750 基础 +300 行）+ SAI + 绕开 SDMA 的轮询式音频：**唯一大件 ≥1000 行**，
  且要和 fsl-sai 驱动的 dmaengine 期望周旋——建议放最后
- FlexCAN 接线到 6UL：≈20 行（模型现成）

维护方式两条路：**a)** 自维护 QEMU fork（百问网模式，交付快、上游漂移要自己背）；
**b)** 尽量上游化（lcdif/flexcan 先例都说明 QEMU 社区收 i.MX 模型），我们用
master 构建 + 自己的 patch 队列。教学外设（ap3216c 这类私货）天然走 fork 侧。

## 三、Renode 路线（补充/后期）

- **开源版零 i.MX6 系平台**：`platforms/` 全量枚举只有 i.MX8MP/RT/Kinetis，
  git 历史深挖从未有过 imx6ull .repl；issue 区搜 6ull 结果为 0。网上「Renode
  有 imx6ull.repl」的说法是把 antmicro Designer **商业服务目录页**误当开源支持。
- 跑 Linux 最小集（UART/GPIO/I2C/ECSPI/uSDHC/ENET/GPT/WDT/GICv2）模型**现成**；
  `cortex-a7` 可用；EPIT/SNVS-RTC/ADC/PWM/eLCDIF/SAI/SDMA/WM8960/GT9147 全缺。
  可用 `dts2repl` 从我们的 dts 半自动生成骨架，再手工映射，估计 2–4 周建模。
- **独有能力**（QEMU 没有的）：
  - `emulation CreateCANHub` 双板/多板 CAN 互联（官方 CI 天天在跑的用法）+
    `CAN.SocketCANBridge` 接宿主 vcan0——CAN 章节双板实验只有这条能模拟；
  - Robot Framework 关键字级测试（`Wait For Line On Uart` 等一整套 +
    LEDTester/PWMTester/FrameBufferTester + HTML 报告）；
  - GDB **反向执行**、时间旅行快照；外设 C# 热加载（200–600 行/个，无构建地狱）。
- 许可：框架/外设 MIT，CPU 翻译核 tlib LGPL-2.1（libqemu fork）。QEMU 整体
  GPLv2。教学都无碍。
- 结论：**不做主轴**（整机从零建模成本高、社区无人区遇坑没得搜），但 CAN 双板
  /自动化测试需求出现时再引入，与 QEMU 不互斥（也没有混跑机制，各自独立）。

## 四、社区先例与生态位

- **百问网（韦东山）是全球做「魔改 QEMU 模拟 6ULL」最深的**：qemu fork 加假
  LCD（贴板子 BMP）、GPIO 按键、MMIO 假寄存器触摸（不走 I2C）、逻辑分析仪、
  AT24C02。但内核停在 4.9.88、QEMU 4.x、`-kernel` 直启不走 U-Boot、无音频/CAN/
  PWM/ADC。**证明教学向魔改路线可行，也说明它停在 2021 年水平。**
- 正点原子、野火官方都**没有**仿真方案（只给编译虚拟机）——中文教学圈这个
  生态位是空的；若我们做成 mainline 内核 + 官方 QEMU 版本的方案即首发。
- CI 判定成熟范式：Buildroot runtime 测试 pexpect 等登录提示符；QEMU functional
  test 串口关键字链（`U-Boot` → `Starting kernel` → `login:`）+ 240s 超时 +
  镜像放 release 固定 sha256。都可以直接抄。

## 五、分期落地建议

### Phase 0 —— 直启 spike（✅ 2026-08-25 完成）

`scripts/qemu_helper/` 三件套已落地并全链路验证：

```bash
scripts/qemu_helper/make-rootfs-img.sh    # rootfs 目录树 → 256M ext4（2 的幂）
scripts/qemu_helper/make-qemu-dtb.sh      # 编 QEMU 变体 dtb（内核树 include）
scripts/qemu_helper/run-qemu.sh --smoke   # CI 冒烟：断言 buildroot login:
```

**验收达成**：apt QEMU 8.2.2 直启到 `buildroot login:`（exit 0）；交互登录
（root/root）成功，`uname -a` = `Linux buildroot 7.1.0 armv7l`；udevd/
network/ifplugd/crond/dropbear/telnetd 全部启动；`poweroff -f` 干净关机
（SNVS poweroff 模型）。SD 卡（mmcblk1, 256 MiB QEMU）+ EXT4 root 挂载正常。

**打地鼠实录（改 dtb 前必读）**：直接用真机 dtb 启动会连环 panic——QEMU
8.2.x 对以下节点是**地址空洞**（无模型也无 stub，`readl` 触发 external
abort 杀 PID 1），且死在 uart 驱动 probe 之前 → **串口完全无输出**，必须
加 `earlycon` 才能看到死点。依次炸的顺序：mmdc（0.33s）→ rngb → lcdif →
qspi → pxp → dcp → ocotp → usbmisc。解法：`imx6ull-aes-qemu.dts` 变体
disable 这 12 个节点（详见 `document/scripts/qemu_helper/make-qemu-dtb.sh.md`
的表格；master/11.1+ 补了部分 stub，lcdif 11.1+ 有真模型可放开）。

**剩余软失败（预期内，不炸内核）**：I2C 传感器（ap3216c/wm8960/gt9147）
probe -110 超时——QEMU 总线上没有器件模型（Phase 3 补）；FlexCAN -110
（控制器未建模，Phase 3 接线）；tempmon defer（依赖 ocotp nvmem）；
sound-wm8960 defer（fsl-asoc-card 注册失败，SAI 无模型）。

**遗留问题（Phase 2 排查）**：FEC 两个 ethernet 节点 probe deferred
（`/sys/kernel/debug/devices_deferred` 里原因 unknown）。驱动已内建
（vmlinux 有 fec_probe 符号），疑似 `phy-supply = <&reg_peri_3v3>`（fixed
regulator 挂 gpio5_2 + IOMUXC pinctrl，QEMU 里 IOMUXC 是 stub）或
ENET_REF 时钟链不 ready。下一步：变体 dts 里试删 phy-supply 引用。

### Phase 1 —— CI boot 冒烟（首个 PR）

- ci-build.yml 的 linux-mainline job 后追加 boot smoke job：串口关键字链断言
  （`Starting kernel` → login 提示符）+ 240s 超时 + uart.log artifact；
- docker 镜像补 `qemu-system-arm`（8.2.2 对直启冒烟够用）；
- rootfs 用精简 CI 变体（完整 Qt6 rootfs 没必要进冒烟）。

### Phase 2 —— 显示 + U-Boot 链（QEMU ≥11.1 自编进 docker）

- docker 里源码编 QEMU master/11.1+（或等 apt 跟上），解锁 eLCDIF 显示
  （我们的 DRM_MXSFB + panel-dpi 直接受益，Qt light-meter 有屏可秀）；
- U-Boot 链：`-device loader u-boot.bin @0x87800000` + SD 镜像按我们
  emmcbootaes 的分区布局（p1 ext4 放 zImage+dtb，rootfs p2）——完整复现真机
  启动叙事，U-Boot 章节可加「模拟器练习」。

### Phase 3 —— 外设深潜（按教学收益排序，每章一个模型）

优先级建议（收益/成本比）：

1. **ap3216c + icm20608 器件模型**（≈300+400 行）：解锁驱动章节 CI 真跑 .ko——
   insmod → 读传感器 → 断言，全仓库最高隐藏收益；
2. **FlexCAN 接线**（≈20 行 + 自编 QEMU）：CAN 章节闭环（若要双板互联则届时
   评估 Renode 并行轨）；
3. **GT9147 触摸**（500–800 行，qemu_input 注入）+ 背光 PWM（300–600 行）；
4. **WM8960+SAI 音频**：大件，最后做或不做（音频章节保真机）。

### 文档配套

`document/tutorial/emu/` 新卷（sidebar 注册进 LEARNING_ORDER），叙事衔接：
light-meter 的「桌面 Mock → 真机」中间天然多了一层「QEMU 半真机」；
`practical/03_boot_and_debug.md` 的 QEMU 小节改指向新章节。

## 六、风险与开放问题

| 风险 | 缓解 |
|---|---|
| apt 8.2.2 与上游差距（无 LCDIF/U-Boot 链修复） | Phase 0/1 只依赖直启（老路径，2019 年起就 work）；显示和 U-Boot 链押后到自编 11.1+ |
| Bin Meng U-Boot 系列未进 master 的时间不确定 | U-Boot 链列 Phase 2 可选项，不阻塞主线 |
| 自编 QEMU 的 CI 体积/时长 | docker 分层缓存 + 只编 arm-softmmu（`--target-list=arm-softmmu`），或用官方静态产物 |
| unimplemented 外设导致意外致命 | Phase 0 spike 实测为准；兜底是 QEMU 变体 dts 裁掉问题节点 |
| QEMU fork 维护漂移 | 教学 private 外设走 fork patch 队列（复用我们 per-component 单 patch 纪律），公共可上游化的尽量上游 |
| 百问网方案对比压力 | 我们差异点：mainline v7.1 + 官方 QEMU + U-Boot 真链路 + CI 集成 |

**开放决策**（待定）：主目标权重（CI 冒烟优先 vs 无板体验完整教程优先）；QEMU
fork 策略（纯上游 vs 自维护 patch 队列）；音频要不要投入；Renode 何时引入。

## 参考来源

- QEMU 机器文档与 Bin Meng 系列（U-Boot on MCIMX6UL-EVK，patchew 20260812013619，
  2026-08-12，含直启/loader 命令与 sdcard 128M resize 说明）
- QEMU 源码：hw/arm/fsl-imx6ul.c、mcimx6ul-evk.c、hw/display/imx6ul_lcdif.c、
  hw/net/can/flexcan.c、hw/net/imx_fec.c
- Buildroot configs/imx6ulevk_defconfig（官方 QEMU 靶机）与
  support/testing/infra/emulator.py（pexpect 判定范式）
- Renode platforms/ 全量枚举 + renode-infrastructure Peripherals（2026-08 master）
- 百问网 100askTeam/qemu、wiki.100ask.org/Qemu、ldd.100ask.net 触摸章节
- 2019 qemu-arm 列表翻车帖（-dtb 必传、`-serial mon:stdio`）与 NXP Community
  官方答复（不支持 6ULL、建议真机/Renode）
- 本仓库：out/mainline/linux/.config（CMDLINE_FROM_BOOTLOADER/FEC/DRM_MXSFB
  验证）、imx6ull-aes.dtsi、ci-build.yml、docker/Dockerfile
