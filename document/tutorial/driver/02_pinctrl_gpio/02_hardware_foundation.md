---
title: 引脚复用与 GPIO 硬件原理
---

# i.MX 6ULL 引脚复用与 GPIO 硬件原理

## 前言：先搞清楚我们在操作什么

说实话，在深入子系统源码之前，我觉得非常有必要先搞清楚硬件是怎么工作的。很多教程一上来就讲 pinctrl 驱动、讲 gpio_chip，结果读者对硬件完全没有概念，看着那些抽象的数据结构完全不知道它们在映射什么硬件功能。

这就像你学开车，教练直接给你讲发动机原理、悬挂系统，但你连方向盘和油门在哪都不知道。所以我们的策略是：先搞清楚硬件长什么样，再来看软件是怎么抽象它的。

## 引脚复用：一个物理引脚，多种功能

让我们先来回答一个问题：为什么需要引脚复用？

i.MX 6ULL 这个芯片有很强大的功能——UART、SPI、I2C、PWM、Ethernet 等等。但如果每个功能都配独立的物理引脚，芯片的封装会变得非常大，成本也会飙升。所以芯片厂商做了一个很聪明的决定：让一个物理引脚可以被多个功能模块共享。

这就是**引脚复用（Pin Multiplexing）**的概念。

你想象一下，你家的客厅有"多种用途"：平时是客厅，有客人来了可以当客房，过年的时候还能当餐厅。同一个物理空间，在不同的场景下有不同的功能。芯片的引脚也是这样，GPIO1_IO03 这个引脚可以被配置成 GPIO，也可以被配置成 I2C1_SDA，还可以配置成 UART1_DCE_RX，等等。

具体选哪个功能，由我们通过软件来配置。配置的入口就是 IOMUXC（I/O Multiplexer Controller）控制器。

### IOMUXC 控制器

IOMUXC 是 i.MX 系列芯片里专门负责引脚复用的硬件模块。你可以把它理解成一个"巨大的多路选择器"，每个引脚都有一个开关，决定这个引脚的信号连接到哪个内部功能模块。

在芯片手册里，你会看到每个引脚都有一个 MUX 寄存器。这个寄存器决定了引脚的功能模式。比如 GPIO1_IO03 的 MUX 寄存器（SW_MUX_CTL_PAD_GPIO1_IO03）：

```
位 [2:0] - MUX_MODE
          000 = ALT0 - 这个引脚作为某个功能模块的信号
          001 = ALT1 - 这个引脚作为另一个功能模块的信号
          ...
          101 = ALT5 = GPIO - 这个引脚作为 GPIO 使用
```

当我们写 `writel(0x5, MUX_CTL_GPIO1_IO03)` 的时候，实际上是在告诉 IOMUXC：把 GPIO1_IO03 这个引脚连接到 GPIO 模块，而不是连接到 UART、I2C 或者其他模块。

### 引脚的多种功能

让我给你看一个真实的例子。GPIO1_IO03 这个引脚在 i.MX 6ULL 里有 9 种功能模式：

```
MUX_MODE = 0: I2C1_SDA      (I2C1 的数据线)
MUX_MODE = 1: GPT1_COMPARE3 (定时器比较输出)
MUX_MODE = 2: USB_OTG2_OC   (USB 过流检测)
MUX_MODE = 3: OSC32K_32K_OUT (32kHz 时钟输出)
MUX_MODE = 4: USDHC1_CD_B   (SD 卡检测)
MUX_MODE = 5: GPIO1_IO03    (GPIO 模式) ← 我们要用的
MUX_MODE = 6: CCM_DI0_EXT_CLK (外部时钟输入)
MUX_MODE = 7: SRC_TESTER_ACK (测试信号)
MUX_MODE = 8: UART1_DCE_RX  (UART1 接收)
```

这些信息都定义在设备树的 pinfunc.h 文件里：

```c
#define MX6UL_PAD_GPIO1_IO03__I2C1_SDA       0x0068 0x02f4 0x05a8 0 1
#define MX6UL_PAD_GPIO1_IO03__GPT1_COMPARE3  0x0068 0x02f4 0x0000 1 0
#define MX6UL_PAD_GPIO1_IO03__USB_OTG2_OC    0x0068 0x02f4 0x0660 2 0
#define MX6UL_PAD_GPIO1_IO03__OSC32K_32K_OUT 0x0068 0x02f4 0x0000 3 0
#define MX6UL_PAD_GPIO1_IO03__USDHC1_CD_B    0x0068 0x02f4 0x0668 4 0
#define MX6UL_PAD_GPIO1_IO03__GPIO1_IO03     0x0068 0x02f4 0x0000 5 0  ← 这一行
#define MX6UL_PAD_GPIO1_IO03__CCM_DI0_EXT_CLK 0x0068 0x02f4 0x0000 6 0
#define MX6UL_PAD_GPIO1_IO03__SRC_TESTER_ACK  0x0068 0x02f4 0x0000 7 0
#define MX6UL_PAD_GPIO1_IO03__UART1_DCE_RX   0x0068 0x02f4 0x0624 8 1
```

这里每个宏定义有 5 个参数（后面会详细解释），第 4 个参数就是 MUX_MODE 的值。你可以看到 `MX6UL_PAD_GPIO1_IO03__GPIO1_IO03` 的第 4 个参数是 5，对应的就是 ALT5 模式。

## PAD 配置：不只是选择功能

选择了功能之后还没完，引脚的电气特性也需要配置。这就像是装修房子，你决定了客厅的用途，还得决定铺什么地板、装什么灯、墙面刷什么颜色。

这些电气特性包括：驱动强度、上下拉电阻、迟滞、速率等等。它们会影响信号的质量和抗干扰能力。

### PAD 寄存器

每个引脚除了有 MUX 寄存器，还有一个 PAD 寄存器（SW_PAD_CTL_PAD_GPIO1_IO03）。这个寄存器配置引脚的电气特性。

i.MX 6ULL 的 PAD 寄存器是 32 位的，每个位都有特定的含义：

```
位 [16]    - HYS   (迟滞使能)
位 [15:14] - PUS   (上下拉选择)
             00 = 100K 下拉
             01 = 47K 上拉
             10 = 100K 上拉
             11 = 22K 上拉
位 [13]    - PUE   (上下拉使能)
             0 = 保留 / 100K 下拉
             1 = 上拉/下拉使能
位 [12]    - PKE   (保持使能)
             0 = 禁用保持器
             1 = 使能保持器
位 [11]    - ODE   (开漏使能)
             0 = 禁止开漏
             1 = 使能开漏
位 [10:6]  - SPEED (速率选择)
             000 = 低速
             001 = 中速
             010 = 高速
             100 = 超高速
位 [5:3]   - DSE   (驱动强度选择)
             000 = 关闭驱动
             001 = R0(260 欧姆)
             010 = R0/2
             011 = R0/3
             100 = R0/4
             101 = R0/5
             110 = R0/6
             111 = R0/7
位 [1:0]   - SRE  (快速 slew rate)
             0 = 慢速 slew rate
             1 = 快速 slew rate
```

这些参数的具体含义取决于你的应用场景。比如：

- **驱动强度（DSE）**：如果你的引脚要驱动长线或者多个负载，就需要更大的驱动强度。
- **上下拉（PUS/PUE/PKE）**：如果引脚在空闲时可能悬空，就需要加上拉或下拉电阻来避免不确定状态。
- **迟滞（HYS）**：对于输入引脚，使能迟滞可以提高抗干扰能力。
- **速率（SPEED/SRE）**：对于高速信号（如 UART、SPI），需要配置更快的速率。

我们的 LED 驱动使用的配置值是 `0x10B0`，让我们来分解一下：

```
0x10B0 = 0b0001 0000 1011 0000

位 [16]    HYS   = 0  (不使能迟滞)
位 [15:14] PUS   = 10 (100K 上拉)
位 [13]    PUE   = 1  (使能上拉)
位 [12]    PKE   = 1  (使能保持器)
位 [11]    ODE   = 0  (禁止开漏)
位 [10:6]  SPEED = 00010 (中速)
位 [5:3]   DSE   = 011 (R0/3)
位 [1:0]   SRE   = 0  (慢速 slew rate)
```

这个配置对于 LED 控制来说完全足够。LED 不需要高速信号，也不需要很强的驱动能力，所以用了中速和中等驱动强度。

## GPIO 模块：点亮 LED 的最后一步

当我们把引脚配置成 GPIO 功能之后，还需要配置 GPIO 模块本身才能控制 LED。

i.MX 6ULL 有多个 GPIO 模块（GPIO1~GPIO5），每个模块最多控制 32 个 GPIO。GPIO1_IO03 表示这是 GPIO1 模块的第 3 号引脚。

### GPIO 寄存器

GPIO 模块有一组寄存器，最常用的有几个：

```
DR (Data Register)      - 数据寄存器，读写 GPIO 的值
GDIR (Direction Register) - 方向寄存器，设置 GPIO 是输入还是输出
PSR (Pad Status Register) - 状态寄存器，读取 GPIO 的实际电平
ICR1/ICR2 (Interrupt Control) - 中断控制寄存器
IMR (Interrupt Mask)    - 中断屏蔽寄存器
ISR (Interrupt Status)  - 中断状态寄存器
EDGE_SEL (Edge Select)  - 边沿选择寄存器
```

对于我们的 LED 控制，只需要关注 DR 和 GDIR 这两个寄存器。

#### GDIR：方向寄存器

在使用 GPIO 之前，必须先设置它的方向：是输入还是输出。

```c
// 设置 GPIO1_IO03 为输出
writel(readl(GPIO1_GDIR) | (1 << 3), GPIO1_GDIR);
```

GDIR 寄存器的每一位对应一个 GPIO。位 3 对应 GPIO1_IO03，写 1 表示输出，写 0 表示输入。

#### DR：数据寄存器

对于输出引脚，写 DR 寄存器可以设置引脚的电平。

```c
// 点亮 LED（写 0）
writel(readl(GPIO1_DR) & ~(1 << 3), GPIO1_DR);

// 熄灭 LED（写 1）
writel(readl(GPIO1_DR) | (1 << 3), GPIO1_DR);
```

对于输入引脚，读 DR 寄存器可以获取引脚的电平。

## 时钟控制：别忘了给 GPIO 模块供电

这里有个很容易被忽略的细节：GPIO 模块也需要时钟！如果时钟没使能，你操作 GPIO 寄存器不会有任何效果。

i.MX 6ULL 的时钟由 CCM（Clock Controller Module）控制。每个外设模块都有对应的时钟门控寄存器，需要手动使能。

```c
// 使能 GPIO1 的时钟
// CCM_CCGR1 的位 [27:26] 控制 GPIO1
writel(readl(IMX6U_CCM_CCGR1) | (3 << 26), IMX6U_CCM_CCGR1);
```

CCM_CCGRx 寄存器每个模块占 2 位：
- `00` = 时钟关闭（低功耗模式）
- `01` = 时钟在运行模式下开启
- `10` = 保留
- `11` = 时钟始终开启

⚠️ **注意**：这一步真的很容易忘！如果你配置了引脚、设置了方向，但 LED 就是不亮，大概率是时钟没使能。

## 完整的初始化流程

现在让我们把所有步骤串起来，看看完整的初始化流程是什么样子的：

```
1. 使能 GPIO1 模块的时钟
   writel(readl(CCM_CCGR1) | (3 << 26), CCM_CCGR1);

2. 配置 GPIO1_IO03 的引脚复用为 GPIO 功能
   writel(0x5, MUX_CTL_PAD_GPIO1_IO03);

3. 配置 GPIO1_IO03 的电气特性
   writel(0x10B0, PAD_CTL_PAD_GPIO1_IO03);

4. 设置 GPIO1_IO03 为输出模式
   writel(readl(GPIO1_GDIR) | (1 << 3), GPIO1_GDIR);

5. 控制 GPIO1_IO03 的电平
   writel(readl(GPIO1_DR) & ~(1 << 3), GPIO1_DR);  // 点亮
```

每一步都必须按顺序来，不能跳过。而且每一步都有对应的寄存器地址，你需要从芯片手册里查到这些地址。

## 硬件连接：低电平有效

最后让我们看看硬件连接。我们的 LED 是连接在 GPIO1_IO03 上的，但有一个细节：这个 LED 是**低电平有效**的。

什么叫低电平有效？意思是当 GPIO 输出低电平（0V）的时候，LED 点亮；当 GPIO 输出高电平（3.3V）的时候，LED 熄灭。

这是因为 LED 的接法。常见的有两种接法：

```
高电平有效：
3.3V → [限流电阻] → [LED] → GPIO

低电平有效：
3.3V → [限流电阻] → [LED] → GPIO
                    ↓
                  (实际上 LED 的负极接 GPIO)
```

低电平有效的接法更常见，因为很多芯片的 GPIO 灌电流能力（sink capability）比拉电流能力（source capability）更强。

所以在我们的驱动代码里，你会发现：

```c
// LED 初始化时设置为 1（熄灭）
gpio_direction_output(led.gpio_sub_sys_nr, 1);

// 点亮 LED 时写 0
gpio_set_value(led.gpio_sub_sys_nr, 0);

// 熄灭 LED 时写 1
gpio_set_value(led.gpio_sub_sys_nr, 1);
```

这个逻辑看起来是反的，但配合硬件连接就是对的。

如果你在设备树里看到 `GPIO_ACTIVE_LOW`，就是在告诉内核：这个 GPIO 是低电平有效的。内核会自动处理反转，你就可以用正常的逻辑（1 表示开，0 表示关）来编程了。

## 寄存器地址一览

为了方便你查阅，我把涉及到的寄存器地址列出来：

```
// 时钟控制
CCM_CCGR1    = 0x020C406C

// GPIO1 模块
GPIO1_DR     = 0x0209C000  // 数据寄存器
GPIO1_GDIR   = 0x0209C004  // 方向寄存器
GPIO1_PSR    = 0x0209C008  // 状态寄存器

// GPIO1_IO03 的引脚控制
MUX_CTL_PAD_GPIO1_IO03    = 0x020E0068  // 引脚复用控制
PAD_CTL_PAD_GPIO1_IO03    = 0x020E02F4  // 电气特性配置
```

这些地址可以从 i.MX 6ULL 的参考手册（Reference Manual）里查到。手册有几千页，但你需要关注的只是 GPIO 章节和 IOMUXC 章节。

## 下一章：软件登场

现在我们对硬件有了完整的理解。我们知道了：

1. 引脚可以通过 IOMUXC 配置成不同的功能
2. 引脚的电气特性可以通过 PAD 寄存器配置
3. GPIO 模块需要时钟使能才能工作
4. GPIO 的方向和数据需要通过 GDIR 和 DR 寄存器控制

接下来就是有趣的部分了：Linux 内核是怎么把这些硬件操作抽象成子系统的？pinctrl 子系统和 gpio 子系统是如何协同工作的？

**下一步：** 阅读 [03_pinctrl_subsystem_arch.md](03_pinctrl_subsystem_arch.md) 了解 pinctrl 子系统的架构和实现。
