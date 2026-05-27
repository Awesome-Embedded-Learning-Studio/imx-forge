# 编译和测试 - 验证你的驱动

终于到了最后一步，编译、加载、测试我们的 Input 子系统按键驱动。说实话，写驱动最爽的时刻就是 `insmod` 后看到 `dmesg` 里出现"device registered"的那行，然后按一下按键，应用程序里收到事件。那一刻你会觉得之前踩的所有坑都值了。

## 编译驱动

首先进入驱动目录：

```bash
cd /home/charliechen/imx-forge/driver/19_tutorial_key_input/alpha-board
```

确保内核源码路径正确（Makefile 中的 `KDIR`），然后编译：

```bash
make
```

如果一切顺利，你应该看到：

```
make -C /path/to/kernel M=/path/to/driver modules
make[1]: Entering directory '/path/to/kernel'
  CC [M]  /path/to/driver/19_tutorial_key_input_driver_main.o
  MODPOST /path/to/driver/Module.symvers
  CC [M]  /path/to/driver/19_tutorial_key_input_driver.mod.o
  LD [M]  /path/to/driver/19_tutorial_key_input_driver.ko
make[1]: Leaving directory '/path/to/kernel'
```

生成的 `.ko` 文件就是我们的驱动模块。

::: tip
如果编译失败，检查内核版本是否匹配、Makefile 中的路径是否正确。常见错误是 `KDIR` 指向了错误的内核目录。
:::

## 更新设备树

驱动的设备树配置在：

```
/home/charliechen/imx-forge/driver/device_tree/alpha-board/19_tutorial_key_input/imx6ull-aes-key.dts
```

编译设备树：

```bash
cd /home/charliechen/imx-forge/driver/device_tree/alpha-board/19_tutorial_key_input
dtc -I dts -O dtb -o imx6ull-aes-key.dtb imx6ull-aes-key.dts
```

将 `.dtb` 文件复制到开发板的 `/boot` 目录（具体路径取决于你的系统）：

```bash
cp imx6ull-aes-key.dtb /boot/imx6ull-aes-key.dtb
```

::: info
设备树更新后需要重启开发板才能生效。有些系统支持运行时设备树 overlays，但这不是标准做法，教程里不涉及。
:::

## 加载驱动

重启开发板后，将 `.ko` 文件复制到开发板，然后加载：

```bash
insmod 19_tutorial_key_input_driver.ko
```

查看内核日志，确认驱动加载成功：

```bash
dmesg | tail -20
```

你应该看到类似输出：

```
[  123.456] input_key_probe: probing device
[  123.457] input_key_probe: device registered (IRQ 52)
[  123.458] input_key_probe: input device: imxaes-key
```

如果看到错误信息，根据提示排查：
- `key_hw_init failed`：GPIO 配置有问题，检查设备树
- `failed to register input device`：Input 子系统注册失败，检查设备能力设置

## 验证设备节点

驱动加载成功后，evdev Handler 会自动创建设备节点。先确认设备存在：

```bash
ls -l /dev/input/event*
```

你应该看到新设备（假设是 `event0`）：

```
crw-rw---- 1 root input 13, 64 ... /dev/input/event0
```

::: warning
如果看不到新设备，检查内核日志中是否有 `evdev` 相关的错误。某些嵌入式系统可能没有启用 evdev Handler，需要在内核配置中启用 `CONFIG_INPUT_EVDEV`。
:::

## 找到你的设备

系统可能有多个输入设备，找到你的按键设备：

```bash
cat /proc/bus/input/devices | grep -A 5 "imxaes-key"
```

输出：

```
I: Bus=0019 Vendor=0001 Product=0001 Version=0100
N: Name="imxaes-key"
P: Phys=imxaes-key/input0
S: Sysfs=/devices/platform/imxaes-key/input/input0
U: Uniq=
H: Handlers=event0
B: PROP=0
B: EV=3
B: KEY=100000 0 0 0
```

`Handlers=event0` 表示设备对应 `/dev/input/event0`。

## 编写测试程序

编写一个简单的测试程序来验证按键事件：

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>

int main(void)
{
    const char *dev = "/dev/input/event0";
    int fd = open(dev, O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Listening on %s (Ctrl+C to exit)...\n", dev);
    printf("Press the button...\n");

    struct input_event ev;
    while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_KEY && ev.code == KEY_ENTER) {
            printf("Key: %s\n", ev.value ? "PRESSED" : "RELEASED");
        }
    }

    close(fd);
    return 0;
}
```

保存为 `test_input_key.c`，编译运行：

```bash
gcc -o test_input_key test_input_key.c
./test_input_key
Listening on /dev/input/event0 (Ctrl+C to exit)...
Press the button...
Key: PRESSED
Key: RELEASED
```

::: info
如果用户权限不足，检查 `/dev/input/event0` 的权限。可以用 `sudo` 运行，或者将用户加入 `input` 组。
:::

## 卸载驱动

测试完成后，可以卸载驱动：

```bash
rmmod 19_tutorial_key_input_driver
```

查看内核日志确认卸载成功：

```bash
dmesg | tail -5
```

你应该看到：

```
[  456.789] input_key_remove: removing device
[  456.790] input_key_remove: device removed
```

设备节点 `/dev/input/event0` 也会被自动删除。

## 常见问题排查

**问题 1：加载驱动后没有设备节点**

可能原因：
- 设备树配置不匹配（`compatible` 字符串不一致）
- GPIO 配置错误
- 内核没有启用 evdev Handler

**问题 2：测试程序能打开设备，但按键没有事件**

可能原因：
- GPIO 中断没有触发（检查 `cat /proc/interrupts`）
- 消抖时间太长（试试减小 `DEBOUNCE_MS`）
- 中断处理函数没有正确调度工作

**问题 3：事件太多（抖动）**

可能原因：
- 消抖时间太短（增加 `DEBOUNCE_MS`）
- `mod_delayed_work()` 没有正确使用（检查是否真的重新调度）

::: tip
调试时在驱动里加 `pr_info()` 打印关键信息：中断发生、工作函数执行、状态变化。这样能快速定位问题。
:::

## 与桌面环境集成（可选）

如果你的系统有 X11：

```bash
# X11 应该已经识别设备
xinput list | grep imxaes-key

# 设置按键映射
xmodmap -e "keycode 36 = Return"

# 测试：在终端里按下按键，应该产生回车
```

如果有 Qt：

```cpp
// 任意 Qt widget
void MyWidget::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Return) {
        qDebug() << "Enter key pressed from imxaes-key!";
    }
}
```

## 章节总结

这一章我们完成了整个流程：编译驱动、更新设备树、加载模块、验证设备节点、编写测试程序。Input 子系统驱动的测试比字符设备驱动简单得多，因为有标准的事件格式。

学完整个教程，你已经掌握了：
1. Input 子系统的分层架构
2. `input_dev` 的分配和注册
3. 事件报告机制（`input_report_key`、`input_sync`）
4. `delayed_work` 实现消抖
5. 用户空间集成（应用程序开发）

这就是"正统"的 Linux 按键驱动写法。以后遇到任何输入设备需求，你都知道该怎么做了。

## 教程回顾

整个按键驱动系列教程走下来，我们经历了：
1. 字符设备基础（`open`/`read`/`write`）
2. 中断与工作队列
3. Platform 驱动框架
4. GPIO 子系统（`gpiod_*` API）
5. 消抖实现
6. Input 子系统

这些是嵌入式 Linux 驱动开发的核心技能。恭喜你完成了这个系列！

---

**相关文档**：
- [Input 子系统架构](02_input_architecture.md)
- [延时消抖](04_delayed_debounce.md)
- [用户空间集成](05_userspace_integration.md)

**教程完成！** 你已经掌握了 Linux Input 子系统按键驱动的完整开发流程。
