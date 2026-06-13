---
title: 板级 DTS 修改实操
---

# 09. 板级DTS修改实操——终于要动手改自己的板子了

## 前言：从理论到实践的跨越

跟着我们的教程一路走过来，到现在你应该对设备树有了相当全面的了解：知道它是什么、为什么需要它、语法怎么写、驱动怎么用。但说实话，这些知识如果不动手，永远只是"纸上谈兵"。

很多朋友在这个阶段会遇到一个尴尬的问题：教程里的示例都跑通了，但面对自己手里的开发板，却不知道从哪里下手。厂商给的设备树文件一大堆，动辄几千行，看着就头皮发麻。我想添加一个LED设备节点，应该改哪个文件？编译出来的DTB怎么放到板子上？怎么验证改动的设备树真的生效了？

这些问题，我们在这一章里全部解决。我们会手把手地带着你走完整个流程：从确认板级DTS位置，到添加设备节点，到编译部署，再到验证生效。这不是什么高深的技术，但确实是每个嵌入式Linux工程师都必须掌握的基本功。

说实话，这一章的内容偏向"操作指南"，理论性不多，但实用性极强。如果你能跟着我们的步骤完整操作一遍，以后再遇到设备树移植的问题，基本上就能自己解决了。

---

## 环境准备：先搞清楚我们在改什么

在我们动手改任何东西之前，最重要的一步是搞清楚"我们要改什么"。这听起来像是废话，但很多人踩坑就是因为没搞清楚自己的开发板型号，或者改错了设备树文件。

### 确认开发板型号

首先，你需要确认你手里的开发板到底是什么型号。这个信息通常可以在以下地方找到：

- 开发板包装盒或说明书
- 开发板上的丝印型号
- 采购订单或产品页面
- 串口启动信息

最后一种方法是最可靠的。当你启动开发板时，串口会输出大量信息，其中往往包含板子型号。比如你会看到类似这样的输出：

```
Model: Freescale i.MX6 UltraLite 14x14 EVK Board
```

或者：

```
Machine: ALIENTEK ATK-IMX6ULL
```

这些信息告诉我们当前板子的型号，以及对应的设备树文件名称。

### 找到板级DTS文件位置

确认了板子型号之后，下一步就是找到对应的DTS文件。这个文件的位置取决于你的项目结构。

在我们的imx-forge项目中，设备树文件存放在 `driver/device_tree/alpha-board/` 目录下。如果你使用的是NXP官方的BSP，那么设备树文件通常在内核源码的 `arch/arm/boot/dts/` 目录下。

让我们来看看一个典型的设备树目录结构：

```
arch/arm/boot/dts/
├── imx6ull.dtsi              # SOC级通用定义
├── imx6ull-14x14-evk.dts     # 官方EVK板级文件
├── imx6ull-14x14-evk.dtb     # 编译后的二进制文件
├── imx6ull-atk.dts           # 正点原子板级文件
└── ...
```

请注意这里的三种文件：
- `.dtsi` 文件：SOC级或模块级的通用定义，类似于C语言头文件
- `.dts` 文件：具体的板级定义，包含这块板子特有的硬件配置
- `.dtb` 文件：编译后的二进制设备树，这才是内核真正读取的文件

**重要原则：永远不要直接修改 `.dtsi` 文件！** 这些文件是公用的，修改它们会影响所有引用这个文件的板子。正确的做法是在你的 `.dts` 文件里通过引用标签来修改或追加内容。

### 备份原有DTS文件

在修改任何文件之前，养成备份的习惯是非常重要的。虽然理论上你可以通过git来回退，但当你改错了导致系统起不来时，一个现成的备份文件能让你快速恢复。

```bash
# 进入设备树目录
cd driver/device_tree/alpha-board/

# 备份原始文件
cp imx6ull-aes-led.dts imx6ull-aes-led.dts.bak
```

或者，如果你使用的是git：

```bash
# 查看当前状态
git status

# 如果文件已经被修改，可以先暂存
git stash save "修改前的备份"

# 或者创建一个新的分支来实验
git checkout -b experiment/device-tree-modification
```

这些操作看起来繁琐，但当你在深夜踩坑时，会感谢自己做了备份。

---

## 添加设备节点：一步步操作

现在我们进入正题：如何在板级DTS中添加一个设备节点。我们以添加一个LED设备为例，因为这个设备足够简单，但又涵盖了设备树修改的核心步骤。

### 确定节点位置

首先需要确定：你添加的设备节点应该放在哪里？这取决于设备的类型和连接方式。

如果设备是挂在SOC内部总线上的（比如我们直接操作GPIO寄存器来控制LED），那么节点通常直接放在根节点 `/` 下面。如果设备是挂在外部总线上的（比如I2C设备、SPI设备），那么节点应该放在对应的总线节点下面。

我们来看一个实际的例子。这是Alpha开发板的LED设备树文件：

```dts
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

/ {
    model = "Awesome Embedded Studio IMX6ULL Example Driver";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

    /*
     * PS 下，可以看到我们在/下追加了一个新的LED节点
     * 这个节点描述了LED驱动需要的所有寄存器地址
     */
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

请注意这里的节点名称 `imx_aes_led`。它直接挂在根节点下面，所以它的完整路径是 `/imx_aes_led`。如果你在驱动代码里通过路径查找这个节点，就需要使用这个完整路径。

### 编写节点内容

一个设备节点需要包含哪些内容？这取决于你的驱动需要什么信息。但对于大多数简单的设备来说，以下几个属性是必需的：

**1. compatible 属性**

这是驱动匹配的关键属性，驱动代码里会有一个匹配表：

```c
static const struct of_device_id led_of_match[] = {
    { .compatible = "atkalpha-led", },
    { /* sentinel */ }
};
```

只要设备树里的 `compatible` 值包含 `"atkalpha-led"`，这个驱动就会被绑定到这个设备上。

**2. status 属性**

这个属性决定了设备是否启用：
- `"okay"`：设备可操作
- `"disabled"`：设备禁用
- `"fail"` 或 `"fail-sss"`：设备检测到错误

**3. reg 属性**

`reg` 属性描述了设备所需的寄存器地址。它的格式由父节点的 `#address-cells` 和 `#size-cells` 决定。在我们的例子中，根节点设置了：

```dts
#address-cells = <1>;
#size-cells = <1>;
```

这意味着子节点的 `reg` 属性中，地址和长度各占一个32位整数。所以我们的 `reg` 属性写成：

```dts
reg = < 0X020C406C 0X04    /* 地址1 长度1 */
        0X020E0068 0X04    /* 地址2 长度2 */
        ... >;
```

每个地址对应一个物理寄存器，长度通常是4字节（32位）。

**4. 其他自定义属性**

除了标准属性，你还可以添加任何自定义属性，然后在驱动里通过OF API读取。比如：

```dts
gpio = <&gpio1 3 GPIO_ACTIVE_LOW>;
default-state = "on";
```

这些属性没有标准含义，完全由你的驱动来解释。

### 修改现有节点

有时候你不需要添加新节点，而是需要修改现有的节点。比如你想启用I2C1并在它下面挂一个设备：

```dts
&i2c1 {
    clock-frequency = <100000>;
    status = "okay";  // 覆盖原来的 "disabled"

    mag3110@0e {
        compatible = "fsl,mag3110";
        reg = <0x0e>;
    };
};
```

请注意这里的语法：`&i2c1` 是一个节点引用，它指向在 `.dtsi` 文件里定义的 `i2c1` 节点。通过这种方式，你可以在不修改原始文件的情况下，修改或追加节点内容。

---

## 编译流程：从DTS到DTB

写好了DTS文件，下一步就是把它编译成DTB格式。内核只能读取二进制的DTB文件，不能直接读取DTS文本文件。

### 使用DTC命令手动编译

最直接的方式是使用DTC（Device Tree Compiler）命令：

```bash
# 基本编译命令
dtc -I dts -O dtb -o output.dtb input.dts

# 带include路径的编译
dtc -I dts -O dtb -i arch/arm/boot/dts -o output.dtb input.dts

# 生成符号信息（用于设备树叠加）
dtc -I dts -O dtb -@ -o output.dtb input.dts
```

这里的选项含义是：
- `-I dts`：输入格式是DTS源文件
- `-O dtb`：输出格式是DTB二进制文件
- `-o output.dtb`：指定输出文件名
- `-i path`：添加include搜索路径
- `-@`：生成符号信息

### 使用build_driver.sh脚本

在我们的imx-forge项目中，我们提供了更方便的构建脚本。你不需要记住复杂的DTC命令，只需要运行：

```bash
# 进入项目根目录
cd /home/charliechen/imx-forge

# 构建指定驱动（会自动编译设备树）
./scripts/driver_helper/build_driver.sh led alpha-board
```

这个脚本会自动完成以下工作：
1. 查找驱动的源码和设备树文件
2. 编译驱动代码生成.ko文件
3. 编译设备树文件生成.dtb文件
4. 把所有产物放到 `out/driver_artifacts/<驱动>/<板卡>/` 目录

### 检查编译结果

编译完成后，你应该检查一下产物是否正确生成：

```bash
# 查看产物目录
ls -lh out/driver_artifacts/led/alpha-board/

# 预期输出：
# imx6ull-aes-led.dtb
# led.ko
```

如果只看到了 `.ko` 文件但没有 `.dtb` 文件，说明设备树编译失败了。这时候你需要检查：
1. DTS文件语法是否正确
2. include的 `.dtsi` 文件是否存在
3. DTC编译器是否正确安装

### 反编译验证

如果你怀疑编译出来的DTB有问题，可以把它反编译回DTS格式进行对比：

```bash
# 反编译DTB
dtc -I dtb -O dts -o test_from_dtb.dts imx6ull-aes-led.dtb

# 对比原始DTS和反编译的DTS
diff imx6ull-aes-led.dts test_from_dtb.dts
```

反编译的DTS可能和原始DTS在格式上有些差异（比如数字的进制、空格的多少），但节点结构和属性值应该是一致的。如果发现不一致，说明DTC在编译时做了某些转换或报错了。

---

## 部署方法：把DTB放到板子上

编译出DTB文件之后，下一步就是把它部署到开发板上。这一步看似简单，但新手经常在这里卡住，因为不同的启动方式对应的部署方法不同。

### 方法一：通过TFTP部署（推荐）

如果你的开发板使用TFTP启动（这是最常见的方式），DTB文件通常存放在TFTP服务器的根目录下。

```bash
# 使用deploy_driver.sh脚本部署
./scripts/driver_helper/deploy_driver.sh led alpha-board --target=tftp

# 或者手动拷贝
sudo cp out/driver_artifacts/led/alpha-board/imx6ull-aes-led.dtb /srv/tftp/imx6ull-aes.dtb
```

请注意这里的一个细节：目标文件名是 `imx6ull-aes.dtb`，而不是 `imx6ull-aes-led.dtb`。这是因为U-Boot在启动时会加载一个固定名字的DTB文件，这个名字在U-Boot环境变量里定义：

```
bootargs=console=ttymxc0,115200 root=/dev/nfs ...
tftp_boot=bootm 0x80800000 - 0x83000000
```

最后的 `0x83000000` 就是DTB的加载地址，而文件名则由 `fdt_file` 环境变量指定：

```
fdt_file=imx6ull-aes.dtb
```

如果你不确定自己的板子使用哪个DTB文件名，可以在U-Boot命令行输入 `printenv` 查看所有环境变量。

### 方法二：通过NFS部署

如果你的rootfs挂载在NFS上，你可以直接把DTB文件拷贝到NFS目录：

```bash
# 使用deploy_driver.sh脚本部署
./scripts/driver_helper/deploy_driver.sh led alpha-board --target=nfs

# 或者手动拷贝
cp out/driver_artifacts/led/alpha-board/imx6ull-aes-led.dtb /path/to/nfs/root/boot/
```

但请注意：通过NFS部署的DTB文件不会立即生效，因为U-Boot在加载内核之前就已经从TFTP读取了DTB。要让NFS上的DTB生效，你需要修改U-Boot的启动命令，让它从NFS加载DTB而不是从TFTP。

### 方法三：直接烧写到eMMC/SD卡

如果你想让DTB持久化存储在板子上，可以直接烧写到eMMC或SD卡：

```bash
# 确定DTB分区
sudo fdisk -l /dev/sdX

# 拷贝DTB文件到挂载点
sudo mount /dev/sdX1 /mnt
sudo cp imx6ull-aes-led.dtb /mnt/imx6ull-aes.dtb
sudo umount /mnt
```

这种方法适用于生产环境，但开发阶段不太推荐，因为频繁烧写会缩短Flash寿命。

### 部署脚本详解

我们的 `deploy_driver.sh` 脚本提供了一个统一的部署接口，它会根据你选择的目标类型（TFTP、NFS、本地、远程）执行相应的操作。

脚本的核心逻辑是：

```bash
# 部署到TFTP
deploy_tftp() {
    local src="$1"
    local dst="$2"

    log_info "部署到TFTP: $dst"
    mkdir -p "$dst" || return 1

    # 只拷贝设备树文件，不拷贝.ko文件
    for file in "$src"/*.dtb; do
        if [[ -f "$file" ]]; then
            # 备份旧文件
            if [[ -f "$dst/imx6ull-aes.dtb" ]]; then
                mv "$dst/imx6ull-aes.dtb" "$dst/imx6ull-aes-$(date +%Y%m%d%H%M%S).dtb.bak"
            fi

            # 拷贝新文件
            cp "$file" "$dst/imx6ull-aes.dtb"
        fi
    done
}
```

请注意这里的一个安全措施：在覆盖旧文件之前先备份。这样当你发现新的DTB有问题时，可以快速回退到旧版本。

---

## 验证方法：确认改动生效

部署完DTB文件之后，最重要的是验证它真的生效了。很多新手改完设备树却发现驱动还是不起作用，排查半天才发现DTB根本没加载正确。

### 方法一：通过/proc/device-tree查看

Linux内核把设备树映射到了 `/proc/device-tree` 目录，你可以通过这个目录查看运行时的设备树：

```bash
# 在开发板上执行
ls /proc/device-tree/

# 查看你的设备节点是否存在
ls /proc/device-tree/imx_aes_led/

# 查看节点的属性
cat /proc/device-tree/imx_aes_led/compatible
# 输出：atkalpha-led

cat /proc/device-tree/imx_aes_led/status
# 输出：okay

hexdump -C /proc/device-tree/imx_aes_led/reg
# 输出寄存器地址列表
```

如果你的节点不存在，说明DTB文件没有正确加载或者节点路径写错了。如果节点存在但属性值不对，说明DTS文件里的属性定义有问题。

### 方法二：通过dmesg日志分析

当你加载驱动模块时，内核会打印大量日志信息。通过分析这些日志，你可以判断设备树是否正确：

```bash
# 加载驱动
insmod led.ko

# 查看内核日志
dmesg | tail -20

# 预期输出：
# [12345.678901] dtsled node has been found!
# [12345.678902] compatible = atkalpha-led
# [12345.678903] status = okay
# [12345.678904] reg data: 20C406C 4 20E0068 4 ...
```

如果你看到 "dtsled node can not found!"，说明节点路径不对或者DTB没有加载。如果你看到 "ioremap failed!"，说明 `reg` 属性里的地址有问题。

### 方法三：使用show_device_tree.sh脚本

我们的项目提供了一个设备树可视化脚本，可以在部署前预览设备树内容：

```bash
# 查看DTB文件的节点结构
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/led/alpha-board/imx6ull-aes-led.dtb

# 查看完整DTS内容
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/led/alpha-board/imx6ull-aes-led.dtb --all

# 搜索特定节点
./scripts/driver_helper/show_device_tree.sh out/driver_artifacts/led/alpha-board/imx6ull-aes-led.dtb --search "imx_aes_led"
```

这个脚本会美化显示设备树的节点结构，高亮显示 `compatible` 和 `status` 等重要属性，非常适合快速检查设备树内容。

### 验证驱动功能

最后，当然是验证驱动本身的功能是否正常：

```bash
# 加载驱动
insmod led.ko

# 检查设备文件是否创建
ls -l /dev/dtsled

# 测试LED控制
echo 1 > /dev/dtsled  # 点亮LED
echo 0 > /dev/dtsled  # 熄灭LED

# 卸载驱动
rmmod led
```

如果LED能正常点亮和熄灭，说明整个流程——从设备树修改到驱动编写——都成功了。

---

## 常见问题：我踩过的坑

在设备树开发的过程中，有些坑几乎是每个人都会踩的。这里总结几个最常见的问题，希望能帮你节省点调试时间。

### 问题1：地址冲突

**症状**：驱动加载成功，但操作寄存器时系统崩溃或行为异常。

**原因**：你在设备树里定义的寄存器地址和其他设备冲突了。

**解决方法**：
1. 查阅芯片手册，确认寄存器地址的正确性
2. 检查其他设备树节点，确保没有地址重叠
3. 使用 `hexdump -C /proc/device-tree/*/reg` 查看所有设备的地址分配

### 问题2：语法错误

**症状**：DTC编译时报错，比如 "syntax error"、"Expected }" 等。

**原因**：DTS文件语法错误，常见的包括：
- 忘记分号
- 花括号不匹配
- 字符串没有用双引号包裹
- 数值没有用尖括号包裹

**解决方法**：
1. 仔细检查报错行及其上下文
2. 使用 `dtc -I dts -O dtb -fs file.dts` 获得更详细的错误信息
3. 使用文本编辑器的语法高亮和括号匹配功能

### 问题3：节点重复

**症状**：编译通过，但内核启动时报 "Duplicate node" 错误。

**原因**：你在 `.dts` 文件里定义了一个节点，但这个节点在 `.dtsi` 文件里已经存在了。

**解决方法**：
1. 不要定义新节点，而是通过 `&label` 引用现有节点
2. 或者使用 `/delete-node/` 指令删除现有节点：
   ```dts
   /delete-node/ &uart1;
   ```

### 问题4：编译失败但找不到原因

**症状**：DTC报错信息非常模糊，比如 "FDT_ERR_BADSTRUCTURE"。

**原因**：可能是include路径不对，或者 `.dtsi` 文件有语法错误。

**解决方法**：
1. 检查所有 `#include` 指令，确保文件存在
2. 使用 `-i` 选项指定include路径
3. 单独编译被include的 `.dtsi` 文件，确认它们没有语法错误

### 问题5：DTB部署后不生效

**症状**：你确信DTB文件部署成功了，但驱动还是找不到节点。

**原因**：可能是U-Boot加载的不是你部署的DTB文件，或者内核启动参数指定了错误的DTB路径。

**解决方法**：
1. 在U-Boot命令行执行 `printenv fdt_file`，确认加载的DTB文件名
2. 检查TFTP目录下是否有同名的旧文件
3. 在U-Boot里手动加载DTB并启动：
   ```
   tftp 0x83000000 imx6ull-aes.dtb
   bootm 0x80800000 - 0x83000000
   ```

---

## 小结

这一章我们完成了从理论到实践的跨越，手把手地走了整个板级DTS修改的流程。我们了解到：

- 确认开发板型号和找到对应的DTS文件是第一步
- 添加设备节点需要考虑节点位置、compatible属性、status属性和reg属性
- 编译DTS可以使用DTC命令或build_driver.sh脚本
- 部署DTB可以通过TFTP、NFS或直接烧写Flash
- 验证设备树生效可以通过/proc/device-tree、dmesg日志和功能测试
- 常见问题包括地址冲突、语法错误、节点重复、编译失败和部署不生效

说实话，设备树开发这东西，光看教程是学不会的。你必须亲自改文件、编译、部署、测试，在这个过程中踩坑、填坑，才能真正理解。所以我们这一章的风格是：少讲理论，多写命令，遇到问题就解决问题。

等你完整走过一遍这个流程，你会发现设备树其实没那么可怕。它只是一种描述硬件的方式，只要掌握了基本的语法和工具链，剩下的就是积累经验了。

---

## 下一步

恭喜你，到这里你已经掌握了设备树开发的完整流程！从概念理解到语法学习，从驱动开发到板级修改，你现在应该可以独立完成大部分设备树相关的开发任务了。

如果你想继续深入学习，可以探索以下方向：

- **平台设备驱动**：学习如何使用 `platform_driver` 框架，让内核自动完成设备匹配和资源管理
- **设备树叠加**：学习如何在运行时动态修改设备树，而不需要重新编译DTB
- **复杂设备描述**：学习如何描述中断、DMA、时钟、电源管理等复杂硬件资源

但那些都是后话了。现在，先找一块开发板，把我们在这一章学到的知识实践一遍。只有在实践中，理论才能变成你自己的技能。

**继续阅读：** [返回教程目录](./) 查看所有章节，或者直接跳到 [10. 完整实战演练](./10_complete_practice.md) 了解更现代的驱动开发方式。
