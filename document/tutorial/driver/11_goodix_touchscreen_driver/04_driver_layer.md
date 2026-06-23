---
title: 关键机制深挖
---

# 关键机制深挖 —— configure_dev、轮询回退与配置校验

上一节我们跟着 `goodix_ts_probe` 走到了 `goodix_configure_dev`，当时一笔带过。这一节把它和另外几个精巧设计单独拆开：input 设备是怎么组装的、手指抬起为什么不用手写、8/9 字节格式的 quirk、以及没有中断时怎么轮询回退。这些是 `goodix.c` 里最见 input 子系统功底的地方。

::: tip 学习目标
看懂 `goodix_configure_dev` 如何一步步组装 input 设备（能力位、MT slots、注册、申请中断）；理解 `INPUT_MT_DROP_UNUSED` + `input_mt_sync_frame` 如何让「手指抬起」自动处理；搞清 `contact_size`（8 vs 9 字节）的 quirk 来源；明白无中断时如何用 `input_setup_polling` 轮询回退。
:::

## `configure_dev`：input 设备是怎么组装的

`goodix_configure_dev`（`:1131`）是 probe 的收尾，把一颗能 I2C 通信的 IC 变成一个注册到 input 子系统的设备。逐段看。

**① 分配 input 设备、填身份信息：**

```c
/* goodix.c:1139 —— 用 devm_ 分配，卸载自动回收 */
ts->input_dev = devm_input_allocate_device(&ts->client->dev);

ts->input_dev->name = "Goodix Capacitive TouchScreen";
ts->input_dev->phys = "input/ts";
ts->input_dev->id.bustype = BUS_I2C;     /* 告诉用户空间：这是 I2C 总线来的 */
ts->input_dev->id.vendor  = 0x0416;      /* 0x0416 = 汇鼎的厂商 ID */
```

`evtest`、`tslib` 看到的设备名「Goodix Capacitive TouchScreen」就是这里设的。

**② 声明能力位——告诉内核「我能产生哪些事件」：**

```c
/* goodix.c:1167 —— 声明：我能产生这些绝对坐标事件 */
input_set_capability(ts->input_dev, EV_ABS, ABS_MT_POSITION_X);   /* 多点 X */
input_set_capability(ts->input_dev, EV_ABS, ABS_MT_POSITION_Y);   /* 多点 Y */
input_set_abs_params(ts->input_dev, ABS_MT_WIDTH_MAJOR, 0, 255, 0, 0);  /* 触摸面积 */
input_set_abs_params(ts->input_dev, ABS_MT_TOUCH_MAJOR, 0, 255, 0, 0);
```

input 子系统的规矩：上报某类事件前，必须先声明「我支持它」。这里声明了多点 X/Y 坐标、触摸面积/粗细。`input_set_abs_params` 还设定了这些轴的取值范围（0-255）。

**③ 读 IC 配置、解析触摸参数：**

```c
/* goodix.c:1174 —— 从 IC 的配置寄存器读分辨率、最大触摸点数 */
goodix_read_config(ts);
/* :1177 —— 再用设备树的 touchscreen-size-x/y 等属性覆盖（优先级更高） */
touchscreen_parse_properties(ts->input_dev, true, &ts->prop);
```

`goodix_read_config`（`:1039`）通过 I2C 把 IC 内部那块「配置寄存器」读出来，从里面解析出 X/Y 最大分辨率、最大触摸点数。`touchscreen_parse_properties` 则允许用设备树属性（`touchscreen-size-x/y`、`touchscreen-inverted-x/y`、`touchscreen-swapped-x-y`）覆盖——板子接线不同导致坐标翻转/互换时，靠这个修正，不用改驱动。

**④ 初始化 MT slots（重头戏）：**

```c
/* goodix.c:1215 —— 告诉内核：开 max_touch_num 个抽屉，直接设备 + 自动丢弃未用 */
error = input_mt_init_slots(ts->input_dev, ts->max_touch_num,
                            INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
```

`max_touch_num` 是从 IC 配置读出的最大触摸点数（GT9147 通常 5 或 10）。两个 flag：

- `INPUT_MT_DIRECT`：直接输入设备（手指坐标就是屏幕坐标，触摸屏属于这类；触控板则不是）。
- `INPUT_MT_DROP_UNUSED`：**关键**——见下面一节。

**⑤ 无中断时轮询回退、注册设备、申请中断：**

```c
/* goodix.c:1225 —— 如果设备树没给 interrupts（client->irq==0），就用轮询 */
if (!ts->client->irq) {
    input_setup_polling(ts->input_dev, goodix_ts_work_i2c_poll);
    input_set_poll_interval(ts->input_dev, GOODIX_POLL_INTERVAL_MS);  /* 17ms = 60fps */
}

input_register_device(ts->input_dev);    /* 正式注册到 input 子系统 */
...
goodix_request_irq(ts);                  /* 申请 threaded IRQ（[03 节] 讲过） */
```

注册后，`/dev/input/eventX` 就出现了。至此 input 设备组装完成。

## `INPUT_MT_DROP_UNUSED`：抬起为什么不用手写

还记得 [02 节](02_input_framework.md) 说 Type B 手指抬起要把 slot 的 `TRACKING_ID` 置 `-1` 吗？但你翻遍 `goodix_ts_report_touch_8b`，**根本找不到处理抬起的代码**——它只管「按下」的点。手指抬起谁来报？

答案藏在 `input_mt_init_slots` 的 `INPUT_MT_DROP_UNUSED` flag + `input_mt_sync_frame` 里：

- 每一帧，驱动只对「当前按下的点」调 `input_mt_slot` + `input_mt_report_slot_state(..., true)`。
- 帧末尾 `input_mt_sync_frame`（goodix.c:498）一调，内核自动检查：**这一帧有哪些 slot 没被碰过？** 那些 slot（说明对应手指已抬起）会被自动置 `TRACKING_ID = -1`。

所以驱动完全不用维护「上一帧有哪些点、这一帧少了哪个」的状态机——`INPUT_MT_DROP_UNUSED` 让内核替你做减法。这就是现代 MT 驱动代码这么干净的原因。老式写法（不用这个 flag）得自己 diff 两帧、手动报抬起，啰嗦又易错。

## 8 字节 vs 9 字节：`contact_size` 的 quirk

`goodix_ts_data` 有个 `contact_size` 字段，默认 8（`GOODIX_CONTACT_SIZE`，goodix.c:34）。意思是每个触摸点在数据帧里占 8 字节：`[id(1)] [x(2)] [y(2)] [w(2)] [?]`。`report_touch_8b`（:404）就是按这个布局解析的。

但少数奇葩设备（联想 Yoga Book 等）用 9 字节格式，坐标偏移不同。goodix 怎么识别它们？靠 DMI 黑名单：

```c
/* goodix.c:1202 —— 命中黑名单的设备，改用 9 字节格式 */
if (dmi_check_system(nine_bytes_report)) {
    ts->contact_size = 9;
    dev_dbg(..., "Non-standard 9-bytes report format quirk\n");
}
```

`nine_bytes_report`（`:126`）是一张 DMI 表，列出已知的 9 字节设备。命中就把 `contact_size` 改成 9，后续 `process_events` 就调 `report_touch_9b`（偏移不同的版本）。这是「一份驱动适配多种硬件怪癖」的典型手法——靠 quirk 表，而不是 if-else 硬编码。GT9147 用标准 8 字节，不命中这张表。

## 配置寄存器：分辨率从哪来 + checksum 校验

前面说 `goodix_read_config` 从 IC 读分辨率。GT9147 内部有一块「配置寄存器」（长度由 chip_data 决定，GT9147 是 `GOODIX_CONFIG_967_LENGTH = 228` 字节），里面编码了分辨率、最大触摸点数、中断触发方式等。驱动读出来解析：

```c
/* goodix.c:1059 —— 从配置寄存器的固定偏移解析参数 */
ts->int_trigger_type = ts->config[TRIGGER_LOC] & 0x03;       /* config[6]：中断触发类型 */
ts->max_touch_num    = ts->config[MAX_CONTACTS_LOC] & 0x0f;  /* config[5]：最大触摸点数 */
x_max = get_unaligned_le16(&ts->config[RESOLUTION_LOC]);     /* config[1..2]：X 分辨率 */
y_max = get_unaligned_le16(&ts->config[RESOLUTION_LOC + 2]); /* config[3..4]：Y 分辨率 */
```

当驱动需要把一份新配置写回 IC 时（`goodix_send_cfg`，`:653`），会先做 **checksum 校验**（`goodix_check_cfg_8`，`:554`）：把配置字节逐个累加、取反加一，和配置末尾自带的校验字节比对。对不上就拒绝写入——防止把损坏的配置刷进 IC 导致触摸失灵。这种「写前校验」是嵌入式驱动的基本素养。

## 无中断也能工作：轮询回退

最后一个亮点。有些板子的触摸 IC 没接中断引脚（或中断引脚被占用），`client->irq` 为 0。goodix 不会就此罢工——它退化为**轮询模式**：

```c
/* goodix.c:1226 —— 无中断时，注册一个定时轮询函数 */
if (!ts->client->irq) {
    error = input_setup_polling(ts->input_dev, goodix_ts_work_i2c_poll);
    input_set_poll_interval(ts->input_dev, GOODIX_POLL_INTERVAL_MS);  /* 17ms ≈ 60fps */
}
```

`input_setup_polling` 是 input 子系统提供的轮询机制：注册后，子系统会按设定间隔（`GOODIX_POLL_INTERVAL_MS = 17ms`，约 60fps）自动调 `goodix_ts_work_i2c_poll`（`:502`），它内部就是调 `goodix_process_events`——和中断路径**共用同一套读+上报逻辑**。

所以 `goodix.c` 有两条数据路径（中断驱动 / 轮询驱动），但**汇合到同一个 `process_events`**。这是优秀的接口设计：上层逻辑不关心数据是被中断唤醒的还是轮询捞的。alpha 板 GT9147 接了中断（`GPIO1_IO09`），走中断路径；但知道有轮询回退这回事，调试时很有用（中断死活不触发？先试试轮询模式排除硬件问题）。

## 小结

这一节深挖了 `goodix.c` 的几个精巧设计：`configure_dev` 一步步组装 input 设备（能力位 → 读配置 → MT slots → 注册 → 中断）；`INPUT_MT_DROP_UNUSED` + `sync_frame` 让手指抬起自动处理、驱动代码极简；8/9 字节靠 DMI quirk 表适配；配置寄存器 checksum 校验防刷错；无中断时优雅轮询回退。这些是工业级 input 驱动的典型手法。下一节我们看设备树，把 GT9147 在 alpha 板上的接线讲清楚，然后上板用 evtest/tslib 验证。

---

<ChapterNav variant="sub">
  <ChapterLink href="03_goodix_driver_analysis.md" variant="sub">← goodix.c 逐段拆解</ChapterLink>
  <ChapterLink href="05_device_tree.md" variant="sub">设备树配置 →</ChapterLink>
</ChapterNav>
