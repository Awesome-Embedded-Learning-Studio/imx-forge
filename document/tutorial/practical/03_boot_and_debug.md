---
title: 启动与调试
---

# 系统启动与调试：见证系统启动的那一刻，并学会如何挽救它

## 为什么这一章是实战教程的收官之作

如果说前两章是在准备食材和烹饪，那这一章就是端上餐桌的那一刻。无论你准备了多久，菜好不好吃，最后还要看端上来的效果。

嵌入式开发的"效果"就是系统启动的那一刻。当你看到串口终端一行行输出冒出来，从 U-Boot 的版本信息到内核的启动日志，再到那个熟悉的 `Please press Enter` 提示符——那一刻的成就感，真的不是写几行代码能比的。

但现实中，启动往往不会一帆风顺。你可能会遇到 U-Boot 卡在某个地方，内核启动到一半崩溃，或者 rootfs 挂载失败。这时候，调试能力就成了你的救命稻草。

所以这一章的目标很明确：**带你完整地走过系统启动的每个环节，学会解读日志，掌握调试技巧，最终让你的系统稳定运行**。

## 启动前的准备——工欲善其事，必先利其器

在给板子上电之前，我们需要做好充分的准备。相信我，准备越充分，遇到问题时就越从容。

### 硬件连接检查

先画一张连接示意图，确保所有线都接对了：

```
┌─────────────────────────────────────────────────────────┐
│                      开发主机                             │
│                 (Ubuntu + 串口工具)                       │
└───────────────────────┬─────────────────────────────────┘
                        │ USB
                        │
                   ┌────▼─────┐
                   │ USB转TTL  │
                   │ 串口模块   │
                   └────┬─────┘
                        │ GND, TX, RX
                        │
┌───────────────────────▼─────────────────────────────────┐
│                    i.MX6ULL 开发板                        │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   电源     │    │   串口      │    │   SD卡      │  │
│  │  5V/2A     │    │  UART1      │    │  (可选)     │  │
│  └─────────────┘    └─────────────┘    └─────────────┘  │
└─────────────────────────────────────────────────────────┘
```

连接要点：
1. **串口连接**：GND 接 GND，TX 接 RX，RX 接 TX（交叉连接）
2. **电源连接**：确保电流足够（至少 1A，推荐 2A）
3. **SD 卡**：确认烧录正确，卡插入到位

**踩坑记录**：有一次我的板子总是起不来，串口输出乱码。排查半天发现 TX 和 RX 接反了。这个低级错误真的会让你怀疑人生。

### 串口工具配置

推荐使用 `picocom`，简单轻量：

```bash
picocom -b 115200 /dev/ttyUSB0
```

参数说明：
- `-b 115200`：波特率 115200（i.MX6ULL 默认）
- `/dev/ttyUSB0`：串口设备（可能是 ttyUSB0、ttyACM0 等，用 `ls /dev/tty*` 查看）

**picocom 使用技巧**：
- 退出：先按 `Ctrl + A`，再按 `Ctrl + Q`
- 暂停/恢复输出：`Ctrl + A` 然后 `Ctrl + S` / `Ctrl + Q`
- 清屏：`Ctrl + A` 然后 `Ctrl + L`

其他串口工具：
- `minicom`：功能强大，但配置复杂
- `screen`：Mac/Linux 内置，命令：`screen /dev/ttyUSB0 115200`
- `cu`：简洁，命令：`cu -l /dev/ttyUSB0 -s 115200`

### 日志记录——调试的必备习惯

在启动板子之前，先启动日志记录。这就像开车开行车记录仪，出事了有据可查。

```bash
# 方法1：使用 tee 同时显示和保存
picocom -b 115200 /dev/ttyUSB0 | tee boot.log

# 方法2：使用脚本自动记录
picocom -b 115200 /dev/ttyUSB0 2>&1 | tee boot.log

# 方法3：使用 screen 和 script
script boot.log
screen /dev/ttyUSB0 115200
# 退出 screen 后，Ctrl + D 退出 script
```

日志文件非常重要！当你遇到问题时，完整的日志能帮你快速定位。很多时候你凭记忆想不起来具体的错误信息，回头查日志就清楚了。

## U-Boot 启动日志解读——系统的第一声啼哭

当你给板子上电后，第一个看到的就是 U-Boot 的启动日志。让我们逐行解读。

### 完整的 U-Boot 启动日志

```
U-Boot 2025.04-00017-gXXXXXXX (Mar 15 2026 - 10:30:00 +0800)

CPU:   Freescale i.MX6ULL rev1.1 528 MHz
Reset cause: POR
Model: Freescale i.MX6ULL 14x14 EVK Board
DRAM:  512 MiB
MMC:   FSL_SDHC: 0, FSL_SDHC: 1
Loading Environment from MMC... OK
In:    serial
Out:   serial
Err:   serial
Net:   ethernet@02188000

Hit any key to stop autoboot...  3  2  1
=>
```

### 逐行解读

#### 1. 版本信息

```
U-Boot 2025.04-00017-gXXXXXXX (Mar 15 2026 - 10:30:00 +0800)
```

- `2025.04`：U-Boot 版本号
- `00017`：git commit 数，表示这是官方版本的第 17 个提交
- `gXXXXXXX`：git commit hash 的前 7 位
- `Mar 15 2026`：编译日期

**经验**：如果你看到版本号很老（比如 2016 年），说明你用的是旧的 U-Boot。虽然也能用，但可能缺少一些新特性。

#### 2. CPU 信息

```
CPU:   Freescale i.MX6ULL rev1.1 528 MHz
```

- `Freescale i.MX6ULL`：芯片型号
- `rev1.1`：芯片版本（不同版本的芯片可能有差异）
- `528 MHz`：当前运行频率

**踩坑记录**：有一次我看到的频率是 396 MHz 而不是 528 MHz。查了半天发现是 board 配置里的 PLL 设置不对。虽然不影响功能，但性能会打折扣。

#### 3. 复位原因

```
Reset cause: POR
```

- `POR`：Power On Reset（上电复位）
- `WDOG`：看门狗复位
- `JTAG`：JTAG 复位
- `WDG`：看门狗复位
- `外部复位`：`RST_B` 引脚触发

**经验**：如果看到 `WDOG` 复位，说明系统之前崩溃了，看门狗把系统重启了。这时候要检查内核日志看是什么导致的崩溃。

#### 4. 板子信息

```
Model: Freescale i.MX6ULL 14x14 EVK Board
```

这个信息来自设备树的 `model` 属性。如果你看到的信息不对，说明设备树选错了。

#### 5. 内存信息

```
DRAM:  512 MiB
```

显示检测到的 DDR 内存大小。i.MX6ULL 支持 256MB、512MB 等配置。

**踩坑记录**：有一次显示 256MiB 而不是 512MiB，排查发现是 DDR 初始化参数不对。虽然系统能跑，但一半内存浪费了。

#### 6. MMC 设备

```
MMC:   FSL_SDHC: 0, FSL_SDHC: 1
```

检测到两个 MMC 控制器。通常是：
- `0`：SD 卡
- `1`：eMMC

具体要看板子的硬件设计。

#### 7. 环境变量加载

```
Loading Environment from MMC... OK
```

从 MMC 设备加载环境变量成功。如果这里失败，可能是：
- 环境变量区域损坏
- MMC 设备初始化失败

#### 8. 控制台设备

```
In:    serial
Out:   serial
Err:   serial
```

标准输入、输出、错误都重定向到串口。这样你才能看到串口输出，也能通过串口输入命令。

#### 9. 网络设备

```
Net:   ethernet@02188000
```

显示检测到的以太网控制器。i.MX6ULL 有两个以太网控制器（FEC），这里显示的是其中一个。

#### 10. 倒计时

```
Hit any key to stop autoboot...  3  2  1
```

自动启动倒计时，默认 3 秒。期间按任意键可以进入 U-Boot 命令行。

**经验**：如果你总是来不及按键，可以在 `bootdelay` 环境变量中增加延迟：

```
=> setenv bootdelay 5
=> saveenv
```

### U-Boot 命令行操作

如果倒计时内按了键，你会进入 U-Boot 命令行：

```
=>
```

这里可以执行各种调试命令，比如：

```
=> bdinfo              # 查看板子信息
=> printenv            # 查看环境变量
=> mmc list            # 列出 MMC 设备
=> mmc part            # 显示分区表
=> dhcp                # 获取 IP 地址
=> tftp 0x82000000 zImage  # 下载内核
=> bootz 0x82000000 - 0x88000000  # 启动内核
```

## Linux 内核启动日志解读——从黑暗到光明

U-Boot 把控制权交给内核后，你会看到一长串内核启动日志。不要被吓到，这些信息都是有规律的。

### 早期初始化阶段

```
Starting kernel ...

[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 6.12.3 (charliechen@ubuntu) (arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409) #1 SMP PREEMPT Sat Mar 15 10:25:00 CST 2026
[    0.000000] CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=10c5387d
[    0.000000] CPU: div instructions available: patching division代码
[    0.000000] CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
[    0.000000] OF: fdt: Machine model: Freescale i.MX6ULL 14x14 EVK Board
```

解读：
- `Linux version 6.12.3`：内核版本
- `ARMv7 Processor`：CPU 架构
- `[410fc075]`：CPU ID（ARM Cortex-A7）
- `Machine model`：板子型号

### 内存和 CPU 信息

```
[    0.000000] Memory: 512MiB/512MiB available
[    0.000000] fdt: reserved memory region 0x80000000..0x8fffffff
[    0.000000] On node 0 totalpages: 131072
[    0.000000]   DMA zone: 1960 pages used for memmap
[    0.000000]   Normal zone: 129112 pages used for memmap
[    0.000000] percpu: Embedded 12 pages/cpu s21280 r8192 d23072 u49152
```

解读：
- `512MiB/512MiB`：总内存和可用内存
- `reserved memory`：保留的内存区域（用于特定目的）
- `DMA zone`、`Normal zone`：内存管理区域

**经验**：如果可用内存明显少于总内存，可能是设备树里预留了太多内存。检查 `reserved-memory` 节点。

### 中断和定时器初始化

```
[    0.000000] arch_timer: cp15 timer(s) running at 8.00MHz (phys)
[    0.000000] clocksource: arch_sys_counter: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 1911260446275 ns
[    0.000003] sched_clock: 32 bits at 8MHz, resolution 125ns, wraps every 268435456250ns
[    0.000011] Calibrating delay loop... 263.88 BogoMIPS (lpj=524288)
```

解读：
- `arch_timer`：ARM 架构定时器
- `8.00MHz`：定时器频率
- `263.88 BogoMIPS`：一个粗略的性能指标（别太当真）

**踩坑记录**：如果 `BogoMIPS` 值异常低（比如只有几十），可能是 CPU 没有正确设置频率。

### 设备树解析

```
[    0.000018] CPU: Testing write coherency: ok
[    0.000025] CPU0: thread -1, cpu 0, socket 0
[    0.000036] smp: Bringing up secondary CPUs ...
[    0.000048] CPU1: thread -1, cpu 1, socket 0
[    0.000060] smp: Brought up 1 node, 2 CPUs
```

i.MX6ULL 是双核 Cortex-A7，这里显示两个 CPU 都启动了。

### 早期控制台

```
[    0.000412] console [ttymxc0] enabled
[    0.000531] console [ttymxc0] enabled
[    0.000592] bootconsole [earlycon0] disabled
```

- `ttymxc0`：串口设备（设备树中定义）
- `bootconsole`：早期控制台，被正常控制台替代

### 内存管理初始化

```
[    0.001234] PID hash table entries: 2048 (order: 1, 131072 bytes, linear)
[    0.001456] Memory: 1998640K/524288K available
```

内核内存管理系统初始化完成。

### 驱动初始化

```
[    0.567890] Serial: 8250/16550 driver, 4 ports, IRQ sharing enabled
[    0.589123] 20208000.serial: ttymxc0 at MMIO 0x20208000 (irq = 43, base_baud = 5000000) is a PL011 rev2
[    0.601456] 20204000.serial: ttyAMA1 at MMIO 0x20204000 (irq = 44, base_baud = 5000000) is a PL011 rev2
```

串口驱动初始化，显示检测到的串口设备。

```
[    1.234567] fec 2188000.ethernet eth0: PHY ID 0x001cc916 at 0 IRQ err (-5)
[    1.345678] fec 2188000.ethernet eth0: Unable to connect to phy
```

以太网驱动初始化。如果 PHY 连接失败，可能是：
- 网线未插
- PHY 地址不对
- 硬件连接问题

### 文件系统挂载

```
[    2.345678] VFS: Mounted root (ext4 filesystem) readonly on device 179:2.
[    2.456789] devtmpfs: mounted
[    2.567890] Freeing unused kernel memory: 1024K
[    2.678901] Run /sbin/init as init process
```

解读：
- `Mounted root (ext4 filesystem)`：rootfs 挂载成功
- `readonly`：以只读方式挂载（后续会重新挂载为读写）
- `Run /sbin/init as init process`：启动 init 进程

**踩坑记录**：如果看到 `VFS: Cannot open root device`，说明 rootfs 挂载失败。检查 `root=` 参数和分区是否存在。

## Rootfs 挂载与初始化——用户空间的开始

内核挂载 rootfs 后，会启动第一个用户空间进程 `init`。在 BusyBox 系统中，这通常是 BusyBox 的 init。

### BusyBox init 启动过程

```
[    3.123456] BusyBox v1.37.0 (2026-03-15 10:20:00 +0800) multi-call binary.
[    3.234567] mounting /etc/fstab failed
[    3.345678] Please press Enter to activate this console.
[    4.456789] input: ttymxc0 as /class/tty/tty0
```

解读：
- `mounting /etc/fstab failed`：这是正常的，因为我们没有创建 fstab
- `Please press Enter`：getty 等待用户激活控制台
- `input: ttymxc0`：输入设备注册

### inittab 执行过程

BusyBox init 会读取 `/etc/inittab` 并执行相应的命令：

```
::sysinit:/etc/init.d/rcS      # 执行启动脚本
::respawn:/sbin/getty -L 115200 ttymxc0 vt100  # 启动登录提示
```

### rcS 启动脚本

`/etc/init.d/rcS` 脚本会执行：

```bash
#!/bin/sh

# 挂载虚拟文件系统
mount -t proc none /proc
mount -t sysfs none /sys
mount -t tmpfs none /tmp

# 配置网络
ifconfig eth0 up 2>/dev/null || true

# 欢迎信息
echo ""
echo "Welcome to IMX-Forge Linux!"
echo "Kernel: $(uname -a)"
echo ""
```

### 成功启动的标志

如果你看到类似这样的输出，说明系统启动成功：

```
Welcome to IMX-Forge Linux!
Kernel: Linux imx6ull 6.12.3 #1 SMP PREEMPT Sat Mar 15 10:25:00 CST 2026 armv7l GNU/Linux

Please press Enter to activate this console.
```

按回车后，你应该看到登录提示符：

```
/ #
```

恭喜！你的系统已经完全启动了！

## 常见启动失败案例——当事情不如意时

### 案例 1：U-Boot 启动后无输出

**症状**：上电后串口完全没有输出。

**可能原因**：
1. 串口连接错误（TX/RX 接反）
2. 波特率不匹配
3. U-Boot 没有正确烧录
4. 板子硬件问题

**排查步骤**：
```
1. 检查串口连接（TX-RX, RX-TX, GND-GND）
2. 尝试不同波特率（9600, 115200, 57600）
3. 检查 U-Boot 是否正确烧录（用 dd 查看）
4. 尝试 SD 卡启动（排除 eMMC 问题）
```

**经验**：用示波器或逻辑分析仪检查 TX 引脚是否有波形，能快速定位是硬件还是软件问题。

### 案例 2：内核启动到一半崩溃

**症状**：看到一些内核输出，然后突然重启或停止。

**可能原因**：
1. 设备树不匹配
2. 内存配置错误
3. 驱动初始化失败

**排查步骤**：
```
1. 查看最后几行输出，定位崩溃点
2. 检查设备树是否匹配板子硬件
3. 简化 bootargs（去掉不必要的参数）
4. 尝试使用最小配置的内核
```

**实战技巧**：在 bootargs 中添加 `earlyprintk` 和 `ignore_loglevel` 可以获得更多调试信息：

```
setenv bootargs "console=ttymxc0,115200 earlyprintk ignore_loglevel"
```

### 案例 3：Rootfs 挂载失败

**症状**：内核报错 "VFS: Cannot open root device"

**可能原因**：
1. root= 参数错误
2. 分区不存在
3. 文件系统类型不匹配

**排查步骤**：
```
1. 检查 bootargs 中的 root= 参数
2. 在 U-Boot 中用 mmc part 查看分区
3. 确认文件系统类型（ext4, vfat 等）
4. 尝试手动挂载（在 U-Boot 或恢复模式下）
```

**解决方法**：
```
# 方法1：使用 UUID（更可靠）
blkid /dev/mmcblk0p2
setenv bootargs "root=UUID=xxxx-xxxx rootfstype=ext4"

# 方法2：使用明确的设备名
setenv bootargs "root=/dev/mmcblk0p2 rootfstype=ext4"
```

### 案例 4：无法登录

**症状**：看到 "Please press Enter" 但输入没反应。

**可能原因**：
1. inittab 配置错误
2. getty 程序不存在
3. 串口设备名错误

**排查步骤**：
```
1. 检查 /etc/inittab 配置
2. 确认 /sbin/getty 指向 busybox
3. 检查 /dev/ttymxc0 设备是否存在
4. 尝试手动运行 getty
```

**解决方法**：
```
# 检查 inittab
cat /etc/inittab

# 手动启动 getty（在 shell 中）
/sbin/getty -L 115200 ttymxc0 vt100
```

## 系统调试技巧汇总——从入门到精通

### 技巧 1：分段验证法

不要试图一次性解决所有问题，分段验证：

```
1. U-Boot 启动 → OK
2. 内核加载 → OK
3. 设备树传递 → OK
4. 内核启动 → OK
5. Rootfs 挂载 → OK
6. Init 进程 → OK
```

每一步都验证通过再进入下一步。

### 技巧 2：日志对比法

有正常的板子是最好的参照：

```
# 正常板子的日志
cat normal_boot.log

# 问题板子的日志
cat problem_boot.log

# 对比差异
diff normal_boot.log problem_boot.log
```

**经验**：有时候差异就在一行，比如一个参数、一个地址，找出来就解决了。

### 技巧 3：最小化配置法

怀疑某个配置导致问题时，先最小化：

```
# 最简单的 bootargs
setenv bootargs "console=ttymxc0,115200"

# 逐步添加参数
setenv bootargs "console=ttymxc0,115200 root=/dev/mmcblk0p2"
setenv bootargs "console=ttymxc0,115200 root=/dev/mmcblk0p2 rootfstype=ext4"
```

### 技巧 4：设备树调试

使用 U-Boot 的 fdt 命令调试设备树：

```
=> fdt addr 0x88000000
=> fdt print /
=> fdt print /memory
=> fdt set /chosen bootargs "console=ttymxc0,115200"
=> bootz 0x82000000 - 0x88000000
```

这样可以临时修改设备树而不需要重新编译。

### 技巧 5：内核动态调试

启用内核动态调试：

```
# 在 bootargs 中添加
setenv bootargs "console=ttymxc0,115200 dyndbg=+p"
```

这会打印大量调试信息，适合深入分析问题。

### 技巧 6：QEMU 模拟

在没有硬件的情况下，可以用 QEMU 模拟：

```bash
qemu-system-arm -M vexpress-a9 \
  -kernel zImage \
  -dtb vexpress-v2p-ca9.dtb \
  -drive if=sd,file=rootfs.ext4,format=raw \
  -serial mon:stdio \
  -append "console=ttymxc0,115200 root=/dev/mmcblk0 rootwait"
```

虽然不能完全替代真实硬件，但能快速验证某些问题。

## 成功启动后的验证——确认系统真的可用

看到登录提示符还不够，我们还要验证系统真的可用。

### 验证 1：基本信息查询

```
/ # uname -a
Linux imx6ull 6.12.3 #1 SMP PREEMPT Sat Mar 15 10:25:00 CST 2026 armv7l GNU/Linux

/ # cat /proc/cpuinfo
processor	: 0
BogoMIPS	: 264.00
Features	: half thumb fastmult vfp edsp neon vfpv3 tls vfpd32
CPU implementer	: 0x41
CPU architecture: 7
CPU variant	: 0x2
CPU part	: 0xc07
CPU revision	: 5

/ # free -h
              total        used        free      shared  buff/cache   available
Mem:          487Mi        24Mi       440Mi       1.0Mi        22Mi       456Mi
Swap:            0B          0B          0B
```

### 验证 2：文件系统检查

```
/ # df -h
Filesystem                Size      Used Available Use% Mounted on
/dev/root                3.6G     12.0M      3.4G   0% /
devtmpfs                244.0M         0    244.0M   0% /dev
tmpfs                   244.0M      4.0K    244.0M   0% /tmp
```

### 验证 3：网络功能

```
/ # ifconfig -a
eth0      Link encap:Ethernet  HWaddr 00:04:25:1C:A0:00
          inet addr:192.168.1.102  Bcast:192.168.1.255  Mask:255.255.255.0
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:10 errors:0 dropped:0 overruns:0 frame:0
          TX packets:8 errors:0 dropped:0 overruns:0 carrier:0

/ # ping -c 4 192.168.1.1
PING 192.168.1.1 (192.168.1.1): 56 data bytes
64 bytes from 192.168.1.1: seq=0 ttl=64 time=0.8 ms
64 bytes from 192.168.1.1: seq=1 ttl=64 time=0.7 ms
```

### 验证 4：存储设备

```
/ # ls /dev/mmc*
/dev/mmcblk0  /dev/mmcblk0p1  /dev/mmcblk0p2

/ # mount | grep mmc
/dev/root on / type ext4 (rw,relatime)
```

### 验证 5：进程检查

```
/ # ps
PID   USER     COMMAND
1     root     {init} /sbin/init
42    root     /sbin/getty -L 115200 ttymxc0 vt100
56    root     sh
62    root     ps
```

## 性能测试——了解你的系统极限

### CPU 性能

```
/ # time dd if=/dev/zero of=/dev/null bs=1M count=100
100+0 records in
100+0 records out
real    0m 0.20s
user    0m 0.00s
sys     0m 0.20s
```

### 存储性能

```
/ # time dd if=/dev/zero of=/tmp/test bs=1M count=100
100+0 records in
100+0 records out
real    0m 2.50s
user    0m 0.00s
sys     0m 2.50s
```

### 网络性能

```
/ # nc -l -p 5000 > /dev/null
# 在主机上: dd if=/dev/zero bs=1M count=100 | nc 192.168.1.102 5000
```

## 完整学习路径回顾——从入门到精通

到这里，我们的实战教程就告一段落了。让我们回顾一下完整的知识体系：

### 第一阶段：工具链基础
- 交叉编译原理
- ARM GNU Toolchain 安装与配置
- 工具链验证方法

### 第二阶段：组件编译
- U-Boot 编译与产物验证
- Linux 内核编译与配置
- BusyBox Rootfs 构建

### 第三阶段：系统整合
- SD 卡镜像制作
- 各组件协调与启动参数配置
- 验证与测试

### 第四阶段：启动调试
- 启动日志解读
- 常见问题排查
- 调试技巧掌握

### 第五阶段：系统优化
- 性能测试
- 配置优化
- 功能扩展

这不是一个线性的过程，而是一个循环迭代的过程。每次你遇到问题、解决问题，你的理解就加深一层。

## 总结：从"照着做"到"理解为什么"

这套实战教程的目标，不只是让你"能跑起来"，而是让你"理解为什么这么跑"。

当你知道：
- U-Boot 为什么需要 IVT 头
- 内核为什么需要设备树
- Rootfs 的 init 程序做什么
- 启动参数每一个字段的含义

你就不是在"照着做"，而是在"掌控整个系统"。

这就是嵌入式开发的魅力——你理解系统的每一层，从硬件到软件，从启动到运行。遇到问题，你知道该从哪里入手；需要优化，你知道该从何处着手。

希望这套教程能成为你嵌入式开发之路上的垫脚石。从 IMX-Forge 开始，构建你自己的嵌入式系统，探索更多可能性！

祝你在嵌入式开发的道路上越走越远！

---

## 附录：快速参考

### 常用 U-Boot 命令

```
bdinfo              # 板子信息
printenv            # 查看环境变量
setenv name value   # 设置变量
saveenv             # 保存变量
mmc list            # 列出 MMC 设备
mmc part            # 显示分区表
dhcp                # 获取 IP
tftp address file   # 下载文件
bootz kernel - dtb  # 启动内核
```

### 常用内核启动参数

```
console=ttymxc0,115200       # 串口控制台
root=/dev/mmcblk0p2          # rootfs 设备
rootfstype=ext4              # 文件系统类型
rootwait                     # 等待设备就绪
ro                           # 只读挂载
rw                           # 读写挂载
init=/sbin/init              # init 进程路径
earlyprintk                  # 早期调试输出
```

### 常用调试命令

```
dmesg                        # 内核日志
dmesg | grep -i error        # 查找错误
cat /proc/cpuinfo            # CPU 信息
cat /proc/meminfo            # 内存信息
mount                        # 挂载情况
ps                           # 进程列表
strace command               # 跟踪系统调用
```

祝调试顺利！
