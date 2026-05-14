# 10. 完整实战演练——从零开始的设备树驱动开发

## 前言：把所有知识串起来

到这里，我们已经学了不少东西：设备树是什么、语法怎么写、OF API怎么用、板级DTS怎么改。但说实话，这些知识如果不成体系，很容易学了后面忘前面。就像你学会了砌砖、学会了和水泥、学会了看图纸，但如果没亲手盖过房子，真正上手时还是会手忙脚乱。

所以这一章，我们来个"大合练"。从空白开始，一步一步走完整个流程：编写DTS设备树文件、编译DTB、编写设备树驱动代码、编译驱动模块、部署到板子、加载驱动测试。这六个步骤走完，你就能真正理解设备树驱动开发的完整闭环了。

这一章的定位是"实战攻略"，理论点到为止，重点是"怎么做"和"怎么验证"。我们会以点亮LED为实验目标，因为这个实验足够简单，不会让你在硬件调试上浪费太多时间，同时又涵盖了设备树驱动的所有核心要素。

我们的实验环境是：imx-forge项目、Alpha开发板、主线内核。如果你用的是其他板子也没关系，原理是一样的，只需要根据你的硬件调整寄存器地址即可。

---

## 实验目标：我们要实现什么

在开始之前，先明确一下我们要做什么。我们的目标是：

1. 在设备树中描述LED硬件的寄存器地址
2. 编写一个驱动程序，从设备树中读取这些地址
3. 通过驱动程序控制LED的点亮和熄灭
4. 验证整个流程的正确性

这个实验的核心不在于"点亮灯"，而在于"通过描述硬件来点亮灯"。这是传统驱动开发和现代驱动开发的分水岭。

---

## 完整流程：六步走

我们把整个实验分解为六个步骤：

1. **编写DTS设备树文件**：在设备树中"画"出硬件
2. **编译DTB**：把文本描述转换为二进制格式
3. **编写设备树驱动代码**：实现"读说明书"的驱动
4. **编译驱动模块**：生成.ko文件
5. **部署到板子**：把DTB和.ko放到正确的位置
6. **加载驱动测试**：见证奇迹的时刻

这六个步骤是一环扣一环的，任何一步出错都会导致最终失败。所以我们每一步都要仔细验证，确保无误后再进行下一步。

---

## 步骤1：编写DTS设备树文件

首先，我们需要在设备树中描述LED硬件。这个描述就像是在填写一张极其严格的表格，错一个标点都可能让内核忽略你的设备。

### 确定寄存器地址

根据IMX6ULL的芯片手册，控制LED需要操作以下几个寄存器：

- `CCM_CCGR1` (0x020C406C)：时钟使能寄存器
- `SW_MUX_GPIO1_IO03` (0x020E0068)：GPIO复用寄存器
- `SW_PAD_GPIO1_IO03` (0x020E02F4)：GPIO电气属性寄存器
- `GPIO1_DR` (0x0209C000)：GPIO数据寄存器
- `GPIO1_GDIR` (0x0209C004)：GPIO方向寄存器

这些地址是芯片物理地址，驱动程序需要通过ioremap映射到虚拟地址后才能操作。

### 编写设备节点

打开你的设备树文件。在我们的项目中，这个文件位于 `driver/device_tree/alpha-board/device_tree_try_03/imx6ull-aes-led.dts`。在根节点 `/` 下添加如下内容：

```dts
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

/ {
    model = "Awesome Embedded Studio IMX6ULL Example Driver";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

    imx_aes_led {
        #address-cells = <1>;
        #size-cells = <1>;
        compatible = "atkalpha-led";
        status = "okay";
        reg = < 0X020C406C 0X04    /* CCM_CCGR1_BASE */
                0X020E0068 0X04    /* SW_MUX_GPIO1_IO03_BASE */
                0X020E02F4 0X04    /* SW_PAD_GPIO1_IO03_BASE */
                0X0209C000 0X04    /* GPIO1_DR_BASE */
                0X0209C004 0X04 >; /* GPIO1_GDIR_BASE */
    };
};
```

让我们逐行解析这段代码的含义：

**第11-20行：设备节点定义**

- `imx_aes_led`：节点名称，在驱动中通过路径 `/imx_aes_led` 来查找这个节点
- `#address-cells = <1>`：告诉内核子节点的reg属性中，地址占用1个单元格（32位）
- `#size-cells = <1>`：告诉内核子节点的reg属性中，长度占用1个单元格（32位）
- `compatible = "atkalpha-led"`：驱动匹配标识，驱动代码里的of_device_id表会包含这个字符串
- `status = "okay"`：设备状态为启用，如果设为"disabled"，内核会跳过这个设备
- `reg`属性：寄存器地址列表，格式为"地址1 长度1 地址2 长度2..."

这里有一个新手极易踩的坑：**reg里的数字必须严格遵循#address-cells和#size-cells定义的格式**。因为我们前面定义了都是1，所以这里的格式就是：地址、长度、地址、长度...以此类推。

### 节点位置选择

你可能会问：为什么把这个节点直接放在根节点下面？能不能放在其他位置？

答案是：可以，但要看具体情况。如果设备是挂在SOC内部总线上的（比如我们直接操作GPIO寄存器），通常放在根节点下面。如果设备是挂在外部总线上的（比如I2C设备、SPI设备），则应该放在对应的总线节点下面。

对于我们的LED实验，它直接操作GPIO寄存器，所以放在根节点下是合适的。

### 验证DTS语法

在编译之前，最好先检查一下语法是否正确。DTC编译器会帮你检查大部分语法错误：

```bash
# 语法检查（不生成输出文件）
dtc -I dts -O dtb -o /dev/null driver/device_tree/alpha-board/device_tree_try_03/imx6ull-aes-led.dts
```

如果没有报错，说明语法基本正确。如果报错了，根据错误提示修改相应位置。

---

## 步骤2：编译DTB

写好了DTS文件，下一步就是把它编译成DTB格式。内核只能读取二进制的DTB文件，不能直接读取DTS文本文件。

### 使用build_driver.sh脚本

在我们的imx-forge项目中，最简单的方式是使用构建脚本：

```bash
# 进入项目根目录
cd /home/charliechen/imx-forge

# 构建驱动（会自动编译设备树）
./scripts/driver_helper/build_driver.sh device_tree_try_03 alpha-board
```

这个脚本会自动完成以下工作：
1. 查找驱动的源码和设备树文件
2. 编译驱动代码生成.ko文件
3. 编译设备树文件生成.dtb文件
4. 把所有产物放到 `out/driver_artifacts/device_tree_try_03/alpha-board/` 目录

执行后，你应该看到类似这样的输出：

```
🔨 编译device_tree_try_03驱动...
✓ 驱动编译完成: out/driver_artifacts/device_tree_try_03/alpha-board/device_tree_try_03_driver.ko
✓ 设备树编译完成: out/driver_artifacts/device_tree_try_03/alpha-board/imx6ull-aes-led.dtb
```

### 手动编译DTB

如果你想单独编译设备树，可以使用DTC命令：

```bash
# 基本编译命令
dtc -I dts -O dtb -o imx6ull-aes-led.dtb imx6ull-aes-led.dts

# 带include路径的编译（如果你的DTS引用了其他文件）
dtc -I dts -O dtb -i driver/device_tree/alpha-board/ \
    -o imx6ull-aes-led.dtb \
    driver/device_tree/alpha-board/device_tree_try_03/imx6ull-aes-led.dts
```

### 检查编译结果

编译完成后，检查一下产物是否正确生成：

```bash
# 查看产物目录
ls -lh out/driver_artifacts/device_tree_try_03/alpha-board/

# 预期输出：
# device_tree_try_03_driver.ko
# imx6ull-aes-led.dtb
```

如果只看到了.ko文件但没有.dtb文件，说明设备树编译失败了。这时候你需要检查：
1. DTS文件路径是否正确
2. include的.dtsi文件是否存在
3. DTC编译器是否正确安装

### 反编译验证

如果你想确认编译出来的DTB是否正确，可以把它反编译回DTS格式进行对比：

```bash
# 反编译DTB
dtc -I dtb -O dts -o test_from_dtb.dts \
    out/driver_artifacts/device_tree_try_03/alpha-board/imx6ull-aes-led.dtb

# 查看反编译结果
cat test_from_dtb.dts

# 对比关键节点
grep -A 10 "imx_aes_led" test_from_dtb.dts
```

反编译的DTS可能和原始DTS在格式上有些差异，但节点结构和属性值应该是一致的。

---

## 步骤3：编写设备树驱动代码

设备树准备好了，现在的任务是编写驱动。这一步的核心逻辑是：**去设备树里把刚才填的那些值"抠"出来，然后操作寄存器控制LED**。

我们的驱动代码分为两个文件：`led_hw.c` 负责硬件操作，`device_tree_try_03_driver_main.c` 负责字符设备框架。这种分离的设计让代码结构更清晰，也便于以后复用。

### 头文件与结构体准备

首先，既然要跟设备树打交道，必须引入对应的头文件：

```c
#include <linux/of.h>
#include <linux/of_address.h>
```

这两行是门票，没有它们，后面的OF函数一个都用不了。

接下来，我们需要一个结构体来保存从设备树获取的信息和映射后的虚拟地址：

```c
/* LED hardware register mapping structure */
struct led_handle {
    void __iomem* ccm_ccgr1;
    void __iomem* sw_mux_gpio;
    void __iomem* sw_pad_gpio;
    void __iomem* gpio_dr;
    void __iomem* gpio_gdir;
    struct device_node* device_tree_node;
};
```

请注意最后一个成员 `device_tree_node`，它保存了我们在设备树中找到的节点指针，后续所有操作都要靠它。

### 核心动作：从设备树获取信息

真正的重头戏在硬件初始化函数 `led_hw_init` 里。这里发生了一次"接力"：数据从DTS流向内核内存，再流向驱动变量。

```c
int led_hw_init(void) {
    u32 regdata[10];
    int ret;
    const char* str;
    struct property* proper;
    u32 val;

    /* 1. 获取设备节点：imx_aes_led */
    led.device_tree_node = of_find_node_by_path("/imx_aes_led");
    if (led.device_tree_node == NULL) {
        pr_err("dtsled node can not found!\n");
        return -EINVAL;
    }
    pr_info("dtsled node has been found!\n");
```

**第一步：找人。**

`of_find_node_by_path("/imx_aes_led")` 就像在电话簿里按名字找人。这里的路径必须和DTS里写的一样（包括根节点`/`）。如果返回NULL，说明设备树里根本没这个节点，或者路径写错了。

```c
    /* 2. 获取 compatible 属性内容 */
    proper = of_find_property(led.device_tree_node, "compatible", NULL);
    if (proper == NULL) {
        pr_err("compatible property find failed\n");
    } else {
        pr_info("compatible = %s\n", (char*)proper->value);
    }
```

**第二步：查户口。**

`of_find_property` 用来找某个具体的属性。这里我们找 `compatible`。`proper->value` 指向的就是属性值字符串本身。这里主要是演示如何读取，在实际驱动中，你可能会根据 `compatible` 的不同值来做不同的初始化逻辑。

```c
    /* 3. 获取 status 属性内容 */
    ret = of_property_read_string(led.device_tree_node, "status", &str);
    if (ret < 0) {
        pr_err("status read failed!\n");
    } else {
        pr_info("status = %s\n", str);
    }
```

**第三步：看状态。**

`of_property_read_string` 是专门用来读字符串属性的。这里我们把 `status` 的值读到了 `str` 指针里。如果读出来是 `"okay"`，我们才继续往下走；如果是 `"disabled"`，这里就应该直接return结束了。

```c
    /* 4. 获取 reg 属性内容 */
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

**第四步：拿地址（关键）。**

`of_property_read_u32_array` 是重头戏。注意看参数：
- `led.device_tree_node`：节点指针
- `"reg"`：属性名
- `regdata`：接收数据的数组
- `10`：读取多少个值

还记得我们在DTS里写了5组寄存器，每组有"地址"和"长度"两个值，加起来正好是10个`u32`数据。执行完这一句，`regdata`数组里就存满了我们在DTS里写的那一大串十六进制数字。

### 内存映射：使用of_iomap

拿到了物理地址数组，下一步就是映射。这里我们使用更现代的 `of_iomap` 方法：

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

`of_iomap(dtsled.nd, 0)` 做了什么？它自动去查找 `dtsled.nd` 节点下的 `reg` 属性，**直接取出第0组（index 0）地址段进行映射**，返回映射好的虚拟地址。

第0组是什么？回顾DTS，`reg`的第一组是 `0X020C406C 0X04`，对应 `CCM_CCGR1`。第1组（index 1）是 `SW_MUX...`，以此类推。

这样写代码极其清爽：**不需要中间数组 `regdata`，也不需要手动计算索引，直接告诉内核"我要这个节点的第几块内存"**。

### 硬件初始化：配置寄存器

映射完成后，我们就可以像操作普通内存一样操作寄存器了：

```c
    /* 6. 使能GPIO1时钟 */
    val = readl(led.ccm_ccgr1);
    val &= ~(3 << 26); /* 清除以前的设置 */
    val |= (3 << 26);  /* 设置新值 */
    writel(val, led.ccm_ccgr1);

    /* 7. 设置GPIO1_IO03复用功能为GPIO */
    writel(5, led.sw_mux_gpio);

    /* 8. 设置GPIO1_IO03电气属性 */
    writel(0x10B0, led.sw_pad_gpio);

    /* 9. 设置GPIO1_IO03为输出功能 */
    val = readl(led.gpio_gdir);
    val &= ~(3 << 3); /* 清除以前的设置 */
    val |= (1 << 3);  /* 设置为输出 */
    writel(val, led.gpio_gdir);

    /* 10. 默认关闭LED (高电平) */
    val = readl(led.gpio_dr);
    val |= (1 << 3);
    writel(val, led.gpio_dr);

    pr_info("LED Init OK!\n");
    return 0;
}
```

这些寄存器操作的含义我们不在这一章详细展开，因为它们和设备树本身无关。你只需要知道：无论地址是从哪里来的（硬编码还是设备树），硬件寄存器的操作方式是不会变的。

### LED控制函数

最后，我们需要提供控制LED的接口：

```c
void led_set_status(bool status) {
    u32 val = readl(led.gpio_dr);
    pr_info("led_set_status: status=%d, GPIO1_DR before=0x%08x\n", status, val);

    if (status) {
        val &= ~(1 << 3); /* 低电平点亮 */
    } else {
        val |= (1 << 3); /* 高电平熄灭 */
    }
    writel(val, led.gpio_dr);

    pr_info("led_set_status: GPIO1_DR after=0x%08x\n", val);
}

bool led_get_status(void) {
    u32 val = readl(led.gpio_dr);
    return (val & (1 << 3)) == 0;
}
```

注意这里的LED是低电平点亮的，所以逻辑稍微有点绕：写0点亮，写1熄灭。

### 字符设备框架

剩下的字符设备框架代码（file_operations、cdev、class、device等）和传统驱动完全一样，这里不再赘述。完整代码请参考项目中的 `device_tree_try_03_driver_main.c` 文件。

---

## 步骤4：编译驱动模块

驱动代码写好了，下一步就是编译。我们使用内核的模块编译机制，生成可以在运行时加载的.ko文件。

### 使用build_driver.sh脚本

最简单的方式还是使用我们的构建脚本：

```bash
# 进入项目根目录
cd /home/charliechen/imx-forge

# 构建驱动
./scripts/driver_helper/build_driver.sh device_tree_try_03 alpha-board
```

这个脚本会自动处理以下事情：
1. 设置正确的交叉编译工具链
2. 指定内核源码路径
3. 调用make编译模块
4. 把编译产物放到输出目录

### 手动编译

如果你想手动编译，可以进入驱动目录直接执行make：

```bash
# 进入驱动目录
cd driver/device_tree_try_03/alpha-board

# 编译
make
```

Makefile的内容大致如下：

```makefile
# Kernel module definition
obj-m := device_tree_try_03_driver.o
device_tree_try_03_driver-y := device_tree_try_03_driver_main.o led_hw.o

# 项目配置
PROJECT_ROOT := $(shell realpath $(CURDIR)/../..)
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码路径
KDIR := $(PROJECT_ROOT)/third_party/linux-${KERNEL_TYPE}
KOBJ := $(PROJECT_ROOT)/out/${KERNEL_TYPE}

modules:
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
```

请注意这里的一个细节：我们的驱动由两个 `.o` 文件组成（`device_tree_try_03_driver_main.o` 和 `led_hw.o`），它们会被链接成一个最终的 `.ko` 模块。

### 检查编译结果

编译完成后，检查一下产物：

```bash
# 查看产物目录
ls -lh out/driver_artifacts/device_tree_try_03/alpha-board/

# 预期输出：
# device_tree_try_03_driver.ko    (约14K)
# imx6ull-aes-led.dtb             (约35K)
```

你可以使用 `modinfo` 命令查看模块的信息：

```bash
# 查看模块信息
modinfo out/driver_artifacts/device_tree_try_03/alpha-board/device_tree_try_03_driver.ko

# 输出示例：
# filename:       device_tree_try_03_driver.ko
# version:        1.0
# description:    Device Tree try
# author:         Charliechen114514
# license:        GPL
# vermagic:       5.10.0 SMP mod_unload modversions aarch64
```

请注意 `vermagic` 字段，它显示了模块编译时的内核版本。如果你的板子运行的是不同版本的内核，模块加载时会因为版本不匹配而失败。

---

## 步骤5：部署到板子

编译好了.ko和.dtb文件，下一步就是把它们部署到开发板上。这一步看似简单，但新手经常在这里卡住，因为不同的启动方式对应的部署方法不同。

### 部署DTB文件

在我们的项目中，使用TFTP启动是最常见的方式。DTB文件需要放在TFTP服务器的根目录下：

```bash
# 使用deploy_driver.sh脚本部署
./scripts/driver_helper/deploy_driver.sh device_tree_try_03 alpha-board --target=tftp

# 或者手动拷贝
sudo cp out/driver_artifacts/device_tree_try_03/alpha-board/imx6ull-aes-led.dtb /srv/tftp/imx6ull-aes.dtb
```

请注意这里的一个细节：目标文件名是 `imx6ull-aes.dtb`，而不是 `imx6ull-aes-led.dtb`。这是因为U-Boot在启动时会加载一个固定名字的DTB文件，这个名字在U-Boot环境变量里定义。

如果你不确定自己的板子使用哪个DTB文件名，可以在U-Boot命令行输入 `printenv` 查看所有环境变量：

```
=> printenv fdt_file
fdt_file=imx6ull-aes.dtb
```

### 部署KO文件

驱动模块文件可以放在NFS rootfs中，或者通过其他方式传输到板子上：

```bash
# 使用deploy_driver.sh脚本部署
./scripts/driver_helper/deploy_driver.sh device_tree_try_03 alpha-board --target=nfs

# 或者手动拷贝到NFS目录
cp out/driver_artifacts/device_tree_try_03/alpha-board/device_tree_try_03_driver.ko /path/to/nfs/root/lib/modules/

# 或者通过scp/串口传输
scp out/driver_artifacts/device_tree_try_03/alpha-board/device_tree_try_03_driver.ko root@192.168.1.100:/lib/modules/
```

### 重启板子

部署好DTB文件后，需要重启板子让U-Boot重新加载设备树：

```bash
# 在板子上执行
reboot
```

重启后，你可以先验证设备树是否正确加载：

```bash
# 查看设备树节点是否存在
ls /proc/device-tree/imx_aes_led/

# 查看节点的属性
cat /proc/device-tree/imx_aes_led/compatible
# 输出：atkalpha-led

cat /proc/device-tree/imx_aes_led/status
# 输出：okay

hexdump -C /proc/device-tree/imx_aes_led/reg
# 输出寄存器地址列表
```

如果节点不存在，说明DTB文件没有正确加载或者节点路径写错了。如果节点存在但属性值不对，说明DTS文件里的属性定义有问题。

---

## 步骤6：加载驱动测试

终于到了这一刻：见证奇迹的时刻。如果前面所有的步骤都正确无误，这一步应该是水到渠成的。

### 加载驱动模块

首先，加载驱动模块：

```bash
# 在板子上执行
insmod device_tree_try_03_driver.ko

# 或者使用modprobe（需要先depmod）
depmod
modprobe device_tree_try_03_driver
```

加载成功后，你应该能在内核日志中看到类似这样的输出：

```
[   12.345678] === Device Tree try ===
[   12.345679] dtsled node has been found!
[   12.345680] compatible = atkalpha-led
[   12.345681] status = okay
[   12.345682] reg data:
[   12.345683] 0X20C406C 0X4 0X20E0068 0X4 0X20E02F4 0X4 0X209C000 0X4 0X209C004 0X4
[   12.345684] IMX6U_CCM_CCGR1    = 0xe8d88000
[   12.345685] SW_MUX_GPIO1_IO03  = 0xe8d90000
[   12.345686] SW_PAD_GPIO1_IO03  = 0xe8d92000
[   12.345687] GPIO1_DR           = 0xe8d00000
[   12.345688] GPIO1_GDIR         = 0xe8d04000
[   12.345689] CCGR1 raw value: 0x0fffffff
[   12.345690] Bits: 00001111222222222222222222222222
[   12.345691] CCGR1 new value: 0x0fffffff
[   12.345692] Bits: 00001111222222222222222222222222
[   12.345693] GPIO1_GDIR = 0x00000008
[   12.345694] GPIO1_DR init = 0x00000008 (LED OFF)
[   12.345695] LED Init OK!
[   12.345696] Init the User Interfaces and driver handles
[   12.345697] LED handle get the device number: major: 245, minor: 0
[   12.345698] cdev series api called success!
[   12.345699] class create success!
[   12.345700] device create success!
[   12.345701] ========================
```

**这一刻意义非凡。**

这串日志意味着：
1. 内核在设备树里找到了你写的 `imx_aes_led` 节点
2. 驱动成功读取了 `compatible` 和 `status` 属性
3. 最关键的是，`reg data` 打印出来的地址，和你在 `.dts` 文件里写的完全一致
4. 寄存器映射成功，虚拟地址已经分配
5. 字符设备创建成功，设备号已经分配

### 检查设备文件

驱动加载成功后，应该在 `/dev` 目录下看到设备文件：

```bash
# 查看设备文件
ls -l /dev/AES_LED

# 输出示例：
# crw------- 1 root root 245, 0 Jan 1 00:00 /dev/AES_LED
```

这里的 `245, 0` 就是主设备号和次设备号，应该和日志中打印的一致。

### 测试LED控制

现在，点灯仪式开始：

```bash
# 点亮LED（低电平有效）
echo 1 > /dev/AES_LED

# 熄灭LED（高电平有效）
echo 0 > /dev/AES_LED
```

看板子上的LED，亮了吗？如果亮了，恭喜，你刚刚完成了你的第一次"设备树驱动开发"！

同时，你可以在内核日志中看到寄存器操作的信息：

```
[  123.456789] Device: AES_LED called open!
[  123.456790] aes_chardev_write: cnt=2
[  123.456791] LED status: 1 (user_led_new_status='1')
[  123.456792] led_set_status: status=1, GPIO1_DR before=0x00000008
[  123.456793] led_set_status: GPIO1_DR after=0x00000000
```

请注意 `GPIO1_DR` 的值变化：从 `0x00000008`（bit3=1，LED熄灭）变成 `0x00000000`（bit3=0，LED点亮）。

### 读取LED状态

你也可以读取LED的当前状态：

```bash
# 读取LED状态
cat /dev/AES_LED

# 输出：
# 1    (LED点亮)
# 或
# 0    (LED熄灭)
```

### 卸载驱动

测试完成后，可以卸载驱动：

```bash
# 卸载驱动
rmmod device_tree_try_03_driver

# 查看日志
dmesg | tail

# 预期输出：
# [  234.567890] === device_tree_try_03驱动卸载成功 ===
# [  234.567891] Device: AES_LED called close!
# [  234.567892] Deinit LED Hardware
```

---

## 调试技巧：当事情不按计划进行时

说实话，即使你严格按教程操作，也可能会遇到各种问题。这一节我们总结一些常用的调试技巧，希望能帮你节省点排错时间。

### dmesg日志分析

`dmesg` 命令是你最好的朋友。它可以显示内核的环形缓冲区，包含所有内核打印的信息：

```bash
# 查看最近的内核消息
dmesg | tail -20

# 过滤特定关键词
dmesg | grep -i "led"
dmesg | grep -i "device_tree"

# 实时监控内核消息
dmesg -w
```

常见的错误信息和解决方法：

**错误1：`dtsled node can not found!`**

原因：设备树中找不到指定节点。

解决方法：
1. 检查节点路径是否正确（注意大小写和前导`/`）
2. 检查DTB文件是否正确部署
3. 在 `/proc/device-tree` 中查看节点是否存在

**错误2：`reg property read failed!`**

原因：无法读取reg属性。

解决方法：
1. 检查DTS文件中reg属性是否存在
2. 检查reg属性的格式是否正确（地址和长度的对数）
3. 使用 `hexdump -C /proc/device-tree/imx_aes_led/reg` 查看实际值

**错误3：`ioremap failed!`**

原因：内存映射失败。

解决方法：
1. 检查reg属性中的地址是否有效
2. 检查是否已经有其他驱动占用了这些地址
3. 查看内核日志中是否有其他错误信息

### 串口输出解读

如果你使用串口连接开发板，所有的内核日志都会直接输出到串口。这对于调试启动阶段的问题特别有用。

串口输出通常包含以下信息：
- U-Boot启动信息
- 内核解压和启动信息
- 设备探测信息
- 驱动加载信息
- 运行时错误信息

学会从这些信息中提取有用的内容，是嵌入式Linux工程师的基本功。

### 常见问题排查清单

当驱动不能正常工作时，按以下顺序排查：

1. **设备树是否正确加载？**
   - 检查 `/proc/device-tree` 中是否有对应节点
   - 检查节点的属性值是否正确

2. **驱动是否成功加载？**
   - 检查 `lsmod` 输出中是否有驱动模块
   - 检查 `dmesg` 日志中是否有错误信息

3. **设备文件是否创建？**
   - 检查 `/dev` 目录下是否有设备文件
   - 检查设备文件的权限是否正确

4. **硬件是否正常工作？**
   - 检查LED是否连接到正确的GPIO
   - 使用万用表或示波器测量电平变化

5. **驱动逻辑是否正确？**
   - 在驱动中添加更多的调试打印
   - 使用 `strace` 跟踪用户态程序的调用

---

## 完结撒花：你已经掌握了设备树驱动开发

到这里，我们不仅点亮了灯，更重要的是，我们点亮了Linux驱动开发的现代树。

回想一下这一章我们做了什么：我们在**描述**硬件，而不是在**编码**硬件。我们在 `.dts` 文件里写下硬件的物理地址，在驱动里通过OF函数把它们"拽"出来。

还记得我们在前言里说的那个分水岭吗？> "这一章的核心不在于'点亮灯'，而在于'通过描述硬件来点亮灯'。这是传统驱动开发和现代驱动开发的分水岭。"

现在你应该深有体会了。以前，如果你要把这个驱动移植到另一块板子上，哪怕只是改了一个GPIO引脚，你都得重新修改驱动代码，重新编译.ko文件。现在呢？你只需要修改 `.dts` 文件，改几个数字，重新编译一下设备树（几秒钟的事），把新的 `.dtb` 拷过去，**驱动代码 `.ko` 连动都不用动**。

这就是Linux内核引入设备树模型的初衷：**把"硬件描述"和"驱动逻辑"彻底解耦**。驱动只需要负责"怎么操作一个GPIO"，而设备树负责"这个GPIO在哪里"。这个分离，是构建大型、可移植嵌入式系统的基石。

当然，我们这里展示的还是最基础的使用方式。在实际的工程中，你可能会遇到更复杂的场景：中断、DMA、时钟、电源管理...这些都可以通过设备树来描述。但万变不离其宗，核心思想是一样的：**描述硬件，而不是编码硬件**。

在未来的学习中，你会接触到Platform设备驱动框架，你会发现，我们今天在这里折腾的 `device_node` 和OF函数，在Platform驱动里是如何以一种更标准、更优雅的方式被封装起来，成为驱动工程师的标准工具箱。

但那些都是后话了。现在，恭喜你完成了设备树驱动开发的完整学习！从概念理解到语法学习，从驱动开发到实战演练，你现在应该可以独立完成大部分设备树相关的开发任务了。

**完结撒花！**

---

## 附录：完整代码清单

### A. 设备树文件 (imx6ull-aes-led.dts)

```dts
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

/ {
    model = "Awesome Embedded Studio IMX6ULL Example Driver";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

    imx_aes_led {
        #address-cells = <1>;
        #size-cells = <1>;
        compatible = "atkalpha-led";
        status = "okay";
        reg = < 0X020C406C 0X04    /* CCM_CCGR1_BASE */
                0X020E0068 0X04    /* SW_MUX_GPIO1_IO03_BASE */
                0X020E02F4 0X04    /* SW_PAD_GPIO1_IO03_BASE */
                0X0209C000 0X04    /* GPIO1_DR_BASE */
                0X0209C004 0X04 >; /* GPIO1_GDIR_BASE */
    };
};
```

### B. 硬件操作头文件 (led_hw.h)

```c
#pragma once

#include <linux/types.h>

int led_hw_init(void);
void led_hw_deinit(void);
void led_set_status(bool status);
bool led_get_status(void);
```

### C. 硬件操作实现 (led_hw.c)

```c
#include "led_hw.h"
#include <asm/io.h>
#include <linux/of.h>
#include <linux/of_address.h>

struct led_handle {
    void __iomem* ccm_ccgr1;
    void __iomem* sw_mux_gpio;
    void __iomem* sw_pad_gpio;
    void __iomem* gpio_dr;
    void __iomem* gpio_gdir;
    struct device_node* device_tree_node;
};

static struct led_handle led;

int led_hw_init(void) {
    u32 regdata[10];
    int ret;
    const char* str;
    u32 val;

    led.device_tree_node = of_find_node_by_path("/imx_aes_led");
    if (led.device_tree_node == NULL) {
        pr_err("dtsled node can not found!\n");
        return -EINVAL;
    }

    led.ccm_ccgr1 = of_iomap(led.device_tree_node, 0);
    led.sw_mux_gpio = of_iomap(led.device_tree_node, 1);
    led.sw_pad_gpio = of_iomap(led.device_tree_node, 2);
    led.gpio_dr = of_iomap(led.device_tree_node, 3);
    led.gpio_gdir = of_iomap(led.device_tree_node, 4);

    val = readl(led.ccm_ccgr1);
    val &= ~(3 << 26);
    val |= (3 << 26);
    writel(val, led.ccm_ccgr1);

    writel(5, led.sw_mux_gpio);
    writel(0x10B0, led.sw_pad_gpio);

    val = readl(led.gpio_gdir);
    val |= (1 << 3);
    writel(val, led.gpio_gdir);

    val = readl(led.gpio_dr);
    val |= (1 << 3);
    writel(val, led.gpio_dr);

    return 0;
}

void led_set_status(bool status) {
    u32 val = readl(led.gpio_dr);
    if (status) {
        val &= ~(1 << 3);
    } else {
        val |= (1 << 3);
    }
    writel(val, led.gpio_dr);
}
```

---

## 下一步学习建议

恭喜你完成了设备树驱动开发的完整学习之旅！如果你想继续深入，可以探索以下方向：

- **Platform设备驱动**：学习如何使用 `platform_driver` 框架，让内核自动完成设备匹配和资源管理
- **设备树叠加**：学习如何在运行时动态修改设备树，而不需要重新编译DTB
- **复杂设备描述**：学习如何描述中断、DMA、时钟、电源管理等复杂硬件资源

但那些都是后话了。现在，先找一块开发板，把我们在这一章学到的知识实践一遍。只有在实践中，理论才能变成你自己的技能。

**相关章节：**
- [返回教程目录](./)
- [09. 板级DTS修改实操](./09_board_dts_modification.md)
