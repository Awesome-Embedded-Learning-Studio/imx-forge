---
title: insmod 底层流程
---

# `insmod` 底层全流程解剖：从用户命令到内核内存

## 为什么要写这一章

老实说，当我第一次使用`insmod`命令加载内核模块的时候，我觉得它就像个魔法工具——一句命令下去，模块就"神奇地"加载到内核里运行了。那时候我只知道`insmod mymodule.ko`就能工作，至于它背后到底发生了什么，我完全是一知半解。

但随着学习的深入，我发现这种"黑盒"理解是远远不够的。当你遇到"Unknown symbol"、"disagrees about version of symbol"、"relocation out of range"这些错误时，当你需要理解为什么模块加载后内存布局是那样的时，当你想要搞清楚符号版本校验到底在检查什么时——如果你不懂`insmod`的底层流程，就真的会抓瞎。

这一章的目标是让你对`insmod`有一个深入的、从源码层面的理解。我会结合linux-imx的实际源码，带你从系统调用入口一路走到模块在内核内存中运行的完整过程。这会是一段有点"硬核"的旅程，但相信我，当你理解了这一切之后，你对内核模块的认识会有质的飞跃。

## 准备工作：核心数据结构

在深入流程之前，我们先看看内核用来管理模块的核心数据结构。这些结构定义在`third_party/linux-imx/include/linux/module.h`中：

```c
struct module {
    /* 模块状态 */
    enum module_state state;

    /* 模块名称 */
    char name[MODULE_NAME_LEN];

    /* 模块内存区域 */
    struct module_memory mem[MOD_MEM_NUM_TYPES];

    /* 导出的符号 */
    const struct kernel_symbol *syms;
    const s32 *crcs;
    unsigned int num_syms;

    /* GPL-only导出的符号 */
    const struct kernel_symbol *gpl_syms;
    const s32 *gpl_crcs;
    unsigned int num_gpl_syms;

    /* 模块参数 */
    struct kernel_param *kp;
    unsigned int num_kp;

    /* 模块初始化和清理函数 */
    int (*init)(void);
    void (*exit)(void);

    /* ... 更多字段 ... */
};
```

在`third_party/linux-imx/kernel/module/internal.h`中定义了内存类型：

```c
enum mod_mem_type {
    MOD_TEXT = 0,          /* 可执行代码 */
    MOD_DATA,              /* 数据 */
    MOD_RODATA,            /* 只读数据 */
    MOD_RO_AFTER_INIT,     /* 初始化后变为只读的数据 */
    MOD_INIT_TEXT,         /* 初始化代码 */
    MOD_INIT_DATA,         /* 初始化数据 */
    MOD_INIT_RODATA,       /* 初始化只读数据 */
    MOD_MEM_NUM_TYPES,     /* 内存类型数量 */
};
```

## 从用户空间到内核空间：系统调用入口

当你执行`insmod mymodule.ko`时，这个命令最终会调用`init_module`系统调用。让我们看看内核中的入口点。

### 系统调用定义

在`third_party/linux-imx/kernel/module/main.c`的第3071行：

```c
SYSCALL_DEFINE3(init_module, void __user *, umod,
        unsigned long, len, const char __user *, uargs)
{
    int err;
    struct load_info info = { };

    err = may_init_module();
    if (err)
        return err;

    pr_debug("init_module: umod=%p, len=%lu, uargs=%p\n",
           umod, len, uargs);

    err = copy_module_from_user(umod, len, &info);
    if (err) {
        mod_stat_inc(&failed_kreads);
        mod_stat_add_long(len, &invalid_kread_bytes);
        return err;
    }

    return load_module(&info, uargs, 0);
}
```

这个系统调用做了几件事：
1. 检查是否有权限加载模块（`may_init_module()`）
2. 将模块文件从用户空间复制到内核空间（`copy_module_from_user()`）
3. 调用`load_module()`进行实际的加载

### `load_module()`：加载流程的总控

`load_module()`函数是整个模块加载流程的核心，它定义在`third_party/linux-imx/kernel/module/main.c`的第2817行左右。让我用流程图来展示这个函数的整体结构：

```
load_module()
    |
    +-- 1. 检查模块权限和签名
    +-- 2. 验证ELF格式和架构
    +-- 3. layout_and_allocate()  [阶段二：内存布局与分配]
    +-- 4. simplify_symbols()      [阶段四：符号解析]
    +-- 5. apply_relocations()     [阶段三：重定位]
    +-- 6. post_relocation()
    +-- 7. do_init_module()        [阶段五：初始化与释放init段]
```

让我们逐一分析每个阶段。

## 阶段二：内存布局与分配

### `layout_and_allocate()` 函数详解

这个函数负责计算模块的内存布局并分配内存。源码在`third_party/linux-imx/kernel/module/main.c`的第2373行：

```c
static struct module *layout_and_allocate(struct load_info *info, int flags)
{
    struct module *mod;
    unsigned int ndx;
    int err;

    /* 允许架构特定的section处理 */
    err = module_frob_arch_sections(info->hdr, info->sechdrs,
                    info->secstrings, info->mod);
    if (err < 0)
        return ERR_PTR(err);

    /* 强制rwx权限检查 */
    err = module_enforce_rwx_sections(info->hdr, info->sechdrs,
                      info->secstrings, info->mod);
    if (err < 0)
        return ERR_PTR(err);

    /* percpu section稍后单独处理 */
    info->sechdrs[info->index.pcpu].sh_flags &= ~(unsigned long)SHF_ALLOC;

    /* 标记ro_after_init section */
    ndx = find_sec(info, ".data..ro_after_init");
    if (ndx)
        info->sechdrs[ndx].sh_flags |= SHF_RO_AFTER_INIT;

    /* 计算section布局和总大小 */
    layout_sections(info->mod, info);
    layout_symtab(info->mod, info);

    /* 分配内存并移动到最终位置 */
    err = move_module(info->mod, info);
    if (err)
        return ERR_PTR(err);

    mod = (void *)info->sechdrs[info->index.mod].sh_addr;
    kmemleak_load_module(mod, info);
    return mod;
}
```

### `layout_sections()`：Section布局策略

这个函数在`third_party/linux-imx/kernel/module/main.c`的第1590行定义：

```c
static void layout_sections(struct module *mod, struct load_info *info)
{
    unsigned int i;

    for (i = 0; i < info->hdr->e_shnum; i++)
        info->sechdrs[i].sh_entsize = ~0UL;

    pr_debug("Core section allocation order for %s:\n", mod->name);
    __layout_sections(mod, info, false);  /* 非init段 */

    pr_debug("Init section allocation order for %s:\n", mod->name);
    __layout_sections(mod, info, true);   /* init段 */
}
```

`__layout_sections()`函数按照以下顺序布局sections：

```c
static const unsigned long masks[][2] = {
    /* 注意：所有可执行代码必须是第一个section */
    { SHF_EXECINSTR | SHF_ALLOC, ARCH_SHF_SMALL },
    { SHF_ALLOC, SHF_WRITE | ARCH_SHF_SMALL },
    { SHF_RO_AFTER_INIT | SHF_ALLOC, ARCH_SHF_SMALL },
    { SHF_WRITE | SHF_ALLOC, ARCH_SHF_SMALL },
    { ARCH_SHF_SMALL | SHF_ALLOC, 0 }
};

static const int core_m_to_mem_type[] = {
    MOD_TEXT,          /* 可执行代码 */
    MOD_RODATA,        /* 只读数据 */
    MOD_RO_AFTER_INIT, /* 初始化后只读 */
    MOD_DATA,          /* 数据 */
    MOD_DATA,
};

static const int init_m_to_mem_type[] = {
    MOD_INIT_TEXT,     /* 初始化代码 */
    MOD_INIT_RODATA,   /* 初始化只读数据 */
    MOD_INVALID,
    MOD_INIT_DATA,     /* 初始化数据 */
    MOD_INIT_DATA,
};
```

这个布局顺序很重要，它保证了：
1. 代码段在前面，便于指令缓存利用
2. 只读数据聚集在一起
3. 初始化段和持久段分离，便于后续释放

### `module_memory_alloc()`：实际的内存分配

在`third_party/linux-imx/kernel/module/main.c`的第1194行：

```c
static int module_memory_alloc(struct module *mod, enum mod_mem_type type)
{
    unsigned int size = PAGE_ALIGN(mod->mem[type].size);
    enum execmem_type execmem_type;
    void *ptr;

    mod->mem[type].size = size;

    if (mod_mem_type_is_data(type))
        execmem_type = EXECMEM_MODULE_DATA;
    else
        execmem_type = EXECMEM_MODULE_TEXT;

    ptr = execmem_alloc(execmem_type, size);
    if (!ptr)
        return -ENOMEM;

    /* 标记为非内存泄漏 */
    kmemleak_not_leak(ptr);

    memset(ptr, 0, size);
    mod->mem[type].base = ptr;

    return 0;
}
```

### ARM架构下的模块内存范围

对于ARM架构，模块加载在特定的虚拟地址范围内。这个范围定义在`third_party/linux-imx/arch/arm/include/asm/memory.h`的第60-77行：

```c
#ifdef CONFIG_XIP_KERNEL
/* XIP内核的模块空间：16MB */
#define MODULES_VADDR        (PAGE_OFFSET - SZ_16M)
#else
/* Thumb-2符号重定位使用较小的范围：8MB */
#define MODULES_VADDR        (PAGE_OFFSET - SZ_8M)
#endif

#if TASK_SIZE > MODULES_VADDR
#error Top of user space clashes with start of module space
#endif

/* 模块空间的结束地址 */
#ifdef CONFIG_HIGHMEM
#define MODULES_END        (PAGE_OFFSET - PMD_SIZE)
#else
#define MODULES_END        (PAGE_OFFSET)
#endif
```

对于i.MX6ULL（ARM Cortex-A7），默认情况下：
- 如果使用Thumb-2指令集（这是常见情况）：`MODULES_VADDR = PAGE_OFFSET - 8MB`
- 如果不使用Thumb-2：`MODULES_VADDR = PAGE_OFFSET - 16MB`

这里的`PAGE_OFFSET`通常是`0xC0000000`，所以模块空间大概在`0xBF800000`附近。

### ARM模块内存分配器

在`third_party/linux-imx/arch/arm/mm/init.c`的第505-525行，定义了ARM架构的模块内存分配器：

```c
static struct execmem_info execmem_info __ro_after_init;

static int __init init_execmem(void)
{
    /* 计算fallback区域 */
    unsigned long fallback_start = MODULES_VADDR;
    unsigned long fallback_end = MODULES_END;

    /* ... 省略XIP内核的处理 ... */

    execmem_info = (struct execmem_info) {
        .ranges = {
            {
                .start      = MODULES_VADDR,
                .end        = MODULES_END,
                .pgprot     = PAGE_KERNEL_EXEC,
                .alignment  = 1,
                .fallback_start  = fallback_start,
                .fallback_end    = fallback_end,
            },
        },
    };

    return 0;
}
```

## 阶段三：重定位（Relocation）

### 为什么模块需要重定位

当你编译一个内核模块时，编译器并不知道这个模块会被加载到哪个内存地址。因此，模块中的符号引用（比如函数调用、全局变量访问）都是相对于某个假设的基地址的。当模块被加载到实际的内存地址时，这些引用需要被修正——这个过程就叫重定位。

### `apply_relocations()` 函数详解

这个函数在`third_party/linux-imx/kernel/module/main.c`的第1465行定义：

```c
static int apply_relocations(struct module *mod, const struct load_info *info)
{
    unsigned int i;
    int err = 0;

    /* 遍历所有section */
    for (i = 1; i < info->hdr->e_shnum; i++) {
        unsigned int infosec = info->sechdrs[i].sh_info;

        /* 不是有效的重定位section */
        if (infosec >= info->hdr->e_shnum)
            continue;

        /* 跳过非分配的section */
        if (!(info->sechdrs[infosec].sh_flags & SHF_ALLOC))
            continue;

        /* Livepatch重定位 */
        if (info->sechdrs[i].sh_flags & SHF_RELA_LIVEPATCH)
            err = klp_apply_section_relocs(mod, info->sechdrs,
                           info->secstrings,
                           info->strtab,
                           info->index.sym, i,
                           NULL);
        /* REL类型重定位 */
        else if (info->sechdrs[i].sh_type == SHT_REL)
            err = apply_relocate(info->sechdrs, info->strtab,
                         info->index.sym, i, mod);
        /* RELA类型重定位（带显式加数） */
        else if (info->sechdrs[i].sh_type == SHT_RELA)
            err = apply_relocate_add(info->sechdrs, info->strtab,
                         info->index.sym, i, mod);
        if (err < 0)
            break;
    }
    return err;
}
```

### ARM特定重定位类型详解

ARM架构的重定位处理在`third_party/linux-imx/arch/arm/kernel/module.c`中实现。重定位类型定义在`third_party/linux-imx/arch/arm/include/asm/elf.h`的第50-65行：

```c
#define R_ARM_NONE        0  /* 无重定位 */
#define R_ARM_PC24        1  /* PC相对24位跳转 */
#define R_ARM_ABS32       2  /* 绝对32位地址 */
#define R_ARM_REL32       3  /* 相对32位地址 */
#define R_ARM_CALL        28 /* 函数调用（BL指令） */
#define R_ARM_JUMP24      29 /* 跳转（B指令） */
#define R_ARM_TARGET1     38 /* 目标特定 */
#define R_ARM_V4BX        40 /* ARMv4 BX指令转换 */
#define R_ARM_PREL31      42 /* PC相对31位 */
#define R_ARM_MOVW_ABS_NC 43 /* MOVW指令（立即数加载低位） */
#define R_ARM_MOVT_ABS    44 /* MOVT指令（立即数加载高位） */
#define R_ARM_MOVW_PREL_NC 45 /* MOVW PC相对 */
#define R_ARM_MOVT_PREL   46 /* MOVT PC相对 */
```

#### `R_ARM_ABS32`：绝对32位重定位

这是最简单的重定位类型，直接将符号的值加到目标位置：

```c
case R_ARM_ABS32:
case R_ARM_TARGET1:
    *(u32 *)loc += sym->st_value;
    break;
```

例如，如果你在模块中引用一个全局变量，编译器会生成一个`R_ARM_ABS32`重定位条目。加载时，内核会将这个变量的实际地址写入到指定位置。

#### `R_ARM_CALL`：函数调用重定位

这个重定位类型用于处理ARM的`BL`（Branch with Link）指令：

```c
case R_ARM_PC24:
case R_ARM_CALL:
case R_ARM_JUMP24:
    /* 检查ARM->Thumb的interworking */
    if (sym->st_value & 3) {
        pr_err("%s: unsupported interworking call (ARM -> Thumb)\n",
               module->name);
        return -ENOEXEC;
    }

    /* 提取并计算偏移 */
    offset = __mem_to_opcode_arm(*(u32 *)loc);
    offset = (offset & 0x00ffffff) << 2;
    offset = sign_extend32(offset, 25);

    offset += sym->st_value - loc;

    /* 如果偏移超出范围，使用PLT */
    if (IS_ENABLED(CONFIG_ARM_MODULE_PLTS) &&
        (offset <= (s32)0xfe000000 || offset >= (s32)0x02000000))
        offset = get_module_plt(module, loc, offset + loc + 8) - loc - 8;

    /* 检查范围 */
    if (offset <= (s32)0xfe000000 || offset >= (s32)0x02000000) {
        pr_err("%s: relocation %u out of range (%#lx -> %#x)\n",
               module->name, ELF32_R_TYPE(rel->r_info), loc, sym->st_value);
        return -ENOEXEC;
    }

    /* 写回结果 */
    offset >>= 2;
    offset &= 0x00ffffff;
    *(u32 *)loc &= __opcode_to_mem_arm(0xff000000);
    *(u32 *)loc |= __opcode_to_mem_arm(offset);
    break;
```

ARM的`BL`指令只能跳转±32MB的范围（实际上因为PC偏移是±24位左移2位，再+8，有效范围约±32MB）。如果目标函数超出这个范围，内核会使用PLT（Procedure Linkage Table）来间接跳转。

#### `R_ARM_REL32`：相对32位重定位

这种重定位用于存储相对于当前位置的偏移：

```c
case R_ARM_REL32:
    *(u32 *)loc += sym->st_value - loc;
    break;
```

这对于位置无关代码（PIC）很重要，因为它允许代码在加载到任何地址后都能正确运行。

#### `R_ARM_MOVW_ABS_NC` / `R_ARM_MOVT_ABS`：立即数加载重定位

ARM的`MOVW`和`MOVT`指令用于加载32位立即数。`MOVW`加载低16位，`MOVT`加载高16位：

```c
case R_ARM_MOVW_ABS_NC:
case R_ARM_MOVT_ABS:
case R_ARM_MOVW_PREL_NC:
case R_ARM_MOVT_PREL:
    offset = tmp = __mem_to_opcode_arm(*(u32 *)loc);
    offset = ((offset & 0xf0000) >> 4) | (offset & 0xfff);
    offset = sign_extend32(offset, 15);

    offset += sym->st_value;

    /* 处理PC相对的情况 */
    if (ELF32_R_TYPE(rel->r_info) == R_ARM_MOVT_PREL ||
        ELF32_R_TYPE(rel->r_info) == R_ARM_MOVW_PREL_NC)
        offset -= loc;

    /* MOVT处理高16位 */
    if (ELF32_R_TYPE(rel->r_info) == R_ARM_MOVT_ABS ||
        ELF32_R_TYPE(rel->r_info) == R_ARM_MOVT_PREL)
        offset >>= 16;

    tmp &= 0xfff0f000;
    tmp |= ((offset & 0xf000) << 4) | (offset & 0x0fff);

    *(u32 *)loc = __opcode_to_mem_arm(tmp);
    break;
```

### 重定位示例分析

假设你有一个模块，代码如下：

```c
extern int printk(const char *fmt, ...);

static void hello(void)
{
    printk("Hello\n");
}
```

编译后，对`printk`的调用会生成一个`R_ARM_CALL`重定位条目。模块加载时：

1. 内核在符号表中找到`printk`的地址（假设是`0xC0123456`）
2. 获取`hello`函数加载后的地址（假设是`0xBF800100`）
3. 计算偏移：`0xC0123456 - 0xBF800100 - 8 = 0x92334E`
4. 检查偏移是否在±32MB范围内
5. 将偏移编码到`BL`指令中

## 阶段四：符号解析与绑定

### 符号解析的必要性

当模块引用了它没有定义的符号时（比如内核函数或其他模块导出的符号），这些符号需要被解析——即找到这些符号的实际地址。

### `simplify_symbols()` 函数详解

这个函数在`third_party/linux-imx/kernel/module/main.c`的第1394行定义：

```c
static int simplify_symbols(struct module *mod, const struct load_info *info)
{
    Elf_Shdr *symsec = &info->sechdrs[info->index.sym];
    Elf_Sym *sym = (void *)symsec->sh_addr;
    unsigned long secbase;
    unsigned int i;
    int ret = 0;
    const struct kernel_symbol *ksym;

    for (i = 1; i < symsec->sh_size / sizeof(Elf_Sym); i++) {
        const char *name = info->strtab + sym[i].st_name;

        switch (sym[i].st_shndx) {
        case SHN_COMMON:
            /* 忽略common符号 */
            if (!strncmp(name, "__gnu_lto", 9))
                break;
            pr_warn("%s: please compile with -fno-common\n", mod->name);
            ret = -ENOEXEC;
            break;

        case SHN_ABS:
            /* 绝对符号，不需要处理 */
            pr_debug("Absolute symbol: 0x%08lx %s\n",
                 (long)sym[i].st_value, name);
            break;

        case SHN_LIVEPATCH:
            /* Livepatch符号由livepatch处理 */
            break;

        case SHN_UNDEF:
            /* 未定义符号，需要解析 */
            ksym = resolve_symbol_wait(mod, info, name);
            if (ksym && !IS_ERR(ksym)) {
                sym[i].st_value = kernel_symbol_value(ksym);
                break;
            }

            /* 弱符号或被忽略的符号 */
            if (!ksym &&
                (ELF_ST_BIND(sym[i].st_info) == STB_WEAK ||
                 ignore_undef_symbol(info->hdr->e_machine, name)))
                break;

            ret = PTR_ERR(ksym) ?: -ENOENT;
            pr_warn("%s: Unknown symbol %s (err %d)\n",
                mod->name, name, ret);
            break;

        default:
            /* 模块内部符号 */
            if (sym[i].st_shndx == info->index.pcpu)
                secbase = (unsigned long)mod_percpu(mod);
            else
                secbase = info->sechdrs[sym[i].st_shndx].sh_addr;
            sym[i].st_value += secbase;
            break;
        }
    }

    return ret;
}
```

### `find_symbol()` 的查找顺序

`find_symbol()`函数在`third_party/linux-imx/kernel/module/main.c`的第304行定义。它按照以下顺序查找符号：

```c
bool find_symbol(struct find_symbol_arg *fsa)
{
    static const struct symsearch arr[] = {
        /* 内核导出的符号（非GPL） */
        { __start___ksymtab, __stop___ksymtab, __start___kcrctab,
          NOT_GPL_ONLY },
        /* 内核导的GPL符号 */
        { __start___ksymtab_gpl, __stop___ksymtab_gpl,
          __start___kcrctab_gpl,
          GPL_ONLY },
    };
    struct module *mod;
    unsigned int i;

    module_assert_mutex_or_preempt();

    /* 1. 首先在内核符号表中查找 */
    for (i = 0; i < ARRAY_SIZE(arr); i++)
        if (find_exported_symbol_in_section(&arr[i], NULL, fsa))
            return true;

    /* 2. 然后在已加载模块的符号表中查找 */
    list_for_each_entry_rcu(mod, &modules, list,
                lockdep_is_held(&module_mutex)) {
        struct symsearch arr[] = {
            { mod->syms, mod->syms + mod->num_syms, mod->crcs,
              NOT_GPL_ONLY },
            { mod->gpl_syms, mod->gpl_syms + mod->num_gpl_syms,
              mod->gpl_crcs,
              GPL_ONLY },
        };

        if (mod->state == MODULE_STATE_UNFORMED)
            continue;

        for (i = 0; i < ARRAY_SIZE(arr); i++)
            if (find_exported_symbol_in_section(&arr[i], mod, fsa))
                return true;
    }

    pr_debug("Failed to find symbol %s\n", fsa->name);
    return false;
}
```

查找顺序总结：
1. 内核导出的符号（`__ksymtab`和`__ksymtab_gpl`）
2. 已加载模块导出的符号（按模块加载顺序）

### `resolve_symbol()` 函数详解

这个函数不仅查找符号，还进行版本校验和许可证检查：

```c
static const struct kernel_symbol *resolve_symbol(struct module *mod,
                          const struct load_info *info,
                          const char *name,
                          char ownername[])
{
    struct find_symbol_arg fsa = {
        .name  = name,
        .gplok = !(mod->taints & (1 << TAINT_PROPRIETARY_MODULE)),
        .warn  = true,
    };
    int err;

    mutex_lock(&module_mutex);
    if (!find_symbol(&fsa))
        goto unlock;

    if (fsa.license == GPL_ONLY)
        mod->using_gplonly_symbols = true;

    /* 检查taint继承 */
    if (!inherit_taint(mod, fsa.owner, name)) {
        fsa.sym = NULL;
        goto getname;
    }

    /* 版本校验 */
    if (!check_version(info, name, mod, fsa.crc)) {
        fsa.sym = ERR_PTR(-EINVAL);
        goto getname;
    }

    /* 命名空间校验 */
    err = verify_namespace_is_imported(info, fsa.sym, mod);
    if (err) {
        fsa.sym = ERR_PTR(err);
        goto getname;
    }

    /* 增加模块引用计数 */
    err = ref_module(mod, fsa.owner);
    if (err) {
        fsa.sym = ERR_PTR(err);
        goto getname;
    }

getname:
    strncpy(ownername, module_name(fsa.owner), MODULE_NAME_LEN);
unlock:
    mutex_unlock(&module_mutex);
    return fsa.sym;
}
```

### 符号版本（Versioning / CRC）校验机制详解

内核使用CRC（循环冗余校验）来确保模块和内核之间的接口兼容性。这个机制在`third_party/linux-imx/kernel/module/version.c`中实现。

#### `check_version()` 函数

```c
int check_version(const struct load_info *info,
          const char *symname,
             struct module *mod,
             const s32 *crc)
{
    Elf_Shdr *sechdrs = info->sechdrs;
    unsigned int versindex = info->index.vers;
    unsigned int i, num_versions;
    struct modversion_info *versions;

    /* 导出模块没有提供CRC？OK，内核已经被污染了 */
    if (!crc)
        return 1;

    /* 没有版本信息？modprobe --force会这样 */
    if (versindex == 0)
        return try_to_force_load(mod, symname) == 0;

    versions = (void *)sechdrs[versindex].sh_addr;
    num_versions = sechdrs[versindex].sh_size
        / sizeof(struct modversion_info);

    /* 遍历版本信息，查找匹配的符号 */
    for (i = 0; i < num_versions; i++) {
        u32 crcval;

        if (strcmp(versions[i].name, symname) != 0)
            continue;

        crcval = *crc;
        if (versions[i].crc == crcval)
            return 1;
        pr_debug("Found checksum %X vs module %lX\n",
             crcval, versions[i].crc);
        goto bad_version;
    }

    /* 工具链有问题。警告一次，然后放过 */
    pr_warn_once("%s: no symbol version for %s\n", info->name, symname);
    return 1;

bad_version:
    pr_warn("%s: disagrees about version of symbol %s\n", info->name, symname);
    return 0;
}
```

CRC校验的工作原理：
1. 编译模块时，对于每个引用的符号，计算其原型（函数签名）的CRC
2. 将这个CRC值记录在模块的`__versions` section中
3. 加载模块时，比较模块中记录的CRC和内核/导出模块提供的CRC
4. 如果不匹配，拒绝加载

#### `same_magic()` 函数

这个函数用于比较vermagic（版本魔数）：

```c
int same_magic(const char *amagic, const char *bmagic,
           bool has_crcs)
{
    if (has_crcs) {
        amagic += strcspn(amagic, " ");
        bmagic += strcspn(bmagic, " ");
    }
    return strcmp(amagic, bmagic) == 0;
}
```

VerMagic包含内核版本、编译器版本、SMP配置等信息，例如：
```
6.12.49-g12345678-dirty SMP preempt mod_unload modversions aarch64
```

#### CRC校验失败的处理

当CRC校验失败时，你会看到这样的错误：

```
module: disagrees about version of symbol printk
module: version magic '6.12.49-g12345678 SMP preempt' should be '6.12.48-g87654321 SMP'
```

处理方法：
1. 重新编译模块（使用与运行内核相同的源码）
2. 使用`modprobe --force`（不推荐，可能导致内核崩溃）
3. 使用`--force-vermagic`选项

## 阶段五补充：init段内存释放

### `init` 段内存的释放时机

模块的`init`段包含初始化代码和数据，这些代码在模块初始化完成后就不再需要了。内核会自动释放这些内存以节省资源。

### `do_init_module()` 函数

这个函数在`third_party/linux-imx/kernel/module/main.c`的第2516行定义：

```c
static noinline int do_init_module(struct module *mod)
{
    int ret = 0;
    struct mod_initfree *freeinit;

    /* ... 省略部分代码 ... */

    /* 调用模块的init函数 */
    ret = mod->init();
    if (ret < 0)
        goto fail;

    /* ... 省略部分代码 ... */

    /*
     * 我们想要释放init段，但要防止其他人仍然在模块列表中遍历。
     * 因此，使用工作队列延迟释放。
     */
    freeinit = kmalloc(sizeof(*freeinit), GFP_KERNEL);
    if (!freeinit) {
        /* 没有内存，就不释放了 */
        ret = -ENOMEM;
        goto fail;
    }

    freeinit->init_text = mod->mem[MOD_INIT_TEXT].base;
    freeinit->init_data = mod->mem[MOD_INIT_DATA].base;
    freeinit->init_rodata = mod->mem[MOD_INIT_RODATA].base;

    /*
     * 将init内存标记为无效，这样后续访问会失败。
     * 注意：execmem_alloc()在大多数架构上创建W+X页映射，
     * 这些映射在do_free_init()运行前不会被清理。
     */
    if (llist_add(&freeinit->node, &init_free_list))
        schedule_work(&init_free_wq);

    /* ... 省略部分代码 ... */

    return 0;

fail:
    /* ... 错误处理 ... */
}
```

### `do_free_init()` 函数

这是实际释放init内存的工作队列函数：

```c
static void do_free_init(struct work_struct *w)
{
    struct llist_node *pos, *n, *list;
    struct mod_initfree *initfree;

    list = llist_del_all(&init_free_list);

    /* 等待RCU grace period，确保没有人还在访问 */
    synchronize_rcu();

    llist_for_each_safe(pos, n, list) {
        initfree = container_of(pos, struct mod_initfree, node);
        execmem_free(initfree->init_text);
        execmem_free(initfree->init_data);
        execmem_free(initfree->init_rodata);
        kfree(initfree);
    }
}
```

### 为什么可以释放init段内存

init段内存可以安全释放的原因：
1. **执行完成**：`module_init()`函数已经执行完毕
2. **不再引用**：初始化完成后，内核不会再调用这些代码
3. **RCU保护**：使用RCU机制确保没有其他CPU还在访问这些内存

释放init段的好处：
1. **节省内存**：对于小型嵌入式系统很重要
2. **减少攻击面**：初始化代码不再驻留在内存中

## 完整可编译代码示例

下面是一个面向IMX6ULL的示例模块，展示了模块加载的各个阶段：

```c
// SPDX-License-Identifier: GPL-2.0
/*
 * insmod internals example module
 * 面向i.MX6ULL (ARM Cortex-A7)
 *
 * 编译命令：
 * arm-linux-gnueabihf-gcc -Wall -Wextra -O2 -D__KERNEL__ \
 *     -I/path/to/kernel/include \
 *     -fno-strict-aliasing -fno-common -fno-delete-null-pointer-checks \
 *     -fno-stack-protector -ffreestanding \
 *     -c insmod_example.c -o insmod_example.o
 * arm-linux-gnueabihf-ld -r insmod_example.o -o insmod_example.ko
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/printk.h>
#include <linux/sysfs.h>
#include <linux/kobject.h>

/* 模块参数 */
static int debug_level = 0;
module_param(debug_level, int, 0644);
MODULE_PARM_DESC(debug_level, "Debug level (0-3)");

static char *greeting = "Hello";
module_param(greeting, charp, 0644);
MODULE_PARM_DESC(greeting, "Greeting message");

/* 全局变量，用于演示重定位 */
static int global_counter = 0;

/* 导出符号，供其他模块使用 */
EXPORT_SYMBOL(global_counter);

/* Init段数据 - 初始化后释放 */
static int __initdata init_only_var = 42;

/*
 * 演示重定位的函数 - 内部调用
 */
static void internal_function(void)
{
    pr_info("insmod_example: internal_function called\n");
    global_counter++;
}

/*
 * 模块初始化函数 - 标记为__init，会被放入.init.text段
 *
 * 这个函数在模块加载时调用一次，执行完后
 * 所在的内存段会被释放。
 */
static int __init insmod_example_init(void)
{
    pr_info("========== insmod_example module loading ==========\n");
    pr_info("insmod_example: init function address: %px\n",
        insmod_example_init);
    pr_info("insmod_example: greeting parameter: %s\n", greeting);
    pr_info("insmod_example: debug_level parameter: %d\n", debug_level);
    pr_info("insmod_example: init_only_var: %d (will be freed)\n",
        init_only_var);

    /* 调用内部函数，演示R_ARM_CALL重定位 */
    internal_function();

    /* 打印模块信息 */
    pr_info("insmod_example: THIS_MODULE: %px\n", THIS_MODULE);
    pr_info("insmod_example: module name: %s\n", THIS_MODULE->name);
    pr_info("insmod_example: module state: %d\n", THIS_MODULE->state);

    /*
     * THIS_MODULE->state的可能值：
     * 0 = MODULE_STATE_LIVE (正常运行)
     * 1 = MODULE_STATE_COMING (正在加载)
     * 2 = MODULE_STATE_GOING (正在卸载)
     * 3 = MODULE_STATE_UNFORMED (未形成)
     */

    pr_info("========== insmod_example init complete ==========\n");
    return 0;
}

/*
 * 模块清理函数
 *
 * 注意：这个函数不在init段，会一直驻留在内存中
 */
static void __exit insmod_example_exit(void)
{
    pr_info("========== insmod_example module unloading ==========\n");
    pr_info("insmod_example: global_counter final value: %d\n",
        global_counter);
    pr_info("========== insmod_example exit complete ==========\n");
}

/* 注册模块的入口和出口点 */
module_init(insmod_example_init);
module_exit(insmod_example_exit);

/* 模块元数据 */
MODULE_AUTHOR("IMX-Forge Tutorial");
MODULE_DESCRIPTION("Example module demonstrating insmod internals");
MODULE_LICENSE("GPL v2");
MODULE_VERSION("1.0");

/* 模块别名 */
MODULE_ALIAS("insmod_example_alias");
```

### Makefile示例

```makefile
# insmod_example模块的Makefile
# 面向i.MX6ULL平台

# 内核源码路径
KERNEL_SRC := /path/to/linux-imx
ARCH := arm
CROSS_COMPILE := arm-linux-gnueabihf-

# 模块名称
obj-m := insmod_example.o

# 编译目标
all:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KERNEL_SRC) M=$(PWD) modules

clean:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KERNEL_SRC) M=$(PWD) clean

# 帮助目标
help:
	@echo "Usage:"
	@echo "  make          - 编译模块"
	@@echo "  make clean    - 清理编译产物"

.PHONY: all clean help
```

## 常见错误、调试方法与内核报错解读

### 错误1：Unknown symbol

```
insmod: ERROR: could not insert module insmod_example.ko: Unknown symbol
```

**原因**：模块引用了不存在的符号

**排查方法**：
```bash
# 查看模块引用的符号
arm-linux-gnueabihf-nm insmod_example.ko | grep U

# 查看内核导出的符号
cat /proc/kallsyms | grep printk

# 使用modinfo查看模块依赖
modinfo insmod_example.ko
```

**解决方法**：
1. 确保所有引用的符号都已导出
2. 加载依赖的模块
3. 检查符号名称拼写

### 错误2：disagrees about version of symbol

```
insmod_example: disagrees about version of symbol module_layout
insmod: ERROR: could not insert module insmod_example.ko: Invalid parameters
```

**原因**：CRC校验失败，模块和内核版本不匹配

**排查方法**：
```bash
# 查看模块的vermagic
modinfo -F vermagic insmod_example.ko

# 查看运行内核的版本
uname -r

# 查看内核版本字符串
cat /proc/version
```

**解决方法**：
1. 使用与运行内核相同的源码重新编译模块
2. 或使用`--force-vermagic`（不推荐）

### 错误3：relocation out of range

```
insmod_example: relocation type 2 out of range
insmod: ERROR: could not insert module insmod_example.ko: Invalid parameters
```

**原因**：ARM的相对跳转超出±32MB范围

**解决方案**：
1. 启用`CONFIG_ARM_MODULE_PLTS`
2. 减小模块大小
3. 调整内存布局

### 错误4：Execution permissions

```
insmod: ERROR: could not insert module insmod_example.ko: Exec format error
```

**可能原因**：
1. 模块架构不匹配（在x86上编译了ARM模块）
2. 内核版本不兼容

**排查方法**：
```bash
# 检查ELF架构
readelf -h insmod_example.ko | grep Machine

# 应该显示：Machine: ARM
```

### 调试技巧

#### 1. 启用模块加载调试

```bash
# 在内核命令行中添加
module.debug=1

# 或在运行时
echo 1 > /proc/sys/kernel/modprobe_debug
```

#### 2. 使用ftrace跟踪

```bash
# 跟踪模块加载函数
echo function > current_tracer
echo do_init_module > set_ftrace_filter
cat trace_pipe
```

#### 3. 查看模块内存布局

```bash
# 查看加载的模块地址
cat /proc/modules | head -20

# 查看模块内存段
cat /sys/module/insmod_example/sections/*
```

## 练习题与实战代码查看

### 练习1：理解重定位

**题目**：编写一个简单的模块，包含一个函数指针，它指向内核的`printk`函数。编译后，使用`readelf -r`查看重定位条目，并解释每种重定位类型的含义。

**参考答案**：

```c
// relocation_example.c
#include <linux/module.h>
#include <linux/kernel.h>

static void (*printk_ptr)(const char *fmt, ...) = printk;

static int __init relocation_init(void)
{
    printk_ptr("Hello from function pointer!\n");
    return 0;
}

static void __exit relocation_exit(void)
{
    printk_ptr("Goodbye from function pointer!\n");
}

module_init(relocation_init);
module_exit(relocation_exit);
MODULE_LICENSE("GPL");
```

查看重定位：
```bash
readelf -r relocation_example.ko
```

你应该能看到类似这样的输出：
```
Relocation section '.rel.text' at offset 0x1bc contains 2 entries:
  Offset     Info    Type            Sym.Value  Sym. Name
00000000  00000602 R_ARM_ABS32       00000000   printk_ptr
00000004  00000802 R_ARM_ABS32       00000000   printk
```

### 练习2：符号导出与引用

**题目**：编写两个模块A和B。模块A导出一个函数，模块B调用这个函数。验证模块之间的符号依赖关系。

**模块A（symbol_exporter.c）**：

```c
#include <linux/module.h>
#include <linux/kernel.h>

int exported_function(int x)
{
    pr_info("exported_function called with %d\n", x);
    return x * 2;
}
EXPORT_SYMBOL(exported_function);

static int __init exporter_init(void)
{
    pr_info("symbol_exporter module loaded\n");
    return 0;
}

static void __exit exporter_exit(void)
{
    pr_info("symbol_exporter module unloaded\n");
}

module_init(exporter_init);
module_exit(exporter_exit);
MODULE_LICENSE("GPL");
```

**模块B（symbol_user.c）**：

```c
#include <linux/module.h>
#include <linux/kernel.h>

extern int exported_function(int x);

static int __init user_init(void)
{
    int result = exported_function(21);
    pr_info("exported_function(21) = %d\n", result);
    return 0;
}

static void __exit user_exit(void)
{
    pr_info("symbol_user module unloaded\n");
}

module_init(user_init);
module_exit(user_exit);
MODULE_LICENSE("GPL");
```

验证步骤：
```bash
# 先加载A
insmod symbol_exporter.ko

# 查看导出的符号
cat /proc/kallsyms | grep exported_function

# 加载B
insmod symbol_user.ko

# 查看模块依赖
cat /sys/module/symbol_user/holders/*

# 卸载顺序（会失败，因为B依赖A）
rmmod symbol_exporter  # 失败
rmmod symbol_user      # 成功
rmmod symbol_exporter  # 成功
```

### 练习3：内存布局分析

**题目**：编写一个模块，在init函数中打印出模块各个section的地址范围。比较`/sys/module/<name>/sections/`中的信息。

**参考代码**：

```c
// layout_example.c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

/* 声明外部符号，用于查看地址 */
extern char __start_rodata[];
extern char __end_rodata[];

static int __init layout_init(void)
{
    pr_info("Module: %s\n", THIS_MODULE->name);
    pr_info("Module size: %lu bytes\n",
            THIS_MODULE->mem[MOD_TEXT].size +
            THIS_MODULE->mem[MOD_DATA].size +
            THIS_MODULE->mem[MOD_RODATA].size);

    pr_info("Text section:   %px - %px (size: %lu)\n",
            THIS_MODULE->mem[MOD_TEXT].base,
            THIS_MODULE->mem[MOD_TEXT].base + THIS_MODULE->mem[MOD_TEXT].size,
            THIS_MODULE->mem[MOD_TEXT].size);

    pr_info("Data section:   %px - %px (size: %lu)\n",
            THIS_MODULE->mem[MOD_DATA].base,
            THIS_MODULE->mem[MOD_DATA].base + THIS_MODULE->mem[MOD_DATA].size,
            THIS_MODULE->mem[MOD_DATA].size);

    pr_info("Rodata section: %px - %px (size: %lu)\n",
            THIS_MODULE->mem[MOD_RODATA].base,
            THIS_MODULE->mem[MOD_RODATA].base + THIS_MODULE->mem[MOD_RODATA].size,
            THIS_MODULE->mem[MOD_RODATA].size);

    pr_info("Init text:      %px (size: %lu)\n",
            THIS_MODULE->mem[MOD_INIT_TEXT].base,
            THIS_MODULE->mem[MOD_INIT_TEXT].size);

    return 0;
}

static void __exit layout_exit(void)
{
    pr_info("Layout example unloaded\n");
}

module_init(layout_init);
module_exit(layout_exit);
MODULE_LICENSE("GPL");
```

### 练习4：Init段释放验证

**题目**：编写一个模块，在init函数中打印init段变量的地址，然后在模块正常运行后尝试访问这个地址（故意制造bug），观察内核行为。

**参考代码**：

```c
// init_free_example.c
#include <linux/module.h>
#include <linux/kernel.h>

/* Init段变量 - 初始化后释放 */
static int __initdata init_value = 12345;

/* 保存init变量的地址，用于演示 */
static int *saved_init_ptr;

static int __init init_free_init(void)
{
    pr_info("init_value address: %px, value: %d\n", &init_value, init_value);
    saved_init_ptr = &init_value;
    pr_info("saved_init_ptr: %px\n", saved_init_ptr);
    return 0;
}

static void __exit init_free_exit(void)
{
    /* 这里访问已释放的内存 - 可能导致崩溃 */
    pr_info("Attempting to access freed init memory...\n");
    pr_info("Value at saved_init_ptr: %d\n", *saved_init_ptr);
    pr_info("If you see this, the memory is still accessible\n");
}

module_init(init_free_init);
module_exit(init_free_exit);
MODULE_LICENSE("GPL");
```

注意：这个例子可能导致内核崩溃，仅供学习使用。

### 练习5：CRC校验实验

**题目**：手动修改模块的CRC值，观察加载时的错误信息。

**步骤**：

1. 编译一个模块
2. 使用`modinfo`查看模块的CRC：
   ```bash
   modinfo -F srcversion mymodule.ko
   ```
3. 使用十六进制编辑器修改CRC
4. 尝试加载模块，观察错误

## 实战代码查看路径

在`third_party/linux-imx`源码中，相关文件路径如下：

| 功能 | 文件路径 |
|------|----------|
| 模块加载主逻辑 | `kernel/module/main.c` |
| 符号版本校验 | `kernel/module/version.c` |
| ARM重定位处理 | `arch/arm/kernel/module.c` |
| ARM模块定义 | `arch/arm/include/asm/module.h` |
| ARM重定位类型 | `arch/arm/include/asm/elf.h` |
| ARM内存布局 | `arch/arm/include/asm/memory.h` |
| ARM模块内存分配 | `arch/arm/mm/init.c` |
| ELF定义 | `include/uapi/linux/elf.h` |
| 模块结构定义 | `include/linux/module.h` |
| 模块加载器接口 | `include/linux/moduleloader.h` |

## 下一章预告

到这里，你应该对`insmod`的底层全流程有了一个深入的理解：从系统调用入口，到内存布局与分配，到重定位处理，到符号解析与版本校验，最后到init段的释放。

但模块加载的故事还没有结束。下一篇文章，我们将会深入`struct module`结构体，看看这个核心数据结构是如何管理模块生命周期的。你会看到：
- `struct module`的完整字段定义
- 模块状态机的转换
- 模块引用计数的管理
- 模块间的依赖关系图

准备好了吗？我们继续深入内核模块的世界。
