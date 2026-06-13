---
title: 应用开发与测试
---

# 应用开发与真实测试 - 我们是怎么验证驱动真的能用的

## 前言：驱动写完了，但故事还没结束

前面我们已经把新 API 驱动写完了，代码编译也没报错，但说实话，这时候我们心里还是没底的。驱动这东西，不到开发板上跑一遍，你永远不知道哪里会炸。内核代码和用户空间程序不一样，一个指针错误就能让整个系统崩溃，连个调试信息都留不下。

所以接下来我们要做两件事：写一个用户空间的测试程序，然后把整个东西部署到真实开发板上，看看它到底能不能正常工作。这个过程其实比写驱动本身还要重要，因为只有通过真实测试，你才能确认代码不是在自嗨，而是真的能解决问题。

## 应用层开发：用户空间怎么和驱动对话

驱动在内核空间，应用程序在用户空间，它们之间通过系统调用和设备文件通信。我们的应用程序要做的事情很简单：打开设备文件，写入控制命令，读取设备状态。但说起来简单，实际写的时候还是有不少细节要注意的。

应用程序位于 `driver/application/chardev_led_control/led_control.c`，我们先看一下完整的代码：

```c
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

void print_help(const char* app_name) {
    printf("Usage: %s /path/to/chardev_file <0/1>\n", app_name);
    printf("    - /path/to/chardev_file: char dev file in /dev/\n");
    printf("    - <0/1>: 0 for off, 1 for on\n");
    printf("@note: make sure the protocols match!\n");
}

int main(int argc, char* argv[])
{
    if (argc != 3) {
        print_help(argv[0]);
        return 1;
    }

    const char* dev_file = argv[1];
    const char* user_indication = argv[2];

    /* 参数验证 */
    if (strcmp(user_indication, "1") != 0 &&
        strcmp(user_indication, "0") != 0) {
        printf("Expected only 1 and 0, but get %s\n", user_indication);
        return 1;
    }

    /* 打开设备文件 */
    const int dev_file_fd = open(dev_file, O_RDWR);
    if (dev_file_fd < 0) {
        printf("Failed to open the file: %s, code: %d\n", dev_file, errno);
        return 1;
    }

    /* 写入控制命令 */
    write(dev_file_fd, user_indication, 1);

    /* 读取设备状态 */
    char buffer[2] = {0};
    const int bytes = read(dev_file_fd, buffer, 1);
    if (bytes < 0) {
        printf("Failed to read the file: %s, code: %d\n", dev_file, errno);
        return 1;
    }

    /* 打印状态 */
    if (buffer[0] == '1') {
        printf("LED is on now, status from the dev file!\n");
    } else if (buffer[0] == '0') {
        printf("LED is off now, status from the dev file!\n");
    } else {
        printf("Unknown value: %s", buffer);
        return -1;
    }

    return 0;
}
```

这个程序虽然简单，但包含了用户空间和驱动通信的完整流程。我们先解析一下参数，用户需要提供设备文件路径和控制命令。设备文件一般是 `/dev/AES_LED`，控制命令是 `0` 或 `1`，`0` 关灯，`1` 开灯。

参数验证这一步真的不能省，用户输入千奇百怪，你不验证的话，什么奇怪的东西都能传进来。我们只接受 `0` 和 `1` 两个值，其他的直接拒绝。说实话，这种防御性编程在驱动开发里特别重要，你永远不知道用户会干什么。

打开设备文件用标准的 `open` 系统调用，`O_RDWR` 表示读写模式。打开失败的话，`errno` 会告诉我们具体是什么问题。我们打印错误码，方便调试。这里要注意，返回值 `< 0` 才是错误，别写成 `== -1`，虽然大多数情况下是这样，但标准只保证负数表示错误。

写入控制命令用 `write` 系统调用，我们把用户输入的 `0` 或 `1` 写入设备文件。驱动会接收这个命令，然后操作硬件。这里我们只写 1 个字节，因为我们的协议很简单，一个字符就够了。

读取设备状态用 `read` 系统调用，我们读取 1 个字节到缓冲区，然后判断是 `0` 还是 `1`。如果驱动工作正常，这里读到的应该就是我们刚才写入的值。

## 编译与部署：从开发机到开发板

代码写完了，下一步是编译和部署。我们的开发环境是在 PC 上，代码要在 ARM 开发板上跑，所以需要交叉编译。

```bash
cd /home/charliechen/imx-forge
./scripts/driver_helper/build_driver.sh chardev_led_v2_02 alpha-board
```

这个脚本会帮我们处理交叉编译的细节，包括设置交叉编译器、指定架构参数、编译驱动和应用程序。说实话，手动敲交叉编译命令真的很烦，每次都要查半天参数，写成脚本之后一条命令搞定，轻松很多。

编译完成后，我们把文件部署到开发板：

```bash
./scripts/driver_helper/deploy_driver.sh chardev_led_v2_02 alpha-board
```

部署脚本会通过网络把驱动和应用程序拷贝到开发板的正确位置。我们的开发板配置要求内核版本 6.12.49 或更高，支持 mdev（BusyBox 的设备管理器），设备文件 `/dev/AES_LED` 会在驱动加载后自动创建。

## 真实测试输出：第一次跑起来是什么样

说实话，第一次在开发板上运行自己写的驱动，心情真的很复杂。既期待它正常工作，又怕哪里出问题炸板。我们先加载驱动：

```bash
/lib/modules # insmod chardev_led_v2_02_driver.ko
```

然后盯着串口看日志输出，每一行都代表一个步骤的成功：

```
[   84.386824] chardev_led_v2_02_driver: loading out-of-tree module taints kernel.
[   84.387622] === led driver using new api ===
[   84.387644] Step 0: Request MMU Mappings by ioremap
[   84.387710] IMX6U_CCM_CCGR1    = 0xc59d421e (phys: 0x20c406c)
[   84.387744] SW_MUX_GPIO1_IO03  = 0x17f27ee4 (phys: 0x20e0068)
[   84.387759] SW_PAD_GPIO1_IO03  = 0xbb8efdcf (phys: 0x20e02f4)
[   84.387775] GPIO1_DR           = 0x3e65fd70 (phys: 0x209c000)
[   84.387790] GPIO1_GDIR         = 0x69125586 (phys: 0x209c004)
```

第一行是内核警告我们加载了一个树外模块，会污染内核。这在开发阶段很正常，不用管。接下来是驱动打印的初始化信息，ioremap 成功映射了 5 个寄存器。

然后是时钟使能：

```
[   84.387806] Step 1: GPIO Enable Clock
[   84.387813] CCGR1 raw value: 0xfcfc0000
[   84.387813]  Bits:
[   84.387826]
[   84.387835] 11111100111111000000000000000000
[   84.387847] CCGR1 new raw value: 0xfcfc0000
[   84.387847] Bits: 11111100111111000000000000000000
```

CCGR1 寄存器的 bit 26-27 控制着 GPIO1 的时钟，这里已经被设置为 `11`，表示时钟已使能。如果这一步不对，后面的 GPIO 操作都不会生效。

接下来是 GPIO 功能配置：

```
[   84.387870]
[   84.387880] Step 2: GPIO Functional Settings
[   84.387888] Setting SW_MUX_GPIO1_IO03 = 0x5
[   84.387901] GPIO1_GDIR set to 0x00000108
[   84.387911] GPIO1_DR init set to 0xf004031c (LED OFF)
[   84.387922] LED Init OK!
```

MUX 寄存器设置为 `0x5`（ALT5，GPIO 模式），GDIR 设置为 `0x108`（bit 3 为 1，输出模式），DR 初始化为 `0xf004031c`（bit 3 为 1，LED 关闭）。LED 的硬件逻辑是低电平点亮，所以初始化时把 bit 3 设为 1，LED 是灭的。

最后是设备注册：

```
[   84.387931] Init the User Interfaces and driver handles
[   84.387944] LED handle get the device number: major: 241, minor: 0
[   84.387966] cdev series api called success!
[   84.388037] class create success!
[   84.388557] device create success!
[   84.388580] ========================
```

内核动态分配了主设备号 241，cdev 注册成功，class 创建成功，device 创建成功。到这里，驱动加载就完成了。

我们可以验证一下设备是否真的创建成功：

```bash
/lib/modules # ls /dev/AES_LED
/dev/AES_LED

/lib/modules # ls -l /dev/AES_LED
crw-------    1 root     root      241,   0 ... /dev/AES_LED
```

设备文件存在，文件类型是 `c`（字符设备），主设备号是 241，次设备号是 0。一切正常。

## LED 控制测试：看看灯是不是真的能亮

接下来就是激动人心的时刻了，我们要看看 LED 到底能不能控制。先用 `printf` 命令测试一下：

```bash
/lib/modules # printf '1' > /dev/AES_LED
```

然后看内核日志：

```
[  125.236855] Device: AES_LED called open!
[  125.237085] aes_chardev_write: cnt=1
[  125.237114] LED status: 1 (user_led_new_status='1')
[  125.237131] led_set_status: status=1, GPIO1_DR before=0xf004031c
[  125.237147] led_set_status: GPIO1_DR after=0xf0040314, bit3=0
[  125.237183] Device: AES_LED called close!
```

open() 被调用，write() 接收到 1 字节数据 `1`，led_set_status() 被调用，GPIO1_DR 从 `0xf004031c` 变成 `0xf0040314`。注意 bit 3 从 1 变成了 0，LED 点亮（低电平有效）。如果硬件连接正确，这时候 LED 应该亮了。

我们再关掉 LED：

```bash
/lib/modules # printf '0' > /dev/AES_LED
```

内核日志：

```
[  130.690963] Device: AES_LED called open!
[  130.691063] aes_chardev_write: cnt=1
[  130.691082] LED status: 0 (user_led_new_status='0')
[  130.691097] led_set_status: status=0, GPIO1_DR before=0xf0040314
[  130.691114] led_set_status: GPIO1_DR after=0xf004031c, bit3=1
[  130.691147] Device: AES_LED called close!
```

GPIO1_DR 从 `0xf0040314` 变回 `0xf004031c`，bit 3 从 0 变成 1，LED 熄灭。一切符合预期。

这里我们总结一下 GPIO 寄存器的值变化，理解这个变化对调试很有帮助。初始化时，GPIO1_DR 是 `0xf004031c`，bit 3 是 1，LED 关闭。开灯时，bit 3 变成 0，LED 点亮。关灯时，bit 3 变回 1，LED 熄灭。如果硬件上 LED 是低电平点亮的，这个逻辑就对了。如果发现 LED 状态反了，要么是硬件接线问题，要么是驱动逻辑问题，根据这个寄存器值的变化就能定位。

## 应用程序测试：完整的工作流

`printf` 命令测试通过后，我们用真正的应用程序测试一下：

```bash
~ # /usr/local/bin/led_control /dev/AES_LED 1
LED is on now, status from the dev file!
```

应用程序成功执行，打印出 LED 已经点亮。内核日志和之前用 `printf` 时一样，说明应用程序和驱动通信正常。

```bash
~ # /usr/local/bin/led_control /dev/AES_LED 0
LED is off now, status from the dev file!
```

LED 成功熄灭。到这里，我们就可以确认驱动和应用程序都工作正常了。

## 驱动卸载测试：资源清理是否完整

最后我们测试一下驱动的卸载，确保资源能被正确释放：

```bash
/lib/modules # rmmod chardev_led_v2_02_driver.ko
```

内核日志：

```
[  155.317898] === chardev_led_v2_02驱动卸载成功 ===
[  155.318567] Deinit the LED Hardware
[  155.318623] ========================
```

我们验证一下设备节点是否被删除：

```bash
/lib/modules # ls /dev/AES_LED
ls: /dev/AES_LED: No such file or directory
```

设备文件已经被删除，说明 `device_destroy` 工作正常。我们再检查一下设备号是否被释放：

```bash
$ cat /proc/devices | grep AES_LED
# （无输出，设备号已释放）
```

设备号已经被释放，说明 `unregister_chrdev_region` 工作正常。资源清理完整，没有泄漏。

## 故障排查：遇到问题怎么办

虽然我们的测试很顺利，但实际开发中难免会遇到各种问题。这里我们总结一些常见的故障和排查方法，希望能帮你少踩点坑。

如果设备节点没有创建，首先检查驱动是否真的加载了：

```bash
$ lsmod | grep aes_led
chardev_led_v2_02_driver    2048  0
```

如果没有输出，说明驱动没加载成功，查看内核日志找原因。如果驱动加载了，检查设备号是否分配：

```bash
$ cat /proc/devices | grep aes_led
241 aes_led
```

如果没有输出，说明设备号分配失败，`alloc_chrdev_region` 可能出错了。再检查 class 是否创建：

```bash
$ ls /sys/class/aes_led/
aes_led/
```

如果这里没有 AES_LED，说明 `class_create` 失败了。最后检查设备是否存在：

```bash
$ ls /sys/class/aes_led/aes_led/
# 如果这里没有 AES_LED，说明 device_create() 失败
```

权限问题是另一个常见问题。如果你遇到这样的错误：

```bash
$ ./led_control /dev/AES_LED 1
Failed to open the file: /dev/AES_LED, code: 13
# code: 13 = EACCES (Permission denied)
```

有几个解决方案。最简单的是用 sudo：

```bash
$ sudo ./led_control /dev/AES_LED 1
```

或者修改设备文件权限：

```bash
$ chmod 666 /dev/AES_LED
```

或者修改用户组：

```bash
$ sudo chown root:users /dev/AES_LED
$ sudo chmod 664 /dev/AES_LED
```

还有一种情况是程序执行成功了，但 LED 就是不亮。这时候需要确认驱动真的收到了命令：

```bash
# 检查 write 是否被调用
$ dmesg | grep "aes_chardev_write"

# 检查 GPIO 操作
$ dmesg | grep "led_set_status"
```

如果这些日志都有，说明驱动工作正常，问题可能在硬件上。用万用表测量一下 GPIO 电平，确认硬件连接。还要检查设备树，看看有没有其他驱动占用了这个 GPIO。

调试的时候有几个工具特别有用。`strace` 可以追踪系统调用，看看应用程序到底干了什么：

```bash
$ strace -e open,read,write ./led_control /dev/AES_LED 1
open("/dev/AES_LED", O_RDWR)         = 3
write(3, "1", 1)                     = 1
read(3, "1", 1)                      = 1
```

`dmesg -w` 可以实时监控内核日志，方便观察驱动的输出：

```bash
$ dmesg -w | grep AES_LED
# 实时监控内核日志
```

还可以检查 `/sys` 下的文件，获取设备信息：

```bash
$ cat /sys/class/aes_led/AES_LED/dev
241:0

$ cat /sys/kernel/debug/gpio
# 查看 GPIO 状态（需要内核支持）
```

## 本章小结

这一章我们完成了应用开发和真实测试。应用程序通过 open、write、read 系统调用与驱动通信，实现了 LED 的控制和状态读取。编译部署后，我们在真实开发板上进行了完整测试，验证了驱动的功能正确性。

测试过程中，我们看到了驱动加载时的完整日志，包括 ioremap、时钟使能、GPIO 配置、设备注册等步骤。我们看到了 GPIO 寄存器值的变化，理解了 bit 3 如何控制 LED 的开关。我们验证了设备节点的自动创建和删除，确认了资源的正确分配和释放。

驱动开发就是这样，代码写完了不算完，必须真实环境跑过才算数。只有通过测试，你才能发现那些在代码审查里看不到的问题，才能确认驱动真的能解决实际问题。这一章的测试流程和调试技巧，在以后的驱动开发里都会用到。

到这里，我们的字符设备驱动教程就告一段落了。从最简单的虚拟设备，到老 API 驱动，再到新 API 驱动，从理论到实践，从代码到测试，我们走完了完整的学习路径。希望这个教程能帮你入门字符设备驱动开发，更希望它能给你信心，让你知道内核驱动开发其实没那么可怕。

---

**相关文档**：
- [老 API 字符设备驱动](06_legacy_chardev.md)
- [新 API 驱动分析](17_new_api_driver_analysis.md)
