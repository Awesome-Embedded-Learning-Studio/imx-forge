# 应用集成：从最小化 Rootfs 到可用系统

## 前言：我们到了哪一步

经过前面五章的折腾，我们已经有了一个可以启动的 Rootfs：

- ✅ BusyBox 编译安装完成
- ✅ 目录结构创建完毕
- ✅ NFS 网络挂载成功
- ✅ 开发板可以进入 shell

但是！当你真正开始使用这个系统时，你会发现它真的"太干净"了——没有 `vim`，没有 `top`，没有 `ps -ef`，连个 `ping` 命令都可能没有。想要添加一个自己的程序，还得考虑库文件依赖、链接方式、部署位置等等问题。

这一章，我们就来解决这些问题，把一个"能启动"的 Rootfs 变成一个"能用"的 Rootfs。

## 添加常用命令和工具

### BusyBox 自带的命令

BusyBox 其实已经提供了很多常用命令，只是默认配置可能没有全部启用。要查看当前 BusyBox 支持的命令：

```bash
# 在开发板上
/bin/busybox --list
```

或者在主机上查看编译好的 BusyBox：

```bash
arm-none-linux-gnueabihf-objdump -T out/release-latest/rootfs/bin/busybox | grep "help_main"
```

### 启用更多 BusyBox 命令

如果你发现某个命令没有，可以先检查 BusyBox 配置：

```bash
cd third_party/busybox
make O=../../out/buildroot menuconfig ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf-
```

一些常用的可能被禁用的命令：

| 配置项 | 说明 | 路径 |
|--------|------|------|
| `CONFIG_VI` | vi 编辑器 | Editor Utilities |
| `CONFIG_TOP` | top 进程查看 | Process Utilities |
| `CONFIG_PS` | ps 命令 | Process Utilities |
| `CONFIG_PING` | ping 命令 | Networking Utilities |
| `CONFIG_WGET` | wget 下载工具 | Networking Utilities |
| `CONFIG_TFTP` | tftp 客户端 | Networking Utilities |
| `CONFIG_IFCONFIG` | ifconfig 网络配置 | Networking Utilities |
| `CONFIG_NETSTAT` | netstat 网络状态 | Networking Utilities |

**踩坑经验**：`CONFIG_PING` 和 `CONFIG_PING6` 可能需要额外的依赖才能正常工作，比如 `/etc/resolv.conf` 和 `/etc/hosts` 文件。

### 添加非 BusyBox 程序

BusyBox 虽然强大，但毕竟是一个"瑞士军刀"，每个命令都是简化版本。如果你需要完整功能的程序，就需要单独编译。

#### 编译一个简单的 Hello World

```c
// hello.c
#include <stdio.h>

int main(int argc, char *argv[]) {
    printf("Hello, i.MX6ULL!\n");
    printf("Arguments received: %d\n", argc - 1);
    for (int i = 1; i < argc; i++) {
        printf("  arg[%d] = %s\n", i, argv[i]);
    }
    return 0;
}
```

**交叉编译**：

```bash
# 静态链接（推荐，无需拷贝库文件）
arm-none-linux-gnueabihf-gcc -static -o hello hello.c

# 或者动态链接
arm-none-linux-gnueabihf-gcc -o hello hello.c
```

**部署**：

```bash
cp hello rootfs/nfs/usr/bin/
chmod +x rootfs/nfs/usr/bin/hello
```

**在开发板上测试**：

```bash
# Hello, i.MX6ULL!
```

## 静态链接 vs 动态链接

这是一个永恒的话题：到底用静态链接还是动态链接？

### 静态链接

**优点**：

- 无需拷贝库文件，部署简单
- 不存在库版本冲突问题
- 程序启动稍快（不需要链接时加载库）

**缺点**：

- 每个程序都包含一份库代码，浪费存储空间
- 如果多个程序使用同一个库，内存中也存在多份
- 程序体积较大

**适用场景**：

- 小型工具程序
- Rootfs 存储空间有限
- 不确定目标系统有什么库

### 动态链接

**优点**：

- 程序体积小
- 多个程序共享同一份库，节省内存
- 库可以独立更新（理论上的好处）

**缺点**：

- 需要确保目标系统有所需的库
- 需要考虑库版本兼容性
- 部署时需要拷贝库文件

**适用场景**：

- 大型应用程序
- 多个程序使用相同的库
- Rootfs 存储空间充足

### 如何查看程序使用的库

```bash
arm-none-linux-gnueabihf-readelf -d hello | grep NEEDED
```

输出示例：

```
 0x00000001 (NEEDED)             Shared library: [libc.so.6]
 0x00000001 (NEEDED)             Shared library: [libm.so.6]
```

### 查看程序是静态还是动态链接

```bash
arm-none-linux-gnueabihf-file hello
```

输出示例：

```
hello: ELF 32-bit LSB executable, ARM, EABI5 version 1 (GNU/Linux), statically linked
#                                                                    ^^^^^^^^^^^^^^^
#                                                                    静态链接

hello: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked
#                                                                    ^^^^^^^^^^^^^^^^
#                                                                    动态链接
```

## 库文件依赖处理

如果你选择动态链接，就需要处理库文件依赖问题。

### 查找所需的库文件

```bash
arm-none-linux-gnueabihf-gcc -o hello hello.c
arm-none-linux-gnueabihf-readelf -d hello | grep NEEDED
```

输出示例：

```
 0x00000001 (NEEDED)             Shared library: [libc.so.6]
 0x00000001 (NEEDED)             Shared library: [ld-linux-armhf.so.3]
```

### 从交叉编译工具链复制库文件

找到工具链的库目录：

```bash
arm-none-linux-gnueabihf-gcc -print-sysroot
```

输出示例：

```
/home/charliechen/opt/arm-none-linux-gnueabihf/libc
```

库文件通常在：

```
/home/charliechen/opt/arm-none-linux-gnueabihf/libc/lib/
```

**复制所需的库**：

```bash
# 创建库目录
mkdir -p rootfs/nfs/lib

# 复制库文件（注意是软链接指向的实际文件）
cp /home/charliechen/opt/arm-none-linux-gnueabihf/libc/lib/libc.so.6 rootfs/nfs/lib/
cp /home/charliechen/opt/arm-none-linux-gnueabihf/libc/lib/ld-linux-armhf.so.3 rootfs/nfs/lib/
```

**注意**：很多库文件是软链接，需要复制实际文件，不要复制链接本身。使用 `cp -L` 或者 `cp -a` 可以自动处理软链接。

### 验证库文件完整性

```bash
arm-none-linux-gnueabihf-readelf -d rootfs/nfs/usr/bin/hello | grep NEEDED
```

然后确认每个 `NEEDED` 的库在 `rootfs/nfs/lib/` 或 `rootfs/nfs/usr/lib/` 下存在。

### 常见的库文件

| 库文件 | 作用 | 程序示例 |
|--------|------|----------|
| `libc.so.6` | C 标准库 | 几乎所有 C 程序 |
| `libm.so.6` | 数学库 | 使用数学函数的程序 |
| `libpthread.so.0` | 线程库 | 多线程程序 |
| `libdl.so.2` | 动态链接库 | 使用 dlopen 的程序 |
| `librt.so.1` | 实时扩展库 | 使用 POSIX 实时功能的程序 |
| `ld-linux-*.so.*` | 动态链接器 | 所有动态链接程序 |

## 添加自定义应用程序

### 组织应用程序目录结构

建议按照以下结构组织应用程序：

```
rootfs/nfs/
├── usr/
│   ├── bin/           # 用户程序
│   ├── sbin/          # 系统管理程序
│   └── lib/           # 应用程序库
├── opt/               # 可选软件包
│   └── myapp/
│       ├── bin/       # myapp 的可执行文件
│       ├── lib/       # myapp 的库
│       └── etc/       # myapp 的配置
└── home/              # 用户目录
    └── myapp/         # 用户程序
```

### 编写一个实用程序：LED 控制工具

```c
// led_ctrl.c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#define LED_PATH "/sys/class/leds"

// 列出所有 LED
void list_leds() {
    char cmd[128];
    snprintf(cmd, sizeof(cmd), "ls %s 2>/dev/null", LED_PATH);
    system(cmd);
}

// 控制 LED 状态
int set_led(const char *led_name, const char *state) {
    char path[128];
    int fd;
    ssize_t ret;

    // 构造亮度控制路径
    snprintf(path, sizeof(path), "%s/%s/brightness", LED_PATH, led_name);

    fd = open(path, O_WRONLY);
    if (fd < 0) {
        perror("open brightness");
        return -1;
    }

    ret = write(fd, state, strlen(state));
    close(fd);

    if (ret < 0) {
        perror("write brightness");
        return -1;
    }

    printf("LED %s set to %s\n", led_name, state);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command> [args]\n", argv[0]);
        printf("Commands:\n");
        printf("  list              List all LEDs\n");
        printf("  on <led_name>     Turn on LED\n");
        printf("  off <led_name>    Turn off LED\n");
        return 1;
    }

    if (strcmp(argv[1], "list") == 0) {
        list_leds();
    } else if (strcmp(argv[1], "on") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: LED name required\n");
            return 1;
        }
        set_led(argv[2], "255");
    } else if (strcmp(argv[1], "off") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: LED name required\n");
            return 1;
        }
        set_led(argv[2], "0");
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        return 1;
    }

    return 0;
}
```

**编译**：

```bash
arm-none-linux-gnueabihf-gcc -o led_ctrl led_ctrl.c
cp led_ctrl rootfs/nfs/usr/bin/
chmod +x rootfs/nfs/usr/bin/led_ctrl
```

**在开发板上使用**：

```bash
# 列出所有 LED
led_ctrl list

# 打开 LED
led_ctrl on led0

# 关闭 LED
led_ctrl off led0
```

## Shell 脚本集成

Shell 脚本是快速添加功能的利器，不需要编译。

### 示例：网络配置脚本

```bash
#!/bin/sh
#
# /usr/bin/netconfig - 简单的网络配置脚本
#

show_usage() {
    echo "Usage: netconfig <command> [args]"
    echo "Commands:"
    echo "  status          Show network status"
    echo "  eth0 <ip>       Configure eth0 IP"
    echo "  dhcp eth0       Enable DHCP on eth0"
}

net_status() {
    echo "=== Network Interfaces ==="
    ifconfig -a
    echo ""
    echo "=== Route Table ==="
    route
}

set_static_ip() {
    local iface=$1
    local ip=$2

    if [ -z "$iface" ] || [ -z "$ip" ]; then
        echo "Error: interface and IP required"
        return 1
    fi

    echo "Configuring $iface to $ip..."
    ifconfig $iface $ip up
    echo "Done."
}

enable_dhcp() {
    local iface=$1

    if [ -z "$iface" ]; then
        echo "Error: interface required"
        return 1
    fi

    if [ -x /sbin/udhcpc ]; then
        echo "Starting DHCP on $iface..."
        /sbin/udhcpc -i $iface -n
    else
        echo "Error: udhcpc not found"
        return 1
    fi
}

# 主逻辑
case "$1" in
    status)
        net_status
        ;;
    eth0)
        set_static_ip "$1" "$2"
        ;;
    dhcp)
        enable_dhcp "$2"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
```

**部署**：

```bash
cp netconfig rootfs/nfs/usr/bin/
chmod +x rootfs/nfs/usr/bin/netconfig
```

### 示例：系统监控脚本

```bash
#!/bin/sh
#
# /usr/bin/sysinfo - 系统信息显示脚本
#

echo "========================================"
echo "   System Information"
echo "========================================"
echo ""
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime)"
echo ""
echo "=== Memory Usage ==="
free
echo ""
echo "=== CPU Info ==="
echo "Processor: $(grep 'Processor' /proc/cpuinfo | cut -d: -f2)"
echo "Hardware:  $(grep 'Hardware' /proc/cpuinfo | cut -d: -f2)"
echo ""
echo "=== Mount Points ==="
mount | grep -E 'proc|sys|tmpfs|nfs'
echo ""
echo "=== Network ==="
ifconfig eth0
echo ""
echo "=== Processes ==="
ps
echo "========================================"
```

## 系统启动服务配置

如果你的程序需要在系统启动时自动运行，可以把它添加到启动脚本中。

### 方法 1：修改 /etc/init.d/rcS

```bash
#!/bin/sh
#
# System initialization script
#

PATH=/sbin:/bin:/usr/sbin:/usr/bin:$PATH
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib:/usr/lib
export LD_LIBRARY_PATH

# Mount all filesystems specified in fstab
mount -a

# Create and mount devpts for pseudo-terminal support
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

# Populate /dev with device nodes
mdev -s

# Configure loopback interface
ifconfig lo 127.0.0.1 up

# === 自定义启动服务 ===

# 启动应用程序（如果需要后台运行，使用 &）
# /usr/bin/myapp &

# 配置网络（可选）
# /usr/bin/netconfig eth0 192.168.60.200

# Print welcome message
echo ""
echo "Welcome to i.MX6ULL Embedded Linux!"
echo "System uptime: $(uptime)"
echo ""
```

### 方法 2：创建独立的启动脚本

对于复杂的服务，可以创建独立的启动脚本：

```bash
#!/bin/sh
#
# /etc/init.d/myapp - My application service
#

case "$1" in
    start)
        echo "Starting myapp..."
        /usr/bin/myapp --daemon
        ;;
    stop)
        echo "Stopping myapp..."
        killall myapp
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    status)
        if pidof myapp > /dev/null; then
            echo "myapp is running"
        else
            echo "myapp is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
```

然后在 `/etc/init.d/rcS` 中调用：

```bash
# Start custom services
[ -x /etc/init.d/myapp ] && /etc/init.d/myapp start
```

### 方法 3：使用 inittab 自动重启服务

如果你希望服务崩溃后自动重启，可以使用 `/etc/inittab` 的 `respawn` 功能：

```bash
# 在 /etc/inittab 中添加
::respawn:/usr/bin/myapp
```

这样当 `myapp` 退出时，init 会自动重启它。

## 完整的 Rootfs 验证

### 启动验证清单

- [ ] 系统能否正常启动
- [ ] 能否进入 shell
- [ ] `/proc`、`/sys` 是否正确挂载
- [ ] 网络是否正常
- [ ] 常用命令是否可用（ls, cd, cat, ps 等）
- [ ] 自定义程序是否能运行
- [ ] 库文件依赖是否满足

### 验证脚本

创建一个验证脚本 `verify_rootfs.sh`：

```bash
#!/bin/sh
#
# Rootfs 验证脚本
#

echo "========================================"
echo "Rootfs Verification"
echo "========================================"
echo ""

ERRORS=0

# 检查关键目录
echo "Checking directories..."
for dir in /bin /sbin /etc /lib /dev /proc /sys /tmp /usr; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir exists"
    else
        echo "  ✗ $dir missing!"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 检查关键设备文件
echo "Checking device files..."
for dev in /dev/console /dev/null /dev/zero; do
    if [ -e "$dev" ]; then
        echo "  ✓ $dev exists"
    else
        echo "  ✗ $dev missing!"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 检查虚拟文件系统挂载
echo "Checking mounted filesystems..."
for fs in /proc /sys /dev/pts; do
    if mount | grep -q "$fs"; then
        echo "  ✓ $fs mounted"
    else
        echo "  ✗ $fs not mounted!"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 检查配置文件
echo "Checking configuration files..."
for file in /etc/inittab /etc/fstab /etc/init.d/rcS; do
    if [ -f "$file" ]; then
        echo "  ✓ $file exists"
    else
        echo "  ✗ $file missing!"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 检查关键命令
echo "Checking commands..."
for cmd in sh ls cat mount ps; do
    if command -v $cmd > /dev/null 2>&1; then
        echo "  ✓ $cmd available"
    else
        echo "  ✗ $cmd not found!"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 检查网络
echo "Checking network..."
if ifconfig lo > /dev/null 2>&1; then
    echo "  ✓ Loopback interface up"
else
    echo "  ✗ Loopback interface down!"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 总结
echo "========================================"
if [ $ERRORS -eq 0 ]; then
    echo "✓ All checks passed!"
else
    echo "✗ $ERRORS error(s) found!"
    exit 1
fi
echo "========================================"
```

**运行验证**：

```bash
chmod +x verify_rootfs.sh
cp verify_rootfs.sh rootfs/nfs/usr/bin/
```

在开发板上运行：

```bash
verify_rootfs
```

## Rootfs 优化建议

### 减小体积

1. **使用 BusyBox**：BusyBox 已经包含了大部分常用命令
2. **去掉不需要的库**：只保留程序实际需要的库
3. **使用 strip 去除符号表**：

```bash
arm-none-linux-gnueabihf-strip rootfs/nfs/usr/bin/myapp
```

4. **启用内核模块**：把不需要的驱动编译成模块，按需加载

### 提高安全性

1. **设置正确的文件权限**：
   ```bash
   chmod 700 rootfs/nfs/root
   chmod 755 rootfs/nfs/etc/shadow
   ```

2. **使用只读 Rootfs**：在 `bootargs` 中添加 `ro` 选项，把 Rootfs 挂载成只读

3. **禁用不需要的服务**：最小化启动脚本

### 提高启动速度

1. **减少启动脚本中的等待**
2. **并行启动服务**（如果 init 支持）
3. **使用更快的文件系统**：squashfs 只读文件系统

## 总结：从零构建可用 Rootfs

经过这一系列章节的学习，我们完成了：

1. **BusyBox 编译**：搭建了 Rootfs 的基础
2. **目录结构创建**：按照 FHS 标准建立了文件系统骨架
3. **NFS 网络启动**：实现了开发板通过网络挂载 Rootfs
4. **应用集成**：添加了自定义程序和脚本
5. **系统优化**：验证并优化了 Rootfs

现在你有了一个功能完整、可用的嵌入式 Linux Rootfs。虽然它可能还很简单，但你已经掌握了构建和定制 Rootfs 的核心技能。

当你需要添加新功能时，基本流程是：

1. 交叉编译你的程序
2. 确定是静态还是动态链接
3. 如果动态链接，复制所需的库文件
4. 把程序部署到合适的目录（`/usr/bin`、`/usr/sbin` 等）
5. 如果需要开机启动，添加到启动脚本
6. 在开发板上测试验证

## 下一步：你自己的 Rootfs

现在你已经掌握了 Rootfs 构建的基础知识。接下来，你可以：

1. **添加你自己的应用程序**：把你实际的项目程序集成进来
2. **优化启动脚本**：根据需要定制系统启动流程
3. **添加更多功能**：比如网络服务、图形界面等
4. **打包部署**：把 Rootfs 打包成镜像，烧录到 Flash

嵌入式 Linux 的世界很大，Rootfs 只是其中的一个起点。但正是这个起点，支撑起了整个系统的运行。

祝你构建出完美的 Rootfs！
