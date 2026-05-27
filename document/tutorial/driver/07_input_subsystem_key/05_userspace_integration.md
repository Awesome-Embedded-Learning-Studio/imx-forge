# 用户空间集成 - 从设备节点到应用程序

驱动写完了，事件也报告了，现在来聊聊用户空间怎么用这些事件。说实话，Input 子系统最大的优势就是用户空间支持——不用自己写应用，不用适配各种框架，标准的输入事件谁都能用。

## 设备节点：自动创建的魔法

注册 input 设备后，evdev Handler 会自动创建设备节点：

```bash
$ ls -l /dev/input/event*
crw-rw---- 1 root input 13, 64 May 27 10:00 /dev/input/event0
crw-rw---- 1 root input 13, 65 May 27 10:00 /dev/input/event1
```

设备节点的主设备号是 13（Input 设备的统一主设备号），次设备号从 64 开始。设备权限是 `crw-rw----`，只有 root 和 `input` 组成员能访问。

::: info
`input` 组是系统专门为输入设备创建的组。如果想让普通用户访问输入设备，可以把用户加入 `input` 组：`usermod -aG input username`
:::

## 找到你的设备

系统可能有多个输入设备（键盘、鼠标、触摸屏等），怎么找到你的按键设备？有几种方法：

**方法 1：查看 `/proc/bus/input/devices`**

```bash
$ cat /proc/bus/input/devices
```

输出包含所有输入设备的详细信息：

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

这里的 `Handlers=event0` 表示这个设备对应 `/dev/input/event0`。

**方法 2：在 sysfs 中查找**

```bash
$ grep -r "imxaes-key" /sys/class/input/input*/name
/sys/class/input/input0/name:imxaes-key
```

设备名是 `input0`，对应的设备节点就是 `/dev/input/event0`（`input0` → `event0`）。

## 用户空间读取事件

用户空间通过标准的 `read()` 读取事件。事件结构体定义在 `<linux/input.h>`：

```c
#include <linux/input.h>

struct input_event {
    struct timeval time;  /* 时间戳 */
    __u16 type;          /* 事件类型 */
    __u16 code;          /* 事件代码 */
    __s32 value;         /* 事件值 */
};
```

读取事件的简单程序：

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

编译运行：

```bash
gcc -o test_input test_input.c
./test_input
Listening on /dev/input/event0 (Ctrl+C to exit)...
Key: PRESSED
Key: RELEASED
Key: PRESSED
Key: RELEASED
```

::: info
`read()` 会阻塞，直到有事件可读。如果要用非阻塞模式，打开时加 `O_NONBLOCK`：`open(dev, O_RDONLY | O_NONBLOCK)`
:::

## poll/select/epoll：多路复用

实际应用中，你可能需要同时监听多个输入设备，或者同时处理其他 I/O。这时可以用 `poll()`、`select()` 或 `epoll()`：

```c
#include <poll.h>

struct pollfd fds[1];
fds[0].fd = fd;
fds[0].events = POLLIN;

while (1) {
    int ret = poll(fds, 1, -1);  /* 永久等待 */
    if (ret > 0 && fds[0].revents & POLLIN) {
        struct input_event ev;
        read(fd, &ev, sizeof(ev));
        /* 处理事件 */
    }
}
```

::: tip
Qt、GTK 这些框架内部已经用 `epoll` 或类似机制监听输入设备，你只需要连接信号槽，不用自己处理 I/O 多路复用。
:::

## 与桌面环境集成

Input 子系统的最大优势是与桌面环境无缝集成。如果你有 X11 或 Wayland：

**X11 会自动识别设备**：

```bash
$ xinput list
⎡ Virtual core pointer                    	id=2	[master pointer  (3)]
⎜ ↳ Alps_I2C_Touchpad                    	id=11	[slave  pointer  (2)]
⎣ Virtual core keyboard                   	id=3	[master keyboard (2)]
  ↳ imxaes-key                            	id=12	[slave  keyboard (3)]
```

`imxaes-key` 已经被 X11 识别为键盘设备。

**设置按键映射**：

```bash
$ xmodmap -e "keycode 36 = Return"
```

现在按下按键，X11 会产生 Enter 键事件，任何应用都能收到。

**Qt 直接支持**：

```cpp
void MyWidget::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Return) {
        qDebug() << "Enter pressed!";
    }
}
```

你不需要自己监听 `/dev/input/eventX`，Qt 已经帮你做了。

::: info
Qt 底层通过 X11、Wayland 或 evdev 直接读取输入设备。你的按键驱动注册后，Qt 应用不需要任何修改就能收到按键事件。
:::

## 与字符设备驱动的对比

之前我们写的字符设备驱动，用户空间要自己实现协议：

```c
/* 字符设备驱动 */
int fd = open("/dev/beep", O_RDONLY);
struct beep_event ev;
read(fd, &ev, sizeof(ev));
```

这个协议是我们自定义的，其他框架不认识。Input 子系统的好处是标准协议，谁都能用：

| 特性 | 字符设备驱动 | Input 子系统 |
|------|-------------|--------------|
| 设备节点 | 自定义 `/dev/beep` | 标准 `/dev/input/eventX` |
| 用户空间库 | 无 | X11、Qt、GTK、SDL |
| 事件格式 | 自定义 `beep_event` | 标准 `input_event` |
| 多按键支持 | 需要自己实现 | 天然支持 |
| 调试工具 | 自己写 hexdump | xinput、cat /proc/bus/input/devices |

## 实际应用场景

Input 子系统驱动的典型应用场景：

**1. 工业控制面板**

多个按键、旋钮、指示灯。用 Input 子系统报告按键，UI 框架直接响应。

**2. 嵌入式设备**

手持设备、医疗设备、POS 机。按键映射到系统快捷键，应用不用关心硬件细节。

**3. 游戏设备**

游戏手柄、方向盘。SDL、Unity 这些引擎直接支持，无需适配。

::: tip
如果你的设备有多个按键，建议在驱动里报告不同的按键代码（KEY_ENTER、KEY_ESC、KEY_1 等），而不是只报告一个按键再在用户空间区分。这样应用可以直接用标准按键处理流程。
:::

## 本章小结

Input 子系统自动创建 `/dev/input/eventX` 设备节点，可以通过 `/proc/bus/input/devices` 或 sysfs 找到对应设备。用户空间通过 `read()` 读取 `input_event` 结构体，可用 `poll()`/`select()`/`epoll` 实现多路复用。

与桌面环境集成是 Input 子系统的杀手锏——X11、Qt、GTK 直接支持，不需要额外适配。相比字符设备驱动的自定义协议，Input 子系统提供了标准接口，大大简化了应用开发。

下一章我们会讲解完整的编译和测试流程，把所有知识点串起来。

---

**相关文档**：
- [事件报告](03_event_reporting.md)
- [编译和测试](06_build_and_test.md)

**下一步：** 继续阅读 [06_build_and_test.md](06_build_and_test.md) 完成整个教程。
