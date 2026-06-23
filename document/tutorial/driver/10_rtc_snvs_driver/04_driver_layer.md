---
title: 关键机制深挖
---

# 关键机制深挖 —— 47 位计数器双读与 alarm 一次性中断

`rtc-snvs.c` 里有两段代码，看着不起眼，却是整颗驱动最见功力的地方：一个是**读时间时的「双读循环」**，一个是**闹钟中断的「一次性」设计**。这两个机制解决了 SNVS 硬件的两个固有难题——多寄存器读取的撕裂、闹钟中断的重复触发。这一节我们专门把这两块硬骨头啃下来。

::: tip 学习目标
理解 47 位硬件计数器为什么会「撕裂」、原厂如何用「双读 + diff 判据」的乐观并发规避它；通过 `set_time` 的位操作反推计数器真实位布局，坐实「手册撒谎」；搞懂 alarm 为什么设计成 one-shot、handler 如何在中断里自动关中断并唤醒等待者。
:::

## 硬骨头一：47 位计数器为什么会「撕裂」

SRTC 的秒计数器是一个 **47 位**的硬件计数器，物理上拆在两个 32 位寄存器里：

- `SNVS_LPSRTCMR`：存高位（实际用到低 15 位）
- `SNVS_LPSRTCLR`：存低位（实际用到高 17 位）

要读出完整时间，你必须**分两次**读这两个寄存器，再拼起来。问题就出在「分两次」上：时钟是不会停下来等你的。设想这个场景——

1. 你先读了高位 `LPSRTCMR`，得到 `H`。
2. 就在你去读低位 `LPSRTCLR` 的那一瞬，计数器低位正好溢出、向高位进了一位。
3. 你读到的低位 `L` 是进位**之后**的新值，而高位 `H` 是进位**之前**的旧值。

拼出来的 `H : L`，高位旧、低位新，整体错位——这个时间值要么跳到未来、要么退回过去，反正不是「现在」。这就是**撕裂读**（torn read）。

::: warning ⚠️ 这不是 i.MX6U 独有的坑
任何「一个值拆在多个寄存器、且硬件在持续更新」的设计都有这个问题。你在别的 SoC 的 64 位定时器、高精度 ADC 里都会遇到。本质是「读取不是原子的」。理解了这个解法，你举一能反十。
:::

## 原厂解法：双读 + diff 判据（乐观并发）

先看读单个 64 位原始值的底层函数（`:52`）：

```c
/* drivers/rtc/rtc-snvs.c:52 —— 读一次完整的 47 位（用 64 位装） */
static u64 rtc_read_lpsrt(struct snvs_rtc_data *data)
{
    u32 msb, lsb;

    regmap_read(data->regmap, data->offset + SNVS_LPSRTCMR, &msb);
    regmap_read(data->regmap, data->offset + SNVS_LPSRTCLR, &lsb);
    return (u64)msb << 32 | lsb;
}
```

这个函数本身就可能返回撕裂值。真正的对策在它的调用者 `rtc_read_lp_counter`（`:64`）：

```c
/* drivers/rtc/rtc-snvs.c:64 —— 双读，不一致就重读 */
static u32 rtc_read_lp_counter(struct snvs_rtc_data *data)
{
    u64 read1, read2;
    s64 diff;
    unsigned int timeout = 100;

    read1 = rtc_read_lpsrt(data);          /* 第一次读 */
    do {
        read2 = read1;
        read1 = rtc_read_lpsrt(data);      /* 第二次读 */
        diff = read1 - read2;
    } while (((diff < 0) || (diff > MAX_RTC_READ_DIFF_CYCLES)) && --timeout);
    if (!timeout)
        dev_err(&data->rtc->dev, "Timeout trying to get valid LPSRT Counter read\n");

    /* Convert 47-bit counter to 32-bit raw second count */
    return (u32)(read1 >> CNTR_TO_SECS_SH);   /* 右移 15 位 → 32 位秒 */
}
```

思路极其优雅，是一种**乐观并发控制**（和内核的 seqlock 同源）：

1. 不加锁（加锁要停掉时钟，代价太大）。先读一次得 `read1`。
2. 紧接着再读一次得新的 `read1`，把上次的存进 `read2`。
3. 算两次的差 `diff = read1 - read2`。正常情况下，两次读之间只过去了极少几个时钟周期，`diff` 是个很小的正数。但如果发生了进位撕裂，`diff` 要么是负的（回绕），要么是个异常大的值。
4. 判据：只要 `diff < 0` 或 `diff > MAX_RTC_READ_DIFF_CYCLES`，就认为这次读「可能撕裂了」，**重读**，直到两次连续读到一致（差值在合理范围内），或超过 100 次超时。

那个魔法阈值 `MAX_RTC_READ_DIFF_CYCLES = 320`（`:41`）不是拍脑袋——注释写得很清楚：RTC 频率 32kHz，320 个周期正好约 **10ms**，远大于两次 `regmap_read` 的耗时；正常绝不会超，只有撕裂才会超。这就是判据的物理依据。

::: tip 为什么是「乐观」？
seqlock/乐观并发的精神是：**假设大多数时候没有冲突，冲突了就重试**。这比悲观地加锁（每次都付出停时钟的代价）高效得多。你以后在内核里看到 `do { read1; read2; } while (inconsistent)` 这种模式，基本都是同一个思想。
:::

最后 `(u32)(read1 >> CNTR_TO_SECS_SH)`，`CNTR_TO_SECS_SH = 15`（`:33`）。因为 47 位计数器的低 15 位是 32768Hz 的亚秒计数，右移 15 位才得到整秒。所以读出来的虽然是 47 位原始计数，但有效秒数是 32 位。

## 用 `set_time` 反推真实位布局

[01 节](01_introduction.md) 我们说手册在 47 位计数器的位布局上「撒了谎」。与其争辩，不如直接看内核怎么写的——`set_time`（`:178`）的写操作会诚实地告诉你真相：

```c
/* drivers/rtc/rtc-snvs.c:193 —— 写时间时的位拆分 */
/* Write 32-bit time to 47-bit timer, leaving 15 LSBs blank */
regmap_write(data->regmap, data->offset + SNVS_LPSRTCLR, time << CNTR_TO_SECS_SH);
regmap_write(data->regmap, data->offset + SNVS_LPSRTCMR, time >> (32 - CNTR_TO_SECS_SH));
```

把 32 位秒数 `time` 写进 47 位计数器：

- `LPSRTCLR = time << 15`：秒数左移 15 位，占据低位寄存器的 bit\[15..31\]（17 位）。
- `LPSRTCMR = time >> 17`（即 `>> (32-15)`）：秒数的高 15 位，进高位寄存器。

拼起来：**32 位秒数分布在 47 位计数器的 bit\[15..46\]**，低 15 位留给亚秒计数。这就是真相——不是手册说的「高 15 + 低 32」，而是「低 15 位亚秒 + bit15 起的 32 位秒」。手册的位域描述对不上，内核用统一的 64 位读 + 右移 15 一刀解决，根本不纠结手册怎么画。

::: info 写时间还要先「停表」
注意 `set_time` 在写之前调了 `snvs_rtc_enable(data, false)`（`:189`），写完再 `enable(true)`。一边走时一边改计数器会乱套，所以必须先关 `SRTC_ENV`、改完再开。这和机械表「调时间先拔表冠」是一个道理。
:::

## 写后同步：`rtc_write_sync_lp`

还有一个容易漏的细节——写完寄存器，怎么确认它生效了？SNVS 的写入和秒计数是**异步**的：你 `regmap_write` 完，值未必立刻反映到计数逻辑，要等下一个 32.768kHz（CKIL）边沿。`rtc_write_sync_lp`（`:109`）干的就是这个：

```c
/* drivers/rtc/rtc-snvs.c:120 —— 写后等 3 个 CKIL 周期确认生效 */
/* Wait for 3 CKIL cycles, about 61.0-91.5 µs */
do {
    ret = rtc_read_lp_counter_lsb(data, &count2);
    ...
    elapsed = count2 - count1;   /* wrap around _is_ handled! */
} while (elapsed < 3 && --timeout);
```

写完后轮询低位计数器，等它跳过 3 个周期（约 61-91µs），说明写入已经和时钟逻辑同步上了。`alarm_irq_enable` 和 `set_alarm` 在改完控制位后都会调它，确保设置真正落地。

## 硬骨头二：alarm 一次性中断

闹钟中断的设计是第二个亮点。先看中断 handler（`:278`）：

```c
/* drivers/rtc/rtc-snvs.c:278 —— alarm 中断处理 */
static irqreturn_t snvs_rtc_irq_handler(int irq, void *dev_id)
{
    struct device *dev = dev_id;
    struct snvs_rtc_data *data = dev_get_drvdata(dev);
    u32 lpsr;
    u32 events = 0;

    clk_enable(data->clk);

    regmap_read(data->regmap, data->offset + SNVS_LPSR, &lpsr);

    if (lpsr & SNVS_LPSR_LPTA) {              /* LPTA = 闹钟到期标志 */
        events |= (RTC_AF | RTC_IRQF);

        /* RTC alarm should be one-shot */
        snvs_rtc_alarm_irq_enable(dev, 0);    /* ← 触发后立刻关掉中断 */

        rtc_update_irq(data->rtc, 1, events); /* 通知等待的进程 */
    }

    /* clear interrupt status —— 写 1 清除 */
    regmap_write(data->regmap, data->offset + SNVS_LPSR, lpsr);

    clk_disable(data->clk);

    return events ? IRQ_HANDLED : IRQ_NONE;
}
```

关键是这一行——

```c
/* RTC alarm should be one-shot */
snvs_rtc_alarm_irq_enable(dev, 0);
```

SNVS 的闹钟硬件，一旦 `LPTAR` 里的时间和当前时间相等，**就会一直触发中断**（只要中断使能着）。如果不在 handler 里关掉，它会响个不停、把系统刷爆。所以原厂的设计是 **one-shot（一次性）**：handler 检测到 `LPSR_LPTA` 置位后，**立刻把闹钟中断关掉**（`alarm_irq_enable(dev, 0)`，清 `LPCR` 的 `LPTA_EN` 位），这样下一次就不会重复触发。

用户想再设一个闹钟？得重新走 `set_alarm`（`:246`）——写新的 `LPTAR`、清 `LPSR`、再调 `alarm_irq_enable` 打开。这个「设一次、响一次、自动关」的语义，就是 `RTC_WKALM_SET` 那类命令期望的行为。

handler 里还有两个标准动作：

- `rtc_update_irq(data->rtc, 1, events)`：通知子系统「有事件发生了」。这会让阻塞在 `read(/dev/rtc0)` 上等待闹钟的进程被唤醒（[06 节](06_build_and_test.md) 的 alarm demo 就靠这个）。
- `regmap_write(LPSR, lpsr)`：状态寄存器「写 1 清除」，把刚才置位的 `LPTA` 清掉，否则下次进 handler 还会看到它。

::: tip 为什么 alarm 默认是一次性？
因为「闹钟」的语义就是「到点提醒一次」，不是「每秒提醒」。周期性提醒那是 RTC 的另一种机制（UIE，update interrupt，每秒一次），由 `RTC_UIE_ON` 命令控制，走的是不同路径。alarm 走一次性，是合理的 API 设计。
:::

## 小结

这一节啃下了 `rtc-snvs.c` 最硬的两块：47 位计数器用「双读 + diff>320 判据」的乐观并发规避撕裂读，并用 `set_time` 的位操作坐实了「手册位布局有误、真相是 bit15 起的 32 位秒」；alarm 中断用 handler 内自动关中断实现 one-shot，配合 `rtc_update_irq` 唤醒等待者。这两段代码不长，但浓缩了「读硬件并发」「中断语义设计」的实战智慧。

读完这些，`rtc-snvs.c` 你就算吃透了。下一节我们看看设备树这边 `snvs-rtc-lp` 节点长什么样，再到板子上把主线 RTC 真正跑起来。

---

<ChapterNav variant="sub">
  <ChapterLink href="03_snvs_driver_analysis.md" variant="sub">← rtc-snvs.c 逐段拆解</ChapterLink>
  <ChapterLink href="05_device_tree.md" variant="sub">设备树配置 →</ChapterLink>
</ChapterNav>
