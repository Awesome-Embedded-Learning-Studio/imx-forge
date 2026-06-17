# 自旋锁完整踩坑记录：为什么你的内核会死锁

## 前言：当原子操作不够用时

上一节我们聊了原子操作，最后提到了`test_and_set_bit`这种「先到先得」的逻辑。这其实就是一个最简单的自旋锁原型。如果你能理解「如果位已经被置1了，我就得在循环里一直等到它变0」，那你其实就已经理解了自旋锁的一半了。

这一节，我们要把这半个位，扩展成一个内核正式承认的「锁」。

老实说，自旋锁是我踩坑最多的地方。第一次用的时候，我以为「不就是加锁解锁吗」，结果系统直接死锁。第二次用的时候，我以为「这次我注意了，不在锁里睡觉」，结果系统还是死锁了。第三次，我终于理解了——**自旋锁不是玩具，它有它的脾气。**

## 从电话亭到自旋锁：理解「忙等待」

原子操作确实好用，但它有一个致命的局限：它只能保护**一个变量**。

现实世界里，我们的临界区往往没那么简单。你可能在操作一个设备结构体，里面有状态、有缓冲区指针、有配置寄存器的映射地址。你操作了状态，还没来得及操作指针，中间被别的线程插了一杠子——数据结构就乱了。

这时候，我们需要一种更粗暴但也更通用的机制：一把锁。
这把锁只有一个原则——**一次只有一个人能进来**。

### 自旋锁的逻辑：傻傻地等待

自旋锁的逻辑非常直白，甚至可以说有点「傻」。

想象一个只有一个隔间的公用电话亭（现在的年轻人可能只在老电影里见过了）。

1. 线程A走到电话亭门口，发现没人，于是推门进去，锁上了门。
   * 这就叫**获取锁**。
2. 线程B也来了，它想打电话，但门锁着。
   * 如果是信号量（后面会讲），线程B会留下一句电话号码，回家睡觉去了，等A打完电话叫醒它。
   * 但在**自旋锁**的世界里，线程B不会走。它就站在门口，透过玻璃看着A，原地转圈圈。
   * 这就叫**自旋**。

线程B不会去干别的事，也不会进入休眠。它就在CPU上空转，死死盯着那个锁的状态。

### 必须付出的代价：CPU时间

这种「傻等」的策略是有代价的。

如果线程A打电话打很久，线程B就要在门口转很久圈。这段时间里，线程B占用着CPU时间片，却什么有用的事都没干。对于整个系统来说，这是纯粹的浪费。

所以，**自旋锁有一个铁律：被自旋锁保护的临界区必须非常短**。

短到什么程度？最好是几条指令，或者几个寄存器读写。如果你需要在锁里拷贝大文件、等待硬件响应、或者做复杂的数学运算，那你就选错锁了。

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7 dual-core) |
| 相关头文件 | `include/linux/spinlock.h` |

## 自旋锁基础：从定义到使用

Linux内核用`spinlock_t`结构体来表示自旋锁。

```c
/* include/linux/spinlock_types.h */
typedef struct spinlock spinlock_t;
```

虽然内核开发者为了调试和优化，在这个结构体里塞了很多条件编译的宏（比如`CONFIG_DEBUG_LOCK_ALLOC`用于检测锁的依赖关系），但剥去外壳，它本质上就是一个对原始自旋锁结构体的封装。

### 定义与初始化

使用前，你需要先定义一把锁：

```c
spinlock_t lock;  /* 定义自旋锁 */
```

光定义还不够，这把锁现在的状态是「未初始化」，甚至可能是个悬空指针。初始化之后才能用。

**静态初始化：**

```c
static DEFINE_SPINLOCK(my_lock);  /* 定义并初始化一个静态锁 */
```

**动态初始化：**

```c
spinlock_t my_lock;
spin_lock_init(&my_lock);  /* 运行时初始化 */
```

### 基本 API

| 函数 | 描述 |
| --- | --- |
| `DEFINE_SPINLOCK(name)` | 静态定义并初始化一个锁变量 |
| `spin_lock_init(spinlock_t *lock)` | 动态初始化自旋锁 |
| `spin_lock(spinlock_t *lock)` | 获取锁（加锁）。如果拿不到，就自旋等待 |
| `spin_unlock(spinlock_t *lock)` | 释放锁（解锁） |
| `spin_trylock(spinlock_t *lock)` | 尝试获取锁。如果锁被占用，立即返回0（失败），不等待 |
| `spin_is_locked(spinlock_t *lock)` | 检查锁是否被持有（返回非0表示被锁住） |

### 一个简单的例子

```c
#include <linux/spinlock.h>

static DEFINE_SPINLOCK(my_lock);
static int shared_data = 0;

void writer_function(void) {
    /* 获取锁 */
    spin_lock(&my_lock);

    /* 临界区：安全地访问共享数据 */
    shared_data++;
    pr_info("shared_data = %d\n", shared_data);

    /* 释放锁 */
    spin_unlock(&my_lock);
}
```

这看起来很简单，对吧？但这里藏着**两个致命的坑**。

## 坑一：在持有自旋锁时睡觉——死锁的配方

现在我们有了一个看起来很完美的机制：

你要进临界区？`spin_lock()`。
搞定了吗？`spin_unlock()`。

但这里有一个**绝对的禁忌**：

> **在持有自旋锁的时候，绝对不能调用任何会引起睡眠（休眠）的函数。**

为什么？

因为自旋锁会禁止内核抢占。这意味着，当线程A拿着锁的时候，调度器不能把它强行切走。如果线程A在临界区里突然睡着了（比如调用了`copy_from_user`，而页面不在内存中，需要等待硬盘读取），线程A就会带着锁一起睡觉。

此时，线程B试图获取同一把锁。它发现锁被A占着，于是开始自旋。但问题是，**A在睡觉，而B因为自旋锁禁止抢占，无法被调度出去让出CPU给A**。

A不醒来就不释放锁，B不释放CPU就不让你跑……系统彻底僵死。这就是典型的**死锁**。

### 哪些函数会睡觉？

这是个好问题。常见的会睡觉的函数包括：

* `copy_from_user()` / `copy_to_user()` - 用户空间内存访问
* `kmalloc(GFP_KERNEL)` - 内核内存分配（除了`GFP_ATOMIC`）
* `msleep()` - 睡眠指定毫秒数
* `wait_event_*()` - 等待事件
* `down_*()` - 获取信号量
* `mutex_lock_*()` - 获取互斥体

**⚠️ 记住这个原则**：

> 如果你在临界区里调用了任何可能阻塞的函数，用自旋锁就是错的。改用互斥体（mutex）。

## 坑二：中断打断持有锁的线程——更隐蔽的死锁

上面的死锁是线程与线程之间的事。如果把**中断**卷进来，情况会更复杂。

请看这个场景：

1. **线程A**获取了`lock`，正在临界区里愉快地读写数据
2. 突然，**硬件中断**发生了，CPU暂停线程A，跳转到中断服务程序（ISR）执行
3. **中断服务程序**里也要访问同一个共享资源，于是它也调用了`spin_lock(&lock)`
4. **卡死**。

```
线程A                           中断
----------------------------------------
spin_lock(&lock)                 <-- 中断发生
  |

  | (正在访问临界区)             spin_lock(&lock)
  |                               |
  |                               | (死等A释放锁)
  |                               |
  |
spin_unlock(&lock)               <-- 永远不会执行
```

中断说：「你先把锁放开我才能干活。」
线程A说：「你把CPU还给我，让我跑完，我就能放开锁。」
互相指着鼻子，谁也动不了。

### 解决方案：关闭中断

怎么破局？

既然中断会打断持有锁的线程，那我们在拿锁之前，先把中断关了不就好了？这样，只要我拿到了锁，中断就无法在我的CPU核上执行，也就不可能出现「中断试图获取我正持有的锁」这种情况。

内核提供了一组专门的API来处理这件事：

| 函数 | 描述 |
| --- | --- |
| `spin_lock_irq(spinlock_t *lock)` | 禁止本地（本CPU）中断，并获取锁 |
| `spin_unlock_irq(spinlock_t *lock)` | 激活本地中断，并释放锁 |
| `spin_lock_irqsave(spinlock_t *lock, flags)` | **保存当前中断状态，禁止本地中断，并获取锁** |
| `spin_unlock_irqrestore(spinlock_t *lock, flags)` | **恢复之前保存的中断状态，释放锁** |

这里有一个技术细节：`spin_lock_irq`假设你知道当前中断是开着的，直接关就行。但在复杂的内核里，你可能不知道调用你函数的人是不是已经把中断关了一半了。

所以，**永远优先使用`spin_lock_irqsave`**。它会把当前中断状态（开还是关）存到`flags`变量里，等你释放锁的时候，原样恢复回去。这叫「好借好还」。

### 代码实战：线程与中断的握手

```c
#include <linux/spinlock.h>

static DEFINE_SPINLOCK(my_lock);
static int shared_data = 0;

/* 线程上下文：可以被中断打断 */
void thread_function(void) {
    unsigned long flags;  /* 用于保存中断状态的变量，必须是栈上变量 */

    /* 1. 保存状态 -> 关中断 -> 拿锁 */
    spin_lock_irqsave(&my_lock, flags);

    /* 临界区：安全地访问共享资源 */
    /* 此时，本地中断被关闭，线程不会被抢占，也不会被本CPU的中断打断 */
    shared_data++;
    pr_info("shared_data = %d\n", shared_data);

    /* 2. 恢复状态 -> 开中断 -> 释放锁 */
    spin_unlock_irqrestore(&my_lock, flags);
}

/* 中断服务函数：ISR上下文，本来就会打断线程 */
irqreturn_t irq_handler(int irq, void *dev_id) {
    /* 中断里已经天然禁止了其他中断（部分情况），且中断不能睡眠 */
    spin_lock(&my_lock);  /* 获取锁 */

    /* 临界区 */
    shared_data++;

    spin_unlock(&my_lock);  /* 释放锁 */

    return IRQ_HANDLED;
}
```

**注意**：

* 在线程（`thread_function`）里，我们用的是`irqsave`版本。因为我们要防止自己被打断
* 在中断（`irq_handler`）里，我们用的是普通版`spin_lock`。为什么？
  * 首先，中断处理程序执行时，本地中断通常已经在一定程度上被屏蔽了
  * 其次，中断里不能睡眠，用普通版就够了

## 坑三：下半部（Bottom Half）也需要特殊处理

除了中断，Linux还有「下半部」机制（软中断、tasklet、工作队列等），用于把中断处理中不紧急的部分延后处理。

如果下半部也要访问共享资源，你不能用普通的关中断锁，要用专门针对下半部的API：

```c
spin_lock_bh(&lock);
/* 临界区 */
spin_unlock_bh(&lock);
```

它的原理是：关掉下半部的处理，但允许硬件中断继续跑。这在某些需要快速响应硬件中断的场景下很有用。

## 进阶：读写自旋锁——让读者并发

自旋锁是独占的。哪怕有10个线程只是想**读**一个数据，不修改它，只要有一个线程拿到了读锁，其他9个读者也得在外面排队。

这对于「读多写少」的数据（比如系统配置表）来说，太浪费了。

能不能让多个人同时读，只有写的时候才独占？可以。这就进化出了**读写自旋锁**。

### 读写锁的基本概念

**逻辑**：

* **读锁**：如果没有写者，多个读者可以同时持有读锁
* **写锁**：必须等到所有读者和写者都释放锁，才能获取写锁。一旦持有写锁，其他任何人（读者或写者）都不能进

**结构体** (`rwlock_t`)：

```c
typedef struct {
    arch_rwlock_t raw_lock;
} rwlock_t;
```

### 定义与初始化

```c
/* 静态定义 */
static DEFINE_RWLOCK(my_rwlock);

/* 或者动态初始化 */
rwlock_t my_rwlock;
rwlock_init(&my_rwlock);
```

### 读写锁 API

| 函数 | 描述 |
| --- | --- |
| `read_lock(lock)` / `read_unlock(lock)` | 读者用 |
| `write_lock(lock)` / `write_unlock(lock)` | 写者用 |
| `read_lock_irqsave(lock, flags)` | 读锁+关中断版本 |
| `write_lock_irqsave(lock, flags)` | 写锁+关中断版本 |

### 读写锁示例

```c
#include <linux/spinlock.h>

static DEFINE_RWLOCK(config_lock);
static int device_config = 0;

/* 读取配置：多个读者可以同时执行 */
int read_config(void) {
    int val;

    read_lock(&config_lock);
    val = device_config;  /* 读取配置 */
    read_unlock(&config_lock);

    return val;
}

/* 更新配置：写者独占 */
void update_config(int new_val) {
    write_lock(&config_lock);
    device_config = new_val;  /* 修改配置 */
    write_unlock(&config_lock);
}
```

## 进阶：顺序锁——写者优先的激进方案

读写锁有个缺点：读者来了，写者就得等。如果读者特别多，写者可能饿死。而且，读者在持有读锁时，写者无法写入，这可能会阻塞写操作很久。

Linux还有一种更激进的锁：**顺序锁**（`seqlock_t`）。

### 顺序锁的基本概念

**逻辑**：

* **写者**：不阻塞读者。写者拿到锁直接写，不管有没有人在读
* **读者**：可以直接读取。但是，读者在读之前要记录一个「序列号」，读完之后再检查序列号
  * 如果序列号没变，说明刚才读的时候没有写者插进来，数据有效
  * 如果序列号变了，说明刚才读的时候发生了写入操作，数据可能不一致
  * **解决办法**：重读

**致命限制**：你不能用顺序锁保护**指针**。为什么？假设写者正在把指针A改成指针B。读者读到一半，可能读到了前半部分的指针A，后半部分的指针B，拼出一个野指针，系统直接崩。

### 顺序锁 API

| 函数 | 描述 |
| --- | --- |
| `DEFINE_SEQLOCK(name)` | 静态定义并初始化顺序锁 |
| `seqlock_init(lock)` | 动态初始化顺序锁 |
| `write_seqlock(lock)` / `write_sequnlock(lock)` | 写者用 |
| `read_seqbegin(lock)` | 读者开始读，返回序列号 |
| `read_seqretry(lock, seq)` | 读者结束读，检查是否需要重读 |

### 顺序锁示例

```c
#include <linux/seqlock.h>

static DEFINE_SEQLOCK(data_lock);
static unsigned long shared_data = 0;

/* 写者：不需要等待读者 */
void writer_function(void) {
    write_seqlock(&data_lock);
    shared_data++;
    write_sequnlock(&data_lock);
}

/* 读者：可能需要重读 */
unsigned long reader_function(void) {
    unsigned long seq, val;

    do {
        seq = read_seqbegin(&data_lock);
        val = shared_data;  /* 读取数据 */
    } while (read_seqretry(&data_lock, seq));

    return val;
}
```

## raw_spinlock_t vs spinlock_t：RT内核的区别

在Linux 7.0中，你可能会看到两种自旋锁：`raw_spinlock_t`和`spinlock_t`。

这是什么区别？

在普通内核中，它们是一样的。但在**PREEMPT_RT**（实时内核）补丁中，它们的实现完全不同：

* `raw_spinlock_t`：真正的自旋锁，即使在RT内核中也是自旋等待
* `spinlock_t`：在RT内核中被实现为可睡眠的互斥体

**⚠️ 重要**：

> 如果你在写通用驱动代码，不确定是否会在RT内核中运行，优先使用`spinlock_t`。只有在确定需要真正的自旋行为（比如在中断上下文中）时，才使用`raw_spinlock_t`。

## 使用自旋锁的四大纪律

在结束自旋锁这一节前，把最后这四条纪律刻在脑门上。违反任何一条，你都可能收获一个莫名其妙的Kernel Panic。

### 1. 短小精悍

持有锁的时间必须极短。不要在锁里做耗时操作，不要在锁里拷贝大块内存，更不要在锁里访问可能阻塞的硬件。

### 2. 严禁睡眠

临界区内不能调用任何可能引起`schedule()`的函数（如`kmalloc(GFP_KERNEL)`，`copy_from_user`等）。一旦睡去，死锁随之而来。

### 3. 严禁递归

你不能递归地申请自旋锁。如果你已经拿着锁了，再次调用`spin_lock(&同一个锁)`，你会发现自己正在等待自己释放锁。但因为自旋锁禁止抢占，你永远没有机会去执行那个「释放」的动作。这叫「自己把自己锁死」。

### 4. 当它是多核

即使你现在的板子是单核CPU，也要把它当成多核来写代码。为什么？因为单核下也有抢占和中断并发。不要心存侥幸。只要用了自旋锁，就假设有别人正在和你抢。

## 这一小节就到这里

自旋锁是内核并发控制的中坚力量。它让CPU空转等待，保证了临界区的独占访问。但它要求你非常小心：临界区必须极短，绝对不能睡眠，小心处理中断，不能递归。

下一章，我们要看互斥体和信号量——那些让等待者去睡觉的锁。它们允许临界区较长，也允许睡眠，但代价是更高的切换开销。

选择哪一种锁，本质上是在权衡两个东西：**保护的成本**与**等待的代价**。

---

## 本章要点

1. **自旋锁让CPU空转等待**，因此临界区必须极短。禁止在锁内睡眠。
2. **`spin_lock_irqsave`是线程中最安全的版本**，它保存并恢复中断状态，防止中断导致的死锁。
3. **读写锁允许读者并发**，适合「读多写少」的场景。
4. **顺序锁允许写者不阻塞读者**，但不能保护指针。适合读者重试成本低的场景。
5. **raw_spinlock_t vs spinlock_t**：在RT内核中不同。通用代码用`spinlock_t`。
6. **四大纪律**：短小精悍、严禁睡眠、严禁递归、当它是多核。
