# 信号量与互斥体：会睡觉的锁

## 前言：当自旋锁不够用时

上一节我们讲了自旋锁，那个让CPU「傻傻空转」的锁。你可能已经注意到它的一个致命缺点：**如果临界区很长，等待的CPU就浪费很多时间在空转上**。

而且，自旋锁有一个严格的限制：**不能在临界区里睡觉**。这意味着你不能在锁里调用任何可能阻塞的函数——不能拷贝用户空间数据，不能用`GFP_KERNEL`分配内存，不能等待硬件响应。

那怎么办？

如果你的临界区确实需要很长时间，或者确实需要调用可能阻塞的函数，你就需要另一种锁：**会让等待者睡觉的锁**。

这一节，我们讲两种会睡觉的锁：**信号量**（Semaphore）和**互斥体**（Mutex）。

## 从电话亭到排队：理解「睡眠等待」

还记得自旋锁那个电话亭的比喻吗？

* 自旋锁：线程B发现电话亭被占，就站在门口原地转圈，死等
* 信号量/互斥体：线程B发现电话亭被占，就留个电话号码，回家睡觉去了。等A打完电话，会打电话通知B

显然，第二种方式更文明，也更高效。B睡觉的时候，CPU可以去干别的事，不会浪费在空转上。

但这种方式也有代价：**上下文切换的开销**。当B被唤醒时，需要重新调度回CPU，这比自旋锁的「立即获得」要慢得多。

所以，选择哪种锁，本质上是在权衡：
* **自旋锁**：等待时间短，但浪费CPU
* **信号量/互斥体**：等待时间长，但节省CPU

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7 dual-core) |
| 相关头文件 | `include/linux/mutex.h`, `include/linux/semaphore.h` |

## 互斥体：现代内核的首选

在Linux内核中，**互斥体**（Mutex）是用于互斥访问的首选机制。它比信号量更轻量，而且有额外的调试支持。

### 什么是互斥体？

互斥体本质上是一个二值信号量（只有0和1两个值），但它有一些特殊属性：

1. **所有权**：互斥体有「所有者」的概念。只有获取锁的线程才能释放锁
2. **递归检测**：同一个线程不能递归获取同一个互斥体（除非显式初始化为可递归）
3. **调试支持**：有lockdep集成，可以检测死锁

### 定义与初始化

```c
#include <linux/mutex.h>

/* 静态定义并初始化 */
static DEFINE_MUTEX(my_mutex);

/* 或者动态初始化 */
static struct mutex my_mutex;
mutex_init(&my_mutex);
```

### 互斥体 API

| 函数 | 描述 |
| --- | --- |
| `DEFINE_MUTEX(name)` | 静态定义并初始化互斥体 |
| `mutex_init(mutex)` | 动态初始化互斥体 |
| `mutex_lock(mutex)` | 获取互斥体（不可中断） |
| `mutex_unlock(mutex)` | 释放互斥体 |
| `mutex_lock_interruptible(mutex)` | 可中断地获取互斥体 |
| `mutex_lock_killable(mutex)` | 可被kill信号中断地获取互斥体 |
| `mutex_trylock(mutex)` | 尝试获取，不等待 |
| `mutex_is_locked(mutex)` | 检查是否被锁定 |

### 互斥体示例

```c
#include <linux/mutex.h>
#include <linux/slab.h>

static DEFINE_MUTEX(device_mutex);
static struct device_data *shared_data;

/* 更新设备数据 */
void update_device_data(int new_val) {
    /* 获取互斥体 */
    mutex_lock(&device_mutex);

    /* 临界区：可以安全地调用可能阻塞的函数 */
    if (!shared_data) {
        /* GFP_KERNEL分配可能睡眠，但在互斥体保护下是安全的 */
        shared_data = kmalloc(sizeof(*shared_data), GFP_KERNEL);
    }

    if (shared_data) {
        shared_data->value = new_val;
    }

    /* 释放互斥体 */
    mutex_unlock(&device_mutex);
}

/* 读取设备数据 */
int read_device_data(void) {
    int val;

    mutex_lock(&device_mutex);
    if (shared_data) {
        val = shared_data->value;
    } else {
        val = -1;
    }
    mutex_unlock(&device_mutex);

    return val;
}
```

### 可中断版本：`mutex_lock_interruptible`

有时候，你希望等待锁的线程可以被信号打断。比如用户按了Ctrl+C，你不希望线程死死等在那里。

```c
int function_with_interruptible_lock(void) {
    /* 可中断地获取互斥体 */
    if (mutex_lock_interruptible(&my_mutex)) {
        /* 返回非0表示被信号中断 */
        return -ERESTARTSYS;  /* 系统调用被中断的标准返回值 */
    }

    /* 临界区 */
    do_something();

    mutex_unlock(&my_mutex);
    return 0;
}
```

> **⚠️ 注意**
>
> 如果你使用了`mutex_lock_interruptible`，**一定要检查返回值**。如果返回非0，说明你没有获得锁，千万不要访问临界区资源。

### 互斥体 vs 自旋锁：决策树

```
临界区会睡眠吗？
├─ 是 → 必须用互斥体
└─ 否 → 临界区短吗？
   ├─ 是（几条指令）→ 用自旋锁
   └─ 否（可能几十微秒以上）→ 考虑用互斥体
```

## 信号量：更灵活的计数器

信号量是比互斥体更通用的机制。它不仅仅是二值的（0或1），可以有任何非负整数值。

### 信号量的概念

信号量就像一个资源计数器：

* `down()`操作：计数器减1。如果计数器变成负数，调用者睡眠等待
* `up()`操作：计数器加1。如果有等待者，唤醒其中一个

计数器的初始值决定了同时可以有多少个执行流访问资源。

### 定义与初始化

```c
#include <linux/semaphore.h>

/* 静态定义并初始化 */
static DEFINE_SEMAPHORE(my_sem, 1);  /* 初始值为1，相当于互斥体 */

/* 或者动态初始化 */
static struct semaphore my_sem;
sema_init(&my_sem, 1);  /* 初始值为1 */
```

### 信号量 API

| 函数 | 描述 |
| --- | --- |
| `DEFINE_SEMAPHORE(name, value)` | 静态定义并初始化信号量 |
| `sema_init(sem, value)` | 动态初始化信号量 |
| `down(sem)` | 获取信号量（不可中断） |
| `down_interruptible(sem)` | 可中断地获取信号量 |
| `down_killable(sem)` | 可被kill信号中断地获取 |
| `down_trylock(sem)` | 尝试获取，不等待 |
| `down_timeout(sem, timeout)` | 带超时地获取 |
| `up(sem)` | 释放信号量 |

### 信号量示例

```c
#include <linux/semaphore.h>

/* 有3个相同资源的设备池 */
static DEFINE_SEMAPHORE(resource_sem, 3);
static int resource_count = 3;

/* 获取资源 */
int acquire_resource(void) {
    /* down会减少信号量，如果变成负数就等待 */
    if (down_interruptible(&resource_sem)) {
        return -ERESTARTSYS;  /* 被信号中断 */
    }

    /* 成功获取一个资源 */
    pr_info("Resource acquired. Available: %d\n",
            atomic_read(&resource_sem.count));

    return 0;
}

/* 释放资源 */
void release_resource(void) {
    up(&resource_sem);  /* 增加信号量，可能唤醒等待者 */

    pr_info("Resource released. Available: %d\n",
            atomic_read(&resource_sem.count));
}
```

### 二值信号量 vs 互斥体

你可能会问：**初始值为1的信号量和互斥体有什么区别？**

主要有以下区别：

| 特性 | 互斥体 | 信号量 |
| --- | --- | --- |
| 所有权 | 有，只有获取者能释放 | 无，任何人都能释放 |
| 用途 | 仅用于互斥 | 可用于计数、同步 |
| 调试支持 | lockdep集成 | 较弱 |
| 中断上下文 | 不能用 | 可以用（`down_trylock`） |
| 性能 | 更优化 | 稍慢 |

**推荐实践**：

> 如果你只是需要互斥访问（一次只有一个线程），**优先使用互斥体**。只有在需要信号量的其他特性（如计数、无所有权）时，才使用信号量。

## RT-Mutex：实时内核的互斥体

如果你在使用**PREEMPT_RT**（实时内核）补丁，互斥体会被特殊处理。

在RT内核中：
* `mutex`被实现为可睡眠的RT互斥体，具有优先级继承等实时特性
* `raw_spinlock_t`保持为真正的自旋锁
* `spinlock_t`被映射为RT互斥体

这是为什么在RT内核中，**几乎所有的驱动代码都应该使用互斥体而不是自旋锁**——除非你确实需要在中断上下文中使用。

## 实战对比：自旋锁 vs 互斥体

让我们用一个实际例子来对比两者的使用场景。

### 场景1：快速修改寄存器——用自旋锁

```c
#include <linux/spinlock.h>

static DEFINE_SPINLOCK(reg_lock);
void __iomem *register_base;

/* 快速设置寄存器 */
void set_register(int offset, u32 value) {
    unsigned long flags;

    /* 临界区极短：只有几条指令 */
    spin_lock_irqsave(&reg_lock, flags);
    writel(value, register_base + offset);
    spin_unlock_irqrestore(&reg_lock, flags);
}
```

### 场景2：拷贝用户数据——用互斥体

```c
#include <linux/mutex.h>

static DEFINE_MUTEX(data_mutex);
static char device_buffer[1024];

/* 从用户空间拷贝数据到设备 */
ssize_t device_write(struct file *file, const char __user *buf,
                     size_t count, loff_t *ppos) {
    ssize_t ret;

    mutex_lock(&data_mutex);

    /* copy_from_user可能睡眠，但在互斥体保护下是安全的 */
    if (copy_from_user(device_buffer, buf, count)) {
        ret = -EFAULT;
    } else {
        ret = count;
        /* 处理数据... */
    }

    mutex_unlock(&data_mutex);
    return ret;
}
```

## 什么时候不能用互斥体？

虽然互斥体很强大，但有些场景不能用：

### 1. 中断上下文

中断处理函数不能睡眠，因此不能使用互斥体。

```c
/* ❌ 错误：中断中不能使用互斥体 */
irqreturn_t irq_handler(int irq, void *dev_id) {
    mutex_lock(&my_mutex);  /* 可能睡眠，在中断中是非法的！ */
    /* ... */
    mutex_unlock(&my_mutex);
    return IRQ_HANDLED;
}

/* ✓ 正确：中断中使用自旋锁 */
irqreturn_t irq_handler(int irq, void *dev_id) {
    unsigned long flags;
    spin_lock_irqsave(&my_lock, flags);
    /* ... */
    spin_unlock_irqrestore(&my_lock, flags);
    return IRQ_HANDLED;
}
```

### 2. 持有锁时不能睡眠

虽然互斥体允许临界区睡眠，但如果你在临界区内又去获取另一个互斥体，可能会死锁。

```c
/* ❌ 危险：嵌套获取互斥体 */
void dangerous_function(void) {
    mutex_lock(&lock1);
    /* 如果这里睡眠，另一个线程获取了lock2... */
    mutex_lock(&lock2);  /* 可能死锁 */
    /* ... */
    mutex_unlock(&lock2);
    mutex_unlock(&lock1);
}
```

### 3. 原子上下文

任何原子上下文（如`RCU`临界区、NMI、`spin_lock`保护的临界区）都不能使用互斥体。

## 错误的代价：死锁

让我们用两个经典的死锁场景来结束这一节。

### 死锁场景1：ABBA死锁

```
线程A                    线程B
--------                 --------
mutex_lock(&lock1)      mutex_lock(&lock2)
/* 持有lock1 */          /* 持有lock2 */
mutex_lock(&lock2)      mutex_lock(&lock1)
/* 等待lock2 */          /* 等待lock1 */
/* 死锁！ */             /* 死锁！ */
```

**解决方法**：永远按照相同的顺序获取多个锁。

### 死锁场景2：自死锁

```c
/* ❌ 错误：试图递归获取互斥体 */
void recursive_function(void) {
    mutex_lock(&my_mutex);
    /* ... */
    recursive_function();  /* 递归调用，再次尝试获取my_mutex */
    /* ... */
    mutex_unlock(&my_mutex);
}
```

**解决方法**：重构代码，避免递归获取同一个锁。或者使用可递归的互斥体（但这是最后手段）。

## 这一小节就到这里

信号量和互斥体是内核中「会睡觉的锁」。它们允许临界区较长，也允许调用可能阻塞的函数，代价是上下文切换的开销。

对于大多数驱动代码，**互斥体是首选**：
* 它有所有权保护，更安全
* 它有lockdep调试支持
* 它的性能经过优化

只有在需要信号量的特殊特性（如计数、无所有权）时，才使用信号量。

下一节，我们要进入时间管理的世界——那些在内核中定时执行任务的机制。

---

## 本章要点

1. **互斥体是现代内核的首选**。它有所有权、调试支持，性能优化。
2. **信号量更通用**，可以是任何非负整数值，用于计数或同步。
3. **互斥体不能在中断上下文使用**。中断中用自旋锁。
4. **`mutex_lock_interruptible`必须检查返回值**，否则可能访问未保护的资源。
5. **避免ABBA死锁**：获取多个锁时，永远按相同顺序。
6. **决策树**：会睡眠→用互斥体；不会睡眠且极短→用自旋锁。
