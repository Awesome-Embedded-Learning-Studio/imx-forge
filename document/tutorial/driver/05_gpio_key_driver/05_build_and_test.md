# 编译和测试 - 让驱动跑起来

前面的章节我们把原理都讲完了，现在该动手验证一下了。说实话，写驱动最爽的时刻就是代码跑通的那一瞬间，你按一下按键，终端输出"Key PRESSED"，那种感觉真的很不一样。

## 编译驱动

驱动代码在 `driver/17_tutorial_key_gpio_driver/` 目录下。编译很简单：

```bash
cd driver/17_tutorial_key_gpio_driver/alpha-board/
make
```

顺利的话会生成 `key_gpio_driver.ko` 文件。`.ko` 是内核模块的扩展名，表示 Kernel Object。

::: tip 编译出错了怎么办

如果编译失败，先检查这几个地方：

1. **内核源码路径**——Makefile 里的 `KDIR` 要指向你的内核源码
2. **架构配置**——确保 `ARCH=arm` 和 `CROSS_COMPILE` 设置正确
3. **头文件**——缺少头文件通常说明内核版本不匹配

第一次编译的时候我经常犯这些错误，多试几次就熟了。
:::

## 编译设备树

我们的按键驱动需要设备树的支持。设备树文件是 `imx6ull-aes-key.dts`，编译成二进制：

```bash
cd arch/arm/boot/dts/
dtc -I dts -O dtb -o imx6ull-aes-key.dtb imx6ull-aes-key.dts
```

生成的 `.dtb` 文件要放到开发板的启动分区里。

::: info 设备树的作用

设备树（Device Tree）描述硬件配置，告诉内核：这个按键接在 GPIO1_18 上，是低电平触发的。驱动代码通过设备树获取这些信息，而不是硬编码。

这样同样的驱动代码，只需要改设备树就能适配不同的硬件配置。
:::

## 部署到开发板

把编译好的文件传到开发板：

```bash
# 用 scp 传输
scp key_gpio_driver.ko root@192.168.1.100:/lib/modules/$(uname -r)/extra/
scp imx6ull-aes-key.dtb root@192.168.1.100:/boot/

# 或者用 U 盘/SD 卡拷贝
```

## 加载驱动

SSH 登录开发板，加载驱动：

```bash
insmod key_gpio_driver.ko
```

成功加载的话，`dmesg` 里会有输出：

```
[12345.678901] key_gpio_driver: module init success
[12345.678902] key_gpio_driver: get gpio: gpio1 18
[12345.678903] key_gpio_driver: device created: /dev/imxaes_key
```

::: tip 检查设备节点

驱动加载成功后，设备节点应该自动出现在 `/dev` 目录下：

```bash
ls -l /dev/imxaes_key
# 输出: crw-rw---- 1 root root 246, 0 ...
```

如果设备节点没有出现，检查设备树配置和驱动的设备创建代码。
:::

## 快速验证

最快验证驱动工作的方法是用 `cat` 命令：

```bash
cat /dev/imxaes_key
```

然后按下板子上的按键，你应该能看到输出（虽然可能是乱码，因为 `cat` 会把数据当作文本）。

按 `Ctrl+C` 退出。

## 用测试程序

更好的方式是写个专门的测试程序：

```c
/* test_key.c */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

int main(void)
{
    int fd = open("/dev/imxaes_key", O_RDONLY);
    if (fd < 0) {
        perror("open device failed");
        return 1;
    }

    printf("Press the key (Ctrl+C to exit)...\n");

    int value;
    while (1) {
        ssize_t n = read(fd, &value, sizeof(value));
        if (n < 0) {
            if (errno == EINTR) {
                printf("\nInterrupted by user\n");
                break;
            }
            perror("read failed");
            break;
        }
        if (n != sizeof(value)) {
            printf("Unexpected read size: %zd\n", n);
            break;
        }

        printf("Key: %s\n", value == 1 ? "PRESSED" : "RELEASED");
        fflush(stdout);
    }

    close(fd);
    return 0;
}
```

交叉编译这个程序：

```bash
arm-linux-gnueabihf-gcc test_key.c -o test_key
```

拷贝到开发板运行：

```bash
./test_key
```

现在按按键，应该能看到清晰的输出：

```
Press the key (Ctrl+C to exit)...
Key: PRESSED
Key: RELEASED
Key: PRESSED
Key: RELEASED
```

按 `Ctrl+C` 退出程序。

## 观察抖动现象

根据上一章的讨论，你应该能看到抖动的效果。快速按一下按键，可能会输出多次事件：

```
Key: PRESSED
Key: RELEASED    <-- 抖动产生的假事件
Key: PRESSED     <-- 抖动产生的假事件
Key: RELEASED
```

这就是我们说的抖动问题。轮询方式很难彻底解决这个问题。

## 调试技巧

如果遇到问题，这几个调试工具很有用：

### 查看内核日志

```bash
dmesg | grep -i key
```

可以看到驱动的初始化日志和可能的错误信息。

### 查看 GPIO 状态

```bash
cat /sys/kernel/debug/gpio | grep -i "gpio-18"
```

这会显示 GPIO 的当前状态和占用情况。如果 GPIO 被其他驱动占用，这里能看出来。

### 监控 CPU 占用

```bash
# 运行测试程序
./test_key &

# 在另一个终端用 top 观察
top -d 1
```

你应该能看到测试程序的 CPU 占用率在 20%-50% 之间，这就是轮询方式的代价。

## 卸载驱动

测试完成后，卸载驱动：

```bash
rmmod key_gpio_driver
```

检查设备节点是否被删除：

```bash
ls /dev/imxaes_key
# ls: /dev/imxaes_key: No such file or directory
```

如果设备节点还在，说明驱动的清理函数有问题，资源泄漏了。

## 性能对比

为了更直观地理解轮询方式的低效，我们可以做一个简单的对比：

| 方式 | CPU 占用率 | 响应延迟 | 实现复杂度 |
|------|-----------|---------|-----------|
| 轮询 | 20-50% | 低（取决于循环频率） | 简单 |
| 中断 | <1% | 低（微秒级） | 中等 |

轮询方式的 CPU 占用是持续性的，即使按键没被按下，循环也在跑。中断方式则完全相反，平时 CPU 占用为零，只有按键按下时才处理。

::: tip 什么时候能用轮询

虽然我们一直在说轮询效率低，但在某些场景下它也有优势：

- 快速原型开发——先验证功能，再优化
- 短时间测试——调试时临时用用
- 简单系统——单进程、低要求的应用

关键是要理解它的局限，选择合适的场景使用。
:::

## 小结

这一章我们编译并测试了轮询式的按键驱动。你应该能体验到：

1. **驱动能工作**——按键事件能被检测到
2. **抖动现象真实存在**——一次按键产生多次事件
3. **CPU 占用确实高**——top 能看到明显的负载
4. **轮询方式简单**——代码逻辑确实容易理解

这个教程的目的是让你理解 GPIO 输入的基本原理。轮询方式作为教学示例是合格的，但作为生产级的解决方案是不合格的。

下一章我们会学习中断方式，这才是输入驱动的主流做法。你将看到：有了中断，CPU 占用降下来，抖动问题也解决了，整个体验完全不同。

---

**上一章**: [抖动现象](./04_bounce_phenomenon.md) | **下一章**: [中断消抖驱动](../06_debounced_key_driver/)
