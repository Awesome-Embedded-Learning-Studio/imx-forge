---
title: RTC 子系统分层框架
---

# RTC 子系统分层框架 —— 通用层与底层契约

## 前言：为什么内核不让你直接写 `file_operations`

回想一下我们在 [00_chardev_base](../00_chardev_base/) 里是怎么写字符设备的：自己实现 `open/read/write/ioctl`，自己填一坨 `file_operations`，自己 `cdev_add`。那套打法对 LED、对 AP3216C 这种「私有」设备没问题——每个设备都不一样，各写各的。

可 RTC 不一样。不管你底层接的是 i.MX6U 的片内 SNVS、还是外挂的 PCF8563、DS1302，**应用层的用法是完全一样的**：`open("/dev/rtc0")` + `ioctl(RTC_RD_TIME)` 读时间。如果让每颗 RTC 芯片的驱动都自己去实现一遍 `ioctl` 解析 `RTC_RD_TIME`、`copy_to_user`、闰年校验……那代码会重复到令人发指。

所以 Linux RTC 子系统干了一件事：**把「和应用层打交道」的通用逻辑抽出来，只让底层驱动实现「怎么读写你的硬件」**。这就是这一节要讲的分层。把它想明白，你才能看懂 `rtc-snvs.c` 为什么长那样——它只填了几个回调，却凭空得到了完整的字符设备能力。

::: tip 学习目标
搞懂 RTC 子系统的三层文件分工（`dev.c` / `interface.c` / `class.c`）；理解「通用 `file_operations` + 底层 `rtc_class_ops`」的契约；看清一条 `ioctl(RTC_RD_TIME)` 如何一路下钻到底层硬件回调；掌握 7.1 推荐的 `devm_rtc_allocate_device` + `devm_rtc_register_device` 两步注册法。
:::

## RTC 设备的本质：一个标准字符设备

在 Linux 眼里，RTC 首先是一个**标准的字符设备**，对外表现为 `/dev/rtc0`、`/dev/rtc1`……应用层用最普通的系统调用操作它：

```c
int fd = open("/dev/rtc0", O_RDONLY);
struct rtc_time tm;
ioctl(fd, RTC_RD_TIME, &tm);   /* 读时间 */
ioctl(fd, RTC_SET_TIME, &tm);  /* 写时间 */
ioctl(fd, RTC_ALM_SET, &alm);  /* 设闹钟 */
```

这里的 `RTC_RD_TIME` / `RTC_SET_TIME` 等命令码，定义在内核头 `include/uapi/linux/rtc.h` 里，对所有 RTC 设备通用。**通用**是关键词——正因为通用，内核才能把它们的处理逻辑收拢起来。

## 三层分工：7.1 的拆分

在 7.1 内核里，RTC 子系统的核心代码拆成了三个文件，各司其职（老内核把它们揉在一个 `rtc-dev.c` 里，7.1 拆得更干净）：

| 文件 | 职责 | 类比 |
|------|------|------|
| `drivers/rtc/dev.c` | 字符设备层：实现 `file_operations`、`ioctl` 命令分发 | 餐厅的**服务员**，面对顾客 |
| `drivers/rtc/interface.c` | 接口层：`rtc_read_time` 等包装函数，负责加锁、校验、调底层回调 | 服务员和后厨之间的**传单流程** |
| `drivers/rtc/class.c` | 设备类管理 + 注册 API（`devm_rtc_allocate_device` 等） | 给后厨**发营业执照** |

底层驱动（`rtc-snvs.c`）要做的，只是实现一组硬件回调，然后到 `class.c` 那里「领执照」。下面我们自顶向下走一遍。

## 顶层入口：`rtc_dev_fops` 与 ioctl 分发

`dev.c` 给所有 RTC 设备实现了一套**共用**的 `file_operations`，叫 `rtc_dev_fops`：

```c
/* drivers/rtc/dev.c:533 */
static const struct file_operations rtc_dev_fops = {
    .owner          = THIS_MODULE,
    .read           = rtc_dev_read,
    .poll           = rtc_dev_poll,
    .unlocked_ioctl = rtc_dev_ioctl,
    .open           = rtc_dev_open,
    .release        = rtc_dev_release,
    .fasync         = rtc_dev_fasync,
};
```

注意：这套 `file_operations` **不是某个具体 RTC 驱动写的**，而是 RTC 子系统统一提供的。每一颗 RTC 芯片驱动注册时，子系统都会用这套 fops 给它派生 `/dev/rtcN`。

核心在 `rtc_dev_ioctl`。应用层 `ioctl(fd, RTC_RD_TIME, &tm)` 进来后，它负责「翻译」这个命令。看 7.1 里 `RTC_RD_TIME` 的分支（`dev.c:329`）：

```c
/* drivers/rtc/dev.c:329 —— RTC_RD_TIME 分支（有删减） */
case RTC_RD_TIME:
    mutex_unlock(&rtc->ops_lock);

    err = rtc_read_time(rtc, &tm);     /* ← 不碰硬件，交给接口层 */
    if (err < 0)
        return err;

    if (copy_to_user(uarg, &tm, sizeof(tm)))   /* 把结果拷回用户空间 */
        err = -EFAULT;
    return err;

case RTC_SET_TIME:
    mutex_unlock(&rtc->ops_lock);
    if (copy_from_user(&tm, uarg, sizeof(tm)))
        return -EFAULT;
    return rtc_set_time(rtc, &tm);     /* ← 同样交给接口层 */
```

注意一个关键细节：`rtc_dev_ioctl` 自己**一行硬件代码都没写**。它只做两件事——解析命令码（`RTC_RD_TIME` / `RTC_SET_TIME` / `RTC_AIE_ON` …）、处理用户空间内存拷贝（`copy_to_user`/`copy_from_user`），然后把脏活儿甩给 `rtc_read_time` / `rtc_set_time` 这些接口层函数。这就是「服务员」：它知道顾客点了什么，但具体怎么做菜，它不管。

## 中间层：`interface.c` 的包装与校验

`rtc_read_time` 定义在 `interface.c`（`:110`）。它是「传单流程」：加锁、调底层回调、校验结果。

```c
/* drivers/rtc/interface.c:84 —— 真正调硬件的地方 */
static int __rtc_read_time(struct rtc_device *rtc, struct rtc_time *tm)
{
    int err;

    if (!rtc->ops)
        err = -ENODEV;
    else if (!rtc->ops->read_time)        /* 没实现 read_time？拒绝 */
        err = -EINVAL;
    else {
        memset(tm, 0, sizeof(struct rtc_time));
        err = rtc->ops->read_time(rtc->dev.parent, tm);  /* ← 调底层回调！ */
        if (err < 0)
            return err;
        rtc_add_offset(rtc, tm);
        err = rtc_valid_tm(tm);           /* 闰年/月份合法性校验 */
    }
    return err;
}

/* drivers/rtc/interface.c:110 —— 加锁包装 */
int rtc_read_time(struct rtc_device *rtc, struct rtc_time *tm)
{
    int err;

    err = mutex_lock_interruptible(&rtc->ops_lock);  /* 串行化访问 */
    if (err)
        return err;

    err = __rtc_read_time(rtc, tm);
    mutex_unlock(&rtc->ops_lock);

    trace_rtc_read_time(rtc_tm_to_time64(tm), err);
    return err;
}
```

最关键的是 `__rtc_read_time` 第 94 行那一声：

```c
err = rtc->ops->read_time(rtc->dev.parent, tm);
```

这一行，就是「服务员把订单递进后厨」的瞬间。`rtc->ops->read_time` 是个函数指针——它指向谁，就由谁来做这道菜。在 `rtc-snvs.c` 里，它指向 `snvs_rtc_read_time`；换成 PCF8563，它就指向 `pcf8560_rtc_read_time`。**上层完全一样，下层各凭本事**，这就是分层带来的复用。

`interface.c` 还顺手做了三件有价值的事：

1. **加锁**（`ops_lock`）：防止两个进程同时读时间把硬件搞乱。
2. **校验**（`rtc_valid_tm`）：读出来的 `tm` 合不合法（月份 1-12、闰年……），不合法会打 `dev_dbg`。
3. **offset / trace**：支持时钟微调偏移、留 tracepoint 供调试。

::: info 为什么中间要隔一层 interface.c？
你可能会问：`dev.c` 里直接调 `rtc->ops->read_time` 不就行了，干嘛非要绕一层 `rtc_read_time`？因为这层负责的是**与硬件无关的策略**——加锁、校验、范围检查、偏移、trace。这些逻辑对所有 RTC 都一样，放底层驱动里会重复 N 次。`interface.c` 把它们收口，底层驱动只管「裸读硬件」，干净利落。
:::

## 底层契约：`rtc_class_ops`

那么底层驱动到底要实现什么？答案是一张「菜单」——`rtc_class_ops`（`include/linux/rtc.h:59`）：

```c
/* include/linux/rtc.h:59 —— 底层驱动要填的「菜单」 */
struct rtc_class_ops {
    int (*ioctl)(struct device *, unsigned int, unsigned long);
    int (*read_time)(struct device *, struct rtc_time *);     /* 读时间 */
    int (*set_time)(struct device *, struct rtc_time *);      /* 写时间 */
    int (*read_alarm)(struct device *, struct rtc_wkalrm *);  /* 读闹钟 */
    int (*set_alarm)(struct device *, struct rtc_wkalrm *);   /* 设闹钟 */
    int (*proc)(struct device *, struct seq_file *);
    int (*alarm_irq_enable)(struct device *, unsigned int enabled); /* 闹钟中断开关 */
    int (*read_offset)(struct device *, long *offset);
    int (*set_offset)(struct device *, long offset);
    int (*param_get)(struct device *, struct rtc_param *param);
    int (*param_set)(struct device *, struct rtc_param *param);
};
```

写一颗 RTC 驱动，本质上就是挑这里面需要的回调实现出来。`rtc-snvs.c` 实现了前五个核心回调（`read_time`/`set_time`/`read_alarm`/`set_alarm`/`alarm_irq_enable`），下一节我们逐个看。`read_offset`/`param_*` 这些是后加的高级特性，snvs 没用到。

这些回调挂在 `rtc_device` 结构体里（`include/linux/rtc.h:93` 的 `const struct rtc_class_ops *ops` 成员）。每个 RTC 设备在内核里都有一个 `rtc_device`，它就是这颗 RTC 的「身份证」。

## 注册：allocate + register 两步走

菜单填好了，怎么把 RTC 设备「执照」领下来？7.1 推荐的是**两步法**（也是 `rtc-snvs.c` 用的）：

```c
/* 第一步：分配一个 rtc_device（此时还没注册） */
struct rtc_device *rtc = devm_rtc_allocate_device(dev);

/* 第二步：填好 ops 等字段，再注册 */
rtc->ops = &snvs_rtc_ops;          /* 挂上你的「菜单」 */
rtc->range_max = U32_MAX;          /* 这颗 RTC 能表示的最大秒数 */
devm_rtc_register_device(rtc);     /* 真正注册，派生 /dev/rtcN */
```

两步法的好处是：你能在 `allocate` 和 `register` 之间设置 `ops`、`range_max` 这些字段。`devm_rtc_register_device` 其实是个宏（`rtc.h:246`），展开成 `__devm_rtc_register_device(THIS_MODULE, rtc)`。

::: warning ⚠️ 老教程里的 `devm_rtc_device_register` 已经 deprecated
很多老教材（和网上文章）还在用一步到位的 `devm_rtc_device_register(dev, name, ops, THIS_MODULE)`。这个函数在 7.1 的 `class.c:457` 还在，但注释写得明明白白：**「This function is deprecated, use devm_rtc_allocate_device and ...」**。它内部其实就是 `allocate` + 帮你设 `ops` + `register` 的语法糖。新驱动请用两步法，和老教材区分开。
:::

注意所有函数都带 `devm_` 前缀——设备托管。驱动卸载时内核自动回收，不用你手写 `rtc_device_unregister`，这点和 [03_platform_led](../03_platform_led_driver/) 里讲的 `devm_` 思想一脉相承。

## 一条完整的调用链

把上面几层串起来，一次「读时间」的完整路径是这样的：

```
应用层：ioctl(fd, RTC_RD_TIME, &tm)
   │
   ▼  （标准字符设备接口）
dev.c：rtc_dev_ioctl  →  case RTC_RD_TIME
   │                        （解析命令、copy_to_user）
   ▼
interface.c：rtc_read_time → __rtc_read_time
   │                        （加锁、校验 rtc_valid_tm）
   ▼
底层回调：rtc->ops->read_time(...)  ← 你/原厂写的代码
   │
   ▼
rtc-snvs.c：snvs_rtc_read_time  （regmap 读 SNVS 计数器）
```

上层三层（`dev.c` / `interface.c` / `class.c`）对所有 RTC 完全一样，是子系统提供的；只有最底下那一格 `snvs_rtc_read_time` 是 i.MX6U 专属的。**分层把「不变的通用逻辑」和「多变的硬件细节」彻底切开**，这正是 Linux 驱动框架的核心美学。

## 小结

这一节我们理清了 RTC 子系统的分层：`dev.c` 当服务员（`file_operations` + `ioctl` 分发），`interface.c` 当传单流程（加锁 + 校验 + 调回调），`class.c` 发执照（注册 API），底层驱动只管填 `rtc_class_ops` 这张菜单。一条 `ioctl(RTC_RD_TIME)` 从应用层一路下钻，最后落到 `rtc->ops->read_time` 这个函数指针上。

带着这张地图，下一节我们正式钻进 `rtc-snvs.c`，看原厂是怎么把这张菜单填满、又是怎么用 regmap 操作 SNVS 寄存器的。

---

<ChapterNav variant="sub">
  <ChapterLink href="01_introduction.md" variant="sub">← 架构概览</ChapterLink>
  <ChapterLink href="03_snvs_driver_analysis.md" variant="sub">rtc-snvs.c 逐段拆解 →</ChapterLink>
</ChapterNav>
