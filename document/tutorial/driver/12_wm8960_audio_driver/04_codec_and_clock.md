---
title: wm8960 codec 与时钟路由
---

# wm8960 codec 与时钟路由 —— 寄存器、DAPM 与 MCLK

[03 节](03_machine_driver_analysis.md) 拆了 machine 驱动怎么「缝」，这一节拆被缝的另一头：codec 驱动 `sound/soc/codecs/wm8960.c`（mainline 7.1，1591 行）。它管 WM8960 这颗芯片的一切——寄存器读写、音频通路（DAPM）、上电序列、时钟分频。再带上 alpha 板那条 **MCLK 时钟路由**：PLL4 → SAI2 → WM8960，为什么是 12.288MHz、为什么免 PLL。

::: tip 学习目标
看懂 `wm8960.c` 的 `i2c_driver` 骨架与「反向存在性探测」；跟着 `wm8960_i2c_probe`（`:1428`）走完 取 MCLK → regmap → 复位 → 设备树属性落寄存器 → 注册 component 的流程；理清 DAPM widget 表怎么构成耳机/喇叭/麦克风三条通路；画出 PLL4_AUDIO_DIV → SAI2 → MCLK 12.288MHz 的时钟树，理解 256×FS 为什么免 PLL。
:::

## 驱动骨架：i2c_driver + wm8960_dai

WM8960 挂在 **I2C1** 上被控制（实测 `i2cdetect -y 0` 命中 0x1a；原版正点原子资料写 I2C2 是错的，见 [05 节](05_device_tree.md) 踩坑），所以 codec 驱动是 `i2c_driver`（和 [08 章](../08_i2c_ap3216c_driver/) AP3216C 一样的总线类型）。注册的「货物」有两件：一个 `snd_soc_component_driver`（codec 的寄存器/DAPM 那一面）和一个 `snd_soc_dai_driver`（codec 的数字音频接口 DAI 那一面）。

DAI 这一面（`:1354`）声明 WM8960 的能力：

```c
/* wm8960.c:1354 —— codec DAI:名字和能力 */
static struct snd_soc_dai_driver wm8960_dai = {
    .name = "wm8960-hifi",                  /* ← machine dai_link 里填的就是它 */
    .playback = {
        .stream_name = "Playback",
        .channels_min = 1, .channels_max = 2,
        .rates = WM8960_RATES,              /* SNDRV_PCM_RATE_8000_48000 */
        .formats = WM8960_FORMATS,          /* S16/S20_3/S24/S32 LE */
    },
    .capture = { /* 同 playback，录音能力 */ },
    .ops = &wm8960_dai_ops,                 /* hw_params/set_fmt/set_sysclk/... */
    .symmetric_rate = 1,                    /* 同一时刻播录必须同采样率 */
};
```

注意 `name = "wm8960-hifi"`——[03 节](03_machine_driver_analysis.md) WM8960 分支里 `codec_dai_name[0] = "wm8960-hifi"` 填的就是它，machine 靠这个名字把 dai_link 的 codec 槽对到这颗驱动。`symmetric_rate = 1` 是个有意思的约束：WM8960 一条音频总线同时跑播放和录音时，俩方向必须用同一个采样率（硬件限制）。

## i2c_probe 逐段：把 WM8960 伺候到可注册

`wm8960_i2c_probe`（`:1428`）是 codec 驱动的心脏。它从「一颗可能没上电、I2C 都没握过手的芯片」开始，注册成一个 ASoC component。分段看。

### 第 1 步：取 MCLK 频率

```c
/* wm8960.c:1441 —— 从设备树 clocks=<&clks SAI2>, clock-names="mclk" 取 MCLK */
wm8960->mclk = devm_clk_get(&i2c->dev, "mclk");
if (!IS_ERR(wm8960->mclk)) {
    ret = clk_get_rate(wm8960->mclk);
    if (ret >= 0)
        wm8960->freq_in = ret;            /* = 12288000，记下来 */
}
```

设备树 `codec` 节点里 `clocks = <&clks IMX6UL_CLK_SAI2>; clock-names = "mclk";`，这里 `devm_clk_get` 取到 SAI2 的时钟（也就是 alpha 板配成 12.288MHz 那个），`freq_in` 记下频率。后面 `hw_params`/`set_sysclk` 会用它算分频——这就是 [03 节](03_machine_driver_analysis.md) machine「只读 MCLK 频率、enable 留给 codec」的下半场。

### 第 2 步：电源 + regmap

```c
/* :1458 —— 取并使能 codec 的几路电源（DBVDD/AVDD/SPKVDD/DCVDD） */
devm_regulator_bulk_get(...);
regulator_bulk_enable(...);

/* :1472 —— regmap：WM8960 寄存器是 7 位地址、9 位数据 */
wm8960->regmap = devm_regmap_init_i2c(i2c, &wm8960_regmap);
```

`regmap_config`（`:1398`）写明 WM8960 的寄存器是 **7 bit 地址、9 bit 数据**——这是 WM8960 硬件决定的。之后所有寄存器读写都走 regmap（`regmap_update_bits` 等），不用裸 `i2c_transfer`。regmap 还带寄存器缓存（`REGCACHE_MAPLE`），suspend/resume 自动恢复。

### 第 3 步：反向存在性探测（一个有意思的套路）

```c
/* wm8960.c:1483 —— 故意裸读一个字节 */
ret = i2c_master_recv(i2c, &val, sizeof(val));
if (ret >= 0) {
    dev_err(&i2c->dev, "Not wm8960, wm8960 reg can not read by i2c\n");
    ret = -EINVAL;
    goto bulk_disable;
}
```

这段反直觉：它**故意**用 `i2c_master_recv` 裸读一个字节。WM8960 的寄存器**不能**这么读——必须先写寄存器地址再读（标准 I2C 两段式，[08 章](../08_i2c_ap3216c_driver/) 讲过）。所以**正确的 WM8960 会拒绝这种读**（返回 `< 0`）。如果 `ret >= 0`（居然读到了字节），说明这颗芯片根本不是 wm8960（可能是别的能裸读的芯片挂在了同一地址），直接报错退出。

这是用「该芯片不该支持的访问方式」反过来确认芯片身份——比读 ID 寄存器还省事。值得品味。

### 第 4 步：复位 + 设备树属性落寄存器

```c
/* :1490 */ wm8960_reset(wm8960->regmap);          /* 软复位，恢复默认 */

/* :1496 —— wlf,shared-lrclk → LRCM 位（左右声道 LRCLK 共享） */
if (wm8960->pdata.shared_lrclk)
    regmap_update_bits(wm8960->regmap, WM8960_ADDCTL2, 0x4, 0x4);

/* :1518 —— wlf,gpio-cfg / wlf,hp-cfg 落到 GPIO/HPDET 配置寄存器 */
regmap_update_bits(wm8960->regmap, WM8960_IFACE2,  1 << 6, pdata.gpio_cfg[0] << 6);
...
regmap_update_bits(wm8960->regmap, WM8960_ADDCTL4, 3 << 2, pdata.hp_cfg[0] << 2);
```

设备树 `codec` 节点里的 `wlf,shared-lrclk`、`wlf,hp-cfg = <3 2 3>`、`wlf,gpio-cfg = <1 3>`，全在这里被 `wm8960_set_pdata_from_of` 读进 `pdata`，再由 `regmap_update_bits` 写进 WM8960 的对应寄存器位。**设备树属性 → pdata → 寄存器位**，这是 codec 驱动处理硬件配置的标准套路。

### 第 5 步：注册 component + dai

```c
/* :1534 —— 把 codec 注册成 ASoC component，挂上 wm8960_dai */
ret = devm_snd_soc_register_component(&i2c->dev,
        &soc_component_dev_wm8960, &wm8960_dai, 1);
```

这一行执行完，ASoC 核心里就多了一个名叫 `"wm8960-hifi"` 的 component+dai，等着 [03 节](03_machine_driver_analysis.md) machine 那张 dai_link 按名字来绑它。

## component 这一面：controls、widgets 与上电

`soc_component_dev_wm8960`（`:1389`）是 codec 的另一面（寄存器/DAPM/电源）。它的 `probe` 回调 `wm8960_probe`（`:1372`）干三件事：

```c
/* wm8960.c:1372 —— component 级 probe */
static int wm8960_probe(struct snd_soc_component *component) {
    if (pdata->capless)                                /* 选上电序列：capless vs out3 */
        wm8960->set_bias_level = wm8960_set_bias_level_capless;
    else
        wm8960->set_bias_level = wm8960_set_bias_level_out3;

    snd_soc_add_component_controls(component, wm8960_snd_controls, ...);  /* 音量/静音 kcontrol */
    wm8960_add_widgets(component);                                       /* DAPM widget + route */
}
```

- **kcontrol**：`amixer` 看到的那些音量、静音控件（如 `PCM Playback Volume`、`Headphone Playback Switch`）就是 `wm8960_snd_controls`，用户态可调。
- **widget + route**：`wm8960_add_widgets` 把下面这张 DAPM 器件表和它们的连线注册进 ASoC。
- **set_bias_level**：根据板子是不是 capless（无电容直耦）输出，选不同的上电序列。alpha 板不是 capless，走 `wm8960_set_bias_level_out3`（`:912`）。

## DAPM widget：三条音频通路

`wm8960_dapm_widgets[]`（`:362`）把 WM8960 内部所有器件都声明成 DAPM widget，每个 widget 绑一组电源寄存器位。按功能分三类：

```c
/* wm8960.c:362 —— DAPM widget 表（节选，按通路分组） */

/* —— 输入（麦克风侧）—— */
SND_SOC_DAPM_INPUT("LINPUT1"),  ... SND_SOC_DAPM_INPUT("RINPUT3"),   /* 6 路模拟输入 */
SND_SOC_DAPM_SUPPLY("MICB", WM8960_POWER1, 1, 0, NULL, 0),           /* 麦克风偏置 */
SND_SOC_DAPM_MIXER("Left Input Mixer", WM8960_POWER3, 5, 0, ...),    /* 输入混音 */
SND_SOC_DAPM_ADC("Left ADC", "Capture", WM8960_POWER1, 3, 0),        /* 模数转换 */

/* —— 核心（数字侧）—— */
SND_SOC_DAPM_DAC("Left DAC", "Playback", WM8960_POWER2, 8, 0),       /* 数模转换 */
SND_SOC_DAPM_MIXER("Left Output Mixer", WM8960_POWER3, 3, 0, ...),   /* 输出混音 */

/* —— 输出（耳机/喇叭侧）—— */
SND_SOC_DAPM_PGA("LOUT1 PGA", WM8960_POWER2, 6, 0, ...),             /* 耳机放大器 */
SND_SOC_DAPM_PGA("Left Speaker PGA", WM8960_POWER2, 4, 0, ...),      /* 喇叭放大器 */
SND_SOC_DAPM_OUTPUT("HP_L"),  SND_SOC_DAPM_OUTPUT("HP_R"),           /* 耳机输出脚 */
SND_SOC_DAPM_OUTPUT("SPK_LP"), ... SND_SOC_DAPM_OUTPUT("SPK_RN"),    /* 喇叭输出脚 */
```

每个 widget 的最后一个参数（如 `WM8960_POWER1, 3`）是「这个器件由哪个寄存器的哪一位控制电源」。DAPM 引擎在 [02 节](02_asoc_framework.md) 讲的那张有向图上做路径搜索时，只会**点亮当前通路上的 widget**（置位对应寄存器），其余保持断电。比如你只 `aplay` 播放：

```
DAC → Output Mixer → LOUT1 PGA → HP_L → Headphone Jack
   （只这一条 path 上的 widget 上电，ADC/MICB/SPK 全断电）
```

设备树 `audio-routing` 那一串（`"Headphone Jack" "HP_L"` 等）定义的是 **widget 之间的连线**（图的边），`wm8960_dapm_widgets` 定义的是**器件本身**（图的节点）。两者合起来就是完整的 DAPM 图。

::: info bias level：codec 的「睡眠等级」
除了 widget 级别的开关，codec 整体还有个 `bias_level` 状态机：`OFF → STANDBY → PREPARE → ON`。`set_bias_level`（`:1302`）负责级间切换：`OFF→STANDBY` 启 VMID（中点参考电压）、`STANDBY→ON` 把 DAC/ADC 真正唤醒。不用 `aplay` 时 codec 待在 STANDBY 省电，一开 PCM 流才升到 ON。这是 DAPM 之上更粗粒度的电源管理。
:::

## 时钟路由深挖：PLL4 → SAI2 → MCLK 12.288MHz

这是音频这章最绕也最值得搞懂的一条链。alpha 板的 MCLK 从哪来、为什么是 12.288MHz、为什么 WM8960 不用启自己的 PLL——全在这条时钟树里。

```
PLL4 (音频 PLL, ~786.432 MHz)
   │
   ▼  (assigned-clock-rates = <786432000>, imx6ull-aes.dtsi:152)
PLL4_AUDIO_DIV
   │
   ▼  (SAI2_SEL 的 parent = PLL4_AUDIO_DIV, dtsi:373 assigned-clock-parents)
SAI2_SEL
   │
   ▼  (SAI2_ROOT = PLL4_AUDIO_DIV / 64 = 12.288 MHz, dtsi:374 assigned-clock-rates=<0>,<12288000>)
SAI2_ROOT
   │
   ▼  (fsl,sai-mclk-direction-output —— SAI2 把 MCLK 从引脚送出去)
SAI2_MCLK 引脚  ────────→  WM8960 MCLK 输入（freq_in = 12288000）
```

设备树里 `&sai2` 那段（`imx6ull-aes.dtsi:372`）就是这条链的配置：

```dts
&sai2 {
    assigned-clocks = <&clks IMX6UL_CLK_SAI2_SEL>, <&clks IMX6UL_CLK_SAI2>;
    assigned-clock-parents = <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;   /* SAI2_SEL ← PLL4_AUDIO_DIV */
    assigned-clock-rates = <0>, <12288000>;                        /* SAI2 ← 12.288 MHz */
    fsl,sai-mclk-direction-output;                                 /* MCLK 从 SAI2 输出给 codec */
    status = "okay";
};
```

为什么是 **12.288MHz**？因为 **12288000 = 48000 × 256**：48kHz 采样率、256 倍过采样系数。WM8960 内部所有时钟（BCLK、LRCLK、DAC/ADC 时钟）都能从这个 MCLK 整数分频出来。

::: tip 为什么 WM8960 不用启 PLL？
WM8960 的 sysclk 有两种来源：直接用 MCLK（直驱），或先把 MCLK 进内部 PLL 倍频/分频再用。`fsl-asoc-card` 给 WM8960 设的是 `WM8960_SYSCLK_AUTO`（[03 节](03_machine_driver_analysis.md) 第 3 步）——驱动自动判断：MCLK 频率能整除目标采样率的所有需求，就**直驱**（省 PLL、jitter 更小）；否则才启 PLL。alpha 板 MCLK 12.288MHz 对 48k/44.1k/32k/... 这些常用采样率都能整除，所以走直驱。**这就是 `=m` 坑修好、MCLK 正确后音频能直出的底层原因。**
:::

## hw_params：运行时按采样率算分频

用户态 `aplay -r 44100 ...` 时，ASoC 调 `wm8960_hw_params`（`:829`），按这次流的采样率/位宽/声道，算出 BCLK 和 MCLK 分频系数，写进 WM8960 的时钟寄存器。`symmetric_rate` 约束在这里生效：如果同时播+录，俩 `hw_params` 必须采样率一致。

这部分细节（`wm8960_set_sysclk`/`set_pll`/BCLK 分频表）是 codec 驱动最数学的部分，初学知道「它按采样率算分频、写寄存器」即可，要深挖再看 `:829` 起的 `hw_params` 和 `:1212` 的 `set_pll`。

## 小结

这一节我们把 codec 那头拆透了：`wm8960.c` 是 `i2c_driver`，`i2c_probe` 取 MCLK 频率（`freq_in=12288000`）→ 建 regmap（7/9 bit）→ 用「裸读必定失败」反探芯片 → 复位 → 把设备树 `wlf,*` 属性写进寄存器 → 注册成 component；component 这一面挂上 kcontrol（音量）和 DAPM widget（按需上电的器件），bias level 状态机管粗粒度电源；时钟上，PLL4_AUDIO_DIV（786.432MHz）经 SAI2 分频成 12.288MHz MCLK 送进 WM8960，256×FS 让 codec 直驱、免启 PLL。下一节 [05 节](05_device_tree.md) 把这一切落回设备树——看 `sound-wm8960` / `codec` / `&sai2` / `pinctrl_sai2` 这几个节点怎么把上面拆的链路描述出来。

---

<ChapterNav variant="sub">
  <ChapterLink href="03_machine_driver_analysis.md" variant="sub">← fsl-asoc-card.c 逐段拆解</ChapterLink>
  <ChapterLink href="05_device_tree.md" variant="sub">设备树配置 →</ChapterLink>
</ChapterNav>
