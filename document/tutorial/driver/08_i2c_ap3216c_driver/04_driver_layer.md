---
title: AP3216C 驱动层实现
---

# AP3216C 驱动层实现 —— I2C 框架与字符设备的合体

前面两节我们把框架和适配器都摸透了，现在终于到了真正动代码的时候。这一节我们要把 AP3216C 的驱动主体写出来——它是一个"I2C 设备驱动"和"字符设备驱动"的合体：对下，用 I2C 框架的 API 跟芯片通信；对上，用字符设备的接口把数据暴露给用户空间。涉及两个源码文件：`ap3216creg.h` 放寄存器定义，`ap3216c.c` 放驱动主体。我们按"寄存器表 → 设备结构体 → 读写封装 → 数据读取 → probe/remove → 字符设备接口 → 注册"的顺序，一块一块把它搭起来。

## 寄存器定义：先把词汇表列出来

驱动和芯片对话，靠的是寄存器地址。为了不让代码里满是魔术数字，我们把这些地址统一收进 `ap3216creg.h`：

```c
/* ap3216creg.h */
#ifndef AP3216C_H
#define AP3216C_H

#define AP3216C_SYSTEMCONG   0x00  /* 系统配置寄存器 */
#define AP3216C_INTSTATUS    0x01  /* 中断状态寄存器 */
#define AP3216C_INTCLEAR     0x02  /* 中断清除寄存器 */
#define AP3216C_IRDATALOW    0x0A  /* IR  数据低字节 */
#define AP3216C_IRDATAHIGH   0x0B  /* IR  数据高字节 */
#define AP3216C_ALSDATALOW   0x0C  /* ALS 数据低字节 */
#define AP3216C_ALSDATAHIGH  0x0D  /* ALS 数据高字节 */
#define AP3216C_PSDATALOW    0x0E  /* PS  数据低字节 */
#define AP3216C_PSDATAHIGH   0x0F  /* PS  数据高字节 */

#endif
```

注意 IR / ALS / PS 这三组数据寄存器的地址是**连续**的（`0x0A`~`0x0F`），这个细节后面读数据时会用到——我们可以从一个起点 `AP3216C_IRDATALOW` 开始，连读六个字节就把三路数据全捞回来。

## 设备结构体：把状态拢到一起

每个字符设备驱动都需要一个结构体来挂自己的全部状态。AP3216C 驱动的设备结构体长这样：

```c
/* ap3216c.c */
#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/delay.h>
#include <linux/uaccess.h>
#include "ap3216creg.h"

#define AP3216C_NAME "ap3216c"

struct ap3216c_dev {
    dev_t               devid;    /* 设备号 */
    struct cdev         cdev;     /* 字符设备 */
    struct class       *class;    /* 设备类 */
    struct device      *device;   /* 设备节点 */
    struct i2c_client  *client;   /* 关联的 i2c_client —— 通信靠它 */
    unsigned short      ir;       /* IR  数据 */
    unsigned short      als;      /* ALS 数据 */
    unsigned short      ps;       /* PS  数据 */
};
```

这里有个和老教程不一样的设计：我们不再用一个 `void *private_data` 黑箱指针存 `i2c_client`，而是堂堂正正地声明一个 `struct i2c_client *client` 成员。类型明确，编译器能帮你查错，读代码的人也不用去猜这个 `void *` 到底指什么。`ir` / `als` / `ps` 三个字段缓存最新一次读到的传感器数据，等用户空间来 `read` 时直接拷给它。

## 寄存器读写：先看 i2c_transfer 的"原始姿势"

我们调的那些读写，最终都会落到适配器的 `master_xfer` 上——但内核给设备驱动准备的接口有好几层，从"亲手拼消息"到"一行搞定"都有。为了搞懂机制，我们先看最原始的那层：亲手拼 `i2c_msg` 再交给 `i2c_transfer`。

I2C 读一个寄存器，本质上是个**两步动作**——先发寄存器地址（一次写），再收数据（一次读），所以得拼两条 `i2c_msg`：

```c
/* 教学版：手拼 i2c_msg 读取一个寄存器（和 i2c_smbus_read_byte_data 等价） */
static int ap3216c_read_reg_xfer(struct ap3216c_dev *dev, u8 reg)
{
    struct i2c_client *client = dev->client;
    struct i2c_msg msg[2];
    u8 val;
    int ret;

    /* msg[0]：写操作，把要读的寄存器地址发出去 */
    msg[0].addr  = client->addr;   /* 从机地址 */
    msg[0].flags = 0;              /* 0 = 写 */
    msg[0].buf   = &reg;           /* 发的内容是寄存器地址 */
    msg[0].len   = 1;

    /* msg[1]：读操作，把数据收回来 */
    msg[1].addr  = client->addr;
    msg[1].flags = I2C_M_RD;       /* I2C_M_RD = 读 */
    msg[1].buf   = &val;
    msg[1].len   = 1;

    ret = i2c_transfer(client->adapter, msg, 2);
    return (ret == 2) ? val : -EREMOTEIO;
}
```

你把 `i2c_msg` 想象成一封"贴好邮票、写好地址，但还没投递的信"：`addr` 是收件人（I2C 地址），`flags` 决定是寄信还是索取，`buf` 是信纸，`len` 是几页。`i2c_transfer` 一次把这组消息全发出去，返回值是成功投递的消息数——我们发了两条，所以必须返回 `2` 才算成功，少了就说明通信出了问题，我们用 `-EREMOTEIO`（对端 I/O 失败）回报。这套"写地址 + 读数据"的两步走，是绝大多数带寄存器地址的 I2C 设备的标准时序，少一步芯片就不理你。

理解了这个机制，你就会明白为什么内核还要再封一层更省事的接口。对于"8 位寄存器、8 位数据"这种最常见的情况，亲手拼两条 `msg` 实在啰嗦，于是内核提供了 `i2c_smbus_read_byte_data` / `i2c_smbus_write_byte_data`——它们内部干的事和上面这段一模一样，只是替你把 `i2c_msg` 拼好了：

```c
/* 主线版：用 SMBus 便捷函数，一行搞定 */
static int ap3216c_read_reg(struct ap3216c_dev *dev, u8 reg)
{
    return i2c_smbus_read_byte_data(dev->client, reg);
}

static int ap3216c_write_reg(struct ap3216c_dev *dev, u8 reg, u8 val)
{
    return i2c_smbus_write_byte_data(dev->client, reg, val);
}
```

`i2c_smbus_read_byte_data(client, reg)` 返回的就是读到的字节值（出错返回负数），`i2c_smbus_write_byte_data(client, reg, val)` 写一个字节。能用这两个函数就别再手拼 `i2c_msg`——代码短、错不了。我们这个驱动的正式代码就用这一对。

::: tip 什么时候还得回去手拼 i2c_msg
当设备的读写时序比较"非标准"时，便捷函数就不够用了：比如某些器件要求一次写多个寄存器、或者读的时候首字节格式特殊。那种情况就得退回 `i2c_transfer` 亲手拼消息。另外内核还提供 `i2c_smbus_read_i2c_block_data` / `i2c_smbus_write_i2c_block_data` 做连续多字节读写，比循环单字节读效率更高——AP3216C 连读六个字节其实可以用块读，这里为了讲解清晰先用循环单字节。
:::

## 读三路数据：ap3216c_readdata

读写封装好了，读三路数据就是顺着连续的寄存器地址一个个读、再按位拼装：

```c
/* 读取并解析 IR / ALS / PS 三路数据 */
static void ap3216c_readdata(struct ap3216c_dev *dev)
{
    u8 i, buf[6];

    /* 0x0A~0x0F 连续六个字节：IR_L/IR_H/ALS_L/ALS_H/PS_L/PS_H */
    for (i = 0; i < 6; i++)
        buf[i] = ap3216c_read_reg(dev, AP3216C_IRDATALOW + i);

    /* IR：10 位有效。bit7=1 表示溢出无效 */
    if (buf[0] & 0x80)
        dev->ir = 0;
    else
        dev->ir = ((unsigned short)buf[1] << 2) | (buf[0] & 0x03);

    /* ALS：16 位 */
    dev->als = ((unsigned short)buf[3] << 8) | buf[2];

    /* PS：bit6=1 表示溢出无效 */
    if (buf[4] & 0x40)
        dev->ps = 0;
    else
        dev->ps = ((unsigned short)(buf[5] & 0x3F) << 4) | (buf[4] & 0x0F);
}
```

这里最容易翻车的是那些位掩码——`buf[0] & 0x80` 判断 IR 是否溢出、`buf[1] << 2 | buf[0] & 0x03` 把散在两个字节里的 10 位 IR 数据拼起来。这些规则全来自数据手册，少一个 `& 0x03` 或者左移位数写错，读出来的数据就是乱码。这种地方别凭感觉，对着手册抄。

## probe：把一切都串起来

`probe` 是驱动真正干活的地方。设备匹配成功后内核回调它，我们要在这儿把字符设备搭起来、把 `i2c_client` 存好、再把芯片初始化成工作状态：

```c
static int ap3216c_probe(struct i2c_client *client)
{
    struct ap3216c_dev *dev;
    int ret;

    /* 1、分配设备结构体，devm_ 版本会在设备移除时自动释放 */
    dev = devm_kzalloc(&client->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;
    dev->client = client;
    i2c_set_clientdata(client, dev);   /* 把 dev 挂到 client 上，remove 时能取回 */

    /* 2、注册字符设备号 */
    ret = alloc_chrdev_region(&dev->devid, 0, 1, AP3216C_NAME);
    if (ret)
        return ret;

    /* 3、初始化并添加 cdev */
    cdev_init(&dev->cdev, &ap3216c_ops);
    ret = cdev_add(&dev->cdev, dev->devid, 1);
    if (ret)
        goto del_region;

    /* 4、创建类 —— 注意 class_create 现在是单参数，不再要 THIS_MODULE */
    dev->class = class_create(AP3216C_NAME);
    if (IS_ERR(dev->class)) {
        ret = PTR_ERR(dev->class);
        goto del_cdev;
    }

    /* 5、创建设备节点 /dev/ap3216c */
    dev->device = device_create(dev->class, NULL, dev->devid, NULL, AP3216C_NAME);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto destroy_class;
    }

    /* 6、初始化 AP3216C：先复位，再开启 ALS+PS+IR */
    ap3216c_write_reg(dev, AP3216C_SYSTEMCONG, 0x04);   /* 0x04 = 软复位 */
    msleep(10);                                         /* 复位需要一点时间 */
    ap3216c_write_reg(dev, AP3216C_SYSTEMCONG, 0x03);   /* 0x03 = 开启 ALS+PS+IR */

    return 0;

destroy_class:
    class_destroy(dev->class);
del_cdev:
    cdev_del(&dev->cdev);
del_region:
    unregister_chrdev_region(dev->devid, 1);
    return ret;
}
```

这段代码里有几处现代写法值得专门点出来。`devm_kzalloc(&client->dev, ...)` 用的是托管分配——它绑在 `client->dev` 上，设备移除时内核自动帮你 `kfree`，所以 `remove` 里我们不用（也不能）再去释放 `dev`。`i2c_set_clientdata(client, dev)` 把设备结构体挂到 `i2c_client` 上，这是 I2C 子系统的标准玩法，等会儿 `remove` 里用 `i2c_get_clientdata` 就能原样取回。`class_create(AP3216C_NAME)`——注意，**只有一个参数**，老教程里那个 `THIS_MODULE` 早从 6.4 开始就被砍掉了，你要是写成双参数，6.12 / 7.1 直接编译报错。最后芯片初始化那两句是 AP3216C 的"开机仪式"：写 `0x04` 软复位、睡 10ms 等它缓过来、再写 `0x03` 把三路采集全打开。

`probe` 里出错处理用了一串 `goto` 标签，按"先创建的后清理"的相反顺序回滚。这是内核驱动里几乎强制的写法——别嫌丑，它保证任何一步失败都不会留下半拉子资源。

## remove：void，按相反顺序清理

`remove` 是 `probe` 的镜像，而且在新内核里它**没有返回值**：

```c
static void ap3216c_remove(struct i2c_client *client)
{
    struct ap3216c_dev *dev = i2c_get_clientdata(client);

    device_destroy(dev->class, dev->devid);
    class_destroy(dev->class);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->devid, 1);
    /* dev 由 devm_kzalloc 分配，这里不用手动释放 */
}
```

`i2c_get_clientdata` 取回 `probe` 里存进去的 `dev`，然后按 `device_destroy → class_destroy → cdev_del → unregister_chrdev_region` 的顺序逐个回收，和 `probe` 里创建的顺序正好反过来。注意这里**没有 `kfree(dev)`**——因为它是 `devm_kzalloc` 分配的，内核会自动收回。如果你在这儿再手动 `kfree` 一次，等着收获一个 double-free 的内核崩溃。

## 字符设备接口：open / read / release

用户空间通过 `/dev/ap3216c` 跟驱动打交道，交互方式由 `file_operations` 定义。这里我们用 `container_of` 从 `inode->i_cdev` 反推出设备结构体——这是支持多设备的标准写法，比全局变量专业得多：

```c
static int ap3216c_open(struct inode *inode, struct file *filp)
{
    /* 从 inode 里的 cdev 反推设备结构体，存进 filp->private_data */
    struct ap3216c_dev *dev = container_of(inode->i_cdev,
                                           struct ap3216c_dev, cdev);
    filp->private_data = dev;
    return 0;
}

static ssize_t ap3216c_read(struct file *filp, char __user *buf,
                            size_t cnt, loff_t *off)
{
    struct ap3216c_dev *dev = filp->private_data;
    unsigned short data[3];

    ap3216c_readdata(dev);
    data[0] = dev->ir;
    data[1] = dev->als;
    data[2] = dev->ps;

    if (cnt > sizeof(data))
        cnt = sizeof(data);

    if (copy_to_user(buf, data, cnt))
        return -EFAULT;

    return cnt;
}

static int ap3216c_release(struct inode *inode, struct file *filp)
{
    return 0;
}

static const struct file_operations ap3216c_ops = {
    .owner   = THIS_MODULE,
    .open    = ap3216c_open,
    .read    = ap3216c_read,
    .release = ap3216c_release,
};
```

`open` 里那句 `container_of(inode->i_cdev, struct ap3216c_dev, cdev)` 是精髓：`inode` 里藏着这个设备节点对应的 `cdev`，而我们的 `cdev` 就嵌在 `ap3216c_dev` 结构体里，`container_of` 反推出外层结构体的地址。拿到 `dev` 后塞进 `filp->private_data`，这样 `read` 里一行 `filp->private_data` 就能取回，不用再依赖任何全局变量——即便板子上挂了三颗 AP3216C，每路也能各管各的。`read` 里先调 `ap3216c_readdata` 刷新数据，再把 `ir/als/ps` 三个 `unsigned short` 打包 `copy_to_user` 给用户空间。

## 注册：module_i2c_driver 一行收尾

最后把驱动挂上 I2C 总线。还记得框架节里那个 `module_i2c_driver` 宏吗？这里就用上它：

```c
static const struct of_device_id ap3216c_of_match[] = {
    { .compatible = "imxaes,ap3216c" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, ap3216c_of_match);

static struct i2c_driver ap3216c_driver = {
    .driver = {
        .name           = AP3216C_NAME,
        .of_match_table = ap3216c_of_match,
    },
    .probe  = ap3216c_probe,
    .remove = ap3216c_remove,
};
module_i2c_driver(ap3216c_driver);

MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("AP3216C ambient light / proximity / IR sensor driver (modern I2C API)");
MODULE_LICENSE("GPL");
```

`of_match_table` 里的 `"imxaes,ap3216c"` 必须和设备树里那个 `compatible` 一字不差——这是驱动和设备配对的暗号，对不上 `probe` 永远不会被调用。`module_i2c_driver(ap3216c_driver)` 这一行同时替我们生成了 `module_init`（调 `i2c_add_driver`）和 `module_exit`（调 `i2c_del_driver`），还顺手设好了 `owner`，所以你既不用手写那两个函数，也不用写 `.driver.owner = THIS_MODULE`。整份驱动到这里就齐活了。

## 小结

这一节我们写完了 AP3216C 的驱动主体：用 `i2c_smbus_*` 做寄存器读写（顺手用 `i2c_transfer` 讲清了底层机制），用 `container_of` + `filp->private_data` 做多设备友好的字符设备接口，`probe` 用 `devm_kzalloc` 托管内存、用单参数 `class_create` 建节点，`remove` 是 `void`、按相反顺序清理，最后 `module_i2c_driver` 一行注册。代码是现代的、能直接在 6.12 / 7.1 上编过。但这一切要跑起来，还差最后一块拼图——设备树。下一节我们就把 AP3216C 画进内核的硬件地图里。

---

<ChapterNav variant="sub">
  <ChapterLink href="03_i2c_adapter_analysis.md" variant="sub">← I.MX6U 适配器分析</ChapterLink>
  <ChapterLink href="05_device_tree.md" variant="sub">设备树配置 →</ChapterLink>
</ChapterNav>
