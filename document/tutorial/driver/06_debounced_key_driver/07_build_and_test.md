# 编译和测试 - 从源码到运行

前面我们讲了驱动的所有技术细节，现在来谈谈怎么编译和测试。说实话，写代码只是工作的一半，另一半是验证代码是否能跑起来，是否能正常工作。

## 获取源码

驱动的源码在项目仓库里：

```bash
cd driver/18_tutorial_key_debounce_driver/alpha-board/
ls
```

你会看到：
```
Makefile                           # 构建配置
key_debounce_driver_main.c        # 主驱动文件
```

## 编译驱动

在驱动目录里执行 `make`：

```bash
make
```

如果一切顺利，你会看到编译输出，最后生成 `.ko` 文件：

```
make -C /lib/modules/6.12.49-imx/build M=/path/to/driver modules
make[1]: Entering directory '/lib/modules/6.12.49-imx/build'
  CC [M]  /path/to/driver/key_debounce_driver_main.o
  MODPOST /path/to/driver/Module.symvers
  CC [M]  /path/to/driver/key_debounce_driver_main.mod.o
  LD [M]  /path/to/driver/key_debounce_driver_main.ko
make[1]: Leaving directory '/lib/modules/6.12.49-imx/build'
```

生成的 `.ko` 文件就是内核模块，可以用 `insmod` 加载。

::: tip 编译错误处理
如果编译失败，检查：
1. 内核头文件是否安装：`ls /lib/modules/$(uname -r)/build`
2. Makefile 中的路径是否正确
3. 代码语法错误（编译器会提示具体位置）
:::

## 加载驱动

驱动编译成功后，可以用 `insmod` 加载：

```bash
sudo insmod key_debounce_driver_main.ko
```

加载后，检查内核日志：

```bash
dmesg | tail -10
```

你应该看到类似这样的输出：

```
[12345.678] key_probe: probing device
[12345.679] key_hw_init: GPIO initialized successfully
[12345.680] key_hw_request_irq: IRQ 256 requested (imxaes_key_debounce)
[12345.681] key_probe: device registered as imxaes_key_debounce (major 240, IRQ 256)
```

如果看到这些，说明驱动加载成功了。

## 验证设备节点

驱动加载后，会自动创建设备节点：

```bash
ls -l /dev/imxaes_key_debounce
```

你应该看到：

```
crw-rw---- 1 root root 240, 0 ... /dev/imxaes_key_debounce
```

`c` 表示字符设备，`240` 是主设备号，`0` 是次设备号。如果设备节点不存在，检查内核日志是否有错误信息。

::: tip 权限问题
默认情况下，只有 root 可以访问设备节点。如果需要普通用户也能访问，可以修改权限：
```bash
sudo chmod 666 /dev/imxaes_key_debounce
```
或者创建一个 udev 规则自动设置权限。
:::

## 编写测试程序

让我们写一个简单的测试程序来验证驱动：

```c
/* test_key.c */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>

int main(void)
{
    int fd = open("/dev/imxaes_key_debounce", O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Press the key (Ctrl+C to exit)...\n");

    struct pollfd pfd = {
        .fd = fd,
        .events = POLLIN,
    };

    while (1) {
        int ret = poll(&pfd, 1, -1);
        if (ret < 0) {
            perror("poll");
            break;
        }

        int value;
        if (read(fd, &value, sizeof(value)) == sizeof(value)) {
            printf("Key: %s\n", value ? "PRESSED" : "RELEASED");
        }
    }

    close(fd);
    return 0;
}
```

这个程序用 `poll()` 监听按键事件，当有事件时读取并打印。

## 编译测试程序

```bash
gcc test_key.c -o test_key
```

如果编译失败，检查是否安装了 GCC：

```bash
gcc --version
```

## 运行测试

运行测试程序：

```bash
./test_key
```

然后按几次按键，你应该看到类似这样的输出：

```
Press the key (Ctrl+C to exit)...
Key: PRESSED
Key: RELEASED
Key: PRESSED
Key: RELEASED
```

每次按一次按键（按下+松开），你会看到一行 `PRESSED` 和一行 `RELEASED`。

::: tip 如果没有输出
如果没有输出，检查：
1. 设备节点权限：`ls -l /dev/imxaes_key_debounce`
2. 中断是否触发：`cat /proc/interrupts | grep imxaes`
3. 内核日志是否有错误：`dmesg | grep -i error`
:::

## 对比轮询和中断

为了验证中断方式的优势，我们可以对比轮询方式的驱动。

### CPU 占用对比

用 `top` 命令查看 CPU 占用：

```bash
# 终端一：运行测试程序
./test_key

# 终端二：查看 CPU 占用
top
```

中断方式的测试程序，即使频繁按按键，CPU 占用也应该接近 0。因为 CPU 只在中断触发和工作队列执行时才干活，大部分时间在空闲。

轮询方式的测试程序，CPU 占用会明显高一些。因为需要持续读取 GPIO，CPU 无法真正空闲。

### 功耗对比

在嵌入式设备上，功耗是一个重要指标。中断方式可以让 CPU 进入深度睡眠，只在事件发生时醒来。轮询方式需要定期唤醒，无法进入深度睡眠。

你可以用 `cat /sys/class/power_supply/battery/current_now` 查看电流消耗（如果设备支持）：

```bash
# 空闲时
cat /sys/class/power_supply/battery/current_now

# 运行轮询驱动时
cat /sys/class/power_supply/battery/current_now

# 运行中断驱动时
cat /sys/class/power_supply/battery/current_now
```

中断方式的电流消耗应该和空闲时差不多，轮询方式会明显高一些。

## 查看统计信息

卸载驱动时，会打印统计信息：

```bash
sudo rmmod key_debounce_driver_main
dmesg | tail -5
```

你会看到：

```
[23456.789] key_remove: removing device
[23456.790] key_remove: statistics - IRQs: 150, events: 5, skipped: 145
```

这个统计信息告诉我们：
- 中断触发了 150 次
- 实际报告了 5 个事件
- 145 次抖动被过滤

如果 `IRQs >> events`，说明消抖在有效工作。如果 `IRQs ≈ events × 2`，说明按键几乎没有抖动。

::: tip 反复测试
多按几次按键，观察统计信息的变化。正常情况下，`skipped` 应该远大于 `events`。如果 `skipped` 很小，可能消抖延时不够，或者按键质量特别好。
:::

## 常见问题

### 编译错误

如果编译失败，检查：
1. 内核头文件是否安装
2. Makefile 中的路径是否正确
3. 代码语法错误

### 加载失败

如果 `insmod` 失败，检查：
1. 设备树配置是否正确
2. GPIO 是否被其他驱动占用
3. 中断号是否有效

### 没有输出

如果测试程序没有输出，检查：
1. 设备节点权限
2. 中断是否触发
3. 工作队列是否正常

### 大量重复事件

如果看到很多连续的 `PRESSED` 或 `RELEASED`，检查：
1. 消抖延时是否足够
2. 按键硬件是否有严重抖动
3. 统计信息中的 `skipped` 计数

## 生产环境建议

在生产环境中使用这个驱动，有一些建议：

1. **设备节点权限**：创建 udev 规则自动设置权限
2. **错误处理**：添加更完善的错误处理和日志
3. **可配置参数**：通过模块参数支持配置消抖延时
4. **多设备支持**：扩展驱动支持多个按键
5. **电源管理**：实现电源管理回调，支持系统休眠

::: tip 模块参数
你可以添加模块参数，让用户可以在加载驱动时配置参数：

```c
static int debounce_ms = 20;
module_param(debounce_ms, int, 0644);
MODULE_PARM_DESC(debounce_ms, "Debounce delay in milliseconds");
```

然后可以用 `insmod key_debounce_driver_main.ko debounce_ms=30` 加载。
:::

## 本章小结

编译和测试是驱动开发的最后一步。从编译驱动、加载模块、编写测试程序，到验证功能、对比性能，每一步都不能马虎。通过本章的学习，你应该能够独立完成驱动的编译、加载和测试。

中断方式相比轮询方式，在 CPU 占用、功耗、响应速度上都有明显优势。统计信息可以验证消抖是否有效工作。这些验证步骤确保了驱动不仅能跑起来，还能正常工作。

本教程到这里就结束了。你学习了中断子系统、工作队列机制、消抖算法、同步机制，以及如何编译和测试驱动。这些知识不仅适用于按键驱动，也适用于其他需要中断和消抖的设备。

下一步，你可以学习 [Input 子系统](../07_input_subsystem_key/)，了解内核提供的标准按键框架。

---

**相关文档**：
- [输出分析](06_output_analysis.md)
- [Input 子系统按键](../07_input_subsystem_key/)
