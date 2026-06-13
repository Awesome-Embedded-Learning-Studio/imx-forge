# 第 31 章  GCC 与 Makefile 基础

> **Part 7 · 开发工具链**

---

## 引子

你写了一个 hello.c，然后呢？

在 IDE 里你点一下「运行」按钮，一切自动完成。在终端里，你需要告诉系统：先预处理，再编译，再汇编，再链接——四个步骤，每一步都有它存在的理由。

为什么不能一步到位？为什么 gcc 不直接把 `.c` 文件变成可执行文件？

技术上它确实可以——你敲 `gcc hello.c` 就能得到 `a.out`。但"能做到"和"应该这么做"是两回事。理解编译的四个阶段，不是为了应付考试，而是因为嵌入式开发中你会反复在每一个阶段停下来检查：预处理的结果对不对？汇编输出是不是我预期的？链接时为什么找不到符号？

gcc 是这个流程的入口。Makefile 是这个流程的自动化脚本。当你有几十个 .c 文件、互相依赖、改动一个需要重新编译另一个时，手动 gcc 会让你疯掉。Makefile 用依赖关系图解决了这个问题。

理解编译流程和 Makefile，是进入嵌入式开发的门票。

---

## 背景与动机

在第 17 章里，我们用 `sudo apt install build-essential` 装好了 gcc。从那时起，你就有了一个 C 编译器。但一直到现在，我们都没有真正用它。

嵌入式开发的核心工作是写代码、编译、调试、烧录。这四步里，"编译"是你和机器之间的第一道桥梁。你需要知道这根桥梁是怎么搭的——不是每一个螺丝都要认识，但你至少要知道桥有几段，每段在干什么，哪一段最可能出问题。

Makefile 看起来像另一个话题，但它和 gcc 是一体的。当你的项目只有一两个文件时，手动敲 `gcc` 命令还勉强能忍。但嵌入式项目的源码动辄几十个文件，互相之间有依赖关系——改了 `driver.c` 需要重新编译它，但 `main.c` 不用重新编译。手动判断"哪些文件需要重编"既慢又容易出错。Makefile 就是解决这个问题的自动化工具。

本章只讲 gcc 编译流程和 Makefile 基础。更高级的构建系统——CMake、automake、Yocto 的 BitBake——都是在这个基础上演进的。地基打好了，后面才站得稳。

---

## 概念层

### 编译流水线——类比第一次：建立映射

你可以把 gcc 的编译过程想象成一条汽车制造流水线。

预处理（Preprocessing）是**原料车间**——把所有原材料展开、分类。`#include` 的头文件全部摊开铺平，`#define` 的宏全部替换成实际值，`#ifdef` 的条件编译决定哪些代码留下、哪些扔掉。

编译（Compilation）是**设计车间**——把高级语言翻译成汇编指令。每一种 CPU 架构对应不同的"设计图纸"。x86 有 x86 的汇编，ARM 有 ARM 的汇编。同一个 `.i` 文件，在不同架构的编译器下会输出完全不同的 `.s` 文件。

汇编（Assembly）是**零件车间**——把汇编指令翻译成机器码。这一步的输出是目标文件（`.o`），已经是二进制了，但还不能直接执行——它是一堆散装的零件，等着被拼起来。

链接（Linking）是**总装车间**——把所有目标文件和标准库拼在一起，解析外部符号（比如 `printf` 到底在哪里），生成最终的可执行文件。

但"流水线"这个比喻有一个关键失真：真正的汽车流水线是不可逆的——零件进了下一个车间就不回头了。而编译流程中，程序员经常需要**回到某个中间阶段**检查输出。比如预处理的 `.i` 文件可以帮你排查宏展开的问题，汇编的 `.s` 文件可以帮你理解编译器做了什么优化。这就是为什么 gcc 允许你在每个阶段停下来，也是为什么"一步到位"并不总是好事。

### 四个阶段，四个文件后缀

gcc 编译一个 `.c` 文件，完整路径是这样的：

```
hello.c → [预处理] → hello.i → [编译] → hello.s → [汇编] → hello.o → [链接] → a.out
            -E                    -S                 -c
```

每个阶段对应的 gcc 选项和输出：

| 阶段 | gcc 选项 | 输入 | 输出 | 做了什么 |
|---|---|---|---|---|
| 预处理 | `-E` | `.c` | `.i` | 展开 `#include`、替换 `#define`、处理条件编译 |
| 编译 | `-S` | `.i` | `.s` | 将 C 代码翻译成汇编代码 |
| 汇编 | `-c` | `.s` | `.o` | 将汇编代码翻译成机器码（目标文件） |
| 链接 | （无专用选项） | `.o` | 可执行文件 | 合并目标文件、解析外部符号、绑定库函数 |

**注意**：`-S` 是大写 S，`-s`（小写）是另一个选项——用于剥离可执行文件的符号表，功能完全不同，不要混淆。

当你直接运行 `gcc hello.c` 时，gcc 在内部把这四步全部走完，中间文件不保留，直接给你最终的可执行文件。这就是"一步到位"——方便，但不透明。

### 预处理——原料车间

```bash
$ cat hello.c
#include <stdio.h>

#define GREETING "Hello, embedded world!"

int main(void) {
    printf("%s\n", GREETING);
    return 0;
}

$ gcc -E hello.c -o hello.i
$ wc -l hello.i
# 预期输出
842 hello.i
```

842 行。你的源文件只有 9 行，但预处理展开 `<stdio.h>` 之后膨胀到了 842 行。这就是预处理做的事——把所有 `#include` 的内容原封不动地插进来，把所有 `#define` 的宏替换掉，处理所有 `#ifdef`/`#ifndef` 条件编译。

看一下文件末尾：

```bash
$ tail -10 hello.i
# 预期输出（文件末尾是你自己的代码，宏已替换）
# 2 "hello.c" 2

int main(void) {
    printf("%s\n", "Hello, embedded world!");
    return 0;
}
```

`GREETING` 宏已经被替换成了 `"Hello, embedded world!"`。如果有一天你的宏展开出了问题——编译器报了一行你完全不认识的错误——看 `.i` 文件是最直接的排查手段。

### 编译——设计车间

```bash
$ gcc -S hello.i -o hello.s
$ head -20 hello.s
# 预期输出（x86-64 汇编，不同架构输出不同）
	.file	"hello.c"
	.section	.rodata
.LC0:
	.string	"Hello, embedded world!"
	.text
	.globl	main
	.type	main, @function
main:
	pushq	%rbp
	movq	%rsp, %rbp
	leaq	.LC0(%rip), %rdi
	call	puts@PLT
	movl	$0, %eax
	popq	%rbp
	ret
```

这是 x86-64 架构的汇编输出。你不需要现在就能读懂每一条汇编指令——但你需要知道这一步的存在。在嵌入式开发中，当你需要优化性能或者排查奇怪的编译器行为时，看汇编输出是关键手段。

注意一个有趣的细节：你写的是 `printf`，但汇编里变成了 `puts`。因为编译器发现格式字符串里只有一个 `%s\n`，用 `puts` 更高效——它不需要解析格式字符串。这种优化是编译器默默做的，你平时不会注意到。

### 汇编——零件车间

```bash
$ gcc -c hello.s -o hello.o
$ file hello.o
# 预期输出
hello.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), not stripped
```

`hello.o` 是目标文件（Object File），已经是机器码了，但还不能直接执行。`file` 命令显示它是 `relocatable`（可重定位的）——里面的地址还没有最终确定，需要链接器来分配。你可以把 `.o` 文件理解为一个"还没装到位的零件"——形状是对的，但位置是浮动的。

### 链接——总装车间

```bash
$ gcc hello.o -o hello
$ ./hello
# 预期输出
Hello, embedded world!
```

链接器把 `hello.o` 和 C 标准库（`libc`）合并，解析 `puts` 函数的实际地址，生成最终的可执行文件。到这一步，编译流程走完了。

### 常用 gcc 选项

在实际开发中，你几乎不会单独执行每个阶段。你更常用的是这些选项的组合：

```bash
# 编译并链接，指定输出文件名（最常用）
$ gcc hello.c -o hello

# 开启常用警告（必须养成的习惯）
$ gcc -Wall hello.c -o hello

# 开启更多警告 + 把警告当错误处理
$ gcc -Wall -Wextra -Werror hello.c -o hello

# 包含调试信息（给 GDB 用，下一章会讲）
$ gcc -g hello.c -o hello

# 指定 C 标准
$ gcc -std=c11 hello.c -o hello

# 只编译不链接（生成 .o 文件）
$ gcc -c hello.c -o hello.o
```

这里要专门说一下 `-Wall`。它的名字有误导性——`-Wall` **不是"所有警告"**（Wall ≠ Warn all），它只是一组最常用的警告集合。在 Ubuntu 22.04 上默认的 GCC 11 中，`-Wall` 包含了 `-Wformat`（格式字符串不匹配）、`-Wunused`（未使用变量）、`-Wreturn-type`（缺少返回值）、`-Wimplicit`（隐式函数声明）等几十个警告选项。

但它**不包含** `-Wextra`（更多边缘情况警告）、`-Wconversion`（隐式类型转换）、`-Wshadow`（变量遮蔽）等。在嵌入式项目里，建议永远带着 `-Wall -Wextra` 编译——警告不是噪音，是编译器在告诉你"这里可能有问题"。

`-Werror` 则更激进：它把所有警告升级为错误，代码有任何警告就编译不过。严格，但能帮你从第一天就养成干净的编码习惯。

### Makefile——自动化的依赖管理

gcc 的编译流程搞清楚了。下一个问题是：当你的项目不止一个文件时，怎么管理编译过程？

假设你的项目结构是这样的：

```
project/
├── main.c      # 主程序
├── driver.c    # 驱动模块
├── driver.h    # 驱动头文件
└── Makefile
```

最笨的方法是每次都手动敲：

```bash
$ gcc -c main.c -o main.o
$ gcc -c driver.c -o driver.o
$ gcc main.o driver.o -o myapp
```

改了 `driver.c`？再敲一遍三行命令。改了 `driver.h`？也要重新编译 `main.c` 和 `driver.c`——因为 `main.c` 也 `#include` 了 `driver.h`。这种手动方式在文件少的时候勉强能忍，一旦文件超过五六个就会开始出错。

Makefile 就是来解决这个问题的。它用一种声明式的方式描述文件之间的依赖关系：

```makefile
# Makefile
myapp: main.o driver.o
	gcc main.o driver.o -o myapp

main.o: main.c driver.h
	gcc -Wall -c main.c -o main.o

driver.o: driver.c driver.h
	gcc -Wall -c driver.c -o driver.o

clean:
	rm -f *.o myapp
```

Makefile 的规则格式是：

```
目标: 依赖列表
	命令（必须用 Tab 缩进，不能用空格）
```

当你运行 `make` 时，Make 会做这几件事：

1. 找到第一个目标 `myapp`
2. 检查它的依赖 `main.o` 和 `driver.o` 是否存在、是否比目标更新
3. 如果 `main.o` 不存在或比它的依赖（`main.c`、`driver.h`）更旧，执行生成 `main.o` 的命令
4. 对 `driver.o` 同理
5. 最后链接生成 `myapp`

关键洞察：**Make 只重新编译有变化的文件**。如果你只改了 `driver.c`，`make` 只会重新编译 `driver.o` 然后重新链接，不会碰 `main.o`。这就是 Makefile 的价值——自动化的增量编译。

> ⚠️ **Makefile 的 Tab 陷阱**
>
> Makefile 中命令行的缩进**必须使用 Tab 键**，不能用空格。这是 Makefile 设计中最臭名昭著的历史包袱——2026 年了，Tab 和空格的区别依然能让新手卡一个小时。
>
> 如果你在 vim 中编辑，确保没有把 Tab 替换成空格。可以在 vim 里执行 `:set noexpandtab` 来确保使用真实 Tab。
>
> 如果你看到 `Makefile:3: *** missing separator. Stop.`，99% 的概率是空格混进去了。

### Makefile 变量——消除重复

上面那个 Makefile 有一个问题：`gcc` 和 `-Wall` 重复出现了三次。如果以后要改编译器（比如改成 ARM 交叉编译器 `arm-linux-gnueabihf-gcc`），你得改三个地方。

Makefile 变量解决这个问题：

```makefile
# Makefile（变量版本）
CC = gcc
CFLAGS = -Wall -Wextra -g

myapp: main.o driver.o
	$(CC) main.o driver.o -o myapp

main.o: main.c driver.h
	$(CC) $(CFLAGS) -c main.c -o main.o

driver.o: driver.c driver.h
	$(CC) $(CFLAGS) -c driver.c -o driver.o

clean:
	rm -f *.o myapp
```

`$(CC)` 和 `$(CFLAGS)` 是变量引用，在执行时展开为对应的值。以后要换编译器，只改 `CC = gcc` 那一行就行。这个能力在做交叉编译（第 35 章会讲）的时候尤其重要——你只需要把 `CC` 改成交叉编译器的路径，整个 Makefile 就自动切换到 ARM 编译模式。

### 自动变量——让规则更简洁

Makefile 提供了几个**自动变量**，在规则的命令中自动展开为对应的值：

| 变量 | 含义 |
|---|---|
| `$@` | 当前规则的**目标名** |
| `$<` | 第一个**依赖文件** |
| `$^` | 所有依赖文件（去重） |

用自动变量改写上面的 Makefile：

```makefile
CC = gcc
CFLAGS = -Wall -Wextra -g

myapp: main.o driver.o
	$(CC) $^ -o $@

main.o: main.c driver.h
	$(CC) $(CFLAGS) -c $< -o $@

driver.o: driver.c driver.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o myapp
```

`$@` 展开为目标名（比如 `main.o`），`$<` 展开为第一个依赖（比如 `main.c`），`$^` 展开为所有依赖（比如 `main.o driver.o`）。规则变得更简洁，也不容易写错。

### 模式规则——通用的编译模板

如果你的项目有十几个 `.c` 文件，每个都写一条规则太啰嗦。Makefile 的**模式规则**用 `%` 通配符解决这个问题：

```makefile
CC = gcc
CFLAGS = -Wall -Wextra -g
OBJS = main.o driver.o utils.o

myapp: $(OBJS)
	$(CC) $^ -o $@

# 模式规则：所有 .o 文件都由对应的 .c 文件生成
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o myapp
```

`%.o: %.c` 的意思是：任何 `.o` 文件，都可以从同名的 `.c` 文件编译生成。`%` 在 Make 匹配规则时被替换为实际的文件名——比如 `main.o` 匹配时，`%` 就是 `main`，依赖就展开为 `main.c`。

这里有一个容易忽略的细节：`%` 的展开发生在 Make 决定使用哪条规则来构建目标的时候，而不是读取 Makefile 的时候。这意味着你不能在变量展开阶段引用 `%` 的值。听起来有点绕——现在只需要知道模式规则是"按需匹配"的就行，用多了自然就理解了。

### 类比第三次——回收验证

回到流水线类比。你现在应该能看清每个车间为什么必须独立存在了：

- **原料车间**（预处理）把原材料全部展开——没有它，编译器不知道 `printf` 的声明长什么样
- **设计车间**（编译）把 C 代码翻译成汇编——没有它，汇编器和链接器都读不懂你的代码
- **零件车间**（汇编）把汇编翻译成机器码——没有它，链接器没有"零件"可以拼
- **总装车间**（链接）把零件拼成完整产品——没有它，所有零件都是散的，无法运行

Makefile 就是这条流水线的自动化调度系统——它知道哪个零件需要重新生产，哪个可以直接用库存。如果你改了某个零件的设计图（源文件），Makefile 只会重新生产那个零件，而不是整条流水线重来一遍。

---

## 实践层

### 4.1 从零编译一个 C 程序

**创建项目目录和源文件**

```bash
$ mkdir -p ~/gcc-practice && cd ~/gcc-practice
$ cat > hello.c << 'EOF'
#include <stdio.h>

#define GREETING "Hello, embedded world!"

int main(void) {
    printf("%s\n", GREETING);
    return 0;
}
EOF
```

**走一遍完整四阶段**

```bash
# 阶段一：预处理
$ gcc -E hello.c -o hello.i
$ wc -l hello.i
# 预期输出
842 hello.i

# 阶段二：编译
$ gcc -S hello.i -o hello.s
$ head -5 hello.s
# 预期输出（x86-64 汇编片段）
	.file	"hello.c"
	.section	.rodata
...

# 阶段三：汇编
$ gcc -c hello.s -o hello.o
$ file hello.o
# 预期输出
hello.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), not stripped

# 阶段四：链接
$ gcc hello.o -o hello
$ ./hello
# 预期输出
Hello, embedded world!
```

**一步到位——日常用法**

```bash
$ gcc -Wall -Wextra hello.c -o hello
$ ./hello
# 预期输出
Hello, embedded world!
```

日常开发中你不会分四步走——除非你在排查编译问题。`-Wall -Wextra` 应该成为你的肌肉记忆，每次编译都带上。

**看看 gcc 版本**

```bash
$ gcc --version
# 预期输出（Ubuntu 22.04）
gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
```

Ubuntu 22.04 默认是 GCC 11，Ubuntu 24.04 默认是 GCC 13。版本号不同不影响本章的操作，但如果你在排查编译器相关的 bug，知道版本号是第一步。

### 4.2 用 Makefile 管理多文件项目

**创建多文件项目**

```bash
$ cd ~/gcc-practice

$ cat > main.c << 'EOF'
#include <stdio.h>
#include "driver.h"

int main(void) {
    driver_init();
    printf("Driver version: %s\n", driver_version());
    driver_cleanup();
    return 0;
}
EOF

$ cat > driver.h << 'EOF'
#ifndef DRIVER_H
#define DRIVER_H

void driver_init(void);
void driver_cleanup(void);
const char *driver_version(void);

#endif
EOF

$ cat > driver.c << 'EOF'
#include "driver.h"
#include <stdio.h>

static const char *version = "1.0.0";

void driver_init(void) {
    printf("Driver initialized (v%s)\n", version);
}

void driver_cleanup(void) {
    printf("Driver cleaned up\n");
}

const char *driver_version(void) {
    return version;
}
EOF
```

**编写 Makefile**

```bash
$ cat > Makefile << 'EOF'
CC = gcc
CFLAGS = -Wall -Wextra -g

myapp: main.o driver.o
	$(CC) $^ -o $@

main.o: main.c driver.h
	$(CC) $(CFLAGS) -c $< -o $@

driver.o: driver.c driver.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o myapp

.PHONY: clean
EOF
```

这里有一个新的东西：`.PHONY: clean`。它告诉 Make `clean` 不是一个真正的文件名，而是一个"伪目标"。这样即使目录下碰巧有一个叫 `clean` 的文件，`make clean` 也不会被跳过。

**编译和运行**

```bash
$ make
# 预期输出
gcc -Wall -Wextra -g -c main.c -o main.o
gcc -Wall -Wextra -g -c driver.c -o driver.o
gcc main.o driver.o -o myapp

$ ./myapp
# 预期输出
Driver initialized (v1.0.0)
Driver version: 1.0.0
Driver cleaned up
```

**验证增量编译——只改一个文件**

```bash
$ touch driver.c     # 修改时间戳模拟文件变更
$ make
# 预期输出（只重新编译了 driver.o）
gcc -Wall -Wextra -g -c driver.c -o driver.o
gcc main.o driver.o -o myapp
```

注意 `main.o` 没有被重新编译。Make 检测到 `main.c` 和 `driver.h` 都没变，所以跳过了 `main.o` 的编译。这就是 Makefile 的增量编译在起作用——只编译必要的部分。

再试一个更有趣的场景：修改头文件。

```bash
$ touch driver.h     # 头文件变了
$ make
# 预期输出（两个 .o 都重新编译了）
gcc -Wall -Wextra -g -c main.c -o main.o
gcc -Wall -Wextra -g -c driver.c -o driver.o
gcc main.o driver.o -o myapp
```

`driver.h` 变了，而 `main.o` 和 `driver.o` 都依赖 `driver.h`，所以两个都重新编译了。这就是依赖关系图的威力——你不需要记住"哪些文件依赖这个头文件"，Makefile 帮你记着。

**清理编译产物**

```bash
$ make clean
# 预期输出
rm -f *.o myapp
```

### 4.3 用模式规则简化 Makefile

当项目文件变多时，给每个 `.c` 文件写一条规则会变得难以维护。模式规则可以让 Makefile 更简洁：

```bash
$ cat > Makefile << 'EOF'
CC = gcc
CFLAGS = -Wall -Wextra -g
OBJS = main.o driver.o

myapp: $(OBJS)
	$(CC) $^ -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o myapp

.PHONY: clean
EOF
```

这个 Makefile 只有十几行，但能管理任意数量的 `.c` 文件——只需要在 `OBJS` 变量里加上新的 `.o` 文件名就行。以后你的项目从 2 个文件变成 20 个文件，Makefile 结构不需要变，只改一行 `OBJS` 就够了。

这种"只改一个地方，其他自动适应"的设计，在嵌入式项目的构建系统中是基本操作——后面你在 imx-forge 项目里看到的 Kbuild 系统，也是类似的思路，只是规模更大。

---

## 练习题

走到这里，编译流程和 Makefile 的基本机制应该清楚了。下面几道题难度递进——第三题如果做出来了，说明你真的懂了。

**练习 31.1** ⭐（理解）

一个 C 文件包含 `#define MAX_SIZE 1024`。如果编译后运行时发现 `MAX_SIZE` 的值不对，你应该检查编译的哪个阶段？用什么命令查看中间结果？

> **提示**：宏是在哪一步被替换的？

**练习 31.2** ⭐⭐（应用）

写一个 Makefile，管理以下项目结构：

```
utils.c / utils.h   —— 工具函数
parser.c / parser.h —— 解析器，依赖 utils.h
main.c              —— 主程序，依赖 utils.h 和 parser.h
```

要求：
- 使用变量 `CC` 和 `CFLAGS`
- 使用模式规则 `%.o: %.c`
- 有 `clean` 目标
- 依赖关系要写对（头文件变了，依赖它的 `.o` 也要重新编译）

**练习 31.3** ⭐⭐⭐（思考）

`gcc -Wall` 并不包含所有可能的警告。查阅资料，找出至少两个 `-Wall` 不包含但 `-Wextra` 包含的警告类型。解释为什么它们没有被归入 `-Wall`——什么情况下合理的代码会触发这些警告？

---

## 本章回响

本章真正在做的事情，是建立两个核心认知：**编译不是一步魔法，而是一条四段流水线**；以及**Makefile 的本质是依赖关系图**。

编译的四段流水线——预处理、编译、汇编、链接——每一步都有独立的输出文件和检查手段。当你遇到编译问题时，可以精准定位到出问题的阶段，而不是面对一堆错误信息手足无措。`.i` 文件查宏展开，`.s` 文件查编译优化，`.o` 文件查符号表——每个阶段都有它专用的调试手段。

Makefile 是编译流程的自动化管理工具。它的核心思想是**依赖驱动的增量构建**：每个目标文件记录它依赖的源文件，源文件变了就重新编译对应的目标。这个思想在嵌入式开发中无处不在——从 Makefile 到 Yocto 的 BitBake，从内核的 Kbuild 系统到 Buildroot，底层都是同一套逻辑。

还记得开头那个问题吗——为什么 gcc 不能一步到位？现在你应该能回答了：技术上它可以，但"一步到位"剥夺了你检查中间过程的能力。在嵌入式开发中，你会无数次需要停在预处理阶段看宏展开、停在汇编阶段看优化结果、停在链接阶段排查符号冲突。理解四阶段，不是为了记流程，是为了在出问题时知道该看哪里。

下一章我们会把视角从"怎么编译"转到"怎么调试"——当你编译出来的程序跑崩了，GDB 是你的第一道防线。而 `-g` 选项生成的调试信息，就是 GDB 工作的燃料。

---

[← 上一章](../06-script/ch30-envvar.md)
[下一章 →](ch32-gdb.md)
