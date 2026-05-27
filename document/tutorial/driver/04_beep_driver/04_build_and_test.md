# 编译测试与调试 - 从代码到响声

前面我们把代码和设备树都分析完了，这一节来实战——编译、部署、测试。说实话，写代码只是第一步，跑起来才是真正的考验。

## 编译驱动

驱动代码的编译和普通 C 程序不同，需要用内核的构建系统。我们的 Makefile 很简单：

```makefile
obj-m := beep_driver.o

KERNEL_DIR := /path/to/kernel
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
```

`obj-m := beep_driver.o` 告诉内核构建系统，我们要编译一个模块 `beep_driver.ko`。`-C $(KERNEL_DIR)` 切换到内核目录，`M=$(PWD)` 回到当前目录编译模块。

::: tip KERNEL_DIR 要设置对
`KERNEL_DIR` 要指向你的内核源码目录。如果路径错了，编译会报一堆奇怪的错误——找不到头文件、宏定义不存在之类。
:::

编译完成后，会生成 `beep_driver.ko` 文件，这就是我们要加载的内核模块。

## 编译设备树

设备树源文件是 `.dts`，需要编译成 `.dtb` 才能给 Bootloader 用：

```bash
dtc -I dts -O dtb -o imx6ull-aes-15_tutorial_beep.dtb imx6ull-aes-15_tutorial_beep.dts
```

`-I dts` 表示输入格式是 dts，`-O dtb` 表示输出格式是 dtb。

::: warning 设备树文件位置
编译好的 `.dtb` 文件要放到 Bootloader 能找到的位置——通常是 TFTP 目录或 SD 卡的 boot 分区。具体位置看你的 Bootloader 配置。
:::

## 部署到板子

编译完成后，把文件拷贝到板子上：

```bash
# 通过 SSH 拷贝驱动
scp beep_driver.ko root@192.168.1.100:/lib/modules/$(uname -r)/extra/

# 通过 TFTP 或 SD 卡拷贝设备树
# 具体方式看你的板子配置
```

拷贝完成后，重启板子或者手动重新加载设备树。

## 加载驱动

驱动加载很简单：

```bash
insmod beep_driver.ko
```

加载后，可以检查一下设备节点：

```bash
ls -l /dev/beep
```

应该能看到类似这样的输出：

```
crw-rw---- 1 root root 246, 0 Jan 1 00:00 /dev/beep
```

`c` 表示字符设备，`246` 是主设备号（动态分配的），`0` 是次设备号。

::: tip 加载失败怎么办
如果加载失败，用 `dmesg | tail` 查看内核日志。常见错误有：版本不匹配、符号未定义、设备树匹配失败等。
:::

## 测试蜂鸣器

### 基本测试

让蜂鸣器响一下：

```bash
# 让蜂鸣器响
echo '0' > /dev/beep

# 让蜂鸣器静音
echo '1' > /dev/beep
```

如果蜂鸣器反应和预期相反，说明 GPIO 极性配置有问题，回看设备树章节的分析。

::: warning 注意写入内容
要写的是字符 `'0'`，不是数字 `0`。`echo 0 > /dev/beep` 写的是字符 `'0'`，`printf '\x00' > /dev/beep` 写的是数字 `0`。
:::

### 调试脚本

可以用脚本做更系统的测试：

```bash
#!/bin/sh

echo "Testing beep driver..."

# 测试 1：短鸣
echo "Test 1: Short beep"
echo '0' > /dev/beep
sleep 0.5
echo '1' > /dev/beep
sleep 0.5

# 测试 2：长鸣
echo "Test 2: Long beep"
echo '0' > /dev/beep
sleep 2
echo '1' > /dev/beep
sleep 0.5

# 测试 3：报警声
echo "Test 3: Alarm pattern"
for i in $(seq 1 5); do
    echo '0' > /dev/beep
    sleep 0.2
    echo '1' > /dev/beep
    sleep 0.2
done

echo "Tests completed!"
```

这个脚本测试短鸣、长鸣和报警模式，覆盖常见使用场景。

## 调试技巧

说实话，驱动开发一半时间在写代码，一半时间在调试。这里分享几个常用的调试方法。

### 检查驱动是否加载

```bash
lsmod | grep beep
```

应该能看到 `beep_driver` 模块和它的使用计数。

### 查看内核日志

```bash
dmesg | grep -i "beep"
dmesg | grep -i "gpio"
```

内核日志会告诉你驱动加载过程、GPIO 获取结果等信息。

### 查看 GPIO 状态

如果启用了 debugfs：

```bash
mount -t debugfs none /sys/kernel/debug
cat /sys/kernel/debug/gpio | grep -i "beep"
```

应该能看到 GPIO 的当前状态：

```
gpio-161 (                    |beep              ) out hi
```

`161` 是 GPIO 编号，`out hi` 表示配置为输出且当前是高电平。

### 通过 sysfs 测试极性

如果怀疑极性配置有问题，可以通过 sysfs 直接控制 GPIO：

```bash
# 导出 GPIO（假设是 GPIO 161）
echo 161 > /sys/class/gpio/export

# 配置为输出
echo out > /sys/class/gpio/gpio161/direction

# 测试高电平
echo 1 > /sys/class/gpio/gpio161/value
# 听蜂鸣器是否响

# 测试低电平
echo 0 > /sys/class/gpio/gpio161/value
# 听蜂鸣器是否响
```

如果高电平时蜂鸣器响，说明是高电平触发，设备树应该用 `GPIO_ACTIVE_HIGH`。如果低电平时蜂鸣器响，说明是低电平触发，设备树应该用 `GPIO_ACTIVE_LOW`。

## 常见问题

### 问题 1：蜂鸣器一直响

**现象**：驱动加载后，蜂鸣器一直响，关不掉。

**原因**：初始状态错误或 GPIO 极性配置错误。

**解决**：
1. 检查 `devm_gpiod_get()` 的 flags 参数
2. 检查设备树的 `GPIO_ACTIVE_*` 声明
3. 确认硬件接线

::: tip 初始状态很重要
蜂鸣器驱动的初始状态应该是静音。如果驱动加载后蜂鸣器一直响，用户体验很差，还可能让人以为板子坏了。
:::

### 问题 2：写入设备节点没反应

**现象**：`echo '0' > /dev/beep` 执行成功，但蜂鸣器没反应。

**原因**：设备树不匹配或驱动加载失败。

**解决**：
```bash
# 检查驱动是否加载
lsmod | grep beep

# 检查设备节点
ls /dev/beep

# 查看内核日志
dmesg | grep -i "beep"
```

### 问题 3：蜂鸣器状态和写入值相反

**现象**：写入 `'0'` 蜂鸣器不响，写入 `'1'` 蜂鸣器响。

**原因**：GPIO 极性配置不匹配。

**解决**：
1. 通过 sysfs 测试硬件极性
2. 根据实际硬件修改设备树或驱动代码

::: warning 驱动和设备树必须对齐
这是最常见的问题。驱动代码和设备树声明要一致——要么都是高电平触发，要么都是低电平触发。
:::

## 卸载驱动

测试完成后，卸载驱动：

```bash
rmmod beep_driver
```

卸载时驱动会自动关闭蜂鸣器（如果 `remove` 函数写对了的话）。

::: tip 卸载前关闭设备
卸载驱动前，确保用户程序已经关闭设备文件。如果有程序还在使用设备，`rmmod` 会返回 `EBUSY`。
:::

## 小结

蜂鸣器驱动的测试要点：

1. 用内核构建系统编译驱动，生成 `.ko` 文件
2. 用 `dtc` 编译设备树，生成 `.dtb` 文件
3. 把文件部署到板子，加载驱动
4. 通过 `/dev/beep` 控制蜂鸣器，验证功能
5. 用 debugfs 和 sysfs 调试 GPIO 问题
6. 确认驱动卸载时蜂鸣器关闭

到这里，蜂鸣器驱动教程就完成了。你应该对 Platform 驱动和 GPIO 子系统有了更深入的理解，也踩了一些常见的坑。

::: tip 下一步
接下来可以学习按键驱动，涉及 GPIO 输入和中断处理。那是另一个有趣的挑战——不仅要读 GPIO 状态，还要处理中断、去抖动等问题。
:::

---

<ChapterNav variant="sub">
  <ChapterLink href="03_driver_impl.md" variant="sub">← 驱动实现详解</ChapterLink>
  <ChapterLink href="../05_gpio_key_driver/" variant="sub">GPIO 按键驱动 →</ChapterLink>
</ChapterNav>
