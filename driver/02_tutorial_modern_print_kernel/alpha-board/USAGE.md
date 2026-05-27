# modern_print_kernel_base00_driver 使用说明

## 📋 简介

这是一个演示 Linux 内核打印功能的内核打印演示模块。它展示了所有 8 种内核日志级别以及各种高级打印功能。

## ✨ 功能特性

### 基础打印宏展示
- `pr_emerg()` - 紧急情况（级别 0）
- `pr_alert()` - 警报（级别 1）
- `pr_crit()` - 严重条件（级别 2）
- `pr_err()` - 错误条件（级别 3）
- `pr_warn()` - 警告条件（级别 4）
- `pr_notice()` - 通知（级别 5）
- `pr_info()` - 信息（级别 6）
- `pr_debug()` - 调试（级别 7）

### 高级打印功能
- `*_once()` - 一次性打印
- `pr_cont()` - 多行连续打印
- 模块参数控制 - 动态调整调试级别
- 条件打印示例

## 🚀 编译和部署

### 方法 1：使用项目脚本（推荐）

```bash
# 编译驱动
scripts/driver_helper/build_driver.sh modern_print_kernel_base00 alpha-board

# 部署到开发板
scripts/driver_helper/deploy_driver.sh modern_print_kernel_base00 alpha-board
```

### 方法 2：手动编译

```bash
# 进入驱动目录
cd driver/modern_print_kernel_base00/alpha-board

# 编译
make

# 查看输出
ls -lh out/driver_artifacts/modern_print_kernel_base00/alpha-board/
```

## 🧪 测试步骤

### 1. 加载模块

```bash
# 基本加载
insmod modern_print_kernel_base00_driver.ko

# 使用模块参数加载
insmod modern_print_kernel_base00_driver.ko debug_level=2
```

### 2. 查看输出

```bash
# 查看最近的内核消息
dmesg | tail -30

# 过滤本驱动的消息
dmesg | grep MODERN_PRINT_KERNEL

# 实时监控内核消息
dmesg -w | grep MODERN_PRINT_KERNEL
```

### 3. 查看所有日志级别

默认情况下，`pr_debug()` 消息不会显示。要查看所有级别：

```bash
# 设置内核日志级别为 8（显示所有级别）
echo 8 > /proc/sys/kernel/printk

# 重新加载模块
rmmod modern_print_kernel_base00_driver
insmod modern_print_kernel_base00_driver.ko

# 现在可以看到 DEBUG 消息了
dmesg | grep MODERN_PRINT_KERNEL
```

### 4. 使用模块参数

```bash
# 查看模块参数
modinfo modern_print_kernel_base00_driver.ko

# 使用不同的调试级别加载
insmod modern_print_kernel_base00_driver.ko debug_level=0  # 最少输出
insmod modern_print_kernel_base00_driver.ko debug_level=1  # 基本信息（默认）
insmod modern_print_kernel_base00_driver.ko debug_level=2  # 详细调试信息

# 查看当前模块参数
cat /sys/module/modern_print_kernel_base00_driver/parameters/debug_level

# 动态修改调试级别
echo 2 > /sys/module/modern_print_kernel_base00_driver/parameters/debug_level
```

### 5. 卸载模块

```bash
rmmod modern_print_kernel_base00_driver

# 查看卸载消息
dmesg | tail -5
```

## 📊 预期输出示例

### 默认日志级别（debug_level=1）

```
[123.456] MODERN_PRINT_KERNEL: === Modern Kernel Print Usage ===
[123.457] MODERN_PRINT_KERNEL: Module loading with debug level: 1
[123.458] MODERN_PRINT_KERNEL: Entering Part 1: Show the modern Print in kernel
[123.459] MODERN_PRINT_KERNEL:
[123.460] MODERN_PRINT_KERNEL: --- Demonstrating Kernel Log Levels ---
[123.461] MODERN_PRINT_KERNEL: EMERGENCY: System is unusable (level 0)
[123.462] MODERN_PRINT_KERNEL: ALERT: Action must be taken immediately (level 1)
[123.463] MODERN_PRINT_KERNEL: CRITICAL: Critical conditions occurred (level 2)
[123.464] MODERN_PRINT_KERNEL: ERROR: Error condition detected (level 3)
[123.465] MODERN_PRINT_KERNEL: WARNING: Warning condition (level 4)
[123.466] MODERN_PRINT_KERNEL: NOTICE: Normal but significant condition (level 5)
[123.467] MODERN_PRINT_KERNEL: INFO: Informational message (level 6)
[123.468] MODERN_PRINT_KERNEL: --- End of Log Level Demonstration ---
[123.469] MODERN_PRINT_KERNEL:
[123.470] MODERN_PRINT_KERNEL: --- Advanced printk Features ---
[123.471] MODERN_PRINT_KERNEL: This INFO_ONCE message will only appear once
[123.472] MODERN_PRINT_KERNEL: This WARN_ONCE message will only appear once
[123.473] MODERN_PRINT_KERNEL: This ERR_ONCE message will only appear once
[123.474] MODERN_PRINT_KERNEL: Multi-line message example:
[123.475]   - Line 1: Continued line without prefix
[123.476]   - Line 2: Continued line without prefix
[123.477]   - Line 3: Continued line without prefix
[123.478] MODERN_PRINT_KERNEL: --- End of Advanced Features ---
[123.479] MODERN_PRINT_KERNEL:
[123.480] MODERN_PRINT_KERNEL: Debug level >= 1: Basic information enabled
[123.481] MODERN_PRINT_KERNEL: ========================
[123.482] MODERN_PRINT_KERNEL: Module initialized successfully!
[123.483] MODERN_PRINT_KERNEL: Use 'dmesg | grep MODERN_PRINT_KERNEL' to see all messages
[123.484] MODERN_PRINT_KERNEL: Use 'echo 8 > /proc/sys/kernel/printk' to see DEBUG messages
[123.485] MODERN_PRINT_KERNEL: ========================
```

### 启用 DEBUG 后的额外输出（debug_level=2, 内核日志级别=8）

```
[123.459] MODERN_PRINT_KERNEL: This is a Debug Message (only visible with DEBUG enabled)
[123.467] MODERN_PRINT_KERNEL: DEBUG: Debug-level message (level 7)
[123.481] MODERN_PRINT_KERNEL: Debug level >= 2: Detailed debug information
[123.482] MODERN_PRINT_KERNEL: Module author: Charliechen114514
[123.483] MODERN_PRINT_KERNEL: Module version: 1.0
[123.484] MODERN_PRINT_KERNEL: Kernel version: 6.12.49
```

## 🔧 动态调试（如果内核支持）

如果内核启用了 `CONFIG_DYNAMIC_DEBUG`，可以更精细地控制打印：

```bash
# 查看可用的调试点
cat /sys/kernel/debug/dynamic_debug/control | grep modern_print_kernel_base00

# 启用所有调试
echo "module modern_print_kernel_base00_driver +p" > /sys/kernel/debug/dynamic_debug/control

# 禁用所有调试
echo "module modern_print_kernel_base00_driver -p" > /sys/kernel/debug/dynamic_debug/control
```

## 💡 使用技巧

### 1. 持续监控日志

```bash
# 终端 1：持续监控
dmesg -w | grep MODERN_PRINT_KERNEL

# 终端 2：反复加载/卸载模块
while true; do
    insmod modern_print_kernel_base00_driver.ko debug_level=2
    sleep 1
    rmmod modern_print_kernel_base00_driver
    sleep 1
done
```

### 2. 对比不同日志级别

```bash
# 测试一次性打印 - 只会看到一次 "This INFO_ONCE message will only appear once"
for i in {1..3}; do
    insmod modern_print_kernel_base00_driver.ko
    rmmod modern_print_kernel_base00_driver
done
```

### 3. 清空内核日志缓冲区

```bash
# 清空日志以便测试
dmesg -c

# 加载模块
insmod modern_print_kernel_base00_driver.ko

# 查看干净的输出
dmesg
```

## 📝 代码结构

```
modern_print_kernel_base00_driver.c
├── demonstrate_kernel_log_levels()        # 展示所有日志级别
├── demonstrate_advanced_printk_features() # 展示高级功能
├── demonstrate_conditional_printing()     # 展示条件打印
├── run_all_printk_demonstrations()        # 运行所有演示
├── modern_print_kernel_base00_init()                 # 模块初始化
└── modern_print_kernel_base00_exit()                 # 模块退出
```

## 🎓 学习要点

1. **日志级别选择**
   - 生产环境：主要使用 `pr_err()`、`pr_warn()`、`pr_info()`
   - 开发调试：可使用 `pr_debug()` 和 `pr_devel()`
   - 关键错误：使用 `pr_emerg()`、`pr_alert()`、`pr_crit()`

2. **性能考虑**
   - 高频路径使用 `*_ratelimited()` 避免日志洪水
   - 生产环境减少不必要的 `pr_debug()` 调用

3. **可维护性**
   - 使用 `pr_fmt()` 定义统一前缀，方便日志过滤
   - 使用模块参数动态控制调试级别
   - 添加清晰的日志消息，包含足够的上下文信息

4. **最佳实践**
   - 错误消息要详细，包含失败原因和建议操作
   - 使用 `*_once()` 避免重复的初始化消息
   - 关键操作的成功/失败都应该有相应的日志

## 🔍 故障排查

### 问题：pr_debug 消息不显示

**解决方案**：
```bash
# 检查内核日志级别
cat /proc/sys/kernel/printk

# 设置为显示所有级别
echo 8 > /proc/sys/kernel/printk

# 或使用模块参数
insmod modern_print_kernel_base00_driver.ko debug_level=2
```

### 问题：模块加载失败

**检查项**：
```bash
# 查看内核日志
dmesg | tail

# 检查模块依赖
modinfo modern_print_kernel_base00_driver.ko

# 检查内核版本匹配
modinfo modern_print_kernel_base00_driver.ko | grep vermagic
uname -r
```

### 问题：找不到 pr_fmt 前缀

**确认**：
```bash
# 使用 grep 过滤时注意前缀
dmesg | grep MODERN_PRINT_KERNEL
```

## 📚 参考资料

- [Linux 内核文档：printk](https://www.kernel.org/doc/html/latest/core-api/printk-basics.html)
- [内核日志级别定义](https://elixir.bootlin.com/linux/v6.12/source/include/linux/kern_levels.h)
- [动态调试文档](https://www.kernel.org/doc/html/latest/admin-guide/dynamic-debug-howto.html)

## 👨‍💻 作者

- Charliechen114514
- 版本：1.0
- 许可证：GPL

---

**注意**：此驱动仅用于演示和教学目的，不涉及实际的字符设备操作。
