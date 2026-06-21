---
title: 编译与上板测试
---

# 编译与上板测试 —— 让六轴数据活起来

驱动和设备树都就绪了，这一节我们把它们编译出来、烧到板子上、读出 ICM-20608 的真实数据。涉及 `Makefile` 和 `icm20608_app.c` 两个文件，流程和 I2C 那篇高度对称，只是测试程序多了"原始值换算成物理量"这一步。

## 驱动 Makefile

```makefile
# Makefile
KERNELDIR := $(PWD)/../../../third_party/linux-imx    # 按你的实际路径改
CURRENT_PATH := $(shell pwd)
obj-m := icm20608.o

build: kernel_modules

kernel_modules:
	$(MAKE) -C $(KERNELDIR) M=$(CURRENT_PATH) modules

clean:
	$(MAKE) -C $(KERNELDIR) M=$(CURRENT_PATH) clean
```

和 I2C 那篇一模一样，只是 `obj-m` 换成了 `icm20608.o`。同样要求 `KERNELDIR` 指向那棵配置并 `make prepare` 过的内核树。编译：

```bash
make
```

成功后得到 `icm20608.ko`。如果报 `.delay_usecs` 之类的错，回头检查你是不是抄进了老的字段名——新内核要用 `struct spi_delay delay`。

## 测试程序 icm20608_app.c

驱动 `read` 上报的是七个 `signed int` 原始值（陀螺仪 xyz、加速度 xyz、温度），测试程序要把它们按量程灵敏度换算成物理量：

```c
/* icm20608_app.c */
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char *argv[])
{
    int fd;
    signed int databuf[7];
    signed int gx, gy, gz, ax, ay, az, t;
    float gx_act, gy_act, gz_act, ax_act, ay_act, az_act, t_act;
    int ret;

    if (argc != 2) {
        printf("Usage: %s /dev/icm20608\n", argv[0]);
        return -1;
    }

    fd = open(argv[1], O_RDWR);
    if (fd < 0) {
        printf("can't open %s\n", argv[1]);
        return -1;
    }

    while (1) {
        ret = read(fd, databuf, sizeof(databuf));
        if (ret == sizeof(databuf)) {
            gx = databuf[0]; gy = databuf[1]; gz = databuf[2];
            ax = databuf[3]; ay = databuf[4]; az = databuf[5];
            t  = databuf[6];

            /* 除数由芯片实际生效的量程灵敏度决定：陀螺仪 ±2000°/s→16.4；加速度这块板
             * 上停在默认 ±2g→16384（驱动 reginit 写的 ±16g 没生效，见下文物理验证）。 */
            gx_act = (float)gx / 16.4;
            gy_act = (float)gy / 16.4;
            gz_act = (float)gz / 16.4;
            ax_act = (float)ax / 16384;
            ay_act = (float)ay / 16384;
            az_act = (float)az / 16384;
            t_act  = ((float)t - 25.0) / 326.8 + 25.0;

            printf("gx=%.2f gy=%.2f gz=%.2f °/s | ax=%.2f ay=%.2f az=%.2f g | t=%.2f °C\n",
                   gx_act, gy_act, gz_act, ax_act, ay_act, az_act, t_act);
        }
        usleep(100000);   /* 100ms */
    }

    close(fd);
    return 0;
}
```

那几个除数（16.4、16384、326.8）不是凭空来的，全由芯片**实际生效**的量程灵敏度决定：陀螺仪 ±2000°/s 对应 16.4 LSB/(°/s)，加速度这块板上停在默认 ±2g 对应 16384 LSB/g，温度换算公式来自数据手册。这里有个很容易踩的坑：驱动 `icm20608_reginit` 往 `ACCEL_CONFIG` 写的明明是 `0x18`（±16g、2048 LSB/g），但实测它没生效、芯片停在默认 ±2g——所以 app 必须按 16384 换算，静止 `az` 才会是 1g 而不是离谱的 ~8g。**除数对齐的是芯片真实的量程，不是代码注释里写的那个**，这就是为什么要拿物理量校准。

I.MX6U 带 VFP/NEON 浮点单元，编译时可以加 `-mfloat-abi=hard` 启用硬浮点，提升浮点性能：

```bash
arm-linux-gnueabihf-gcc icm20608_app.c -o icm20608_app -mfloat-abi=hard
```

## 上板测试

把驱动模块（`21_tutorial_icm20608_spi_driver.ko`）和 `icm20608_app` 拷到板子。先确认设备树层面内核已经"看见"这颗芯片——ECSPI3 一旦注册，`/sys/bus/spi/devices/` 里就会多出一个设备，总线号取决于注册顺序（这块板上 `ecspi3` 对应的是 `spi2.0`，因为 `imx6ul.dtsi` 的 alias 把 `spi2` 指给了 `ecspi3`）：

```bash
ls /sys/bus/spi/devices/
# spi2.0  spi4.0  spi5.0      ← spi2.0 就是 icm20608（另外两个是 NOR flash 和 74hc595）

cat /sys/bus/spi/devices/spi2.0/modalias
# spi:imxaes,icm20608
```

::: tip 那条 `error -ENODEV: can't get the TX DMA channel!` 别慌
ECSPI3 在 `imx6ul.dtsi` 里默认带 `dmas` 属性，本章的板级 dts 已经把它删掉、让 spi-imx 走 PIO。但启动日志里仍会冒出一条 `spi_imx 2010000.spi: error -ENODEV: can't get the TX DMA channel!`——它是 spi-imx 的 `dev_err_probe` 打的，看着像报错，其实只是告知"没有 DMA、改用 PIO"。`-ENODEV` 不会让 probe 失败（只有 `-EPROBE_DEFER` 才会中断 probe），ECSPI3 照常注册，这条可以直接忽略。
:::

加载驱动：

```bash
insmod /lib/modules/21_tutorial_icm20608_spi_driver.ko
```

`dmesg` 里能看到 probe 跑通：

```text
icm20608 spi2.0: icm20608 hardware initialized
icm20608 spi2.0: icm20608 probe success
```

`/dev/icm20608` 出现后，跑测试程序：

```bash
/home/icm20608_app /dev/icm20608
```

屏幕开始刷真实数据：

```text
gx=1.34 gy=-5.49 gz=1.10 deg/s | ax=-0.01 ay=0.03 az=0.99 g | t=29.97 C
gx=-1.83 gy=-3.72 gz=-0.49 deg/s | ax=-0.01 ay=0.03 az=0.99 g | t=29.97 C
gx=-0.37 gy=-5.73 gz=0.37 deg/s | ax=-0.01 ay=0.03 az=1.00 g | t=29.67 C
...
```

## 拿物理世界验证

六轴数据光看数字不够，得用动作验证。先把板子**静止放桌上**：陀螺仪三轴都接近 0（实测 `gx/gy≈-3~-6 deg/s`、`gz≈0`，这点小零偏是 MEMS 陀螺仪的常态）；加速度方面，水平放置时地球引力集中在 Z 轴，所以 **`az` 稳定在 1g 附近**（实测 `≈0.99 g`），`ax/ay≈0`；温度稳定在室温（实测 `t≈30°C`）。接着**晃动/转动板子**——陀螺仪立刻飙升，实测一次剧烈甩动能把 `gx` 推到 `-978 deg/s`、`gy` 推到 `+804 deg/s`，停下后又回落到个位数；加速度计也会跟着你施加的力剧烈波动。角速度和加速度都被正确翻译成数字，这条 SPI 数据链路是真的通了。

翻转板子还能看个有意思的现象：让 X 轴朝下，`ax` 就升到 ~1g、`az` 回落到 0——重力分量始终落在"指向地心"的那根轴上。这是验证三轴方向接对没接反的最直接办法。

如果静止时 `az` 明显偏离 1g（成倍地偏大或偏小），多半是加速度量程灵敏度除数和芯片实际量程对不上——回去核对 `icm20608_reginit` 写的量程是否真的生效、app 的除数是否匹配；如果数据乱跳或全 0，按这个顺序排查：先确认 `/sys/bus/spi/devices/` 下有设备（设备树层面 OK），再 `dmesg | grep icm20608` 看 `probe` 有没有跑完、`spi_setup` 有没有调，最后用示波器抓 SCLK/MOSI/MISO/CS 四根线有没有波形、CS 有没有正确拉低。

## 小结

这一节我们编译驱动、写测试程序、上板读到了真实的六轴 + 温度数据。回头看，整条 SPI 驱动链路和 I2C 高度对称：设备树描述硬件（这次多了 `cs-gpios` 管片选）→ SPI 核心实例化 `spi_device` → `compatible` 匹配上 `spi_driver` → `probe` 里 `spi_setup` 固化模式、注册字符设备、初始化芯片 → 用户空间 `read` 触发 `spi_write_then_read` → 最终落到主机驱动的 `transfer_one`、由核心用 `cs-gpios` 控制片选把比特发到线上。

到这儿，I2C 和 SPI 这两条最重要的串行总线驱动我们都用现代 API 重写通了。你会真切地发现：底层时序天差地别，但内核那套"分层 + 匹配 + 结构体契约"的设计哲学，在两条总线上惊人地一致——学会了这一套，再遇到别的子系统，你也能举一反三。

---

<ChapterNav variant="sub">
  <ChapterLink href="05_device_tree.md" variant="sub">← 设备树配置</ChapterLink>
  <ChapterLink href="../modules/" variant="sub">模块开发 →</ChapterLink>
</ChapterNav>
