# 第 32 章  GDB 调试入门

> **Part 7 · 开发工具链**

---

## 引子

程序跑崩了。终端吐了一行 `Segmentation fault (core dumped)`，然后什么都没了。

没有行号，没有调用栈，没有变量值。你知道它崩了，但你不知道它在哪里崩的、为什么崩的。

初学者的本能反应是加 `printf`——在崩溃位置前面打一堆日志，重新编译，再跑一次。有时候管用。但有时候崩溃的位置不确定，你得加十几个 `printf` 反复试，编译了跑、跑了崩、崩了再加，来回折腾。更麻烦的是，有些 bug 跟时序有关——加了 `printf` 之后时序变了，bug 反而消失了。

GDB 是法医。它不关心你的程序应该做什么，它只关心你的程序实际上做了什么——一步一步，一个变量一个变量，一层调用栈一层调用栈地查。学会 GDB，你就不再需要靠猜来调试了。

---

## 背景与动机

在上一章（第 31 章）里，我们学会了用 GCC 编译 C 程序。编译通过了，程序跑起来了——然后崩了。这是 C 语言开发中最常见的场景：编译器只能帮你抓语法错误，逻辑错误和内存错误它管不了。

传统的调试手段是 `printf` 大法。它的优势是简单直接，不需要学新工具。但它的劣势同样明显：

- 每次 `printf` 都要重新编译
- 不能在运行时改变策略——你只能在编译时决定打印什么
- 时序相关的 bug 会被 `printf` 的执行时间干扰
- 崩溃瞬间的一切信息都丢了——`printf` 只能输出崩溃之前你预想到的内容

GDB（GNU Debugger）解决了这些问题。它让你在程序运行时暂停执行、检查变量、单步推进、查看调用栈——甚至可以在不重新编译的情况下改变执行流程。对于嵌入式开发来说，GDB 的远程调试功能（`gdbserver`）是调试开发板上程序的标配方案——这个我们会在后续的 imx-forge 教程中用到。

---

## 概念层

### 编译时带上调试信息

GDB 能告诉你「第几行崩溃」，前提是编译时保留了调试信息。这需要在 `gcc` 后面加 `-g` 选项：

```bash
$ gcc -g -o myapp myapp.c
```

`-g` 的作用是在可执行文件里嵌入源代码的行号信息和变量名。没有 `-g`，GDB 只能看到内存地址和汇编指令——虽然也能用，但体验差了一个数量级。

日常开发中，推荐组合使用 `-g` 和 `-O0`（关闭优化）：

```bash
$ gcc -g -O0 -o myapp myapp.c
```

为什么要关优化？因为编译器优化会重排代码、内联函数、消除变量。开了 `-O2` 之后，你设断点的那行代码可能已经被编译器挪到别的地方了，变量也可能被优化掉查不到了。调试阶段关优化，发布阶段再开——这是标准做法。

### GDB 的基本工作流

你可以把 GDB 想象成一个**录像机的慢放模式**。普通运行是按播放键——程序从头跑到尾，你只能看最终结果。GDB 是按暂停键之后一帧一帧地看：暂停在某一帧（断点），看清楚每一帧的细节（变量），按快进到下一个暂停点（continue），或者一帧一帧慢慢看（step / next）。

但这个类比有一个地方是错的。录像机只能回放已经发生的事情，GDB 不一样——它是实时的。程序在 GDB 里是真的在运行，只是你可以随时让它停下来、检查状态、然后继续。你甚至可以在运行时修改变量的值，看看程序会怎么走。它不是回放，是现场直播的慢放。

GDB 的基本工作流是这样的：

```
启动 GDB → 设断点 → 运行程序 → 在断点处停下来 → 检查变量 → 单步推进 → 找到 bug
```

对应的命令只有几个：

| 命令 | 缩写 | 作用 |
|---|---|---|
| `break` | `b` | 设断点 |
| `run` | `r` | 运行程序 |
| `next` | `n` | 单步执行（不进入函数） |
| `step` | `s` | 单步执行（进入函数） |
| `print` | `p` | 打印变量值 |
| `backtrace` | `bt` | 查看调用栈 |
| `continue` | `c` | 继续运行到下一个断点 |
| `quit` | `q` | 退出 GDB |

不需要一次记住所有命令。先把 `break`、`run`、`next`、`print`、`backtrace` 这五个用熟，就能覆盖 80% 的调试场景。

### Core dump：崩溃现场保留

程序崩溃时，操作系统可以把崩溃瞬间的内存映像保存到一个文件里——这就是 core dump（核心转储）。拿到这个文件，你可以用 GDB 事后分析崩溃现场，不需要重新运行程序。

这个功能默认在 Ubuntu 上是关闭的（或者被 Apport 接管了）。手动开启的方法：

```bash
$ ulimit -c unlimited
```

这条命令取消 core 文件的大小限制。之后程序崩溃时，当前目录下会出现一个叫 `core` 或 `core.<PID>` 的文件。

### TUI 模式

GDB 还有一个文本界面模式（TUI），可以把源代码和命令窗口并排显示。启动方式：

```bash
$ gdb -tui ./myapp
```

TUI 模式下，上半部分显示源代码（当前行高亮），下半部分是命令输入区。用 `Ctrl+X A` 可以在 TUI 和普通模式之间切换。如果你觉得纯命令行 GDB 信息不够直观，TUI 模式值得一试。

---

## 实践层

### 4.1  准备一个有 bug 的程序

先写一个「看起来没什么问题但其实会崩」的程序，用来练习 GDB 操作：

```c
/* bug.c: 一个经典的空指针崩溃 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void greet(const char *name)
{
    char *msg = NULL;

    /* 忘了给 msg 分配内存 */
    sprintf(msg, "Hello, %s!", name);
    printf("%s\n", msg);
}

int main(void)
{
    const char *users[] = {"Alice", "Bob", "Charlie"};
    int i;

    for (i = 0; i < 3; i++) {
        greet(users[i]);
    }

    return 0;
}
```

编译（带调试信息，关优化）：

```bash
$ gcc -g -O0 -o bug bug.c
```

编译不会报错——语法上没问题。运行：

```bash
$ ./bug
Segmentation fault (core dumped)
```

崩了。没有行号，没有调用栈。现在用 GDB 来查。

### 4.2  用 GDB 找到崩溃点

启动 GDB：

```bash
$ gdb ./bug
```

```
GNU gdb (Ubuntu 12.1-0ubuntu1~22.04) 12.1
...
Reading symbols from ./bug...
(gdb)
```

`(gdb)` 是 GDB 的提示符。直接运行程序：

```
(gdb) run
Starting program: /home/charlie/projects/bug
Program received signal SIGSEGV, Segmentation fault.
0x0000555555555169 in greet (name=0x555555556004 "Alice") at bug.c:10
10	    sprintf(msg, "Hello, %s!", name);
```

关键信息来了：
- **SIGSEGV**：段错误，程序访问了非法内存
- **greet 函数，bug.c 第 10 行**：崩溃的精确位置
- **name=0x... "Alice"**：参数 `name` 的值是正常的
- **第 10 行**：`sprintf(msg, ...)`——往一个 NULL 指针里写数据

查看调用栈：

```
(gdb) backtrace
#0  0x0000555555555169 in greet (name=0x555555556004 "Alice") at bug.c:10
#1  0x00005555555551a0 in main () at bug.c:17
```

`backtrace`（缩写 `bt`）显示函数调用链：`main` 第 17 行调用了 `greet`，`greet` 在第 10 行崩了。从下往上读——越往下越是调用者。

打印变量 `msg` 的值确认：

```
(gdb) print msg
$1 = 0x0
```

`0x0` 就是 NULL。问题清楚了：`msg` 是空指针，`sprintf` 往空指针写数据，触发段错误。

退出 GDB：

```
(gdb) quit
```

### 4.3  用断点逐步调试

上面是「事后分析」的模式——让程序跑完，看它崩在哪里。但很多时候你需要「事前埋伏」——在某个可疑位置设断点，程序运行到那里自动停下来，你一步步看。

修改一下程序，让它有更隐蔽的 bug：

```c
/* bug2.c: 数组越界访问 */
#include <stdio.h>

int sum(int arr[], int len)
{
    int total = 0;
    int i;

    for (i = 0; i <= len; i++) {   /* 注意这里是 <= */
        total += arr[i];
    }

    return total;
}

int main(void)
{
    int nums[] = {10, 20, 30};

    printf("Sum = %d\n", sum(nums, 3));
    return 0;
}
```

编译运行：

```bash
$ gcc -g -O0 -o bug2 bug2.c
$ ./bug2
Sum = 60
```

看起来没问题？输出 60，`10 + 20 + 30 = 60`。但仔细看 `for` 循环：`i <= len`，而数组只有 3 个元素（下标 0、1、2）。当 `i == 3` 时，`arr[3]` 越界了——读到了数组后面的内存，恰好是 0，所以结果凑巧对了。但这是未定义行为（undefined behavior），在别的机器上、别的编译选项下，结果可能完全不同。

用 GDB 抓这个 bug：

```bash
$ gdb ./bug2
```

在 `sum` 函数的入口设断点：

```
(gdb) break sum
Breakpoint 1 at 0x555555555169: file bug2.c, line 8.
```

运行程序，它会在断点处停下来：

```
(gdb) run
Starting program: /home/charlie/projects/bug2

Breakpoint 1, sum (arr=0x7fffffffdc30, len=3) at bug2.c:8
8	    int total = 0;
```

现在一步一步走：

```
(gdb) next
9	    for (i = 0; i <= len; i++) {
(gdb) next
10	        total += arr[i];
```

打印当前循环变量的值：

```
(gdb) print i
$1 = 0
(gdb) print arr[i]
$2 = 10
(gdb) print total
$3 = 0
```

继续单步，观察每一轮循环：

```
(gdb) next
9	    for (i = 0; i <= len; i++) {
(gdb) print i
$4 = 1
```

等等，为什么 `i` 变成 1 了？因为 `next` 执行了 `total += arr[0]`，然后回到了 `for` 循环头部的 `i++` 和判断。每一轮 `next` 执行一条语句。我们需要多走几步。

一直 `next` 到 `i` 变成 3：

```
(gdb) next
10	        total += arr[i];
(gdb) print i
$5 = 3
(gdb) print arr[i]
$6 = 32765
```

`arr[3]` 的值是 32765——这是数组后面的垃圾数据。如果这个值不是 0，`Sum` 的结果就不对了。

这里也可以用条件断点——让程序在 `i == 3` 时自动停下来：

```
(gdb) break bug2.c:10 if i == 3
Breakpoint 2 at 0x555555555183: file bug2.c, line 10.
(gdb) continue
Continuing.

Breakpoint 2, sum (arr=0x7fffffffdc30, len=3) at bug2.c:10
10	        total += arr[i];
(gdb) print i
$7 = 3
```

条件断点在调试循环的时候特别好用——不需要按几百次 `next`，直接让程序在满足条件时停住。

退出：

```
(gdb) quit
```

### 4.4  Core dump 分析

如果程序已经崩了，生成了 core 文件，你可以事后分析。

先确保 core dump 是开启的：

```bash
$ ulimit -c unlimited
```

运行有 bug 的程序，让它崩：

```bash
$ ./bug
Segmentation fault (core dumped)
```

查看是否生成了 core 文件：

```bash
$ ls -lh core*
# 实际输出可能略有不同
-rw------- 1 charlie charlie 256K Jun 11 12:00 core
```

⚠️ **Ubuntu 注意事项**：在 Ubuntu 22.04/24.04 上，core dump 可能被 Apport（错误报告服务）接管了，core 文件不会出现在当前目录，而是被 `/proc/sys/kernel/core_pattern` 里的管道程序处理。可以用以下命令检查：

```bash
$ cat /proc/sys/kernel/core_pattern
|/usr/share/apport/apport -p%p -s%s -C -r%i -m%i -I -f %F
```

如果输出以 `|` 开头，说明 core dump 被管道到了 Apport。如果想生成传统的 core 文件，可以临时关闭管道：

```bash
$ sudo sysctl -w kernel.core_pattern=core.%p
```

用 GDB 分析 core 文件：

```bash
$ gdb ./bug core
```

```
...
Core was generated by `./bug'.
Program terminated with signal SIGSEGV, Segmentation fault.
#0  0x0000555555555169 in greet (name=0x555555556004 "Alice") at bug.c:10
10	    sprintf(msg, "Hello, %s!", name);
```

和之前 `run` 的结果一样——GDB 直接把崩溃现场还原了。你可以用 `backtrace`、`print` 等命令继续分析。

回到录像机慢放的类比。GDB 的普通调试模式是「边播边暂停」——你控制播放速度。Core dump 分析是「调出事故录像」——事故已经发生了，你一帧一帧地看最后一刻的画面。两种模式用同一套命令——`backtrace`、`print`——因为不管事故是正在发生还是已经发生，你需要看的信息是一样的：在哪个函数崩的、调用栈是什么、变量的值是什么。

---

## 练习题

走到这里，GDB 的基本操作应该清楚了。下面两道题难度递进，建议先动手再翻提示。

**练习 32.1** ⭐（理解）

编译时为什么要加 `-g` 选项？如果忘了加，GDB 还能用吗？会丢失哪些信息？

**练习 32.2** ⭐⭐（应用）

下面这个程序会崩溃。请用 GDB 找出崩溃的行号、原因，并说明怎么修复：

```c
#include <stdio.h>

int main(void)
{
    int arr[5] = {1, 2, 3, 4, 5};
    int *p = NULL;

    for (int i = 0; i < 5; i++) {
        *p += arr[i];
    }

    printf("Total: %d\n", *p);
    return 0;
}
```

> **提示**：先 `gcc -g -O0` 编译，再 `gdb ./a.out`，`run` 之后看 `backtrace`。

---

## 本章回响

GDB 的价值不在于它是一个「更高级的 printf」——它的价值在于让你能在程序运行的任意时刻暂停、检查、然后继续。这种能力在调试时序相关的 bug、多线程问题、和崩溃分析中是不可替代的。`break` 让你选择在哪里停，`next` 和 `step` 让你选择以什么粒度推进，`print` 和 `backtrace` 让你选择看什么信息。五个命令，覆盖了绝大多数调试场景。

还记得开头那个 `Segmentation fault` 吗——终端吐了一行输出就什么都没了？现在你知道 GDB 怎么把碎片拼回来了：`run` 让崩溃重演，GDB 自动停在崩溃点，`backtrace` 显示调用链，`print` 显示变量值。整个过程不需要改一行代码，不需要加一个 `printf`。崩溃不再是一个黑箱——它是一个你可以反复回看的现场。

Core dump 则是这个能力的延伸：程序在生产环境崩了，你把 core 文件拷回来，在本机用 GDB 分析，等于把事故现场搬回了实验室。对于嵌入式开发来说，这意味着开发板上的崩溃你可以在开发机上远程调试——后面的 imx-forge 教程会详细展开这种用法。

下一章我们会换一个角度审视编译产物——不用运行程序，而是用 binutils 工具箱直接「透视」ELF 文件的内部结构。GDB 是在运行时查，binutils 是在静态时查，两者配合才能完整掌握程序的行为。

---

[← 上一章：GCC 与 Makefile 基础](ch31-gcc-make.md)
[下一章：二进制工具箱 →](ch33-binutils.md)
