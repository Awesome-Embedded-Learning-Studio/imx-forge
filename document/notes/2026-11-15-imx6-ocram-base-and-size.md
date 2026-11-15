---
title: i.MX6 OCRAM 基址与大小速查
description: "OCRAM(IRAM)基址 0x00900000 与按芯片分档的大小定义,出处直接取自 U-Boot 树头文件"
---

# i.MX6 OCRAM 基址与大小速查

OCRAM（On-Chip RAM，U-Boot 头文件里叫 IRAM）是 i.MX6 芯片内部的一块通用
SRAM。芯片上电后 Boot ROM 把 SPL 加载进 OCRAM 里执行，SPL 在这里面完成
DDR 初始化，才轮得到 SDRAM 上场。所以算 SPL 的栈、算早期的加载地址，都绕
不开这块内存的基址和大小。

这两个值不用背，U-Boot 树里一个头文件全写清楚了，本文把出处卡在下面，
以后查的时候从这一页跳过去就行。

## 基址：全系同一个值

`IRAM_BASE_ADDR` 定义在 `arch/arm/include/asm/arch-mx6/imx-regs.h`。
它不在按芯片分家的 `#if` 分支里，i.MX6 全系都是 `0x00900000`；上面那组
GPV、PCIe 的基址才是每个芯片各一套。

::: code-loc uboot-mainline arch/arm/include/asm/arch-mx6/imx-regs.h:67
```c
#define PCIE_ARB_END_ADDR               0x01FFFFFF
#endif

#define IRAM_BASE_ADDR			0x00900000
#define SCU_BASE_ADDR                   0x00A00000
#define IC_INTERFACES_BASE_ADDR         0x00A00100
#define GLOBAL_TIMER_BASE_ADDR          0x00A00200
```
:::

## 大小：按芯片分两档

大小定义在同一个文件更靠下的 `IRAM_SIZE`，这里反而带了一个按芯片分的
判断：6Q、6D 这类大块头是 256 KiB，SX、UL、ULL、SL、SLL 这几个小封装是
128 KiB。本项目的 6ULL 落在 `#else` 分支，是 128 KiB 那档。

::: code-loc uboot-mainline arch/arm/include/asm/arch-mx6/imx-regs.h:370
```c
#if !(defined(CONFIG_MX6SX) || \
	defined(CONFIG_MX6UL) || defined(CONFIG_MX6ULL) || \
	defined(CONFIG_MX6SLL) || defined(CONFIG_MX6SL))
#define IRAM_SIZE                    0x00040000
#else
#define IRAM_SIZE                    0x00020000
#endif
```
:::

## 出处卡是怎么写出来的

上面两张卡是站点的 `CodeLoc` 组件，由 `::: code-loc 容器` 生成。写法：
第一个空格前是项目名（徽章文案），其余是文件路径（相对该子模块根，可带
`:行号`），中间照常写围栏，容器收尾用单独一行 `:::`。

````md
::: code-loc uboot-mainline arch/arm/include/asm/arch-mx6/imx-regs.h:67
```c
#define IRAM_BASE_ADDR			0x00900000
```
:::
````

容器里的围栏走原生渲染链：高亮、复制按钮、行号、`{行号}` 高亮标记全都
保留，超长代码也会照常被折叠。头带里的路径整段可点，点一下复制到剪贴板。

## 一句话总结

| 项目 | 值 | 出处 |
| --- | --- | --- |
| OCRAM 基址 | `0x00900000` | `imx-regs.h:67`，全系通用 |
| OCRAM 大小（6Q/6D） | 256 KiB（`0x40000`） | `imx-regs.h:373` |
| OCRAM 大小（6ULL 等） | 128 KiB（`0x20000`） | `imx-regs.h:375` |

以此类推需要更多细节时，直接打开
`third_party/uboot-mainline/arch/arm/include/asm/arch-mx6/imx-regs.h`，
同一块内存区域的外设基址（SCU、GIC、L2PL310）就排在 IRAM 后面那几行。
