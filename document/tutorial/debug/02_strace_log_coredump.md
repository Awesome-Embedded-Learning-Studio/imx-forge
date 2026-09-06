---
title: 程序在板上崩了：strace、日志与 coredump 的最小够用集
---

# 程序在板上崩了：strace、日志与 coredump 的最小够用集

> 上一篇咱们把 gdbserver 的断点链路走通了，可板子上的问题十有八九轮不到上断点：内核报了一句错、程序行为说不清哪儿不对、或者干脆吐一行 Segmentation fault 就退场。本篇补上这一层的三件轻量工具，日志、strace、coredump，从开销最低的 dmesg 一路用到把事故现场搬回宿主机回溯到源码行号；全部输出来自本仓 rootfs 在 QEMU 客户机里的真跑记录，实际的板子上命令一字不改。断点能力上一篇已经备好，串口日志的完整读法留给下一篇，本篇管的是还不用上断点的排查层。

::: tip 前置知识 · 咱们的环境
- menuconfig 里开软件包与 QEMU 直启这两件事，[01 gdbserver 远程调试全链](01_gdbserver_remote_debug.md) 已经走通，本篇直接沿用
- 宿主 gdb 的基础操作（含 core 文件分析入门）回 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md)；构建侧排错与 stamp 机制看 [Buildroot 调试与排错](../buildroot/10_debugging.md)
- 串口登录回 [串口工具使用](../start/04_serial_tools_minicom.md)；内核侧的 printk 级别与 bootargs 见 [内核启动与调试](../kernel/08_kernel_boot_debug.md)
- 路径上下文：宿主操作都在仓库根 ~/imx-forge 下进行，构建树是 out/release-latest/buildroot，rootfs 目录是 out/release-latest/rootfs，QEMU 用的 ext4 镜像在 out/qemu/rootfs.ext4，交叉工具链装在 /opt/arm-gnu-toolchain（Arm GNU Toolchain 15.2.Rel1）
:::

## 一、排查的次序为什么是日志→strace→core

断点是重型工具——要提前部署、要程序可重现、要人盯着会话跑。而日常的怪现象多数停在更浅的层：一句内核报错、一个说不清的行为、一次崩完就跑的段错误，轮不到咱们架起 gdbserver 去对付。本篇三件工具按成本与信息量递增排列，排序本身就是判断依据。

日志这一层的开销最低。rootfs 默认带着 syslogd 与 klogd，内核的环形缓冲从开机第一微秒就在记，出事回看一眼，看 dmesg 几乎不花什么代价；代价低意味着咱们任何时候都可以先看它，不用犹豫。strace 贵一档：要往 rootfs 装包，要以能重现的方式把程序再跑一遍。换来的是一次进程内视角，程序与内核的全部对话、每一个系统调用的参数与返回值，全都摊在桌面上。core 最贵也最全：要提前打开 ulimit 的闸门、要留着一份带符号的编译产物、还要把几百 KB 的文件从板子搬回宿主机；换来的也是另外两件给不了的，事故瞬间的完整内存快照，寄存器、栈、堆一样不少。

咱们排问题的次序就顺着这条成本线走：日志能解决的，不动 strace；strace 能看清卡点的，不必等它崩；真崩了，再请 core 出场。还有一条时间轴的维度值得您留意：日志随时能翻，strace 要能附着或重现，core 只在崩溃那一刻产生。三件工具其实对应三个时间窗，哪扇窗还开着，就用哪件。

## 二、日志层：dmesg 与 busybox 的 syslogd

### 两个 S 脚本起了什么

rootfs 的 /etc/init.d/ 目录咱们在宿主侧直接看，真实清单如下：

```bash
# 主机 ~/imx-forge
ls out/release-latest/rootfs/etc/init.d/
```

```text
S01seedrng
S01syslogd
S02klogd
S02sysctl
S10udevd
S11modules
S40network
S41ifplugd
S50crond
S50dropbear
S50telnet
rcK
rcS
```

咱们挑日志层的两位主角——S01syslogd 与 S02klogd，rcS 按文件名顺序把它们启动起来。同一轮启动的串口日志里有这两行作证：

```text
Starting syslogd: OK
Starting klogd: OK
```

S01syslogd 这个脚本是 buildroot 自带的标准写法，咱们把开头摘出来看：

```bash
#!/bin/sh

DAEMON="syslogd"
PIDFILE="/var/run/$DAEMON.pid"

SYSLOGD_ARGS=""

# shellcheck source=/dev/null
[ -r "/etc/default/$DAEMON" ] && . "/etc/default/$DAEMON"

# BusyBox' syslogd does not create a pidfile, so pass "-n" in the command line
# and use "--make-pidfile" to instruct start-stop-daemon to create one.
start() {
	printf 'Starting %s: ' "$DAEMON"
	# shellcheck disable=SC2086 # we need the word splitting
	start-stop-daemon --start --background --make-pidfile \
		--pidfile "$PIDFILE" --exec "/sbin/$DAEMON" \
		-- -n $SYSLOGD_ARGS
# ……后文的 status 判断与 stop()、restart() 省略……
```

脚本留了一个口子：/etc/default/syslogd 里可以填 SYSLOGD_ARGS 覆盖参数。笔者实测 /etc/default 这个目录在 rootfs 里压根没建，`[ -r /etc/default/syslogd ]` 这一行连文件带目录都找不到，所以最终执行的就是 /sbin/syslogd -n，一个参数都没带。这句里的 /sbin/syslogd 也值得看一眼本体：它和 /sbin/klogd、/sbin/logread、/bin/dmesg 一样，都是指向 busybox 的软链，咱们这棵 rootfs 的日志层整个由 busybox 1.37.0 一个二进制扛起。

### logread 输出为空的来历

```bash
# 虚拟机 /root
logread 2>/dev/null | tail -3; echo LOGREAD_DONE
```

```text
LOGREAD_DONE
```

logread 空空如也，很多朋友第一反应是系统没在记日志。logread 空的根因是 syslogd 没带 -C。busybox 的 logread 读的是 syslogd 维护的内存环形缓冲，而这个缓冲只有 syslogd 启动时带 -C 参数才会建；咱们的 S01syslogd 不带参数起服务，环形缓冲压根不存在，logread 自然一行都吐不出来。不带 -C 的 busybox syslogd 默认把消息写进 /var/log/messages，所以用户态的消息没有丢，只是换了个地方呆着，笔者重新采集时 tail /var/log/messages，咱们串口登录那一下的 auth.info root login on 'ttymxc0' 就躺在里面。您要让 logread 有货，得先 mkdir -p /etc/default（这个目录默认没建，ls 报的就是 No such file or directory，直接写会扑空），再往 /etc/default/syslogd 里填 SYSLOGD_ARGS="-C"，跑 /etc/init.d/S01syslogd restart。

这套做法笔者在 QEMU 客户机里实际跑通过：重启后用 logger 塞一句 logread ring proof 进去，logread 吐出来的头一行是 syslogd started: BusyBox v1.37.0，第二行正是咱们塞的那句。留档的事还得交代一层实情：环形缓冲在内存里，掉电即失；/var/log/messages 在咱们这棵 rootfs 里同样是易失的：/var/log 是指向 ../tmp 的软链，fstab 又把 /tmp 挂成了 tmpfs，messages 一样活内存里，重启即丢。运行期翻 messages 没问题，真要留档，得把日志引到持久化的挂载点上去。

### dmesg 与 /var/log/messages 的分工

```bash
# 虚拟机 /root
dmesg | tail -4
```

```text
[   12.413431] usb usb2: SerialNumber: ci_hdrc.1
[   12.423354] hub 2-0:1.0: USB hub found
[   12.423459] hub 2-0:1.0: 1 port detected
[   12.431578] platform sound-wm8960: deferred probe pending: fsl-asoc-card: snd_soc_register_card failed
```

咱们要内核消息，dmesg 直读内核自己的环形缓冲，开机至今的内核消息全在里面，最后一行那条 wm8960 的 deferred probe 就是活样本。klogd 的角色是把内核缓冲的消息转投给 syslogd 一份，让内核日志也进 /var/log/messages；dmesg 依然是最直接的那条路。

想按级别筛错误的朋友要注意一个差异：桌面发行版的 dmesg 有 -l err 这种级别过滤，咱们 rootfs 里这颗是 busybox applet。笔者翻了构建树里 busybox 1.37.0 的源码（util-linux/dmesg.c 的 usage 原文），选项只有 -c、-r、-n LEVEL、-s SIZE，没有 -l。所以筛错误的惯用写法是抓关键字：

```bash
# 虚拟机 /root
dmesg | grep -i -E "error|fail"
```

咱们的判据先看问题出在哪一层：驱动 probe 失败、挂载报错、OOM 这类内核态的问题，dmesg 是第一现场；crond、dropbear 这类 S 脚本起的用户态守护进程出事，去 /var/log/messages 翻。两处都查过再说没日志，别只看了 logread 就下结论。内核日志的级别体系与 bootargs 里 loglevel 的调法，[内核启动与调试](../kernel/08_kernel_boot_debug.md) 有完整一章，这里不占用篇幅。

## 三、strace：在系统调用层看它卡在哪

### 把 strace 装进 rootfs

装 strace 的套路与上一篇的 gdbserver 同一个入口。仓库 defconfig（rootfs/buildroot/configs/imx6ull_aes_defconfig）里没有 BR2_PACKAGE_STRACE，笔者 grep 过，一条不中；本地 out 树 .config 的第 797 行有 BR2_PACKAGE_STRACE=y，那是咱们自己开出来的实验状态。您走 menuconfig：

```bash
# 主机 ~/imx-forge
./scripts/build_helper/buildroot_menuconfig.sh
```

您进去找 Target packages → Debugging, profiling and benchmark → strace，空格打星保存退出，重跑构建：

```bash
# 主机 ~/imx-forge
./scripts/build_helper/build-buildroot.sh
ls -l out/release-latest/rootfs/usr/bin/strace
```

```text
-rwxr-xr-x 1 charliechen charliechen 1361460 Sep  2 09:23 out/release-latest/rootfs/usr/bin/strace
```

这里有个好消息，值得与上一篇的坑对照：strace 是普通包，构建安装全走 buildroot 的通用包流程，翻了开关重跑构建，增量就会把它编出来并同步到 release rootfs，没有 gdbserver 那种挂在 toolchain 包 install 步上的 stamp 坑。笔者实测的路径就是翻开关、跑一遍脚本、文件就位。--reconfigure 会把开关改回关闭这一点，它和 dropbear、gdbserver 是一个家族，细节上一篇讲过，这里只列动作。虚拟机里验一下版本：

```bash
# 虚拟机 /root
strace --version 2>&1 | head -1
```

```text
strace -- version 6.19
```

### 基础式：整程跟踪 /bin/ls

咱们拿一个短命程序开刀，跟踪结果写进文件再看：

```bash
# 虚拟机 /root
strace -o /root/ls.strace /bin/ls / >/dev/null 2>&1; echo STRACE_LS_RC=$?
head -12 /root/ls.strace
```

```text
STRACE_LS_RC=0
execve("/bin/ls", ["/bin/ls", "/"], 0xbed4ae4c /* 10 vars */) = 0
brk(NULL)                               = 0x10ac000
mmap2(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0xb6f89000
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/lib/libm.so.6", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
read(3, "\177ELF\1\1\1\0\0\0\0\0\0\0\0\0\3\0(\0\1\0\0\0\0\0\0\0004\0\0\0"..., 512) = 512
statx(3, "", AT_STATX_SYNC_AS_STAT|AT_NO_AUTOMOUNT|AT_EMPTY_PATH, STATX_BASIC_STATS, {stx_mask=STATX_BASIC_STATS|STATX_MNT_ID, stx_attributes=0, stx_mode=S_IFREG|0755, stx_size=312712, ...}) = 0
mmap2(NULL, 315496, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0xb6f3b000
mmap2(0xb6f87000, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x4b000) = 0xb6f87000
close(3)                                = 0
openat(AT_FDCWD, "/lib/libresolv.so.2", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
```

怎么读这份输出，咱们一行的结构拆开看：最左是系统调用名，括号里是参数，等号后面是返回值。返回 0 或正数（文件描述符、地址）是成功；返回 -1 是失败，后面跟着的 ENOENT 是内核错误码，括号里那半句是人话翻译，No such file or directory，文件不存在。第一行 execve 是一切的开头，内核把 /bin/ls 装进来换上它自己的地址空间；接着的 brk、mmap2 是动态加载器在布置内存；openat、read、mmap2 三步一组，是在逐个加载共享库，libm、libresolv、libc 一个个进场。中间两条 ENOENT 也有教学价值：/etc/ld.so.preload 与 /etc/ld.so.cache 都不存在，rootfs 没做 ldconfig 缓存，加载器只能挨个 openat 库文件，这两条失败无害。

### 过滤式：-e trace=openat

整程跟踪信息量大，多数时候咱们只想看某一类动作。找文件找不到、库找不到这类问题，盯 openat 最快：

```bash
# 虚拟机 /root
strace -e trace=openat /bin/ls /etc >/dev/null 2>/root/openat.strace; head -8 /root/openat.strace
```

```text
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/lib/libm.so.6", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD, "/lib/libresolv.so.2", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD, "/lib/libc.so.6", O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD, "/etc", O_RDONLY|O_NONBLOCK|O_LARGEFILE|O_CLOEXEC|O_DIRECTORY) = 3
+++ exited with 0 +++
```

-e trace= 后面接待跟踪的调用名单，输出里只剩这些行。程序报 library not found 的时候，您跑一遍这个式子，缺的是哪个库、它在找哪个路径，一眼就看出来了。

### 统计式：-c

第三个用法回答咱们另一类问题：程序慢，慢在哪。统计式不列每一条调用，只汇总：

```bash
# 虚拟机 /root
strace -c -o /root/c.strace /bin/ls >/dev/null 2>&1; cat /root/c.strace
```

```text
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 25.07    0.000960          68        14           statx
 15.12    0.000579         289         2           getdents64
 14.99    0.000574          57        10           mmap2
  9.85    0.000377          75         5           mprotect
  5.93    0.000227          75         3           read
  5.88    0.000225          45         5         1 openat
  5.51    0.000211         211         1           rseq
  4.47    0.000171          42         4         3 ioctl
  3.45    0.000132          33         4           close
  2.22    0.000085          28         3           brk
  1.57    0.000060          60         1           set_tls
  1.49    0.000057          57         1           write
  1.36    0.000052          52         1           getrandom
  1.15    0.000044          44         1           ugetrlimit
  0.71    0.000027          27         1           set_tid_address
  0.65    0.000025          25         1           getuid32
  0.60    0.000023          23         1           set_robust_list
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         1         1 access
------ ----------- ----------- --------- --------- ----------------
100.00    0.003829          63        60         5 total
```

读法看三列：calls 告诉您哪类调用最频繁（这里 statx 14 次、mmap2 10 次），% time 告诉您时间花在哪（statx 一项就占了四分之一），errors 列把失败计数单独拎出来（5 个错分散在 openat、access、ioctl）。咱们拿它做性能粗判：一个程序要是显示某类调用几千次，八成就是它在拖后腿，比拍脑袋猜靠谱得多。

### 多进程式：-f

程序派生子进程时，默认的 strace 只跟父亲，孩子的调用咱们看不见。-f 让它把整棵进程树都跟上：

```bash
# 虚拟机 /root
strace -f -o /root/f.strace /bin/sh -c "/bin/echo hi; /bin/echo ho" >/dev/null 2>&1; grep -c clone /root/f.strace; head -4 /root/f.strace
```

```text
2
146   execve("/bin/sh", ["/bin/sh", "-c", "/bin/echo hi; /bin/echo ho"], 0xbedb4e34 /* 10 vars */) = 0
146   brk(NULL)                         = 0x1068000
146   mmap2(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0xb6ee5000
146   access("/etc/ld.so.preload", R_OK) = -1 ENOENT (No such file or directory)
```

换人的那几行，咱们用 grep 挑出来看：

```bash
# 虚拟机 /root
grep -n -E "clone|execve|write\(1" /root/f.strace; tail -4 /root/f.strace
```

```text
1:146   execve("/bin/sh", ["/bin/sh", "-c", "/bin/echo hi; /bin/echo ho"], 0xbedb4e34 /* 10 vars */) = 0
53:146   clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD <unfinished ...>
56:146   <... clone resumed>, child_tidptr=0xb6d72088) = 147
62:147   execve("/bin/echo", ["/bin/echo", "hi"], 0x10684f4 /* 10 vars */) = 0
102:147   write(1, "hi\n", 3)               = 3
109:146   execve("/bin/echo", ["/bin/echo", "ho"], 0x10684f4 /* 10 vars */) = 0
149:146   write(1, "ho\n", 3)               = 3
146   brk(0x675000)                     = 0x675000
146   write(1, "ho\n", 3)               = 3
146   exit_group(0)                     = ?
146   +++ exited with 0 +++
```

行首多出来的那个数字就是 -f 的标记：进程号。146 是 shell 自己。咱们故意在 -c 参数里放了两条命令，ash 的两种走法正好各走一遍：第一条 /bin/echo hi 不是 -c 参数里的最后一条，ash 走正经的 fork 路线，而 glibc 的 fork() 落到内核接口上就是 clone 系统调用，所以第 53 行看到的是 clone，resumed 半行的返回值 147 就是孩子的进程号；孩子紧接着把自己 execve 成 /bin/echo，写出 hi 的那行顶的也是 147。

第二条 /bin/echo ho 换了个走法：它是 -c 参数里的最后一条命令，ash 直接 exec 换程序不换 pid（busybox 的 ash 源码 10600 行附近就写着这句注释：very last command in a script or a subshell does not need forking, we can just exec it），所以咱们看到 146 亲自变成 /bin/echo，写完 ho、以 146 的身份退场，整份日志里没有第二次 fork。判断子进程有没有被跟上，看行首的进程号列有没有换人；也别拿 grep -c clone 当进程计数器——这一次 clone 被 strace 拆成 unfinished 和 resumed 两行，grep 数出来是 2，真发生的进程创建只有一次。

### 附着运行中的进程

还有一个式子，本篇只给咱们讲机制：strace -p 进程号，附着到一个已经在跑的进程上，现场写法 strace -p $(pidof 进程名)。它是排查无声卡死的路子，第五节的剧本二会用到。

::: warning 未实测标注
strace -p 附着运行中进程这一式，本轮咱们的 QEMU 会话里没有跑过，没有采集到输出；机制与写法以 strace 通用行为为准，判据见第五节剧本二。
:::

## 四、coredump：把事故现场搬回宿主机

### 试验程序：十行空指针

笔者为这一节准备的试验程序叫 crash.c，故意往空指针里写值：

```c
#include <stdio.h>

static void poke_null(int tag)
{
    int *p = (int *)0;
    *p = tag;                    /* 第 6 行:崩在这里 */
}

int main(void)
{
    printf("about to poke null...\n");
    fflush(stdout);
    poke_null(42);
    return 0;
}
```

把上面这份源码存成仓库根下的 crash.c。咱们的编译参数还是那对老搭档，-g 留调试信息、-O0 关优化，道理 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md) 讲过：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc -g -O0 -o crash crash.c
file crash
```

```text
crash: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, with debug_info, not stripped
```

结尾的 with debug_info, not stripped 是咱们要认的判定，core 里的地址能不能回到这一行源码，全看它。咱们接着把产物送进 rootfs 并重新打包镜像，与上一篇放 demo 的动作一模一样；手工 cp 进 out/release-latest/rootfs 的文件会被下次构建的 rsync --delete 清掉，上一篇提醒过，咱们放完就尽快打包：

```bash
# 主机 ~/imx-forge
cp crash out/release-latest/rootfs/root/
./scripts/qemu_helper/make-rootfs-img.sh
```

### 两个开关：ulimit 与 core_pattern

咱们进了虚拟机。core 文件的大小限制默认关死：

```bash
# 虚拟机 /root
ulimit -c; ulimit -c unlimited; ulimit -c
```

```text
0
unlimited
```

默认值 0 不是谁跟咱们过不去：core 是进程的完整内存映像，动辄几百 KB 到几百 MB，嵌入式设备的存储心疼这个。ulimit 是 shell 内建命令，作用域只在当前会话，每个新登录的 shell 都会回到 0，想一劳永逸得写进 /etc/profile。还有一道开关管 core 文件写到哪、叫什么名字：

```bash
# 虚拟机 /root
cat /proc/sys/kernel/core_pattern
```

```text
core
```

值就是一个朴素的 core，意思是崩了就在工作目录写一个叫 core 的文件。桌面 Ubuntu 上这个值常是竖线打头的管道程序（apport 一类），core 不写进文件而被上报服务接管，那套背景 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md) 的 core 分析一节讲过；咱们的嵌入式 rootfs 没这套，所见即所得。

### 触发与现场

```bash
# 虚拟机 /root
cd /root && ./crash; echo CRASH_RC=$?
```

```text
about to poke null...
Segmentation fault (core dumped)
CRASH_RC=139
```

三条线索一起到：提示语打出来了，段错误带 core dumped 标记，退出码 139。139 这个数值得会反推：128 加 11，11 是 SIGSEGV 的编号，shell 对被信号致死的进程统一记 128 加信号号，看到 139 咱们不用猜就知道是段错误。工作目录里 core 应声落地：

```bash
# 虚拟机 /root
ls -l /root/core
```

```text
-rw-------    1 root     root        401408 Sep  2 01:24 /root/core
```

实测会话里这条 ls 是带通配的写法连跑了两遍，串口上带出来的终端颜色码咱们剥掉后照录，401408 字节，一个 13 KB 的程序崩出 400 KB 的现场，内存映像比程序本体重是正常事。

### 从 ext4 镜像把 core 拿回宿主机

QEMU 场景里虚拟机的磁盘是宿主上的一个 ext4 镜像文件（out/qemu/rootfs.ext4），关机之后它就是一份静止的文件系统，咱们可以用 e2fsprogs 的 debugfs 直接从里面把 core 拷出来，不走又慢又脆的串口搬运：

```bash
# 主机 ~/imx-forge,前提是 QEMU 已经 poweroff,目标路径随您换
debugfs -R "dump /root/core ./core" out/qemu/rootfs.ext4
file ./core
```

```text
./core: ELF 32-bit LSB core file, ARM, version 1 (SYSV), SVR4-style, from './crash', real uid: 0, effective uid: 0, real gid: 0, effective gid: 0, execfn: './crash', platform: 'v7l'
```

file 这一行的信息量不小：ELF core file 说明它是标准 core 格式，ARM 与 v7l 对上咱们的目标架构，from './crash' 与 execfn 记着它是谁崩出来的，uid 全 0 是 root 会话。到这里，事故现场已经完整躺在宿主磁盘上了。

::: warning 未实测标注
NFS root 场景（实际的板子通过网络挂宿主目录当根文件系统）本轮没有环境跑：按机制，crash 的工作目录在 NFS 挂载上，core 就等于直接写到了宿主磁盘，宿主侧无需任何搬运。这一条属机制推断，您在 NFS root 环境验证时以实际落点为准。
:::

### 交叉 gdb 读 core

最后一棒咱们交给交叉 gdb，一条 -batch 命令把读符号、载 core、回溯、看变量、看指令指针一口气做完：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gdb -batch \
    -ex "file crash" \
    -ex "core-file core" \
    -ex "bt" \
    -ex "frame 0" \
    -ex "print tag" \
    -ex "info registers pc"
```

输出原样照录（源码路径是笔者机器上的绝对路径，您自己跑时显示您的）：

```text
warning: Can't open file /root/crash during file-backed mapping note processing
[New LWP 174]
Core was generated by `./crash'.
Program terminated with signal SIGSEGV, Segmentation fault.
#0  0x00010450 in poke_null (tag=42) at /home/charliechen/imx-forge/.claude/materials/debug-workflow/crash.c:6
6	    *p = tag;                    /* 第 6 行:崩在这里 */
#0  0x00010450 in poke_null (tag=42) at /home/charliechen/imx-forge/.claude/materials/debug-workflow/crash.c:6
#1  0x00010482 in main () at /home/charliechen/imx-forge/.claude/materials/debug-workflow/crash.c:13
#0  0x00010450 in poke_null (tag=42) at /home/charliechen/imx-forge/.claude/materials/debug-workflow/crash.c:6
6	    *p = tag;                    /* 第 6 行:崩在这里 */
$1 = 42
pc             0x10450             0x10450 <poke_null+16>
```

头一行的 warning 您别慌——core 文件里记着的映射路径是虚拟机里的 /root/crash，宿主上没有这个文件，gdb 读不到那份数据段，但符号咱们已经用 file 命令给了，栈与变量照读不误，这行警告无害。[New LWP 174] 是崩掉的那个执行流，LWP 就是线程，单线程程序也是这个记法。#0 出现三次，是 -ex 序列里 core-file、bt、frame 0 各打了一遍。真正的干货在这几行里。SIGSEGV 定了死因。#0 帧给出 poke_null (tag=42) 停在 crash.c 第 6 行，#1 帧给出 main 在第 13 行发起的调用，调用来路就清楚了。$1 = 42 说明 print tag 拿到的参数值还是 42，正是 main 里塞进去的那个；pc 0x10450 <poke_null+16> 指明指令指针停在函数开头偏 16 字节处。死因、位置、调用来路、变量值都齐了，这个案子在笔者这里可以结了。

## 五、两个排障剧本

### 剧本一：段错误定位

把第四节拆成一个可复用的流程，您遇到任何段错误都能照走。现象是串口吐一行 Segmentation fault (core dumped)，退出码 139。头一件事查 ulimit：新登录的 shell 默认是 0，这时候重跑一百遍也不会有 core，把闸门打开（ulimit -c unlimited）再重跑触发。接着 ls 确认 core 落了多大，然后把它弄回宿主：QEMU 场景走 debugfs 从镜像里 dump，实际的板子走您顺手的传输方式，NFS root 则大概率天然就在宿主磁盘上。最后交叉 gdb 一条 -batch，bt 给行号，print 给变量，结案。有一件事千万忍住：别急着重编程序——core 对应的是崩溃那一刻的二进制，重编过后 file 载入的产物与 core 对不上号，栈回溯可能整个错位。当时怎么编的，留一份当时的产物，这是纪律，上一篇远程调试强调两端的程序必须同一份，是同一条道理。

### 剧本二：程序无声卡死

另一种形态的麻烦：进程还活着，不退出也不报错，就是不动了。咱们的思路是层层缩小包围圈。日志层看 dmesg，内核要是杀了它或饿着它（OOM、挂起任务告警）会有话要说。用户态没有线索的话，就该 strace -p 出场，附着上去看它堵在哪一个系统调用上，写法是 strace -p $(pidof 进程名)。附着之后看尾巴停在哪。最后一行停在 read，多半是在等输入或等对端，串口没数据、socket 对面没吭声，都长这个样。停在 futex 就是在等一把锁，死锁的味道这时才出来。要是停在 nanosleep，那只是节奏慢，程序没有死。还有一整屏还在刷的重复调用，那是活锁，它在空转。这一步的价值在于把排查对象从整个程序缩小到一个系统调用，接下来去查谁，方向就定了。附着操作要 root 或与目标进程同一个用户，不然 ptrace 权限这一关就过不去。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| logread 一行都不吐 | S01syslogd 不带参数启动 syslogd，没带 -C，内存环形缓冲没建 | 运行期看 /var/log/messages（同样在 tmpfs 里，重启即失）；要开环形缓冲：先 mkdir -p /etc/default，再给 /etc/default/syslogd 填 SYSLOGD_ARGS="-C"，跑 /etc/init.d/S01syslogd restart |
| 程序崩了却没生成 core | ulimit -c 还是 0（每个新会话重置），或 core_pattern 指向不可写目录 | 当前 shell 设 unlimited；cat /proc/sys/kernel/core_pattern 核对落点 |
| core 拿到了，gdb 读不出符号 | file 载入的产物与 core 不是同一份编译产物，或产物被 strip | 用当时那份 -g -O0 产物，file 确认 with debug_info, not stripped |
| 程序起不来，报找不到库 | 依赖库没进 rootfs 或路径不对 | strace -e trace=openat 盯 ENOENT，把缺的库补进镜像 |
| strace 附加进程报无权限 | ptrace 要求同 uid 或 root | 用 root 操作，或核对目标进程属主 |

## 继续学习

- 上一篇：[01 gdbserver 远程调试全链](01_gdbserver_remote_debug.md)，断点打在板上程序里的能力在那里备好，与本篇三件工具互补
- 下一篇：[03 串口日志阅读](03_serial_log_reading.md)，启动与运行期的日志在串口上怎么读、怎么留档
- 深读：宿主 gdb 与 core 文件分析的入门在 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md)；构建侧的调试选项与 stamp 机制看 [Buildroot 调试与排错](../buildroot/10_debugging.md)；内核侧的 printk 级别与启动日志读法看 [内核启动与调试](../kernel/08_kernel_boot_debug.md)
