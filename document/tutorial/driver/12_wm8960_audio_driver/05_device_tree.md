---
title: 设备树配置
---

# 设备树配置 —— sound-wm8960 / codec / sai2 节点逐行解读

前面三节我们拆了 machine（`fsl-asoc-card.c`）和 codec（`wm8960.c`）驱动。这一节把这一切**落回设备树**——看看 alpha 板上那几个节点，是怎么把前面讲的 `audio-cpu`/`audio-codec`/`audio-asrc`/MCLK/audio-routing 这些概念，用 DTS 语法描述出来的。

::: tip 学习目标
逐行读懂 `sound-wm8960`（machine）、`codec: wm8960@1a`（codec）、`&sai2`（cpu_dai + MCLK 时钟源）、`pinctrl_sai2`（JTAG→SAI2 引脚复用）四个节点；理清 `audio-routing` 那 12 条连线对应 [04 节](04_codec_and_clock.md) 哪些 DAPM widget；知道 alpha 板这些节点都在共享 `imx6ull-aes.dtsi` 里、本章分析型只解读不新增，板级改动看章节级 dts。
:::

## 先说清楚：这些节点 alpha 板早配好了

和 [RTC 章](../10_rtc_snvs_driver/) 的 `snvs-rtc-lp` 一样，alpha 板的整条音频链路**硬件描述早就在共享 `imx6ull-aes.dtsi` 里配齐了**——`sound-wm8960`、`codec`、`&sai2`、`pinctrl_sai2` 四块。本章是分析型、复用主线驱动，**不用新增任何硬件配置**，这一节纯解读。

::: warning 别去改共享 dtsi
按项目规范，共享 `imx6ull-aes.dtsi` 的改动会**被回退**（它是 alpha 板的基础配置，多章节共用）。板级音频改动要进每章自己的 `.dts`——本章的章节级 dts 在 `driver/device_tree/alpha-board/24_tutorial_wm8960_audio/`，见本节末尾。
:::

## 一、sound-wm8960（machine 节点）

这是 `fsl-asoc-card.c` 的入口节点（[03 节](03_machine_driver_analysis.md) probe 解析的就是它）：

```dts
/* imx6ull-aes.dtsi:104 —— machine 节点 */
sound-wm8960 {
    compatible = "fsl,imx-audio-wm8960";   /* ← 命中 fsl-asoc-card 的 dt_ids */
    model = "wm8960-audio";                 /* ← card 名，/proc/asound/cards 里看到它 */

    audio-cpu = <&sai2>;                    /* cpu_dai：SAI2 */
    audio-codec = <&codec>;                 /* codec：下面那个 wm8960@1a */
    audio-asrc = <&asrc>;                   /* 可选：ASRC（注释掉也能出声） */

    hp-det-gpio = <&gpio5 4 0>;             /* 耳机检测引脚 GPIO5_IO04 */

    audio-routing =                         /* 12 条模拟通路连线，见下 */
        "Headphone Jack", "HP_L",
        "Headphone Jack", "HP_R",
        "Ext Spk", "SPK_LP",
        "Ext Spk", "SPK_LN",
        "Ext Spk", "SPK_RP",
        "Ext Spk", "SPK_RN",
        "LINPUT2", "Mic Jack",
        "LINPUT3", "Mic Jack",
        "RINPUT1", "AMIC",
        "RINPUT2", "AMIC",
        "Mic Jack", "MICB",
        "AMIC", "MICB";
};
```

逐属性对应 [03 节](03_machine_driver_analysis.md)：

| 属性 | 对应 probe 里的 | 含义 |
|------|---------------|------|
| `compatible` | `of_device_id` 表 | 选中 `fsl-asoc-card`，走 WM8960 分支（`:782`） |
| `model` | `snd_soc_of_parse_card_name`（`:929`） | card 名，`cat /proc/asound/cards` 第一列 |
| `audio-cpu` | `of_parse_phandle(np,"audio-cpu",0)`（`:640`） | cpu_dai 节点 → SAI2 |
| `audio-codec` | `of_parse_phandle(np,"audio-codec",0)`（`:659`） | codec 节点 → wm8960@1a |
| `audio-asrc` | `of_parse_phandle(np,"audio-asrc",0)`（`:682`） | 可选 ASRC，去掉则 `num_links=1` |
| `hp-det-gpio` | `:1048` 的 jack 检测 | 插拔耳机自动切换输出 |

### audio-routing 那 12 条线

格式是成对的 `"sink", "source"`，表示「音频从 source 流向 sink」。对应 [04 节](04_codec_and_clock.md) 的 DAPM widget：

- **耳机**（`"Headphone Jack" ← "HP_L/HP_R"`）：WM8960 的耳机输出脚 `HP_L/HP_R` 接到板上的耳机座。两条（左右声道）。
- **喇叭**（`"Ext Spk" ← "SPK_LP/SPK_LN/SPK_RP/SPK_RN"`）：外部喇叭走 **BTL 桥接**，每声道一正一负成对，所以 4 条线（左正/左负/右正/右负）。
- **麦克风**（`"LINPUT2/3" ← "Mic Jack"`、`"RINPUT1/2" ← "AMIC"`）：板上有两个麦——`Mic Jack`（3.5mm 麦克风孔）接到左声道输入 `LINPUT2/3`，`AMIC`（板载驻极体麦）接到右声道输入 `RINPUT1/2`。
- **麦克风偏置**（`"Mic Jack/AMIC" ← "MICB"`）：两个麦都从 WM8960 的 `MICB`（MICBIAS）取偏置电压，否则驻极体麦不工作。

这 12 条线在 `:944` 被 `snd_soc_of_parse_audio_routing` 解析进 `card.dapm_routes`，就成了 [04 节](04_codec_and_clock.md) DAPM 那张图的边。

::: tip audio-routing 和 DAPM widget 的对应
`audio-routing` 里的 `HP_L`、`SPK_LP`、`LINPUT2`、`MICB` 这些名字，**必须和 `wm8960.c` widget 表里的名字一字不差**（`SND_SOC_DAPM_OUTPUT("HP_L")` 等）。写错一个字母，DAPM 路径就连不上、那路模拟通道就哑。这是设备树和 codec 驱动之间最硬的契约。
:::

## 二、codec: wm8960@1a（codec 节点）

::: warning 踩坑：WM8960 实测在 I2C1，不是原版资料的 I2C2
正点原子原版 patch（`patches/linux-imx`）、linux-imx BSP `imx6ull-aes.dtsi`、以及本教程早期版本**都把 `codec` 节点挂在 `&i2c2`**——但 alpha 板实测 WM8960 **接在 I2C1 @0x1a**：`i2cdetect -y 0`（I2C1）命中 `0x1a`(WM8960) + `0x1e`(AP3216C)，而 `i2cdetect -y 1`（I2C2）只有 `0x5d`(goodix)。

挂 I2C2 时 codec probe 第一步 `wm8960_reset`（I2C 写 0x1a）就 NACK，dmesg 报 `wm8960 1-001a: Failed to issue reset` → `fsl-asoc-card: snd_soc_register_card failed` → `/proc/asound/cards` 只剩 `ASRC-M2M` 没声卡。把 `codec` 挪到 `&i2c1` 立刻就好（实测 `card 1: wm8960audio` 上线、`/dev/snd/pcmC1D0p` 出现）。

**看到 `Failed to issue reset` 别急着查供电/焊接**，先 `i2cdetect -y 0` 和 `-y 1` 看 `0x1a` 到底在哪条总线。本项目共享 `imx6ull-aes.dtsi` 已修正：codec 在 `&i2c1`。
:::

挂在 I2C1 下的 codec 节点（`wm8960.c` 的 `i2c_probe` 解析的就是它）：

```dts
/* imx6ull-aes.dtsi —— codec 节点，挂在 &i2c1 下（实测 I2C1，非原版资料的 I2C2）*/
codec: wm8960@1a {
    #sound-dai-cells = <0>;
    compatible = "wlf,wm8960";              /* ← 命中 wm8960.c 的 of_match */
    reg = <0x1a>;                           /* I2C1 上的 7 位从机地址 */

    wlf,shared-lrclk;                       /* LRCM：左右声道 LRCLK 共享 */
    wlf,hp-cfg = <3 2 3>;                   /* 耳机检测 3 参数 */
    wlf,gpio-cfg = <1 3>;                   /* GPIO 配置 2 参数 */

    clocks = <&clks IMX6UL_CLK_SAI2>;       /* MCLK 取自 SAI2 时钟 */
    clock-names = "mclk";                   /* ← wm8960 devm_clk_get("mclk") 找它 */
};
```

逐属性对应 [04 节](04_codec_and_clock.md) `i2c_probe`：

| 属性 | 对应 probe 里的 | 含义 |
|------|---------------|------|
| `compatible "wlf,wm8960"` | `of_device_id` 表 | 选中 `wm8960.c` 驱动 |
| `reg <0x1a>` | `i2c_client->addr` | I2C1 总线上的从机地址（0x1a = 26） |
| `wlf,shared-lrclk` | `:1496` 设 LRCM 位 | 左右声道 LRCLK 共享一个引脚 |
| `wlf,hp-cfg = <3 2 3>` | `:1525` 写 ADDCTL4/2/1 | 耳机检测的 3 个寄存器配置参数 |
| `wlf,gpio-cfg = <1 3>` | `:1519` 写 IFACE2/ADDCTL4 | WM8960 GPIO 引脚功能配置 |
| `clocks` + `clock-names "mclk"` | `:1441` `devm_clk_get("mclk")` | MCLK 时钟源 = SAI2（12.288MHz） |

`#sound-dai-cells = <0>` 表示这个 codec 节点作为 DAI 引用时不需要额外的 cell（单 DAI codec 都是这样）。`clock-names` 必须是 `"mclk"`——和 `wm8960.c:1441` 的 `devm_clk_get(&i2c->dev, "mclk")` 字符串一致，codec 才能拿到 MCLK。

## 三、&sai2（cpu_dai + MCLK 时钟源）

SAI2 节点是 cpu_dai 这端，同时是 MCLK 的「发源地」（[04 节](04_codec_and_clock.md) 时钟树的出口）：

```dts
/* imx6ull-aes.dtsi:372 —— cpu_dai 节点 + MCLK 时钟配置 */
&sai2 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_sai2>;            /* 引脚配置，见下一节 */

    assigned-clocks = <&clks IMX6UL_CLK_SAI2_SEL>, <&clks IMX6UL_CLK_SAI2>;
    assigned-clock-parents = <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;   /* SAI2_SEL ← PLL4_AUDIO_DIV */
    assigned-clock-rates = <0>, <12288000>;   /* SAI2 ← 12.288 MHz（48k×256） */

    fsl,sai-mclk-direction-output;           /* MCLK 从 SAI2_MCLK 引脚输出给 codec */
    status = "okay";
};
```

这三行 `assigned-*` 就是 [04 节](04_codec_and_clock.md) 那张时钟树的设备树写法：

- `assigned-clock-parents`：SAI2_SEL 的父时钟选 `PLL4_AUDIO_DIV`（786.432MHz）。
- `assigned-clock-rates = <0>, <12288000>`：第一个 0 表示 SAI2_SEL 不设速率（继承父），第二个 `12288000` 把 SAI2_ROOT 设成 12.288MHz（=786.432MHz / 64）。
- `fsl,sai-mclk-direction-output`：让 SAI2 把这个 12.288MHz 从 `SAI2_MCLK` 引脚送出去，物理上接到 WM8960 的 MCLK 脚。

`status = "okay"` 启用 SAI2（`imx6ul.dtsi` 里默认 `disabled`）。这一段是 alpha 板音频时钟链的核心，配错一个数字（比如 `12288000` 写成 `1228800`）就全哑。

## 四、pinctrl_sai2（JTAG 引脚复用）

最后是引脚配置——[01 节](01_introduction.md) 说过 SAI2 复用了 JTAG 那组脚，这里看实物：

```dts
/* imx6ull-aes.dtsi:616 —— SAI2 引脚：5 根信号 + 1 根耳机检测 */
pinctrl_sai2: sai2grp {
    fsl,pins = <
        MX6UL_PAD_JTAG_TDI__SAI2_TX_BCLK     0x17088   /* 位时钟（codec 出） */
        MX6UL_PAD_JTAG_TDO__SAI2_TX_SYNC     0x17088   /* 帧时钟/LRCLK（codec 出） */
        MX6UL_PAD_JTAG_TRST_B__SAI2_TX_DATA  0x11088   /* 播放数据（CPU→codec） */
        MX6UL_PAD_JTAG_TCK__SAI2_RX_DATA     0x11088   /* 录音数据（codec→CPU） */
        MX6UL_PAD_JTAG_TMS__SAI2_MCLK        0x17088   /* 主时钟（CPU→codec） */
        MX6UL_PAD_SNVS_TAMPER4__GPIO5_IO04   0x17059   /* 耳机检测，普通 GPIO */
    >;
};
```

`MX6UL_PAD_JTAG_TDI__SAI2_TX_BCLK` 这种宏名一眼能看出来：「JTAG 的 TDI 脚，复用成 SAI2 的 TX_BCLK 功能」。五个 JTAG 脚（TDI/TDO/TRST/TCK/TMS）正好变成 SAI2 的五根信号线，外加一个 SNVS 域的 GPIO 当耳机检测。

::: details 那个 0x17088 / 0x11088 是什么？
是 i.MX IOMUX 控制寄存器的配置值，编码了引脚的驱动强度（DSE）、压摆率（SRE）、上下拉（PUS/PUE/PKE）、复用模式（MUX_MODE）等。`0x17088` 和 `0x11088` 的差异主要在上下拉/输入输出方向相关位——TX_BCLK/TX_SYNC/MCLK 是 codec 驱动的输入脚（SAI2 接收），TX_DATA/RX_DATA 是数据脚，配置略有不同。细节属于 pinctrl 子系统（[02_pinctrl_gpio](../02_pinctrl_gpio/) 章），这里知道「每根脚的电气属性都由这个值决定」即可。
:::

## 五、本章的章节级 dts

按项目规范，每章在 `driver/device_tree/alpha-board/<NN>_tutorial_<topic>/` 下有自己的章节级 dts。本章是 `24_tutorial_wm8960_audio/imx6ull-aes-24_tutorial_wm8960_audio.dts`：

```dts
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"          /* ← 音频链路全在这里 */

/ {
    model = "Awesome Embedded Studio IMX6ULL Tutorial 24 - WM8960 Audio";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
};

/* 板级一行硬件配置都不用加：sound-wm8960 / codec / sai2 全在 aes.dtsi 默认启用。
 * 下面 &sai2 显式标 okay 只是风格统一，写不写都 probe。
 * 想做对比实验：改成 status = "disabled"，复现 "no soundcards found"。 */
&sai2 {
    status = "okay";
};
```

和 [RTC 章](../10_rtc_snvs_driver/) 的章节级 dts 同一个套路：分析型章节因为硬件配置已在共享 dtsi，板级 dts 只做 `#include` + 显式确认，留个口子给你改 `disabled` 做对比实验。比如把 `&sai2` 改成 `disabled`，`fsl-asoc-card` 找不到 cpu_dai、`devm_snd_soc_register_card` 失败，正好复现 [06 节](06_build_and_test.md) 要讲的「无声」现象。

## 六、确认节点生效

部署 dtb、重启板子后，几条命令确认音频链路 probe 成功：

```bash
# codec（I2C 层面）
ls /sys/bus/i2c/devices/ | grep 001a        # 0-001a 应存在（I2C1, 地址 0x1a）

# machine + codec + cpu_dai 都 probe 了？
dmesg | grep -iE "wm8960|fsl-asoc-card|sai2"
# wm8960 0-001a: ...
# fsl-asoc-card fsl-asoc-card.0: ...

# 声卡上线
cat /proc/asound/cards
#  0 [wm8960audio  ]: wm8960-audio - wm8960-audio
#                       (alpha 板的 wm8960-audio 声卡)

ls /dev/snd/                                # controlC0 pcmC0D0c pcmC0D0p timer
```

看到 `card 0 [wm8960audio]` 和 `/dev/snd/pcmC0D0p`（播放 PCM 设备），说明 [03 节](03_machine_driver_analysis.md) 的 dai_link 已经成功绑定、声卡上线了。接下来 [06 节](06_build_and_test.md) 就用 `aplay`/`amixer`/`arecord` 让它真正出声。

## 小结

这一节我们把 alpha 板音频的四个设备树节点逐行解读了：`sound-wm8960`（machine，定义 cpu/codec/asrc/routing）+ `codec: wm8960@1a`（codec，I2C 地址 + `wlf,*` 属性 + MCLK）+ `&sai2`（cpu_dai + PLL4→12.288MHz 时钟树）+ `pinctrl_sai2`（JTAG 五脚复用）。这些都在共享 `imx6ull-aes.dtsi`、默认启用，本章分析型只解读、章节级 dts 只做显式确认。下一节 [06 节](06_build_and_test.md) 是真正的「上板时刻」——修 mainline defconfig、装 alsa-utils、`aplay` 出声。

---

<ChapterNav variant="sub">
  <ChapterLink href="04_codec_and_clock.md" variant="sub">← wm8960 codec 与时钟路由</ChapterLink>
  <ChapterLink href="06_build_and_test.md" variant="sub">修 defconfig 与上板验证 →</ChapterLink>
</ChapterNav>
