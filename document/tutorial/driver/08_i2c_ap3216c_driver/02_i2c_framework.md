---
title: I2C 驱动框架
---

# I2C 驱动框架 —— 谁开卡车，谁打包货物

在动手写任何一行代码之前，我们得先把一个根子上的问题想明白。回想你在裸机篇是怎么对付 AP3216C 的：写一个 `bsp_i2c.c` 折腾 I.MX6U 的 I2C 控制器——配时钟、设 GPIO、算波特率；再写一个 `bsp_ap3216c.c`，把芯片手册里那串寄存器读写序列硬编码进去。这两坨代码紧紧焊在一起，某天换了颗传感器，`bsp_i2c.c` 得原样抄一遍；某天换了块板子、I2C 控制器变了，`bsp_ap3216c.c` 里那一堆时序又得推倒重来。任何一个写过两块板子的人，最后都会被逼到同一个岔路口：必须把"控制器的操作"和"设备的业务逻辑"拆开。

Linux 内核的设计者二十年前就走完了这条路，而且走得很彻底。他们立了一套硬规矩叫 I2C 驱动框架：控制器驱动只管"比特怎么发出去"，设备驱动只管"我要发什么"，中间靠 I2C 核心层那一套 API 把两头粘起来。我们要学习的就是这个东西。

## 总线驱动：适配器和它的算法

总线驱动操作的对象是 SoC 上的 I2C 适配器，内核把它抽象成了 `i2c_adapter`，定义在 `include/linux/i2c.h`。字段一大堆，我们只挑跟传输相关的核心成员看，免得被管理字段晃花眼：

```c
/*
 * i2c_adapter 结构体（节选自 include/linux/i2c.h）
 */
struct i2c_adapter {
    struct module *owner;
    unsigned int class;
    const struct i2c_algorithm *algo;   /* 总线访问算法，灵魂在这里 */
    void *algo_data;

    struct rt_mutex bus_lock;
    int timeout;            /* 单位是 jiffies */
    int retries;
    struct device dev;      /* 适配器对应的 device */
    int nr;                 /* 总线号 */
    char name[48];

    struct i2c_bus_recovery_info *bus_recovery_info;
    const struct i2c_adapter_quirks *quirks;
    /* ...... 管理字段省略 ...... */
};
```

这一大坨里，真正决定"这个适配器怎么动起来"的只有 `algo` 一个指针。它指向 `i2c_algorithm`，相当于适配器的使用说明书——告诉内核这玩意儿到底是硬件控制器，还是拿 GPIO 软件模拟出来的。它的 6.12.49 真实形态长这样：

```c
/*
 * i2c_algorithm 结构体（include/linux/i2c.h）
 */
struct i2c_algorithm {
    /*
     * xfer 和 master_xfer 是 union，二选一：新代码用 xfer，
     * master_xfer 是为兼容老代码留的老名字。你调的所有读写 API，
     * 最终都落到这个函数指针上。
     */
    union {
        int (*xfer)(struct i2c_adapter *adap,
                    struct i2c_msg *msgs, int num);
        int (*master_xfer)(struct i2c_adapter *adap,
                           struct i2c_msg *msgs, int num);
    };
    /* 原子上下文里用的版本（崩溃恢复、调试器），大多数驱动用不到 */
    union {
        int (*xfer_atomic)(struct i2c_adapter *adap,
                           struct i2c_msg *msgs, int num);
        int (*master_xfer_atomic)(struct i2c_adapter *adap,
                                  struct i2c_msg *msgs, int num);
    };

    int (*smbus_xfer)(struct i2c_adapter *adap, u16 addr,
                      unsigned short flags, char read_write,
                      u8 command, int size, union i2c_smbus_data *data);

    /* 告诉内核这个适配器支持哪些能力 */
    u32 (*functionality)(struct i2c_adapter *adap);
    /* ...... I2C 从机模式相关成员省略 ...... */
};
```

这里有个细节值得停下来想一想：`xfer` 和 `master_xfer` 被塞进了同一个 `union`。这不是内核作者闲得慌，而是一次正在进行的命名迁移——`master_xfer` 是老名字，`xfer` 是新名字，两者完全等价，你写哪个内核都认。看到这种 `union` 双名，你心里就该有数：这是个新旧交替的过渡期字段。下一节我们拆 `i2c-imx.c` 的时候，会看到 I.MX6U 的适配器实际填的是哪一个。

所以假如你是 SoC 厂商的工程师，写一个 I2C 总线驱动的套路是定死的：定义一个 `i2c_adapter`，实现 `xfer`（或 `smbus_xfer`），再用 `i2c_add_adapter` 或 `i2c_add_numbered_adapter` 把它注册进内核。这俩注册函数的区别只有一个——前者让内核动态分配总线号，后者由你指定一个静态总线号。

```c
int i2c_add_adapter(struct i2c_adapter *adapter);       /* 动态分配总线号 */
int i2c_add_numbered_adapter(struct i2c_adapter *adap);  /* 你指定总线号   */
```

这里有个好消息也有个坏消息。好消息是像 I.MX6U 这种主流 SoC，NXP 早就把这层写好了，驱动就在 `drivers/i2c/busses/i2c-imx.c`，开箱即用。坏消息是你大概率这辈子都没机会亲手写一个总线驱动——除非跳槽去了原厂。所以对这一层，我们的定位是"使用者"而不是"创造者"，知道它存在、知道它向上暴露了哪些 API 就够了。真正要我们操刀的，是下面这层。

## 设备驱动：i2c_client 描述"你是谁"，i2c_driver 描述"怎么干"

聊完了开卡车的，现在轮到打包货物的——这才是开发者真正要操心的部分。这一层的主角是一对结构体：`i2c_client` 和 `i2c_driver`。顺着 Linux"总线-设备-驱动"那套老传统，总线有了，剩下的自然就是设备和驱动。

`i2c_client` 描述"挂在 I2C 总线上的一个具体设备"，每多一个 I2C 设备，内核里就多一个对应实例：

```c
/*
 * i2c_client 结构体（include/linux/i2c.h）
 */
struct i2c_client {
    unsigned short flags;         /* 标志位 */
    unsigned short addr;          /* 7 位 I2C 地址，存在低 7 位 */
    char name[I2C_NAME_SIZE];     /* 设备名 */
    struct i2c_adapter *adapter;  /* 挂在哪个控制器上 */
    struct device dev;            /* 内嵌的 device */
    int irq;                      /* 中断号 */
    struct list_head detected;
    /* ...... */
};
```

`addr` 就是你那颗芯片的 7 位地址（AP3216C 是 `0x1e`），`adapter` 指向它挂在哪个控制器上，`name` 用于匹配驱动。这里有个关键认知要先建立起来：**这个结构体通常不是你手动填充的**。它是 I2C 核心层在你写好设备树之后，根据设备树节点自动生成的——你只管在设备树里写 `reg = <0x1e>`，内核替你把 `addr` 填好、把 `adapter` 指过去。我们要亲手写的，是另一个结构体。

`i2c_driver` 才是这一章的主角，和 `platform_driver` 长得像一个模子刻出来的，用来注册驱动逻辑。看它在 6.12.49 里的真实定义：

```c
/*
 * i2c_driver 结构体（include/linux/i2c.h）
 */
struct i2c_driver {
    unsigned int class;

    /* 设备和驱动匹配成功后回调 —— 绝大多数初始化都在这里 */
    int  (*probe)(struct i2c_client *client);
    /* 设备拔掉或驱动卸载时回调 —— 注意返回值是 void！ */
    void (*remove)(struct i2c_client *client);

    void (*shutdown)(struct i2c_client *client);
    void (*alert)(struct i2c_client *client, enum i2c_alert_protocol protocol,
                  unsigned int data);

    struct device_driver driver;
    const struct i2c_device_id *id_table;   /* 传统匹配表，现代驱动可省略 */

    /* 下面两个是老式自动探测用的，现代驱动不要碰 */
    int  (*detect)(struct i2c_client *client, struct i2c_board_info *info);
    const unsigned short *address_list;
    struct list_head clients;

    u32 flags;
};
```

把这份定义和老教程里的对照一下，"现代"两个字落在哪儿就一目了然了。`probe` 的签名是干干净净的 `int (*probe)(struct i2c_client *client)`，**只有一个参数**——老教程里那个 `const struct i2c_device_id *id` 早被内核咔嚓掉了，因为现代驱动从设备树取数据根本用不着它。`remove` 的返回类型从 `int` 变成了 `void`，I2C 子系统比很多别的子系统都更早完成了这次迁移。你要是还照老教程写 `static int xxx_remove(...) { ...; return 0; }`，在新内核里赋给 `i2c_driver.remove` 这一步就会触发 `incompatible pointer type` 警告。

注册函数这边，老教程会让你手写一整套 `module_init` / `module_exit`，里面调 `i2c_add_driver`。写法没错，但内核早就备好了更省事的宏，一行顶你原来十行：

```c
/* include/linux/i2c.h */
#define i2c_add_driver(driver) \
        i2c_register_driver(THIS_MODULE, driver)

#define module_i2c_driver(__i2c_driver) \
        module_driver(__i2c_driver, i2c_add_driver, i2c_del_driver)
```

`i2c_add_driver` 本质就是帮你把 `THIS_MODULE` 塞进 `i2c_register_driver` 的宏；`module_i2c_driver` 更狠，直接帮你生成 `module_init` 和 `module_exit`，前者调注册、后者调注销。`i2c_register_driver` 内部还会替你设好 `driver->owner`，所以你连 `.driver.owner = THIS_MODULE` 都不用写了。

把这些凑齐，一个现代的、完整的 I2C 设备驱动注册骨架就是下面这样，往后你写的 I2C 驱动九成都是它的变体：

```c
/*
 * 现代 i2c_driver 注册骨架
 */

/* 1、probe：设备匹配上以后，初始化硬件、注册字符设备都在这儿 */
static int ap3216c_probe(struct i2c_client *client)
{
    /* 函数具体程序 */
    return 0;
}

/* 2、remove：注意是 void，别再 return 0 了 */
static void ap3216c_remove(struct i2c_client *client)
{
    /* 注销字符设备、释放资源 */
}

/* 3、设备树匹配表 —— 现代 I2C 驱动靠它就能匹配，id_table 可以不要 */
static const struct of_device_id ap3216c_of_match[] = {
    { .compatible = "imxaes,ap3216c" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, ap3216c_of_match);

/* 4、驱动结构体 */
static struct i2c_driver ap3216c_driver = {
    .driver = {
        .name           = "ap3216c",
        .of_match_table = ap3216c_of_match,
    },
    .probe  = ap3216c_probe,
    .remove = ap3216c_remove,
};

/* 5、注册交给宏，再也不用手写 module_init/module_exit */
module_i2c_driver(ap3216c_driver);

MODULE_AUTHOR("Charliechen114514");
MODULE_LICENSE("GPL");
```

::: warning ⚠️ 踩坑预警
如果你是照老教材抄过来的代码，加载之前务必把这三处老写法改掉：`probe` 多出来的那个 `id` 参数得删；`remove` 的 `int` 返回值改成 `void`、函数体里的 `return 0` 删掉；`.driver.owner = THIS_MODULE` 这行可以直接去掉。这三样不改，要么编译报警告，要么行为压根不对。另外纯设备树匹配的驱动，那张老的 `i2c_device_id` 表是可以整个省掉的——这点我们马上从内核源码里给你找到依据。
:::

## 它们是怎么"对上眼"的：匹配机制

到这儿，适配器（总线）、设备（`i2c_client`）、驱动（`i2c_driver`）三方到齐，剩下的问题只有一个：内核凭什么把某颗芯片和某个驱动撮合到一起？这个"月老"由 **I2C 核心层**扮演，源码在 `drivers/i2c/i2c-core-base.c`。它不光提供了前面那些注册函数，还维护着一条虚拟的 I2C 总线 `i2c_bus_type`：

```c
/*
 * i2c_bus_type（drivers/i2c/i2c-core-base.c）
 * 现代内核里它已经是 const struct bus_type
 */
const struct bus_type i2c_bus_type = {
    .name     = "i2c",
    .match    = i2c_device_match,    /* 匹配判断在这里 */
    .probe    = i2c_device_probe,
    .remove   = i2c_device_remove,
    .shutdown = i2c_device_shutdown,
};
```

真正的撮合逻辑在 `.match` 指向的 `i2c_device_match` 里，我们从 `i2c-core-base.c` 把它抠出来看：

```c
/*
 * i2c_device_match（drivers/i2c/i2c-core-base.c）
 */
static int i2c_device_match(struct device *dev, const struct device_driver *drv)
{
    struct i2c_client *client = i2c_verify_client(dev);
    const struct i2c_driver *driver;

    /* 第一优先级：设备树（OF）匹配，比较 compatible 字符串 */
    if (i2c_of_match_device(drv->of_match_table, client))
        return 1;

    /* 第二优先级：ACPI 匹配，x86/PC 那套，嵌入式板子基本跳过 */
    if (acpi_driver_match_device(dev, drv))
        return 1;

    /* 最后兜底：老式 id_table 名字匹配 */
    driver = to_i2c_driver(drv);
    if (i2c_match_id(driver->id_table, client))
        return 1;

    return 0;
}
```

这段逻辑读起来有种"层层退让"的味道。内核一上来先试设备树匹配——拿设备树节点里的 `compatible`，去和驱动 `of_match_table` 里登记的每一项比，对上了就牵手成功，后面两步根本不看。这也是为什么我们前面敢说"现代驱动只靠 `of_match_table` 就够了"：只要这一步能命中，`id_table` 永远轮不到被查询。只有设备树这条路走不通时，内核才会退而求其次试 ACPI（嵌入式板子上基本不存在），再不行才退到最老土的办法——拿 `i2c_client` 的 `name` 去和驱动 `id_table` 里的名字比。最后这一步是给那些既没设备树、也没 ACPI 的远古板子留的逃生通道，我们这年头写驱动基本用不上。

框架的全貌到此就清楚了。我们虽然把驱动分成了"总线驱动"和"设备驱动"两层，但它俩绝不是老死不相往来——下一节我们就钻进 `i2c-imx.c`，看看 I.MX6U 的总线驱动到底长什么样、又是怎么被注册进系统的。等看明白它怎么把"搬运比特"的能力封装好向上暴露，再回过头写自己的设备驱动，心里就有底了。

---

<ChapterNav variant="sub">
  <ChapterLink href="./" variant="sub">← 教程首页</ChapterLink>
  <ChapterLink href="03_i2c_adapter_analysis.md" variant="sub">I.MX6U 适配器分析 →</ChapterLink>
</ChapterNav>
