---
title: fsl-asoc-card.c 逐段拆解
---

# fsl-asoc-card.c 逐段拆解 —— probe 怎么缝出 HiFi 这条声卡

理论武装完毕（[02 节](02_asoc_framework.md)），这一节正式拆 machine 驱动 `sound/soc/fsl/fsl-asoc-card.c`（mainline 7.1，1112 行）。它和 [RTC 章的 rtc-snvs.c](../10_rtc_snvs_driver/)、goodix.c 一样是标准子系统驱动，只不过挂在 platform 总线上、干的是「缝纫机」的活——把 cpu_dai（SAI2）和 codec_dai（wm8960-hifi）按 [02 节](02_asoc_framework.md) 讲的 dai_link 契约绑成一张声卡。

::: tip 学习目标
看懂 `fsl-asoc-card.c` 的 `platform_driver` 骨架与 14 种 codec 的 compatible 表；跟着 `fsl_asoc_card_probe`（`:614`）走完「解析设备树 → 选 codec 分支 → 搭 dai_link → 注册 card」的完整流程；认清 WM8960 专属分支（`:782`）那几行决定了什么；理解 ASRC 那两条额外 dai_link 是干什么的（可选）。
:::

## 驱动骨架：platform_driver + 14 种 compatible

整颗驱动是一个 `platform_driver`（`sound-wm8960` 节点是 platform 设备，不是 i2c/timer，所以走 platform 总线）：

```c
/* fsl-asoc-card.c:1079 —— 设备树匹配表：一个 machine 通吃 14 种 codec */
static const struct of_device_id fsl_asoc_card_dt_ids[] = {
    { .compatible = "fsl,imx-audio-wm8960", },   /* ← alpha 板命中这条 */
    { .compatible = "fsl,imx-audio-wm8962", },
    { .compatible = "fsl,imx-audio-sgtl5000", },
    { .compatible = "fsl,imx-audio-cs427x", },
    { .compatible = "fsl,imx-audio-tlv320aic32x4", },
    /* ... 共 14 种 codec ... */
    { }
};

/* :1098 —— platform 驱动骨架 */
static struct platform_driver fsl_asoc_card_driver = {
    .probe  = fsl_asoc_card_probe,
    .driver = {
        .name = DRIVER_NAME,                  /* "fsl-asoc-card" */
        .pm   = &snd_soc_pm_ops,
        .of_match_table = fsl_asoc_card_dt_ids,
    },
};
module_platform_driver(fsl_asoc_card_driver);
```

内核启动解析设备树，看到 alpha 板 `imx6ull-aes.dtsi` 里 `sound-wm8960` 节点的 `compatible = "fsl,imx-audio-wm8960"`，就用这张表匹配、触发 `fsl_asoc_card_probe`。**一份 machine 驱动兼容 14 种 codec**——这就是它能把正点原子那颗只认 WM8960 的 `imx-wm8960.c` 挤掉的本钱。

## probe 全景：从设备树到注册 card

`fsl_asoc_card_probe`（`:614`）是这颗驱动的心脏。它要把设备树 `sound-wm8960` 节点里那几个 phandle，变成一张注册进 ASoC 核心的 `snd_soc_card`。分步看。

### 第 1 步：解析设备树四件（audio-cpu / audio-codec / audio-asrc / MCLK）

```c
/* fsl-asoc-card.c:640 —— cpu DAI 节点（SAI2） */
cpu_np = of_parse_phandle(np, "audio-cpu", 0);
...
/* :659 —— codec 节点（支持双 codec，WM8960 用第 0 个） */
codec_np[0] = of_parse_phandle(np, "audio-codec", 0);
codec_np[1] = of_parse_phandle(np, "audio-codec", 1);
/* :682 —— ASRC 节点（可选） */
asrc_np = of_parse_phandle(np, "audio-asrc", 0);
```

三个 `of_parse_phandle` 把设备树的 `audio-cpu = <&sai2>`、`audio-codec = <&codec>`、`audio-asrc = <&asrc>` 解析成 `device_node *`。alpha 板这三个都有（[05 节](05_device_tree.md) 会贴完整节点）。

紧接着读 MCLK 频率：

```c
/* :686 —— MCLK 频率由 codec 端的 "mclk" clk 决定，留给 codec 驱动去 enable */
for (codec_idx = 0; codec_idx < 2; codec_idx++) {
    struct clk *codec_clk = clk_get(codec_dev[codec_idx], NULL);
    if (!IS_ERR(codec_clk)) {
        priv->codec_priv[codec_idx].mclk_freq = clk_get_rate(codec_clk);
        clk_put(codec_clk);
    }
}
```

注释写得很明白——「Get the MCLK rate only, and leave it controlled by CODEC drivers」：machine 只**读** MCLK 频率（=12288000），真正的 `clk_prepare_enable` 留给 codec 驱动（`wm8960.c`）干。这是分层：谁用谁管。默认采样率先填 44100/S16（运行时 `hw_params` 会覆盖）：

```c
/* :698 */ priv->sample_rate = 44100;
priv->sample_format = SNDRV_PCM_FORMAT_S16_LE;
```

### 第 2 步：dai_fmt 基础 + dai_link 模板拷贝

```c
/* :702 */ priv->dai_fmt = DAI_FMT_BASE;     /* I2S | NB_NF —— 见 :41 */
/* :705 */ memcpy(priv->dai_link, fsl_asoc_card_dai,
                 sizeof(struct snd_soc_dai_link) * ARRAY_SIZE(priv->dai_link));
```

`DAI_FMT_BASE`（`:41`）是 `SND_SOC_DAIFMT_I2S | SND_SOC_DAIFMT_NB_NF`——所有 codec 共用「I2S + 正常极性」当起点。`fsl_asoc_card_dai`（`:316`）是三组静态 `snd_soc_dai_link` 模板，name 分别是 `"HiFi"`、`"HiFi-ASRC-FE"`、`"HiFi-ASRC-BE"`。先 memcpy 进 priv，后面再按 codec 微调。

接着 `kcalloc` 10 个 `snd_soc_dai_link_component`（`dlc`，`:713`），给三条 link 的 cpus/codecs/platforms 填指针。这部分是机械的内存布局，知道「dai_link[0] 用 dlc[0/1/3]」即可，不用抠。

### 第 3 步：WM8960 专属 if 分支 —— 通用 machine 的差异化点

这是整颗驱动最精彩的地方：probe 用一个超长 `if-else if` 链（`:746-845`），按设备树 `compatible` 走不同分支，给每种 codec 配它的专属参数。alpha 板命中 WM8960 这条：

```c
/* fsl-asoc-card.c:782 —— WM8960 专属分支 */
} else if (of_device_is_compatible(np, "fsl,imx-audio-wm8960")) {
    codec_dai_name[0] = "wm8960-hifi";                    /* ① codec DAI 名 */
    priv->codec_priv[0].fll_id = WM8960_SYSCLK_AUTO;      /* ② sysclk 模式自动 */
    priv->codec_priv[0].pll_id = WM8960_SYSCLK_AUTO;
    priv->dai_fmt |= SND_SOC_DAIFMT_CBP_CFP;              /* ③ codec 当时钟主 */
```

就这三件事，定义了 alpha 板这张 WM8960 声卡的灵魂：

1. **codec DAI 名 `"wm8960-hifi"`**：`wm8960.c` 注册自己的 DAI 时就叫这个名字。machine 填进 dai_link，内核才能按名匹配到 codec 驱动。换颗 codec（WM8962 是 `"wm8962"`、SGTL5000 是 `"sgtl5000"`），改的就是这一行。
2. **`fll_id/pll_id = WM8960_SYSCLK_AUTO`**：告诉 codec 驱动「sysclk 模式自动选」——MCLK 够用就直驱、不够才启内部 PLL。alpha 板 MCLK 12.288MHz 够 48kHz 用，走直驱、不启 PLL（[04 节](04_codec_and_clock.md) 详讲）。
3. **`dai_fmt |= CBP_CFP`**：[02 节](02_asoc_framework.md) 讲过——codec 产生 BCLK/LRCLK（主），SAI2 跟着（从）。叠加 `DAI_FMT_BASE`，完整 fmt = `I2S | NB_NF | CBP_CFP`。

::: tip 一个 machine 通吃 14 种 codec 的秘密
对比旁边 wm8962（`:776`）、cs427x（`:756`）、sgtl5000（`:760`）的分支，结构完全一样——只是 `codec_dai_name`、`fll_id/pll_id`、`dai_fmt` 主从位不同。**差异点全收敛在这几行**，其余 probe 逻辑（搭 dai_link、注册 card）对所有 codec 通用。这就是「通用 machine 驱动」的设计：把 per-codec 差异塞进一张 switch 表，公共流程复用。
:::

### 第 4 步：CPU 是 SAI 时的 sysclk 处理

```c
/* :921 */ } else if (of_node_name_eq(cpu_np, "sai")) {
    priv->cpu_priv.sysclk_id[1] = FSL_SAI_CLK_MAST1;   /* SAI 内部主时钟1 */
    priv->cpu_priv.sysclk_id[0] = FSL_SAI_CLK_MAST1;
}
```

machine 还按 cpu 节点名（esai/sai/spdif）给 cpu_dai 选 sysclk 源。alpha 板是 SAI2，走这条——`FSL_SAI_CLK_MAST1` 是 SAI 自己的主时钟分支。这个细节 `fsl_sai.c` 内部用，machine 只是替它选好。

### 第 5 步：组装 card 名 + 解析 audio-routing

```c
/* :926 —— 初始化 card */
priv->card.dev = &pdev->dev;
priv->card.owner = THIS_MODULE;
snd_soc_of_parse_card_name(&priv->card, "model");   /* "wm8960-audio" */
priv->card.dai_link = priv->dai_link;
priv->card.late_probe = fsl_asoc_card_late_probe;
priv->card.dapm_widgets = fsl_asoc_card_dapm_widgets;

/* :944 —— 解析 audio-routing（那 12 条耳机/喇叭/麦克风连线） */
if (of_property_present(np, "audio-routing"))
    snd_soc_of_parse_audio_routing(&priv->card, "audio-routing");
```

`model` 属性 → card 名（`"wm8960-audio"`，`/proc/asound/cards` 里看到的就是它）。`audio-routing` 解析进 `card.dapm_routes`，这些就是 [02 节](02_asoc_framework.md) DAPM 那张有向图的边。

### 第 6 步：填 dai_link[0] 三要素 + 注册 card

终于到了「缝」的一步。dai_link[0]（HiFi）的 cpu/codec/platform 三个槽，这里把第 1 步解析到的节点填进去：

```c
/* fsl-asoc-card.c:953 —— Normal DAI Link（HiFi） */
priv->dai_link[0].cpus->of_node = cpu_np;                  /* cpu_dai = SAI2 */
for_each_link_codecs((&(priv->dai_link[0])), codec_idx, codec_comp) {
    codec_comp->dai_name = codec_dai_name[codec_idx];      /* "wm8960-hifi" */
}
for_each_link_codecs((&(priv->dai_link[0])), codec_idx, codec_comp) {
    codec_comp->of_node = codec_np[codec_idx];             /* wm8960@1a */
}
priv->dai_link[0].platforms->of_node = cpu_np;             /* DMA 走 SAI2 */
priv->dai_link[0].dai_fmt = priv->dai_fmt;                 /* I2S|NB_NF|CBP_CFP */
priv->card.num_links = 1;                                   /* 暂时只 1 条 */
```

看，[02 节](02_asoc_framework.md) 那张「dai_link 契约」的 cpu/codec/platform/of_node/dai_name/dai_fmt，全在这几行填实。填完，probe 末尾一行把 card 注册进 ASoC 核心：

```c
/* :1034 */ ret = devm_snd_soc_register_card(&pdev->dev, &priv->card);
```

这一行执行完，内核就按 dai_link 的名字去找 SAI2 的 `snd_soc_dai`、WM8960 的 `snd_soc_dai`，把俩绑成一个 `snd_soc_pcm_runtime`，在 `/dev/snd/` 下生出 `controlC0`/`pcmC0D0p`/`pcmC0D0c`——声卡正式上线。

### （可选）第 7 步：ASRC —— 额外的两条 dai_link

```c
/* :990 */ if (asrc_pdev) {
    /* DPCM DAI Links only if ASRC exists */
    priv->dai_link[1].cpus->of_node = asrc_np;     /* FE: 用户态 PCM → ASRC */
    priv->dai_link[2].cpus->of_node = cpu_np;       /* BE: ASRC → SAI2 */
    priv->card.num_links = 3;
    ...
}
```

alpha 板设备树有 `audio-asrc = <&asrc>`，所以会搭这两条。**ASRC（异步采样率转换）** 是个进阶特性：它让你能用一个采样率播放另一个采样率录的音频、或把不同来源的流混到统一采样率。`dai_link[1/2]` 用 DPCM（Dynamic PCM）把 ASRC 插在用户态和 SAI2 之间。

但**即使去掉 `audio-asrc` 这行，alpha 板照样出声**（`num_links` 退回 1，走纯 HiFi 链路）。初学可以先把 `audio-asrc` 注释掉、`num_links=1`，链路最简、好理解。本教程的上板验证（[06 节](06_build_and_test.md)）默认带 ASRC，但出声只依赖 `dai_link[0]`。

## late_probe：runtime 设 codec sysclk

`devm_snd_soc_register_card` 时 card 还没真正「通电」；等用户态第一次 `open("/dev/snd/pcmC0D0p")`，ASoC 核心才调 `late_probe`（`:569`），这里给 codec 设 sysclk：

```c
/* :600 —— late_probe 里：把 MCLK 频率告诉 codec，选好 sysclk 源 */
ret = snd_soc_dai_set_sysclk(codec_dai, codec_priv->mclk_id,
                             codec_priv->mclk_freq,   /* 12288000 */
                             SND_SOC_CLOCK_IN);
if (!IS_ERR_OR_NULL(codec_priv->mclk))
    clk_prepare_enable(codec_priv->mclk);            /* 真正使能 MCLK */
```

第 1 步只**读**了 MCLK 频率，这里才**使能**它（`clk_prepare_enable`），并通知 codec「用这个频率当 sysclk」。WM8960 收到后会按 `SYSCLK_AUTO` 决定直驱还是启 PLL（[04 节](04_codec_and_clock.md) 拆）。

## hp-det：耳机检测（可选）

设备树有 `hp-det-gpio = <&gpio5 4 0>`，probe 末尾（`:1048`）解析它，注册成耳机插拔的 jack 检测——插耳机自动切到耳机输出、拔了切回喇叭。这是个体验优化，不影响出声，[05 节](05_device_tree.md) 提一下。

## HiFi dai_link 拓扑图

把这一节拆的全画出来，alpha 板的 HiFi（`dai_link[0]`）长这样：

```
           snd_soc_card "wm8960-audio"   (fsl-asoc-card.c)
                    │
                dai_link[0] "HiFi"
          ┌──────────┼──────────┐
          ▼          ▼          ▼
       cpus       codecs     platforms
       of_node    of_node    of_node
        sai2   →  wm8960@1a  → sai2(DMA)
                  dai_name:
                  "wm8960-hifi"

         dai_fmt = I2S | NB_NF | CBP_CFP
         (codec 产生 BCLK/LRCLK，MCLK 由 SAI2 给)
```

一行 `devm_snd_soc_register_card`，这张图就活了。

## 小结

这一节我们把 `fsl-asoc-card.c` 从骨架拆到了注册 card：它是 `platform_driver`，一张 14 compatible 表通吃 14 种 codec；probe 解析 `audio-cpu/audio-codec/audio-asrc` 三个 phandle + MCLK 频率，在 WM8960 分支（`:782`）填下 `codec_dai_name="wm8960-hifi"`、`SYSCLK_AUTO`、`CBP_CFP` 三件套，把 `dai_link[0]` 的 cpu/codec/platform 三个 of_node 填实，最后一行 `devm_snd_soc_register_card`（`:1034`）上线声卡。ASRC 那两条 DPCM link 是可选增强。下一节 [04 节](04_codec_and_clock.md) 拆另一头——codec 驱动 `wm8960.c` 怎么初始化 WM8960、DAPM 路径怎么搭、以及 MCLK 时钟路由的细节。

---

<ChapterNav variant="sub">
  <ChapterLink href="02_asoc_framework.md" variant="sub">← ASoC 子系统与四件套</ChapterLink>
  <ChapterLink href="04_codec_and_clock.md" variant="sub">wm8960 codec 与时钟路由 →</ChapterLink>
</ChapterNav>
