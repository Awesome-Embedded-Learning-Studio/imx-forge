---
title: ICM-20608 驱动层实现
---

# ICM-20608 驱动层实现 —— SPI 框架与字符设备的合体

和 I2C 那篇一样，ICM-20608 的驱动也是个"SPI 设备驱动 + 字符设备驱动"的合体：对下用 SPI 框架的 API 跟芯片通信，对上用字符设备把数据交给用户空间。涉及两个源码文件：`icm20608reg.h` 放寄存器定义，`icm20608.c` 放驱动主体。我们按"寄存器表 → 设备结构体 → 读写封装 → 初始化与数据读取 → probe/remove → 字符设备接口 → 注册"的顺序搭起来。

## 寄存器定义

ICM-20608 的寄存器不少，我们挑后面用到的列进 `icm20608reg.h`：

```c
/* icm20608reg.h */
#ifndef ICM20608_H
#define ICM20608_H

#define ICM20608_SMPLRT_DIV   0x19   /* 采样率分频 */
#define ICM20608_GYRO_CONFIG  0x1B   /* 陀螺仪配置 */
#define ICM20608_ACCEL_CONFIG 0x1C   /* 加速度计配置 */
#define ICM20608_ACCEL_CONFIG2 0x1D
#define ICM20608_PWR_MGMT_1   0x6B   /* 电源管理 */
#define ICM20608_PWR_MGMT_2   0x6C
#define ICM20608_WHO_AM_I     0x75

/* 数据寄存器，从 0x3B 开始连续 14 字节：ax/ay/az/temp/gx/gy/gz */
#define ICM20608_ACCEL_XOUT_H 0x3B

#endif
```

注意 `0x3B` 那个注释——加速度、温度、陀螺仪的数据寄存器从 `0x3B` 开始连续排布，每个轴的高低字节紧挨着，一共 14 个字节。这个"连续"特性让我们能一次连读 14 字节把七组数据全捞回来，比一个个寄存器单读高效得多。

## 设备结构体

```c
/* icm20608.c */
#include <linux/module.h>
#include <linux/spi/spi.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/delay.h>
#include <linux/uaccess.h>
#include "icm20608reg.h"

#define ICM20608_NAME "icm20608"

struct icm20608_dev {
    dev_t              devid;
    struct cdev        cdev;
    struct class      *class;
    struct device     *device;
    struct spi_device *spi;       /* 关联的 spi_device，通信靠它 */
    signed int gyro_x_adc, gyro_y_adc, gyro_z_adc;   /* 陀螺仪原始值 */
    signed int accel_x_adc, accel_y_adc, accel_z_adc; /* 加速度原始值 */
    signed int temp_adc;                              /* 温度原始值 */
};
```

和 I2C 那篇一样，我们用明确的 `struct spi_device *spi` 成员取代老教程的 `void *private_data`。七个 `signed int` 缓存三轴陀螺仪、三轴加速度和温度的原始 ADC 值，等用户空间来 `read` 时拷出去。

## 寄存器读写：spi_write_then_read 一招鲜

ICM-20608 的读写规则我们 [01 节](01_introduction.md) 强调过：寄存器地址 bit7 置 1 是读、清 0 是写。SPI 是全双工的，但这套"发地址、收数据"的时序，内核早就封装好了——就是 `spi_write_then_read`：

```c
/* 读多个寄存器：地址 bit7 置 1 */
static int icm20608_read_regs(struct icm20608_dev *dev, u8 reg, u8 *buf, int len)
{
    u8 reg_h = reg | 0x80;   /* bit7 = 1，表示读 */
    return spi_write_then_read(dev->spi, &reg_h, 1, buf, len);
}

/* 写单个寄存器：地址 bit7 清 0 */
static int icm20608_write_reg(struct icm20608_dev *dev, u8 reg, u8 val)
{
    u8 buf[2];
    buf[0] = reg & ~0x80;    /* bit7 = 0，表示写 */
    buf[1] = val;
    return spi_write(dev->spi, buf, 2);
}
```

`spi_write_then_read(spi, &reg_h, 1, buf, len)` 干的事是：先发 1 字节（带读标志的地址），再发 `len` 个 dummy 字节同时收回 `len` 字节数据到 `buf`。它把"地址阶段"和"数据阶段"在内部拆成了两段，所以你拿到的 `buf` 里**全是有效数据，没有 dummy**——这一点比手拼 `spi_transfer` 省心太多。`spi_write(spi, buf, 2)` 是纯写：把 2 字节（地址 + 数据）一次性发出去。

如果你好奇这两个便捷函数内部到底干了什么，或者遇到它们覆盖不了的复杂时序，就得回到最底层的 `spi_transfer` + `spi_message` + `spi_sync`。我们也看一眼这个"原始姿势"，顺带讲一个老教程的雷区：

```c
/* 教学版：手拼 spi_transfer 读取（演示原理，正式代码用上面的 spi_write_then_read） */
static int icm20608_read_regs_xfer(struct icm20608_dev *dev, u8 reg, u8 *buf, int len)
{
    struct spi_message m;
    u8 tx = reg | 0x80;
    struct spi_transfer t = {
        .tx_buf = &tx,        /* 发：带读标志的地址 */
        .rx_buf = buf,        /* 收：注意 buf[0] 是 dummy，真数据从 buf[1] 起 */
        .len    = len + 1,    /* 全双工，发几个就收几个 */
        /* 老教程写的是 .delay_usecs = 10; 这个字段已经没了！现在用： */
        /* .delay = { .value = 10, .unit = SPI_DELAY_UNIT_USECS }, */
    };
    int ret;

    spi_message_init(&m);
    spi_message_add_tail(&t, &m);
    ret = spi_sync(dev->spi, &m);
    if (ret)
        return ret;
    memmove(buf, buf + 1, len);   /* 丢掉首字节 dummy */
    return 0;
}
```

你可以把 `spi_transfer` 想成一个"快递包裹"（装着要发的货、或装回货的空箱），`spi_message` 是"发货单"（把包裹按顺序串起来、中途不许插队、送完通知我）。三步走永远固定：`spi_message_init` 初始化发货单、`spi_message_add_tail` 挂包裹、`spi_sync` 同步发货（会睡眠，别在中断里调，中断里要用 `spi_async`）。

注意这段代码里我特意注释掉的那行——这是老教程最经典的雷区：**`.delay_usecs` 字段已经不存在了**。新内核里它换成了 `struct spi_delay delay`，要同时给 `.value` 和 `.unit`（`SPI_DELAY_UNIT_USECS` / `NSECS` / `SECS`）。你要是照老教程敲 `.delay_usecs = 10`，6.12 / 7.1 直接编不过。另外这个手拼版本里 `rx_buf[0]` 是 dummy，得 `memmove` 把它挪掉——而 `spi_write_then_read` 帮你省了这一步，这就是为什么正式代码推荐用它。

## 初始化与数据读取

读写封装好了，剩下的就是按数据手册写业务逻辑。初始化函数把芯片从复位状态唤醒、配好量程和采样率：

```c
static void icm20608_reginit(struct icm20608_dev *dev)
{
    icm20608_write_reg(dev, ICM20608_PWR_MGMT_1, 0x80);   /* 0x80 = 复位 */
    mdelay(50);                                           /* 复位要等一会 */
    icm20608_write_reg(dev, ICM20608_PWR_MGMT_1, 0x01);   /* 唤醒，时钟源选 PLL */
    icm20608_write_reg(dev, ICM20608_SMPLRT_DIV, 0x00);   /* 采样率不分频 */
    icm20608_write_reg(dev, ICM20608_GYRO_CONFIG, 0x18);  /* ±2000°/s */
    icm20608_write_reg(dev, ICM20608_ACCEL_CONFIG, 0x18); /* ±16g */
}
```

这里的配置值直接决定了后面读到的原始值怎么换算成物理量。陀螺仪配成 ±2000°/s、加速度计配成 ±16g，对应的灵敏度分别约是 16.4 LSB/(°/s) 和 2048 LSB/g——这两个数测试程序里会用到。

读数据就痛快了，一次连读 14 字节，再按高低字节拼成有符号数：

```c
static void icm20608_readdata(struct icm20608_dev *dev)
{
    unsigned char data[14];

    icm20608_read_regs(dev, ICM20608_ACCEL_XOUT_H, data, 14);

    dev->accel_x_adc = (signed short)((data[0]  << 8) | data[1]);
    dev->accel_y_adc = (signed short)((data[2]  << 8) | data[3]);
    dev->accel_z_adc = (signed short)((data[4]  << 8) | data[5]);
    dev->temp_adc    = (signed short)((data[6]  << 8) | data[7]);
    dev->gyro_x_adc  = (signed short)((data[8]  << 8) | data[9]);
    dev->gyro_y_adc  = (signed short)((data[10] << 8) | data[11]);
    dev->gyro_z_adc  = (signed short)((data[12] << 8) | data[13]);
}
```

`(signed short)` 这个强转很关键：两字节拼出来的 16 位值要按**有符号**解释，强转成 `signed short` 再赋给 `signed int`，负数才会被正确符号扩展。漏了这步，静止时 Z 轴加速度可能显示成一个巨大的正数。

## probe：把一切都串起来

```c
static int icm20608_probe(struct spi_device *spi)
{
    struct icm20608_dev *dev;
    int ret;

    /* 1、托管分配设备结构体 */
    dev = devm_kzalloc(&spi->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;
    dev->spi = spi;
    spi_set_drvdata(spi, dev);    /* 挂到 spi_device，remove 时取回 */

    /* 2、字符设备号 + cdev */
    ret = alloc_chrdev_region(&dev->devid, 0, 1, ICM20608_NAME);
    if (ret)
        return ret;
    cdev_init(&dev->cdev, &icm20608_ops);
    ret = cdev_add(&dev->cdev, dev->devid, 1);
    if (ret)
        goto del_region;

    /* 3、类（单参数！）+ 设备节点 */
    dev->class = class_create(ICM20608_NAME);
    if (IS_ERR(dev->class)) { ret = PTR_ERR(dev->class); goto del_cdev; }
    dev->device = device_create(dev->class, NULL, dev->devid, NULL, ICM20608_NAME);
    if (IS_ERR(dev->device)) { ret = PTR_ERR(dev->device); goto destroy_class; }

    /* 4、SPI 模式 + 让配置生效 */
    spi->mode = SPI_MODE_0;   /* CPOL=0, CPHA=0 */
    spi_setup(spi);           /* 关键：把 mode/时钟固化进硬件 */

    /* 5、初始化芯片 */
    icm20608_reginit(dev);
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

这段和 I2C 那篇的 `probe` 几乎是双胞胎，区别只在两处 SPI 特有的地方。第一，`spi->mode = SPI_MODE_0` 设完，**必须**紧跟一句 `spi_setup(spi)`——设 `spi->mode` 只改了软件字段，硬件控制器还不知道；`spi_setup` 才会把 mode、时钟频率、字宽算成分频系数写进控制器的寄存器。漏了它，控制器可能还停在复位默认态，通信必败。第二，托管分配绑的是 `&spi->dev`（SPI 设备的 device），`spi_set_drvdata` / `spi_get_drvdata` 是 SPI 子系统对应 `i2c_set_clientdata` 的那对函数。

## remove：void，镜像清理

```c
static void icm20608_remove(struct spi_device *spi)
{
    struct icm20608_dev *dev = spi_get_drvdata(spi);

    device_destroy(dev->class, dev->devid);
    class_destroy(dev->class);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->devid, 1);
    /* dev 由 devm_kzalloc 分配，自动释放，不要手动 kfree */
}
```

同样 `void` 返回、同样按相反顺序回收、同样别去 `kfree(dev)`。

## 字符设备接口

和 I2C 那篇完全一样的 `container_of` 套路：

```c
static int icm20608_open(struct inode *inode, struct file *filp)
{
    struct icm20608_dev *dev = container_of(inode->i_cdev,
                                            struct icm20608_dev, cdev);
    filp->private_data = dev;
    return 0;
}

static ssize_t icm20608_read(struct file *filp, char __user *buf,
                             size_t cnt, loff_t *off)
{
    struct icm20608_dev *dev = filp->private_data;
    signed int data[7];

    icm20608_readdata(dev);
    data[0] = dev->gyro_x_adc;
    data[1] = dev->gyro_y_adc;
    data[2] = dev->gyro_z_adc;
    data[3] = dev->accel_x_adc;
    data[4] = dev->accel_y_adc;
    data[5] = dev->accel_z_adc;
    data[6] = dev->temp_adc;

    if (cnt > sizeof(data))
        cnt = sizeof(data);
    if (copy_to_user(buf, data, cnt))
        return -EFAULT;
    return cnt;
}

static int icm20608_release(struct inode *inode, struct file *filp)
{
    return 0;
}

static const struct file_operations icm20608_ops = {
    .owner   = THIS_MODULE,
    .open    = icm20608_open,
    .read    = icm20608_read,
    .release = icm20608_release,
};
```

`read` 里把七路数据按"陀螺仪 xyz、加速度 xyz、温度"的顺序打包给用户空间，顺序要和测试程序对齐。

## 注册：module_spi_driver 收尾

```c
static const struct of_device_id icm20608_of_match[] = {
    { .compatible = "imxaes,icm20608" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, icm20608_of_match);

static struct spi_driver icm20608_driver = {
    .driver = {
        .name           = ICM20608_NAME,
        .of_match_table = icm20608_of_match,
    },
    .probe  = icm20608_probe,
    .remove = icm20608_remove,
};
module_spi_driver(icm20608_driver);

MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("ICM-20608 6-axis IMU driver (modern SPI API)");
MODULE_LICENSE("GPL");
```

`module_spi_driver(icm20608_driver)` 一行生成 `module_init`/`module_exit`，设好 `owner`。整份驱动到这里就齐活了——和 I2C 那篇并排看，骨架几乎一模一样，差别只在通信那层用 `spi_write_then_read` 替了 `i2c_smbus_*`。

## 小结

这一节我们写完了 ICM-20608 的驱动主体：用 `spi_write_then_read` / `spi_write` 做寄存器读写（顺手用 `spi_transfer` 讲清了底层机制和 `.delay` 新字段），`probe` 里设 `spi->mode` 后不忘 `spi_setup` 固化，`remove` 是 `void`，最后 `module_spi_driver` 注册。代码是现代的、能直接在 6.12 / 7.1 编过。要让它在板子上跑起来，还差设备树——下一节我们就把 ECSPI3 唤醒、挂上 ICM-20608。

---

<ChapterNav variant="sub">
  <ChapterLink href="03_spi_master_analysis.md" variant="sub">← I.MX6U 主机驱动分析</ChapterLink>
  <ChapterLink href="05_device_tree.md" variant="sub">设备树配置 →</ChapterLink>
</ChapterNav>
