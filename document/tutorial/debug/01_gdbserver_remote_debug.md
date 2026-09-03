---
title: gdbserver 远程调试全链：把断点打在实际的板子上
---

# gdbserver 远程调试全链：把断点打在实际的板子上

> 程序在板子上跑飞了，printf 加到十几轮还是定位不了，咱们缺的是把断点打到实际的板子上的能力。本篇把用户态交叉调试的整条链路走通：从 Buildroot 里那颗开关开始，让 rootfs 长出 gdbserver,再用命令行与 VSCode 两条路完成 target remote;手边没板子时，QEMU 客户机能把同一条链原样跑一遍。本篇是调试卷的第一篇；宿主 gdb 的基础操作在 Linux 基础卷教过，Buildroot 侧调试选项的取舍在 Buildroot 卷讲过，这里只做整条链路的实操；内核态调试(kgdb)不在本篇范围。

::: info 您将学到
- 调试器为什么拆成宿主交叉 gdb 与板端 gdbserver 两半，中间的 RSP 协议在做什么
- 怎么开 menuconfig 让 rootfs 长出 gdbserver,翻了开关却 0 包重做时该删哪个 stamp
- 从 target remote 到 break、continue、print、bt 的整条命令行链路，断点命中输出咱们逐行解读
- VSCode 的 cppdbg 怎么接管同一条链，launch.json 每个字段对应哪条 gdb 命令
- 共享库符号、多线程、pending 断点这几个坑的机制与验证手段，您拿判据自查
:::

::: tip 前置知识 · 咱们的环境
- 宿主 gdb 基础(break / run / print / bt / core 分析)您回 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md) 看，本篇从 target remote 开始接
- 串口登录与 minicom 配置见 [串口工具使用](../start/04_serial_tools_minicom.md),首次把系统跑到板子上的流程见 [启动与调试](../practical/03_boot_and_debug.md)
- BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY 等调试选项的含义与取舍，[Buildroot 调试与排错](../buildroot/10_debugging.md) 有专节，本篇带咱们把整条链路实操一遍，概念不再展开
- 路径上下文：咱们的宿主操作都在仓库根 ~/imx-forge 下进行，构建树是 out/release-latest/buildroot,rootfs 目录是 out/release-latest/rootfs,交叉工具链装在 /opt/arm-gnu-toolchain(Arm GNU Toolchain 15.2.Rel1)
:::

## 一、两台机器、一个协议：gdbserver 的分工

有一个会让新手困惑的事实：断点明明打在板子上的程序里，板子上却没有调试器的大头。咱们在宿主用的交叉 gdb 是 `/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gdb`,笔者机器上它有 10930648 字节，约 11MB;而拷进 rootfs 的 `/usr/bin/gdbserver` 只有 646328 字节。差出一个数量级——这个差距就是分工的由来：完整 gdb 要背符号解析、源码回溯、表达式求值、Python 脚本这些又大又吃内存的部件，塞进 rootfs 既浪费也不现实；gdbserver 只干最轻的两件事，用 ptrace 控制被调试进程，把事件按协议转发给网络对端。

整条链长这样：

```text
宿主机(x86_64 WSL)                板子 / QEMU 客户机(ARMv7)
arm-none-linux-gnueabihf-gdb ←TCP→ gdbserver → ptrace → ./demo
  ├─ 符号表:自己 -g 编的 demo          └─ 被调试进程，不需要任何符号
  └─ 源码:demo.c 在宿主磁盘上
```

宿主这端负责人机交互的全部：读符号、显示源码、算表达式、管断点；板端那端只是内核 ptrace 接口套了一个网络壳子。中间 TCP 上跑的是 GDB Remote Serial Protocol,习惯叫 RSP,一种文本形式的请求应答协议：gdb 把读寄存器、写内存、设断点这类操作编成报文发过去，gdbserver 应答。咱们不必背协议细节，记住一条就够：命令行里能做的操作，报文里都装得下，这决定了 GUI 调试器与命令行调试器能力完全等价。

这个架构正是 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md) 结尾预告的内容：那一章两次提到远程调试会在 imx-forge 的教程里展开，一次在介绍 gdbserver 是嵌入式标配处，一次在收尾说板子上的崩溃可以在开发机上远程分析。本篇就来补上这块，而且咱们只讲用户态；内核态的 kgdb 调试由驱动卷与内核卷的调试章负责，两边不串。

## 二、让 rootfs 长出 gdbserver

### 打开那颗开关

仓库有个教学上的约定：rootfs/buildroot/configs/imx6ull_aes_defconfig 里一个 gdb 相关选项都没开，为的就是让咱们自己动手开一次，知道这东西从哪来。选项本体定义在 third_party/buildroot/toolchain/toolchain-external/Config.in 里，名字叫 `BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY`,菜单文案是 Copy gdb server to the Target,依赖 `BR2_TOOLCHAIN_EXTERNAL`;咱们用外部工具链，.config 里这个依赖是 y,所以选项可见可选。

进 menuconfig,咱们走仓库封装好的脚本：

```bash
# 主机 ~/imx-forge
./scripts/build_helper/buildroot_menuconfig.sh
```

您进去后按这个路径找：Toolchain → Copy gdb server to the Target,按空格打成星号，一路保存退出。开关前后，.config 里第 300 行附近的变化是：

```ini
# 开关前
# BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY is not set

# 开关后
BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY=y
```

说明一下状态：defconfig 里没有这行，现在 out 树里的 =y 是咱们手动开出来的；哪天跑了 --reconfigure,defconfig 重放，这行会被拿掉。这个行为本身就是下面第二个坑。

### 翻了开关，gdbserver 却没写进 rootfs

::: warning 翻了开关不等于拷了文件
在一棵已经构建好的树上翻开开关，咱们重跑 ./scripts/build_helper/build-buildroot.sh,进度显示 0 个包重做，直接跳到 Step 3 同步，rootfs 里没有 gdbserver。原因是这颗开关的拷贝动作挂在 toolchain-external-custom 包的 install 步骤里(pkg-toolchain-external.mk 中 `TOOLCHAIN_EXTERNAL_INSTALL_TARGET_GDBSERVER` 那段)；该包的 `.stamp_installed` 早就存在，增量 make 一看 stamp 齐，认为无事可做，根本不会再走 install。要让文件拷进 rootfs，得让这个包把 install 重跑一遍，下面两条路都在笔者机器上验证过。
:::

```bash
# 主机 ~/imx-forge;官方单包目标，O= 与 BR2_EXTERNAL= 必须绝对路径
make -C third_party/buildroot O=$PWD/out/release-latest/buildroot \
     BR2_EXTERNAL=$PWD/rootfs/buildroot toolchain-external-custom-reinstall
```

reinstall 这条 make 只把文件拷进 buildroot 自己的输出树(out/release-latest/buildroot/target/ 下),release rootfs 是 build-buildroot.sh Step 3 的 rsync 才同步过去的。所以咱们跑完 reinstall 还得再跑一遍构建脚本——这次增量构建无事可做,正好一路走到 Step 3 把文件同步出来;嫌两步麻烦的话,下面删 stamp 的路子让构建脚本一步到位。

```bash
# 主机 ~/imx-forge;或删掉两个 install 系 stamp 再跑一遍构建
rm out/release-latest/buildroot/build/toolchain-external-custom/.stamp_installed \
   out/release-latest/buildroot/build/toolchain-external-custom/.stamp_target_installed
./scripts/build_helper/build-buildroot.sh
```

reinstall 这条路有个容易冤枉 make 的细节值得您知道：目标本身存在，buildroot 的通用包基建会给每个包生成 -reinstall、-rebuild 这类目标；但如果 O= 写了相对路径，make 会去 third_party/buildroot/out/ 底下找输出树，那条目录根本不存在，于是报 No rule to make target,看起来像目标没定义，其实只是路径解析错了。笔者第一次就撞在这行报错上，把 O= 换成 $PWD 打头的绝对路径，立刻通过。

### --reconfigure 会把开关悄悄改回去

::: warning 配置与磁盘脱节
跑完 build-buildroot.sh --reconfigure,.config 里那行变回 not set,可 rootfs/usr/bin/gdbserver 还躺在磁盘上，配置与磁盘就这么脱了节。--reconfigure 重放 defconfig,defconfig 里没有这颗开关，自然回到关闭；但 buildroot 的 files-list 只记录文件归属，没有卸载路径，已经拷进去的文件不会被拿走，此后的增量构建照样 0 包重做。想回到干净状态，用 --clean 全量重建，或手动删掉那个文件；调试期间笔者建议就让开关开着别来回拨，免得记不清磁盘处于哪种状态。
:::

### 验证：ls 加 file

```bash
# 主机 ~/imx-forge
ls -l out/release-latest/rootfs/usr/bin/gdbserver
file out/release-latest/rootfs/usr/bin/gdbserver
```

```text
-rwxr-xr-x 1 charliechen charliechen 646328 Sep  1 11:12 out/release-latest/rootfs/usr/bin/gdbserver
out/release-latest/rootfs/usr/bin/gdbserver: ELF 32-bit LSB executable, ARM, EABI5 version 1 (GNU/Linux), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, stripped
```

这组输出里能对上号的地方不少。文件真在，646328 字节，ARM EABI5,动态链接，加载器路径 /lib/ld-linux-armhf.so.3 与 rootfs 里的库对得上。结尾那个 stripped 值得留意：工具链原件 /opt/arm-gnu-toolchain/arm-none-linux-gnueabihf/libc/usr/bin/gdbserver 是 1192672 字节、with debug_info, not stripped,进了 buildroot 的 target-finalize strip 流程后被削掉将近一半。gdbserver 自己不需要被调试，strip 无妨；但同一条流程也会削咱们自己的程序，size 与符号这两方面的代价，第五节回来算清楚。这颗开关还顺带把 libthread_db.so.1 拷进了 rootfs/lib(pkg-toolchain-external.mk 给 gdbserver 场景追加的库)，多线程调试靠它，咱们 ls rootfs/lib 能看到它和 libpthread.so.0 作伴。

还有一句要提醒您：build-buildroot.sh 的 Step 3 用 rsync --delete 把 buildroot 的 target/ 同步到 release rootfs,咱们手工塞进 out/release-latest/rootfs 的文件，下次构建会被当多余文件删掉。第六节往 rootfs 里放 demo 时，放完尽快重新打包镜像，别指望手工文件常驻。

## 三、手搓命令行：从 target remote 到断点命中

### 试验程序：二十行循环程序

调试链路要一个稳定的试验程序，笔者为本篇准备了这段 demo.c:静态函数 heat_up 被 main 的循环反复调用，每轮 printf 加 sleep(1),跑 120 轮退出；断点设在 heat_up 上，命中时的参数 step 就是当轮循环计数：

```c
#include <stdio.h>
#include <unistd.h>

static int heat_up(int step)
{
    return step * 2 + 1;
}

int main(void)
{
    for (int i = 0; i < 120; i++) {
        int v = heat_up(i);
        printf("loop %d: heat=%d\n", i, v);
        fflush(stdout);
        sleep(1);
    }
    return 0;
}
```

编译参数 -g -O0 的理由 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md) 已经讲清楚，这里只补一个本篇特有的选择：-static。静态链接把共享库这个变量先摘掉，咱们聚焦链路本身，第五节再把动态链接放回来：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc -g -O0 -static -o demo demo.c
file demo
```

```text
demo: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, for GNU/Linux 3.2.0, with debug_info, not stripped
```

产物 2524908 字节，结尾的 with debug_info, not stripped 就是咱们要的判定。仓库里 examples/qemu-hello/hello_app 是另一个现成的试验程序，笔者 file 过，同样是 ARM 静态带符号产物，您嫌敲代码麻烦可以直接拿它练手。

### 传到板子上，起 gdbserver

咱们这棵 out 树里开着 dropbear(S50dropbear,/usr/bin 下有 scp),您一条 scp demo root@板子IP:/root/ 就能传过去。注意它同样不在 defconfig 里——干净构建出来的 rootfs 没有 scp,menuconfig 里 Target packages → dropbear 一颗开关就能补上;--reconfigure 重放 defconfig 后它也会跟着回退。传输细节是后面章节的主场,这里不展开。板端把服务起起来：

```bash
# 板端 /
gdbserver :2345 /root/demo
```

正常形态下它前台打印一行就绪信息(形如 Process /root/demo created; pid = NNN),然后停在等待连接的状态；宿主一连上，它再打印 Remote debugging from host ...,断点命中时被调试进程停在原地，板端输出暂停。脚本化场景咱们可以加 --once,一个调试会话结束它自动退出，不留后台进程；交互调试别加，断开后它还能等下一次连接。

::: warning 未实测标注
实际的板子上，gdbserver 前台输出本环境采集不了，笔者手边没有上电的 i.MX6ULL;上面的形态描述以 gdbserver 通用行为为准，等价的 QEMU 客户机输出在第六节有实测记录，端口与命令参数完全一致。
:::

### 宿主侧：一条 -batch 命令把整条链路走完

宿主这端不需要任何交互，咱们一条命令把读符号、连接、断点、继续、打印、栈回溯串完：

```bash
# 主机 ~/imx-forge
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gdb -batch \
    -ex "file demo" \
    -ex "set remotetimeout 10" \
    -ex "target remote localhost:12345" \
    -ex "break heat_up" \
    -ex "continue" \
    -ex "info args" \
    -ex "print step" \
    -ex "bt" \
    -ex "info breakpoints"
```

这份命令按笔者机器上实际跑过的记录给出，当时连的是 QEMU 客户机(localhost:12345);连实际的板子时把地址换成 板子IP:2345,其余一字不改。输出原样贴在下面：

```text
_start () at ../sysdeps/arm/start.S:79
warning: 79	../sysdeps/arm/start.S: No such file or directory
Breakpoint 1 at 0x102d0: file /home/charliechen/imx-forge/.claude/materials/debug-workflow/demo.c, line 6.

Breakpoint 1, heat_up (step=0) at /home/charliechen/imx-forge/.claude/materials/debug-workflow/demo.c:6
6	    return step * 2 + 1;
step = 0
$1 = 0
#0  heat_up (step=0) at /home/charliechen/imx-forge/.claude/materials/debug-workflow/demo.c:6
#1  0x000102f2 in main () at /home/charliechen/imx-forge/.claude/materials/debug-workflow/demo.c:12
Num     Type           Disp Enb Address    What
1       breakpoint     keep y   0x000102d0 in heat_up at /home/charliechen/imx-forge/.claude/materials/debug-workflow/demo.c:6
```

输出里的源码路径是笔者机器上素材目录的绝对路径，原样保留；您自己编译时，gdb 显示的就是您编译时的目录。逐行看：头两行是连接后的常态，gdbserver 启动的进程停在静态程序入口 _start,gdb 顺符号表想读 glibc 的 start.S 源码，宿主上没有这个文件，warning 无害，continue 一下就翻篇。Breakpoint 1 at 0x102d0 说明断点地址在本地符号表里就解析完了，这一步不需要连接(笔者单独验证过：不连接直接 break heat_up,同样得到这行)。Breakpoint 1, heat_up (step=0) 是第一次命中，循环第一轮 i=0;info args 给出 step = 0,print step 给出 $1 = 0,两个命令一个看参数表一个看表达式。bt 的双帧栈说清了来路：main 在 demo.c 第 12 行调用 heat_up,heat_up 停在第 6 行。走完这一条链，咱们已经在实际的板子(或虚拟机)的程序里拿到了断点、变量与调用栈。

断点先设还是先连，两种顺序都行。gdb 解析 heat_up 用的是本机符号表，连不连接不影响算地址；target remote 之后 break,是把算好的地址写进对方内存。习惯上 attach 一个已在跑的进程，咱们先连后设；gdbserver 专职启动程序的场景，像上面这样连完、设断点、再 continue,最顺。

## 四、VSCode 接管：launch.json 与 clangd 共存

命令行链路通了之后，GUI 只是换一层皮，底层还是同一个 gdb。咱们仓库的代码索引归 clangd 管(配置细节见工作流卷，本篇不展开)，调试引擎用 C/C++ 扩展的 cppdbg 类型；两者共存的办法是把扩展自己的索引关掉，settings.json 里写 `"C_Cpp.intelliSenseEngine": "disabled"`,扩展只出调试器，clangd 只出索引，互不打架。下面这份 .vscode/launch.json 是全仓第一份实例，字段值全部按本机真实路径填：

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "gdbserver remote (board or qemu)",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/examples/qemu-hello/hello_app",
            "cwd": "${workspaceFolder}",
            "MIMode": "gdb",
            "miDebuggerPath": "/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gdb",
            "miDebuggerServerAddress": "localhost:12345",
            "externalConsole": false,
            "setupCommands": [
                { "text": "set sysroot ${workspaceFolder}/out/release-latest/buildroot/staging" },
                { "text": "set solib-search-path ${workspaceFolder}/out/release-latest/buildroot/staging/lib" }
            ]
        }
    ]
}
```

字段逐个说。program 指向咱们本机那份带符号副本，这里用仓库里真实存在的 hello_app(with debug_info, not stripped);远程场景下板端跑的程序必须和它是同一份编译产物，否则地址对不上。miDebuggerServerAddress 是远程 attach 形态：QEMU 路线写 localhost:12345,实际的板子写 板子IP:2345。setupCommands 两条对应命令行的 set sysroot 与 set solib-search-path,为什么需要它们，第五节马上讲。cwd 影响相对路径的源码定位，externalConsole 咱们关掉，免得每次调试弹一个外部终端。

按下 F5 之后 VSCode 做的事，与命令行的映射给您列清楚：

| launch.json 字段 / 操作 | 等价 gdb 命令 |
|---|---|
| program | file /path/to/hello_app |
| miDebuggerPath 加 MIMode | (决定启动哪个 gdb) |
| miDebuggerServerAddress | target remote localhost:12345 |
| setupCommands 第一条 | set sysroot out/release-latest/buildroot/staging |
| setupCommands 第二条 | set solib-search-path .../staging/lib |
| 编辑器行号点断点、F5 | break / continue,断点列表即 info breakpoints |

::: warning 未实测标注
VSCode 的 F5 图形流程本环境跑不了，GUI 操作无法在笔者的采集环境里自动化验证；这份 launch.json 的每个字段都映射到第三节已实测的命令行，miDebuggerPath 与 sysroot 路径按本机真实值填写，您以这套参数为准。
:::

## 五、共享库与多线程的坑

### 动态链接回来了

同一份 demo.c,咱们去掉 -static,在 /tmp 下现场编一个动态版。demo.c 在仓库根，先把它送进 /tmp:

```bash
# 主机 ~/imx-forge
cp demo.c /tmp/

# 主机 /tmp
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc -g -O0 -o demo-dyn demo.c
file demo-dyn
```

```text
/tmp/demo-dyn: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, with debug_info, not stripped
```

interpreter 那一行的含义：程序启动要先靠板子上的 /lib/ld-linux-armhf.so.3 这个动态加载器，再按需映射 libc.so.6 等共享库。麻烦在于宿主 gdb 分析的是 ARM 库的符号，而它默认在本机文件系统里找，当然找不到。告诉它去哪找有两个命令：set sysroot 给一个前缀目录，gdb 会把 /lib、/usr/lib 都拼到这个前缀下找；set solib-search-path 直接给库目录列表。本仓现成的正确答案是构建树的 staging 目录：out/release-latest/buildroot/staging/lib 下面 libc.so.6、libpthread.so.0、libthread_db.so.1、ld-linux-armhf.so.3 一个不缺(笔者 ls 过)，第四节 launch.json 里那两条 setupCommands 指的就是它。

咱们验证不靠猜：连接之后执行 info sharedlibrary,gdb 列出每个已加载库的 From 地址与 Syms Read 列；全显示 Yes 说明库符号加载成功，全显示 No 就是 sysroot 没指对，回去查路径。这个判据比反复试错快得多。

### 别拿 rootfs 里被 strip 的产物调试

第二节留了个尾巴，这里接上：buildroot 的 target-finalize 会把 target/ 里的二进制统一 strip,rootfs 里的 gdbserver 从 1192672 字节被削到 646328 字节，削掉的正是调试符号。咱们自己的程序会不会被削，取决于它怎么进的 rootfs：包构建装进 target/ 的二进制走这条 strip 流程；rootfs overlay(BR2_ROOTFS_OVERLAY)拷进去的文件在 strip 之后才落位，不会被削；手工 cp 进 out/release-latest/rootfs 的文件(第六节放 demo 用的就是这条路)同样不经 target-finalize,符号无损，但下次构建会被 Step 3 的 rsync --delete 当多余文件清掉，第二节末尾提醒的就是这条。所以在板子上调试永远用自己 -g 编的那份产物，别图方便直接拿 rootfs 里 buildroot 装出来的现成二进制；file 输出结尾是不是 with debug_info, not stripped，一眼就能对上号。[Buildroot 调试与排错](../buildroot/10_debugging.md) 的 gdbserver 一节有同款提醒，构建侧的完整视角在那边。

### 多线程与 pending 断点

多线程一句话入门：咱们用 info threads 列出所有线程，thread N 切过去，bt 各看各的栈。要记住的是默认 all-stop 模式：任何一个线程命中断点，所有线程一起停，远程场景同样是这个默认；想换成 non-stop 逐线程控制属于进阶话题，本篇不碰。前面看到 libthread_db.so.1 已随开关进 rootfs,没有它，gdb 读不出线程信息。dlopen 场景另有一个坑：程序在运行时才加载的插件库里设断点，加载前 gdb 找不到符号会报错，前面加一句 set breakpoint pending on,断点先挂起，库加载进来的瞬间自动落地。

## 六、没有板子：QEMU 把同一条链跑通

手边没板子，咱们拿 QEMU 客户机当那台板子。run-qemu.sh 起的 mcimx6ul-evk 机器跑的是与实际的板子同一份 zImage、同一棵设备树、同一个 rootfs 打出来的 ext4 镜像，用户态调试链在虚拟机里和实际的板子上没有区别；唯一要解决的是宿主怎么连进虚拟机的网络。

### 端口转发：QEMU_NET_EXTRA

run-qemu.sh 头部注释把机制写得很清楚，咱们原文摘两段：

```text
# Networking: -nic user. On this machine QEMU wires user netdevs to the fec
# controllers itself (qemu_configure_nic_device); fec2 is the one with a PHY.
# Guest DHCP gets 10.0.2.15 with host-forwarding available via QEMU_NET_EXTRA.
# ……中间数行，省略……
#   QEMU_NET_EXTRA  Extra -nic/-netdev options appended verbatim (e.g.
#                   hostfwd=tcp::5022-:22 with -nic user)
```

机制说白：脚本固定起一块 -nic user(顺带挂了 tftp);QEMU_NET_EXTRA 环境变量的内容原样追加到 QEMU 命令行。追加的网卡落在哪颗 FEC 上，咱们不凭印象写；本篇没做 monitor 采集，手头实际跑出来的日志是单网卡形态，它的第一行就是接线证据：

```text
qemu-system-arm: warning: nic imx.enet.1 has no peer
```

这句告警 QEMU 一启动就打出来：第二颗 FEC imx.enet.1 没分到网卡，咱们那块唯一的 -nic user 落在第一颗 imx.enet.0 上。

而内核给这两颗 FEC 起的名字与编号是反着的，咱们实际跑出来的日志里是 fec 20b4000.ethernet eth0、fec 2188000.ethernet eth1:imx.enet.0 对应 2188000,在客户机里叫 eth1;imx.enet.1 对应 20b4000,叫 eth0。两条证据一串，单网卡形态下的接线就齐了：带 hostfwd 的这块网卡落在 2188000 那颗 FEC 上，日志里链路点亮(Link is Up)的正是 2188000.ethernet eth1,客户机里命令 udhcpc -i eth1 拿地址，拿的也是它。

::: warning 未实测标注
两网卡形态(脚本固定的 tftp 网卡 + QEMU_NET_EXTRA 追加的 hostfwd 网卡)咱们没有把整条链路跑通过，QEMU monitor 的 info network / info usernet 也没做过采集，下面的说法属机制推断，未采集验证：QEMU 大致按 -nic 在命令行里的先后顺序把用户态网卡分给两颗 FEC,追加的第二块多半落到 20b4000 那颗上，客户机里对应 eth0,要走这条路得 udhcpc -i eth0;而且两块网卡不能都 DHCP:两个 slirp 各发一条 10.0.2.0/24 的路由，路由一歧义连接就可能被重置。
:::

这条路咱们不当实操路径，本篇实操统一走下面“完整跑一遍”一节的单网卡直连：命令只起一块带 hostfwd 的 -nic user,您在客户机里敲的就是 udhcpc -i eth1。宿主侧 12345 端口的监听在 QEMU 一启动就建立，收到的包转发给客户机的 12345。

### 完整跑一遍

咱们的 demo 得先进 rootfs 再进镜像。把它拷到 release rootfs 的 /root 下，再显式重新打包 out/qemu/rootfs.ext4;run-qemu.sh 的自动重建只在它自己启动时触发，下面这条裸 qemu 命令不经过它，这一步咱们手动跑(与采集脚本一致)：

```bash
# 主机 ~/imx-forge
cp demo out/release-latest/rootfs/root/demo
./scripts/qemu_helper/make-rootfs-img.sh
```

启动命令按记录原样给出，它就是第三节那份输出的采集现场；开头那行清掉残留进程的 pkill，正是下面陈旧 QEMU 那个坑的解药，咱们别省：

```bash
# 主机 ~/imx-forge
pkill -f qemu-system-arm; sleep 2
out/qemu/build/qemu-system-arm -M mcimx6ul-evk -m 512M \
    -kernel out/mainline/linux/arch/arm/boot/zImage \
    -dtb out/qemu/imx6ull-aes.dtb \
    -append "console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw" \
    -drive file=out/qemu/rootfs.ext4,if=sd,index=1,format=raw \
    -nic user,hostfwd=tcp::12345-:12345 \
    -nographic -no-reboot
```

登录进虚拟机后，把网络与服务备好：

```bash
# QEMU 客户机 /
udhcpc -i eth1
ping -c 1 10.0.2.2
gdbserver :12345 /root/demo >/dev/null 2>&1 &
echo GDBSERVER_PID=$(pidof gdbserver)
```

咱们把 gdbserver 这条挂在后台，串口控制台才不被它占住，后面那行 PID 标记敲得动，下面第一个坑的就绪判据等的就是这行；>/dev/null 2>&1 只是不让它的输出混进串口日志。要是照第三节的前台形态起，就绪信号就换成它自己打出的那行就绪信息(形如 Process /root/demo created; pid = NNN),两种形态挑顺手的用。虚拟机里的实测记录，串口日志原样摘录：

```text
# ……登录与内核启动日志省略……
# udhcpc -i eth1 >/dev/null 2>&1; ifconfig eth0 2>/dev/null | head -1; ping -c 1 -W 3 10.0.2.2 >/dev/null 2>&1; echo NETRC=$?
[   31.241000] Micrel KSZ8081 or KSZ8091 20b4000.ethernet-1:02: attached PHY driver (mii_bus:phy_addr=20b4000.ethernet-1:02, irq=POLL)
[   31.251904] fec 2188000.ethernet eth1: Link is Up - 100Mbps/Full - flow control rx/tx
eth0      Link encap:Ethernet  HWaddr 00:11:22:33:44:01
NETRC=0
# gdbserver --version | head -1
GNU gdbserver (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 16.3.90.20250906-git
# gdbserver :12345 /root/demo >/dev/null 2>&1 &
# echo GDBSERVER_PID=$(pidof gdbserver)
GDBSERVER_PID=171
# ……会话收尾部分省略……
```

摘录里几处值得咱们驻足。头一条命令回显把三步检查串成了一行：udhcpc 静默拿地址、ifconfig 打出 eth0 的首行(顺带留下它的 MAC)、ping 静默探测网关再以 echo NETRC=$? 落一个结果；NETRC=0 就是 ping 成功的退出码，到 slirp 网关 10.0.2.2 的路通了。您分开手敲这三条，看到的是各自的正常回显，结论一样。两行内核日志是链路点亮的实据：PHY 挂上，fec 2188000.ethernet eth1 Link is Up,正是前面接线推断里说的那颗 FEC。版本行值得您多看一眼：客户机里的 gdbserver 与宿主交叉 gdb 同属 Arm GNU Toolchain 15.2.Rel1,版本串一致。gdb 与 gdbserver 版本错配是远程调试的经典雷区，轻则协议协商降级，重则满屏 unrecognized,同工具链成对使用最稳。宿主侧随后跑的正是第三节那条 -batch 命令，命中输出就是贴过的那份，一字不差。

### 撞出来的坑，个个有实据

这条 QEMU 链路笔者反复跑了好几轮才通，每一轮卡住的地方都留了日志；按撞上的顺序写给您。

::: warning 端口通了，服务没就绪
QEMU 启动才三秒，宿主上 12345 端口就能连上，立刻启动 gdb 却收到 Ignoring packet error,或 Remote replied unexpectedly to 'vMustReplyEmpty': timeout。端口能连是个假信号：hostfwd 的宿主侧监听随 QEMU 启动就存在，它只管转发；而虚拟机里从开机、登录到 gdbserver 起来，实测要三十多秒——端口通只证明 QEMU 在，不证明服务在。咱们判据用虚拟机里的标记，服务起完回一句 echo GDBSERVER_PID=$(pidof gdbserver),宿主侧等到这行再连，别拿端口探测当服务探测。
:::

::: warning 陈旧 QEMU 占着端口
要是上一轮没退干净的 QEMU 还握着宿主侧 12345,新一轮 QEMU 会绑定失败，只打一行告警，照样正常启动，虚拟机里一切如常；宿主 gdb 连上的其实是上一轮的僵尸服务，咱们看到的症状跟上一个坑长得一模一样——两个坑叠在一起更难分辨。宿主侧监听先到先得，新旧两个 QEMU 只有一个真正持有端口；绑定失败的告警不致命，QEMU 不会自己退出。起 QEMU 之前先用 pkill -f qemu-system-arm 把残留进程清掉，完整命令里第一行干的就是这件事。
:::

::: warning 虚拟机里网卡没有地址
gdb 一连就报 warning: unrecognized item "timeout" in "qSupported" response,紧接着 Connection reset by peer,这个症状多半出在虚拟机里那块网卡还没拿到地址。咱们的内核命令行没有 ip= 参数，虚拟机里 eth1 驱动起来后没有 IP 地址；slirp 把宿主发来的包投递到客户机的 10.0.2.15 时无人应答，连接被重置。登录后先跑 udhcpc -i eth1 拿地址，ping -c 1 10.0.2.2 验证到网关的路通了，再起 gdbserver。
:::

三个坑有个共性值得点破：它们全都伪装成 gdb 或 gdbserver 的毛病，根子却分别在网络转发时序、进程残留与 DHCP 上。远程调试链路长，报错出现在哪一端，根因未必在哪一端；咱们排查时得把整条链从头到尾过一遍，而不是盯着 gdb 的报错文本猜。

### 边界：这条链不管内核态

run-qemu.sh 没有配 -s / -S 这类 gdbstub 入口，本篇讲的也始终是用户态进程。咱们要进内核下断点，走 kgdb 路线，见驱动卷的 [内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) 与内核卷的 [驱动开发入门](../kernel/07_driver_basic.md);启动阶段的日志怎么读，[内核启动与调试](../kernel/08_kernel_boot_debug.md) 有完整一章。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| Ignoring packet error 或 vMustReplyEmpty timeout | gdb 连得太早，或连到了陈旧会话 | 等客户机里 gdbserver 的 PID 标记再连；起 QEMU 前 pkill 清场 |
| qSupported 报 unrecognized timeout 加 Connection reset | 客户机网卡没拿到地址，slirp 投递无人应答 | udhcpc -i eth1 后 ping 10.0.2.2 验证 |
| 翻开关后重跑构建 0 包重做 | toolchain-external-custom 的 install stamp 已存在 | 单包 reinstall(O= 用绝对路径)或删两个 install stamp 重跑 |
| 符号读不到，断点全是裸地址 | 产物被 strip,或 file 指错了副本 | 用自己 -g 编的产物，file 对齐 not stripped |
| 库符号加载不到，单步进 libc 断在裸地址 | sysroot / solib-search-path 没指对 | 指向构建树 staging,info sharedlibrary 看 Syms Read |
| --reconfigure 后开关回关，磁盘上 gdbserver 却还在 | defconfig 重放，files-list 只记归属不卸载 | 重新 menuconfig 开回；要干净状态用 --clean |

## 继续学习

- 上一篇：本卷从这篇开始，调试卷后面各篇咱们都拿这条远程链当地基
- 下一篇：[02 程序在板上崩了：strace、日志与 coredump](02_strace_log_coredump.md),程序没崩到要断点、但又说不清哪儿不对时,咱们换三件更轻的工具
- 深读：宿主 gdb 基础回 [GDB 调试入门](../linux-basics/07-devtools/ch32-gdb.md);构建侧选项与 stamp 机制看 [Buildroot 调试与排错](../buildroot/10_debugging.md);内核态 kgdb 转 [内核调试技术](../driver/00_chardev_base/05_kernel_debug_techniques.md) 与 [驱动开发入门](../kernel/07_driver_basic.md);登板串口操作回 [串口工具使用](../start/04_serial_tools_minicom.md)