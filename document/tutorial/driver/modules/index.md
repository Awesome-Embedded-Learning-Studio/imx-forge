<PageHeader icon="🧩" title="内核模块开发" description="Linux 内核模块 (LKM) 是动态加载到内核的代码，是驱动开发的基础" />

## 章节目录

<ChapterNav>
  <ChapterLink num="00" href="00_module_overview">模块概述</ChapterLink>
  <ChapterLink num="01" href="01_hello_world_module">Hello World 模块</ChapterLink>
  <ChapterLink num="02" href="02_module_build_and_load">编译与加载</ChapterLink>
  <ChapterLink num="03" href="03_module_params_and_debug">模块参数与调试</ChapterLink>
  <ChapterLink num="04" href="04_elf_and_ko_structure">ELF 与 KO 结构</ChapterLink>
  <ChapterLink num="05" href="05_insmod_internals_advanced">insmod 内部机制</ChapterLink>
  <ChapterLink num="06" href="06_struct_module_deep_dive">struct module 深入</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解内核模块的概念和作用，编写 Hello World 模块，掌握编译加载和参数传递机制。
:::

::: info 前置知识
C 语言基础 · Linux 基本操作 · Makefile 基础
:::

::: details 快速开始：最简内核模块
```c
// hello.c
#include <linux/module.h>
#include <linux/kernel.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("A simple Hello World module");

static int __init hello_init(void)
{
    printk(KERN_INFO "Hello, World!\n");
    return 0;
}

static void __exit hello_exit(void)
{
    printk(KERN_INFO "Goodbye, World!\n");
}

module_init(hello_init);
module_exit(hello_exit);
```

```makefile
obj-m += hello.o

all:
    make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
    make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
```
:::

::: details 延伸阅读
- [Linux 内核模块编程指南](https://sysprog21.github.io/lkmpg/)
- [内核模块文档](https://www.kernel.org/doc/html/latest/kbuild/)
:::

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回驱动开发</ChapterLink>
</ChapterNav>
