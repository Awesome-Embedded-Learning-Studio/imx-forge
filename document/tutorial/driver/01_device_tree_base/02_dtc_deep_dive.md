---
title: DTC 深入讲解
---

# 02. DTC深入讲解——从文本到二进制的魔法转换

上一章我们讲了设备树的历史背景和基本概念，现在手里应该有一个模糊的概念了：设备树是一种描述硬件的数据结构，内核通过它来了解板子上有什么设备。

但事情还没完，你可能会问：这些 `.dts` 文件是怎么变成内核能识别的二进制格式的？`make dtbs` 这条命令背后到底发生了什么？为什么有时候改个设备树会导致内核启动失败，报错信息却只有一句不知所云的 "FDT_ERR_BADSTRUCTURE"？

说实话，这些问题曾经也困扰了我很久。那时候刚开始尝试学习嵌入式Linux（嘿嘿，就是这块板子），对着厂商给的一堆 `.dts` 文件改来改去，编译出错了就瞎猫碰死耗子，改对了也不知道为什么。直到有一天我决定把 DTC 编译器的源码翻出来看了一遍，才真正理解了这背后的机制。

这一章，我们就来深入剖析 DTC（Device Tree Compiler）的工作原理，看看它是如何把我们写的文本文件转换成内核能读懂的二进制格式的。

---

## 为什么我们需要深入理解 DTC

你可能会说：不就是编译个设备树吗，`make dtbs` 一把梭，为什么还要研究原理？

这个问题问得好。在实际开发中，我们确实很少需要手动调用 DTC 工具，大部分时间都是通过内核的构建系统间接使用。但是，**理解 DTC 的工作原理能帮你解决一些棘手的问题**：

比如，你遇到过这种情况吗？改了 `.dts` 文件后编译通过，但内核启动时某个设备就是找不到。你怀疑是设备树没生效，但 DTB 文件是二进制的，怎么看里面到底有什么？这时候如果你知道 DTC 的反向编译功能，一条命令就能把 DTB 转回 DTS，对比一下就清楚问题出在哪了。

又比如，你想给某个驱动添加一个新的属性，但不确定属性名该怎么写，值该用什么格式。这时候如果能读懂 DTB 的二进制结构，就能明白内核解析设备树时的具体要求，而不是靠猜。

更重要的是，**DTC 是设备树的"编译器"**，就像 gcc 之于 C 语言。理解了编译器的工作原理，你写代码时就会更有底气，知道哪些写法是合法的，哪些会踩坑。

---

## DTC 工作原理：从源码看编译过程

DTC 的源码在内核源码树的 `scripts/dtc` 目录下。虽然我们不需要通读整个源码，但了解一下它的整体架构还是有帮助的。

打开这个目录，你会看到一堆 `.c` 和 `.h` 文件：

```
dtc-lexer.l      # 词法分析器（Lex定义）
dtc-parser.y     # 语法分析器（Yacc定义）
dtc.c            # 主程序入口
treesource.c     # 源树处理
flattree.c       # 扁平树处理（生成DTB）
livetree.c       # 活树处理（内存中的树结构）
data.c           # 数据处理
checks.c         # 语法检查
...
```

看到 `dtc-lexer.l` 和 `dtc-parser.y` 这两个文件，做过编译原理的朋友应该会心一笑。没错，DTC 就是一个典型的**词法分析 + 语法分析**的编译器前端，加上一个**代码生成**的后端。

### 词法分析：把文本切分成 Token

词法分析器的工作是把输入的字符流切分成有意义的记号（Token）。比如看到 `compatible = "fsl,imx6ull";` 这一行，词法分析器会识别出：

- `compatible`：标识符
- `=`：赋值符号
- `"fsl,imx6ull"`：字符串字面量
- `;`：语句结束符

这个任务由 `dtc-lexer.l` 完成，它使用 **Lex**（或者其开源实现 Flex）工具生成。我们不需要深入研究它的实现，只需要知道它会处理以下几种基本元素：

```c
// 节点名字符
PROPNODECHAR [a-zA-Z0-9,._+*#?@-]

// 标签（label）
LABEL [a-zA-Z_][a-zA-Z0-9_]*

// 字符串
STRING \"([^\\"]|\\.)*\"

// 数字
DT_LITERAL [0-9]+|0[xX][0-9a-fA-F]+
```

### 语法分析：构建语法树

词法分析器吐出的 Token 流会被语法分析器吃进去，构建出一棵语法树。这部分在 `dtc-parser.y` 中定义，使用 **Yacc**（或 Bison）工具生成。

语法分析器会定义 DTS 文法的各种规则，比如：

```
devicetree: '/' nodedef
    | devicetree ';' nodedef
    ;

nodedef: '{' proplist childnodes '}'    // 节点定义
    | reference ';'                     // 引用已有节点
    ;

proplist: /* 空 */
    | proplist propdef ';'              // 属性列表
    ;
```

通过这些规则，语法分析器就能把文本形式的设备树转换成内存中的树形结构。这个过程和 C 编译器把源码转换成抽象语法树（AST）是一样的道理。

### 树构建：从 AST 到 DTB

语法树构建完成后，DTC 会把它"拍扁"成一个线性的二进制格式，这就是 DTB（Device Tree Blob）。这个任务由 `flattree.c` 完成。

我们来看看这个文件里的一些关键函数。首先是一组"发射器"（emitter）的定义：

```c
static void bin_emit_cell(void *e, cell_t val)
{
    struct data *dtbuf = e;
    *dtbuf = data_append_cell(*dtbuf, val);
}

static void bin_emit_string(void *e, const char *str, int len)
{
    struct data *dtbuf = e;
    if (len == 0)
        len = strlen(str);
    *dtbuf = data_append_data(*dtbuf, str, len);
    *dtbuf = data_append_byte(*dtbuf, '\0');
}

static void bin_emit_beginnode(void *e, struct label *labels)
{
    bin_emit_cell(e, FDT_BEGIN_NODE);  // 节点开始标记
}

static void bin_emit_endnode(void *e, struct label *labels)
{
    bin_emit_cell(e, FDT_END_NODE);    // 节点结束标记
}

static void bin_emit_property(void *e, struct label *labels)
{
    bin_emit_cell(e, FDT_PROP);        // 属性标记
}
```

看到 `FDT_BEGIN_NODE`、`FDT_END_NODE`、`FDT_PROP` 这些常量了吗？这些就是 DTB 二进制格式中的"魔术数字"，用来标记不同的数据块类型。我们稍后再详细讲解它们的含义。

现在只需要知道：DTC 会遍历语法树，遇到节点开始就写入 `FDT_BEGIN_NODE`，遇到属性就写入 `FDT_PROP`，依此类推，最终生成一个线性的字节流。

---

## 文件格式详解：dts/dtsi/dtb 的区别

在设备树的生态里，你会经常看到三种文件后缀：`.dts`、`.dtsi` 和 `.dtb`。它们各有各的用途，搞清楚它们的区别是避免踩坑的第一步。

### .dts：源文件

`.dts` 是设备树源文件（Device Tree Source），就是我们用文本编辑器写的那种。它的语法我们在上一章已经讲过了，这里不再赘述。

你只需要记住：`.dts` 文件是给人看的，不是给机器看的。内核不会直接读取 `.dts` 文件，必须先编译成 `.dtb` 格式。

### .dtsi：头文件

`.dtsi` 是设备树头文件（Device Tree Source Include），作用类似于 C 语言的 `.h` 文件。它通常包含一些通用的定义，可以被多个 `.dts` 文件引用。

比如，`imx6ull.dtsi` 里面定义了 I.MX6ULL 这颗芯片的所有硬件外设：

```dts
/ {
    soc {
        uart1: serial@02020000 {
            compatible = "fsl,imx6ul-uart", "fsl,imx21-uart";
            reg = <0x02020000 0x4000>;
            status = "disabled";
        };

        i2c1: i2c@021a0000 {
            compatible = "fsl,imx6ul-i2c", "fsl,imx21-i2c";
            reg = <0x021a0000 0x4000>;
            status = "disabled";
        };
    };
};
```

这些定义是所有使用 I.MX6ULL 的板子共有的，所以被封装在 `.dtsi` 文件里。你的板级设备树只需要 `#include "imx6ull.dtsi"`，就能继承所有这些定义。

**重要提示**：永远不要直接修改 `.dtsi` 文件！这些文件通常是芯片厂商提供的，修改它们会影响所有引用这个文件的板子。正确的做法是在你的 `.dts` 文件里通过引用标签来覆盖或追加内容。

### .dtb：二进制格式

`.dtb` 是设备树二进制文件（Device Tree Blob），这是内核真正能读懂的格式。它是由 DTC 编译器从 `.dts` 文件生成的。

DTB 文件的结构是完全定义好的，我们在下一节会详细剖析。现在先来看一下它的外观。

我们可以用 `hexdump` 命令查看一个 DTB 文件的二进制内容：

```bash
$ dtc -I dts -O dtb -o /tmp/test.dtb /tmp/simple-test.dts
$ hexdump -C /tmp/test.dtb | head -20
00000000  d0 0d fe ed 00 00 01 7f  00 00 00 38 00 00 01 3c  |...........8...<|
00000010  00 00 00 28 00 00 00 11  00 00 00 10 00 00 00 00  |...(............|
00000020  00 00 00 43 00 00 01 04  00 00 00 00 00 00 00 00  |...C............|
00000030  00 00 00 00 00 00 00 00  00 00 00 01 00 00 00 00  |................|
00000040  00 00 00 03 00 00 00 11  00 00 00 00 54 65 73 74  |............Test|
00000050  20 44 65 76 69 63 65 20  54 72 65 65 00 00 00 00  | Device Tree....|
00000060  00 00 00 03 00 00 00 0c  00 00 00 06 74 65 73 74  |............test|
00000070  2c 73 69 6d 70 6c 65 00  00 00 00 03 00 00 00 04  |,simple.........|
00000080  00 00 00 11 00 00 00 01  00 00 00 03 00 00 00 04  |................|
```

看起来像一堆乱码？别急，我们接下来就教你如何"破译"这些内容。

---

## DTB 格式详解：二进制的秘密

DTB 文件的结构定义在内核源码的 `scripts/dtc/libfdt/fdt.h` 头文件里。虽然我们不需要逐字节去解析它，但了解一下整体结构还是很有帮助的。

### 整体布局

一个 DTB 文件由以下几个部分组成：

```
+------------------+
|   fdt_header     |  // 文件头（固定大小）
+------------------+
|   (reserved)     |  // 保留区域（可选）
+------------------+
|   memory reserve |  // 内存保留区域
+------------------+
|   structure block|  // 结构块（节点和属性）
+------------------+
|   strings block  |  // 字符串块（属性名等）
+------------------+
```

### 文件头（fdt_header）

文件头是一个固定大小的结构体（通常 40 字节），包含了整个 DTB 文件的元信息。它的定义如下：

```c
struct fdt_header {
    uint32_t magic;              // 魔术数字：0xd00dfeed
    uint32_t totalsize;          // 整个文件的大小
    uint32_t off_dt_struct;      // 结构块相对于文件头的偏移
    uint32_t off_dt_strings;     // 字符串块相对于文件头的偏移
    uint32_t off_mem_rsvmap;     // 内存保留区域的偏移
    uint32_t version;            // DTB 版本号（17是当前版本）
    uint32_t last_comp_version;  // 兼容的最低版本
    uint32_t boot_cpuid_phys;    // 启动 CPU 的物理 ID
    uint32_t size_dt_strings;    // 字符串块的大小
    uint32_t size_dt_struct;     // 结构块的大小
};
```

注意一个重要的细节：**DTB 使用大端序（Big Endian）**。这意味着在小端系统（比如 x86）上读取 DTB 时需要进行字节序转换。这也就是为什么你在 `dtc.h` 里会看到这些函数：

```c
static inline uint32_t dtb_ld32(const void *p)
{
    const uint8_t *bp = (const uint8_t *)p;
    return ((uint32_t)bp[0] << 24)
         | ((uint32_t)bp[1] << 16)
         | ((uint32_t)bp[2] << 8)
         | bp[3];
}
```

它手动把四个字节按大端序拼成一个 32 位整数。

让我们对照着前面的 `hexdump` 输出来理解一下文件头：

```
00000000  d0 0d fe ed 00 00 01 7f  00 00 00 38 00 00 01 3c
```

- `d0 0d fe ed`：魔术数字。等等，不是 `0xd00dfeed` 吗？怎么反过来了？哦，因为我的电脑是小端序，`hexdump` 按小端序显示了。实际上这四个字节应该是 `ed fe 0d d0`，也就是 `0xd00dfeed`。
- `00 00 01 7f`：整个文件的大小，`0x17f` = 383 字节。你可以用 `ls -lh` 验证一下。
- `00 00 00 38`：结构块的偏移，`0x38` = 56 字节。这说明结构块从文件的第 56 字节开始。
- `00 00 01 3c`：字符串块的偏移，`0x13c` = 316 字节。

### 结构块（structure block）

结构块是 DTB 的核心部分，它以一系列"标记 + 数据"的形式描述了设备树的节点和属性。每个标记都是一个 32 位的整数，表示不同的含义：

| 标记 | 值 | 含义 |
|------|-----|------|
| FDT_BEGIN_NODE | 0x00000001 | 开始一个节点 |
| FDT_END_NODE | 0x00000002 | 结束一个节点 |
| FDT_PROP | 0x00000003 | 一个属性 |
| FDT_NOP | 0x00000004 | 空操作（用于对齐） |
| FDT_END | 0x00000009 | 结束整个结构块 |

我们继续看 `hexdump` 的输出：

```
00000040  00 00 00 03 00 00 00 11  00 00 00 00 54 65 73 74
```

- `00 00 00 03`：`FDT_PROP`，表示接下来是一个属性。
- `00 00 00 11`：属性值的长度，`0x11` = 17 字节。
- `00 00 00 00`：属性名在字符串块中的偏移，0 表示字符串块的开头。
- `54 65 73 74 20 44 65 76 69 63 65 20 54 72 65 65 00`：属性值，"Test Device Tree" 加上一个结尾的 `\0`。

等等，这个属性没有名字啊？别急，名字在字符串块里。我们来看字符串块：

```
00000140  6c 00 63 6f 6d 70 61 74  69 62 6c 65 00 23 61 64
00000150  64 72 65 73 73 2d 63 65  6c 6c 73 00 23 73 69 7a
00000160  65 2d 63 65 6c 6c 73 00  64 65 76 69 63 65 5f 74
00000170  79 70 65 00 72 65 67 00  73 74 61 74 75 73 00
```

- 开头的 `model` 就是刚才那个属性的名字。
- 后面跟着 `compatible`、`#address-cells`、`#size-cells` 等等，都是各个属性的名字。

这种设计的好处是可以节省空间：如果多个属性有相同的名字（比如多个节点都有 `compatible` 属性），名字只需要在字符串块里存一次。

---

## 编译流程：make dtbs 背后发生了什么

现在我们了解了 DTC 的工作原理和 DTB 的文件格式，接下来看看内核的构建系统是如何组织整个编译流程的。

当你执行 `make dtbs` 时，内核的构建系统会做以下几件事：

### 1. 确定要编译哪些 DTS 文件

内核的设备树文件存放在 `arch/arm/boot/dts`（或 `arch/arm64/boot/dts`）目录下。但并不是所有的 DTS 文件都会被编译，这取决于你的内核配置。

打开 `arch/arm/boot/dts/Makefile`，你会看到类似这样的内容：

```makefile
dtb-$(CONFIG_SOC_IMX6Q) += \
    imx6dl-sabrelite.dtb \
    imx6q-sabrelite.dtb \
    imx6qp-sabreauto.dtb \
    ...

dtb-$(CONFIG_SOC_IMX6UL) += \
    imx6ul-14x14-evk.dtb \
    imx6ul-9x9-evk.dtb \
    ...
```

这里的 `dtb-$(CONFIG_SOC_IMX6Q)` 表示：只有当内核配置中启用了 `CONFIG_SOC_IMX6Q` 时，才会编译这些 DTB 文件。

这种机制的好处是：你不需要手动指定要编译哪个 DTS，只需要在内核配置里选择你的 SOC 型号，构建系统就会自动找到对应的设备树文件。

### 2. 调用 DTC 编译器

构建系统会为每个 DTS 文件生成一条编译命令，类似于：

```bash
dtc -I dts -O dtb -o imx6ull-14x14-evk.dtb imx6ull-14x14-evk.dts
```

这里 `dtc` 命令的选项含义是：

- `-I dts`：输入格式是 DTS 源文件
- `-O dtb`：输出格式是 DTB 二进制文件
- `-o imx6ull-14x14-evk.dtb`：指定输出文件名

实际上，内核构建系统会传递更多的选项，比如：

- `-i`：指定 include 路径，这样 `#include` 指令才能找到 `.dtsi` 文件
- `-@`：生成符号信息，用于设备树叠加（Device Tree Overlay）
- `-Wno-unit_address_format`：忽略某些警告

### 3. 安装 DTB 文件

编译完成后，DTB 文件会被复制到内核的安装目录（通常是 `/boot`），或者被打包进 initramfs 里。

U-Boot 在启动内核时，会读取这个 DTB 文件，把它加载到内存中，然后通过寄存器把 DTB 的地址传递给内核。

---

## DTC 工具链：dtc 命令详解

虽然我们平时很少直接调用 `dtc` 命令，但掌握它的用法还是很有用的，特别是在调试设备树问题的时候。

### 基本用法

```bash
dtc [选项] <输入文件>
```

最常用的选项包括：

| 选项 | 含义 |
|------|------|
| `-I <格式>` | 输入格式（dts、dtb、fs） |
| `-O <格式>` | 输出格式（dts、dtb、yaml） |
| `-o <文件>` | 输出文件名 |
| `-i <路径>` | 添加 include 路径 |
| `-@` | 生成符号信息 |
| `-s` | 排序节点和属性 |
| `-H <格式>` | phandle 格式 |

### 实战：手动编译一个 DTS 文件

假设你有这样一个简单的 DTS 文件：

```dts
/dts-v1/;

/ {
    model = "Test Device Tree";
    compatible = "test,simple";

    #address-cells = <1>;
    #size-cells = <1>;

    memory@80000000 {
        device_type = "memory";
        reg = <0x80000000 0x20000000>;
    };

    uart@2020000 {
        compatible = "fsl,imx6ul-uart";
        reg = <0x2020000 0x4000>;
        status = "okay";
    };
};
```

你可以这样编译它：

```bash
$ dtc -I dts -O dtb -o test.dtb test.dts
```

如果你想验证编译结果，可以把它反向编译回 DTS：

```bash
$ dtc -I dtb -O dts test.dtb
```

输出结果应该和原来的 DTS 文件类似（可能会有一些格式差异，比如数字变成十六进制）。

### 调试技巧：DTB 转 DTS

当你怀疑 DTB 文件有问题时，把它转回 DTS 格式是最直接的调试方法。你可以对比转回的 DTS 和你写的 DTS，看看哪里不一样。

```bash
$ dtc -I dtb -O dts /boot/imx6ull-14x14-evk.dtb > current.dts
$ diff current.dts arch/arm/boot/dts/imx6ull-14x14-evk.dts
```

这个方法在排查设备树问题时非常有效，强烈建议掌握。

---

## 常见问题与调试技巧

在实际开发中，我们经常会遇到一些和 DTC 相关的问题。这里总结几个常见的坑和对应的解决方案。

### 问题1：编译时报 "syntax error"

如果你看到这样的错误：

```
Error: test.dts:10.1-9 syntax error
FATAL ERROR: Unable to parse input tree
```

首先检查语法是否正确。DTS 的语法虽然简单，但也有一些容易犯错的地方：

- 节点和属性的定义要用大括号 `{}` 包裹
- 每个属性定义要以分号 `;` 结尾
- 字符串要用双引号 `"` 包裹
- 数值要用尖括号 `<>` 包裹

如果你不确定哪里写错了，可以用 `dtc -fs` 选项来获得更详细的错误信息。

### 问题2：include 文件找不到

```
Error: test.dts:2:10: Fatal error: 'imx6ull.dtsi' file not found
```

这是因为 DTC 不知道去哪里找 include 文件。你需要用 `-i` 选项指定搜索路径：

```bash
dtc -I dts -O dtb -i arch/arm/boot/dts -o test.dtb test.dts
```

或者，你可以设置环境变量：

```bash
export DTC_INCLUDE_PATH=arch/arm/boot/dts
```

### 问题3：DTB 文件损坏或版本不匹配

有时候你会遇到内核启动失败，提示 DTB 文件有问题。这可能是 DTB 的版本和内核不兼容，或者文件在传输过程中损坏了。

你可以用 `dtc` 来检查 DTB 的完整性：

```bash
$ dtc -I dtb -O dts test.dtb
```

如果 DTB 文件有问题，这个命令会报错。如果成功输出 DTS，说明文件本身是完整的。

另外，你可以检查 DTB 的版本信息：

```bash
$ fdtdump test.dtb
```

`fdtdump` 是另一个有用的工具，它会以可读的形式打印出 DTB 的结构，包括版本号、各块的偏移等等。

---

## 小结

这一章我们深入剖析了 DTC 的工作原理，从词法分析到语法分析，再到二进制格式生成，完整地走了一遍设备树的编译流程。

我们了解到：

- DTC 是一个典型的编译器，由词法分析、语法分析和代码生成三部分组成
- `.dts`、`.dtsi`、`.dtb` 三种文件格式各有用途，不能混淆
- DTB 文件有固定的结构，包括文件头、结构块和字符串块
- `make dtbs` 背后是内核构建系统在调用 DTC 编译器
- `dtc` 命令不仅可以编译 DTS，还可以反向编译 DTB，这是调试的利器

掌握了这些知识，你在处理设备树问题时就不再是"瞎猫碰死耗子"，而是能够有的放矢地定位和解决问题了。

下一章，我们将讲解如何在驱动程序中读取和使用设备树的信息，把理论知识应用到实际开发中。

---

## 下一步

- [03. 设备树语法详解](./03_device_tree_syntax.md)：讲解设备树的语法规则和节点属性。
- [返回目录](./)：查看所有章节。
