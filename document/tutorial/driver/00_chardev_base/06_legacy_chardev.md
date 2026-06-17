# 老API字符设备驱动 - 从零开始踩坑实录

马上准备写驱动了，可以先看看如何配置clangd环境确保写代码丝滑补全和0红线！[06p_ide_setup](06p_ide_setup.md)

## 前言：我们为什么要折腾这个

前面几节我们把理论都过了一遍：MMU 怎么把虚拟地址变成物理地址，内核为什么不让我们直接访问物理内存，`ioremap` 和 `readl/writel` 这对搭档怎么帮我们绕过这些限制。但说实话，光看理论真的很虚，代码不跑起来，永远不知道哪里会炸。

现在我们要写一个字符设备驱动。但先别急着去搞硬件，我们从最简单的**虚拟字符设备**开始。这个驱动不会点亮任何 LED，它只是在内核和用户空间之间传递数据。为什么要从虚拟设备开始？因为这样可以让我们专注于核心概念，不用操心硬件寄存器、时钟使能、GPIO 配置这些乱七八糟的细节。出问题了也更容易定位，毕竟排除了硬件因素这个大变量。

## 第一步：先搞清楚"老API"是什么

说实话，当我们第一次看到 `register_chrdev` 这个函数的时候，感觉还挺友好的。在老内核时代，注册一个字符设备驱动真的非常简单，简单到一行代码就能搞定：

```c
int register_chrdev(unsigned int major, const char *name,
                    const struct file_operations *fops);
```

参数也就三个：major 是主设备号，name 是设备名称（会出现在 `/proc/devices` 里），fops 是指向 `file_operations` 结构体的指针。返回值也很直观，成功就返回主设备号，失败就返回负数错误码。

但事情没这么简单。当我们真正开始写代码的时候，问题一个接一个地冒出来了。

## 第二步：第一次尝试——写个最简单的版本

我们先写一个最基本的版本，看看会发生什么。首先引入必要的头文件：

```c
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/printk.h>
#include <linux/string.h>
```

然后定义一些宏和全局变量。这里我们硬编码了主设备号为 `200`，说实话这个做法其实很粗糙，但作为第一次实验，我们先把路跑通再谈规范：

```c
static const char* CHARDEV_NAME = "AES_Chardev";
static const int CHARDEV_MAJOR = 200;

#define BUFFER_SIZE (100)
static char buf_read[BUFFER_SIZE] = {0};
static char buf_write[BUFFER_SIZE] = {0};
#undef BUFFER_SIZE

static const char* kFixedMessage = "Hello from Kernel! Message Sent from the module!";
```

接下来是 `file_operations` 结构体。Linux 驱动最核心的设计思想，就是把硬件抽象成一个文件。用户程序用 `open`、`read`、`write` 来操作设备，而内核需要知道当这些系统调用发生时，该跳转到哪段代码执行。这个映射关系就定义在 `file_operations` 结构体里。

我们先写一个最简单的 read 函数：

```c
static ssize_t aes_chardev_read(struct file* filp, char __user* buf, size_t cnt, loff_t* offt) {
    memcpy(buf_read, kFixedMessage, strlen(kFixedMessage) + 1);
    const unsigned long kRetValue = copy_to_user(buf, buf_read, cnt);
    return kRetValue;
}
```

看起来没什么问题，对吧？我们把固定消息复制到缓冲区，然后用 `copy_to_user` 把数据发送给用户空间。其他几个函数也更简单，基本上就是打印个日志就完事：

```c
static int aes_chardev_open(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called open!\n", CHARDEV_NAME);
    return 0;
}

static ssize_t aes_chardev_write(struct file* filp, const char __user* buf, size_t cnt, loff_t* offt) {
    pr_info("Device: %s called write!\n", CHARDEV_NAME);
    return cnt;
}

static int aes_chardev_release(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called close!\n", CHARDEV_NAME);
    return 0;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = aes_chardev_open,
    .read = aes_chardev_read,
    .write = aes_chardev_write,
    .release = aes_chardev_release,
};
```

最后是模块的加载和卸载函数：

```c
static int __init chardev_base_00_init(void) {
    const int kResult = register_chrdev(CHARDEV_MAJOR, CHARDEV_NAME, &fops);
    if (kResult != 0) {
        pr_warn("Failed to register the chardev region! kResult=%d\n", kResult);
        return kResult;
    }

    pr_info("%s load successfully!\n", CHARDEV_NAME);
    return kResult;
}

static void __exit chardev_base_00_exit(void) {
    pr_info("=== chardev_base_00 module unloaded ===\n");
    unregister_chrdev(CHARDEV_MAJOR, CHARDEV_NAME);
    pr_info("========================\n");
}

module_init(chardev_base_00_init);
module_exit(chardev_base_00_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("Basic Char Dev Usage");
MODULE_VERSION("1.0");
```

到这里我们觉得应该没什么问题了，赶紧编译一下看看效果。

## 第三步：第一次运行——缓冲区溢出警告

编译很顺利，`make` 一把过，生成了 `chardev_base_00_driver.ko` 文件。我们把驱动拷贝到开发板，然后加载：

```bash
insmod chardev_base_00_driver.ko
```

加载成功！现在创建设备节点：

```bash
mknod /dev/aes c 200 0
```

然后试试读取：

```bash
cat /dev/aes
```

**直接炸了：**

```
[  138.137579] Device: AES_Chardev called open!
[  138.137668] Device: AES_Chardev called read!
[  138.137684] ------------[ cut here ]------------
[  138.137695] WARNING: mm/maccess.c:234 at __copy_overflow+0x24/0x34
[  138.158630] Buffer overflow detected (100 < 4096)!  ← 关键信息！
[  138.163512] Modules linked in: chardev_base_00_driver(O)
[  138.168890] CPU: 0 UID: 0 PID: 66 Comm: cat Tainted: G        W  O        7.1.0-dirty #1
[  138.179550] Tainted: [W]=WARN, [O]=OOT_MODULE
[  138.183924] Hardware name: Freescale i.MX6 Ultralite (Device Tree)
[  138.190125] Call trace:
[  138.190149]  unwind_backtrace from show_stack+0x10/0x14
[  138.197984]  show_stack from dump_stack_lvl+0x38/0x48
[  138.203106]  dump_stack_lvl from __warn+0x84/0xec
[  138.207881]  __warn from warn_slowpath_fmt+0x94/0xc8
[  138.212906]  warn_slowpath_fmt from __copy_overflow+0x24/0x34
[  138.218719]  __copy_overflow from aes_chardev_read+0x54/0xdc [chardev_base_00_driver]
```

看到堆栈跟踪我们才意识到问题出在哪里。关键信息在这一行：`Buffer overflow detected (100 < 4096)!`

我们回头看看代码，问题一下子就清楚了。我们的缓冲区 `buf_read` 只有 100 字节，但 `cat` 程序默认请求 4096 字节（一页内存）。我们直接把用户请求的大小 `cnt` 传给了 `copy_to_user`，结果就是试图从 100 字节的缓冲区复制 4096 字节。这就是为什么内核会检测到缓冲区溢出。

说实话，这个坑我们真的踩了很久。一开始还以为是 `copy_to_user` 用法有问题，翻半天内核文档才发现问题出在长度检查上。

修复方法也很简单，取实际长度和请求长度的较小值就可以了：

```c
static ssize_t aes_chardev_read(struct file* filp, char __user* buf, size_t cnt, loff_t* offt) {
    unsigned int len = strlen(kFixedMessage);

    // 防止溢出：取实际长度和请求长度的较小值
    if (cnt < len)
        len = cnt;

    if (copy_to_user(buf, kFixedMessage, len)) {
        pr_warn("Failed to send data to user\n");
        return -EFAULT;
    }

    pr_info("Successfully Send data to user!\n");
    return len;
}
```

这里我们还做了一处改动：直接用 `kFixedMessage` 而不是先复制到 `buf_read`，反正 `copy_to_user` 会安全地处理数据拷贝。

## 第四步：第二次运行——无限循环噩梦

修复了缓冲区溢出问题，我们重新编译加载，然后再次运行 `cat /dev/aes`。这次没有报错了，但是出现了一个新问题：

```bash
cat /dev/aes
Hello from Kernel! Message Sent from the module!Hello from Kernel! Message Sent from the module!Hello from Kernel! Message Sent from the module!Hello from Kernel! Message Sent from the module!...
[无限循环，需要 Ctrl+C 停止]
```

屏幕上不停地输出相同的消息，只能用 Ctrl+C 强制终止。

这个问题真的困扰了我们很久。后来我们仔细想了想 `cat` 程序的工作原理，才明白问题所在。`cat` 程序的内部逻辑大概是这个样子的：

```c
while (1) {
    n = read(fd, buf, 4096);
    if (n == 0) break;  // EOF（文件结束）← 关键！
    write(1, buf, n);
}
```

我们的驱动问题在于，每次 `read()` 调用都返回数据，从不返回 0（EOF）。所以 `cat` 认为文件还没结束，就一直读下去。

解决办法是用偏移量来管理文件位置。第一次 `read()` 之后更新偏移量，后续调用检测到偏移量大于 0 就返回 0：

```c
static ssize_t aes_chardev_read(struct file* filp, char __user* buf, size_t cnt, loff_t* offt) {
    pr_info("Device: %s called read!\n", CHARDEV_NAME);

    // 已经读过一次 → 返回 EOF
    if (*offt > 0) {
        return 0;  // 终止读取循环
    }

    unsigned int len = strlen(kFixedMessage);
    if (cnt < len)
        len = cnt;

    // 更新偏移量（关键！）
    *offt += len;

    if (copy_to_user(buf, kFixedMessage, len)) {
        pr_warn("Failed to send data to user\n");
        return -EFAULT;
    }

    pr_info("Successfully Send data to user!\n");
    return len;
}
```

修复后再试一次：

```bash
cat /dev/aes
Hello from Kernel! Message Sent from the module!
[正常结束，不再循环]
```

## 第五步：第三个坑——返回值语义错误

在调试过程中，我们还发现了一个更隐蔽的问题：返回值的语义错误。这个问题之所以隐蔽，是因为它不会直接导致程序崩溃，而是会让用户程序收到错误的信息。

我们一开始的代码是这样的：

```c
const unsigned long kRetValue = copy_to_user(buf, buf_read, cnt);
return kRetValue;  // ❌ 错误！
```

这里的问题在于，`copy_to_user` 的返回值语义和 `read` 系统调用的返回值语义是相反的。`copy_to_user` 返回的是**未能复制的字节数**，如果完全成功就返回 0；而 `read` 系统调用应该返回**成功读取的字节数**。如果直接返回 `copy_to_user` 的结果，用户程序就会以为读取了 0 字节。

正确的做法是检查 `copy_to_user` 的返回值，如果非 0 就返回错误码，否则返回实际传输的字节数：

```c
if (copy_to_user(buf, kFixedMessage, len)) {
    return -EFAULT;  // 返回错误码
}
return len;  // 返回实际传输的字节数
```

`write` 函数也是类似的处理方式：

```c
static ssize_t aes_chardev_write(struct file* filp, const char __user* buf, size_t cnt, loff_t* offt) {
    pr_info("Device: %s called write!\n", CHARDEV_NAME);

    size_t len = cnt;

    // 防止溢出
    if (len > sizeof(buf_write) - 1)
        len = sizeof(buf_write) - 1;

    if (copy_from_user(buf_write, buf, len)) {
        pr_warn("Failed to receive data from user\n");
        return -EFAULT;
    }

    buf_write[len] = '\0';

    pr_info("Kernel module has received from data: %s\n", buf_write);
    memset(buf_write, 0, cnt);
    return len;
}
```

这里多说一句，千万别以为 `copy_from_user` 和 `copy_to_user` 只是简单的 `memcpy`。这两个函数做了很多额外的工作，比如检查用户空间指针是否有效、处理页面错误等。直接解引用用户空间的指针是绝对禁止的，那会导致内核崩溃或者安全漏洞。

## 第六步：完整的测试代码

到这里，我们的驱动代码终于能正常工作了。但为了验证它的功能，我们还需要一个用户空间的测试程序：

```c
#include "stdio.h"
#include "unistd.h"
#include "sys/types.h"
#include "sys/stat.h"
#include "fcntl.h"
#include "stdlib.h"
#include "string.h"

int main(int argc, char *argv[])
{
    int fd, retvalue;
    char *filename;
    unsigned char databuf[1];

    if(argc != 3){
        printf("Error Usage!\r\n");
        return -1;
    }

    filename = argv[1];

    fd = open(filename, O_RDWR);
    if(fd < 0){
        printf("file %s open failed!\r\n", argv[1]);
        return -1;
    }

    databuf[0] = atoi(argv[2]);

    /* 向/dev/aes 文件写入数据 */
    retvalue = write(fd, databuf, sizeof(databuf));
    if(retvalue < 0){
        printf("Control Failed!\r\n");
        close(fd);
        return -1;
    }

    retvalue = close(fd);
    if(retvalue < 0){
        printf("file %s close failed!\r\n", argv[1]);
        return -1;
    }

    return 0;
}
```

编译测试程序：

```bash
arm-linux-gnueabihf-gcc aes_chardev_test.c -o aes_chardev_test
```

然后拷贝到开发板测试：

```bash
# 测试写入
./aes_chardev_test /dev/aes 123

# 查看内核日志
dmesg | tail -10
```

如果一切正常，你应该能在内核日志里看到驱动打印的消息。

## 第七步：老API的问题暴露出来了

折腾完这一轮，我们开始感觉到老API的一些问题。这些问题在一开始的时候不太明显，但当你开始写更复杂的驱动时，它们会变得越来越烦人。

**第一个问题是设备号冲突。** 我们硬编码了主设备号为 `200`，这个数字是我们"猜"的，假设它没有被占用。但如果系统里已经有驱动占用了这个号，我们的驱动注册就会失败。正规的做法应该是让内核动态分配一个空闲的设备号，但老API在这方面做得不好。

**第二个问题是资源浪费。** 我们的驱动只需要一个设备（一对设备号），但 `register_chrdev` 会粗暴地霸占整个主设备号下的所有 1048576 个次设备号。在一个资源紧张的嵌入式系统里，这简直是在犯罪。

**第三个问题是手动创建节点。** 每次加载驱动后，我们都必须手动执行 `mknod` 命令创建 `/dev` 节点。如果忘记这一步，用户程序就无法访问设备。而且用户必须知道正确的主设备号和次设备号，这对新手来说很不友好。

这些问题就是为什么内核后来引入了新的字符设备API。下一章我们会学习新API，它虽然代码量多一些，但解决了上述所有问题：动态分配设备号避免冲突，按需申请设备号避免浪费，还能自动创建设备节点无需手动 mknod。

## 调试技巧分享

在这一章的折腾过程中，我们总结了一些有用的调试技巧，希望能帮读者少走弯路。

**查看内核日志是基本操作：**

```bash
# 实时监控
dmesg -w

# 查看最近的日志
dmesg | tail -20

# 过滤特定消息
dmesg | grep "AES_Chardev"

# 清空日志（方便重新观察）
dmesg -c
```

**理解堆栈跟踪很重要。** 当内核打印出 Call trace 时，不要被那一堆地址吓到。关键信息通常在最后几行，比如 `__copy_overflow from aes_chardev_read+0x54/0xdc`，这告诉我们在 `aes_chardev_read` 函数里调用了 `__copy_overflow`，偏移量是 `0x54`。根据这个信息，你可以快速定位到问题代码。

**调试步骤建议：** 首先确认问题现象，然后查看内核日志，分析错误信息，定位问题代码，最后修复验证。这个流程看起来很基础，但当我们急着解决问题的时候，很容易跳过某些步骤，导致反而花了更多时间。

## 本章小结

说实话，这一章我们踩的坑比预想的要多。但正是这些坑，让我们真正理解了字符设备驱动的核心概念。

我们学到了什么？

第一，永远不要信任用户输入。用户提供的 `cnt` 可能比你想象的要大得多，必须做好边界检查。

第二，理解并实现正确的文件语义。`read()` 必须在适当的时候返回 0（EOF），否则用户程序会陷入无限循环。

第三，正确处理返回值。`copy_to_user` 和 `copy_from_user` 的返回值语义和系统调用不同，不能直接返回。

第四，使用偏移量管理文件位置。这不仅是实现正确语义的需要，也是维护驱动状态的重要手段。

老API（`register_chrdev`）虽然简单直接，但它的局限性也很明显。下一章我们会学习新字符设备驱动API，它会让你看到更规范、更优雅的驱动开发方式。但不管用哪种API，本章学到的这些核心概念都是通用的。

---

**相关文档**：
- [新字符设备驱动 API 概览](12_new_chardev_api_overview.md)
- [新 API 驱动代码深度解析](17_new_api_driver_analysis.md)
