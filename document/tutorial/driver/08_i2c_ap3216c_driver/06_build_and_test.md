---
title: 编译与上板测试
---

# 编译与上板测试 —— 让真实数据流起来

代码写完了，设备树也改好了，现在到了见证全程的时刻：把驱动编成 `.ko`、把测试程序编出来、烧到板子上、看 AP3216C 把物理世界翻译成屏幕上跳动的数字。这一节涉及的文件是 `Makefile` 和 `ap3216c_app.c`。

## 驱动 Makefile

驱动是内核模块，得靠内核的构建系统来编。`Makefile` 很短，关键是把 `KERNELDIR` 指向你**配置过、编译过**的内核源码树：

```makefile
# Makefile
KERNELDIR := $(PWD)/../../../third_party/linux-imx    # 6.12.49，按你的实际路径改
CURRENT_PATH := $(shell pwd)
obj-m := ap3216c.o

build: kernel_modules

kernel_modules:
	$(MAKE) -C $(KERNELDIR) M=$(CURRENT_PATH) modules

clean:
	$(MAKE) -C $(KERNELDIR) M=$(CURRENT_PATH) clean
```

`obj-m := ap3216c.o` 告诉构建系统：把 `ap3216c.c` 编成模块 `ap3216c.ko`。`$(MAKE) -C $(KERNELDIR) M=$(CURRENT_PATH) modules` 的意思是"跳到内核源码树里、借用它的构建规则、编译当前目录下的模块"。这里 `KERNELDIR` 要指向那棵你已经 `make imx_aes_defconfig`（或对应 defconfig）并且至少 `make prepare` 过的树——光有源码不行，得配置过，否则编出来的模块会因为 `Module.symvers` 对不上而拒绝加载。

::: tip 选哪棵内核树
我们这次同时支持 `linux-imx` 6.12.49 和 `mainline` 7.1.0。日常开发用 `linux-imx` 那棵（推荐），想验证主线兼容性就把 `KERNELDIR` 指到 `third_party/linux_mainline` 再编一次——同一份 `ap3216c.c` 两边都能过。
:::

编译驱动，在驱动源码目录下执行：

```bash
make
```

成功后会得到 `ap3216c.ko`。如果报 `class_create` 之类的错，回头检查你是不是不小心抄进了老的双参数写法。

## 测试程序 ap3216c_app.c

用户空间的测试程序逻辑很直白：打开 `/dev/ap3216c`，循环 `read`，把读到的 IR / ALS / PS 打出来：

```c
/* ap3216c_app.c */
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char *argv[])
{
    int fd;
    unsigned short databuf[3];   /* ir, als, ps，和驱动里 data[3] 对齐 */
    int ret;

    if (argc != 2) {
        printf("Usage: %s /dev/ap3216c\n", argv[0]);
        return -1;
    }

    fd = open(argv[1], O_RDWR);
    if (fd < 0) {
        printf("can't open %s\n", argv[1]);
        return -1;
    }

    while (1) {
        ret = read(fd, databuf, sizeof(databuf));
        if (ret == sizeof(databuf))
            printf("ir = %d, als = %d, ps = %d\n",
                   databuf[0], databuf[1], databuf[2]);
        usleep(200000);   /* 200ms 读一次 */
    }

    close(fd);
    return 0;
}
```

这里有个对齐细节：`databuf` 是三个 `unsigned short`，对应驱动 `ap3216c_read` 里 `copy_to_user` 出去的 `data[3] = {ir, als, ps}`。顺序、类型两边必须一致，否则数据对不上号。`read` 的返回值是实际读到的字节数，等于 `sizeof(databuf)` 才算读全。

用交叉工具链编译它：

```bash
arm-linux-gnueabihf-gcc ap3216c_app.c -o ap3216c_app
```

## 上板测试

把驱动模块（`20_tutorial_ap3216c_iic_driver.ko`）和 `ap3216c_app` 拷到板子上。加载驱动前，最后一次确认设备树的 `reg` 是 `0x1e`、`compatible` 和驱动里的 `imxaes,ap3216c` 完全一致、SCL/SDA 接线没松动。然后：

```bash
insmod /lib/modules/20_tutorial_ap3216c_iic_driver.ko
```

加载后 `dmesg` 里会看到三行，头一行是提示、后两行才是要盯的关键日志：

```text
[   58.676302] 20_tutorial_ap3216c_iic_driver: loading out-of-tree module taints kernel.
[   58.691463] ap3216c 0-001e: ap3216c hardware initialized
[   58.692023] ap3216c 0-001e: ap3216c probe success
```

那行 `loading out-of-tree module taints kernel` 不用慌——内核只是提醒"这个模块不在源码树里编译"，树外模块都这样，不影响功能。真正要确认的是后面两行：`hardware initialized` 说明芯片寄存器写进去了、`probe success` 说明字符设备和 `/dev/ap3216c` 节点都建好了。日志前缀 `ap3216c 0-001e` 里的 `0-001e` 正是设备树里那个 I2C1（总线 0）+ 地址 `0x1e` 的 `i2c_client`，对得上号。

再核对一眼 sysfs，确认内核真的"看见"这颗芯片：

```bash
ls /sys/bus/i2c/devices/
# 0-001e  1-001a  1-005d  i2c-0   i2c-1

cat /sys/bus/i2c/devices/0-001e/name
# ap3216c
```

`0-001e` 在、`name` 是 `ap3216c`，设备树和总线层面就都通了。接着跑测试程序：

```bash
/home/ap3216c_app /dev/ap3216c
```

屏幕上开始刷真实数据：

```text
ir = 2, als = 82, ps = 447
ir = 3, als = 81, ps = 439
ir = 4, als = 81, ps = 430
ir = 2, als = 81, ps = 439
ir = 0, als = 83, ps = 439
...
```

## 拿物理世界验证

光看数字还在跳不算完，得用真实物理量验证驱动真的通了。AP3216C 三路数据各自对应一种物理现象，正好可以分别测：拿手电筒照一下芯片，`als`（环境光）应该明显蹿高，移开就回落；把手指慢慢靠近芯片，`ps`（接近距离）会随着距离缩短而增大，贴上去时接近满量程；`ir`（红外）在普通环境下数值较低，用电视遥控器对着它按几下，能看到红外脉冲带来的跳变。

实测就能看到这套规律。下面是从板子上抓的一段连续输出，正好记录了一次"手指靠近 → 贴近 → 移开"的完整过程：

```text
ir = 2, als = 82, ps = 447      # 正常室内环境
ir = 0, als = 83, ps = 439
ir = 8, als = 33, ps = 444      # 手指靠近，环境光开始被遮挡
ir = 0, als = 0,  ps = 436      # als 已跌到 0
ir = 6, als = 1,  ps = 456
ir = 2, als = 0,  ps = 498      # ps 继续上升
ir = 6, als = 0,  ps = 502      # 手指贴近，ps 到达峰值
ir = 0, als = 60, ps = 441      # 手指移开，als 回升、ps 回落
ir = 1, als = 79, ps = 429      # 恢复正常室内
ir = 1, als = 78, ps = 439
```

重点看 `als` 和 `ps` 这一升一降的耦合：手指越近 = 遮光越狠 = `als` 越低，同时反射回去的红外越强 = `ps` 越高；手指移开后，`als` 立刻回升到 ~78、`ps` 回落到 ~440，整个过程干净利落。这种此消彼长的同步变化，正是物理量被正确翻译成数字的活证据，比任何单路读数都更能说明驱动真的通了。注意全程 `ir` 都维持个位数（0~8），符合红外在无红外源环境下的低值预期——这反而是正常的，别因为 `ir` 纹丝不动就以为哪路坏了，它要等到遥控器、热源这类红外信号出现才会跳。

如果三路数据全是 `0` 或者死活不变，按这个顺序排查：先确认 `/sys/bus/i2c/devices/0-001e` 存在（设备树层面 OK）；再 `dmesg | grep ap3216c` 看 `probe` 有没有成功跑完；最后用示波器抓一下 SCL/SDA 有没有波形、地址周期有没有 ACK。只要 ACK 正常、寄存器能读出合理的值，数据就一定会动起来。

## 小结

这一节我们把驱动编成模块、写好测试程序、上板拿到了真实的 IR / ALS / PS 数据，并用物理实验验证了链路。回过头看，整条 I2C 驱动链路是这样跑通的：设备树描述硬件 → I2C 核心层生成 `i2c_client` → `compatible` 匹配上我们的 `i2c_driver` → `probe` 注册字符设备并初始化芯片 → 用户空间 `read` 触发 `i2c_smbus_*` → 最终落到适配器的 `master_xfer` 把比特发到线上。任何一个环节断了，数据都流不过来。下一篇我们要把这套思维搬到 SPI 上——你会发现，虽然时序完全不同，但内核那套"分层 + 匹配"的哲学惊人地一致。

---

<ChapterNav variant="sub">
  <ChapterLink href="05_device_tree.md" variant="sub">← 设备树配置</ChapterLink>
  <ChapterLink href="../09_spi_icm20608_driver/" variant="sub">SPI ICM-20608 驱动 →</ChapterLink>
</ChapterNav>
