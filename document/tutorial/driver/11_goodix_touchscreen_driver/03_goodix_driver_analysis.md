---
title: goodix.c 逐段拆解
---

# goodix.c 逐段拆解 —— probe、I2C 与触摸上报

理论武装完毕，这一节我们正式拆 `drivers/input/touchscreen/goodix.c`（7.1，1579 行）。和 RTC 章 `rtc-snvs.c` 一样，它是标准的子系统驱动——只不过这次挂在 **I2C 总线**上、上报走 **input 子系统**、用的是上一节讲的 **Type B MT 协议** + **threaded IRQ**。我们从匹配表一路拆到中断上报，看完你就懂了一颗工业级触摸驱动长什么样。

::: tip 学习目标
看懂 `goodix.c` 的 `i2c_driver` 骨架与 `of_match`（GT9147/GT911）；跟着 `goodix_ts_probe` 走完上电复位 → I2C 握手 → 读版本 → 配置 input 设备的完整流程；理清 `goodix_i2c_read` → `goodix_ts_read_input_report` → `goodix_ts_report_touch_8b` → `goodix_process_events` 这条数据上报链路；认清 threaded IRQ 在哪里注册、如何触发。
:::

## 驱动骨架：i2c_driver + of_match

整颗驱动是一个 `i2c_driver`（触摸 IC 挂 I2C，所以是 i2c 驱动，不是 platform）：

```c
/* drivers/input/touchscreen/goodix.c:1543 —— 设备树匹配表（节选） */
static const struct of_device_id goodix_of_match[] = {
    { .compatible = "goodix,gt911" },     /* ← 上一章你听到的 "GT911" */
    { .compatible = "goodix,gt9147" },    /* ← alpha 板实际的 GT9147 命中这条 */
    { .compatible = "goodix,gt9271" },
    { .compatible = "goodix,gt928" },
    /* ... 还有 gt1151/gt5663/gt912/gt967 等十几个 ... */
    { }
};

/* :1563 —— i2c 驱动骨架 */
static struct i2c_driver goodix_ts_driver = {
    .probe      = goodix_ts_probe,
    .remove     = goodix_ts_remove,
    .id_table   = goodix_ts_id,
    .driver = {
        .name           = "Goodix-TS",
        .of_match_table = of_match_ptr(goodix_of_match),
        .pm             = pm_sleep_ptr(&goodix_pm_ops),
    },
};
module_i2c_driver(goodix_ts_driver);
```

内核启动解析设备树，看到 `compatible = "goodix,gt9147"` 的节点（alpha 板 `i2c2` 下那个 `gt9147@5d`），就用这张表匹配、触发 `goodix_ts_probe`。一份驱动兼容整个 GT 家族——这就是主线成熟驱动的好处。`module_i2c_driver` 一行宏搞定注册，和 [08 章](../08_i2c_ap3216c_driver/) 的 I2C 驱动骨架一致。

## probe 全景：从上电到 input 设备就绪

`goodix_ts_probe`（`:1308`）是这颗驱动最长也最关键的函数。它要把一颗可能还没上电、还没握过手的触摸 IC，伺候到一个能上报事件的 input 设备。分几步看。

### 第 1 步：I2C 能力检查 + 私有数据

```c
/* goodix.c:1316 —— 先确认这条 I2C 总线支持标准 I2C 传输 */
if (!i2c_check_functionality(client->adapter, I2C_FUNC_I2C)) {
    dev_err(&client->dev, "I2C check functionality failed.\n");
    return -ENXIO;
}

ts = devm_kzalloc(&client->dev, sizeof(*ts), GFP_KERNEL);   /* 私有数据 */
ts->client = client;
i2c_set_clientdata(client, ts);
ts->contact_size = GOODIX_CONTACT_SIZE;   /* 8 字节/点（默认） */
```

`goodix_ts_data`（定义在 `goodix.h`）是这颗驱动的私有数据，装着 i2c_client、input_dev、GPIO、regulator、chip 配置等。`contact_size` 默认 8（每个触摸点 8 字节），后面上报要用。

### 第 2 步：GPIO 与电源（irq + reset + 双 regulator）

```c
/* goodix.c:1330 —— 拿 INT/RESET 引脚和两路电源 */
error = goodix_get_gpio_config(ts);      /* 读设备树：irq-gpios、reset-gpios、AVDD28、VDDIO */
...
error = regulator_enable(ts->avdd28);    /* 模拟电源 AVDD28 上电 */
error = regulator_enable(ts->vddio);     /* IO 电源 VDDIO 上电 */
error = devm_add_action_or_reset(&client->dev, goodix_disable_regulators, ts);
```

`goodix_get_gpio_config`（`:963`）从设备树拿四样东西：中断 GPIO（`irq-gpios`，对应 `devm_gpiod_get_optional(dev, "irq", GPIOD_IN)`）、复位 GPIO（`reset-gpios`）、模拟电源 `AVDD28`、IO 电源 `VDDIO`。两路 regulator 上电后，用 `devm_add_action_or_reset` 注册「卸载时自动断电」的回调——又是 `devm_` 托管。

::: tip 中断号从哪来？
注意 `goodix_get_gpio_config` 拿的 `irq-gpios` 主要是为了「复位时操控 INT 引脚」（配合 GT9147 的双地址机制）。真正用于 `request_irq` 的中断号 `client->irq`，是 I2C 核心从设备树的 `interrupts` 属性（alpha 板 `interrupts = <9 0>`，即 GPIO1_IO09 的中断）自动填进 `i2c_client` 的。所以设备树里 `interrupts` 和 `reset-gpios` 各司其职，别搞混，[05 节](05_device_tree.md) 会详讲。
:::

### 第 3 步：复位与 I2C 握手

```c
/* goodix.c:1357 —— 复位 IC（操作 RST 和 INT 引脚的时序） */
if (ts->reset_controller_at_probe) {
    error = goodix_reset(ts);
    ...
}

/* goodix.c:1365 —— I2C 握手测试：读一下 ID 寄存器看 IC 应答不应答 */
error = goodix_i2c_test(client);
```

`goodix_reset`（`:811`）按数据手册的时序操作 RST/INT 引脚（拉低 RST → 等 → 拉高，期间按地址模式操作 INT）。`goodix_i2c_test`（`:1104`）读一次 ID 寄存器，IC 能应答就说明 I2C 通了；不通就复位重试一次。这是个很实在的「上线前体检」。

### 第 4 步：读版本、选 chip_data

```c
/* goodix.c:1381 —— 读 IC 的芯片 ID 字符串（如 "9147"）和固件版本 */
error = goodix_read_version(ts);
ts->chip = goodix_get_chip_data(ts->id);   /* 按 ID 选配置（如 9147 → gt967_chip_data） */
```

`goodix_read_version`（`:1077`）通过 I2C 读 6 字节，前 4 字节是 ID 字符串（`"9147"`），后 2 字节是版本号。`goodix_get_chip_data`（`:241`）拿这个 ID 去查表（`goodix_chip_ids`，`:98`），选出该芯片的配置长度、校验方式等（GT9147 命中 `"9147" → gt967_chip_data`，`:114`）。**一份驱动适配多颗芯片**，靠的就是这张表。

### 第 5 步：configure_dev —— input 设备登场

```c
/* goodix.c:1411 —— 配置并注册 input 设备、申请中断 */
error = goodix_configure_dev(ts);
```

`goodix_configure_dev`（`:1131`）是收尾重头戏，下一节我们单独深挖。它干三件事：分配并配置 `input_dev`（设能力位、`input_mt_init_slots`）、注册 input 设备、`goodix_request_irq` 申请 threaded IRQ。

## I2C 读坐标：`goodix_i2c_read`

所有 I2C 操作的底层是 `goodix_i2c_read`（`:171`）。它和 [08 章](../08_i2c_ap3216c_driver/) 我们写的 I2C 寄存器读是同一个套路——两条 `i2c_msg`：先写寄存器地址、再读数据：

```c
/* drivers/input/touchscreen/goodix.c:171 —— 标准的「写寄存器地址 + 读数据」 */
int goodix_i2c_read(struct i2c_client *client, u16 reg, u8 *buf, int len)
{
    struct i2c_msg msgs[2];
    __be16 wbuf = cpu_to_be16(reg);     /* 寄存器地址，大端 2 字节 */

    msgs[0].flags = 0;                  /* 写：把 reg 地址发给 IC */
    msgs[0].addr  = client->addr;
    msgs[0].len   = 2;
    msgs[0].buf   = (u8 *)&wbuf;

    msgs[1].flags = I2C_M_RD;           /* 读：从 IC 读 len 字节到 buf */
    msgs[1].addr  = client->addr;
    msgs[1].len   = len;
    msgs[1].buf   = buf;

    ret = i2c_transfer(client->adapter, msgs, 2);   /* 一次 transfer 完成两条 */
    ...
}
```

这就是 [08 章](../08_i2c_ap3216c_driver/) 讲过的 `i2c_transfer` 两段式读写，goodix 用它读一切（ID 寄存器、配置、坐标）。熟悉的配方。

## 读一帧：`goodix_ts_read_input_report`

中断到来后，驱动要读「这一帧有几个点、各点坐标」。`goodix_ts_read_input_report`（`:253`）干这个，有个值得讲的轮询细节：

```c
/* drivers/input/touchscreen/goodix.c:253 —— 读一帧触摸数据（有删减） */
static int goodix_ts_read_input_report(struct goodix_ts_data *ts, u8 *data)
{
    max_timeout = jiffies + msecs_to_jiffies(GOODIX_BUFFER_STATUS_TIMEOUT);  /* 20ms */
    do {
        error = goodix_i2c_read(ts->client, addr, data, header_contact_keycode_size);
        if (error)
            return error;

        if (data[0] & GOODIX_BUFFER_STATUS_READY) {   /* buffer-status 位=数据有效 */
            touch_num = data[0] & 0x0f;               /* 低 4 位=触摸点数 */
            ...                                        /* 多点时再读后续坐标 */
            return touch_num;
        }
        usleep_range(1000, 2000);                      /* 1-2ms 轮询一次 */
    } while (time_before(jiffies, max_timeout));

    return -ENOMSG;   /* 超时：可能是「手指抬起」后的虚假中断 */
}
```

注意那个 `do-while` 轮询：IC 拉低 INT 后，「数据有效」位（`GOODIX_BUFFER_STATUS_READY`）不是立刻置位、而是**稍后才置位**（约 10ms 内）。所以驱动读一次发现没就绪，就每隔 1-2ms 重读、最多等 20ms。这是和 IC 时序特性匹配的「缓冲就绪轮询」。

返回值 `touch_num` 是这一帧的触摸点数；`-ENOMSG` 表示超时——通常是「手指抬起」后 IC 发的虚假中断（没数据可读），上层会忽略它。

## 上报一点：`goodix_ts_report_touch_8b`

读到坐标后，要把每个点按 [02 节](02_input_framework.md) 的 Type B 时序上报。8 字节格式的上报在 `goodix_ts_report_touch_8b`（`:404`）：

```c
/* drivers/input/touchscreen/goodix.c:404 —— Type B 上报一个触摸点 */
static void goodix_ts_report_touch_8b(struct goodix_ts_data *ts, u8 *coor_data)
{
    int id = coor_data[0] & 0x0F;                       /* 点的 ID（slot 号） */
    int input_x = get_unaligned_le16(&coor_data[1]);    /* 小端 16 位 X */
    int input_y = get_unaligned_le16(&coor_data[3]);    /* 小端 16 位 Y */
    int input_w = get_unaligned_le16(&coor_data[5]);    /* 触摸面积/粗细 */

    input_mt_slot(ts->input_dev, id);                            /* 1. 选抽屉 */
    input_mt_report_slot_state(ts->input_dev, MT_TOOL_FINGER, true); /* 2. 激活 */
    touchscreen_report_pos(ts->input_dev, &ts->prop,
                           input_x, input_y, true);              /* 3. 填 X/Y 坐标 */
    input_report_abs(ts->input_dev, ABS_MT_TOUCH_MAJOR, input_w); /* 4. 填面积 */
    input_report_abs(ts->input_dev, ABS_MT_WIDTH_MAJOR, input_w);
}
```

和 [02 节](02_input_framework.md) 那个 Type B 节奏**一模一样**：选槽（`input_mt_slot`）→ 激活（`input_mt_report_slot_state`）→ 填坐标（`touchscreen_report_pos`，它内部调 `input_report_abs` 报 `ABS_MT_POSITION_X/Y`，还会按设备树的 `touchscreen-size-x/y`、翻转等做坐标变换）→ 填面积。`touchscreen_report_pos` 是 input 子系统提供的触摸坐标上报助手，比裸调 `input_report_abs` 更省心。

（旁边还有个 `goodix_ts_report_touch_9b`，`:419`，是给少数用 9 字节格式的设备准备的 quirk，逻辑相同、只是字节偏移不同。）

## 串起来：`goodix_process_events` + 中断 handler

最后把读和上报串起来。`goodix_process_events`（`:468`）是一帧的编排：

```c
/* drivers/input/touchscreen/goodix.c:468 —— 处理一帧（有删减） */
static void goodix_process_events(struct goodix_ts_data *ts)
{
    u8 point_data[2 + GOODIX_MAX_CONTACT_SIZE * GOODIX_MAX_CONTACTS];

    touch_num = goodix_ts_read_input_report(ts, point_data);   /* 读一帧 */
    if (touch_num < 0)
        return;

    goodix_ts_report_key(ts, point_data);   /* 触摸按键（如有） */

    for (i = 0; i < touch_num; i++)         /* 逐点上报 */
        if (ts->contact_size == 9)
            goodix_ts_report_touch_9b(ts, &point_data[1 + ts->contact_size * i]);
        else
            goodix_ts_report_touch_8b(ts, &point_data[1 + ts->contact_size * i]);

    input_mt_sync_frame(ts->input_dev);     /* 帧同步：自动处理抬起 + 单点模拟 */
    input_sync(ts->input_dev);
}
```

读一帧 → 逐点 `report_touch_8b` → `input_mt_sync_frame` + `input_sync` 收尾。`input_mt_sync_frame`（配合 `init_slots` 时的 `INPUT_MT_DROP_UNUSED`）会自动把「这一帧没上报的 slot」标记为抬起，所以代码里**不用显式处理手指抬起**——上一节说的增量更新、自动回收，全交给这一行。

谁调它？中断 handler `goodix_ts_irq_handler`（`:516`），跑在 threaded IRQ 的内核线程里：

```c
/* drivers/input/touchscreen/goodix.c:516 —— threaded IRQ 的下半部 */
static irqreturn_t goodix_ts_irq_handler(int irq, void *dev_id)
{
    struct goodix_ts_data *ts = dev_id;

    goodix_process_events(ts);                              /* 读+上报 */
    goodix_i2c_write_u8(ts->client, GOODIX_READ_COOR_ADDR, 0); /* 清坐标寄存器，告诉 IC「读完了」 */

    return IRQ_HANDLED;
}
```

读完上报后，往坐标寄存器写个 0——这是「回执」，告诉 IC「这帧我收下了、你可以发下一帧」。中断注册在 `goodix_request_irq`（`:544`）：

```c
/* goodix.c:549 —— threaded IRQ：上半部空、下半部是上面的 handler */
return devm_request_threaded_irq(&client->dev, client->irq,
                                 NULL, goodix_ts_irq_handler,
                                 ts->irq_flags,   /* 含 IRQF_ONESHOT */
                                 client->name, ts);
```

整条链路闭合：**INT 拉低 → threaded IRQ 唤醒内核线程 → `irq_handler` → `process_events` → `read_input_report`(I2C 读) → 循环 `report_touch_8b`(Type B 上报) → `sync_frame`**。一次完整的触摸数据搬运。

## 小结

这一节我们把 `goodix.c` 从骨架拆到了上报链路：它是 `i2c_driver`，`probe` 里完成上电（双 regulator）→ 复位 → I2C 握手 → 读版本选 chip_data → `configure_dev` 配 input 设备；数据来时由 threaded IRQ 触发，在内核线程里 `i2c_transfer` 读一帧坐标，按 Type B 节奏逐点上报，最后 `input_mt_sync_frame` 收尾。下一节我们专门深挖几个关键机制：`configure_dev` 里 input 能力位怎么设、8 字节 vs 9 字节格式、以及没有中断时怎么轮询回退。

---

<ChapterNav variant="sub">
  <ChapterLink href="02_input_framework.md" variant="sub">← Input 子系统与 MT 协议</ChapterLink>
  <ChapterLink href="04_driver_layer.md" variant="sub">关键机制深挖 →</ChapterLink>
</ChapterNav>
