# 模块参数与内核调试：让模块"活"起来的魔法

::: warning 阅读前提：本章行号基于已退役的 linux-imx 树
modules/ 这几章写于项目还维护 NXP linux-imx 内核（6.12.49）的双轨时代，文中所有源码路径、行号都对着那棵已经删除的源码树。项目现在只保留上游主线内核（`third_party/linux_mainline`，v7.1）：概念、原理、流程完全通用，但具体行号在 mainline 树上对不上。行号重核已挂在待办上，按学习者反馈排期——发现对不上的地方，欢迎进 QQ 群（645248275）或提 issue 反馈。
:::

## 前言：从静态代码到可交互模块

还记得上一章我们写的第一个内核模块吗？它就像一个只会说"Hello"的呆板机器人——加载时打个招呼，卸载时道个别，就没别的了。但实际驱动开发中，我们经常需要在运行时调整模块的行为：开启/关闭调试输出、修改缓冲区大小、设置设备地址等等。

这时候，模块参数（Module Parameters）就派上用场了。它就像是模块的"控制面板"，让你在不重新编译模块的情况下，就能改变模块的行为。

今天我们就来聊聊：
- 模块参数的工作原理（深入内核源码）
- 各种参数类型的使用场景
- 通过 /sys/module/ 与模块交互
- 内核调试的十八般武艺
- 那些让人头秃的常见错误

## 一、模块参数原理：内核是如何解析参数的

### 1.1 从宏定义到 ELF section

你可能会好奇，为什么写一行 `module_param()`，内核就能自动创建 sysfs 接口？这背后其实是一套精妙的链接器魔术。

让我们从内核源码说起。打开 `third_party/linux-imx/include/linux/moduleparam.h`，你会看到 `module_param` 宏的定义：

```c
// 文件位置：third_party/linux-imx/include/linux/moduleparam.h
#define module_param(name, type, perm)
    module_param_named(name, name, type, perm)

#define module_param_named(name, value, type, perm)
    param_check_##type(name, &(value));
    module_param_cb(name, &param_ops_##type, &value, perm);
    __MODULE_PARM_TYPE(name, #type)

#define __module_param_call(prefix, name, ops, arg, perm, level, flags)
    static_assert(sizeof(""prefix) - 1 <= MAX_PARAM_PREFIX_LEN);
    static const char __param_str_##name[] = prefix #name;
    static struct kernel_param __moduleparam_const __param_##name
    __used __section("__param")
    __aligned(__alignof__(struct kernel_param))
    = { __param_str_##name, THIS_MODULE, ops,
        VERIFY_OCTAL_PERMISSIONS(perm), level, flags, { arg } }
```

看不懂？别慌，我们用人话翻译一下：

1. `module_param(name, type, perm)` 展开成 `module_param_named(name, name, type, perm)`
2. `module_param_named` 做了三件事：
   - 调用 `param_check_type()` 做编译时类型检查
   - 调用 `module_param_cb()` 注册参数
   - 调用 `__MODULE_PARM_TYPE()` 记录类型信息到模块信息中
3. `module_param_cb()` 最终调用 `__module_param_call()`
4. `__module_param_call()` 这个宏创建了一个 `struct kernel_param` 结构体
5. 关键点来了：`__section("__param")` 把这个结构体放到 ELF 的 `__param` section 中

**__section("__param")** 是什么鬼？这是 GCC 的扩展语法，告诉链接器把特定变量放到指定的 section 中。当模块加载时，内核会遍历 `__param` section，找到所有参数描述符。

### 1.2 参数加载流程：从 insmod 到内核

当我们执行 `insmod mymodule.ko param1=123` 时，内核内部发生了什么？

让我们追踪内核源码的调用链（文件位置：`third_party/linux-imx/kernel/module/main.c`）：

```
sys_init_module()                    // 系统调用入口
  -> load_module()
    -> parse_args()                  // 解析命令行参数
      -> parse_one()                 // 逐个解析参数
        -> kp->ops->set()            // 调用参数的 set 函数
    -> mod_sysfs_setup()
      -> module_param_sysfs_setup()  // 创建 /sys/module/.../parameters/
```

`parse_args()` 函数在 `third_party/linux-imx/kernel/params.c` 中定义：

```c
// 文件位置：third_party/linux-imx/kernel/params.c
char *parse_args(const char *doing,
         char *args,
         const struct kernel_param *params,
         unsigned num,
         s16 min_level,
         s16 max_level,
         void *arg, parse_unknown_fn unknown)
{
    char *param, *val, *err = NULL;

    args = skip_spaces(args);

    while (*args) {
        int ret;
        args = next_arg(args, &param, &val);  // 解析 "param=val" 格式

        ret = parse_one(param, val, doing, params, num,
                min_level, max_level, arg, unknown);

        if (ret == -ENOENT)
            pr_err("%s: Unknown parameter `%s'\n", doing, param);
        // ... 其他错误处理
    }
    return err;
}
```

`parse_one()` 负责查找参数并调用对应的 set 函数：

```c
// 文件位置：third_party/linux-imx/kernel/params.c
static int parse_one(char *param,
             char *val,
             const struct kernel_param *params,
             unsigned num_params,
             s16 min_level,
             s16 max_level,
             void *arg, parse_unknown_fn handle_unknown)
{
    unsigned int i;
    int err;

    /* 查找参数 */
    for (i = 0; i < num_params; i++) {
        if (parameq(param, params[i].name)) {  // 参数名匹配
            /* 调用参数的 set 函数 */
            kernel_param_lock(params[i].mod);
            if (param_check_unsafe(&params[i]))
                err = params[i].ops->set(val, &params[i]);
            else
                err = -EPERM;
            kernel_param_unlock(params[i].mod);
            return err;
        }
    }
    return -ENOENT;  // 未找到参数
}
```

注意到 `parameq()` 函数了吗？它会把参数名中的 `-` 当作 `_` 处理，所以 `my-param` 和 `my_param` 是等价的：

```c
// 文件位置：third_party/linux-imx/kernel/params.c
bool parameq(const char *a, const char *b)
{
    return parameqn(a, b, strlen(a)+1);
}

bool parameqn(const char *a, const char *b, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++) {
        if (dash2underscore(a[i]) != dash2underscore(b[i]))
            return false;
    }
    return true;
}

static char dash2underscore(char c)
{
    if (c == '-')
        return '_';
    return c;
}
```

### 1.3 参数类型系统：ops 结构体

每种参数类型都对应一个 `kernel_param_ops` 结构体：

```c
// 文件位置：third_party/linux-imx/include/linux/moduleparam.h
struct kernel_param_ops {
    /* 行为标志 */
    unsigned int flags;
    /* 设置参数：返回 0 或 -errno */
    int (*set)(const char *val, const struct kernel_param *kp);
    /* 获取参数：返回写入长度或 -errno。buffer 大小为 4k */
    int (*get)(char *buffer, const struct kernel_param *kp);
    /* 可选：释放参数 */
    void (*free)(void *arg);
};
```

内核已经为我们实现了常用类型的 ops：

```c
// 文件位置：third_party/linux-imx/kernel/params.c
STANDARD_PARAM_DEF(byte,    unsigned char,  "%hhu", kstrtou8);
STANDARD_PARAM_DEF(short,   short,          "%hi",  kstrtos16);
STANDARD_PARAM_DEF(ushort,  unsigned short, "%hu",  kstrtou16);
STANDARD_PARAM_DEF(int,     int,            "%i",   kstrtoint);
STANDARD_PARAM_DEF(uint,    unsigned int,   "%u",   kstrtouint);
STANDARD_PARAM_DEF(long,    long,           "%li",  kstrtol);
STANDARD_PARAM_DEF(ulong,   unsigned long,  "%lu",  kstrtoul);
STANDARD_PARAM_DEF(ullong,  unsigned long long, "%llu", kstrtoull);
STANDARD_PARAM_DEF(hexint,  unsigned int,   "%#08x", kstrtouint);
```

`STANDARD_PARAM_DEF` 是一个宏模板：

```c
#define STANDARD_PARAM_DEF(name, type, format, strtolfn)
    int param_set_##name(const char *val, const struct kernel_param *kp)
    {
        return strtolfn(val, 0, (type *)kp->arg);  // 字符串转数值
    }
    int param_get_##name(char *buffer, const struct kernel_param *kp)
    {
        return scnprintf(buffer, PAGE_SIZE, format "\n",
                *((type *)kp->arg));  // 数值转字符串
    }
    const struct kernel_param_ops param_ops_##name = {
        .set = param_set_##name,
        .get = param_get_##name,
    };
```

## 二、参数类型详解： Choosing the Right Type

### 2.1 基础数值类型

```c
static int my_int = 42;
module_param(my_int, int, 0644);
MODULE_PARM_DESC(my_int, "An integer parameter");

static unsigned int my_uint = 100;
module_param(my_uint, uint, 0644);
MODULE_PARM_DESC(my_uint, "An unsigned integer");

static bool my_bool = true;
module_param(my_bool, bool, 0644);
MODULE_PARM_DESC(my_bool, "A boolean parameter");
```

**权限位说明**：
- `0`：不在 sysfs 中显示
- `0444`：全局只读
- `0644`：root 可写，其他只读
- `0666`：全局可写（不推荐）

### 2.2 字符串参数

```c
static char *my_string = "default";
module_param(my_string, charp, 0644);
MODULE_PARM_DESC(my_string, "A string parameter");
```

注意：`charp` 类型会动态分配内存，所以模块卸载时内核会自动释放。

### 2.3 数组参数

```c
#define MAX_ARRAY_LEN 10
static int my_array[MAX_ARRAY_LEN];
static int array_count;

module_param_array(my_array, int, &array_count, 0644);
MODULE_PARM_DESC(my_array, "An integer array");
```

使用方式：
```bash
insmod mymodule.ko my_array=1,2,3,4,5
```

### 2.4 自定义参数操作

有时候内置类型不够用，你需要自定义参数处理逻辑。比如，你想限制参数的范围：

```c
static int my_param_set(const char *val, const struct kernel_param *kp)
{
    int ret;
    int num;

    ret = kstrtoint(val, 0, &num);
    if (ret)
        return ret;

    // 自定义逻辑：限制范围
    if (num < 0 || num > 100)
        return -EINVAL;

    *((int *)kp->arg) = num;
    return 0;
}

static const struct kernel_param_ops my_param_ops = {
    .set = my_param_set,
    .get = param_get_int,
};

static int my_custom_param = 50;
module_param_cb(my_custom_param, &my_param_ops, &my_custom_param, 0644);
MODULE_PARM_DESC(my_custom_param, "Custom parameter with range check (0-100)");
```

## 三、/sys/module/ 接口：运行时与模块交互

### 3.1 sysfs 结构

模块加载后，内核会自动创建以下结构：

```
/sys/module/
├── mymodule/
│   ├── sections/
│   │   ├── .text
│   │   ├── .data
│   │   └── .bss
│   ├── parameters/
│   │   ├── my_int
│   │   ├── my_uint
│   │   ├── my_bool
│   │   └── my_string
│   ├── refcnt         # 引用计数
│   ├── taint          # 污染标志
│   └── coresize       # 代码大小
```

参数的 sysfs 创建逻辑在 `third_party/linux-imx/kernel/params.c` 中：

```c
// 文件位置：third_party/linux-imx/kernel/params.c
int module_param_sysfs_setup(struct module *mod,
                 const struct kernel_param *kparam,
                 unsigned int num_params)
{
    int i, err;
    bool params = false;

    for (i = 0; i < num_params; i++) {
        if (kparam[i].perm == 0)
            continue;
        err = add_sysfs_param(&mod->mkobj, &kparam[i], kparam[i].name);
        if (err) {
            free_module_param_attrs(&mod->mkobj);
            return err;
        }
        params = true;
    }

    if (!params)
        return 0;

    /* 创建参数组 */
    err = sysfs_create_group(&mod->mkobj.kobj, &mod->mkobj.mp->grp);
    if (err)
        free_module_param_attrs(&mod->mkobj);
    return err;
}
```

### 3.2 读写参数

```bash
# 查看参数值
cat /sys/module/mymodule/parameters/my_int

# 修改参数值（需要 root 权限）
echo 99 > /sys/module/mymodule/parameters/my_int

# 查看模块引用计数
cat /sys/module/mymodule/refcnt
```

### 3.3 引用计数的重要性

引用计数决定了模块能否被卸载。每次 `open()` 设备文件时引用计数 +1，`close()` 时 -1。只有计数为 0 时才能 `rmmod`。

## 四、内核调试技巧：printk 之外的选择

### 4.1 printk 基础

`printk()` 是内核调试的瑞士军刀，但它有一些坑：

```c
printk(KERN_INFO "Hello, world!\n");
printk(KERN_WARNING "Something might be wrong\n");
printk(KERN_ERR "Oops, error occurred: %d\n", err);
```

**日志级别对照表**（文件位置：`third_party/linux-imx/include/linux/kern_levels.h`）：

```c
#define KERN_EMERG      "0"    // 系统不可用
#define KERN_ALERT      "1"    // 需要立即采取行动
#define KERN_CRIT       "2"    // 严重情况
#define KERN_ERR        "3"    // 错误情况
#define KERN_WARNING    "4"    // 警告情况
#define KERN_NOTICE     "5"    // 正常但重要
#define KERN_INFO       "6"    // 信息性消息
#define KERN_DEBUG      "7"    // 调试级别
```

**查看和设置日志级别**：

```bash
# 查看当前控制台日志级别
cat /proc/sys/kernel/printk
# 输出：4 4 1 7
# 含义：控制台日志级别、默认消息级别、最小控制台级别、默认控制台级别

# 设置控制台日志级别为 8（打印所有消息）
echo 8 > /proc/sys/kernel/printk
```

### 4.2 pr_* 宏系列

内核提供了一组更方便的宏：

```c
pr_info("Info: %d\n", value);
pr_warn("Warning: %s\n", msg);
pr_err("Error: %d\n", err);
pr_debug("Debug: x=%d, y=%d\n", x, y);  // 只有开启 DEBUG 时才编译进去
```

这些宏会自动添加模块前缀，格式为 `[模块名] 消息内容`。

### 4.3 dev_* 系列宏：设备相关调试

编写设备驱动时，使用 `dev_*` 系列可以自动添加设备信息：

```c
dev_info(&pdev->dev, "Device initialized\n");
dev_warn(&pdev->dev, "Voltage out of range: %d\n", voltage);
dev_err(&pdev->dev, "Failed to register: %d\n", ret);
```

输出格式：`设备名: 消息内容`，例如 `mydevice 0000:01:00.0: Device initialized`

### 4.4 动态调试（Dynamic Debug）

这是内核的"核武器"级调试工具，可以在运行时开启/关闭特定的 pr_debug() 语句。

**前提条件**：内核配置时开启 `CONFIG_DYNAMIC_DEBUG`

```c
// 使用 pr_debug 而不是 printk
pr_debug("Entering function %s\n", __func__);
pr_debug("Value of x: %d\n", x);
```

**控制动态调试**（文件位置：`third_party/linux-imx/include/linux/dynamic_debug.h`）：

```bash
# 查看所有可用的动态调试点
cat /sys/kernel/debug/dynamic_debug/control

# 开启某个模块的所有动态调试
echo "module mymodule +p" > /sys/kernel/debug/dynamic_debug/control

# 开启某个文件的动态调试
echo "file mydriver.c +p" > /sys/kernel/debug/dynamic_debug/control

# 开启某个函数的动态调试
echo "func my_function +p" > /sys/kernel/debug/dynamic_debug/control

# 开启某一行
echo "file mydriver.c line 100 +p" > /sys/kernel/debug/dynamic_debug/control

# 关闭动态调试
echo "module mymodule -p" > /sys/kernel/debug/dynamic_debug/control
```

动态调试的实现原理（文件位置：`third_party/linux-imx/include/linux/dynamic_debug.h`）：

```c
struct _ddebug {
    const char *modname;
    const char *function;
    const char *filename;
    const char *format;
    unsigned int lineno:18;
    unsigned int class_id:6;
    unsigned int flags:8;  // 控制是否打印
#ifdef CONFIG_JUMP_LABEL
    union {
        struct static_key_true dd_key_true;
        struct static_key_false dd_key_false;
    } key;
#endif
};
```

每个 `pr_debug()` 调用点都会创建一个 `_ddebug` 结构体实例，放在 `__dyndbg` section 中。

### 4.5 ftrace：函数跟踪

ftrace 是内核内部的追踪器，可以跟踪函数调用：

```bash
# 挂载 debugfs（如果没挂载）
mount -t debugfs none /sys/kernel/debug

# 查看可用的追踪器
cat /sys/kernel/debug/tracing/available_tracers

# 启用函数图追踪器
echo function_graph > /sys/kernel/debug/tracing/current_tracer

# 查看追踪结果
cat /sys/kernel/debug/tracing/trace

# 只追踪某个函数
echo my_function > /sys/kernel/debug/tracing/set_ftrace_filter
```

## 五、常见错误与调试方法

### 5.1 Version Magic Mismatch

**错误信息**：
```
disagrees about version of symbol module_layout
```

**原因**：模块编译时的内核版本与运行时的内核版本不匹配。

**解决方法**：
1. 重新编译模块（确保使用当前内核的头文件）
2. 使用 `-f` 强制加载（不推荐，可能导致崩溃）
```bash
insmod -f mymodule.ko
```

**内核源码位置**（`third_party/linux-imx/include/linux/vermagic.h`）：

```c
#define VERMAGIC_STRING
    UTS_RELEASE " "                         // 内核版本号
    MODULE_VERMAGIC_SMP MODULE_VERMAGIC_PREEMPT
    MODULE_VERMAGIC_MODULE_UNLOAD MODULE_VERMAGIC_MODVERSIONS
    MODULE_ARCH_VERMAGIC
    MODULE_RANDSTRUCT
```

版本检查代码（`third_party/linux-imx/kernel/module/main.c`）：

```c
static int check_modinfo(struct module *mod, struct load_info *info,
             int flags)
{
    const char *modmagic = get_modinfo(info, "vermagic");

    if (flags & MODULE_INIT_IGNORE_VERMAGIC)
        modmagic = NULL;

    if (!modmagic) {
        err = try_to_force_load(mod, "bad vermagic");
        if (err)
            return err;
    } else if (!same_magic(modmagic, vermagic, info->index.vers)) {
        pr_err("%s: version magic '%s' should be '%s'\n",
               info->name, modmagic, vermagic);
        return -ENOEXEC;
    }
    return 0;
}
```

### 5.2 Unknown Symbol

**错误信息**：
```
Unknown symbol print_hex_dump (err 0)
```

**原因**：模块使用了内核中未导出的符号，或者符号名称拼写错误。

**解决方法**：
1. 检查符号名称是否正确
2. 确认符号是否已导出（`EXPORT_SYMBOL()` 或 `EXPORT_SYMBOL_GPL()`）
3. 检查 `CONFIG_*` 选项是否开启

**内核源码位置**（`third_party/linux-imx/kernel/module/main.c`）：

```c
static int simplify_symbols(struct module *mod, const struct load_info *info)
{
    unsigned int i;
    int ret = 0;
    struct symbol *s;

    for (i = 1; i < info->hdr->e_shnum; i++) {
        // ...
        switch (sym[i].st_shndx) {
        case SHN_UNDEF:
            ksym = resolve_symbol_wait(mod, info, name);
            if (IS_ERR(ksym) || !ksym) {
                ret = PTR_ERR(ksym) ?: -ENOENT;
                pr_warn("%s: Unknown symbol %s (err %d)\n",
                    mod->name, name, ret);
                break;
            }
            // ...
        }
    }
    return ret;
}
```

### 5.3 Invalid Parameters

**错误信息**：
```
mymodule: 'abc' invalid for parameter `my_int`
```

**原因**：参数值格式错误，比如传字符串给整型参数。

**解决方法**：检查参数格式是否正确。

**内核源码位置**（`third_party/linux-imx/kernel/params.c`）：

```c
char *parse_args(const char *doing, ...)
{
    // ...
    switch (ret) {
    case 0:
        continue;
    case -ENOENT:
        pr_err("%s: Unknown parameter `%s'\n", doing, param);
        break;
    case -ENOSPC:
        pr_err("%s: `%s' too large for parameter `%s'\n",
               doing, val ?: "", param);
        break;
    default:
        pr_err("%s: `%s' invalid for parameter `%s'\n",
               doing, val ?: "", param);
        break;
    }
    // ...
}
```

### 5.4 内存访问错误

**错误信息**：
```
BUG: unable to handle page fault for address 0x12345678
```

**原因**：访问了无效的内存地址（空指针、野指针、越界访问）。

**解决方法**：
1. 使用 `objdump -d` 反汇编查看指令地址
2. 使用 addr2line 定位源代码行：
```bash
addr2line -e vmlinux 0x12345678
```

### 5.5 死锁与并发问题

**症状**：系统卡死、Watchdog 触发。

**调试方法**：
1. 检查自旋锁/互斥锁的使用是否正确
2. 确认锁的顺序是否一致（避免 ABBA 死锁）
3. 使用 `lockdep` 工具检测死锁：

```bash
# 启用 lockdep
echo 1 > /proc/sys/kernel/lock_stat

# 查看 lockdep 报告
cat /proc/lockdep_stats
```

## 六、完整代码示例：带参数的调试模块

下面是一个完整的示例模块，展示了所有学到的知识：

```c
/*
 * 模块参数与调试示例
 * 文件名：mymodule_params.c
 * 编译命令：make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
 */

#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/slab.h>

/* ==================== 模块信息 ==================== */
MODULE_LICENSE("GPL");
MODULE_AUTHOR("IMX-Forge");
MODULE_DESCRIPTION("Module Parameters and Debugging Demo");
MODULE_VERSION("1.0");

/* ==================== 基础参数 ==================== */
static int int_param = 100;
module_param(int_param, int, 0644);
MODULE_PARM_DESC(int_param, "An integer parameter (0-1000)");

static unsigned int uint_param = 200;
module_param(uint_param, uint, 0644);
MODULE_PARM_DESC(uint_param, "An unsigned integer parameter");

static bool bool_param = true;
module_param(bool_param, bool, 0644);
MODULE_PARM_DESC(bool_param, "A boolean parameter");

static char *string_param = "hello";
module_param(string_param, charp, 0644);
MODULE_PARM_DESC(string_param, "A string parameter");

/* ==================== 数组参数 ==================== */
#define ARRAY_SIZE 10
static int int_array[ARRAY_SIZE];
static int array_count = 0;
module_param_array(int_array, int, &array_count, 0644);
MODULE_PARM_DESC(int_array, "An integer array");

/* ==================== 自定义参数：带范围检查 ==================== */
static int ranged_param = 50;

/* 自定义 set 函数：限制参数在 0-100 范围内 */
static int ranged_param_set(const char *val, const struct kernel_param *kp)
{
    int ret;
    int num;

    /* 将字符串转换为整数 */
    ret = kstrtoint(val, 0, &num);
    if (ret) {
        pr_err("Failed to convert '%s' to integer\n", val);
        return ret;
    }

    /* 范围检查 */
    if (num < 0 || num > 100) {
        pr_err("Parameter must be between 0 and 100, got %d\n", num);
        return -EINVAL;
    }

    /* 设置新值 */
    *((int *)kp->arg) = num;

    pr_info("ranged_param updated to %d\n", num);
    return 0;
}

/* 使用标准的 get 函数 */
static const struct kernel_param_ops ranged_param_ops = {
    .set = ranged_param_set,
    .get = param_get_int,
};

module_param_cb(ranged_param, &ranged_param_ops, &ranged_param, 0644);
MODULE_PARM_DESC(ranged_param, "A parameter with range check (0-100)");

/* ==================== 调试开关 ==================== */
static int debug_level = 0;
module_param(debug_level, int, 0644);
MODULE_PARM_DESC(debug_level, "Debug level (0=off, 1=info, 2=verbose)");

#define DBG(level, fmt, ...)                    \
    do {                                        \
        if (debug_level >= (level))             \
            pr_info(fmt, ##__VA_ARGS__);        \
    } while (0)

/* ==================== 动态调试示例 ==================== */
/* 这里的 pr_debug 只有在开启动态调试时才生效 */
static void demo_dynamic_debug(void)
{
    pr_debug("This is a dynamic debug message\n");
    pr_debug("Function: %s, Line: %d\n", __func__, __LINE__);
}

/* ==================== 模块初始化与清理 ==================== */
static int __init mymodule_init(void)
{
    int i;

    pr_info("==================== Module Init ====================\n");
    pr_info("int_param      = %d\n", int_param);
    pr_info("uint_param     = %u\n", uint_param);
    pr_info("bool_param     = %s\n", bool_param ? "true" : "false");
    pr_info("string_param   = %s\n", string_param);
    pr_info("ranged_param   = %d\n", ranged_param);
    pr_info("debug_level    = %d\n", debug_level);

    pr_info("Array contents (%d elements):\n", array_count);
    for (i = 0; i < array_count; i++) {
        pr_info("  int_array[%d] = %d\n", i, int_array[i]);
    }

    DBG(1, "Debug level 1: Basic info\n");
    DBG(2, "Debug level 2: Verbose info\n");

    demo_dynamic_debug();

    pr_info("===================================================\n");
    return 0;
}

static void __exit mymodule_exit(void)
{
    pr_info("==================== Module Exit ====================\n");
    pr_info("Final parameter values:\n");
    pr_info("  int_param    = %d\n", int_param);
    pr_info("  ranged_param = %d\n", ranged_param);
    pr_info("===================================================\n");
}

module_init(mymodule_init);
module_exit(mymodule_exit);
```

**配套的 Makefile**：

```makefile
# Makefile for mymodule_params
obj-m += mymodule_params.o

# 内核构建目录
KDIR := /lib/modules/$(shell uname -r)/build

# 如果使用交叉编译，取消下面的注释并修改路径
# KDIR := /path/to/linux-imx
# ARCH := arm
# CROSS_COMPILE := arm-linux-gnueabihf-

all:
    $(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
    $(MAKE) -C $(KDIR) M=$(PWD) clean
```

**测试脚本**：

```bash
#!/bin/bash
# test_module.sh

echo "=== 加载模块 ==="
insmod mymodule_params.ko \
    int_param=42 \
    bool_param=n \
    string_param="Hello World" \
    int_array=1,2,3,4,5 \
    ranged_param=75 \
    debug_level=2

echo "=== 查看内核日志 ==="
dmesg | tail -20

echo "=== 查看 sysfs 参数 ==="
echo "int_param = $(cat /sys/module/mymodule_params/parameters/int_param)"
echo "bool_param = $(cat /sys/module/mymodule_params/parameters/bool_param)"
echo "string_param = $(cat /sys/module/mymodule_params/parameters/string_param)"
echo "int_array = $(cat /sys/module/mymodule_params/parameters/int_array)"

echo "=== 修改参数 ==="
echo "99" > /sys/module/mymodule_params/parameters/int_param
echo "0" > /sys/module/mymodule_params/parameters/bool_param
echo "New int_param = $(cat /sys/module/mymodule_params/parameters/int_param)"
echo "New bool_param = $(cat /sys/module/mymodule_params/parameters/bool_param)"

echo "=== 测试范围检查 ==="
echo "150" > /sys/module/mymodule_params/parameters/ranged_param 2>&1

echo "=== 测试动态调试 ==="
echo "module mymodule_params +p" > /sys/kernel/debug/dynamic_debug/control
echo "=== 卸载模块 ==="
rmmod mymodule_params
dmesg | tail -5
```

## 七、练习题

### 练习 1：参数类型实验

编写一个模块，包含以下参数：
- `delay_ms`：整型，延迟时间（毫秒），范围 1-5000
- `repeat_count`：无符号整型，重复次数
- `enable_feature`：布尔型，开启/关闭某个功能
- `device_name`：字符串，设备名称

要求：
1. 对 `delay_ms` 进行范围检查
2. 通过 `/sys/module/` 接口测试参数修改
3. 使用 `pr_debug()` 输出调试信息

**参考答案**：

```c
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/kernel.h>

MODULE_LICENSE("GPL");

static int delay_ms = 100;
static int delay_ms_set(const char *val, const struct kernel_param *kp)
{
    int ret, num;

    ret = kstrtoint(val, 0, &num);
    if (ret)
        return ret;
    if (num < 1 || num > 5000)
        return -EINVAL;
    *((int *)kp->arg) = num;
    return 0;
}
static const struct kernel_param_ops delay_ms_ops = {
    .set = delay_ms_set,
    .get = param_get_int,
};
module_param_cb(delay_ms, &delay_ms_ops, &delay_ms, 0644);
MODULE_PARM_DESC(delay_ms, "Delay in milliseconds (1-5000)");

static unsigned int repeat_count = 10;
module_param(repeat_count, uint, 0644);
MODULE_PARM_DESC(repeat_count, "Number of repetitions");

static bool enable_feature = false;
module_param(enable_feature, bool, 0644);
MODULE_PARM_DESC(enable_feature, "Enable the feature");

static char *device_name = "dev0";
module_param(device_name, charp, 0644);
MODULE_PARM_DESC(device_name, "Device name");

static int __init ex1_init(void)
{
    int i;

    pr_info("Exercise 1 loaded\n");
    pr_info("delay_ms=%d, repeat_count=%u, enable=%d, name=%s\n",
        delay_ms, repeat_count, enable_feature, device_name);

    if (enable_feature) {
        for (i = 0; i < repeat_count; i++) {
            pr_debug("Iteration %d for device %s\n", i, device_name);
        }
    }

    return 0;
}
static void __exit ex1_exit(void)
{
    pr_info("Exercise 1 unloaded\n");
}
module_init(ex1_init);
module_exit(ex1_exit);
```

### 练习 2：动态调试实战

1. 编写一个模块，在不同函数中使用 `pr_debug()`
2. 加载模块，默认不输出调试信息
3. 使用动态调试接口，只开启某个函数的调试输出

**参考命令**：

```bash
# 只开启函数 my_func 的调试
echo "func my_func +p" > /sys/kernel/debug/dynamic_debug/control

# 开启某个文件的调试
echo "file mymodule.c +p" > /sys/kernel/debug/dynamic_debug/control

# 查看当前动态调试状态
cat /sys/kernel/debug/dynamic_debug/control | grep mymodule
```

### 练习 3：自定义参数操作

实现一个十六进制字符串参数，要求：
1. 输入格式为 "0x12ab" 或 "12ab"
2. 存储为 unsigned int
3. 通过 get 函数输出十六进制格式

**参考答案**：

```c
static unsigned int hex_param = 0x1234;

static int hex_param_set(const char *val, const struct kernel_param *kp)
{
    return kstrtouint(val, 16, (unsigned int *)kp->arg);
}

static int hex_param_get(char *buffer, const struct kernel_param *kp)
{
    return sprintf(buffer, "0x%08x\n", *((unsigned int *)kp->arg));
}

static const struct kernel_param_ops hex_param_ops = {
    .set = hex_param_set,
    .get = hex_param_get,
};

module_param_cb(hex_param, &hex_param_ops, &hex_param, 0644);
MODULE_PARM_DESC(hex_param, "Hex parameter (e.g., 0x12ab)");
```

### 练习 4：参数验证与错误处理

扩展 `delay_ms` 参数，添加以下验证：
- 拒绝非数字输入
- 拒绝负数
- 超出范围时打印警告并保持原值

**提示**：参考 `kernel/params.c` 中的 `param_set_uint_minmax()` 函数实现。

### 练习 5：实战代码查看

阅读以下内核源码文件，回答问题：
1. `drivers/video/logo/logo.c` 中 `nologo` 参数的作用是什么？
2. `drivers/i2c/i2c-stub.c` 如何使用数组参数？
3. `kernel/printk/printk.c` 中 `console_loglevel` 参数如何工作？

**查找命令**：

```bash
# 在内核源码中查找 module_param 使用示例
grep -r "module_param(" third_party/linux-imx/drivers/ | head -20

# 查看特定驱动的参数实现
cat third_party/linux-imx/drivers/video/logo/logo.c | grep -A2 "module_param"
```

## 八、延伸阅读

- [Linux内核文档：kernel-parameters.txt](https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html)
- [Linux内核文档：dynamic-debug-howto](https://www.kernel.org/doc/html/latest/admin-guide/dynamic-debug-howto.html)
- 内核源码：include/linux/moduleparam.h
- 内核源码：kernel/params.c
- 内核源码：include/linux/dynamic_debug.h

---

**下一章预告**：

掌握了模块参数和调试技巧后，你已经具备了基本的驱动开发能力。下一章，我们将深入字符设备驱动，学习如何创建 `/dev` 节点、实现 file_operations 结构体，并编写一个完整的虚拟设备驱动。
