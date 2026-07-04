---
title: 修 defconfig 与上板验证
---

# 修 defconfig 与上板验证 —— 让 alpha 板真正出声

这一节上板。和 [RTC](../10_rtc_snvs_driver/)、[goodix](../11_goodix_touchscreen_driver/) 一样，**没有 `.ko` 可编译**——`fsl-asoc-card.c`/`wm8960.c`/`fsl_sai.c` 都编进内核、开机自动 probe。但音频这章比那俩多一个**前置坑**：mainline 的 defconfig 模板把 `fsl-asoc-card` 配成 `=m`，而项目 build 流程不编模块，结果整机静音。这就是 [Issue #43](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/43)，我们这一节第一件事就是把它修掉，再用 `aplay`/`amixer`/`arecord` 验证耳机出声、录音回放。

::: tip 学习目标
把 mainline defconfig 里 `CONFIG_SND_SOC_FSL_ASOC_CARD` 从 `=m` 改成 `=y`（Issue #43 根因）；编内核 + dtb；用 `install_alsa.sh` 给 rootfs 装 `aplay`/`amixer`/`arecord`；上板确认声卡、解 WM8960 默认静音、播放 WAV 出声、录音回放；掌握「无声」的排查思路。
:::

## 第一步：修 mainline defconfig（Issue #43）

::: warning 这个坑项目已经替你填了
本仓库的 `driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template` 已经把这一行改成 `=y` 了（见下方）。**你如果用本仓库的 defconfig，这步是已完成的**——下面是讲「为什么」，让你知道这个 `=y` 不是凭空来的。
:::

打开 `driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template`，找到 Sound 段：

```diff
  # --- Sound ---
  CONFIG_SOUND=y
  CONFIG_SND=y
  CONFIG_SND_SOC=y
  ...
- CONFIG_SND_SOC_FSL_ASOC_CARD=m
+ # fsl-asoc-card（WM8960 等 machine 驱动）：必须 =y。见 Issue #43
+ # 项目 build 流程不带 modules_install，=m 会让声卡整机静音。
+ CONFIG_SND_SOC_FSL_ASOC_CARD=y
  ...
  CONFIG_SND_SOC_WM8960=y
```

为什么 `=m` 不行？正点原子那种「内核 + 模块」的发行版，`=m` 表示编成 `.ko`、`modules_install` 装到 `/lib/modules/`、开机 `modprobe` 加载。但 **imx-forge 的内核 build 流程不带 `modules_install`**（`build-mainline-linux.sh` 只编 `zImage` + `modules`，但不部署到 rootfs），于是 `fsl-asoc-card.ko` 压根没出现在板子上 → machine 驱动缺席 → dai_link 绑不起来 → 声卡不存在 → `aplay: no soundcards found`。

而 `wm8960.c`（codec）和 `fsl_sai.c`（cpu_dai）在 defconfig 里是 `=y`、本来就在内核里。唯独 machine 驱动 `fsl-asoc-card` 漏成 `=m`——三层缺了中间的「缝纫机」，声卡就散架了。改成 `=y` 把它也编进内核，三层齐全，声卡上线。

::: details 想验证这个坑？做个对比实验
临时把那行改回 `=m`、重编内核、上板，你会看到：
```bash
aplay -l                              # aplay: device_list:274: no soundcards found
zcat /proc/config.gz | grep ASOC_CARD  # CONFIG_SND_SOC_FSL_ASOC_CARD=m
ls /lib/modules/*/kernel/sound/soc/fsl/  # 空的，.ko 没部署
```
改回 `=y` 重编，声卡就回来了。Issue #43 现象可复现、可修复。
:::

::: tip SDMA 也已 =y（2026-07-03「默认全」任务修）
早期 wm8960 章只改了 ASOC_CARD=y（主因），SDMA 留 `=m`。2026-07-03「让默认 build 驱动全」任务把 `CONFIG_IMX_SDMA` 也改 `=y`（子模块 defconfig + patch + 项目副本三同步），alpha 板 SAI2 的 DMA 链路完整——`imx-pcm-dma` 进内核、`fsl_sai` 拿得到 DMA channel。固件 6ULL 用 `sdma-imx6q.bin`（`install_firmwares.sh` 已装）。至此 Issue #43 的 ASOC_CARD + SDMA 双修复都真正进 build。上板若 `aplay` 仍报 DMA 错误，查 `zcat /proc/config.gz | grep IMX_SDMA` 应为 `=y`、`/lib/firmware/imx/sdma/sdma-imx6q.bin` 存在。
:::

## 第二步：编内核 + dtb

defconfig 改好后，编主线内核（会自动从 template 生成 `imx_aes_mainline_defconfig`）：

```bash
./scripts/build_helper/build-mainline-linux.sh
```

产物在 `out/mainline/linux/`：`zImage`、`imx6ull-aes.dtb`、模块。重点确认 build log 里 `fsl-asoc-card.o` / `snd-soc-wm8960.o` 被编进内核映像（而不是只生成 `.ko`）：

```bash
grep -iE "fsl-asoc-card|wm8960" out/mainline/linux/.built-in.a.cmd 2>/dev/null || true
# 或在编完的源码树里确认：
ls third_party/linux_mainline/sound/soc/fsl/fsl-asoc-card.o   # .o 存在说明编了
```

## 第三步：给 rootfs 装 ALSA 用户态

alpha 板的 rootfs 默认没有 `aplay`/`amixer`/`arecord`。本仓库的 `scripts/third_party_install/install_alsa.sh`（[本教程配套新增](index.md)）会交叉编译 `alsa-lib` + `alsa-utils`，把它们装进 rootfs。手动触发：

```bash
# 方式一：只跑 alsa 安装（快）
ROOTFS_DIR=rootfs/nfs ./scripts/third_party_install/install_alsa.sh

# 方式二：跑整个 rootfs 验证 + 第三方依赖安装（会自动执行所有 install_*.sh）
./scripts/varified_rootfs_ok.sh
```

跑完确认 `rootfs/nfs/usr/bin/aplay` 存在、`libasound.so.*` 在 `rootfs/nfs/usr/lib/`。脚本带缓存（`out/.alsa-workdir/`），第二次跑会跳过已下載的 tarball；想强制重装加 `FORCE=1`。

::: tip 工具链要先进 PATH
`install_alsa.sh` 用 `arm-none-linux-gnueabihf-` 交叉编译，跑前先 `source scripts/init/env-init.sh` 让工具链可见，否则报「Cross compiler not found」。
:::

## 第四步：部署 + 上板

- **dtb**：拷到 tftp 目录（`/home/charliechen/tftp`），netboot 固定拉 `imx6ull-aes.dtb`。**部署后必须重启板子**才生效（dtb 互斥、每次启动重拉）。
- **rootfs**：alpha 板走 NFS root，bind-mount 源指向 `rootfs/nfs`。**换 bind-mount 源后必须 `restart nfs-ganesha`**，否则板子挂载 ESTALE 报错。

## 第五步：确认声卡

上板启动后，先确认 [03 节](03_machine_driver_analysis.md) 那张 dai_link 真的绑起来了：

```bash
cat /proc/asound/cards
#  0 [wm8960audio  ]: wm8960-audio - wm8960-audio
#                       fsl,imx6ull SAI2 + WM8960 codec

ls /dev/snd/
# controlC0  pcmC0D0c  pcmC0D0p  timer     ← 有这四个就说明声卡在线

aplay -l
# card 0: wm8960audio [wm8960-audio], device 0: ...
#   Subdevices: 1/1
#   Subdevice #0: subdevice #0

dmesg | grep -iE "wm8960|fsl-asoc-card"
# wm8960 0-001a: ...
# asoc-simple-card fsl-asoc-card.0: ...
```

如果 `aplay -l` 报 `no soundcards found`，回到第一步确认 defconfig 是 `=y`、内核是重编过的——大概率就是 Issue #43 没修干净。

## 第六步：解 WM8960 默认静音（出声的关键）

::: warning 全章最大的坑：WM8960 上电默认静音，两道闸门都要开
即使声卡 probe 成功，`aplay` 也可能**完全没声音**——WM8960 复位后有两道闸门默认关着，必须都打开：

1. **音量寄存器 = 0**（`Playback`/`Headphone`/`Speaker` 都是最小）：`amixer sset ... 100%` 拧满。
2. **`Left/Right Output Mixer PCM` 默认 mute**（DAC 数据进 Output Mixer 的开关关着——音量再大、数据也到不了耳机）：必须 `sset ... on`。**这道最容易漏，实测不开就没声**。

两道都开才出声。控件名用 `amixer -c 1 scontrols` 查（amixer simple 模式是**短名** `'Headphone'`、`'Playback'`，不是 `wm8960_snd_controls[]` 里的全称 `'Headphone Playback Volume'`）。这不是 bug，是 codec 的默认状态。
:::

先用 `amixer` 看 card 1 上有哪些控件（`amixer -c 1 scontrols`），再逐个拧大：

```bash
# 列出所有控件（确认名字；amixer simple 用短名）
amixer -c 1 scontrols

# —— 播放链路：把 DAC、耳机、喇叭音量全拧到 100% ——
amixer -c 1 sset 'Playback' 100%       # DAC 输出音量
amixer -c 1 sset 'Headphone' 100%      # 耳机音量
amixer -c 1 sset 'Speaker' 100%        # 喇叭音量
# 关键：PCM 数据进 Output Mixer 的开关，默认可能 mute，不开就没声
amixer -c 1 sset 'Left Output Mixer PCM' on
amixer -c 1 sset 'Right Output Mixer PCM' on

# —— 录音链路 ——
amixer -c 1 sset 'Capture' 100%
amixer -c 1 sset 'ADC PCM' 100%
```

::: details 为什么是这些控件名？
`wm8960.c` 的 `wm8960_snd_controls[]` 定义了所有用户态可调控件（`:247`）。WM8960 没有独立的 mute 开关，靠 Volume = 0 实现静音，所以「解 mute」就是「设音量」。`amixer contents` 能列出你这颗 WM8960 的全部控件（名字可能因内核版本略有出入），以板子实际为准。
:::

## 第七步：播放 WAV 出声

把一个测试 WAV（任意 48kHz/44.1kHz 16-bit 立体声 WAV）放进 rootfs，插上耳机：

```bash
aplay -D plughw:1,0 /path/to/test.wav
# Playing WAVE '/path/to/test.wav' : Signed 16 bit Little Endian, Rate 44100 Hz, Stereo
# ← 耳机里应该听到声音了（WM8960 是 card 1，用 plughw:1,0 指定）
```

听到声音，整条链路就通了：用户态 `aplay` → `libasound` → `/dev/snd/pcmC1D0p` → ASoC core（[03 节](03_machine_driver_analysis.md) 的 card）→ DMA 搬 PCM 数据 → SAI2 TX_DATA → WM8960 DAC → Output Mixer → HP PGA → 耳机。

## 第八步：录音回放

接个麦克风（板载 AMIC 或 3.5mm Mic Jack），录 3 秒再播：

```bash
arecord -d 3 -f cd -D plughw:1,0 /tmp/r.wav
# Recording... (3 秒, CD 质量 44.1kHz 16bit 立体声)

aplay /tmp/r.wav    # 把刚录的播出来，耳机里听到自己刚才录的
```

能录能播，说明 RX_DATA（codec→CPU）方向也通、Capture 链路（MICB → LINPUT → Boost → Input Mixer → ADC）的 DAPM 通路也上电了。

## 排错速查

| 现象 | 排查 |
|------|------|
| `aplay: no soundcards found` | defconfig `ASOC_CARD=m` 没改 `=y`（Issue #43）；或内核没重编；或 dtb 没更新重启 |
| 声卡在、但 `aplay` 完全无声 | 默认静音两道闸门：① `Playback`/`Headphone`/`Speaker` 拧 100% ② **`Left/Right Output Mixer PCM` 设 on**（最容易漏，第六步） |
| 声音极小/失真 | `Playback` 没拧满；或耳机没插紧；或 `Speaker` 当耳机用了 |
| `aplay` 报 `SND_ERROR DMA` 类错误 | SAI2 / DMA 没绑上；查 `dmesg \| grep -i sai` 看 `fsl_sai` probe 有没有报错（pinctrl、clock） |
| 录音全零（`arecord` 文件存在但无声） | `Capture`/`ADC PCM` 没拧满；`MICB` 偏置没上（DAPM 路径断）；麦克风没接对路（Mic Jack vs AMIC） |
| I2C 探不到 0x1a | `ls /sys/bus/i2c/devices/` 没 `0-001a`；查 WM8960 供电、I2C1 上拉、地址脚。**注意 WM8960 在 I2C1（i2c-0）不是 I2C2**，`i2cdetect -y 0` 应命中 0x1a（[05 节](05_device_tree.md) 踩坑） |
| probe 报 `failed to set sysclk` | MCLK 时钟树配错——检查 `&sai2` 的 `assigned-clock-rates = <0>, <12288000>` 数字 |
| 时钟对、配置对、还是杂音 | MCLK 不是 256×FS 整数倍时 codec 会启 PLL，jitter 大；确认 MCLK = 12288000（48k）或改采样率 |

## 小结

这一节我们在 alpha 板上把 WM8960 验证通了：先修掉 mainline defconfig 的 `ASOC_CARD=m` 坑（Issue #43，让 machine 驱动编进内核），编内核 + dtb，用 `install_alsa.sh` 装 `aplay`/`amixer`/`arecord`，部署上板，`cat /proc/asound/cards` 确认 `wm8960-audio` 上线，`amixer` 解掉 WM8960 默认静音这个最大坑，最后 `aplay` 出声、`arecord` 录音回放。全程没编译一行驱动代码——`fsl-asoc-card.c` / `wm8960.c` / `fsl_sai.c` 全默认在内核里，我们要做的只是「让它正确地编进去 + 把音量拧开」。

回头看，音频这章和 RTC、goodix 一样走了「分析型」路线：把主线这套 machine + codec + cpu_dai 三件套从 ASoC 架构（[02 节](02_asoc_framework.md)）、probe 缝合（[03 节](03_machine_driver_analysis.md)）、codec 与时钟（[04 节](04_codec_and_clock.md)）、设备树（[05 节](05_device_tree.md)）一路拆透，再上板验证。到这里，Linux 音频子系统这块拼图补齐了——以后遇到任何 codec（wm8962、sgtl5000、cs42xx8……），套路都是：`fsl-asoc-card` 加个 `compatible` 分支、设备树改俩节点、codec 驱动换一份，machine 和 cpu_dai 不用动。

---

<ChapterNav variant="sub">
  <ChapterLink href="05_device_tree.md" variant="sub">← 设备树配置</ChapterLink>
  <ChapterLink href="../modules/" variant="sub">模块开发 →</ChapterLink>
</ChapterNav>
