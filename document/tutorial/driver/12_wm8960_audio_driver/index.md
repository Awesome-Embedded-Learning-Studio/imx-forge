---
title: WM8960 音频驱动教程
---

<PageHeader icon="🔊" title="WM8960 音频驱动" description="拆主线 ASoC 三件套——fsl-asoc-card.c（machine）+ wm8960.c（codec）+ fsl_sai.c（cpu_dai）：从 Card/dai_link 的缝合、DAPM 按需上电、MCLK 12.288MHz 时钟路由，到 mainline 那个 ASOC_CARD=m 的无声大坑（Issue #43），最后在 alpha 板上 aplay 出声、arecord 录音回放" />

## 版本说明

本教程基于以下内核版本：

- **mainline** 7.1.0 <Badge type="tip" text="主轴" /> —— alpha 板日常跑的就是这条线
- **linux-imx** 6.12.49 <Badge type="info" text="对照" />

::: warning 和前两章反过来：这里 mainline 是主轴
[RTC](../10_rtc_snvs_driver/)、[goodix](../11_goodix_touchscreen_driver/) 两章我们都把 linux-imx 标成「推荐」、mainline 标「进阶」，因为那俩外设两条线都开箱即用。音频这章反过来：**alpha 板现在跑的是 mainline 7.x**，所以正文以 mainline 为主线（所有行号、配置、踩坑都对着 mainline 讲），linux-imx 退到对照位置。两颗驱动两边都有、代码几乎一样，差异主要在 defconfig 默认值（见下）。
:::

源码就躺在仓库的 `third_party/linux_mainline` 与 `third_party/linux-imx` 下，涉及三个文件：

- `sound/soc/fsl/fsl-asoc-card.c` —— **machine 驱动**（把 codec 和 cpu_dai 缝成一张声卡）
- `sound/soc/codecs/wm8960.c` —— **codec 驱动**（WM8960 这颗音频芯片的寄存器/DAPM）
- `sound/soc/fsl/fsl_sai.c` —— **cpu_dai 驱动**（i.MX6ULL 这端的 SAI2 数字音频接口）

::: tip 一个要提前知道的坑：mainline 默认不出声
linux-imx 线的 defconfig 把 `CONFIG_SND_SOC_FSL_ASOC_CARD=y`，开箱即用；mainline 线的模板却是 `=m`，而项目的内核 build 流程不带 `modules_install`，结果 `.ko` 根本没编出来 → 声卡整机静音、`aplay: no soundcards found`。这就是 [Issue #43](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/43)。修复一行：`defconfig` 里改 `=y`，[06 节](06_build_and_test.md) 会边修边讲根因，顺手把它变成这章最生动的教材。
:::

## 这一篇要解决什么问题

和 [RTC](../10_rtc_snvs_driver/)、[goodix](../11_goodix_touchscreen_driver/) 一样，音频这章**也不写驱动**，继续走「分析型」路线。理由照样实在：主线对 WM8960 的支持是**完整三层**——machine（`fsl-asoc-card.c`）+ codec（`wm8960.c`）+ cpu_dai（`fsl_sai.c`）——全都被无数 i.MX 板子验证过。正点原子那套自己写的 `imx-wm8960.c` machine 驱动，在主线 `fsl-asoc-card` 面前属于「重复造轮子」，我们直接复用主线。

但音频比触摸复杂一档：触摸是「一个驱动搞定一颗 IC」，音频是「**三颗驱动缝成一张声卡**」。所以这章的硬骨头是 ASoC（ALSA System on Chip）子系统那套「machine + codec + cpu_dai + platform」的四件套架构——它怎么把 i.MX6ULL 的 SAI2 接口、WM8960 这颗 codec、DMA 引擎、以及耳机/喇叭/麦克风的模拟通道，拼成 `/dev/snd/*` 里那台 `wm8960-audio` 声卡。

读懂它，你就拿下了 Linux 音频子系统这块拼图——以后遇到任何 codec（wm8962、sgtl5000、cs42xx8……）套路都一样：换颗 codec 驱动、设备树改俩节点，machine 层不用动。

## 学习路径

我们按「先理框架、再拆源码、最后上板验证」的顺序推进，和 RTC、goodix 章对称。

### 🎯 推荐学习路径

#### **阶段一：硬件与框架**

1. **[01_introduction](01_introduction.md)** - 架构概览：ASoC 四件套、alpha 板音频链路、为什么不用 `imx-wm8960.c`
2. **[02_asoc_framework](02_asoc_framework.md)** - ASoC 子系统：Card/dai_link/DAPM/platform 的缝合哲学

#### **阶段二：源码拆解**

3. **[03_machine_driver_analysis](03_machine_driver_analysis.md)** - `fsl-asoc-card.c` 逐段拆解：probe、dai_link 搭建、CARD_WM8960 分支
4. **[04_codec_and_clock](04_codec_and_clock.md)** - `wm8960.c` codec + MCLK 时钟路由 + SAI DMA

#### **阶段三：设备树与验证**

5. **[05_device_tree](05_device_tree.md)** - 设备树：sound-wm8960 / codec / sai2 节点逐行解读
6. **[06_build_and_test](06_build_and_test.md)** - 修 defconfig、装 alsa-utils、aplay 出声 + arecord 回放

## 章节目录

<ChapterNav>
  <ChapterLink num="02" href="02_asoc_framework.md">ASoC 子系统与四件套</ChapterLink>
  <ChapterLink num="03" href="03_machine_driver_analysis.md">fsl-asoc-card.c 逐段拆解</ChapterLink>
  <ChapterLink num="04" href="04_codec_and_clock.md">wm8960 codec 与时钟路由</ChapterLink>
  <ChapterLink num="05" href="05_device_tree.md">设备树配置</ChapterLink>
  <ChapterLink num="06" href="06_build_and_test.md">修 defconfig 与上板验证</ChapterLink>
</ChapterNav>

::: tip 学习目标
搞懂 Linux ASoC「machine + codec + cpu_dai + platform」四件套怎么缝成一张声卡；理解 DAPM 的「按需上电」widget/route 模型；看清 MCLK 时钟从 PLL4_AUDIO_DIV 走到 SAI2 的 12.288MHz 路由（为什么是 48k×256 免 PLL）；读懂 `fsl-asoc-card.c` 的 probe + dai_link 搭建、`wm8960.c` 的 codec 初始化与 DAPM 路径；最终在 alpha 板上修掉 mainline 的 `=m` 坑，用 `aplay` 让耳机出声、`arecord` 录音回放。
:::

::: info 前置知识
- I2C 驱动框架（[08_i2c_ap3216c_driver](../08_i2c_ap3216c_driver/)）—— WM8960 挂 I2C1 控制（实测，非原版资料的 I2C2）
- 设备树基础（[01_device_tree_base](../01_device_tree_base/)）—— sound 节点的 of 解析
- regmap（可选，`wm8960.c` 用 regmap 读写寄存器）
:::

::: details 延伸阅读
- [ALSA SoC 层文档](https://www.kernel.org/doc/html/latest/sound/soc/index.html)
- [DAPM 动态音频电源管理](https://www.kernel.org/doc/html/latest/sound/soc/dapm.html)
- 仓库源码：`third_party/linux_mainline/sound/soc/fsl/fsl-asoc-card.c`、`sound/soc/codecs/wm8960.c`、`sound/soc/fsl/fsl_sai.c`
:::

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../11_goodix_touchscreen_driver/" variant="sub">← 电容触摸驱动（goodix）</ChapterLink>
  <ChapterLink href="../modules/" variant="sub">模块开发 →</ChapterLink>
</ChapterNav>
