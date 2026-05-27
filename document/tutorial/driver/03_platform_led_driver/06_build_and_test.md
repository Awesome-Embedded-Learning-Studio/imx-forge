# 编译和测试 - 纸上得来终觉浅

## 前言：验证驱动功能

前面我们分析了代码结构、HAL 层、驱动层、设备树。但代码写出来，不测试就是一堆废字符。这一节我们实际编译并测试驱动，验证它确实能工作。

## 编译驱动

首先确认你的编译环境：交叉编译工具链（arm-linux-gnueabihf-gcc）、内核源码（与目标板运行的内核版本一致）、Makefile。

驱动的 Makefile 很简单：

```makefile
obj-m += platform_led_13_driver.o
platform_led_13_driver-objs := platform_led_13_driver_main.o led_hw.o

KERNEL_DIR := /path/to/kernel
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
```

关键点：`obj-m` 表示编译为模块（.ko 文件），`platform_led_13_driver-objs` 列出组成模块的目标文件，`-C $(KERNEL_DIR) M=$(PWD)` 是内核模块编译的标准方式。

编译命令就是 `make`。如果编译成功，会生成 `platform_led_13_driver.ko` 文件。

## 编译设备树

设备树文件是 `imx6ull-aes-16_tutorial_platform_led.dts`。编译命令：

```bash
dtc -I dts -O dtb -o imx6ull-aes-16_tutorial_platform_led.dtb imx6ull-aes-16_tutorial_platform_led.dts
```

可以反编译 DTB 检查内容：

```bash
dtc -I dtb -O dts imx6ull-aes-16_tutorial_platform_led.dtb
```

应该能看到我们的 `imx_aes_led` 节点。

## 加载驱动

```bash
insmod platform_led_13_driver.ko
```

如果成功，应该看到内核日志中有类似输出：

```
[12345.678] platform_led: probe
[12345.678] LED hardware initialized
[12345.678] platform_led probe success
```

检查设备节点是否存在：

```bash
ls -l /dev/AES_LED
```

应该看到设备节点已经创建。如果设备节点不存在，可能是设备树没有生效，或者驱动加载失败。查看 `dmesg` 可以找到错误信息。

## 测试驱动

点亮 LED：

```bash
echo '1' > /dev/AES_LED
```

LED 应该点亮。如果没反应，检查 LED 硬件连接、设备树的 GPIO 编号是否正确、`GPIO_ACTIVE_LOW` 是否符合硬件设计。

熄灭 LED：

```bash
echo '0' > /dev/AES_LED
```

LED 应该熄灭。

读取状态：

```bash
cat /dev/AES_LED
```

应该输出 `1`（如果 LED 点亮）或 `0`（如果 LED 熄灭）。

## 调试技巧

查看内核日志：

```bash
dmesg | grep -i "led"
```

检查 GPIO 状态（如果系统支持 debugfs）：

```bash
mount -t debugfs none /sys/kernel/debug
cat /sys/kernel/debug/gpio
```

应该能看到类似输出，表明 GPIO 状态正确。

::: tip 常见问题排查
如果 insmod 失败提示"Invalid module format"，说明内核版本不匹配。确保编译驱动时用的内核源码和目标板一致。如果设备节点不存在，检查驱动是否加载成功、设备树是否生效。如果写入设备节点没反应，检查 GPIO 配置是否正确、硬件连接是否正常。
:::

## 卸载驱动

```bash
rmmod platform_led_13_driver
```

如果成功，内核日志会显示设备已被移除。

## 小结

本节我们完成了驱动的编译、部署和测试。编译驱动使用内核的模块构建系统，编译设备树使用 dtc 编译器，部署到开发板后加载驱动，通过设备节点测试功能，遇到问题时用 dmesg 和 debugfs 调试。

到这里，Platform LED 驱动教程就全部完成了。恭喜你，已经掌握了嵌入式 Linux 驱动开发的核心技能！接下来可以尝试更复杂的驱动，比如蜂鸣器、按键、或者带中断的设备。

---

<ChapterNav variant="sub">
  <ChapterLink href="05_device_tree.md" variant="sub">← 设备树配置</ChapterLink>
  <ChapterLink href="../04_beep_driver/" variant="sub">蜂鸣器驱动 →</ChapterLink>
</ChapterNav>
