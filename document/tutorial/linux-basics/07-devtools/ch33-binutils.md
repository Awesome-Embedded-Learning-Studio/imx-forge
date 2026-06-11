# 第 33 章  二进制工具箱

> **Part 7 · 开发工具链**

---

## 引子

你编译出来了一个可执行文件。它到底对不对？

符号表里有没有你定义的函数？链接的库对不对？段布局是什么样子？

你不能用文本编辑器打开一个 ELF 文件——它是二进制的，打开全是乱码。你需要专门的工具来「读」它。

`readelf` 读 ELF 头和段表，`objdump` 反汇编，`nm` 列符号，`strip` 瘦身，`size` 看各段大小——这套 binutils 工具箱，是你在编译和调试之间搭的那座桥。编译说成功了，但真的成功了吗？得用工具自己查。

这里有一个嵌入式开发中几乎每个人都会遇到的问题：你用交叉编译器编了一个程序，拷到板子上运行，报 `Exec format error`。为什么？因为编译的架构不对。但你怎么确认编译出来的文件到底是什么架构？`readelf -h` 一看就知道。

---

## 背景与动机

在第 31 章里，我们学了 GCC 的编译流程：预处理 → 编译 → 汇编 → 链接。最终产物是一个可执行文件。在 Linux 上，这个文件几乎一定是 ELF 格式（Executable and Linkable Format）。

编译器说 `Build finished successfully`——但它只告诉你编译过程没出错，不告诉你最终产物长什么样。如果你的链接脚本写错了，段地址不对；如果你的编译选项少了某个宏，代码路径跟你预期的不一样；如果你的交叉编译器选错了，生成的是 x86 指令而不是 ARM 指令——编译器都不会报错，但程序跑不了。

binutils 就是用来查这些问题的。它不能帮你写代码，但它能让你「看见」编译产物内部到底装了什么。对于嵌入式开发来说，这套工具尤其重要——你没法在板子上随便装软件，很多时候只能在开发机上通过静态分析来判断二进制文件是否正确。

---

## 概念层

### ELF 格式简介

在学工具之前，需要先理解 ELF 文件的基本结构。你可以把 ELF 文件想象成一本**精装书**。封面是 ELF 头（Header），告诉你书名（文件类型）、语言（架构）、出版社（操作系统）；目录是段表（Section Header），列出每一章（section）的标题和页码；正文是一个个 section——`.text` 放代码，`.data` 放已初始化的全局变量，`.bss` 放未初始化的变量。

但这个类比有一个地方是错的。真正的书从头读到尾就行了，ELF 文件不是这样的。操作系统加载 ELF 文件时，看的是**程序头（Program Header）**——它定义的是「哪些内容需要加载到内存里、加载到哪个地址」，而不是按 section 一个个读。程序头是给加载器看的，段表是给链接器和调试工具看的。同一本「书」，有两种「目录」，服务于两种读者。

ELF 文件的三种核心结构：

| 结构 | 命令 | 作用 |
|---|---|---|
| ELF 头（Header） | `readelf -h` | 文件类型、架构、入口地址 |
| 段表（Section Header） | `readelf -S` | 各 section 的名称、类型、大小、偏移 |
| 程序头（Program Header） | `readelf -l` | 加载到内存的段（segment）信息 |

常见的 section：

| Section | 内容 |
|---|---|
| `.text` | 编译后的机器指令（代码段） |
| `.data` | 已初始化的全局/静态变量 |
| `.bss` | 未初始化的全局/静态变量（不占文件空间，运行时分配） |
| `.rodata` | 只读数据（字符串常量等） |
| `.symtab` | 符号表（函数名、变量名到地址的映射） |
| `.strtab` | 字符串表（符号名等字符串） |

### readelf：读取 ELF 文件信息

`readelf` 是专门分析 ELF 格式的工具。它只能读 ELF 文件，不支持其他格式——但正因为专一，它输出的信息比 `objdump` 更全面、更结构化。

**ELF 头（`readelf -h`）**：回答「这个文件是什么」：

```bash
$ readelf -h ./myapp
```

```
ELF Header:
  Class:                             ELF64
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  Type:                              DYN (Position-Independent Executable)
  Machine:                           Advanced Micro Devices X86-64
  Entry point address:               0x1060
  ...
```

关键字段：
- **Machine**：目标架构。如果这里是 `ARM` 而不是 `X86-64`，说明这是 ARM 程序，不能在 x86 上直接运行。
- **Type**：文件类型。`DYN` 是动态链接的可执行文件，`REL` 是可重定位文件（`.o` 目标文件），`EXEC` 是静态链接的可执行文件。

**段表（`readelf -S`）**：回答「文件里有哪些 section」：

```bash
$ readelf -S ./myapp
```

```
Section Headers:
  [Nr] Name              Type             Address          Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  0000
       0000000000000000  0000000000000000           0     0     0
  [13] .text             PROGBITS         0000000000001050  1050
       00000000000001b5  0000000000000000  AX       0     0     1
  [23] .data             PROGBITS         0000000000004000  3000
       0000000000000010  0000000000000000  WA       0     0     8
```

Flags 列的 `A` 表示 Alloc（需要加载到内存），`X` 表示 Executable（可执行），`W` 表示 Writable（可写）。`.text` 有 `AX`（需要加载且可执行），`.data` 有 `WA`（需要加载且可写）——这和它们的用途完全对应。

**程序头（`readelf -l`）**：回答「操作系统怎么加载这个文件」：

```bash
$ readelf -l ./myapp
```

输出显示的是一个或多个 segment（加载段），每个 segment 由一个或多个 section 组成。操作系统只看 segment，不看 section。

### objdump：反汇编与信息查看

`objdump` 是一个更通用的工具——它支持多种二进制格式（不只是 ELF），能反汇编、显示 section 内容、显示重定位信息等。

**反汇编（`objdump -d`）**：把机器码翻译成汇编指令：

```bash
$ objdump -d ./myapp | head -30
```

```
0000000000001060 <main>:
    1060:	f3 0f 1e fa          	endbr64
    1064:	55                   	push   %rbp
    1065:	48 89 e5             	mov    %rsp,%rbp
    1068:	48 83 ec 10          	sub    $0x10,%rsp
    106c:	89 7d fc             	mov    %edi,-0x4(%rbp)
    ...
```

左列是地址，中间是机器码，右列是汇编指令。对于大多数嵌入式开发者来说，不需要能写汇编——但需要能「读」反汇编输出，确认编译器生成了你预期的指令。

加上 `-S` 选项可以混排源代码和汇编（需要编译时加了 `-g`）：

```bash
$ objdump -d -S ./myapp
```

**`readelf` 和 `objdump` 的功能有重叠**——比如两者都能显示 section 信息。区别在于：`readelf` 只支持 ELF 格式，输出更结构化，适合脚本解析；`objdump` 支持更多格式（a.out、COFF 等），输出更偏人类阅读，反汇编功能是它的强项。日常使用中，查结构信息用 `readelf`，看反汇编用 `objdump`，这条分工就够了。

### nm：符号表查看

`nm` 列出目标文件或可执行文件中的符号（函数名、全局变量名）及其地址：

```bash
$ nm ./myapp
```

```
0000000000004000 D __data_start
0000000000001060 T main
                 U printf@@GLIBC_2.2.5
0000000000004010 D my_global_var
```

符号类型字母的含义：
- `T`（Text）：代码段中的全局符号（函数）
- `D`（Data）：数据段中的全局符号（已初始化变量）
- `B`（BSS）：BSS 段中的符号（未初始化变量）
- `U`（Undefined）：未定义符号——需要动态链接库提供

`U printf@@GLIBC_2.2.5` 表示 `printf` 这个函数在文件里找不到定义，需要 libc.so 在运行时提供。如果某个你定义的函数在这里显示为 `U`，说明链接阶段出了问题——要么忘了编译对应的 `.c` 文件，要么库的路径不对。

### strip：给二进制文件瘦身

`strip` 删除可执行文件中的符号表和调试信息，减小文件体积：

```bash
# 先看看原始大小
$ ls -lh ./myapp
-rwxr-xr-x 1 charlie charlie 16K Jun 11 12:00 ./myapp

# 瘦身
$ strip ./myapp

# 再看大小
$ ls -lh ./myapp
-rwxr-xr-x 1 charlie charlie 6.2K Jun 11 12:00 ./myapp
```

体积从 16K 缩到 6.2K——删掉的是 `.symtab` 和 `.debug_*` section。程序的功能不受影响，它照样能正常运行。但如果你之后想用 GDB 调试这个文件，就看不到函数名和变量名了——只剩地址和汇编。

所以正确的做法是：**保留一份未 strip 的文件用于调试，发布时 strip 一份用于部署。** 不要直接在原文件上操作。

`strip` 有两种粒度，区别主要在**目标文件（`.o`）**上：

| 选项 | 行为 |
|---|---|
| `--strip-all`（默认） | 删除 `.symtab`、`.strtab`、`.debug_*`；保留 `.dynsym` 和 `.dynstr` |
| `--strip-unneeded` | 同上，但对 `.o` 文件额外保留链接器需要的全局符号 |

两者在可执行文件和 `.so` 上的效果几乎相同——都保留动态符号表（`.dynsym`），不会影响运行时链接。

真正的区别在目标文件（`.o`）上：`--strip-all` 会把 `.o` 里的全局函数符号也删掉，导致链接器找不到符号，无法把这个 `.o` 链接成可执行文件。而 `--strip-unneeded` 会保留链接器需要的符号，`.o` 仍然可以正常链接。

所以经验法则是：**对 `.o` 文件用 `--strip-unneeded`，对可执行文件和 `.so` 用 `--strip-all` 即可。**

### file 和 size：快速概览

`file` 命令快速判断文件类型：

```bash
$ file ./myapp
./myapp: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV),
dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, ...
```

一行输出包含了架构、链接方式、位数等关键信息——比 `readelf -h` 快得多，适合快速判断。

`size` 命令显示各 section 的大小：

```bash
$ size ./myapp
   text    data     bss     dec     hex filename
   1203     600       8    1811     713 ./myapp
```

三个核心数字：代码段（text）、数据段（data）、BSS 段（bss）。在嵌入式开发中，这三个数字直接影响 Flash 和 RAM 的用量——`text` + `data` 占 Flash，`data` + `bss` 占 RAM。

### 交叉编译工具链中的 binutils

在嵌入式开发中，你用的不是系统自带的 `readelf`，而是交叉编译工具链里的版本。命令名带前缀：

```bash
$ arm-linux-gnueabihf-readelf -h ./arm-app
$ arm-linux-gnueabihf-objdump -d ./arm-app
$ arm-linux-gnueabihf-nm ./arm-app
```

为什么要用工具链自带的版本？因为系统自带的 `readelf` 是为 x86 编译的，虽然它也能读 ARM ELF 文件（ELF 格式是跨平台的），但工具链自带的版本保证了对目标架构的完整支持——比如某些 ARM 特有的 section 标志和重定位类型。

回到精装书的类比。`readelf -h` 是看封面——什么架构、什么类型。`readelf -S` 是看目录——有哪些章节、各占多少页。`objdump -d` 是逐页阅读——把每一行「印刷体」（机器码）翻译成你能看懂的「手写批注」（汇编）。`nm` 是查索引——函数和变量在哪一页。`strip` 是撕掉索引和批注——书变薄了，但内容还在。`file` 是扫一眼封面上的所有信息，一秒判断这本书是不是你要的。现在你手里有一整套「读」精装书的工具——ELF 文件不再是黑箱了。

---

## 实践层

### 4.1  准备一个示例程序

写一个简单的 C 程序，用来演示各种 binutils 工具：

```c
/* hello.c */
#include <stdio.h>

int global_init = 42;       /* .data */
int global_uninit;           /* .bss */
const char msg[] = "hello";  /* .rodata */

int add(int a, int b)
{
    return a + b;
}

int main(void)
{
    int result = add(global_init, global_uninit);
    printf("%s: %d\n", msg, result);
    return 0;
}
```

编译：

```bash
$ gcc -g -O0 -o hello hello.c
```

### 4.2  用 readelf 查看 ELF 结构

先看 ELF 头——确认架构和文件类型：

```bash
$ readelf -h ./hello
```

```
ELF Header:
  Class:                             ELF64
  Machine:                           Advanced Micro Devices X86-64
  Type:                              DYN (Position-Independent Executable)
  Entry point address:               0x1060
```

`Machine` 是 `X86-64`，`Type` 是 `DYN`（位置无关可执行文件，支持 ASLR）。这两个信息一秒钟就能告诉你这个文件能不能在当前系统上跑。

看段表——找出 `.text`、`.data`、`.bss` 在哪：

```bash
$ readelf -S ./hello | grep -E '\.text|\.data|\.bss|\.rodata'
```

```
  [13] .text             PROGBITS         0000000000001050  1050
  [15] .rodata           PROGBITS         0000000000002000  2000
  [23] .data             PROGBITS         0000000000004000  3000
  [24] .bss              NOBITS           0000000000004010  3010
```

注意 `.bss` 的类型是 `NOBITS`——它不占文件空间（大小在运行时才确定），但它在内存中占位置。

看程序头——操作系统怎么加载这个文件：

```bash
$ readelf -l ./hello
```

输出会显示两个 `LOAD` 段：一个放 `.text` 和 `.rodata`（只读+可执行），一个放 `.data` 和 `.bss`（可读写）。加载器只看这两个段。

### 4.3  反汇编、符号表与瘦身

反汇编 `main` 函数：

```bash
$ objdump -d ./hello | grep -A 20 '<main>'
```

```
0000000000001176 <main>:
    1176:	f3 0f 1e fa          	endbr64
    117a:	55                   	push   %rbp
    117b:	48 89 e5             	mov    %rsp,%rbp
    117e:	48 83 ec 10          	sub    $0x10,%rsp
    ...
```

如果编译时加了 `-g`，加上 `-S` 选项可以看源码和汇编的对应关系：

```bash
$ objdump -d -S ./hello | grep -A 25 '<main>'
```

查看符号表：

```bash
$ nm ./hello | grep -E 'main|add|global|msg'
```

```
0000000000001176 T main
0000000000001169 T add
0000000000004010 B global_uninit
0000000000004008 D global_init
0000000000002004 R msg
```

- `T main` 和 `T add`：代码段中的函数
- `B global_uninit`：BSS 段（未初始化）
- `D global_init`：数据段（已初始化）
- `R msg`：只读数据段（const）

用 `file` 快速确认文件类型：

```bash
$ file ./hello
./hello: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV),
dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2,
with debug_info, not stripped
```

注意 `with debug_info, not stripped`——因为我们编译时加了 `-g`，符号和调试信息都还在。

用 `size` 看各段大小：

```bash
$ size ./hello
   text    data     bss     dec     hex filename
   2529     616      16    3161     c59 ./hello
```

现在做一次 strip，看看前后对比：

```bash
$ cp ./hello ./hello.debug
$ strip ./hello
$ ls -lh ./hello ./hello.debug
-rwxr-xr-x 1 charlie charlie 6.2K Jun 11 12:00 ./hello
-rwxr-xr-x 1 charlie charlie 16K Jun 11 12:00 ./hello.debug
```

`hello.debug` 是未 strip 的备份（用于 GDB 调试），`hello` 是 strip 后的版本（用于部署）。

确认 strip 后的文件还能正常运行：

```bash
$ ./hello
hello: 42
```

但符号表没了：

```bash
$ nm ./hello
nm: ./hello: no symbols
```

> ⚠️ **踩坑提醒**
> `strip` 对可执行文件和 `.so` 是安全的（动态符号表会保留）。但对**目标文件（`.o`）** 使用 `--strip-all` 会删除全局函数符号，导致链接失败。如果需要 strip `.o` 文件，用 `--strip-unneeded`。

---

## 练习题

走到这里，binutils 的核心工具应该清楚了。下面两道题帮你验证——第一题是理解，第二题需要动手。

**练习 33.1** ⭐（理解）

`.text` section 和 `.data` section 的区别是什么？它们在 `readelf -S` 输出中的 Flags 分别是什么？为什么 `.text` 有 `X` 标志而 `.data` 没有？

**练习 33.2** ⭐⭐（应用）

用 `gcc -g -O0` 编译以下程序，然后回答：

```c
#include <stdio.h>
static int counter = 0;
void inc(void) { counter++; }
int get(void) { return counter; }
int main(void) { inc(); inc(); printf("%d\n", get()); return 0; }
```

1. 用 `nm` 查看 `counter`、`inc`、`get` 的符号类型。`counter` 是 `T`、`D` 还是 `b`/`B`？为什么和 `readelf -S` 中看到的 section 对应？
2. 用 `size` 查看 text、data、bss 的值。如果去掉 `= 0`（变成 `static int counter;`），bss 的大小会怎么变化？先预测，再验证。

> **提示**：`static` 变量不论有没有初始化，都是全局变量。初始化了放 `.data`，没初始化放 `.bss`。

---

## 本章回响

binutils 的核心价值不是某一个工具，而是一种能力——在编译和运行之间，对二进制文件进行静态检查的能力。编译器告诉你「编译通过了」，`file` 和 `readelf` 告诉你「这个文件是什么架构、什么格式」。链接器告诉你「链接完成了」，`nm` 告诉你「符号表里有没有你定义的函数，有没有缺失的依赖」。GDB 在运行时查，binutils 在运行前查——两者配合，才能完整掌握程序的行为。

还记得开头那个问题吗——编译出来的文件到底对不对？现在你有一整套工具来回答：`file` 一秒看架构，`readelf -h` 看详细信息，`readelf -S` 看段布局，`nm` 查符号，`objdump -d` 看反汇编。ELF 文件不再是黑箱，你可以像翻书一样逐页检查。

对于嵌入式开发来说，这套工具会在你每次交叉编译之后用到。编译完了，先 `arm-linux-gnueabihf-readelf -h` 确认架构对了，再拷到板子上——这个习惯能帮你省下大量「拷过去跑不了」的排查时间。

下一章我们会进入代码管理——Git 的日常操作。当你的代码越来越多、改动越来越频繁，版本控制就成了必须掌握的技能。

---

[← 上一章：GDB 调试入门](ch32-gdb.md)
[下一章：Git 日常操作手册 →](ch34-git.md)
