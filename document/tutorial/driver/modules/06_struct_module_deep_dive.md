---
title: struct module 解析
---

# struct module 深度解析：内核模块的核心数据结构

> **适用平台**：i.MX6ULL (ARM Cortex-A7)
> **内核版本**：Linux 6.12.49 (linux-imx)
> **目标读者**：准备入门驱动开发的嵌入式工程师
> **前置知识**：已阅读前面章节，了解模块加载基本流程

---

## 为什么要写这一章

在前面几章中，我们学习了模块的基本概念、编写方法和加载流程。但是，有一个核心问题我们还没有深入探讨：内核到底是用什么数据结构来描述一个模块的？

`struct module` 是内核模块系统的核心数据结构。理解它的每一个字段，不仅能帮你更好地理解模块的工作原理，还能在调试问题时快速定位原因。比如，当你遇到"Module is in use"错误时，你知道是 `refcnt` 字段在作怪；当你需要在内核中遍历所有模块时，你知道 `modules` 链表就是入口。

这一章，我们结合 linux-imx 6.12.49 的实际源码，对 `struct module` 进行一次彻底的剖析。

---

## 一、rmmod 底层全流程（补充）

在深入 `struct module` 之前，让我们先把模块卸载的完整流程理清楚，这样能更好地理解后续的字段含义。

### 1.1 delete_module 系统调用

当你执行 `rmmod` 命令时，最终会调用 `delete_module` 系统调用。这个系统调用的实现在 `kernel/module/main.c:700`：

```c
/* third_party/linux-imx/kernel/module/main.c:700 */
SYSCALL_DEFINE2(delete_module, const char __user *, name_user,
		unsigned int, flags)
{
	struct module *mod;
	char name[MODULE_NAME_LEN];
	char buf[MODULE_FLAGS_BUF_SIZE];
	int ret, len, forced = 0;

	/* 1. 权限检查：需要 CAP_SYS_MODULE 权限 */
	if (!capable(CAP_SYS_MODULE) || modules_disabled)
		return -EPERM;

	/* 2. 从用户空间复制模块名 */
	len = strncpy_from_user(name, name_user, MODULE_NAME_LEN);
	if (len == 0 || len == MODULE_NAME_LEN)
		return -ENOENT;
	if (len < 0)
		return len;

	/* 3. 审计日志 */
	audit_log_kern_module(name);

	/* 4. 获取模块互斥锁 */
	if (mutex_lock_interruptible(&module_mutex) != 0)
		return -EINTR;

	/* 5. 查找模块 */
	mod = find_module(name);
	if (!mod) {
		ret = -ENOENT;
		goto out;
	}

	/* 6. 检查是否有其他模块依赖我们 */
	if (!list_empty(&mod->source_list)) {
		/* Other modules depend on us: get rid of them first. */
		ret = -EWOULDBLOCK;
		goto out;
	}

	/* 7. 检查模块状态 */
	if (mod->state != MODULE_STATE_LIVE) {
		/* FIXME: if (force), slam module count damn the torpedoes */
		pr_debug("%s already dying\n", mod->name);
		ret = -EBUSY;
		goto out;
	}

	/* 8. 检查是否有 exit 函数 */
	if (mod->init && !mod->exit) {
		forced = try_force_unload(flags);
		if (!forced) {
			/* This module can't be removed */
			ret = -EBUSY;
			goto out;
		}
	}

	/* 9. 尝试停止模块（核心函数！） */
	ret = try_stop_module(mod, flags, &forced);
	if (ret != 0)
		goto out;

	/* 10. 释放锁，执行最后的清理 */
	mutex_unlock(&module_mutex);
	/* Final destruction now no one is using it. */
	if (mod->exit != NULL)
		mod->exit();
	blocking_notifier_call_chain(&module_notify_list,
				     MODULE_STATE_GOING, mod);
	klp_module_going(mod);
	ftrace_release_mod(mod);

	async_synchronize_full();

	/* Store the name and taints of the last unloaded module */
	strscpy(last_unloaded_module.name, mod->name, sizeof(last_unloaded_module.name));
	strscpy(last_unloaded_module.taints, module_flags(mod, buf, false), sizeof(last_unloaded_module.taints));

	/* 11. 释放模块内存 */
	free_module(mod);
	/* someone could wait for the module in add_unformed_module() */
	wake_up_all(&module_wq);
	return 0;
out:
	mutex_unlock(&module_mutex);
	return ret;
}
```

### 1.2 try_stop_module 函数详解

`try_stop_module()` 是模块卸载的核心函数，负责处理引用计数和状态转换。实现在 `kernel/module/main.c:668`：

```c
/* third_party/linux-imx/kernel/module/main.c:668 */
static int try_stop_module(struct module *mod, int flags, int *forced)
{
	/* 如果模块还被引用，必须使用强制卸载 */
	if (try_release_module_ref(mod) != 0) {
		*forced = try_force_unload(flags);
		if (!(*forced))
			return -EWOULDBLOCK;
	}

	/* 标记模块为 GOING 状态 */
	mod->state = MODULE_STATE_GOING;

	return 0;
}
```

### 1.3 free_module 函数：模块内存释放

`free_module()` 负责释放模块占用的所有资源。实现在 `kernel/module/main.c:1261`：

```c
/* third_party/linux-imx/kernel/module/main.c:1261 */
static void free_module(struct module *mod)
{
	bool unload_codetags;

	trace_module_free(mod);

	/* 1. 检查并卸载代码标签 */
	unload_codetags = codetag_unload_module(mod);
	if (!unload_codetags)
		pr_warn("%s: memory allocation(s) from the module still alive, cannot unload cleanly\n",
			mod->name);

	/* 2. 拆除 sysfs 接口 */
	mod_sysfs_teardown(mod);

	/* 3. 设置为 UNFORMED 状态 */
	mutex_lock(&module_mutex);
	mod->state = MODULE_STATE_UNFORMED;
	mutex_unlock(&module_mutex);

	/* 4. 架构特定的清理 */
	module_arch_cleanup(mod);

	/* 5. 模块卸载相关清理 */
	module_unload_free(mod);

	/* 6. 销毁模块参数 */
	destroy_params(mod->kp, mod->num_kp);

	/* 7. 如果是 livepatch 模块，释放 ELF 信息 */
	if (is_livepatch_module(mod))
		free_module_elf(mod);

	/* 8. 从模块链表和树中移除 */
	mutex_lock(&module_mutex);
	list_del_rcu(&mod->list);
	mod_tree_remove(mod);
	module_bug_cleanup(mod);
	synchronize_rcu();
	if (try_add_tainted_module(mod))
		pr_err("%s: adding tainted module to the unloaded tainted modules list failed.\n",
		       mod->name);
	mutex_unlock(&module_mutex);

	/* 9. 释放初始化段内存和参数 */
	module_arch_freeing_init(mod);
	kfree(mod->args);
	percpu_modfree(mod);

	/* 10. 释放模块内存 */
	free_mod_mem(mod, unload_codetags);
}
```

### 1.4 强制卸载（rmmod -f）的风险

强制卸载（使用 `O_TRUNC` 标志）是非常危险的操作，可能导致：

1. **系统崩溃**：如果模块代码仍在执行
2. **数据损坏**：如果模块持有的数据结构还在被使用
3. **资源泄漏**：模块无法正常清理资源

内核文档 `Documentation/kbuild/modules.rst` 中明确警告不要使用强制卸载。

### 1.5 MODULE_STATE_GOING 状态处理

当一个模块进入 `MODULE_STATE_GOING` 状态时：

1. 新的 `try_module_get()` 调用会失败
2. 内核不再允许其他模块依赖它
3. sysfs 中的模块状态会更新
4. 通知链会收到 `MODULE_STATE_GOING` 通知

---

## 二、struct module 数据结构全字段解析

现在让我们逐字段分析 `struct module` 结构。这个结构定义在 `include/linux/module.h:410`：

```c
/* third_party/linux-imx/include/linux/module.h:410 */
struct module {
	enum module_state state;
	struct list_head list;
	char name[MODULE_NAME_LEN];
	/* ... 更多字段 ... */
};
```

### 2.1 状态与标识字段

#### state：模块状态

```c
enum module_state {
	MODULE_STATE_LIVE,      /* 正常运行状态 */
	MODULE_STATE_COMING,    /* 正在初始化 */
	MODULE_STATE_GOING,     /* 正在卸载 */
	MODULE_STATE_UNFORMED,  /* 还在设置中 */
};
```

**状态转换图**：

```
                    加载模块
                       ↓
                  UNFORMED
                       ↓
                  COMING (执行 init 函数)
                       ↓
                  LIVE (正常运行)
                       ↓
                  GOING (执行 exit 函数)
                       ↓
                  UNFORMED (清理中)
                       ↓
                     (释放)
```

**源码位置**：`include/linux/module.h:320`

#### list：全局模块链表节点

```c
struct list_head list;
```

这个字段将所有已加载的模块链接到全局的 `modules` 链表。定义在 `kernel/module/main.c:76`：

```c
/* third_party/linux-imx/kernel/module/main.c:76 */
DEFINE_MUTEX(module_mutex);
LIST_HEAD(modules);
```

**遍历所有模块的示例**：

```c
/* 遍历所有已加载模块 */
struct module *mod;
mutex_lock(&module_mutex);
list_for_each_entry(mod, &modules, list) {
    pr_info("Module: %s, state: %d, refcnt: %d\n",
            mod->name, mod->state,
            atomic_read(&mod->refcnt));
}
mutex_unlock(&module_mutex);
```

#### name：模块名称

```c
char name[MODULE_NAME_LEN];
```

模块的唯一标识符，长度限制为 `MAX_PARAM_PREFIX_LEN`（通常为 64 字符）。

**源码位置**：`include/linux/module.h:35`、`:417`

### 2.2 符号导出字段

#### syms / num_syms：导出符号

```c
/* Exported symbols */
const struct kernel_symbol *syms;
const s32 *crcs;
unsigned int num_syms;
```

这些字段描述模块导出的符号：

- `syms`：导出符号数组（使用 `EXPORT_SYMBOL` 导出）
- `crcs`：对应的 CRC 校验值数组
- `num_syms`：导出符号的数量

**struct kernel_symbol 定义**（`include/linux/export.h`）：

```c
struct kernel_symbol {
	unsigned long value;
	const char *name;
};
```

#### gpl_syms / num_gpl_syms：GPL 符号

```c
/* GPL-only exported symbols. */
unsigned int num_gpl_syms;
const struct kernel_symbol *gpl_syms;
const s32 *gpl_crcs;
bool using_gplonly_symbols;
```

这些字段用于 `EXPORT_SYMBOL_GPL` 导出的符号。只有声明为 GPL 许可证的模块才能使用这些符号。

### 2.3 生命周期函数字段

#### init / exit：初始化和清理函数

```c
/* Startup function. */
int (*init)(void);

/* 在 CONFIG_MODULE_UNLOAD 下定义 */
void (*exit)(void);
```

- `init`：模块加载时调用的初始化函数（通过 `module_init()` 注册）
- `exit`：模块卸载时调用的清理函数（通过 `module_exit()` 注册）

**重要**：如果模块定义了 `init` 函数但没有 `exit` 函数，模块将无法被卸载（除非强制卸载）。

### 2.4 引用计数字段

#### refcnt：引用计数

```c
/* 在 CONFIG_MODULE_UNLOAD 下定义 */
atomic_t refcnt;
```

**源码位置**：`include/linux/module.h:582`

引用计数跟踪有多少内核组件正在使用这个模块。当 `refcnt > 0` 时，模块无法被卸载。

**关键函数**：

```c
/* 增加引用计数 */
int try_module_get(struct module *mod);

/* 减少引用计数 */
void module_put(struct module *mod);

/* 获取当前引用计数 */
int module_refcount(struct module *mod);
```

**try_module_get 实现**（`kernel/module/main.c:1014`）：

```c
/* third_party/linux-imx/kernel/module/main.c:1014 */
bool try_module_get(struct module *mod)
{
	if (IS_ENABLED(CONFIG_MODULE_UNLOAD) && mod) {
		preempt_disable();
		/* 检查模块是否正在卸载 */
		if (likely(atomic_read(&mod->refcnt) != MODULE_REF_BASE)) {
			/* 增加引用计数 */
			__module_get(mod);
			preempt_enable();
			return true;
		}
		preempt_enable();
		return false;
	}
	return true;
}
EXPORT_SYMBOL(try_module_get);
```

### 2.5 sysfs 相关字段

#### mkobj：模块 kobject

```c
/* Sysfs stuff. */
struct module_kobject mkobj;
```

**struct module_kobject 定义**（`include/linux/module.h:45`）：

```c
struct module_kobject {
	struct kobject kobj;              /* 内嵌的 kobject */
	struct module *mod;               /* 指向父模块 */
	struct kobject *drivers_dir;      /* 驱动目录 */
	struct module_param_attrs *mp;    /* 参数属性 */
	struct completion *kobj_completion; /* 完成通知 */
} __randomize_layout;
```

**kobject 是什么**？

kobject 是内核设备模型的基础结构（定义在 `include/linux/kobject.h:64`）：

```c
/* third_party/linux-imx/include/linux/kobject.h:64 */
struct kobject {
	const char		*name;
	struct list_head	entry;
	struct kobject		*parent;
	struct kset		*kset;
	const struct kobj_type	*ktype;
	struct kernfs_node	*sd; /* sysfs directory entry */
	struct kref		kref;
	/* ... 状态标志 ... */
};
```

每个加载的模块都会在 `/sys/module/` 下创建一个目录。

#### modinfo_attrs：模块信息属性

```c
struct module_attribute *modinfo_attrs;
```

这是一个数组，包含模块的各种信息属性（如 license、author、description 等），这些信息会显示在 sysfs 中。

#### version / srcversion：版本信息

```c
const char *version;
const char *srcversion;
```

- `version`：通过 `MODULE_VERSION()` 设置的模块版本字符串
- `srcversion`：源代码版本（基于源文件的 CRC 值）

#### holders_dir：持有者目录

```c
struct kobject *holders_dir;
```

在 sysfs 中，这个目录包含依赖当前模块的其他模块的符号链接。

### 2.6 段属性字段

#### sect_attrs：段属性

```c
/* Section attributes */
struct module_sect_attrs *sect_attrs;
```

**定义**（`kernel/module/sysfs.c:27`）：

```c
/* third_party/linux-imx/kernel/module/sysfs.c:27 */
struct module_sect_attrs {
	struct attribute_group grp;
	unsigned int nsections;
	struct module_sect_attrs attrs[];
};
```

这会在 `/sys/module/<name>/sections/` 下创建各个段的信息文件，如 `.text`、`.data`、`.bss` 等。

#### notes_attrs：notes 属性

```c
/* Notes attributes */
struct module_notes_attrs *notes_attrs;
```

用于处理 ELF 的 `SHT_NOTE` 类型的段，通常包含构建信息。

### 2.7 内存管理字段

#### mem：模块内存区域

```c
struct module_memory mem[MOD_MEM_NUM_TYPES] __module_memory_align;
```

**enum mod_mem_type**（`include/linux/module.h:332`）：

```c
enum mod_mem_type {
	MOD_TEXT = 0,          /* 代码段 */
	MOD_DATA,              /* 数据段 */
	MOD_RODATA,            /* 只读数据 */
	MOD_RO_AFTER_INIT,     /* 初始化后变为只读 */
	MOD_INIT_TEXT,         /* 初始化代码 */
	MOD_INIT_DATA,         /* 初始化数据 */
	MOD_INIT_RODATA,       /* 初始化只读数据 */
	MOD_MEM_NUM_TYPES,
	MOD_INVALID = -1,
};
```

**struct module_memory**（`include/linux/module.h:370`）：

```c
struct module_memory {
	void *base;            /* 基地址 */
	unsigned int size;     /* 大小 */
#ifdef CONFIG_MODULES_TREE_LOOKUP
	struct mod_tree_node mtn;
#endif
};
```

### 2.8 参数字段

#### kp / num_kp：内核参数

```c
/* Kernel parameters. */
#ifdef CONFIG_SYSFS
	struct mutex param_lock;
#endif
struct kernel_param *kp;
unsigned int num_kp;
```

这些字段描述模块的参数，通过 `module_param()` 宏定义的参数会存储在这里。

### 2.9 依赖关系字段

```c
#ifdef CONFIG_MODULE_UNLOAD
	/* What modules depend on me? */
	struct list_head source_list;
	/* What modules do I depend on? */
	struct list_head target_list;
#endif
```

- `source_list`：依赖当前模块的其他模块列表
- `target_list`：当前模块依赖的其他模块列表

**struct module_use 定义**（`include/linux/module.h:314`）：

```c
struct module_use {
	struct list_head source_list;
	struct list_head target_list;
	struct module *source, *target;
};
```

### 2.10 其他重要字段

#### args：模块参数字符串

```c
char *args;
```

加载模块时传递的参数字符串。

#### taints：污点标志

```c
unsigned long taints;
```

记录模块导致内核污点的标志（如非 GPL 模块、强制加载等）。

#### percpu：Per-CPU 数据

```c
#ifdef CONFIG_SMP
	void __percpu *percpu;
	unsigned int percpu_size;
#endif
```

模块的 Per-CPU 变量区域。

---

## 三、在内核代码中遍历所有已加载模块

这是一个常见的调试需求。下面是一个完整的示例代码，演示如何遍历所有模块并打印信息。

### 3.1 基本遍历方法

```c
/*
 * 遍历所有已加载模块并打印信息
 */
static void print_all_modules(void)
{
	struct module *mod;

	pr_info("=== All Loaded Modules ===\n");

	/* 必须持有 module_mutex */
	mutex_lock(&module_mutex);

	list_for_each_entry(mod, &modules, list) {
		pr_info("Module: %-20s State: %d Refcnt: %d\n",
			mod->name,
			mod->state,
			module_refcount(mod));
	}

	mutex_unlock(&module_mutex);
}
```

### 3.2 查找特定模块

```c
/*
 * 根据名称查找模块
 * 注意：调用者必须持有 module_mutex
 */
static struct module *find_module_by_name(const char *name)
{
	struct module *mod;

	list_for_each_entry(mod, &modules, list) {
		if (strcmp(mod->name, name) == 0)
			return mod;
	}
	return NULL;
}

/*
 * 安全的模块查找接口
 */
static struct module *safe_find_module(const char *name)
{
	struct module *mod;

	mutex_lock(&module_mutex);
	mod = find_module_by_name(name);
	if (mod)
		/* 增加引用计数，防止模块被卸载 */
		if (!try_module_get(mod))
			mod = NULL;
	mutex_unlock(&module_mutex);

	return mod;
}
```

### 3.3 打印模块详细信息

```c
/*
 * 打印模块的详细信息
 */
static void print_module_info(struct module *mod)
{
	if (!mod) {
		pr_info("Module is NULL\n");
		return;
	}

	pr_info("=== Module Information ===\n");
	pr_info("Name: %s\n", mod->name);
	pr_info("State: %d\n", mod->state);
	pr_info("RefCount: %d\n", module_refcount(mod));

	if (mod->version)
		pr_info("Version: %s\n", mod->version);

	if (mod->srcversion)
		pr_info("Source Version: %s\n", mod->srcversion);

	pr_info("Exported Symbols: %u\n", mod->num_syms);
	pr_info("GPL Symbols: %u\n", mod->num_gpl_syms);

#ifdef CONFIG_MODULE_UNLOAD
	pr_info("Has exit function: %s\n", mod->exit ? "yes" : "no");
#endif

	if (mod->num_kp > 0)
		pr_info("Parameters: %u\n", mod->num_kp);
}
```

### 3.4 检查模块依赖关系

```c
/*
 * 打印模块依赖关系
 */
static void print_module_dependencies(struct module *mod)
{
	struct module_use *use;

	if (!mod)
		return;

	pr_info("=== %s Dependencies ===\n", mod->name);

	mutex_lock(&module_mutex);

	/* 打印我们依赖的模块 */
	pr_info("Depends on:\n");
	list_for_each_entry(use, &mod->target_list, target_list) {
		pr_info("  - %s\n", use->target->name);
	}

	/* 打印依赖我们的模块 */
	pr_info("Depended by:\n");
	list_for_each_entry(use, &mod->source_list, source_list) {
		pr_info("  - %s\n", use->source->name);
	}

	mutex_unlock(&module_mutex);
}
```

---

## 四、完整可编译代码示例

下面是一个完整的内核模块，演示如何遍历所有模块并打印信息。

### 4.1 模块源码（module_list.c）

```c
// SPDX-License-Identifier: GPL-2.0
/*
 * module_list.c - 列出所有已加载模块的示例
 * 适用于 i.MX6ULL + Linux 6.12.49
 *
 * 编译方法：
 *   make -C <内核源码路径> M=$(pwd) modules
 *
 * 加载/卸载：
 *   insmod module_list.ko
 *   rmmod module_list
 *
 * 查看输出：
 *   dmesg | tail
 */

#include <linux/module.h>      /* 模块核心API */
#include <linux/init.h>        /* __init、__exit 宏 */
#include <linux/kernel.h>      /* printk */
#include <linux/list.h>        /* list_head */
#include <linux/mutex.h>       /* mutex */
#include <linux/slab.h>        /* kmalloc */

/* 外部声明：全局模块链表和互斥锁 */
extern struct list_head modules;
extern struct mutex module_mutex;

/*
 * print_all_modules - 打印所有已加载模块的信息
 *
 * 注意：这个函数必须在持有 module_mutex 的情况下调用
 */
static void print_all_modules(void)
{
	struct module *mod;
	int count = 0;

	pr_info("\n");
	pr_info("========================================\n");
	pr_info("  All Loaded Modules Information\n");
	pr_info("========================================\n");

	/* 遍历全局模块链表 */
	list_for_each_entry(mod, &modules, list) {
		count++;
		pr_info("[%2d] %-20s State:%d Ref:%d\n",
			count,
			mod->name,
			mod->state,
			module_refcount(mod));
	}

	pr_info("Total modules: %d\n", count);
	pr_info("========================================\n");
	pr_info("\n");
}

/*
 * print_gpl_modules - 打印使用 GPL 符号的模块
 */
static void print_gpl_modules(void)
{
	struct module *mod;
	int count = 0;

	pr_info("\n");
	pr_info("========================================\n");
	pr_info("  Modules Using GPL Symbols\n");
	pr_info("========================================\n");

	list_for_each_entry(mod, &modules, list) {
		if (mod->using_gplonly_symbols) {
			count++;
			pr_info("[%2d] %s (using %u GPL symbols)\n",
				count,
				mod->name,
				mod->num_gpl_syms);
		}
	}

	pr_info("Total GPL-using modules: %d\n", count);
	pr_info("========================================\n");
	pr_info("\n");
}

/*
 * print_exporting_modules - 打印导出符号的模块
 */
static void print_exporting_modules(void)
{
	struct module *mod;
	int count = 0;

	pr_info("\n");
	pr_info("========================================\n");
	pr_info("  Modules Exporting Symbols\n");
	pr_info("========================================\n");

	list_for_each_entry(mod, &modules, list) {
		if (mod->num_syms > 0 || mod->num_gpl_syms > 0) {
			count++;
			pr_info("[%2d] %-20s Syms:%u GPL:%u\n",
				count,
				mod->name,
				mod->num_syms,
				mod->num_gpl_syms);
		}
	}

	pr_info("Total exporting modules: %d\n", count);
	pr_info("========================================\n");
	pr_info("\n");
}

/*
 * module_list_init - 模块初始化函数
 */
static int __init module_list_init(void)
{
	pr_info("module_list: loading...\n");

	/*
	 * 打印所有模块信息
	 * 注意：这里不需要手动获取 module_mutex，
	 * 因为在模块初始化期间，其他模块不会被卸载
	 */
	print_all_modules();
	print_exporting_modules();
	print_gpl_modules();

	return 0;
}

/*
 * module_list_exit - 模块清理函数
 */
static void __exit module_list_exit(void)
{
	pr_info("module_list: unloading...\n");
	pr_info("Goodbye!\n");
}

/*
 * 模块元数据
 */
MODULE_LICENSE("GPL");
MODULE_AUTHOR("IMX-Forge Tutorial <tutorial@example.com>");
MODULE_DESCRIPTION("List all loaded kernel modules");
MODULE_VERSION("1.0");

/*
 * 注册模块的加载和卸载函数
 */
module_init(module_list_init);
module_exit(module_list_exit);
```

### 4.2 Makefile

```makefile
# module_list 模块的 Makefile

# 内核源码路径 - 修改为你的实际路径
KERNEL_DIR := /home/charliechen/imx-forge/third_party/linux-imx

# 当前目录
PWD := $(shell pwd)

# 模块名称
obj-m := module_list.o

# 编译目标
all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

# 清理目标
clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
	rm -f Module.symvers modules.order

# 安装目标
install:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules_install

.PHONY: all clean install
```

### 4.3 编译和测试

```bash
# 1. 进入模块目录
cd /path/to/module/directory

# 2. 编译模块
make

# 3. 加载模块
sudo insmod module_list.ko

# 4. 查看内核日志
dmesg | tail -50

# 5. 验证模块已加载
lsmod | grep module_list

# 6. 卸载模块
sudo rmmod module_list

# 7. 再次查看日志
dmesg | tail -10
```

---

## 五、常见错误、调试方法与内核报错解读

### 5.1 常见错误及解决方案

#### 错误 1：Module is in use

```
rmmod: ERROR: Module module_name is in use
```

**原因**：模块的引用计数不为 0，有其他内核组件正在使用它。

**解决方法**：
1. 找出谁在使用模块：
```bash
cat /sys/module/module_name/refcnt
ls -la /sys/module/module_name/holders/
```

2. 先卸载依赖的模块：
```bash
lsmod | grep module_name
rmmod dependent_module
rmmod module_name
```

**源码分析**：这个检查发生在 `delete_module()` 中：

```c
/* third_party/linux-imx/kernel/module/main.c:671 */
if (try_release_module_ref(mod) != 0) {
    *forced = try_force_unload(flags);
    if (!(*forced))
        return -EWOULDBLOCK;
}
```

#### 错误 2：Module has no exit function

```
rmmod: ERROR: Module module_name has no exit function
```

**原因**：模块有 `init` 函数但没有 `exit` 函数。

**解决方法**：这通常是设计上的限制。如果必须卸载，只能使用强制卸载（不推荐）。

**源码分析**：
```c
/* third_party/linux-imx/kernel/module/main.c:743 */
if (mod->init && !mod->exit) {
    forced = try_force_unload(flags);
    if (!forced) {
        ret = -EBUSY;
        goto out;
    }
}
```

#### 错误 3：Module state is not LIVE

```
rmmod: ERROR: Module module_name is in an invalid state
```

**原因**：模块正处于加载或卸载过程中。

**解决方法**：等待模块操作完成，或检查是否有死锁。

**源码分析**：
```c
/* third_party/linux-imx/kernel/module/main.c:735 */
if (mod->state != MODULE_STATE_LIVE) {
    pr_debug("%s already dying\n", mod->name);
    ret = -EBUSY;
    goto out;
}
```

### 5.2 调试技巧

#### 技巧 1：启用模块加载调试

```bash
# 启用模块相关的动态调试
echo 'file kernel/module/main.c +p' > /sys/kernel/debug/dynamic_debug/control

# 查看调试输出
dmesg -w
```

#### 技巧 2：使用 ftrace 跟踪函数

```bash
# 启用模块加载函数跟踪
echo delete_module > /sys/kernel/debug/tracing/set_ftrace_filter
echo function > /sys/kernel/debug/tracing/current_tracer

# 查看跟踪结果
cat /sys/kernel/debug/tracing/trace
```

#### 技巧 3：检查模块状态

```bash
# 查看模块详细信息
cat /sys/module/module_name/refcnt
cat /sys/module/module_name/sections/.text

# 查看模块参数
ls /sys/module/module_name/parameters/

# 查看 taint 信息
cat /proc/sys/kernel/tainted
```

### 5.3 内核 OOPS 解读

如果模块导致内核崩溃，OOPS 信息会包含模块相关的信息：

```
[  123.456789] BUG: unable to handle page fault for address: 0xdeadbeef
[  123.456790] Internal error: Oops: 86000007 [#1] PREEMPT SMP ARM
[  123.456791] Modules linked in: my_module(O+) other_module ...
[  123.456792] CPU: 0 PID: 1234 Comm: insmod Tainted: G           O      6.12.49 ...
[  123.456793] PC is at my_function+0x10/0x20 [my_module]
[  123.456794] LR is at do_one_initcall+0x48/0x1b0
```

关键字段：
- `Modules linked in`: 列出所有加载的模块，`O+` 表示正在加载
- `Tainted`: `O` 表示外部模块加载了
- `PC is at`: 崩溃发生的地址和函数

---

## 六、练习题与实战代码查看

### 练习 1：查找特定模块

**题目**：编写一个函数，根据模块名查找 `struct module` 指针。如果找到，返回模块指针并增加引用计数。

**参考答案**：

```c
/*
 * find_module_safe - 安全地查找模块
 * @name: 模块名
 *
 * 返回：找到的模块指针，或 NULL
 * 注意：调用者必须在完成后调用 module_put()
 */
static struct module *find_module_safe(const char *name)
{
	struct module *mod;

	mutex_lock(&module_mutex);
	mod = find_module(name);
	if (mod && !try_module_get(mod))
		mod = NULL;
	mutex_unlock(&module_mutex);

	return mod;
}

/* 使用示例 */
void example_use(const char *name)
{
	struct module *mod;

	mod = find_module_safe(name);
	if (mod) {
		pr_info("Found module: %s\n", mod->name);
		pr_info("RefCount: %d\n", module_refcount(mod));
		module_put(mod);  /* 释放引用 */
	}
}
```

### 练习 2：统计模块数量

**题目**：编写一个函数，统计当前加载的模块数量，并分别统计有导出符号和使用 GPL 符号的模块数量。

**参考答案**：

```c
/*
 * struct module_stats - 模块统计信息
 */
struct module_stats {
	unsigned int total;           /* 总模块数 */
	unsigned int exporting;       /* 导出符号的模块数 */
	unsigned int gpl_using;       /* 使用 GPL 符号的模块数 */
	unsigned int with_params;     /* 有参数的模块数 */
};

/*
 * count_modules - 统计模块信息
 * @stats: 输出统计信息
 */
static void count_modules(struct module_stats *stats)
{
	struct module *mod;

	memset(stats, 0, sizeof(*stats));

	mutex_lock(&module_mutex);
	list_for_each_entry(mod, &modules, list) {
		stats->total++;

		if (mod->num_syms > 0 || mod->num_gpl_syms > 0)
			stats->exporting++;

		if (mod->using_gplonly_symbols)
			stats->gpl_using++;

		if (mod->num_kp > 0)
			stats->with_params++;
	}
	mutex_unlock(&module_mutex);
}

/* 使用示例 */
static void print_module_stats(void)
{
	struct module_stats stats;

	count_modules(&stats);

	pr_info("Module Statistics:\n");
	pr_info("  Total modules: %u\n", stats.total);
	pr_info("  Exporting symbols: %u\n", stats.exporting);
	pr_info("  Using GPL symbols: %u\n", stats.gpl_using);
	pr_info("  With parameters: %u\n", stats.with_params);
}
```

### 练习 3：分析模块依赖关系

**题目**：编写一个函数，打印指定模块的完整依赖树（包括直接依赖和间接依赖）。

**参考答案**：

```c
#define MAX_DEPTH 10

/*
 * print_dependencies_recursive - 递归打印依赖关系
 * @mod: 当前模块
 * @depth: 递归深度
 * @visited: 已访问模块的 bitmap
 */
static void print_dependencies_recursive(struct module *mod,
					 int depth,
					 unsigned long *visited)
{
	struct module_use *use;
	int idx;

	/* 检查是否已访问 */
	idx = mod - list_entry(modules.next, struct module, list);
	if (test_bit(idx, visited))
		return;
	set_bit(idx, visited);

	/* 打印当前模块（带缩进） */
	pr_info("%*s%s\n", depth * 2, "", mod->name);

	if (depth >= MAX_DEPTH)
		return;

	/* 递归打印依赖的模块 */
	list_for_each_entry(use, &mod->target_list, target_list) {
		print_dependencies_recursive(use->target, depth + 1, visited);
	}
}

/*
 * print_module_dependency_tree - 打印模块依赖树
 * @name: 模块名
 */
static void print_module_dependency_tree(const char *name)
{
	struct module *mod;
	unsigned long *visited;
	size_t bitmap_size;

	mutex_lock(&module_mutex);
	mod = find_module(name);
	if (!mod) {
		pr_info("Module '%s' not found\n", name);
		mutex_unlock(&module_mutex);
		return;
	}

	/* 分配 visited bitmap */
	bitmap_size = BITS_TO_LONGS(module_count) * sizeof(unsigned long);
	visited = kzalloc(bitmap_size, GFP_KERNEL);
	if (!visited) {
		mutex_unlock(&module_mutex);
		return;
	}

	pr_info("\n=== Dependency Tree for '%s' ===\n", name);
	print_dependencies_recursive(mod, 0, visited);
	pr_info("====================================\n\n");

	kfree(visited);
	mutex_unlock(&module_mutex);
}
```

### 练习 4：导出符号分析

**题目**：编写一个函数，分析指定模块导出了哪些符号，并打印符号名和值。

**参考答案**：

```c
/*
 * print_module_exports - 打印模块导出的符号
 * @mod: 模块
 */
static void print_module_exports(struct module *mod)
{
	unsigned int i;

	if (mod->num_syms == 0 && mod->num_gpl_syms == 0) {
		pr_info("Module '%s' exports no symbols\n", mod->name);
		return;
	}

	pr_info("Module '%s' exported symbols:\n", mod->name);

	/* 打印普通导出符号 */
	for (i = 0; i < mod->num_syms; i++) {
		const struct kernel_symbol *sym = &mod->syms[i];
		pr_info("  [EXPORT] %p: %s\n",
			(void *)sym->value, sym->name);
	}

	/* 打印 GPL 导出符号 */
	for (i = 0; i < mod->num_gpl_syms; i++) {
		const struct kernel_symbol *sym = &mod->gpl_syms[i];
		pr_info("  [GPL]    %p: %s\n",
			(void *)sym->value, sym->name);
	}
}
```

### 练习 5：模块状态监控

**题目**：创建一个内核线程，定期监控模块状态变化，并在状态改变时打印日志。

**参考答案**：

```c
#include <linux/kthread.h>
#include <linux/delay.h>

static struct task_struct *monitor_thread;
static bool monitor_running = true;

/*
 * module_monitor_thread - 模块监控线程
 * @data: 未使用
 */
static int module_monitor_thread(void *data)
{
	struct module *mod;
	int last_count = 0;

	while (!kthread_should_stop()) {
		int current_count = 0;

		mutex_lock(&module_mutex);
		list_for_each_entry(mod, &modules, list) {
			current_count++;
		}
		mutex_unlock(&module_mutex);

		/* 检测模块数量变化 */
		if (current_count != last_count) {
			pr_info("Module count changed: %d -> %d\n",
				last_count, current_count);
			last_count = current_count;
		}

		/* 每 5 秒检查一次 */
		msleep(5000);
	}

	return 0;
}

/*
 * start_monitor - 启动监控线程
 */
static int start_monitor(void)
{
	monitor_thread = kthread_run(module_monitor_thread,
				     NULL, "module_monitor");
	if (IS_ERR(monitor_thread))
		return PTR_ERR(monitor_thread);

	pr_info("Module monitor thread started\n");
	return 0;
}

/*
 * stop_monitor - 停止监控线程
 */
static void stop_monitor(void)
{
	if (monitor_thread) {
		kthread_stop(monitor_thread);
		monitor_thread = NULL;
		pr_info("Module monitor thread stopped\n");
	}
}

/* 在模块初始化时启动，退出时停止 */
static int __init my_module_init(void)
{
	return start_monitor();
}

static void __exit my_module_exit(void)
{
	stop_monitor();
}
```

---

## 七、实战代码查看

为了更深入地理解 `struct module`，建议查看以下内核源码文件：

### 7.1 核心头文件

| 文件 | 说明 |
|------|------|
| `include/linux/module.h` | `struct module` 定义和模块 API |
| `include/linux/moduleparam.h` | 模块参数相关定义 |
| `include/linux/export.h` | 符号导出宏定义 |
| `include/linux/kobject.h` | kobject 定义（sysfs 基础） |

### 7.2 核心实现文件

| 文件 | 说明 |
|------|------|
| `kernel/module/main.c` | 模块加载/卸载核心实现 |
| `kernel/module/sysfs.c` | 模块 sysfs 接口实现 |
| `kernel/module/version.c` | 模块版本检查 |
| `kernel/module/kallsyms.c` | 符号表处理 |

### 7.3 关键函数位置

| 函数 | 文件位置 | 说明 |
|------|----------|------|
| `SYSCALL_DEFINE2(delete_module)` | `kernel/module/main.c:700` | 卸载模块系统调用 |
| `try_stop_module()` | `kernel/module/main.c:668` | 停止模块 |
| `free_module()` | `kernel/module/main.c:1261` | 释放模块 |
| `try_module_get()` | `kernel/module/main.c:1014` | 增加引用计数 |
| `module_put()` | `kernel/module/main.c:1028` | 减少引用计数 |
| `find_module()` | `kernel/module/main.c:647` | 查找模块 |
| `mod_sysfs_setup()` | `kernel/module/sysfs.c:371` | 设置 sysfs |

### 7.4 内核文档

- `Documentation/kbuild/modules.rst` - 外部模块构建指南
- `Documentation/driver-api/` - 驱动开发 API 文档
- `Documentation/core-api/kobject.rst` - kobject 和 sysfs

---

## 八、下一章预告

到这里，你应该对 `struct module` 有了全面的理解。你知道了模块的完整生命周期、各个字段的含义，以及如何在内核中遍历和操作模块。

下一章，我们将探索更高级的主题：

- 模块间的符号依赖和通信
- 模块签名和安全机制
- 设备模型与模块的关系
- 实战：编写一个完整的字符设备驱动

准备好了吗？让我们继续深入内核模块开发的世界。

---

## 参考资料

### 内核源码引用

本文档所有源码引用基于 linux-imx 6.12.49，位于 `third_party/linux-imx/` 目录：

- `include/linux/module.h:410` - struct module 定义
- `include/linux/module.h:320` - enum module_state
- `kernel/module/main.c:700` - delete_module 系统调用
- `kernel/module/main.c:668` - try_stop_module 函数
- `kernel/module/main.c:1261` - free_module 函数
- `kernel/module/sysfs.c:371` - mod_sysfs_setup 函数

### 延伸阅读

- [Linux内核模块编程指南](https://sysprog21.github.io/lkmpg/)
- 内核文档：kbuild/modules.rst
- [Understanding the Linux Kernel](https://www.oreilly.com/library/view/understanding-the-linux/0596005652/)

---

**作者**: IMX-Forge 项目组
**最后更新**: 2026年3月
**内核版本**: 6.12.49 (linux-imx)
