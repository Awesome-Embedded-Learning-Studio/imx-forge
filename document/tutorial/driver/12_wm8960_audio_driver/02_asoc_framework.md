---
title: ASoC 子系统与四件套
---

# ASoC 子系统与四件套 —— Card、dai_link 与 DAPM 怎么缝出一张声卡

[01 节](01_introduction.md) 我们把音频的四件套（machine / cpu_dai / codec / platform）按角色分了工。这一节拆开看它们**软件上怎么连起来**——也就是 ASoC（ALSA System on Chip）子系统那套数据结构。说白了，ASoC 干的事就一件：**让「CPU 这端」和「codec 那端」两个独立写的驱动，能在运行时被「machine 驱动」缝成一张完整的声卡**。

这一节概念偏多，但全是后面拆 `fsl-asoc-card.c` 的前置知识。啃完它，[03 节](03_machine_driver_analysis.md) 的 probe 你会觉得顺理成章。

::: tip 学习目标
搞懂 ASoC 四个核心数据结构（`snd_soc_card` / `snd_soc_dai_link` / `snd_soc_dai` / `snd_soc_component`）的绑定关系；理解 DAI 信号的位时钟/帧时钟/数据/MCLK 四件及其与采样率的数学关系；分清 I2S / Left-Justified / DSP 等 DAI 格式，以及 CBP_CFP / CBC_CFC 四种主从组合；看懂 DAPM「按需上电」的 widget / route / path 模型。
:::

## 一、四个核心数据结构

ASoC 把声卡抽象成几个互相引用的结构体。不用记全字段，记住**谁引用谁**就行：

| 结构体 | 谁来填 | 装着什么 | 数量关系 |
|--------|--------|---------|---------|
| `snd_soc_card` | **machine** 驱动 | 一张声卡的总入口：名字、`dai_link[]` 数组、routing、probe 回调 | 一张声卡 1 个 |
| `snd_soc_dai_link` | **machine** 驱动 | 一条「音频流通道」的契约：接哪个 cpu_dai、哪个 codec_dai、DAI 格式、平台 | 一张声卡 N 条（alpha 板 1 条 HiFi） |
| `snd_soc_dai` | 内核运行时拼装 | 一个 DAI 实例（CPU 侧和 codec 侧各一个），是 cpu_dai/codec 驱动的「运行时化身」 | 每个 dai_link 里 2 个（cpu + codec） |
| `snd_soc_component` / `snd_soc_dai_driver` | **codec / cpu_dai** 驱动 | codec 的寄存器操作、DAPM widget、kcontrol；DAI 的能力（采样率/格式） | 每颗芯片 1 套 |

它们的引用链：

```
                 snd_soc_card  (machine: fsl-asoc-card.c)
                      │
                      ├── dai_link[0]  ──┐   "HiFi" 这条流
                      │   (cpu_dai 名)   │
                      │   (codec_dai 名) │
                      │   (platform 名)  │
                      │   dai_fmt        │
                      │                 │
              ┌───────┴───────┐    ┌────┴─────────────┐
              ▼               ▼    ▼                  ▼
         snd_soc_dai     snd_soc_dai(snd_soc_dai_driver)
         (cpu: SAI2)     (codec: wm8960-hifi) ←── wm8960.c 注册
              │
              └── snd_soc_component ── DAPM widget / kcontrol / regmap
```

一句话：**machine 驱动用 `dai_link` 把 cpu_dai 和 codec_dai「点名」绑在一起**，内核再按名字找到两侧的 `snd_soc_dai` 实例、配上 `dai_fmt`，一条音频流就通了。`platform`（DMA）由 cpu_dai 驱动自动 select，machine 几乎不用管。

## 二、dai_link：一张声卡的「最小契约」

`dsl-asoc-card.c` 为 alpha 板搭的 `dai_link[0]`（HiFi），关键字段长这样（简化自 `include/sound/soc.h`）：

```c
struct snd_soc_dai_link {
    const char *name;                 /* "HiFi" —— 这条流的名字 */
    const char *stream_name;          /* 用户态 aplay -L 看到的 PCM 流名 */

    struct snd_soc_dai_link_component *cpus;     /* 指向 &sai2（cpu_dai） */
    unsigned int num_cpus;
    struct snd_soc_dai_link_component *codecs;   /* 指向 &codec（codec_dai） */
    unsigned int num_codecs;
    struct snd_soc_dai_link_component *platforms; /* DMA platform（imx-pcm-dma） */
    unsigned int num_platforms;

    unsigned int dai_fmt;             /* I2S / 主从 / 极性 —— 见第三节 */
    int (*init)(struct snd_soc_pcm_runtime *rtd); /* 可选：runtime 初始化回调 */
    /* ... */
};
```

注意它**只存名字（或 of_phandle 引用）**，不存代码。machine 驱动填进去的是「cpu 用 sai2、codec 用 wm8960-hifi」，内核再拿这些名字去 `snd_soc_dai` 列表里找实例。这就是分层的精髓：machine 不关心 SAI2 和 WM8960 的寄存器怎么写，它只管「让它们俩搭档」。

::: info 一个比喻
`dai_link` 是乐队经理（machine）签的**演出合同**：上面写着「这次演出，指挥棒用 SAI2、乐手请 WM8960、乐谱搬运交给 imx-pcm-dma、按 I2S 谱子、codec 来打节拍」。合同本身不发声，但没它，三个人各干各的，永远凑不出一首曲子。
:::

## 三、DAI 信号：BCLK / LRCLK / DATA / MCLK

数字音频接口（DAI）就是 CPU 和 codec 之间的那几根串行线。讲清楚每根线的含义和它们与采样率的数学关系，是看懂时钟路由的前提。

| 信号 | 全称 | 作用 | alpha 板方向 |
|------|------|------|------------|
| **MCLK** | Master Clock | 给 codec 当「心脏」时钟源，codec 内部分频出一切 | CPU → codec（12.288MHz） |
| **BCLK** | Bit Clock | 位时钟：每个 bit 一拍 | **codec → CPU**（codec-master） |
| **LRCLK** | LR Clock / WS | 帧时钟（Word Select）：高=右声道、低=左声道 | **codec → CPU** |
| **DATA** | Audio Data | 串行音频数据 | TX: CPU→codec（播放）<br>RX: codec→CPU（录音） |

::: tip 采样率怎么算出来？
对 48kHz / 16bit 立体声：
- **LRCLK = 采样率 = 48 kHz**（每秒 48000 个帧，每帧含左+右两个采样）
- **BCLK = LRCLK × 位宽 × 声道 = 48000 × 16 × 2 = 1.536 MHz**
- **MCLK = LRCLK × 256 = 12.288 MHz**（256 倍过采样，常见系数 64/128/256/384）

所以 alpha 板把 MCLK 配成 **12.288MHz**（设备树 `assigned-clock-rates = <0>, <12288000>`），WM8960 收到后内部分频出 BCLK/LRCLK——**codec 不用启自己的 PLL**。[04 节](04_codec_and_clock.md) 拆时钟路由时还会再算一遍。
:::

## 四、DAI 格式：左右声道怎么分时

BCLK 上跑的是连续 bit，那「哪些 bit 属于左声道、哪些属于右」？这就由 **DAI 格式 + LRCLK 极性** 决定。常见的几种（alpha 板用第一种）：

```
I2S 格式（Philips 标准）：LRCLK 翻转后，延迟 1 个 BCLK 才出现数据 MSB
       ┌──左──┐┌──右──┐
LRCLK ─┘      └┘      └─
DATA     [L15..L0]  [R15..R0]
BCLK   ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃   ← 每个 bit 一拍

Left-Justified：LRCLK 翻转同时，数据 MSB 立刻出现（无 1 BCLK 延迟）

DSP A/B：LRCLK 是窄脉冲（1 BCLK 宽），数据紧跟其后（模式 A/B 差脉冲位置/极性）
```

alpha 板走 **I2S**（`DAI_FMT_BASE` 里写死的 `SND_SOC_DAIFMT_I2S`，`fsl-asoc-card.c:41`）。`NB_NF` 表示位时钟正常极性、帧时钟正常极性（不反转）。绝大多数 codec 都默认 I2S，所以这是最省心的选择。

::: details 为什么不都用 I2S？
I2S 是「带 1 BCLK 延迟」的标准，最通用。但有些老 codec 或 DSP 用 Left-Justified（省那 1 拍延迟）、TDM 多通道用 DSP 模式。alpha 板的 WM8960 三种都支持，I2S 是默认且最常见，所以主线给它配 I2S。
:::

## 五、主从：谁产生时钟（CBP_CFP 还是 CBC_CFC）

这是最绕、也最容易写反的一点。内核用 **四个组合** 描述「codec 这端在 BCLK/LRCLK 上是 provider（产生）还是 consumer（接收）」：

| dai_fmt 宏 | codec 角色 | alpha 板？ |
|-----------|----------|-----------|
| `CBP_CFP` | codec 产生 BCLK **和** LRCLK | ✅ **就是这个** |
| `CBP_CFC` | codec 产生 BCLK，但 LRCLK 由 CPU 给 | |
| `CBC_CFP` | codec 产生 LRCLK，但 BCLK 由 CPU 给 | |
| `CBC_CFC` | codec 都不产生（CPU 全给） | |

> 记法：**C**odec **B**it-clock **P**rovider/Consumer + **C**odec **F**rame-clock **P**rovider/Consumer。Provider=产生、Consumer=接收。

`fsl-asoc-card.c` 的 WM8960 分支（`:786`）写的就是 `priv->dai_fmt |= SND_SOC_DAIFMT_CBP_CFP;`——**WM8960 当时钟主、SAI2 当从**。这跟「MCLK 由 CPU 送给 codec」并不矛盾：MCLK 是「原料时钟」，WM8960 拿它分频出 BCLK/LRCLK 再「反哺」给 SAI2，SAI2 只管按 BCLK 节拍收发数据。

::: warning 为什么 alpha 板让 codec 当主？
两种模式都能工作，选 codec-master 通常是历史 + 硬件设计原因：WM8960 在 codec-master 下，BCLK/LRCLK 由它内部从 MCLK 精确分频，jitter 更可控（时钟源单一）；CPU 当主则要 SAI 自己分频，灵活性高但时钟树更复杂。i.MX + WM8960 这套组合社区验证下来用 CBP_CFP 最稳。**你在设备树里可以覆盖这个选择**（`dai-format` 属性），[05 节](05_device_tree.md) 会提到。
:::

## 六、DAPM：按需上电的 widget / route / path

codec 驱动（`wm8960.c`）里最庞大的部分是 **DAPM（Dynamic Audio Power Management）**。它解决一个现实问题：codec 里有 ADC、DAC、耳机放大器、喇叭放大器、麦克风偏置、一堆混音器……全开着费电、还会串扰。DAPM 让内核**根据「当前要播还是要录」自动只开必要的通路**。

DAPM 三个概念：

- **widget**：一个通路上器件的抽象。类型有 `ADC`、`DAC`、`HP`（耳机）、`SPK`（喇叭）、`MIC`（麦克风）、`Mixer`、`PGA`（可编程增益）、`AIF_IN`/`AIF_OUT`（数字音频接口进出）等。每个 widget 对应 codec 的一组寄存器位（电源开关）。
- **route**：widget 之间的连线，是个三元组 `(sink, control, source)`——「从 source 流向 sink、中间可能经过 control」。比如 `("Headphone Jack", NULL, "HP_L")` 表示 HP_L 这个放大器输出接到 Headphone Jack。
- **path**：内核运行时把 widget + route 拼成一张**有向图**，当用户态打开某条 PCM 流时，从 AIF（数字口）出发搜到目标输出（如 HP），**只把这条 path 上的 widget 上电**，其余保持断电。

alpha 板的 routing（设备树 `audio-routing` 那一串）就是定义这些连线，比如：

```
"Headphone Jack" ← "HP_L", "HP_R"      （DAC → 耳机放大器 → 耳机口）
"Ext Spk"        ← "SPK_LP/LN/RP/RN"   （DAC → 喇叭放大器 → 喇叭）
"Mic Jack"       ← "LINPUT2/3"         （麦克风 → PGA → ADC）
```

[04 节](04_codec_and_clock.md) 拆 `wm8960.c` 时会把它的 widget 表和 `set_bias_level` 上电序列展开讲。这里先记住：**DAPM 让 codec 像个智能电闸，按需给每条音频通路送电**。

## 七、platform：DMA 搬运工

最后一块，platform（DMA）其实你不用操心。`fsl_sai.c` 在 Kconfig 里 `select SND_SOC_IMX_PCM_DMA`，SAI2 probe 时会自动挂上 imx 的 DMA 引擎。machine 驱动只在 `dai_link->platforms` 里填个名字（或留空让内核默认），DMA 通道就配好了。

它的作用：用户态 `aplay` 把 PCM 数据丢进内存环形缓冲区，**platform 层用 SDMA 把数据自动搬到 SAI2 的 TX FIFO**，SAI2 再按 BCLK 节拍把数据从 TX_DATA 推给 WM8960。整个过程不用 CPU 干预，是音频能实时低延迟的关键。

## 小结

这一节我们把 ASoC 的软件骨架拆清楚了：四件套靠 `snd_soc_card` → `snd_soc_dai_link` → `snd_soc_dai` 这条引用链缝成一张声卡；`dai_link` 是 machine 签的「演出合同」，只点名不写代码；DAI 信号里 MCLK（CPU→codec，12.288MHz）是原料、BCLK/LRCLK（codec→CPU）是节拍、DATA 是音频；格式走 I2S、主从是 codec-master（`CBP_CFP`）；DAPM 用 widget/route/path 图实现按需上电；DMA 由 cpu_dai 自动挂。接下来 [03 节](03_machine_driver_analysis.md) 就用这套理论去拆 `fsl-asoc-card.c` 的 probe，看它具体怎么搭出 alpha 板的这张 HiFi dai_link。

---

<ChapterNav variant="sub">
  <ChapterLink href="01_introduction.md" variant="sub">← 架构概览</ChapterLink>
  <ChapterLink href="03_machine_driver_analysis.md" variant="sub">fsl-asoc-card.c 逐段拆解 →</ChapterLink>
</ChapterNav>
