---
title: OF API 基础
---

# 05. OF API 基础——从 DTS 到代码的桥梁

## 前言：当设备树遇见驱动代码

前几章我们聊了设备树的语法、编译原理和历史演进，知道了 `.dts` 文件是如何被编译成 `.dtb` 然后被内核解析的。但说实话，这些只是"准备工作"。对于驱动开发者来说，真正的问题在于：**我的驱动代码怎么去用这些设备树信息？**

设备树里写着 `reg = <0x020C406C 0x04>`，但这只是个文本描述。驱动程序在运行时需要知道这个地址，需要把它映射成虚拟地址，然后才能去读写寄存器。中间缺了一个环节——需要有人在运行时去解析设备树，把那些 `< >` 里的数字提取出来，塞给 C 代码。

Linux 内核提供了这个环节，那就是一系列以 `of_` 为前缀的 API 函数。你可以把它们理解为设备树和驱动代码之间的"翻译官"。

但这里有个历史遗留问题可能会困扰你：为什么叫 "OF" 而不是 "DT"？Device Tree 的缩写不是 DT 吗？这个问题的答案藏在设备树的历史里，我们稍后再说。现在先记住一点：当你看到 `of_xxx()` 这样的函数时，它们就是在操作设备树。

这一章我们会系统地介绍这些 API，看看它们是如何在实际驱动中使用的。我们还会拿 LED 驱动的代码做例子，看看那些在设备树里写的属性，是怎么一步步变成驱动里的寄存器地址的。

---

## OF 的概念：为什么叫 OF 而不是 DT

在正式讲 API 之前，我们先把这个"名字问题"说清楚。这不仅仅是咬文嚼字，理解了这个命名，你就能明白为什么设备树的很多设计是这样的。

OF 是 **Open Firmware** 的缩写。我们在第四章历史演进里提到过，设备树最早是 IBM 和苹果在 PowerPC 时代搞出来的 Open Firmware 标准的一部分。那时候的 idea 是：固件应该向操作系统提供一份完整的硬件描述，这样操作系统就不需要为每块板子写专门的初始化代码了。

后来 Linux 把这个机制移植过来，用于 PowerPC 和 SPARC 架构。那时候内核里操作设备树的函数就都叫 `of_xxx()`，因为它们是从 Open Firmware 标准来的。

再后来，ARM 社区也意识到了板级代码的问题，开始引入设备树机制。但为了复用已有的基础设施，ARM 也沿用了 `of_` 这个命名前缀。所以今天我们在 ARM Linux 里看到的设备树 API，依然叫 OF API，而不是 DT API。

你可以把它理解为一种"历史遗产"。就像 C 语言的 `stdio.h` 里为什么有 `printf` 而不是 `print`——这是历史原因造成的。但这个命名其实挺合理的，因为 Open Firmware 本质上就是一种"开放固件"的规范，而设备树正是这种规范的核心部分。

那么 OF 和设备树是什么关系呢？可以这样理解：设备树是数据结构，OF API 是操作这个数据结构的一套函数。就像 C 语言里有 struct 和操作 struct 的函数一样，设备树是"数据"，OF API 是"操作数据的工具"。

在 Linux 内核的源码里，你会看到这样的头文件：

- `include/linux/of.h`：核心 OF API 定义
- `include/linux/of_address.h`：地址映射相关函数
- `include/linux/of_gpio.h`：GPIO 相关函数
- `include/linux/of_irq.h`：中断相关函数

这些文件里定义的所有函数，都是我们这一章要讲的内容。

---

## 核心数据结构：device_node、property 和 resource

在讲具体的 API 之前，我们需要先了解一下内核是用什么数据结构来表示设备树的。毕竟 API 只是操作这些数据结构的工具，如果不了解数据结构本身，用起 API 来也是一头雾水。

### struct device_node：节点的内核表示

`struct device_node` 是内核对设备树节点的描述。每个设备树节点在内核里都对应一个 `device_node` 结构体。这个结构体的定义在 `include/linux/of.h` 里，我们挑重点字段看：

```c
struct device_node {
    const char *name;        /* 节点名字，比如 "gpio" */
    const char *type;        /* 设备类型，取自 device_type 属性 */
    phandle phandle;         /* 节点的 phandle 值 */
    const char *full_name;   /* 节点的全路径名 */
    struct fwnode_handle fwnode;

    struct property *properties;  /* 属性链表头 */
    struct property *deadprops;   /* 已删除的属性 */

    struct device_node *parent;   /* 父节点 */
    struct device_node *child;    /* 子节点 */
    struct device_node *sibling;  /* 兄弟节点 */

    struct kobject kobj;
    unsigned long _flags;
    void *data;
    /* ... 更多平台特定字段 ... */
};
```

这个结构体设计得很巧妙。它不仅记录了节点的名字和类型，还通过 `parent`、`child` 和 `sibling` 三个指针把整棵树串了起来。这意味着你可以从任意一个节点出发，往上找父节点，往下找子节点，往旁边找兄弟节点——就像在真的树上爬一样。

`properties` 字段指向一个属性链表，所有的 `property` 结构体都挂在这个链表上。我们接下来看 `property` 结构体。

### struct property：属性的内核表示

```c
struct property {
    char *name;            /* 属性名字，比如 "reg" */
    int length;            /* 属性值的字节长度 */
    void *value;           /* 属性值，可以是任意数据 */
    struct property *next; /* 指向下一个属性 */
    unsigned long _flags;
    unsigned int unique_id;
    struct bin_attribute attr;
};
```

这里最关键的是 `value` 字段。它是个 `void *`，可以指向任意类型的数据。这是因为设备树里的属性值可以是各种类型：可能是单个整数，可能是字符串，可能是整数数组，甚至可能是任意字节序列。

内核怎么知道 `value` 里存的是什么类型呢？答案是：**不知道**。内核只知道这是一坨字节，具体怎么解释，要看属性的名字和上下文。比如 `status` 属性通常被解释为字符串，`reg` 属性被解释为整数数组，而 `compatible` 属性被解释为字符串数组。

所以当我们用 API 读取属性时，需要明确告诉内核我们想要什么类型的数据。这就是为什么有 `of_property_read_u32()`、`of_property_read_string()` 这样不同的函数。

### struct resource：资源的统一描述

Linux 内核用 `struct resource` 来统一描述各种资源——不仅仅是内存映射 IO，还包括中断、DMA 通道等。这个结构体定义在 `include/linux/ioport.h`：

```c
struct resource {
    resource_size_t start;  /* 资源起始地址/号 */
    resource_size_t end;    /* 资源结束地址/号 */
    const char *name;       /* 资源名称 */
    unsigned long flags;    /* 资源类型标志 */
    struct resource *parent, *sibling, *child;
};
```

`flags` 字段说明这是什么类型的资源：

- `IORESOURCE_MEM`：内存映射 IO
- `IORESOURCE_IRQ`：中断资源
- `IORESOURCE_IO`：端口 IO（x86 特有）
- `IORESOURCE_DMA`：DMA 通道

设备树里的 `reg` 属性可以通过 `of_address_to_resource()` 函数转换成 `resource` 结构体，这样驱动就可以用统一的方式来处理不同类型的资源了。

---

## 节点查找 API：如何在设备树中定位目标节点

有了数据结构基础，现在我们可以开始讲具体的 API 了。第一步是找到你要操作的节点。就像你想操作一个文件，得先找到它的路径一样，你想操作设备树里的某个节点，也得先定位到它。

内核提供了好几种查找节点的方法，适用于不同的场景。我们一个一个来看。

### of_find_node_by_path：按路径查找

这是最直接的方法。如果你知道节点的完整路径，用这个函数最快：

```c
struct device_node *of_find_node_by_path(const char *path);
```

参数 `path` 是节点的完整路径，比如 `"/imx_aes_led"`。返回值是找到的节点指针，如果没找到就返回 `NULL`。

这个函数在我们的 LED 驱动里用到了：

```c
/* 从 /home/charliechen/imx-forge/driver/device_tree_try_03/alpha-board/led_hw.c */
static const char* kIMX_AES_LED = "/imx_aes_led";

led.device_tree_node = of_find_node_by_path(kIMX_AES_LED);
if (led.device_tree_node == NULL) {
    pr_err("dtsled node can not found!\n");
    return -EINVAL;
}
```

这里我们直接用路径 `/imx_aes_led` 去找节点。这个路径对应设备树里的定义：

```dts
/* 从 /home/charliechen/imx-forge/driver/device_tree/alpha-board/device_tree_try_03/imx6ull-aes-led.dts */
/ {
    imx_aes_led {
        #address-cells = <1>;
        #size-cells = <1>;
        compatible = "atkalpha-led";
        status = "okay";
        reg = <...>;
    };
};
```

`of_find_node_by_path()` 的好处是简单直接，缺点是你要知道确切的路径。如果你只是想找某个类型的设备（比如所有的 GPIO 控制器），这个方法就不太方便了。

### of_find_node_by_name：按节点名查找

```c
struct device_node *of_find_node_by_name(struct device_node *from,
                                         const char *name);
```

这个函数按节点名查找。注意节点名不是 `compatible` 属性，而是节点本身的名字。比如节点 `gpio1 { ... }` 的名字就是 `"gpio1"`。

`from` 参数指定从哪里开始找。如果传 `NULL`，就从根节点开始遍历整棵树。如果传一个具体的节点，就从那个节点之后继续找（这个设计允许你多次调用来遍历所有同名节点）。

这个函数在实际驱动里用得不多，因为节点名往往不够具体。同一个设备树上可能有很多叫 `"gpio"` 的节点，你很难确定找到的是哪一个。

### of_find_compatible_node：按兼容性查找

这是驱动里最常用的查找函数：

```c
struct device_node *of_find_compatible_node(struct device_node *from,
                                            const char *type,
                                            const char *compatible);
```

参数说明：
- `from`：起始节点，`NULL` 表示从根开始
- `type`：`device_type` 属性值，可以传 `NULL` 表示不检查
- `compatible`：要匹配的 `compatible` 属性字符串

这个函数会遍历设备树，找到第一个 `compatible` 属性包含指定字符串的节点。比如你可以用 `"fsl,imx6ul-gpio"` 来找 NXP 的 GPIO 控制器。

这里需要注意一点：`compatible` 属性可以包含多个字符串，用逗号分隔。`of_find_compatible_node()` 会检查所有这些字符串，只要有一个匹配就认为找到了。

### of_find_matching_node_and_match：按匹配表查找

这是最强大的查找函数，它直接拿驱动里的 `of_device_id` 匹配表去过滤节点：

```c
struct device_node *of_find_matching_node_and_match(
                            struct device_node *from,
                            const struct of_device_id *matches,
                            const struct of_device_id **match);
```

`matches` 参数就是驱动里的 `.of_match_table`，比如：

```c
static const struct of_device_id led_of_match[] = {
    { .compatible = "atkalpha-led", },
    { /* sentinel */ }
};
```

这个函数会遍历匹配表，找到第一个匹配的节点。`match` 是输出参数，告诉你具体匹配上了表里的哪一项。

在实际的 platform 驱动框架里，这个函数通常不需要你手动调用。驱动核心会自动帮你匹配。但如果你在写一些特殊逻辑（比如在驱动初始化时主动查找某个设备），这个函数就很有用了。

---

## 属性读取 API：如何从节点中提取信息

找到了节点，下一步就是读取它的属性。这是 OF API 的核心部分，也是驱动开发者用得最多的部分。

### of_find_property：查找属性结构体

这是最底层的属性查找函数：

```c
struct property *of_find_property(const struct device_node *np,
                                 const char *name,
                                 int *lenp);
```

参数说明：
- `np`：设备节点
- `name`：属性名
- `lenp`：输出参数，返回属性值的字节长度

返回值是找到的 `property` 结构体指针，如果没找到就返回 `NULL`。

这个函数返回的是原始的 `property` 结构体，你可以直接访问它的 `value` 字段。但 `value` 是 `void *` 类型，你需要自己解释它的内容。

我们的 LED 驱动里用这个函数读取了 `compatible` 属性：

```c
struct property* proper;

proper = of_find_property(led.device_tree_node, "compatible", NULL);
if (proper == NULL) {
    pr_err("compatible property find failed\n");
} else {
    pr_info("compatible = %s\n", (char*)proper->value);
}
```

这里我们知道 `compatible` 属性的值是个字符串，所以直接把 `value` 强转成 `char *` 来打印。但这种方法并不安全，因为 `compatible` 实际上是个字符串数组，可能包含多个以 null 结尾的字符串。更好的做法是用专门的字符串读取函数，我们稍后讲。

### of_property_read_string：读取字符串属性

```c
int of_property_read_string(struct device_node *np,
                            const char *propname,
                            const char **out_string);
```

这个函数用于读取字符串类型的属性，比如 `status`、`device_type` 等。

参数说明：
- `np`：设备节点
- `propname`：属性名
- `out_string`：输出参数，返回字符串指针

返回值是 0 表示成功，负值表示失败（`-EINVAL` 属性不存在，`-ENODATA` 属性值为空）。

我们的 LED 驱动用它来读取 `status` 属性：

```c
const char* str;
int ret;

ret = of_property_read_string(led.device_tree_node, "status", &str);
if (ret < 0) {
    pr_err("status read failed!\n");
} else {
    pr_info("status = %s\n", str);
}
```

这里需要注意一个细节：如果属性里包含多个字符串（字符串数组），这个函数只会返回第一个。如果你想读取第 N 个字符串，可以用 `of_property_read_string_index()`。

### of_property_read_u32：读取 32 位整数

```c
int of_property_read_u32(const struct device_node *np,
                        const char *propname,
                        u32 *out_value);
```

这个函数用于读取单个 32 位整数属性。设备树里的 `<0x12345678>` 会被解析成一个 `u32` 值。

参数说明：
- `np`：设备节点
- `propname`：属性名
- `out_value`：输出参数，返回读取的值

返回值是 0 表示成功，负值表示失败。

类似的还有读取 8 位、16 位、64 位整数的版本：
- `of_property_read_u8()`
- `of_property_read_u16()`
- `of_property_read_u64()`

### of_property_read_u32_array：读取整数数组

这个函数用于读取包含多个整数的属性，比如 `reg` 属性：

```c
int of_property_read_u32_array(const struct device_node *np,
                              const char *propname,
                              u32 *out_values,
                              size_t sz);
```

参数说明：
- `np`：设备节点
- `propname`：属性名
- `out_values`：接收数据的数组指针
- `sz`：要读取的元素个数

返回值是 0 表示成功，负值表示失败。

我们的 LED 驱动用它来读取 `reg` 属性：

```c
u32 regdata[10];
int ret;

ret = of_property_read_u32_array(led.device_tree_node, "reg", regdata, 10);
if (ret < 0) {
    pr_err("reg property read failed!\n");
    of_node_put(led.device_tree_node);
    return -EINVAL;
}

pr_info("reg data:\n");
for (int i = 0; i < 10; i++) {
    pr_cont("%#X ", regdata[i]);
}
pr_cont("\n");
```

这里我们预先知道 `reg` 属性有 10 个整数（5 组地址-长度对），所以直接读 10 个。在实际驱动里，你可能需要先用 `of_property_count_elems_of_size()` 来获取元素个数，动态分配内存。

### of_property_count_elems_of_size：计算数组元素个数

```c
int of_property_count_elems_of_size(const struct device_node *np,
                                    const char *propname,
                                    int elem_size);
```

这个函数返回指定属性里有多少个指定大小的元素。比如你想知道 `reg` 属性里有多少个 `u32`，可以这样做：

```c
int count = of_property_count_elems_of_size(np, "reg", sizeof(u32));
```

返回值是元素个数，负值表示出错。

---

## 内存映射 API：如何将设备树地址转换为可访问的虚拟地址

我们前面讲了如何从设备树里读取地址值，但那些只是物理地址（或者总线地址）。驱动程序要访问这些地址，还需要把它们映射到内核虚拟地址空间。这一步通常用 `ioremap()` 来完成。

但 OF API 提供了更便捷的方法，把"读 reg 属性"和"ioremap"两步合成一步。

### of_iomap：一步到位的地址映射

这是驱动里最常用的函数之一：

```c
void __iomem *of_iomap(struct device_node *np,
                       int index);
```

参数说明：
- `np`：设备节点
- `index`：`reg` 属性的索引（从 0 开始）

返回值是映射后的内核虚拟地址，失败返回 `NULL`。

这个函数会自动完成以下步骤：
1. 从 `reg` 属性里读取第 `index` 组地址
2. 处理地址转换（如果需要的话）
3. 调用 `ioremap()` 建立映射

我们的 LED 驱动用它来映射所有寄存器地址：

```c
/* 5. 使用 of_iomap 进行寄存器地址映射 */
led.ccm_ccgr1 = of_iomap(led.device_tree_node, 0);
led.sw_mux_gpio = of_iomap(led.device_tree_node, 1);
led.sw_pad_gpio = of_iomap(led.device_tree_node, 2);
led.gpio_dr = of_iomap(led.device_tree_node, 3);
led.gpio_gdir = of_iomap(led.device_tree_node, 4);

if (!led.ccm_ccgr1 || !led.sw_mux_gpio || !led.sw_pad_gpio ||
    !led.gpio_dr || !led.gpio_gdir) {
    pr_err("ioremap failed!\n");
    of_node_put(led.device_tree_node);
    return -ENOMEM;
}
```

这里我们连续调用了 5 次 `of_iomap()`，每次传入不同的索引。这些索引对应 `reg` 属性里的 5 组地址：

```dts
reg = < 0X020C406C 0X04  /* 索引 0: CCM_CCGR1_BASE */
        0X020E0068 0X04  /* 索引 1: SW_MUX_GPIO1_IO03_BASE */
        0X020E02F4 0X04  /* 索引 2: SW_PAD_GPIO1_IO03_BASE */
        0X0209C000 0X04  /* 索引 3: GPIO1_DR_BASE */
        0X0209C004 0X04 >; /* 索引 4: GPIO1_GDIR_BASE */
```

注意这里有个重要的错误处理：我们检查了所有映射是否成功，只要有一个失败就报错退出。这点很重要，因为部分成功会导致后续代码访问空指针，引发内核 panic。

### of_get_address：获取地址原始数据

有时候你不想直接映射，而是想先拿到地址的原始数据，这时候可以用 `of_get_address()`：

```c
const __be32 *of_get_address(struct device_node *dev,
                             int index,
                             u64 *size,
                             unsigned int *flags);
```

参数说明：
- `dev`：设备节点
- `index`：`reg` 属性的索引
- `size`：输出参数，返回地址长度
- `flags`：输出参数，返回标志（比如 `IORESOURCE_MEM`）

返回值是读取到的地址数据指针（大端格式的 `u32` 数组），失败返回 `NULL`。

这个函数返回的是设备树里的原始数据，可能还需要地址转换才能变成 CPU 物理地址。

### of_translate_address：地址转换

设备树里的地址有时是总线地址，需要转换成 CPU 物理地址：

```c
u64 of_translate_address(struct device_node *dev,
                         const __be32 *in_addr);
```

参数说明：
- `dev`：设备节点
- `in_addr`：从 `of_get_address()` 拿到的地址

返回值是转换后的物理地址，如果是 `OF_BAD_ADDR` 表示转换失败。

### of_address_to_resource：转换成标准资源结构

Linux 内核用 `struct resource` 统一描述各种资源。这个函数把设备树里的 `reg` 直接转成 `resource`：

```c
int of_address_to_resource(struct device_node *dev,
                           int index,
                           struct resource *r);
```

参数说明：
- `dev`：设备节点
- `index`：`reg` 属性的索引
- `r`：输出的 `resource` 结构体

返回值是 0 表示成功，负值表示失败。

这个函数在某些场景下很实用，比如你需要把地址信息传递给其他子系统时。但在简单的字符设备驱动里，直接用 `of_iomap()` 往往更方便。

---

## 资源管理 API：如何正确释放引用

到这里我们讲的都是"获取"资源的 API，但 Linux 内核编程有个黄金法则：**有获取就必须有释放**。OF API 也不例外。

### of_node_put：释放节点引用

当你用 `of_find_xxx()` 系列函数获取了一个 `device_node` 指针后，你就有了对这个节点的引用。内核用引用计数来管理这些节点，当你用完后必须调用 `of_node_put()` 来释放引用：

```c
void of_node_put(struct device_node *node);
```

参数 `node` 是你要释放的节点指针。

我们的 LED 驱动在出错处理和反初始化函数里都用到了它：

```c
/* 出错处理 */
ret = of_property_read_u32_array(led.device_tree_node, "reg", regdata, 10);
if (ret < 0) {
    pr_err("reg property read failed!\n");
    of_node_put(led.device_tree_node);  /* 释放节点引用 */
    return -EINVAL;
}

/* 反初始化函数 */
void led_hw_deinit(void) {
    /* ... 先 unmap 所有地址 ... */

    if (led.device_tree_node) {
        of_node_put(led.device_tree_node);
        led.device_tree_node = NULL;
    }
}
```

这里有个小技巧：我们在释放引用后把指针设为 `NULL`。这样即使 `deinit()` 函数被多次调用，也不会 double-free。

你可能会问：`of_find_property()` 需要配合 `of_node_put()` 吗？答案是：**不需要**。`property` 结构体是 `device_node` 的一部分，它的生命周期由节点管理。你只需要在用完整个节点后调用一次 `of_node_put()` 就行了。

---

## 实战示例：LED 驱动中的设备树使用

讲了这么多 API，现在我们把它们串起来，看看在实际驱动里是怎么用的。我们以 LED 硬件控制代码为例，完整走一遍流程。

### 第一步：查找节点

```c
static const char* kIMX_AES_LED = "/imx_aes_led";

led.device_tree_node = of_find_node_by_path(kIMX_AES_LED);
if (led.device_tree_node == NULL) {
    pr_err("dtsled node can not found!\n");
    return -EINVAL;
}
pr_info("dtsled node has been found!\n");
```

这里我们用路径查找节点。如果没找到，直接返回错误。注意这里还没释放引用，因为后面还要用这个节点。

### 第二步：读取属性（调试用）

```c
/* 读取 compatible 属性 */
proper = of_find_property(led.device_tree_node, "compatible", NULL);
if (proper == NULL) {
    pr_err("compatible property find failed\n");
} else {
    pr_info("compatible = %s\n", (char*)proper->value);
}

/* 读取 status 属性 */
ret = of_property_read_string(led.device_tree_node, "status", &str);
if (ret < 0) {
    pr_err("status read failed!\n");
} else {
    pr_info("status = %s\n", str);
}
```

这两步主要是为了调试，确认我们找到了正确的节点，并且节点状态是 `"okay"`。在实际生产代码里，这些调试信息可以去掉或改成 `pr_debug()`。

### 第三步：读取 reg 属性

```c
ret = of_property_read_u32_array(led.device_tree_node, "reg", regdata, 10);
if (ret < 0) {
    pr_err("reg property read failed!\n");
    of_node_put(led.device_tree_node);
    return -EINVAL;
}

pr_info("reg data:\n");
for (int i = 0; i < 10; i++) {
    pr_cont("%#X ", regdata[i]);
}
pr_cont("\n");
```

这里我们读取 `reg` 属性的所有 10 个整数。注意出错处理里调用了 `of_node_put()`，避免内存泄漏。

### 第四步：映射寄存器地址

```c
led.ccm_ccgr1 = of_iomap(led.device_tree_node, 0);
led.sw_mux_gpio = of_iomap(led.device_tree_node, 1);
led.sw_pad_gpio = of_iomap(led.device_tree_node, 2);
led.gpio_dr = of_iomap(led.device_tree_node, 3);
led.gpio_gdir = of_iomap(led.device_tree_node, 4);

if (!led.ccm_ccgr1 || !led.sw_mux_gpio || !led.sw_pad_gpio ||
    !led.gpio_dr || !led.gpio_gdir) {
    pr_err("ioremap failed!\n");
    of_node_put(led.device_tree_node);
    return -ENOMEM;
}
```

这里我们用 `of_iomap()` 一次性完成地址读取和映射。注意检查了所有映射是否成功，只要有一个失败就全部回滚。

### 第五步：硬件初始化

```c
/* 使能 GPIO1 时钟 */
val = readl(led.ccm_ccgr1);
pr_info("CCGR1 raw value: 0x%08x\n Bits: ", val);
pr_bin_u32(val);
pr_cont("\n");

val &= ~(3 << 26); /* 清除以前的设置 */
val |= (3 << 26);  /* 设置新值 */
writel(val, led.ccm_ccgr1);

/* 设置 GPIO1_IO03 复用功能为 GPIO */
writel(5, led.sw_mux_gpio);

/* 设置 GPIO1_IO03 电气属性 */
writel(0x10B0, led.sw_pad_gpio);

/* 设置 GPIO1_IO03 为输出功能 */
val = readl(led.gpio_gdir);
val &= ~(3 << 3); /* 清除以前的设置 */
val |= (1 << 3);  /* 设置为输出 */
writel(val, led.gpio_gdir);

/* 默认关闭 LED (高电平) */
val = readl(led.gpio_dr);
val |= (1 << 3);
writel(val, led.gpio_dr);
```

到这里，我们已经完成了从设备树读取配置到初始化硬件的完整流程。注意这里的寄存器操作（`readl()`/`writel()`）操作的是映射后的虚拟地址，而不是设备树里的物理地址。

### 第六步：资源释放

```c
void led_hw_deinit(void) {
    pr_info("Deinit LED Hardware\n");

    if (led.ccm_ccgr1) {
        iounmap(led.ccm_ccgr1);
        led.ccm_ccgr1 = NULL;
    }
    /* ... 其他 iounmap ... */

    if (led.device_tree_node) {
        of_node_put(led.device_tree_node);
        led.device_tree_node = NULL;
    }
}
```

卸载驱动时，我们释放所有映射的地址和节点引用。注意这里我们把指针设为 `NULL`，防止 double-free。

---

## 常见错误及处理方法

在实际使用 OF API 时，有几个常见的坑需要特别注意。

### 错误 1：忘记检查返回值

几乎所有 OF API 都有返回值，你必须检查它们：

```c
/* 错误示例 */
struct device_node *node = of_find_node_by_path("/some-node");
/* 直接用 node，没检查 NULL */
of_property_read_u32(node, "some-prop", &val);

/* 正确示例 */
struct device_node *node = of_find_node_by_path("/some-node");
if (!node) {
    pr_err("node not found\n");
    return -ENODEV;
}
ret = of_property_read_u32(node, "some-prop", &val);
if (ret) {
    pr_err("property read failed: %d\n", ret);
    of_node_put(node);
    return ret;
}
```

### 错误 2：忘记释放引用

这是内存泄漏的常见原因：

```c
/* 错误示例 */
struct device_node *node = of_find_node_by_path("/some-node");
/* 用完后没有调用 of_node_put() */

/* 正确示例 */
struct device_node *node = of_find_node_by_path("/some-node");
/* ... 使用 node ... */
of_node_put(node);
```

### 错误 3：数组长度不匹配

用 `of_property_read_u32_array()` 时，确保你分配的数组足够大：

```c
/* 危险示例 */
u32 data[5];
of_property_read_u32_array(node, "reg", data, 10);  /* 数组越界！ */

/* 安全示例 */
int count = of_property_count_elems_of_size(node, "reg", sizeof(u32));
u32 *data = kmalloc(count * sizeof(u32), GFP_KERNEL);
if (!data) return -ENOMEM;
of_property_read_u32_array(node, "reg", data, count);
/* ... 用完后 ... */
kfree(data);
```

### 错误 4：重复映射

不要对同一个地址调用多次 `of_iomap()`：

```c
/* 错误示例 */
void __iomem *addr1 = of_iomap(node, 0);
void __iomem *addr2 = of_iomap(node, 0);  /* 重复映射！ */

/* 正确做法 */
void __iomem *addr = of_iomap(node, 0);
/* 后续直接用 addr */
```

---

## 下一步

到这里，我们已经掌握了 OF API 的基础知识。你可以从设备树里读取节点、属性，完成地址映射，并正确释放资源。这已经足够编写简单的字符设备驱动了。

但还有几个高级话题我们没讲到：
- GPIO 子系统：如何用 `of_get_named_gpio()` 获取 GPIO 引脚
- 中断子系统：如何用 `of_irq_get()` 获取中断号
- 时钟子系统：如何用 `of_clk_get()` 获取时钟
- 设备模型：如何让驱动核心自动匹配设备树

这些内容会在后续的驱动实战章节中逐步展开。下一章，我们将深入平台设备驱动，看看设备树是如何与 Linux 驱动模型配合工作的。

**继续阅读：[06. OF API 验证](./06_of_api_verification.md)**
