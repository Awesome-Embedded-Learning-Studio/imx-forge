---
title: 新 API 驱动解析
---

# 新 API 驱动代码深度解析 - 我们是怎么把代码重构成人能读的样子

## 前言：为什么要折腾这个

前面我们已经把老 API 驱动跑起来了，说实话，虽然能用，但代码写起来真的挺别扭的。硬编码主设备号、手动创建设备节点、资源浪费严重，这些问题在写简单驱动的时候还能忍受，但一旦项目复杂起来，这些坑会让你踩到怀疑人生。

所以我们决定用新 API 重写驱动。新 API 虽然代码量多一些，但每个步骤都清清楚楚，该申请什么资源、该释放什么资源，明明白白。更重要的是，它解决了老 API 的那些硬伤：动态分配设备号避免冲突，按需申请资源避免浪费，还能自动创建设备节点不用每次手动 mknod。

## 驱动结构：文件是怎么组织的

我们先看看新驱动的文件组织，和 v1 老驱动相比，现在的结构清晰多了：

```
driver/chardev_led_v2_02/alpha-board/
├── chardev_led_v2_02_driver_main.c  # 主驱动文件
├── led_hw.c                          # 硬件抽象层实现
├── led_hw.h                          # 硬件抽象层接口
├── led_reg.h                         # 寄存器定义
└── Makefile                          # 构建配置
```

以前我们把所有代码都塞在一个文件里，后来发现这根本不是个好主意。硬件操作、设备管理、文件操作，全部混在一起，改一个地方得在几百行代码里翻半天。现在我们把这些职责分开了，led_hw 负责硬件操作，主驱动负责设备管理和用户接口，各司其职。

新驱动和老驱动最大的区别，其实是设计思想的变化。老驱动就是"能跑就行"，代码怎么写都无所谓；新驱动我们开始关注可维护性，用结构体封装设备信息，用函数抽象硬件操作，虽然代码量多了不少，但以后要改功能或者调试问题，会轻松很多。

## 设备结构体：我们把所有东西打包在一起

新驱动引入了一个核心结构体 `struct IMXAesLED`，这是整个驱动的设计基础：

```c
struct IMXAesLED {
    dev_t devid;
    struct cdev char_device_handle;
    struct class* char_device_class;
    struct device* char_device_device;
} led_handle;
```

这个结构体把所有与设备相关的资源都打包在一起了。devid 是设备号，char_device_handle 是 cdev 结构体，char_device_class 是设备类，char_device_device 是设备本身。以前我们用全局变量到处散乱地存这些东西，现在统一放在一个结构体里，管理起来方便多了。

说句实话，一开始我们觉得这个结构体有点多此一举，反正就一个设备，直接用全局变量不也挺好吗。但后来当需要支持多个设备实例的时候，才意识到这个设计的价值。每个实例有自己的 IMXAesLED 结构体，互不干扰，扩展性一下子就上来了。

## init_led_handle()：新 API 的三步走

初始化函数是新驱动的核心，完整展示了新 API 的"三步走"流程。我们把这个函数拆开来看，每一步都做得很清楚。

### 第一步：动态申请设备号

```c
ret = alloc_chrdev_region(&led_handle->devid, 0, LED_CNT, CHARDEV_NAME);
if (ret < 0) {
    return ret;
}
```

这里我们用 `alloc_chrdev_region` 动态申请设备号，而不是像老 API 那样硬编码一个主设备号。函数的第一个参数 `&led_handle->devid` 是传出参数，内核会把分配到的设备号写到这里；第二个参数 `0` 是次设备号的起始值；第三个参数 `LED_CNT` 是我们要申请的设备数量；第四个参数 `CHARDEV_NAME` 是设备名称，会出现在 `/proc/devices` 里。

动态分配的好处是，我们不需要猜哪个设备号是空闲的，内核会自动找一个给我们用。老驱动硬编码主设备号 200，如果系统里已经有驱动占用了这个号，我们的驱动注册就会失败。这个问题真的坑了我们好几次，换了个开发板或者加载了其他驱动，突然就起不来了，查半天才发现是设备号冲突。

分配成功后，我们打印一下分配到的设备号，方便调试：

```c
const auto led_major_number = MAJOR(led_handle->devid);
const auto led_minor_number = MINOR(led_handle->devid);

pr_info("LED handle get the device number: major: %u, minor: %u\n",
        led_major_number, led_minor_number);
```

### 第二步：初始化并注册 cdev

拿到设备号之后，下一步就是初始化并注册 cdev 结构体：

```c
led_handle->char_device_handle.owner = THIS_MODULE;
cdev_init(&led_handle->char_device_handle, &fops);

ret = cdev_add(&led_handle->char_device_handle,
               led_handle->devid, LED_CNT);
if (ret < 0) {
    pr_warn("Error when trying to make a cdev in kernel: %d\n", ret);
    return ret;
}
```

这里的 `THIS_MODULE` 宏很重要，它告诉内核这个 cdev 属于当前模块，防止模块在使用时被卸载。说实话，这个细节很容易被忽略，但如果你忘记设置这个字段，在某些情况下可能会遇到奇怪的问题，比如模块被卸载了但还有进程在使用设备，然后内核就炸了。

`cdev_init` 初始化 cdev 结构体，并把我们的 `file_operations` 结构体关联上去。`cdev_add` 把 cdev 添加到内核，这时候设备就正式注册了。

### 第三步：创建类和设备

最后一步是创建类和设备，这也是新 API 相比老 API 最大的改进：

```c
led_handle->char_device_class = class_create(CHARDEV_NAME);
if (IS_ERR(led_handle->char_device_class)) {
    const auto error_code = PTR_ERR(led_handle->char_device_class);
    pr_warn("Failed to create a class, code: %ld", error_code);
    return error_code;
}

led_handle->char_device_device =
    device_create(led_handle->char_device_class, NULL,
                  led_handle->devid, NULL, CHARDEV_NAME);
if (IS_ERR(led_handle->char_device_device)) {
    const auto error_code = PTR_ERR(led_handle->char_device_device);
    pr_warn("Failed to create a device, code: %ld", error_code);
    return error_code;
}
```

`class_create` 创建一个设备类，会出现在 `/sys/class` 目录下。`device_create` 创建具体的设备，这一步会自动在 `/dev` 目录下创建设备节点。也就是说，我们再也不用手动执行 `mknod` 命令了，驱动加载完设备节点就自动出现在 `/dev` 目录下。

说实话，这个改进真的太赞了。老驱动每次加载后都要手动创建设备节点，忘记这步的话用户程序就访问不了设备，而且用户必须知道正确的主设备号和次设备号，对新手来说很不友好。现在好了，`insmod` 完就能直接用，体验完全不一样。

这里要注意 `IS_ERR` 和 `PTR_ERR` 的用法。内核里很多函数用指针返回值，成功时返回有效指针，失败时返回错误码编码的指针。`IS_ERR` 判断是否是错误指针，`PTR_ERR` 把错误指针转换成错误码。这个模式和普通的返回值判断不太一样，一开始用的时候真的搞混了好几次。

## 错误处理：别让错误悄无声息地溜走

上面的代码为了简洁省略了错误处理，但在实际代码里，每一步都可能失败，我们需要妥善处理。正确的做法是用 goto 模式进行逆序清理：

```c
static int init_led_handle(struct IMXAesLED* led_handle)
{
    int ret;

    ret = alloc_chrdev_region(&led_handle->devid, 0, LED_CNT, CHARDEV_NAME);
    if (ret < 0) {
        return ret;
    }

    led_handle->char_device_handle.owner = THIS_MODULE;
    cdev_init(&led_handle->char_device_handle, &fops);

    ret = cdev_add(&led_handle->char_device_handle,
                   led_handle->devid, LED_CNT);
    if (ret < 0) {
        goto failed_cdev;
    }

    led_handle->char_device_class = class_create(CHARDEV_NAME);
    if (IS_ERR(led_handle->char_device_class)) {
        ret = PTR_ERR(led_handle->char_device_class);
        goto failed_class;
    }

    led_handle->char_device_device =
        device_create(led_handle->char_device_class, NULL,
                      led_handle->devid, NULL, CHARDEV_NAME);
    if (IS_ERR(led_handle->char_device_device)) {
        ret = PTR_ERR(led_handle->char_device_device);
        goto failed_device;
    }

    return 0;

failed_device:
    class_destroy(led_handle->char_device_class);
failed_class:
    cdev_del(&led_handle->char_device_handle);
failed_cdev:
    unregister_chrdev_region(led_handle->devid, LED_CNT);
    return ret;
}
```

错误处理的思路是，如果某一步失败了，就往前清理已经分配的资源。创建顺序是 alloc_chrdev_region → cdev_add → class_create → device_create，清理顺序就是反过来的 device_destroy → class_destroy → cdev_del → unregister_chrdev_region。

说实话，这种 goto 模式一开始看着有点怪，但写多了你会发现它确实是处理多步初始化的最佳实践。每一步失败都有一个对应的清理标签，资源不会泄漏，代码逻辑也清晰。别一听到 goto 就觉得是坏习惯，在内核代码里，这是标准写法。

## release_led_handle()：逆序清理的艺术

卸载函数比初始化函数简单得多，核心就是逆序清理资源：

```c
static void release_led_handle(struct IMXAesLED* led_handle)
{
    device_destroy(led_handle->char_device_class,
                   led_handle->devid);
    class_destroy(led_handle->char_device_class);
    cdev_del(&led_handle->char_device_handle);
    unregister_chrdev_region(led_handle->devid, LED_CNT);
}
```

清理顺序一定要对，最后创建的最先销毁，最先创建的最后销毁。如果顺序乱了，可能会出现内核试图访问已经被释放的资源，然后就 panic 了。这种问题真的很难调试，因为不是每次都会复现，但一出现就是致命的。

卸载完成后，我们可以验证一下资源是否真的被释放了：

```bash
# 验证设备节点被删除
$ ls /dev/AES_LED
ls: /dev/AES_LED: No such file or directory

# 验证设备号被释放
$ cat /proc/devices | grep AES_LED
# （无输出，设备号已释放）
```

如果设备节点还在或者设备号还在释放，那说明我们的清理函数有问题，资源泄漏了。在嵌入式系统里，反复加载卸载驱动是常见操作，资源泄漏会慢慢耗尽系统资源，最后系统就起不来了。

## 与硬件抽象层的集成：分层设计的好处

新驱动的另一个重要改进是引入了硬件抽象层。硬件相关的操作全部封装在 led_hw.c 里，主驱动通过简洁的接口调用：

```c
void led_hw_init(void);
void led_hw_deinit(void);
void led_set_status(bool status);
bool led_get_status(void);
```

这样的设计有什么好处呢？首先是代码复用，硬件操作可能被多处调用，封装成函数就不用重复写了。其次是隔离变化，硬件相关的代码集中在一个地方，以后换硬件或者改寄存器操作，只需要修改硬件抽象层，主驱动代码不用动。

主驱动的 write 函数就是这样调用硬件抽象层的：

```c
static ssize_t aes_chardev_write(struct file* filp, const char __user* buf,
                                 size_t cnt, lloff_t* offt)
{
    /* ... 参数验证 ... */

    const bool led_new_status = (user_led_new_status == '1') ? true : false;
    pr_info("LED status: %d (user_led_new_status='%c')\n",
            led_new_status, user_led_new_status);

    led_set_status(led_new_status);  /* 调用硬件抽象层 */
    return 1;
}
```

主驱动根本不关心硬件是怎么操作的，它只知道调用 `led_set_status` 就能设置 LED 状态。这种抽象让代码更易读，也更容易测试。你可以在硬件抽象层下面模拟硬件，单独测试主驱动的逻辑。

## 模块初始化和退出：把所有步骤串起来

最后我们看一下模块的初始化和退出函数，把所有步骤串起来：

```c
static int __init chardev_led_v2_02_init(void)
{
    pr_info("=== led driver using new api ===\n");
    led_hw_init();
    init_led_handle(&led_handle);
    pr_info("========================\n");
    return 0;
}

static void __exit chardev_led_v2_02_exit(void)
{
    pr_info("=== chardev_led_v2_02驱动卸载成功 ===\n");
    release_led_handle(&led_handle);
    led_hw_deinit();
    pr_info("========================\n");
}
```

初始化的顺序是先硬件后软件，先初始化硬件，再注册设备。退出的顺序是反过来的，先注销设备，再清理硬件。这个顺序不能乱，乱了就会出问题。

说实话，写到这里我们真的感慨很多。从老 API 到新 API，代码量确实增加了不少，但换来的是更清晰的架构、更安全的资源管理、更好的用户体验。这些改进在写简单驱动的时候可能不明显，但一旦项目复杂起来，你会感谢自己一开始就选择了正确的路。

## 本章小结

这一章我们深入分析了新 API 驱动的实现。核心是 init_led_handle() 函数展示的"三步走"：alloc_chrdev_region 动态申请设备号，cdev_init + cdev_add 初始化并注册 cdev，class_create + device_create 创建类和设备。释放的时候要逆序清理，device_destroy → class_destroy → cdev_del → unregister_chrdev_region。

与老驱动相比，新驱动在架构上有很多改进。设备结构体封装了所有设备相关信息，硬件抽象层分离了硬件操作和业务逻辑，动态设备号分配避免了冲突，自动创建设备节点改善了用户体验。这些改进让代码更易维护、更易扩展。

下一章我们会写用户空间的应用程序，测试这个驱动，看看真实环境下是怎么跑的。

---

**相关文档**：
- [老 API 字符设备驱动](06_legacy_chardev.md)
- [应用开发与真实测试](18_app_development_and_testing.md)
