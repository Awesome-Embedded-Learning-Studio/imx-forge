---
title: 设备树配置
---

# 设备树配置 —— snvs 与 snvs-rtc-lp

前面几节我们都在读驱动源码，这一节换到设备树这边。好消息是：**alpha 板这块，你一行设备树都不用改**。SNVS RTC 在 i.MX6UL 的基础 dtsi 里早就配好了，主线内核开机自动 probe。我们这一节的目的是看懂它配了什么、确认它生效，而不是去改它。

::: tip 学习目标
看懂 `imx6ul.dtsi` 里 `snvs@20cc000` 父节点为什么是 `syscon` + `simple-mfd`、`snvs-rtc-lp` 子节点的每个属性（`compatible`/`regmap`/`offset`/`interrupts`）对应驱动里的什么；理解为什么 `snvs_rtc` 没有 `status` 属性就意味着默认启用；学会在板子上确认设备树真的生效。
:::

## 为什么 alpha 板不用改设备树

回顾 [01 节](01_introduction.md)：`rtc-snvs.c` 默认就编进内核。那它怎么知道要 probe？靠设备树里有没有 `compatible = "fsl,sec-v4.0-mon-rtc-lp"` 的节点。

这个节点，NXP 在 `imx6ul.dtsi`（所有 i.MX6UL/6ULL 板子共用的基础设备树）里**已经写好了**，alpha 板的 dts `#include` 它就直接继承。所以你不用碰设备树——这正是「主线成熟驱动」省心的地方。

## snvs 父节点：syscon + simple-mfd

打开 `arch/arm/boot/dts/nxp/imx/imx6ul.dtsi`，找到 `snvs` 节点（约第 676 行）：

```dts
/* imx6ul.dtsi —— SNVS 是一个多驱动共享的寄存器块 */
snvs: snvs@20cc000 {
    compatible = "fsl,sec-v4.0-mon", "syscon", "simple-mfd";
    reg = <0x020cc000 0x4000>;

    snvs_rtc: snvs-rtc-lp {
        ...   /* RTC 子节点 */
    };

    snvs_poweroff: snvs-poweroff {
        ...   /* 关机控制子节点 */
    };

    snvs_pwrkey: snvs-powerkey {
        ...   /* 电源按键子节点 */
    };

    snvs_lpgpr: snvs-lpgpr {
        ...   /* 低功耗通用寄存器子节点 */
    };
};
```

先看父节点这三个 `compatible` 值，它们各司其职：

- `"fsl,sec-v4.0-mon"`：硬件标识，说明这是 NXP 安全监控模块 v4.0。
- `"syscon"`：声明这是一块**「多驱动共享的寄存器区」**。内核会为它建一个 regmap，别的子节点可以通过 `regmap = <&snvs>` 来「借用」它（回想 [03 节](03_snvs_driver_analysis.md) probe 里那个 `syscon_regmap_lookup_by_phandle`）。
- `"simple-mfd"`：声明这是一个**多功能设备**（Multi-Function Device），它的 `reg` 区域里挤着好几个独立子设备，每个子设备由各自的驱动管理（RTC、poweroff、pwrkey、lpgpr）。

`reg = <0x020cc000 0x4000>`：这块寄存器区从物理地址 `0x020cc000` 开始，长 16KB，里面装着 SNVS 的全部寄存器。

## snvs-rtc-lp 子节点详解

RTC 在 SNVS 里是一个子节点 `snvs-rtc-lp`：

```dts
/* imx6ul.dtsi —— RTC 子节点 */
snvs_rtc: snvs-rtc-lp {
    compatible = "fsl,sec-v4.0-mon-rtc-lp";
    regmap = <&snvs>;
    offset = <0x34>;
    interrupts = <GIC_SPI 19 IRQ_TYPE_LEVEL_HIGH>,
                 <GIC_SPI 20 IRQ_TYPE_LEVEL_HIGH>;
};
```

逐个属性对照驱动：

| 属性 | 值 | 对应驱动里的什么 |
|------|-----|-----------------|
| `compatible` | `"fsl,sec-v4.0-mon-rtc-lp"` | 命中 `rtc-snvs.c:428` 的 `snvs_dt_ids`，触发 probe |
| `regmap` | `<&snvs>` | probe 里 `syscon_regmap_lookup_by_phandle(..., "regmap")` 借父节点 regmap |
| `offset` | `0x34` | probe 里 `of_property_read_u32(..., "offset", ...)` → `SNVS_LPREGISTER_OFFSET`，RTC 寄存器在 SNVS 里的基地址偏移 |
| `interrupts` | GIC SPI 19, 20 | `platform_get_irq` 取中断号；19 是闹钟（`LPTA`），20 是秒更新 |

注意 `regmap = <&snvs>` 这个写法——RTC 子节点**没有自己的 `reg`**（没有独立物理地址），而是指向父节点 `&snvs` 借 regmap，再用 `offset` 说「我在父节点这块寄存器里的 `0x34` 位置」。这正是 [03 节](03_snvs_driver_analysis.md) 讲的 syscon 模型在设备树上的体现。

::: info 为什么是两个中断？
SNVS LP 域有两个中断源：**19 号**是闹钟（`LPTA`，时间到点），**20 号**是秒更新（每秒一次，给 UIE 那种周期性提醒用）。`rtc-snvs.c` 的 handler 主要处理 19 号（[04 节](04_driver_layer.md) 的 alarm），20 号留给周期中断机制。两个中断共享同一个 handler，靠 `IRQF_SHARED`。
:::

## 默认启用：为什么 snvs_rtc 没有 status

你可能注意到：`snvs_poweroff` 和 `snvs_pwrkey` 都有 `status = "disabled"`，而 `snvs_rtc` **没有 status 属性**。

这是设备树的惯例：**没有 `status` 属性，等同于 `status = "okay"`，默认启用**。NXP 默认把 RTC 打开（因为几乎所有系统都需要时间），把 poweroff/pwrkey 留给板子按需启用。所以 alpha 板继承这个 dtsi 后，RTC 直接就启用，不用你操心。

## 确认设备树生效

到板子上，几条命令确认 RTC 真的立起来了：

```bash
# 1. /dev/rtc0 在不在
ls -l /dev/rtc*
# crw-rw----    1 root     root      254,   0 Jan  1 00:00 /dev/rtc0

# 2. 看驱动名（应该是 snvs_rtc）
cat /proc/driver/rtc
# rtc_time        : 00:00:12
# rtc_date        : 2000-01-01
# alrm_time       : 00:00:00
# ...
# name            : snvs_rtc          ← 就是它

# 3. 设备树节点存在
ls /proc/device-tree/soc/bus@*/snvs@*/snvs-rtc-lp/
# compatible  interrupts  name  offset  regmap  ...

# 4. 启动日志里有 probe 记录
dmesg | grep -i rtc
```

只要 `/dev/rtc0` 在、`/proc/driver/rtc` 里 `name` 是 `snvs_rtc`，就说明 `rtc-snvs.c` 已经成功 probe、主线 RTC 完全可用。接下来 [06 节](06_build_and_test.md) 我们就用 `hwclock` 和 alarm demo 操作它。

## 硬件：纽扣电池 + 32.768kHz 晶振

最后说一句硬件，因为它决定了 RTC「断电走时」的本事。SNVS_LP 能在主电源断开后续命，靠两样东西，都在核心板上焊好了：

1. **纽扣电池**（接 `VDD_SNVS_IN`）：主电源断了，它给 SNVS_LP 供电，时钟继续走。
2. **32.768kHz 晶振**（接 `XTALOSC32`）：SRTC 的时钟源，$2^{15}$ Hz，分频出秒信号。

这两个东西在，你的板子拔了电源线、过几天再开机，时间照样准。我们会在 [06 节](06_build_and_test.md) 做断电走时验证。如果板子上没焊纽扣电池，断电后时间会回到 1970/2000 年——这是硬件配置问题，不是驱动问题。

## 小结

这一节我们看懂了设备树：`snvs@20cc000` 是 `syscon + simple-mfd` 的多驱动共享寄存器块，RTC 作为 `snvs-rtc-lp` 子节点，靠 `compatible` 命中驱动、靠 `regmap=<&snvs>` + `offset=0x34` 借寄存器、靠 GIC 19/20 两个中断。alpha 板继承自 `imx6ul.dtsi`，**一行都不用改**，开机就有 `/dev/rtc0`。下一节，我们用 `hwclock`、`date` 和一个 alarm demo 把它真正跑起来。

---

<ChapterNav variant="sub">
  <ChapterLink href="04_driver_layer.md" variant="sub">← 关键机制深挖</ChapterLink>
  <ChapterLink href="06_build_and_test.md" variant="sub">启用主线 RTC 与验证 →</ChapterLink>
</ChapterNav>
