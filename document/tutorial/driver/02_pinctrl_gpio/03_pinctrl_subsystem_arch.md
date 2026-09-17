# Pinctrl 子系统架构深度解析

## 前言：从硬件到软件的桥梁

在上一章我们了解了硬件层面是如何工作的：IOMUXC 控制器负责引脚复用，PAD 寄存器负责电气特性配置。现在的问题是：Linux 内核是怎么把这些硬件操作抽象成一个统一的子系统的？

说实话，pinctrl 子系统的源码量真的很大，光是 `pinctrl-imx.c` 就有两万多行代码。如果我们逐行分析，大概率会迷失在细节里。我们的策略是：抓住主线，理解核心流程，遇到细节再看。

## pinctrl 子系统的三重身份

pinctrl 子系统在 Linux 内核里扮演着三重角色。我习惯把它比喻成：**翻译官、复用管理员、电工**。

### 翻译官：设备树到硬件配置的翻译

设备树里写的引脚配置，最终要变成硬件寄存器的值。这个"翻译"工作就是 pinctrl 子系统做的。

你回忆一下设备树里的配置：

```dts
pinctrl_aes_led: led_grp {
    fsl,pins = <
        MX6UL_PAD_GPIO1_IO03__GPIO1_IO03    0x10B0
    >;
};
```

`MX6UL_PAD_GPIO1_IO03__GPIO1_IO03` 是一个宏定义，展开后是 5 个整数：`0x0068 0x02f4 0x0000 5 0`。这 5 个数字分别代表：mux_reg、conf_reg、input_reg、mux_val、input_val。

pinctrl 子系统的工作就是：读取这 5 个数字，解析出每个数字的含义，然后计算出需要写入哪个寄存器、写什么值。

### 复用管理员：统一管理所有引脚的复用配置

一个芯片可能有几百个引脚，每个引脚又可能复用成多种功能。如果让每个驱动自己配置引脚复用，很容易出问题：两个驱动同时用同一个引脚怎么办？配置顺序不同导致冲突怎么办？

pinctrl 子系统作为"管理员"，统一管理所有引脚的复用配置。当设备 A 需要用某个引脚时，它向 pinctrl 子系统申请；子系统检查这个引脚是否已经被占用，如果没有，就帮它配置好；如果有，就拒绝申请。

这样就避免了冲突。

### 电工：配置引脚的电气特性

引脚的电气特性——驱动强度、上下拉、迟滞等——也由 pinctrl 子系统配置。这些配置会影响信号质量，如果配置不当可能导致通信不稳定。

pinctrl 子系统把这些配置统一管理起来，驱动开发者不需要关心具体的电气参数，只要知道"我要标准配置"或"我要高速配置"就可以了。

## 核心数据结构

pinctrl 子系统的核心是一组数据结构，它们定义了子系统的接口和能力。让我们从下往上看：

### struct pinctrl_pin_desc：描述单个引脚

```c
struct pinctrl_pin_desc {
    unsigned int number;
    const char *name;
    void *drv_data;
};
```

这个结构体描述芯片上的一个物理引脚。`number` 是引脚的编号，`name` 是引脚的名称。

在 i.MX 的实现里，每个引脚都有一个这样的描述：

```c
#define IMX_PINCTRL_PIN(pin) PINCTRL_PIN(pin, #pin)
```

### struct imx_pin：描述引脚的配置

```c
struct imx_pin {
    unsigned int pin;
    union {
        struct imx_pin_mmio mmio;
        struct imx_pin_scu scu;
    } conf;
};

struct imx_pin_mmio {
    unsigned int mux_mode;    // 复用模式
    u16 input_reg;            // 输入选择寄存器
    unsigned int input_val;   // 输入选择值
    unsigned long config;     // 电气特性配置
};
```

这个结构体描述了一个引脚的完整配置信息：复用模式、输入选择、电气特性。

### struct pinctrl_dev：pinctrl 设备的核心结构

```c
struct pinctrl_dev {
    struct list_head node;
    struct device *dev;
    struct pinctrl_desc *desc;
    // ...
};
```

`pinctrl_dev` 是 pinctrl 子系统的核心数据结构，每个 pinctrl 控制器驱动都会创建一个。它包含了控制器的所有信息：支持的引脚、支持的分组、支持的功能等。

### struct pinctrl_desc：pinctrl 描述符

```c
struct pinctrl_desc {
    const char *name;
    struct pinctrl_pin_desc const *pins;
    unsigned int npins;
    const struct pinctrl_ops *pctlops;
    const struct pinmux_ops *pmxops;
    const struct pinconf_ops *confops;
    struct module *owner;
    // ...
};
```

这个结构体描述了一个 pinctrl 控制器的"能力"。 pins 指向引脚数组，npins 是引脚数量，三个 ops 结构体定义了控制器支持的操作。

## 三个 ops 结构体：pinctrl 的"工具箱"

pinctrl 子系统定义了三组操作函数，分别对应三个不同层次的功能。

### pinctrl_ops：引脚和分组管理

```c
struct pinctrl_ops {
    int (*get_groups_count)(struct pinctrl_dev *pctldev);
    const char *(*get_group_name)(struct pinctrl_dev *pctldev,
                   unsigned selector);
    int (*get_group_pins)(struct pinctrl_dev *pctldev,
                  unsigned selector,
                  const unsigned **pins,
                  unsigned *num_pins);
    int (*dt_node_to_map)(struct pinctrl_dev *pctldev,
                  struct device_node *np,
                  struct pinctrl_map **map,
                  unsigned *num_maps);
    void (*dt_free_map)(struct pinctrl_dev *pctldev,
                struct pinctrl_map *map,
                unsigned num_maps);
};
```

这组操作函数负责管理引脚分组。最重要的函数是 `dt_node_to_map`，它把设备树节点转换成 pinctrl 子系统能理解的"映射"。

在 i.MX 的实现里（`pinctrl-imx.c`）：

```c
static const struct pinctrl_ops imx_pctrl_ops = {
    .get_groups_count = pinctrl_generic_get_group_count,
    .get_group_name = pinctrl_generic_get_group_name,
    .get_group_pins = pinctrl_generic_get_group_pins,
    .pin_dbg_show = imx_pin_dbg_show,
    .dt_node_to_map = imx_dt_node_to_map,  // 关键函数
    .dt_free_map = imx_dt_free_map,
};
```

`imx_dt_node_to_map` 这个函数负责解析设备树里的 `fsl,pins` 属性，把每个引脚的配置转换成 `pinctrl_map` 结构体。

### pinmux_ops：引脚复用管理

```c
struct pinmux_ops {
    int (*get_functions_count)(struct pinctrl_dev *pctldev);
    const char *(*get_function_name)(struct pinctrl_dev *pctldev,
                    unsigned selector);
    int (*set_mux)(struct pinctrl_dev *pctldev,
            unsigned selector,
            unsigned group);
    // ...
};
```

这组操作函数负责设置引脚的复用功能。最重要的是 `set_mux` 函数，它实际执行寄存器操作，把引脚配置成指定的功能。

在 i.MX 的实现里：

```c
struct pinmux_ops imx_pmx_ops = {
    .get_functions_count = pinmux_generic_get_function_count,
    .get_function_name = pinmux_generic_get_function_name,
    .get_function_groups = pinmux_generic_get_function_groups,
    .set_mux = imx_pmx_set,  // 关键函数
};
```

`imx_pmx_set` 函数会遍历分组里的每个引脚，调用 `imx_pmx_set_one_pin_mmio` 来配置单个引脚：

```c
static int imx_pmx_set_one_pin_mmio(struct imx_pinctrl *ipctl,
                    struct imx_pin *pin)
{
    // ... 获取寄存器地址
    if (info->flags & SHARE_MUX_CONF_REG) {
        // 复用和配置在同一个寄存器的情况
        reg = readl(ipctl->base + pin_reg->mux_reg);
        reg &= ~info->mux_mask;
        reg |= (pin_mmio->mux_mode << info->mux_shift);
        writel(reg, ipctl->base + pin_reg->mux_reg);
    } else {
        // 复用和配置在不同寄存器的情况
        writel(pin_mmio->mux_mode, ipctl->base + pin_reg->mux_reg);
    }
    // ...
}
```

这里你可以看到，最终就是调用 `readl` 和 `writel` 来操作寄存器，和我们上一章讲的直接操作寄存器是一样的。

### pinconf_ops：引脚配置管理

```c
struct pinconf_ops {
    int (*pin_config_get)(struct pinctrl_dev *pctldev,
                 unsigned pin,
                 unsigned long *config);
    int (*pin_config_set)(struct pinctrl_dev *pctldev,
                 unsigned pin,
                 unsigned long *configs,
                 unsigned num_configs);
    // ...
};
```

这组操作函数负责配置引脚的电气特性：上下拉、驱动强度、迟滞等。

## 设备树解析流程：从设备树到内存结构

现在让我们来追踪一个完整的设备树解析流程。假设我们有这样的设备树：

```dts
&iomuxc {
    pinctrl_aes_led: led_grp {
        fsl,pins = <
            MX6UL_PAD_GPIO1_IO03__GPIO1_IO03    0x10B0
        >;
    };
};
```

系统启动后，pinctrl 驱动会加载并解析这些配置。流程大致是这样的：

```
1. pinctrl 驱动 probe 函数被调用
   ↓
2. 读取设备树，解析所有引脚定义
   ↓
3. 为每个引脚创建 struct imx_pin 结构体
   ↓
4. 注册到 pinctrl 核心层
   ↓
5. 当设备驱动加载时，通过 pinctrl子系统申请引脚配置
   ↓
6. pinctrl子系统调用 .set_mux 配置引脚复用
   ↓
7. pinctrl子系统调用 .pin_config_set 配置电气特性
```

## 主线内核与 imx 内核的差异对比

这里对比一下主线内核（`third_party/linux_mainline`）和 NXP imx 内核在 pinctrl 子系统实现上的差异——imx 侧的内容基于已退役的 linux-imx 树写成，当成行业背景材料看；正文的源码讲解仍然全部对着主线内核。

### 文件结构

两个内核的 pinctrl 驱动都位于 `drivers/pinctrl/freescale/` 目录下，文件结构基本相同：

```
pinctrl-imx.c          # 通用 i.MX pinctrl 实现
pinctrl-imx.h          # 头文件
pinctrl-imx6ul.c       # i.MX6UL 专用
pinctrl-imx6ull.c      # i.MX6ULL 专用
```

### 代码量对比

```
主线内核 pinctrl-imx.c:  21982 字节
imx 内核 pinctrl-imx.c:   21982 字节
```

两个版本的文件大小完全一样，这说明核心实现是同步的。但实际上，imx 内核可能有一些私有补丁或者针对特定硬件的修改。

### API 差异

从代码分析来看，两个内核的 pinctrl API 基本兼容。主要的差异可能在于：

1. **SCU 支持**：imx 内核对 SCU（System Controller Unit）的支持可能更完善，因为这是 NXP 芯片特有的功能。

2. **错误处理**：主线内核可能有更严格的错误检查和返回值处理。

3. **调试支持**：imx 内核可能添加了一些 NXP 私有的调试接口。

### 数据结构差异

两个内核的核心数据结构（`struct imx_pin`、`struct imx_pin_mmio`）完全一致，这意味着设备树配置在两个内核之间是可以兼容的。

## pinctrl 子系统的初始化流程

让我们看看 pinctrl 驱动是怎么初始化的。这是 probe 函数的简化流程：

```
imx_pinctrl_probe()
├── 获取设备树资源
│   └── of_address_to_resource() 获取寄存器地址
├── 映射寄存器地址
│   └── devm_ioremap_resource()
├── 解析引脚信息
│   ├── 从 soc_info 获取引脚数组
│   └── 为每个引脚分配寄存器地址
├── 注册到 pinctrl 核心层
│   ├── 填充 pinctrl_desc 结构体
│   ├── 设置 ops 函数
│   └── pinctrl_register()
└── 创建设备节点
    └── pinctrl_generic_add_group()
```

## 小结

pinctrl 子系统是 Linux 内核里相当复杂的一个子系统，但它的核心思想很简单：**统一管理芯片的引脚配置**。

从硬件角度看，pinctrl 子系统是对 IOMUXC 控制器和 PAD 寄存器的软件抽象。

从软件角度看，pinctrl 子系统提供了一套标准的 API，让设备驱动不需要关心具体的寄存器操作。

从架构角度看，pinctrl 子系统采用了经典的"核心层 + 平台驱动层"的分层设计。核心层提供通用的框架和管理，平台驱动层针对具体的硬件实现。

说实话，要完全理解 pinctrl 子系统需要花不少时间，但好消息是：作为驱动开发者，你不需要完全理解它的内部实现。你只需要知道怎么在设备树里配置引脚，怎么在驱动里使用 pinctrl API，就足够了。

**下一步：** 阅读 [04_pinctrl_device_tree.md](04_pinctrl_device_tree.md) 了解如何在设备树里配置 pinctrl。
