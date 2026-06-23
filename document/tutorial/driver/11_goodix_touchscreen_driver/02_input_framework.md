---
title: Input 子系统与 MT 协议
---

# Input 子系统与 MT 协议 —— 多点触摸是怎么「记账」的

看 `goodix.c` 之前，我们必须先补一块理论：**多点触摸协议（Multi-Touch Protocol，MT 协议）**。这是 input 子系统里专门为「多手指」设计的上报规则，也是这一章最值钱的知识点——你在 [07_input_subsystem_key](../07_input_subsystem_key/) 学的按键 input 只报「按下/松开」，而触摸屏要同时报「5 根手指各自在哪、谁刚按下、谁在移动、谁抬起了」，复杂度完全不同。这一节把 MT 协议讲透，下一节看 `goodix.c` 你就毫无障碍。

::: tip 学习目标
理解电容触摸驱动「I2C + 中断 + input」三件套的本质；搞清 MT 协议 Type A 与 Type B 的区别（流水账 vs 记账本）；掌握 `input_mt_init_slots` / `input_mt_slot` / `input_mt_report_slot_state` / `input_mt_sync_frame` 这组 API 的时序；理解为什么触摸中断要用 threaded IRQ。
:::

## 触摸驱动：三件事的缝合体

剥开 `goodix.c` 的外衣，它其实是三样东西的组合：

1. **I2C 设备驱动**：触摸 IC（GT9147）挂在 I2C 上，坐标数据靠 I2C 读。I2C 这套我们在 [08 章](../08_i2c_ap3216c_driver/) 已经写烂了。
2. **中断驱动**：触摸 IC 不会傻站着等你轮询，手指一碰就把 INT 引脚拉低、主动通知 CPU。中断我们在 [06 章](../06_debounced_key_driver/) 也学过。
3. **input 子系统**：读到的坐标，最终要以**标准的 input 事件**格式上报给用户空间（`evtest`、`tslib` 才能消费）。按键 input 我们在 [07 章](../07_input_subsystem_key/) 见过 `input_report_key`。

前两件都是老朋友，唯独 **input 子系统下的多点触摸协议** 是新东西。内核里这份协议的「圣经」在 `Documentation/input/multi-touch-protocol.rst`，我们这里把它讲通俗。

## 为什么需要专门的 MT 协议

回忆按键 input：一个按键就 `input_report_key(dev, KEY_xxx, 1/0)` 完事。单点触摸屏也好办：报 `ABS_X` / `ABS_Y` 两个绝对坐标就行（[07 章](../07_input_subsystem_key/) 那种）。

但多点触摸屏不一样——它要同时追踪**好几个手指**。假如屏幕上有 5 根手指，你光报「X=100, Y=200」根本说不清这是哪根手指的坐标、哪根刚抬起。所以内核设计了一套专门的 `ABS_MT_*` 事件家族，用来**逐点、可追踪地**上报多个触摸点。这就是 MT 协议。

## Type A vs Type B：流水账与记账本

早期的 MT 协议把硬件分成两类，对应两种上报方式。用两个生活化的比喻：

- **Type A（记流水账）**：硬件**分不清**各个触摸点，只管一股脑扔出一堆坐标。驱动把这些坐标像流水账一样逐个上报，靠一个「分隔符」切开。老硬件用这种，现在基本绝迹。
- **Type B（记账本）**：硬件**有追踪能力**，给每个触摸点分配一个唯一 ID。驱动用「抽屉（slot）」管理每个点，明确告诉内核「3 号抽屉的手指移到了」「1 号抽屉的手指抬起了」。GT9147 这类现代 IC 都是 Type B，也是我们要重点掌握的。

这些触摸点信息，都是通过一系列 `ABS_MT_*` 事件上报的。打开 `include/uapi/linux/input-event-codes.h`，你会看到一大堆 `ABS_MT_` 开头的宏。真正核心的就这几个：

```c
#define ABS_MT_SLOT          0x2f  /* 当前要操作哪个 slot（抽屉）        */
#define ABS_MT_POSITION_X    0x35  /* 触摸点 X 坐标                    */
#define ABS_MT_POSITION_Y    0x36  /* 触摸点 Y 坐标                    */
#define ABS_MT_TRACKING_ID   0x39  /* 唯一追踪 ID（-1 表示抬起）        */
```

`ABS_MT_SLOT` 和 `ABS_MT_TRACKING_ID` 是 Type B 用来区分手指的命脉。

## Type A 时序：靠 `input_mt_sync` 切分

Type A 设备每报完一个点的坐标，就调一次 `input_mt_sync(dev)`——它发一个 `SYN_MT_REPORT` 事件，相当于说「这一段写完了，下一段开始」。两个手指的时序：

```text
ABS_MT_POSITION_X  x[0]
ABS_MT_POSITION_Y  y[0]
SYN_MT_REPORT            ← 0 号手指的数据包结束

ABS_MT_POSITION_X  x[1]
ABS_MT_POSITION_Y  y[1]
SYN_MT_REPORT            ← 1 号手指的数据包结束

SYN_REPORT               ← 一整帧结束（所有点报完）
```

逻辑直观，但内核得自己猜哪个点是哪个，效率低。GT9147 不用这种。

## Type B 时序：用「抽屉」增量记账

Type B 完全是另一种思路——用**抽屉（slot）**。每个 slot 装一个触摸点。上报前，驱动先指着某个抽屉说「我要更新它」，这就是 `input_mt_slot(dev, slot)`（发 `ABS_MT_SLOT` 事件）。

抽屉里最重要的信息是**它现在是空的还是满的**，用 `ABS_MT_TRACKING_ID` 标识（由内核分配）：

- ID 从 `-1` 变成一个非负数 → 「新手指按下了」。
- ID 变回 `-1` → 「手指抬起了」。

两个手指按下的 Type B 时序：

```text
ABS_MT_SLOT         0       ← 选中 0 号抽屉
ABS_MT_TRACKING_ID  45      ← 分配 ID=45，表示有手指了
ABS_MT_POSITION_X   x[0]
ABS_MT_POSITION_Y   y[0]

ABS_MT_SLOT         1       ← 切换到 1 号抽屉
ABS_MT_TRACKING_ID  46
ABS_MT_POSITION_X   x[1]
ABS_MT_POSITION_Y   y[1]

SYN_REPORT                  ← 整帧结束
```

Type B 的杀手锏是**增量更新**：如果 0 号手指没动，这一帧根本不用再报它的坐标，内核自动保留上一次的状态。手指抬起时，只要把对应 slot 的 ID 置 `-1`：

```text
ABS_MT_SLOT         0
ABS_MT_TRACKING_ID  -1      ← 0 号手指抬起了
SYN_REPORT
```

## Type B 的 API 军火库

理论清楚了，看看手里有哪些函数（`include/linux/input.h` 和 `input/mt.c`）。这就是 `goodix.c` 上报触摸时用的工具：

```c
/* 1. 开工前告诉内核要盖几层楼（几个 slot）—— 必须在注册 input 设备前调 */
int input_mt_init_slots(struct input_dev *dev, unsigned int num_slots,
                        unsigned int flags);
/*   flags: INPUT_MT_DIRECT（直接设备，如触摸屏）| INPUT_MT_DROP_UNUSED（自动丢弃未上报的点）*/

/* 2. 选中当前要操作的抽屉 */
void input_mt_slot(struct input_dev *dev, int slot);

/* 3. 填抽屉状态：active=true 自动分配新 ID（按下），active=false 置 ID=-1（抬起） */
void input_mt_report_slot_state(struct input_dev *dev, unsigned int tool_type,
                                bool active);   /* tool_type: MT_TOOL_FINGER 等 */

/* 4. 上报坐标（goodix 用封装版 touchscreen_report_pos，内部调 input_report_abs） */
void input_report_abs(struct input_dev *dev, unsigned int code, int value);

/* 5. 一帧结束的同步 —— Type B 用 sync_frame 替代老的 input_sync + pointer_emulation */
void input_mt_sync_frame(struct input_dev *dev);
```

::: warning ⚠️ 老教程里的 `input_mt_report_pointer_emulation` 已被 `input_mt_sync_frame` 取代
很多老文章在帧末尾调 `input_mt_report_pointer_emulation` + `input_sync`，来给只认单点（`ABS_X/ABS_Y`）的老应用做兼容。7.1 里现代写法是直接 `input_mt_sync_frame`——它在 `input_mt_init_slots` 时配合 `INPUT_MT_DROP_UNUSED` 标志，会自动处理「未上报的 slot 视为抬起」并完成单点模拟。`goodix.c:498` 用的就是 `input_mt_sync_frame`。
:::

把这套 API 串起来，一个 Type B 上报循环长这样（和 `goodix.c` 的 `goodix_ts_report_touch_8b` 几乎一样）：

```c
for (i = 0; i < touch_num; i++) {
    input_mt_slot(input, id);                                   /* 选抽屉 */
    input_mt_report_slot_state(input, MT_TOOL_FINGER, true);    /* 标记按下、分配 ID */
    input_report_abs(input, ABS_MT_POSITION_X, x);              /* 填坐标 */
    input_report_abs(input, ABS_MT_POSITION_Y, y);
}
input_mt_sync_frame(input);   /* 帧同步：自动处理抬起 + 单点模拟 */
```

记住这个节奏：**选槽 → 激活 → 填数 → 帧同步**。

## 为什么触摸要用 threaded IRQ

最后一块拼图：中断。你可能注意到 [RTC 章](../10_rtc_snvs_driver/03_snvs_driver_analysis.md) 的 `rtc-snvs.c` 用的是普通 `devm_request_irq`，而触摸 `goodix.c` 用的是 `devm_request_threaded_irq`（goodix.c:549）。为什么不同？

两层原因：

1. **中断太频繁**：手指按在屏上稍微一划，每秒几十上百次中断。
2. **handler 里要读 I2C**：I2C 是慢总线，一次读几百微秒。在**硬中断上下文**（Hard IRQ）里干这种慢活，会把系统其它任务饿死——硬中断是最高优先级、不可睡眠的。

threaded IRQ 的解法：把中断处理拆两半。**上半部**几乎不干事（甚至为空），只负责唤醒一个专属的**内核线程**；真正耗时的 I2C 读取和坐标上报，全在这个线程里跑。线程是可调度、可睡眠的，慢操作不会卡死系统。

```c
/* goodix.c:549 —— 看两个 handler 参数：第一个 NULL，第二个才是干活的 */
devm_request_threaded_irq(&client->dev, client->irq,
                          NULL,                  /* 上半部（hard irq）：空 */
                          goodix_ts_irq_handler, /* 下半部（thread）：读 I2C + 上报 */
                          ts->irq_flags,         /* 含 IRQF_ONESHOT */
                          client->name, ts);
```

第一个 handler 参数填 `NULL`，意味着没有上半部、全部在线程里处理。那个 `IRQF_ONESHOT` 标志很关键：它保证线程处理完之前硬件中断一直被屏蔽，否则 I2C 还没读完、下一个中断又来了，形成中断风暴。

::: tip devm_ 再现
注意又是 `devm_` 前缀。`devm_request_threaded_irq` 申请的中断，驱动卸载时内核自动 `free_irq`，不用手写——和 RTC 章、按键章一脉相承的资源托管思想。
:::

## 小结

这一节我们补齐了 MT 协议这块理论：触摸驱动是「I2C + 中断 + input」三件套；多点触摸用 Type B（抽屉式）上报，节奏是「选槽 → 激活 → 填数 → 帧同步」；频繁中断 + 慢 I2C 决定了必须用 threaded IRQ。带着这套理论，下一节我们钻进 `goodix.c`，看它怎么把这些落到代码上。

---

<ChapterNav variant="sub">
  <ChapterLink href="01_introduction.md" variant="sub">← 架构概览</ChapterLink>
  <ChapterLink href="03_goodix_driver_analysis.md" variant="sub">goodix.c 逐段拆解 →</ChapterLink>
</ChapterNav>
