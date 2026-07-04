---
title: 架构概览
---

# WM8960 音频驱动 —— 架构概览

## 前言：WM8960 为什么也不自己写

[RTC](../10_rtc_snvs_driver/)、[goodix](../11_goodix_touchscreen_driver/) 两章我们开了「分析型」的头：主线驱动太成熟，重写没意义，不如拆开读懂。音频这章接着走这条路——而且理由更硬。

WM8960 是 Wolfson（现 Cirrus Logic）的一颗立体声音频 codec，i.MX6ULL ALPHA 板上用它做耳机/喇叭输出和麦克风输入。主线内核对它的支持是**完整三层**：

- `sound/soc/codecs/wm8960.c`（1591 行）—— codec 驱动，管 WM8960 的所有寄存器、音频通路、DAPM
- `sound/soc/fsl/fsl_sai.c`（1900+ 行）—— cpu_dai 驱动，管 i.MX6ULL 这端的 SAI2 数字音频接口
- `sound/soc/fsl/fsl-asoc-card.c`（1112 行）—— machine 驱动，把上面俩缝成一张声卡

这三颗驱动被 NXP、主线社区、无数 i.MX 板子反复验证过。正点原子教程里那套自己写的 `imx-wm8960.c` machine 驱动，在主线的 `fsl-asoc-card` 面前就是「重新发明轮子」——`fsl-asoc-card` 一个 machine 驱动兼容 WM8960/WM8962/SGTL5000/CS42XX8/TLV320AIC3x 一大家子 codec，你板子这颗 WM8960 它本来就支持。

所以这章的任务：**把这三颗驱动拆给你看**，再上板让耳机出声。驱动本体一行都不用你敲。

::: tip 学习目标
理清 Linux ASoC「machine + codec + cpu_dai + platform」四件套各自的角色；看懂 alpha 板的音频硬件链路（SAI2 怎么连 WM8960、MCLK 哪来的、耳机/喇叭/麦克风怎么走线）；理解为什么正点原子的 `imx-wm8960.c` 该被主线 `fsl-asoc-card` 取代。
:::

## 音频为什么是「四件套」

按键、触摸那些驱动，基本是「一个驱动搞定一颗 IC」。音频不一样——一块声卡从软件看是**四个角色分工合作**，这正是 ASoC（ALSA System on Chip）子系统要解决的：

| 角色 | 干什么 | alpha 板对应 | 主线驱动 |
|------|--------|------------|---------|
| **machine**（card） | 「缝纫机」：把 cpu_dai 和 codec 按某种拓扑缝成一张声卡，定义 DAI 格式、时钟、音频通路 routing | `sound-wm8960` 节点 | `fsl-asoc-card.c` |
| **cpu_dai** | CPU 这端的数字音频接口驱动（串行音频总线，传 PCM 数据 + 位/帧时钟） | SAI2 接口 | `fsl_sai.c` |
| **codec** | 外接音频芯片驱动：控制模拟通路（麦克风→ADC、DAC→耳机/喇叭）、寄存器、DAPM | WM8960（I2C 0x1a） | `wm8960.c` |
| **platform** | 音频数据搬运工：DMA 把内存里的 PCM 数据搬到 SAI2、再喂给 codec | imx-pcm-dma | `imx-pcm-dma.c`（被 fsl_sai 自动 select） |

为什么要分四块？因为同一颗 cpu_dai（SAI2）可以接不同 codec（WM8960、SGTL5000……），同一颗 codec 也能被不同 cpu_dai 驱动。**分层 = 复用**：换 codec 只换 codec 驱动 + 设备树节点，machine 和 cpu_dai 不用动。`fsl-asoc-card` 就是利用这套分层，一个 machine 驱动通吃 N 种 codec。

::: info 一个生活化的比喻
把声卡想象成一个乐队：**platform（DMA）**是搬运乐谱的助理，**cpu_dai（SAI2）**是 CPU 这端的指挥棒（打节拍、传音符），**codec（WM8960）**是真正的乐手（把数字音符变成模拟声波），**machine（card）**是乐队经理——它不发声，但它决定「谁和谁组乐队、按什么谱子演」。少任何一块，乐队都转不起来。
:::

[02 节](02_asoc_framework.md) 会把这四件套的软件绑定关系（`snd_soc_card` / `snd_soc_dai_link` / `snd_soc_dai` / `snd_soc_codec_driver`）掰开讲。这里先有个全景就行。

## alpha 板音频链路全景

纸上谈兵结束，看看 alpha 板上这条链路物理上怎么连。WM8960 和 i.MX6ULL 之间有两根总线：

```
                 I2C1 (控制面，配寄存器)
   i.MX6ULL  ───────────────────────────  WM8960 (codec, 0x1a)
             ───────────────────────────
                 SAI2 (数据面，传音频 + 时钟)
```

- **I2C1，地址 0x1a**：控制通道。CPU 通过它读写 WM8960 的寄存器（音量、静音、通路选择、上电）。这条线和 [08 章](../08_i2c_ap3216c_driver/) AP3216C 的 I2C 套路完全一样。**注意是 I2C1，不是原版资料的 I2C2**——alpha 板实测 WM8960 + AP3216C 都在 I2C1，goodix 才在 I2C2，[05 节](05_device_tree.md) 有这个坑的详解。
- **SAI2**：数据通道。五根信号线：`TX_BCLK`（位时钟）、`TX_SYNC`（帧/字选择）、`TX_DATA`（CPU→codec 的播放数据）、`RX_DATA`（codec→CPU，录音用）、`MCLK`（主时钟）。这里有个**反直觉**的点：时钟角色上 **BCLK 和 LRCLK 由 WM8960 产生、SAI2 反而是从**（这叫 codec-master 模式），而 **MCLK 由 CPU 产生送给 codec**——03 节拆 `CARD_WM8960` 分支时你会看到 `DAIFMT_CBP_CFP` 就是这层意思，[02 节](02_asoc_framework.md) 会把主从关系彻底讲透。

::: warning 引脚是「借」JTAG 的
alpha 板上 SAI2 没有独占引脚，是**复用了 JTAG 那组脚**（TDI/TDO/TRST/TCK/TMS → SAI2_TX_BCLK/TX_SYNC/TX_DATA/RX_DATA/MCLK）。所以设备树 `pinctrl_sai2` 里你会看到 `MX6UL_PAD_JTAG_TDI__SAI2_TX_BCLK` 这种「JTAG 脚变 SAI 脚」的映射——别觉得眼熟就以为还能用 JTAG 调试，那组脚已经被音频征用了。
:::

时钟怎么来？i.MX6ULL 内部有个音频 PLL（PLL4），分频出 **12.288MHz** 从 MCLK 脚送给 WM8960。为什么是 12.288MHz？因为 **12288000 = 48000 × 256**，48kHz 采样率、256 倍过采样，WM8960 拿这个 MCLK 内部分频就能直接生成所有需要的时钟，**不用再启 codec 内部的 PLL**——省事。这条时钟路由 [04 节](04_codec_and_clock.md) 会深挖。

模拟那侧，alpha 板上 WM8960 接了三路：

- **耳机**（Headphone）：左右声道，`HP_L/HP_R`，有耳机检测引脚（`hp-det-gpio`，GPIO5_IO04）
- **喇叭**（Ext Spk）：外部功放，`SPK_LP/LN/RP/RN`（桥接负载）
- **麦克风**（Mic Jack / AMIC）：`LINPUT2/3`、`RINPUT1/2`，WM8960 提供 MICB 偏置电压

设备树里 `audio-routing` 那一串字符串，就是定义这些模拟通路的连接关系——[05 节](05_device_tree.md) 逐行解读。

## 为什么不用正点原子的 imx-wm8960.c

正点原子教程（草稿 ch65）的方案是：自己写一个 `imx-wm8960.c` 当 machine 驱动，配合主线 `wm8960.c` codec 和 `fsl_sai.c`。这条路能跑，但**没必要**——主线早就有 `fsl-asoc-card.c` 这个通用 machine 驱动，`compatible = "fsl,imx-audio-wm8960"` 就是给 WM8960 准备的。

两份 machine 驱动干的是同一件事（定义 dai_link、设 DAI 格式、注册 card），但 `fsl-asoc-card` 更通用（一份代码兼容十几种 codec）、维护更勤（主线社区在养）、还顺手支持 ASRC（异步采样率转换）。自写的 `imx-wm8960.c` 只能接 WM8960 一颗。所以本项目（[Issue #43](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/43) 的修复）明确：**复用主线 `fsl-asoc-card`，不移植 `imx-wm8960.c`**。

这章我们就拆主线这套。你也省得去维护一份「抄过来就再没动过」的 machine 驱动。

## WM8960 能力速览

拆代码前，先知道这颗芯片能干什么：

- **采样率**：8kHz – 48kHz（电话质量到 CD 质量足够，再高就得换 codec 了）
- **采样精度**：16 / 20 / 24 / 32 bit
- **通道**：立体声（2 通道）播放 + 录音
- **模拟接口**：3 路立体声输入（LINPUT1/2/3、RINPUT1/2/3）、立体声耳机输出（HP_L/R）、桥接喇叭输出（SPK_L/R）、单独的 OUT3
- **片上**：ADC、DAC、麦克风偏置（MICBIAS）、可编程增益（PGA）、混音器、3D 增强、ALC（自动电平控制）

这些能力在 `wm8960.c` 里全是 DAPM widget 和 kcontrol（音量/静音那种用户态能调的控件）。`amixer` 看到的 `Headphone`、`Speaker`、`PCM Playback Volume` 那些，就是从这里来的。

## 分析型打开方式：和 RTC / goodix 一致

| 维度 | 从零写 machine 驱动 | 本章（分析型） |
|------|-------------------|----------------|
| 驱动代码 | 我们写 `imx-wm8960.c` → `.ko` | 复用主线 `fsl-asoc-card.c`，**不写驱动** |
| 学习重点 | 怎么缝一张声卡 | 怎么读懂 ASoC 四件套 + DAPM + 时钟 |
| 配套产物 | 自写 machine `.ko` + app | 设备树解读 + alsa-utils + aplay/arecord 验证 |
| 验证手段 | `insmod` + 自写 app | `aplay`/`amixer`/`arecord`（现成工具） |

## 小结

这一节我们理清了：音频这章和 RTC/goodix 一样走分析型（主线三层驱动太成熟）、ASoC 为什么是 machine/codec/cpu_dai/platform 四件套（分层 = 复用）、alpha 板的物理链路（I2C1 控制 + SAI2 数据 + MCLK 12.288MHz + 三路模拟通道）、以及为什么弃用正点原子的 `imx-wm8960.c` 改用主线 `fsl-asoc-card`。接下来 [02 节](02_asoc_framework.md) 先把 ASoC 子系统那套软件绑定关系理清楚——这是看懂三颗驱动怎么「缝」在一起的前提。

---

<ChapterNav variant="sub">
  <ChapterLink href="index.md" variant="sub">← 返回目录</ChapterLink>
  <ChapterLink href="02_asoc_framework.md" variant="sub">ASoC 子系统与四件套 →</ChapterLink>
</ChapterNav>
