# 23_tutorial_rtc_snvs

RTC（SNVS）「分析型」教程配套。**本章不含可编译的内核驱动 `.ko`** —— RTC 驱动复用主线
`third_party/linux_mainline/drivers/rtc/rtc-snvs.c`，默认编进内核、开机自动 probe，无需
`insmod`。

## 配套产物

| 文件 | 位置 | 作用 |
|------|------|------|
| `rtc_alarm_demo.c` | `driver/application/rtc_snvs/` | 用户空间 alarm 一次性中断验证程序 |
| 板级设备树 | `driver/device_tree/alpha-board/23_tutorial_rtc_snvs/` | 确认 `snvs_rtc` 启用（默认即 okay） |

> 这个 `alpha-board/` 目录下**没有** `.c` 驱动、也没有内核模块 `Makefile`，因为本章根本不需要
> 自己写驱动。这是和 `20_tutorial_ap3216c_iic` / `21_tutorial_icm20608_spi` 那些「从零写」
> 章节的本质区别，详见教程
> [06 节](../../../document/tutorial/driver/10_rtc_snvs_driver/06_build_and_test.md)。

## 编译 alarm demo

app 在 `driver/application/rtc_snvs/`，用 CMake 或直接交叉编译：

```bash
# 方式一：直接交叉编译
arm-none-linux-gnueabihf-gcc -O2 -Wall \
    driver/application/rtc_snvs/rtc_alarm_demo.c -o rtc_alarm_demo

# 方式二：CMake（参考 driver/application/ap3216c）
cd driver/application/rtc_snvs && mkdir build && cd build
cmake -DCMAKE_TOOLCHAIN_FILE=<你的 arm 工具链.cmake> ..
make
```

## 上板验证（详见教程 06 节）

```bash
# 1. 确认主线 RTC 就绪
ls /dev/rtc0 && cat /proc/driver/rtc    # name 应为 snvs_rtc

# 2. 读写时间（设完系统时间记得同步进 RTC）
date -s "2026-06-23 14:30:00" && hwclock --systohc
hwclock --show

# 3. alarm 一次性中断 demo（5 秒后触发，read 阻塞到点返回）
./rtc_alarm_demo /dev/rtc0 5

# 4. 断电走时验证（纽扣电池续命）：拔电等待 → 重启 → 时间继续走
hwclock --show
```

## 设备树

`imx6ull-aes-23_tutorial_rtc_snvs.dts` 里 `&snvs_rtc { status = "okay"; };` 只是**显式确认**
—— `snvs-rtc-lp` 节点在 `imx6ul.dtsi` 里默认就是启用的（没有 `status` 属性等价于
`status = "okay"`），板级 dts 实际一行硬件配置都不用加。留着是为了和其它章节 dts 风格统一，
也方便你改成 `disabled` 做对比实验。
