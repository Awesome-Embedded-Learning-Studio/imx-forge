---
title: 启用主线 goodix 与验证
---

# 启用主线 goodix 与验证 —— evtest 与 tslib 多点测试

这一节上板。和 RTC 章一样，**没有 `.ko` 可编译**——`goodix.c` 默认编进内核、开机自动 probe（alpha 板 defconfig 已开 `CONFIG_TOUCHSCREEN_GOODIX=y`）。我们要做的是：确认它已经驱动起 GT9147，然后用现成的 `evtest`（看原始 input 事件）和 `tslib`（校准 + 多点测试）验证多点触摸。

::: tip 学习目标
在 alpha 板上确认主线 goodix 已驱动 GT9147；用 `evtest` 看到多手指的 `ABS_MT_*` 事件流；移植 `tslib` 并用 `ts_calibrate` 校准、`ts_test_mt` 五指同测；掌握触摸无响应时的排查思路。
:::

## 第一步：确认 goodix 已 probe

[05 节](05_device_tree.md) 末尾的命令再确认一遍，重点是找到 `/dev/input/eventN`：

```bash
cat /proc/bus/input/devices | grep -A6 -i goodix
# N: Name="Goodix Capacitive TouchScreen"
# H: Handlers=event0          ← 记住 event0（你的板子可能是别的号）
# B: PROP=2                   ← INPUT_PROP_DIRECT（直接输入设备）

dmesg | grep -i goodix
# Goodix-TS 2-005d: ID 9147, version: 0000    ← I2C2 上的 0x5d，芯片 ID 9147
```

`Name` 是 Goodix、`ID 9147`，就说明 [03 节](03_goodix_driver_analysis.md) 拆的那颗驱动已经在 GT9147 上跑起来了。下面所有操作针对这个 `/dev/input/event0`。

如果没看到 Goodix 设备，先查：

```bash
# I2C 层面：0x5d 这个设备在不在
ls /sys/bus/i2c/devices/ | grep 005d        # 2-005d 应该存在
# 内核配置
zcat /proc/config.gz | grep GOODIX          # CONFIG_TOUCHSCREEN_GOODIX=y
```

## evtest：看多手指的原始事件

`evtest` 是最直接的验证工具，它把 input 设备上报的每个事件实时打印出来。板子上没有就从 buildroot/发行版装一个，或交叉编译（源码在 https://gitlab.freedesktop.org/libevdev/evtest ）。

```bash
evtest /dev/input/event0
# Event: time ..., type 3 (EV_ABS), code 2f (ABS_MT_SLOT), value 0
# Event: time ..., type 3 (EV_ABS), code 39 (ABS_MT_TRACKING_ID), value 45
# Event: time ..., type 3 (EV_ABS), code 35 (ABS_MT_POSITION_X), value 400
# Event: time ..., type 3 (EV_ABS), code 36 (ABS_MT_POSITION_Y), value 300
# Event: time ..., type 3 (EV_ABS), code 34 (ABS_MT_WIDTH_MAJOR), value 8
# ... (sync 报文) ...
```

手指按上去、移动、抬起，你会看到一连串事件。重点观察 [02 节](02_input_framework.md) 讲的 Type B 时序：

- **按下**：先 `ABS_MT_SLOT 0`（选抽屉）→ `ABS_MT_TRACKING_ID 45`（分配非负 ID，表示按下）→ `ABS_MT_POSITION_X/Y`（坐标）。
- **移动**：同一 slot 继续报新的 `ABS_MT_POSITION_X/Y`，`TRACKING_ID` 不变。
- **抬起**：`ABS_MT_SLOT 0` → `ABS_MT_TRACKING_ID -1`（[04 节](04_driver_layer.md) 说的 `DROP_UNUSED` 自动处理）。

**多指测试**：两根、三根手指同时按，你会看到 `ABS_MT_SLOT` 在 0、1、2 之间切换，每个 slot 独立的 `TRACKING_ID` 和坐标——这就是多点触摸。能稳定区分多指，说明 GT9147 + goodix 的 Type B 链路完全通了。

## tslib 移植与校准

`evtest` 只看原始事件，真正要用触摸（比如给 Qt 应用当输入），得经过 `tslib` 做校准和滤波。tslib 的完整移植流程见正点原子教程第 64.4 节，这里给关键步骤。

**交叉编译 tslib**（在主机上）：

```bash
# 下载 tslib 源码（如 tslib-1.21），配置交叉编译
./autogen.sh
./configure --host=arm-linux-gnueabihf --prefix=$PWD/_install
make && make install
# 把 _install/ 下的 lib/ 和 etc/ 拷到板子根文件系统对应位置
```

**板子上配置环境变量**（`/etc/profile` 或手动 export）：

```bash
export TSLIB_TSDEVICE=/dev/input/event0      # 触摸设备节点
export TSLIB_CONFFILE=/etc/ts.conf            # tslib 配置
export TSLIB_PLUGINDIR=/usr/lib/ts            # 插件目录
export TSLIB_CALIBFILE=/etc/pointercal        # 校准结果
export TSLIB_CONSOLEDEVICE=none
export TSLIB_FBDEVICE=/dev/fb0                # framebuffer（校准画面要用）
```

::: warning ⚠️ 绕过 LCD 的话，tslib 校准需要显示
`ts_calibrate` 会在屏幕上画校准十字、让你点，依赖 framebuffer（`/dev/fb0`）。本章我们绕过了 LCD 驱动教程，如果你还没点亮屏幕，可以先用 `evtest` 验证触摸本身没问题；等 LCD 章就绪后再回来做 tslib 校准和 `ts_test_mt`。触摸驱动和显示驱动是解耦的，可以分别验证。
:::

**校准 + 多点测试**：

```bash
ts_calibrate        # 屏幕上点 5 个十字，生成 pointercal
ts_test_mt          # 多点测试程序：五指同按，画板上看每个手指的轨迹
```

`ts_test_mt` 能同时追踪多个手指、各自画线，这是验证「多点触控端到端可用」最直观的方式。

## （可选）hexdump 解析原始字节

想看看 input 事件在字节级长什么样，可以用 `hexdump` 直接读设备节点：

```bash
hexdump -e '6/2 "%04x " "\n"' /dev/input/event0
```

Linux input 事件是 `struct input_event`（时间戳 + type + code + value），`hexdump` 能把这几个字段按小端十六进制打出来。配合 [02 节](02_input_framework.md) 的事件码（`EV_ABS=3`、`ABS_MT_SLOT=0x2f`、`ABS_MT_TRACKING_ID=0x39`、`ABS_MT_POSITION_X=0x35`），你能逐字节还原一帧触摸数据。正点原子第 64.3 节有详细的字节级解析，可参考。

## 排错速查

| 现象 | 排查 |
|------|------|
| 没有 Goodix input 设备 | `ls /sys/bus/i2c/devices/2-005d` 在不在；dmesg 看 `goodix_ts_probe` 有没有报错（I2C 通信失败？） |
| probe 报 `I2C communication failure` | 复位引脚 `reset-gpios` 没生效，或 IC 没上电；检查 `irq-gpios` 命名（[05 节](05_device_tree.md) 那个 `interrupt-gpios` 坑） |
| 单指能用、多指分不开 | 检查 `input_mt_init_slots` 的 `max_touch_num`、IC 配置寄存器的最大触摸点数 |
| 坐标方向不对（X/Y 颠倒、翻转） | 在设备树加 `touchscreen-swapped-x-y` / `touchscreen-inverted-x/y`，不用改驱动 |
| 中断死活不触发 | 试试轮询模式（临时把设备树 `interrupts` 注释掉，goodix 会走 [04 节](04_driver_layer.md) 的轮询回退），排除硬件中断引脚问题 |
| `evtest` 有事件、`tslib` 不响应 | tslib 环境变量没配对（尤其 `TSLIB_TSDEVICE`）、或 event interface 配置（`CONFIG_INPUT_EVDEV`） |

## 小结

这一节我们在 alpha 板上把主线 goodix 验证通了：确认 GT9147 已 probe（`/dev/input/event0`、ID 9147）、用 `evtest` 看到了多手指的 Type B `ABS_MT_*` 事件流（选槽→给 ID→报坐标→抬起）、移植 `tslib` 做校准和多点测试。全程没编译一行驱动代码——`goodix.c` 默认就在内核里。

回头看，触摸这一章和 RTC 一样走了「分析型」路线：把主线这颗 1579 行的 `goodix.c` 从 input 子系统、MT 协议 Type B、threaded IRQ、configure_dev、配置校验一路拆透，再上板验证。到这里，你已经掌握了 input 子系统这块最重要的拼图——按键（[07 章](../07_input_subsystem_key/)）+ 多点触摸（本章）凑齐，再遇到任何输入设备都能举一反三。后续的模块开发、固件加载等章节，会更轻松。

---

<ChapterNav variant="sub">
  <ChapterLink href="05_device_tree.md" variant="sub">← 设备树配置</ChapterLink>
  <ChapterLink href="../modules/" variant="sub">模块开发 →</ChapterLink>
</ChapterNav>
