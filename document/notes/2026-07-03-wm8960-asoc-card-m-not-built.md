# WM8960 主线声卡无声根因（Issue #43：ASOC_CARD=m）

> **日期**：2026-07-03
> **关联**：[Issue #43](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues/43)、[WM8960 音频驱动教程](../tutorial/driver/12_wm8960_audio_driver/)

## 现象

alpha 板跑主线内核（mainline 7.x），`fsl-asoc-card` / `wm8960` / `fsl_sai` 驱动都「开了」，但声卡整机静音：

```bash
$ aplay -l
aplay: device_list:274: no soundcards found
```

`/proc/asound/cards` 空、`/dev/snd/` 下没有设备节点。

## 排查

查内核实际配置：

```bash
$ zcat /proc/config.gz | grep -iE "FSL_ASOC_CARD|WM8960|FSL_SAI"
CONFIG_SND_SOC_FSL_SAI=y          # cpu_dai 在内核里 ✓
CONFIG_SND_SOC_WM8960=y           # codec 在内核里 ✓
CONFIG_SND_SOC_FSL_ASOC_CARD=m    # machine 驱动是模块 ← 问题在这
```

machine 驱动是 `=m`，但板子上找不到 `.ko`：

```bash
$ ls /lib/modules/$(uname -r)/kernel/sound/soc/fsl/
（空，fsl-asoc-card.ko 根本没部署）
```

## 根因

ASoC 声卡是三层结构：**machine（`fsl-asoc-card.c`）+ codec（`wm8960.c`）+ cpu_dai（`fsl_sai.c`）**。三颗都得在内核里，machine 才能把另外俩缝成一张声卡。

mainline defconfig 模板里：
- `CONFIG_SND_SOC_WM8960=y`（codec 编进内核 ✓）
- `CONFIG_SND_SOC_FSL_SAI=y`（被 ASOC_CARD select，cpu_dai 编进内核 ✓）
- `CONFIG_SND_SOC_FSL_ASOC_CARD=m`（**machine 是模块** ✗）

而 imx-forge 的内核 build 流程（`build-mainline-linux.sh`）**不带 `modules_install`**——只编 `zImage`，不把 `.ko` 部署到 rootfs 的 `/lib/modules/`。结果 machine 驱动既不在内核映像里、也没作为模块部署 → dai_link 的 cpu/codec 找不到「缝纫机」→ `devm_snd_soc_register_card` 没执行 → 声卡不存在。

> 正点原子那种「内核 + modules_install + 开机 modprobe」的发行版里，`=m` 能工作。imx-forge 走的是「尽量 `=y`、最小 rootfs」路线，所以 `=m` 就等于「没有」。

## 修复

把 machine 驱动也改成编进内核。`driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template`：

```diff
  # --- Sound ---
- CONFIG_SND_SOC_FSL_ASOC_CARD=m
+ # fsl-asoc-card（WM8960 等 machine 驱动）：必须 =y。见本笔记（Issue #43）
+ # 项目的内核 build 流程不带 modules_install，=m 会让声卡整机静音。
+ CONFIG_SND_SOC_FSL_ASOC_CARD=y
```

linux-imx 线的 `imx_aes_defconfig.template` 本来就是 `=y`，不受影响。

## 顺带：弃用 imx-wm8960.c

正点原子教程（草稿 ch65）走的是「自己写 `imx-wm8960.c` 当 machine 驱动」。本仓库明确**不移植 `imx-wm8960.c`**，直接复用主线 `fsl-asoc-card`（`compatible = "fsl,imx-audio-wm8960"` 命中其 WM8960 分支）。理由：`fsl-asoc-card` 一个 machine 驱动通吃 WM8960/WM8962/SGTL5000/CS42XX8 等 14 种 codec，社区维护、还带 ASRC；自写 `imx-wm8960.c` 只认 WM8960 一颗，重复造轮子。

## 验证

改 `=y` 重编内核、重部署：

```bash
$ zcat /proc/config.gz | grep FSL_ASOC_CARD
CONFIG_SND_SOC_FSL_ASOC_CARD=y

$ cat /proc/asound/cards
  0 [wm8960audio]: wm8960-audio - wm8960-audio

$ aplay -l   # 列出 card 0 ✓
```

声卡上线。再 `amixer` 把 WM8960 默认静音拧开（见教程 [06_build_and_test](../tutorial/driver/12_wm8960_audio_driver/06_build_and_test.md)），`aplay` 出声。

## SDMA 也已 =y（2026-07-03「默认全」任务修）

`ASOC_CARD` 是 Issue #43 主因，但 alpha 板 SAI2 走 **SDMA** 搬运音频数据，`CONFIG_IMX_SDMA=m`（注释「fixes firmware loading issues」）同样让 `imx-pcm-dma` 不进 rootfs、`fsl_sai` 拿不到 DMA channel。

**2026-07-03 已修**：「让默认 build 驱动全」任务把 `IMX_SDMA` 也改 `=y`，在子模块 defconfig + patch + 项目副本三处同步（见记忆 `device-tree-workflow` 修正后的「三同步」真相）。固件 6ULL 用 `sdma-imx6q.bin`（`sdma_imx6ul` 复用 imx6q 脚本、MODULE_FIRMWARE 只声明 imx6q.bin），`install_firmwares.sh` 已装，SDMA=y 后固件就绪。

至此 Issue #43 的 ASOC_CARD + SDMA 双修复都真正进 build（之前 wm8960 那次只改项目副本 ASOC_CARD、没进 patch/子模块、实际没生效；本次一并修正，三同步）。

## 教训

- **`=m` 不等于「开了」**。在「不 modules_install」的 build 流程里，`=m` = 缺失。音频/显示/网络这类「必须三方缝合才出活」的子系统，machine 层一定要 `=y`。
- ASoC 三层缺一不可，缺中间 machine 层的症状最迷惑（codec、cpu_dai 都「在线」但没声卡）。
- 排查「no soundcards」先 `zcat /proc/config.gz | grep ASOC_CARD` 看 machine 驱动是不是 `=y`。
