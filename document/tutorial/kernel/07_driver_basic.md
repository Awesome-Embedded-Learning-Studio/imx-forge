---
title: 驱动开发入门
---

# Linux驱动开发入门：从Hello World到第一个字符驱动

## 为什么要写这一章

如果你按照前面的教程一路走过来，这时候你应该已经能够成功编译内核、移植设备树、让Linux在板子上跑起来了。恭喜你，这是一个不小的成就！

但很快你会遇到一个问题：Linux跑起来了，然后呢？

你可能会发现自己能用的只有串口终端敲敲命令，想控制板子上的LED、想读取某个传感器、想用个自定义硬件，完全不知道从哪下手。这时候你需要的就是——驱动程序。

驱动开发在很多新手眼里是个"神秘领域"。网上的教程要么上来就给你一堆内核API文档，要么直接甩一个几十KB的复杂驱动源码让你自己悟。我当时学的时候就是这种感觉：每个API我都认识，但凑在一起就不知道为什么要这么写了。

更糟糕的是，很多教程没有教你如何验证驱动是否正常工作。编译通过了，加载了，然后呢？不知道怎么测试，不知道出了问题怎么排查。

所以这一章的目标很明确：带你从零开始写一个最简单的字符驱动，理解驱动的核心概念，学会编译、加载、测试和调试。到了最后，你会明白驱动其实就是内核和硬件之间的"翻译官"，它的工作就是让用户程序能够安全、有序地访问硬件资源。

## 驱动到底是什么？

先说个最直白的解释：驱动就是运行在内核空间的"硬件管家"。

用户程序（比如你写的C程序、Python脚本）运行在用户空间，权限有限，不能直接访问硬件。内核运行在内核空间，拥有最高权限，可以直接操作所有硬件。驱动就是连接这两者的桥梁。

用个类比来解释：

- 用户程序 = 顾客，想买东西但不能进仓库
- 内核 = 仓库管理员，管着所有东西
- 驱动 = 仓库管理员的具体工作流程图，告诉他怎么处理顾客的请求

当用户程序想操作硬件时，它不能直接说"给我控制GPIO管脚"，而是要通过驱动提供的"接口"发出请求。驱动接收到请求后，按照预定的规则去操作硬件，然后把结果返回给用户程序。

这个设计有几个好处：

1. **安全性**：用户程序不能乱来，所有操作都要经过驱动的检查
2. **抽象性**：同样的用户程序可以使用不同的硬件，只要驱动接口一致
3. **稳定性**：驱动崩溃会影响整个系统，但用户程序崩溃不会

在Linux中，驱动主要通过**设备文件**来向用户空间暴露接口。你会在`/dev`目录下看到各种设备文件：`/dev/ttyUSB0`、`/dev/input/mouse0`等等。用户程序通过读写这些文件来和驱动交互，驱动再转而去操作真正的硬件。

## 最简单的字符驱动：Hello World

我们从最基础的开始——一个"Hello World"字符驱动。这个驱动不做任何实际的事，就是用来展示驱动的基本框架。

### 驱动代码结构

创建一个文件`hello_drv.c`：

```c
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/init.h>
#include <linux/cdev.h>
#include <linux/slab.h>

#define DEVICE_NAME "hello"
#define BUF_LEN 80

// 全局变量
static int major_num;
static struct cdev hello_cdev;
static char msg[BUF_LEN] = "Hello from kernel space!\n";
static int msg_len = 28;

// 文件操作函数
static int hello_open(struct inode *inode, struct file *file)
{
    printk(KERN_INFO "hello: device opened\n");
    return 0;
}

static int hello_release(struct inode *inode, struct file *file)
{
    printk(KERN_INFO "hello: device closed\n");
    return 0;
}

static ssize_t hello_read(struct file *file, char __user *buf,
                         size_t count, loff_t *ppos)
{
    int bytes_read = 0;

    if (*ppos > 0)
        return 0;  // EOF

    if (count > msg_len)
        count = msg_len;

    if (copy_to_user(buf, msg, count) != 0)
        return -EFAULT;

    *ppos += count;
    bytes_read = count;

    printk(KERN_INFO "hello: read %d bytes\n", bytes_read);
    return bytes_read;
}

// 文件操作结构体
static struct file_operations hello_fops = {
    .owner = THIS_MODULE,
    .open = hello_open,
    .release = hello_release,
    .read = hello_read,
};

// 模块初始化
static int __init hello_init(void)
{
    int ret;
    dev_t dev;

    // 动态申请设备号
    ret = alloc_chrdev_region(&dev, 0, 1, DEVICE_NAME);
    if (ret < 0) {
        printk(KERN_ERR "hello: failed to allocate major number\n");
        return ret;
    }
    major_num = MAJOR(dev);

    // 初始化cdev
    cdev_init(&hello_cdev, &hello_fops);

    // 添加cdev到系统
    ret = cdev_add(&hello_cdev, dev, 1);
    if (ret < 0) {
        unregister_chrdev_region(MKDEV(major_num, 0), 1);
        printk(KERN_ERR "hello: failed to add cdev\n");
        return ret;
    }

    printk(KERN_INFO "hello: module loaded, major=%d\n", major_num);
    return 0;
}

// 模块退出
static void __exit hello_exit(void)
{
    cdev_del(&hello_cdev);
    unregister_chrdev_region(MKDEV(major_num, 0), 1);
    printk(KERN_INFO "hello: module unloaded\n");
}

module_init(hello_init);
module_exit(hello_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("IMX-Forge");
MODULE_DESCRIPTION("A simple hello driver");
```

这个代码看起来有点长，但核心部分其实很简单。让我逐块解释：

**头文件部分**：
- `module.h`：模块相关宏和函数
- `fs.h`：文件系统和文件操作相关
- `uaccess.h`：用户空间数据访问函数（`copy_to_user`等）
- `cdev.h`：字符设备结构

**file_operations结构体**：
这是驱动的"接口定义"，告诉内核当用户对设备文件执行各种操作时，应该调用哪些函数。

```c
static struct file_operations hello_fops = {
    .owner = THIS_MODULE,
    .open = hello_open,
    .release = hello_release,
    .read = hello_read,
};
```

每个字段都是一个函数指针：
- `open`：用户打开设备文件时调用（比如`open("/dev/hello", O_RDWR)`）
- `release`：用户关闭设备文件时调用
- `read`：用户读设备文件时调用
- `write`：用户写设备文件时调用（我们没实现）

**模块初始化函数**：
```c
static int __init hello_init(void)
```
这个函数在模块加载时执行（`insmod`）。它的职责是：
1. 申请设备号（`alloc_chrdev_region`）
2. 初始化字符设备（`cdev_init`）
3. 把字符设备添加到系统（`cdev_add`）

**模块退出函数**：
```c
static void __exit hello_exit(void)
```
模块卸载时执行（`rmmod`），负责清理资源。

### Makefile编写

要编译这个驱动，需要准备一个Makefile：

```makefile
# 内核源码路径
KERNEL_DIR := /path/to/linux-imx

# 当前模块目录
PWD := $(shell pwd)

# 模块名称
obj-m := hello_drv.o

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
```

把`KERNEL_DIR`改成你实际的内核源码路径。然后执行：

```bash
make
```

如果一切顺利，你应该会看到类似这样的输出：

```
make -C /path/to/linux-imx M=/home/user/hello modules
make[1]: Entering directory '/path/to/linux-imx'
  CC [M]  /home/user/hello/hello_drv.o
  MODPOST /home/user/hello/Module.symvers
  CC [M]  /home/user/hello/hello_drv.mod.o
  LD [M]  /home/user/hello/hello_drv.ko
make[1]: Leaving directory '/path/to/linux-imx'
```

编译完成后，当前目录下会出现`hello_drv.ko`文件，这就是内核模块文件（KO = Kernel Object）。

## 模块 vs 内置：两种编译方式

驱动有两种编译方式：编译为模块（`.ko`文件）或者直接编译进内核镜像。

### 模块编译（动态加载）

这是我们刚才演示的方式。驱动编译成独立的`.ko`文件，可以在系统运行时动态加载和卸载。

**优点**：
- 开发调试方便，改完重新编译、加载即可
- 不需要重新编译整个内核
- 可以按需加载，节省内存

**缺点**：
- 需要文件系统支持
- 启动时不会自动加载（除非配置）

**操作命令**：

```bash
# 加载模块
insmod hello_drv.ko

# 查看已加载模块
lsmod | grep hello

# 查看模块信息
modinfo hello_drv.ko

# 卸载模块
rmmod hello_drv
```

### 内置编译（静态链接）

把驱动代码直接编进内核镜像（`zImage`或`uImage`）。驱动在内核启动时自动初始化。

**如何配置**：

在内核源码的`drivers/char`目录下创建`Kconfig`：

```config
config HELLO_DRV
    tristate "Hello World Driver"
    help
      This is a simple hello driver for demonstration.
      If unsure, say N.
```

修改`drivers/char/Makefile`：

```makefile
obj-$(CONFIG_HELLO_DRV) += hello_drv.o
```

然后在内核配置界面开启：

```
Device Drivers  --->
    Character devices  --->
        [*] Hello World Driver
```

选择`[*]`就是内置（编译进内核），选择`[M]`就是模块。

重新编译内核后，驱动会在启动时自动初始化。

**踩坑提醒**：
内置驱动出问题时调试很麻烦，因为内核启动失败就进不去系统了。所以开发阶段建议用模块方式，稳定后再考虑内置。

## 设备号和设备文件

Linux通过**设备号**来识别设备。设备号由**主设备号**和**次设备号**组成：

- 主设备号：标识驱动程序
- 次设备号：标识同一驱动下的不同设备

比如`/dev/ttyS0`和`/dev/ttyS1`的主设备号相同（都是串口驱动），次设备号不同（0和1）。

### 动态分配 vs 静态分配

我们刚才用的是动态分配：

```c
ret = alloc_chrdev_region(&dev, 0, 1, DEVICE_NAME);
```

内核会自动分配一个可用的主设备号。

静态分配是指定一个固定的主设备号：

```c
major_num = 200;  // 自己选一个没被占用的号
ret = register_chrdev_region(MKDEV(major_num, 0), 1, DEVICE_NAME);
```

**经验**：动态分配更安全，避免冲突。静态分配的好处是设备号固定，方便创建设备文件。

### 创建设备文件

驱动加载后，需要创建设备文件才能被用户程序访问：

```bash
# 查看分配的主设备号
cat /proc/devices | grep hello
# 输出：250 hello

# 创建设备文件
sudo mknod /dev/hello c 250 0
#                    ^   ^   ^
#                    |   |   +- 次设备号
#                    |   +----- 主设备号
#                    +--------- c=字符设备，b=块设备

# 设置权限
sudo chmod 666 /dev/hello
```

### 自动创建设备文件（udev）

手动创建设备文件太麻烦了，现代Linux用`udev`来自动创建。需要在驱动里添加`class`和`device`注册：

```c
#include <linux/device.h>

static struct class *hello_class;
static struct device *hello_device;

static int __init hello_init(void)
{
    // ... 前面的代码不变 ...

    // 创建class
    hello_class = class_create(THIS_MODULE, DEVICE_NAME);
    if (IS_ERR(hello_class)) {
        ret = PTR_ERR(hello_class);
        goto fail_class;
    }

    // 创建device
    hello_device = device_create(hello_class, NULL, dev, NULL, DEVICE_NAME);
    if (IS_ERR(hello_device)) {
        ret = PTR_ERR(hello_device);
        goto fail_device;
    }

    printk(KERN_INFO "hello: device created\n");
    return 0;

fail_device:
    class_destroy(hello_class);
fail_class:
    // ... 清理代码 ...
}

static void __exit hello_exit(void)
{
    device_destroy(hello_class, MKDEV(major_num, 0));
    class_destroy(hello_class);
    // ... 其他清理代码 ...
}
```

这样udev会自动在`/dev`下创建设备文件，并且设置合适的权限。

## 测试驱动

驱动加载、设备文件创建好后，我们来测试一下：

### 方法一：命令行测试

```bash
# 读取设备
cat /dev/hello

# 输出：Hello from kernel space!
```

### 方法二：C程序测试

写一个测试程序`test_hello.c`：

```c
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main(void)
{
    int fd;
    char buf[128];
    int ret;

    fd = open("/dev/hello", O_RDWR);
    if (fd < 0) {
        perror("Failed to open device");
        return -1;
    }

    ret = read(fd, buf, sizeof(buf));
    if (ret < 0) {
        perror("Failed to read");
        close(fd);
        return -1;
    }

    buf[ret] = '\0';
    printf("Read from device: %s\n", buf);

    close(fd);
    return 0;
}
```

交叉编译后放到板子上运行：

```bash
gcc -o test_hello test_hello.c  # 本机测试
arm-none-linux-gnueabihf-gcc -o test_hello test_hello.c  # 交叉编译
./test_hello
```

## 查看内核日志：dmesg

内核日志是调试驱动最重要的工具。内核用`printk`函数输出日志（类似用户空间的`printf`）。

### 查看日志

```bash
# 查看全部内核日志
dmesg

# 只看最后20行
dmesg | tail -20

# 实时监控
dmesg -w

# 过滤包含"hello"的日志
dmesg | grep hello

# 清空日志
sudo dmesg -c
```

### 日志级别

`printk`有8个日志级别：

```c
#define KERN_EMERG   "0"    // 系统不可用
#define KERN_ALERT   "1"    // 必须立即处理
#define KERN_CRIT    "2"    // 严重情况
#define KERN_ERR     "3"    // 错误
#define KERN_WARNING "4"    // 警告
#define KERN_NOTICE  "5"    // 正常但重要
#define KERN_INFO    "6"    // 信息
#define KERN_DEBUG   "7"    // 调试信息
```

使用方式：
```c
printk(KERN_INFO "hello: device opened\n");
printk(KERN_ERR "hello: failed to allocate memory\n");
```

### 控制台日志级别

内核控制台默认只显示比某个级别高的日志。查看当前级别：

```bash
cat /proc/sys/kernel/printk
# 输出：4    4    1    7
#       |    |    |    |
#       |    |    |    +-- 默认控制台日志级别
#       |    |    +------- 最小控制台日志级别
#       |    +------------ 当前控制台日志级别
#       +----------------- 默认日志级别
```

修改日志级别：
```bash
sudo echo 8 > /proc/sys/kernel/printk  # 显示所有级别
```

## 常见驱动调试方法

驱动调试比用户程序调试要麻烦，因为你不能直接用gdb attach到内核。这里介绍几个实用方法。

### 方法1：printk大法

最简单也最常用的方法。在关键位置添加printk，然后通过dmesg查看。

**技巧**：为驱动定义统一的打印宏：

```c
#define DRV_NAME "hello"
#define drv_printk(level, fmt, ...) \
    printk(level DRV_NAME ": " fmt, ##__VA_ARGS__)

drv_printk(KERN_INFO, "device opened, pid=%d\n", current->pid);
drv_printk(KERN_ERR, "failed to allocate, err=%d\n", ret);
```

### 方法2：/proc和debugfs

内核提供了两个特殊的文件系统用于调试：

- `/proc`：主要用于展示信息
- `debugfs`：专门用于调试

在驱动中创建proc文件：

```c
#include <linux/proc_fs.h>

static int hello_proc_show(struct seq_file *m, void *v)
{
    seq_printf(m, "Hello Driver Status:\n");
    seq_printf(m, "  Major number: %d\n", major_num);
    seq_printf(m, "  Message: %s\n", msg);
    return 0;
}

static int hello_proc_open(struct inode *inode, struct file *file)
{
    return single_open(file, hello_proc_show, NULL);
}

static const struct file_operations hello_proc_fops = {
    .owner = THIS_MODULE,
    .open = hello_proc_open,
    .read = seq_read,
    .llseek = seq_lseek,
    .release = single_release,
};

// 在init函数中
proc_create("hello_driver", 0, NULL, &hello_proc_fops);

// 在exit函数中
remove_proc_entry("hello_driver", NULL);
```

然后可以`cat /proc/hello_driver`查看驱动状态。

### 方法3：动态调试（dynamic debug）

内核支持动态调试，可以在运行时控制哪些调试信息打印：

```bash
# 查看可动态调试的打印语句
cat /sys/kernel/debug/dynamic_debug/control | grep hello

# 启用某个文件的调试
echo 'file hello_drv.c +p' > /sys/kernel/debug/dynamic_debug/control

# 启用某个函数的调试
echo 'func hello_open +p' > /sys/kernel/debug/dynamic_debug/control
```

代码中使用`pr_debug()`或`dev_dbg()`：
```c
pr_debug("entering hello_open\n");
dev_dbg(hello_device, "read %zu bytes\n", count);
```

### 方法4：崩溃分析

如果驱动导致内核崩溃（oops或panic），会打印寄存器信息和调用栈。关键信息：

```
Internal error: Oops - BUG: 0 [#1] PREEMPT SMP ARM
Process hello_test (pid: 123, stack limit = 0x...)
CPU: 0 PID: 123 Comm: hello_test Tainted: G           O
PC is at hello_read+0x24/0x60 [hello_drv]
LR is at vfs_read+0x88/0x1c0
...
Stack:
[<bf000000>] hello_read+0x0/0x60 [hello_drv]
[<80001234>] vfs_read+0x88/0x1c0
[<80005678>] sys_read+0x40/0x80
```

- `PC`（Program Counter）：出错的地址
- `LR`（Link Register）：函数返回地址
- `Stack`：调用栈

用`addr2line`可以定位到源码行号：

```bash
arm-none-linux-gnueabihf-addr2line -e hello_drv.ko bf000000
```

### 方法5：KGDB（内核调试器）

内核支持类似gdb的远程调试。需要在启动参数中加上：

```
kgdboc=ttyS0,115200 kgdbwait
```

然后用gdb远程连接。这个方法比较复杂，适合深入调试时使用。

## 实战：一个带读写的LED驱动

来个更实际的例子——LED驱动。支持开关控制和状态查询。

```c
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/gpio.h>
#include <linux/delay.h>

#define DEVICE_NAME "led"
#define LED_GPIO 130  // 假设LED连接到GPIO130

static int major_num;
static struct cdev led_cdev;
static struct class *led_class;
static struct device *led_device;
static int led_state = 0;

static int led_open(struct inode *inode, struct file *file)
{
    return 0;
}

static int led_release(struct inode *inode, struct file *file)
{
    return 0;
}

static ssize_t led_read(struct file *file, char __user *buf,
                        size_t count, loff_t *ppos)
{
    char state_str[16];
    int len;

    if (*ppos > 0)
        return 0;

    len = snprintf(state_str, sizeof(state_str), "%d\n", led_state);
    if (len > count)
        len = count;

    if (copy_to_user(buf, state_str, len) != 0)
        return -EFAULT;

    *ppos += len;
    return len;
}

static ssize_t led_write(struct file *file, const char __user *buf,
                         size_t count, loff_t *ppos)
{
    char cmd;
    int new_state;

    if (count != 2)  // 只接受单个字符+'\n'
        return -EINVAL;

    if (copy_from_user(&cmd, buf, 1) != 0)
        return -EFAULT;

    if (cmd == '1') {
        new_state = 1;
    } else if (cmd == '0') {
        new_state = 0;
    } else {
        return -EINVAL;
    }

    if (new_state != led_state) {
        gpio_set_value(LED_GPIO, new_state);
        led_state = new_state;
        printk(KERN_INFO "led: turned %s\n", led_state ? "on" : "off");
    }

    return count;
}

static long led_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    switch (cmd) {
    case 0:
        gpio_set_value(LED_GPIO, 0);
        led_state = 0;
        break;
    case 1:
        gpio_set_value(LED_GPIO, 1);
        led_state = 1;
        break;
    default:
        return -EINVAL;
    }
    return 0;
}

static struct file_operations led_fops = {
    .owner = THIS_MODULE,
    .open = led_open,
    .release = led_release,
    .read = led_read,
    .write = led_write,
    .unlocked_ioctl = led_ioctl,
};

static int __init led_init(void)
{
    int ret;
    dev_t dev;

    // 申请GPIO
    ret = gpio_request(LED_GPIO, "led");
    if (ret < 0) {
        printk(KERN_ERR "led: failed to request GPIO %d\n", LED_GPIO);
        return ret;
    }

    // 配置为输出
    gpio_direction_output(LED_GPIO, 0);

    // 申请设备号
    ret = alloc_chrdev_region(&dev, 0, 1, DEVICE_NAME);
    if (ret < 0) {
        gpio_free(LED_GPIO);
        return ret;
    }
    major_num = MAJOR(dev);

    // 初始化cdev
    cdev_init(&led_cdev, &led_fops);
    ret = cdev_add(&led_cdev, dev, 1);
    if (ret < 0) {
        unregister_chrdev_region(MKDEV(major_num, 0), 1);
        gpio_free(LED_GPIO);
        return ret;
    }

    // 创建class和device
    led_class = class_create(THIS_MODULE, DEVICE_NAME);
    if (IS_ERR(led_class)) {
        cdev_del(&led_cdev);
        unregister_chrdev_region(MKDEV(major_num, 0), 1);
        gpio_free(LED_GPIO);
        return PTR_ERR(led_class);
    }

    led_device = device_create(led_class, NULL, dev, NULL, DEVICE_NAME);
    if (IS_ERR(led_device)) {
        class_destroy(led_class);
        cdev_del(&led_cdev);
        unregister_chrdev_region(MKDEV(major_num, 0), 1);
        gpio_free(LED_GPIO);
        return PTR_ERR(led_device);
    }

    printk(KERN_INFO "led: module loaded, GPIO=%d, major=%d\n", LED_GPIO, major_num);
    return 0;
}

static void __exit led_exit(void)
{
    device_destroy(led_class, MKDEV(major_num, 0));
    class_destroy(led_class);
    cdev_del(&led_cdev);
    unregister_chrdev_region(MKDEV(major_num, 0), 1);
    gpio_set_value(LED_GPIO, 0);
    gpio_free(LED_GPIO);
    printk(KERN_INFO "led: module unloaded\n");
}

module_init(led_init);
module_exit(led_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("IMX-Forge");
MODULE_DESCRIPTION("A simple LED driver");
```

测试方法：

```bash
# 开灯
echo 1 > /dev/led

# 关灯
echo 0 > /dev/led

# 查询状态
cat /dev/led

# 用ioctl控制
./led_ioctl 1  # 需要自己写测试程序
```

## 驱动开发常见问题

### Q1: 编译时提示undefined reference

这类错误通常是没配置内核选项。比如用到GPIO函数时，需要在`make menuconfig`中开启：

```
Device Drivers  --->
    GPIO Support  --->
        [*] /sys/class/gpio/... (sysfs interface)
```

### Q2: insmod时提示Invalid module format

这通常是内核版本不匹配。模块必须用与运行内核相同的源码编译。

检查方法：
```bash
modinfo hello_drv.ko | grep vermagic
uname -r
```

### Q3: 加载后没有输出

可能是printk级别太高，没显示。修改日志级别：
```bash
sudo echo 8 > /proc/sys/kernel/printk
```

### Q4: copy_to_user返回错误

这是权限问题或地址问题。检查用户空间缓冲区是否有效，不要在原子上下文中调用这类函数。

### Q5: 设备文件打开失败

检查：
1. 设备文件是否存在（`ls -l /dev/your_device`）
2. 权限是否正确
3. 驱动是否真的加载了（`lsmod | grep your_driver`）
4. dmesg里有没有错误信息

## 总结

到这里，你应该掌握了驱动开发的基础知识。虽然示例很简单，但框架是通用的：

1. 定义file_operations结构体
2. 实现各个操作函数
3. 在init中注册设备
4. 在exit中清理资源

驱动开发的难点不在于API的使用，而在于对硬件的理解和内核机制的掌握。后续你可以学习：
- 设备树和驱动的匹配机制（platform驱动）
- 并发控制（互斥锁、自旋锁）
- 中断处理
- DMA操作
- 高级字符驱动（poll、mmap、异步通知）

下一章，我们来看看内核启动过程和调试方法。了解内核是如何从零开始启动的，有助于你更好地理解整个系统的工作原理，也能在遇到启动问题时快速定位原因。

你已经成功编译了内核，现在让我们看看内核是如何启动的！
