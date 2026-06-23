---
title: 启用主线 RTC 与验证
---

# 启用主线 RTC 与验证 —— hwclock、date 与 alarm

这一节我们上板。和前面 AP3216C、ICM-20608 那两章「编译 `.ko` → `insmod` → 跑测试程序」的套路不同，RTC 这章**没有 `.ko` 可编译**——`rtc-snvs.c` 默认就编进内核了。所以这里的「验证」全是用户空间的事：用 `hwclock`、`date` 操作时间，用一个 alarm demo 验证闹钟中断，再拔电测一次纽扣电池的续命能力。

::: tip 学习目标
在 alpha 板上确认 `/dev/rtc0` 就绪；用 `hwclock`/`date` 读写硬件时间、搞清「系统时间」与「硬件时间」的关系；编译运行 `rtc_alarm_demo` 验证闹钟一次性中断；做一次断电走时验证，亲眼看纽扣电池续命；理解开机时 `hctosys` 如何把硬件时间同步进系统。
:::

## 第一步：确认 RTC 就绪

开机进系统，先确认主线 RTC 已经 probe：

```bash
ls -l /dev/rtc*
# crw-rw----    1 root     root      254,   0 Jan  1 00:00 /dev/rtc0

cat /proc/driver/rtc
# rtc_time        : 00:00:42
# rtc_date        : 2000-01-01
# alrm_time       : 00:00:00
# alrm_date       : 2000-01-01
# alarm_IRQ       : no
# ...
# name            : snvs_rtc          ← 命中 rtc-snvs.c
```

`/dev/rtc0` 在、`name` 是 `snvs_rtc`，就说明 [03 节](03_snvs_driver_analysis.md) 拆的那颗驱动已经在跑了。下面所有操作都针对这个 `/dev/rtc0`。

## 读写时间：hwclock 与 date

先理清两个概念，这是新手最容易混的：

- **硬件时间（RTC）**：SNVS 里那个一直在走的计数器，靠纽扣电池维持，断电不丢。
- **系统时间**：内核内存里的时间（`date` 看到的），开机时从 RTC 拷一份过来，关机就没了。

`hwclock` 是在两者之间搬数据的工具：

```bash
# 读硬件时间
hwclock --show            # 或 hwclock -r
# 2000-01-01 00:01:23.456789+00:00

# 读系统时间
date
# Thu Jan  1 00:01:25 UTC 2000

# 把系统时间写进硬件（system → hardware）
date -s "2026-06-23 14:30:00"     # 先设好系统时间
hwclock --systohc                 # 再同步到 RTC（简称 -w）

# 把硬件时间读进系统（hardware → system）
hwclock --hctosys                  # 简称 -s
```

::: warning ⚠️ 别用 `date -s` 设完就以为万事大吉
`date -s` 只改**系统时间**（内存里的），断电就丢。要让时间持久化，设完系统时间必须跟一句 `hwclock --systohc`，把它写进 RTC。很多人调完时间、重启发现又回到 2000 年，就是因为漏了这一步。
:::

::: tip 时区
`hwclock`/RTC 存的是 **UTC**（或更准确说，存的是「从 1970 起的秒数」，与本地时区无关）。`date` 显示的可能是本地时区（取决于 `TZ`）。要显示北京时间，设 `export TZ=CST-8` 或装 `tzdata`。时区只影响「显示」，不影响 RTC 里存的秒数。
:::

## alarm 闹钟 demo：验证一次性中断

[04 节](04_driver_layer.md) 我们讲了 alarm 的 one-shot 设计，现在用程序验证它。配套代码在 `driver/application/rtc_snvs/rtc_alarm_demo.c`，核心逻辑是：设一个 N 秒后的闹钟 → 阻塞 `read` 等中断 → 到点被唤醒。

```c
/* rtc_alarm_demo.c —— 核心（完整可编译版见 driver/application/rtc_snvs/） */
#define _GNU_SOURCE                     /* timegm */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/rtc.h>

int main(int argc, char *argv[])
{
    int fd, ret, secs;
    struct rtc_time now;
    struct rtc_wkalrm alarm;
    struct tm tm;
    unsigned long fired;

    if (argc != 3) {
        printf("Usage: %s /dev/rtcN <seconds>\n", argv[0]);
        return 1;
    }
    secs = atoi(argv[2]);

    fd = open(argv[1], O_RDWR);
    if (fd < 0) { perror("open rtc"); return 1; }

    /* 1. 读当前硬件时间 */
    ioctl(fd, RTC_RD_TIME, &now);

    /* 2. 当前时间 + secs 秒，用 timegm 规范化（处理秒→分→时进位；RTC 存 UTC） */
    memcpy(&tm, &now, sizeof(tm));
    tm.tm_sec += secs;
    tm.tm_isdst = -1;
    timegm(&tm);
    memcpy(&alarm.time, &tm, sizeof(alarm.time));

    /* 3. 设闹钟：RTC_WKALM_SET 支持带日期的闹钟，enabled=1 同时使能中断 */
    alarm.enabled = 1;
    alarm.pending = 0;
    ioctl(fd, RTC_WKALM_SET, &alarm);
    printf("alarm armed, blocking %d s...\n", secs);

    /* 4. 阻塞 read，直到闹钟中断到来（snvs_rtc_irq_handler → rtc_update_irq 唤醒它） */
    ret = read(fd, &fired, sizeof(fired));
    if (ret < 0) { perror("read"); return 1; }
    printf("alarm fired! (%lu interrupts)\n", fired);

    close(fd);
    return 0;
}
```

完整可编译版本（含 `mktime` 调用、错误处理、`O_RDWR` 等）见配套代码。交叉编译（注意 RTC 是 `O_RDONLY` 就能 `ioctl` 设闹钟，但有些实现要 `O_RDWR`，配套代码用 `O_RDWR` 保险）：

```bash
arm-none-linux-gnueabihf-gcc rtc_alarm_demo.c -o rtc_alarm_demo
```

拷到板子运行，设一个 5 秒后的闹钟：

```bash
./rtc_alarm_demo /dev/rtc0 5
# alarm set, waiting 5 s...
# （5 秒后）
# alarm fired! (1 interrupts)
```

`read` 阻塞了 5 秒、然后返回——这就是 [04 节](04_driver_layer.md) handler 里 `rtc_update_irq` 的功劳：闹钟到期 → `LPTA` 置位 → 中断 → handler 关中断 + `rtc_update_irq` → 唤醒阻塞的 `read`。

**验证 one-shot**：紧接着再跑一次 `./rtc_alarm_demo /dev/rtc0 5`，确认它又能正常设闹钟。因为上次 handler 已经自动关了中断、demo 重新 `RTC_WKALM_SET` 又打开了。如果你把 demo 改成「设一次、连续 `read` 两次」，第二次 `read` 会永远阻塞——这就坐实了 alarm 是一次性的。

## 断电走时验证：纽扣电池续命

最有说服力的测试是断电。SNVS_LP 靠纽扣电池维持走时，我们亲眼看一遍：

```bash
# 1. 设好一个明显「未来」的时间，同步进 RTC
date -s "2026-06-23 14:30:00"
hwclock --systohc
hwclock --show          # 确认 RTC 记下了
# 2026-06-23 14:30:12.xxx

# 2. 记下此刻，然后给板子彻底断电（拔电源线，留纽扣电池）
#    去喝杯咖啡，等个 5~10 分钟

# 3. 重新上电开机，再看硬件时间
hwclock --show
# 2026-06-23 14:40:xx.xxx      ← 时间往前走了约 10 分钟，没丢！
```

如果断电期间时间在正常走（往前走了你等待的时长），说明纽扣电池 + 32.768kHz 晶振在正常续命。如果重启后时间回到 1970/2000 年，检查核心板纽扣电池有没有电、有没有焊好——这是硬件问题。

## 开机自动同步：hctosys

最后一个常见疑问：开机后 `date` 显示的时间，是怎么来的？

答案是：**开机时，系统会自动执行一次 `hwclock --hctosys`**（或等价的内核 `hctosys` 机制），把 RTC 里的硬件时间拷一份到系统时间。在 systemd 系统，这是 `systemd-timesyncd` 或 `rtc-hctosys` 服务干的；在 busybox/init 系统，通常是 `/etc/init.d/` 里一条 `hwclock -s`。

```bash
# 查看开机时谁同步了时间（systemd）
systemctl status systemd-timesyncd
# 或在 rcS/init.d 里找 hwclock
grep -r hwclock /etc/init.d/ 2>/dev/null
```

所以正确的「设一劳永逸的时间」流程是：`date -s` 设系统时间 → `hwclock --systohc` 写进 RTC → 以后每次开机，`hctosys` 自动把 RTC 时间读回系统，不用你再操心。

## 排错速查

| 现象 | 排查 |
|------|------|
| 没有 `/dev/rtc0` | `dmesg \| grep -i rtc` 看 probe 有没有报错；检查内核配置 `CONFIG_RTC_DRV_SNVS=y` |
| `name` 不是 `snvs_rtc` | 可能启用了别的 RTC（比如外挂芯片），确认 `/proc/driver/rtc` 对应 `rtc0` |
| alarm `read` 永久阻塞 | 闹钟中断没使能，或设的闹钟时间已是过去时；检查 `RTC_WKALM_SET` 的 `enabled=1` |
| 重启后时间归零 | 纽扣电池没电/没焊；或设时间后忘了 `hwclock --systohc` |
| 设的时间重启后偏差大 | 晶振频偏，可走 `read_offset`/`set_offset` 校准（snvs 未实现，需硬件晶振够准） |

## 小结

这一节我们在 alpha 板上把主线 RTC 跑通了：确认 `/dev/rtc0`、用 `hwclock`/`date` 读写时间并理清系统时间与硬件时间的关系、用 `rtc_alarm_demo` 验证了闹钟一次性中断（`read` 阻塞 → 到点唤醒）、断电验证了纽扣电池续命。全程没编译一行驱动代码——`rtc-snvs.c` 默认就在内核里干活。

回头看，RTC 这一章我们走的是「分析型」路线：不写驱动，而是把原厂这颗成熟驱动从子系统分层、regmap、47 位计数器双读、alarm 一次性中断一路拆透，再在板子上验证。读懂它，你就掌握了「分层 + 回调契约 + regmap + 中断设计」这套贯穿整个 Linux 驱动世界的思想。下一章我们用同样的方式去拆触摸（GT911/goodix），那会是一次更复杂的实战——input 子系统和多点触摸协议在等着。

---

<ChapterNav variant="sub">
  <ChapterLink href="05_device_tree.md" variant="sub">← 设备树配置</ChapterLink>
  <ChapterLink href="../modules/" variant="sub">模块开发 →</ChapterLink>
</ChapterNav>
