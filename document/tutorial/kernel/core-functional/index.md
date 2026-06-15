---
title: 内核核心功能
---

<PageHeader icon="⚙️" title="内核核心功能" description="并发同步、中断、阻塞/非阻塞 I/O —— 编写健壮驱动绕不开的内核机制" />

## 为什么单独成组？

并发与同步是 Linux 内核里最容易踩坑、也最难调试的部分。一段在单核、不开抢占时永远正确的代码，换到 i.MX6ULL 的双核 Cortex-A7 + SMP + 抢占环境下，就可能因为时序的细微差异而偶发崩溃——这类「幽灵 Bug」往往调一整天都复现不了。

这一组教程把驱动开发真正用得上的内核机制集中讲透：从并发的来源与同步原语，到中断上下文，再到字符设备的三种 I/O 模型。学完之后，你会清楚什么场景该用自旋锁、什么场景该用信号量，以及为什么同一个 `read` 既可以阻塞、也可以立即返回、还能用信号通知。

::: tip 学习目标
掌握内核里的并发来源与同步原语（原子操作 / 自旋锁 / 互斥锁 / 信号量），理解中断上下文与处理流程，能用阻塞、非阻塞、异步通知三种模型编写字符设备驱动。
:::

::: info 前置知识
内核模块机制（[modules/](../../driver/modules/)）· 字符设备基础（[字符设备教程](../../driver/00_chardev_base/)）· C 语言高级特性
:::

## 教程目录

### 并发与同步

| 文件 | 标题 | 说明 |
|------|------|------|
| [01_concurrency_basics](01_concurrency_basics) | 并发基础 | 并发的四大来源、单核 vs 多核、为什么需要同步 |
| [02_atomic_operations](02_atomic_operations) | 原子操作 | 原子变量、内存屏障、典型用法 |
| [03_spinlocks](03_spinlocks) | 自旋锁 | spinlock 原理、读写自旋锁、使用约束 |
| [04_mutex_semaphore](04_mutex_semaphore) | 互斥锁与信号量 | mutex 与 semaphore 的区别与选型 |

### 时间与定时器

| 文件 | 标题 | 说明 |
|------|------|------|
| [05_time_management](05_time_management) | 时间管理 | jiffies、ktime、时间测量与延时 |
| [06_timer_practice](06_timer_practice) | 定时器实践 | 内核定时器、高精度定时器实战 |

### 中断

| 文件 | 标题 | 说明 |
|------|------|------|
| [07_interrupt_basics](07_interrupt_basics) | 中断基础 | 中断上下文、上半部 / 下半部机制 |
| [08_interrupt_practice](08_interrupt_practice) | 中断实践 | 注册与处理中断、顶半部与底半部协作 |

### I/O 模型

| 文件 | 标题 | 说明 |
|------|------|------|
| [09_blocking_io](09_blocking_io) | 阻塞 I/O | 等待队列、阻塞式 read 实现 |
| [10_nonblocking_io](10_nonblocking_io) | 非阻塞 I/O | O_NONBLOCK、poll / select 轮询机制 |
| [11_async_notification](11_async_notification) | 异步通知 | fasync 机制、SIGIO 信号通知用户空间 |

## 学习路径

1. 从 [01 并发基础](01_concurrency_basics) 建立对「并发」的全局认知
2. 用 [02 原子操作](02_atomic_operations)、[03 自旋锁](03_spinlocks)、[04 互斥锁与信号量](04_mutex_semaphore) 逐层掌握同步原语
3. 学习 [05 时间管理](05_time_management) 与 [06 定时器实践](06_timer_practice)
4. 攻克 [07 中断基础](07_interrupt_basics) 与 [08 中断实践](08_interrupt_practice)
5. 最后用 [09 阻塞 I/O](09_blocking_io)、[10 非阻塞 I/O](10_nonblocking_io)、[11 异步通知](11_async_notification) 理解三种 I/O 模型

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="01_concurrency_basics" variant="sub">从并发基础开始 →</ChapterLink>
  <ChapterLink href="../" variant="sub">← 返回内核教程</ChapterLink>
</ChapterNav>
