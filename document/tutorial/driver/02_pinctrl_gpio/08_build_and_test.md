# 编译、部署与实战测试

## 前言：见证真理的时刻

前面的章节我们讲了那么多理论和代码，说实话，不跑起来你永远不知道会不会有坑。这一章我们来编译、部署、测试驱动，看看它到底能不能工作。

## 编译驱动

### Makefile 解析

我们的驱动使用标准的内核模块 Makefile：

```makefile
obj-m := pinctrl_gpio_demo_04_driver.o

KERNELDIR := /path/to/kernel/source
PWD := $(shell pwd)

default:
    $(MAKE) -C $(KERNELDIR) M=$(PWD) modules
```

这里的关键是 `obj-m`，它告诉 kbuild 系统要把这个文件编译成内核模块。

### 交叉编译

对于嵌入式开发，我们需要使用交叉编译工具链：

```bash
# 设置交叉编译工具链
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# 设置内核源码路径
export KDIR=/path/to/imx/kernel/source

# 编译
make
```

如果一切顺利，你会看到类似这样的输出：

```
make -C /path/to/kernel M=/path/to/driver modules
make[1]: Entering directory '/path/to/kernel'
  CC [M]  /path/to/driver/pinctrl_gpio_demo_04_driver_main.o
  CC [M]  /path/to/driver/led_hw.o
  LD [M]  /path/to/driver/pinctrl_gpio_demo_04_driver.o
  MODPOST /path/to/driver/Module.symvers
  CC [M]  /path/to/driver/pinctrl_gpio_demo_04_driver.mod.o
  LD [M]  /path/to/driver/pinctrl_gpio_demo_04_driver.ko
make[1]: Leaving directory '/path/to/kernel'
```

最终生成 `.ko` 文件，这就是我们的内核模块。

⚠️ **注意**：如果你看到 `undefined reference` 之类的错误，通常是因为内核源码版本和编译工具链版本不匹配，或者某些内核配置选项没有打开。

## 编译设备树

### 修改设备树

首先，需要把我们的 pinctrl 和 GPIO 配置添加到设备树里。主线内核的设备树源文件在 `arch/arm/boot/dts/nxp/imx/` 目录下。

我们开发板的板级文件是 `imx6ull-aes.dts`（基于 `imx6ull-aes.dtsi`）。

```dts
/ {
    model = "Awesome Embedded Studio IMX6ULL Example Driver";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

    imx_aes_led {
        compatible = "imxaes_led";
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_aes_led>;
        status = "okay";
        led-gpio = <&gpio1 3 GPIO_ACTIVE_LOW>;
    };
};

&iomuxc {
    pinctrl_aes_led: led_grp {
        fsl,pins = <
            MX6UL_PAD_GPIO1_IO03__GPIO1_IO03    0x10B0
        >;
    };
};
```

### 编译设备树

设备树的编译是内核编译过程的一部分：

```bash
# 在项目根目录，编译所有已启用的设备树（输出在 out/linux）
make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=$(pwd)/out/linux dtbs
```

编译后的 `.dtb` 文件在 `out/linux/arch/arm/boot/dts/nxp/imx/` 目录下，我们关心的是 `imx6ull-aes.dtb`。

## 部署到开发板

### 文件拷贝

编译完成后，需要把文件拷贝到开发板：

```bash
# 拷贝驱动模块
scp pinctrl_gpio_demo_04_driver.ko root@board_ip:/lib/modules/

# 拷贝设备树
scp out/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb root@board_ip:/boot/
```

### 更新设备树

如果设备树文件有变化，需要重启开发板才能生效。或者，如果使用 U-Boot，可以通过 U-Boot 命令更新设备树。

## 加载驱动

### insmod 命令

在开发板上，使用 `insmod` 命令加载驱动：

```bash
insmod pinctrl_gpio_demo_04_driver.ko
```

如果一切顺利，你会看到：

```
[   95.894724] pinctrl_gpio_demo_04_driver: loading out-of-tree module taints kernel.
[   95.895579] === Pin Control And GPIO Demo ===
[   95.895626] dtsled node has been found!
[   95.895638] compatible = imxaes_led
[   95.895654] status = okay
[   95.895706] Get the gpio handle: 3
[   95.895730] LED Hardware init finished!
[   95.895741] Init the User Interfaces and driver handles
[   95.895755] LED handle get the device number: major: 241, minor: 0
[   95.895778] cdev series api called success!
[   95.895848] class create success!
[   95.896419] device create success!
[   95.896444] ========================
```

### 验证设备节点

驱动加载后，应该会自动创建设备节点：

```bash
ls -l /dev/AES_LED
```

输出应该类似于：

```
crw-rw---- 1 root root 241, 0 May  3 10:23 /dev/AES_LED
```

这里的 `241` 是主设备号，`0` 是次设备号。`crw-rw----` 表示这是一个字符设备。

## 测试驱动

### 点亮 LED

```bash
printf "1" > /dev/AES_LED
```

你应该看到 LED 点亮，同时内核输出：

```
[  108.091762] Device: AES_LED called open!
[  108.092023] aes_chardev_write: cnt=1
[  108.092051] LED status: 1 (user_led_new_status='1')
[  108.092095] Device: AES_LED called close!
```

### 熄灭 LED

```bash
printf "0" > /dev/AES_LED
```

你应该看到 LED 熄灭，同时内核输出：

```
[  111.995927] Device: AES_LED called open!
[  111.996026] aes_chardev_write: cnt=1
[  111.996047] LED status: 0 (user_led_new_status='0')
[  111.996086] Device: AES_LED called close!
```

### 读取状态

```bash
cat /dev/AES_LED
```

这会输出当前的 LED 状态（`1` 或 `0`）。

## 卸载驱动

测试完成后，可以使用 `rmmod` 命令卸载驱动：

```bash
rmmod pinctrl_gpio_demo_04_driver
```

内核输出：

```
[  136.068333] === pinctrl_gpio_demo_04驱动卸载成功 ===
[  136.068995] Deinit LED Hardware
[  136.069018] ========================
```

## 常见问题排查

### 驱动加载失败

如果 `insmod` 失败，首先检查内核日志：

```bash
dmesg | tail
```

常见的错误信息：

1. **Unknown symbol**：表示缺少某些内核符号，通常是因为内核配置选项没有打开。
2. **Invalid module format**：表示内核版本不匹配，需要重新编译。
3. **Device or resource busy**：表示 GPIO 已经被其他驱动占用了。

### 设备节点没有创建

如果驱动加载成功但设备节点没有创建，检查：

1. 设备树配置是否正确（compatible、status、pinctrl-0 等）
2. `class_create` 和 `device_create` 是否成功
3. 查看 `/sys/class/` 目录下是否有相关的类

### LED 不响应

如果设备节点存在但 LED 不响应，检查：

1. GPIO 编号是否正确
2. 引脚是否被其他功能占用
3. 硬件连接是否正确
4. LED 是否是低电平有效

### 引脚冲突检测

如果怀疑引脚冲突，可以这样检测：

```bash
# 查看所有 GPIO 的使用情况
cat /sys/kernel/debug/gpio

# 查看特定 GPIO
ls /sys/class/gpio/
```

## 调试技巧

### 打开内核调试

如果需要更详细的调试信息，可以在内核配置中打开：

```
CONFIG_DEBUG_GPIO=y
CONFIG_GPIO_SYSFS=y
```

### 使用 GPIO sysfs

GPIO 子系统会在 sysfs 下导出信息：

```bash
# 导出 GPIO
echo 3 > /sys/class/gpio/export

# 设置方向
echo out > /sys/class/gpio/gpio3/direction

# 设置值
echo 1 > /sys/class/gpio/gpio3/value
echo 0 > /sys/class/gpio/gpio3/value

# 读取值
cat /sys/class/gpio/gpio3/value
```

### 查看 pinctrl 配置

pinctrl 子系统也会在 debugfs 下导出信息：

```bash
# 查看 pinctrl 配置
cat /sys/kernel/debug/pinctrl/*/pins
```

## 性能测试

如果需要测试性能，可以使用 `time` 命令：

```bash
time for i in $(seq 1 1000); do
    printf "1" > /dev/AES_LED
    printf "0" > /dev/AES_LED
done
```

这会测试 1000 次开关操作所需的时间。

## 小结

到这里，我们已经完成了从硬件原理、子系统分析、设备树配置、驱动实现到编译测试的完整流程。

说实话，驱动开发最耗时的往往不是写代码，而是调试和排错。当你遇到问题的时候，记住这几个工具：

- `dmesg`：查看内核日志
- `/sys/kernel/debug/gpio`：查看 GPIO 使用情况
- `/sys/kernel/debug/pinctrl`：查看 pinctrl 配置
- `lsmod`：查看已加载的模块
- `cat /proc/devices`：查看设备号分配

掌握了这些工具，大部分问题都能定位到。

**下一步：** 阅读 [09_kernel_comparison.md](09_kernel_comparison.md) 了解主线内核与 imx 内核的差异对比。
