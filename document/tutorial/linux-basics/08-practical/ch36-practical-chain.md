#    第 36 章  综合实战：从一个 GitHub 源码包到跑在板子上的程序

> **Part 8 · 综合实战**

---

## 引子

从前三十五章走下来，你会的命令不少了。但有个问题一直藏着：**这些命令是分开学的，也是分开记的。** 你在第 11 章背过 `tar`，在第 24 章背过文件传输，在第 35 章背过 `arm-none-linux-gnueabihf-gcc`。真到用的时候，脑子里是一堆散落的零件，不知道先拧哪颗螺丝。因此这一章我们只做一件事：**将前 35 章的零件落地。**

我们会扮演一个真实的嵌入式工程师。某天早上，同事丢给你一个 GitHub 链接，说：「这有个传感器采集的小工具，源码在这儿，你把它弄到正点原子 i.MX6ULL 板子上跑起来。」没有教程，没有提示，只有一条从源码到板子的完整链路。你会用到环境准备、下载、校验、解包、用户、权限、进程、GDB、vim、交叉编译、tftp——几乎每一章的工具都会在这条链上出现一次。

---

### 三台机器的分工

这套实战涉及三个角色，别搞混：

| 角色 | 是什么 | 干什么 |
|---|---|---|
| **WSL2 Ubuntu** | 你的构建主机（x86_64） | 装工具链、下载、编译、本地调试、交叉编译、跑 tftpd |
| **Windows 宿主机** | 跑 VSCode 的桌面 | 编辑代码、用 MobaXterm 连板子串口 |
| **i.MX6ULL 开发板** | 目标机（ARM32，极简 rootfs） | 只负责运行程序，通过串口操作 |

也就是说：**编译和调试在 WSL2，写代码在 Windows 的 VSCode，运行在板子（串口操作）。** 希望在后面的每一步，都可以清楚自己需要使用哪台机器上。

---

## 概念层

### 一条链，十五个环节

把「从 GitHub 到板子」拆开，大致是十五个环节：

```
环境准备 ──► 摸工具链 ──► 定任务 ──► 下载校验 ──► 建用户 ──► 解包加权
   │            │            │           │           │          │
 apt+工具链    tree/find    明确目标   wget/sha256  useradd   tar+chmod
                                                              │
      ┌───────────────────────────────────────────────────────┘
      ▼
后台进程 ──► 一键脚本 ──► gdb 调试 ──► vim/nano ──► 交叉编译 ──► 连板子 ──► tftp 上板 ──► 验证
   │            │             │            │             │           │           │          │
 &/jobs/kill  pipeline.sh   break/bt    改源码       arm-gcc     串口115200   tftp -g   跑起来
 nohup        退出码判断    print cfg   判空        file 看 ARM  MobaXterm   busybox
```

排查时，你需要大致判断「问题出在哪一环」——是下载的包损坏了？是权限没给对？是编译架构错了？还是网络不通？**定位到具体的环节，再进行处理。**

## 实践层

下面十五步，就是上述的落地步骤。每一步都标了「此刻你在哪台机器上」。

### 4.1 环境准备：系统工具与交叉工具链

**这一步在 WSL2。**

整条链要用到的系统工具，一把装齐（第 3 章讲过换源和基础工具，第 17 章讲过 apt 的完整用法）：

```bash
# WSL2
sudo apt update
sudo apt install -y \
    wget curl \
    tar xz-utils \
    tree \
    findutils grep \
    gdb \
    vim nano \
    tftpd-hpa tftp-hpa \
    ufw net-tools \
    build-essential cmake
```

装完逐条校验（`-v` / `--version` 简单过一下）：

```bash
wget --version   | head -1      # GNU Wget 1.21.4
curl --version   | head -1      # curl 8.x
tar  --version   | head -1      # tar (GNU tar) 1.35
xz   --version   | head -1      # xz (XZ Utils) 5.4.1
tree --version                  # tree v2.1.0
find --version   | head -1      # find (GNU findutils) 4.9.0
grep --version   | head -1      # grep (GNU grep) 3.11
gcc  --version   | head -1      # gcc (Ubuntu 13.x)  ← 主机编译器
gdb  --version   | head -1      # GNU gdb 15.x
vim  --version   | head -1      # VIM 9.x
nano --version   | head -1      # GNU nano 7.x
tftp --version  2>&1 | head -1  # tftp-hpa 5.2
ufw  --version                  # ufw 0.36.x
cmake --version | head -1       # cmake 3.28.x
```

> `tree` 是一个组件能够快速的了解目录结构；`build-essential` 给主机 gcc（4.9 本地调试）；`cmake` 是 4.11 的「更方便」路线；`tftpd-hpa` 是 4.13 板端文件的来源。

**接下来装交叉编译工具链。** 35 章用的是 Arm GNU Toolchain 15.2，安装在 `/opt/arm-gnu-toolchain`，前缀 `arm-none-linux-gnueabihf-`。完整步骤见 [工具链安装](../../start/01_start_from_toolchain.md)，这里走一遍：

```bash
# WSL2，下载（约 135 MB）
cd ~
wget https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz

# 断了就续传
wget -c https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

> ⚠️ **实在下载不下来怎么办**
>
> 把上面这条完整链接复制到浏览器里下载，再把文件从 Windows 拷进 WSL2。比如放到 `\\wsl$\Ubuntu\home\<你>\`，或者：
>
> ```bash
> # WSL2，从 Windows 下载目录拷进来（把 <你> 换成你的 Windows 用户名）
> cp /mnt/c/Users/<你>/Downloads/arm-gnu-toolchain-*.tar.xz ~/
> ```
>
> Windows 与 Linux 文件互传的完整方法，第 4 章讲过。

```bash
# WSL2，解压
tar -xf arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz

# 装到 /opt（Linux 放第三方软件的惯例位置）
sudo mv arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf /opt/arm-gnu-toolchain
```

配置 PATH——这一步属于第 30 章（环境变量与 Shell 配置文件）的地盘：

```bash
# WSL2
nano ~/.bashrc
# 在文件末尾加入这一行（注意结尾是 /bin）
export PATH=/opt/arm-gnu-toolchain/bin:$PATH

source ~/.bashrc
```

> ⚠️ **个人翻车过的问题**
>
> PATH 写成 `/opt/arm-gnu-toolchain`（少了 `/bin`）→ 永远 `command not found`。排查：
>
> ```bash
> echo $PATH | tr ':' '\n' | grep arm
> # 预期：只有一行 /opt/arm-gnu-toolchain/bin
> ```

```bash
# WSL2，验证
arm-none-linux-gnueabihf-gcc --version | head -2
# 预期输出
arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203
Copyright (C) 2025 Free Software Foundation, Inc.
```

> 对于工具链「能不能真的编出 ARM 产物」，留到 4.9 / 4.11 用 `file` 一并验证。
>
> **对应教程**：[换源、语言、基础工具初始化](../01-environment/ch03-init.md)、[软件安装全解](../04-system/ch17-software.md)、[环境变量与 Shell 配置文件](../06-script/ch30-envvar.md)、[工具链安装](../../start/01_start_from_toolchain.md)

### 4.2 摸工具链目录

**这一步在 WSL2。**

装完别急着用，让我们先看清这套工具链长什么样——也就是使用 `tree`/`find`/`grep` （第 7、10 章的内容）：

```bash
# WSL2

# 1) 工具链整体结构（两层）
tree -L 2 /opt/arm-gnu-toolchain
# 预期输出（节选）
/opt/arm-gnu-toolchain
├── bin
│   ├── arm-none-linux-gnueabihf-gcc
│   ├── arm-none-linux-gnueabihf-g++
│   ├── arm-none-linux-gnueabihf-ld
│   ├── arm-none-linux-gnueabihf-objdump
│   ├── arm-none-linux-gnueabihf-strip
│   └── ...
├── include
├── lib
├── lib64
├── libexec
└── share

# 2) bin 里到底有多少个工具
find /opt/arm-gnu-toolchain/bin -maxdepth 1 -name 'arm-none-linux-gnueabihf-*' | wc -l
# 预期输出：一个几十的数字

# 3) 挑几个后面要用的确认一下
ls /opt/arm-gnu-toolchain/bin | grep -E 'gcc$|ld$|objdump$|strip$|gdb$'
# 预期输出
arm-none-linux-gnueabihf-gcc
arm-none-linux-gnueabihf-gdb
arm-none-linux-gnueabihf-ld
arm-none-linux-gnueabihf-objdump
arm-none-linux-gnueabihf-strip

# 4) 目标三元组（这套工具链是为谁编的）
arm-none-linux-gnueabihf-gcc -dumpmachine
# 预期输出
arm-none-linux-gnueabihf

# 5) sysroot 在哪，里面的 libc 长什么样
arm-none-linux-gnueabihf-gcc -print-sysroot
find "$(arm-none-linux-gnueabihf-gcc -print-sysroot)" -name 'libc.so*' 2>/dev/null | head
# 预期输出（节选）
/opt/arm-gnu-toolchain/arm-none-linux-gnueabihf/libc.so
/opt/arm-gnu-toolchain/arm-none-linux-gnueabihf/libc/lib/libc.so.6
```

> 看懂这套编译器的结构，你就初步明白为什么交叉编译时头文件和库都指向这里，以及 4.11 里 `-static` 静态编译为什么不依赖板子上的库。
>
> **对应教程**：[目录导航](../02-commandline/ch07-navigate.md)、[搜索与查找](../02-commandline/ch10-search.md)

### 4.3 任务设定


```bash
# WSL2，确认在 x86_64 主机上
uname -m
# 预期输出
x86_64

# 确认交叉工具链（配了 PATH 后可直接用短名）
arm-none-linux-gnueabihf-gcc --version | head -1

# 建工作目录
mkdir -p ~/work/sensor-cfg
cd ~/work/sensor-cfg
```

任务清单：拿到一份带 bug 的传感器采集源码包，交叉编译后部署到板子上，并让它跑起来。

> **对应教程**：[终端与 Shell 入门](../02-commandline/ch06-shell.md)

### 4.4 下载与校验

**这一步在 WSL2。**

在我个人学习的过程中，我包有着一个疑惑：**为什么有些工具是要使用`wget` 下载github上的东西，到底能不能用 `wget` 下载 GitHub 上的东西？**后来我知道了答案：能，但**不能下载览器地址栏里那个链接**。

地址形态对照如下：

| 地址形态 | 用途 | 能不能 `wget` |
|---|---|---|
| `github.com/USER/REPO/blob/main/f.c` | 网页预览页 | ❌ 下回来是 HTML |
| `raw.githubusercontent.com/USER/REPO/main/f.c` | 单文件原文 | ✅ |
| `github.com/USER/REPO/archive/refs/heads/main.tar.gz` | 分支归档 | ✅ |
| `github.com/USER/REPO/releases/download/v1.0/pkg.tar.xz` | Release 资产 | ✅ |

注意 `blob/`：那是 GitHub 网页版的「文件预览页」，`wget` 这个地址，下载回来的是一个包裹着 HTML 的网页，不是源码，`gcc` 一编译就报一堆语法错误。正确的地址是 **raw 域名**。

项目发布了 Release，优先下载 Release 资产（版本固定、经过测试）：

```bash
# WSL2，下载源码包 + 校验文件
wget https://github.com/<USER>/<REPO>/releases/download/v1.0/sensor-cfg-1.0.tar.xz
wget https://github.com/<USER>/<REPO>/releases/download/v1.0/sensor-cfg-1.0.tar.xz.sha256

# 校验（这一步 35 章没展开，但工作中必备）
sha256sum -c sensor-cfg-1.0.tar.xz.sha256
# 预期输出
sensor-cfg-1.0.tar.xz: OK
```

看到 `OK`，说明文件完整、没被篡改。看到 `FAILED`，别犹豫，重新下载。老项目可能只提供 MD5：

```bash
$ md5sum -c sensor-cfg-1.0.tar.xz.md5
```

如果项目用 GPG 对 Release 签名（Linux 内核这类项目常见），还能验证来源：

```bash
$ gpg --verify sensor-cfg-1.0.tar.xz.asc sensor-cfg-1.0.tar.xz
# 预期输出
gpg: Good signature from "Release Bot <release@example.com>"
```

> 网络不稳时，`wget -c` 可以断点续传。不想用 `wget` 的话，`curl -L -O <URL>` 效果等价（虽然我个人基本上是先curl但是不知道为什么有时候不行换成wget就行了），`-L` 是跟随重定向（GitHub 会跳转），`-O` 是按远端文件名保存。
>
> **对应教程**：[换源、语言、基础工具初始化](../01-environment/ch03-init.md)、[交叉编译与 imx-forge 衔接](../07-devtools/ch35-crosscompile.md)

### 4.5 独立用户

**这一步在 WSL2。**

守护进程不该以 root 裸跑。建一个专用用户，后面的操作都在它的家目录里进行（第 15 章）：

```bash
# WSL2

# ——以下在“原始用户”（有 sudo 权限的那个）下执行——

# 建用户
sudo useradd -m -s /bin/bash sensor

# 看一眼是否建好
id sensor
# 预期输出
uid=1001(sensor) gid=1001(sensor) groups=1001(sensor)

# 把包挪到 sensor 家目录（~ 此时还是原始用户的家目录）
sudo cp ~/work/sensor-cfg/sensor-cfg-1.0.tar.xz /home/sensor/
sudo chown sensor:sensor /home/sensor/sensor-cfg-1.0.tar.xz

# 切到 sensor；4.6～4.11 都在 sensor 用户下执行
sudo -iu sensor
```

> **对应教程**：[用户与组管理](../04-system/ch15-user.md)

---


### 4.6 解包与加权

**这一步在 WSL2，sensor 用户下**（4.5 结尾 `sudo -iu sensor` 之后）。

**先解包。** 拿到 `sensor-cfg-1.0.tar.xz` 后，**先看再解**，别急着 `tar -xJf`（第 11 章）：

```bash
# WSL2
cd /home/sensor

# 只列出归档内容，不解压
tar -tJf sensor-cfg-1.0.tar.xz
# 预期输出
sensor-cfg-1.0/
sensor-cfg-1.0/sensor_daemon.c
sensor-cfg-1.0/Makefile
sensor-cfg-1.0/pipeline.sh
sensor-cfg-1.0/README.md

# 解包（.xz 用 -J，不是 -z！）
tar -xJf sensor-cfg-1.0.tar.xz -C /home/sensor/
```

> ⚠️ **`.xz` 用 `-J`**
>
> `.tar.gz` 用 `-z`，`.tar.xz` 用 `-J`。用错了会报 `xz: (stdin): File format not recognized` 或解出一堆乱码。第 11 章讲过 `-z`/`-j`/`-J` 的区别，`-J` 就是给 xz 的。

**再摸结构。** 进去摸清家底，`tree` 一眼看两层，`find` 找源码，`grep` 找待办（第 7、10 章）：

```bash
# WSL2
tree -L 2 /home/sensor/sensor-cfg-1.0
# 预期输出
/home/sensor/sensor-cfg-1.0
├── Makefile
├── README.md
├── pipeline.sh
└── sensor_daemon.c

# 找源码文件
find /home/sensor/sensor-cfg-1.0 -name '*.c'
# 预期输出
/home/sensor/sensor-cfg-1.0/sensor_daemon.c

# 找待办标记
grep -rn "TODO" /home/sensor/sensor-cfg-1.0
# 预期输出（如果 README 里有 TODO 项）
/home/sensor/sensor-cfg-1.0/README.md:12:TODO: 参数校验还没做
```

**最后加权。** 设置归属与权限（第 16 章）。先看现状：

```bash
# WSL2
ls -l /home/sensor/sensor-cfg-1.0
# 预期输出（注意 pipeline.sh 没有 x）
-rw-r--r-- 1 sensor sensor 1044 Sep 18 10:00 sensor_daemon.c
-rw-r--r-- 1 sensor sensor  220 Sep 18 10:00 pipeline.sh
```

`-rw-r--r--` 的意思是：所有者可读写，同组和其他人只读。`pipeline.sh` **没有 `x`（执行位）**，这时候直接运行它，就会撞上那个经典错误：

```bash
# WSL2
cd /home/sensor/sensor-cfg-1.0
./pipeline.sh
# 预期输出
bash: ./pipeline.sh: Permission denied
```

`Permission denied` 说的是「你没有执行这个文件的权限」，不是「文件不存在」（那是 `No such file or directory`），也不是「格式不对」（那是 `cannot execute binary file`）。现在看到它，就该检查执行位。

修复——目录锁死 `700`，源码 `644`，脚本 `755`：

```bash
# WSL2

chmod 700 /home/sensor
chmod 644 /home/sensor/sensor-cfg-1.0/sensor_daemon.c
chmod 755 /home/sensor/sensor-cfg-1.0/pipeline.sh
ls -l /home/sensor/sensor-cfg-1.0/pipeline.sh
# 预期输出
-rwxr-xr-x 1 sensor sensor 220 Sep 18 10:00 pipeline.sh
```

> `chmod 644` 表示 `rw-r--r--`（文件常用），`chmod 755` 表示 `rwxr-xr-x`（可执行文件/脚本常用）。普通用户不能 `chown`，改归属要用 root/sudo；这里以 sensor 用户解包，属主已经是 sensor，用 `chmod` 就够了。
>
> **对应教程**：[压缩归档](../02-commandline/ch11-archive.md)、[权限模型详解](../04-system/ch16-permission.md)、[目录导航](../02-commandline/ch07-navigate.md)、[搜索与查找](../02-commandline/ch10-search.md)

---

## 4.7 后台进程

**这一步在 WSL2。**

先手动编译一份**主机版**（x86，方便本地调试，第 31 章）：

```bash
# WSL2
cd /home/sensor/sensor-cfg-1.0
gcc -g -O0 -o sensor_daemon sensor_daemon.c
```

带参数跑起来（进采样循环）：

```bash
./sensor_daemon imu &
# 预期输出
[1] 20431

jobs
# 预期输出
[1]+  Running                 ./sensor_daemon imu &

ps aux | grep sensor_daemon
# 预期输出
sensor   20431  0.0  0.0   4520   912 pts/0    S    10:05   0:00 ./sensor_daemon imu
```

`[1]` 是作业号，`20431` 则是进程号（PID）。

**现在试杀它——你会发现杀不掉（我留下的缺陷 A，之后有用）。**

```bash
kill %1
# 预期输出：进程打印一行，然后……还在跑！
[sensor] received SIGTERM, exiting...

jobs
# 预期输出：它没死
[1]+  Running                 ./sensor_daemon imu &

kill -9 %1
# 预期输出：这次死了（SIGKILL 不可捕获）
```

> ⚠️ **为什么 `kill` 杀不掉？**
>
> 程序注册了 `SIGTERM` 处理函数，但函数里**只打印、没 `exit()`**，返回后主循环继续跑。这就是本章的**缺陷 A**。`SIGTERM`（信号 15）是「请你退出」，进程有机会捕获并清理；`SIGKILL`（信号 9）是「立刻死」，内核直接回收，进程无法拒绝。**先试 `kill`，不行再 `kill -9`。**

**关终端就死 → 用 `nohup`，并且用 `tail -f` 实时看日志：**

```bash
# stdbuf -o0 让 stdout 变成无缓冲，日志才能立刻落进 sensor.log
nohup stdbuf -o0 ./sensor_daemon imu > sensor.log 2>&1 &
# 预期输出
[1] 20488

# 实时查看日志；Ctrl+C 退出 tail（不会杀到 sensor_daemon）
tail -f sensor.log
# 预期输出（每秒一行，持续刷新）
[sensor] sampling imu...
[sensor] sampling imu...
[sensor] sampling imu...
```

> ⚠️ **为什么日志会“空”？**
>
> `nohup ... > sensor.log 2>&1` 之后，stdout 变成了文件，不再是终端。C 库检测到不是 tty，会把 stdout 从行缓冲切成**全缓冲**（通常 4 KB）。程序 `printf` 了但没凑满 4 KB，就一直在缓冲区里没落盘；一旦用 `kill -9` 杀进程，缓冲区被内核直接丢掉，`sensor.log` 就会一直是空的。
>
> 两种解法，任选其一：
>
> - 运行时加 `stdbuf -o0`，强制 stdout 无缓冲（上面用的就是这种，不改源码）；
> - 改源码，在每次 `printf` 后加 `fflush(stdout);`（后面 4.9 会顺带讲）。
>
> **注意**：不要用 `cat sensor.log` 看，它只读一次；进程每秒都在写，用 `tail -f` 才是「实时看日志」的正确姿势。

`> sensor.log` 把标准输出写进日志，`2>&1` 把标准错误也并进去（第 14 章重定向与管道），`nohup` 忽略挂断信号。这样即使你关掉终端，进程依然在跑。

几个键盘快捷键也归这里管：`Ctrl+C` 发送 `SIGINT`，中断当前前台进程；`Ctrl+Z` 发送 `SIGTSTP`，把前台进程挂起，之后可以用 `bg` 放到后台、`fg` 拉回前台。

清理一下，方便后面 4.8 重跑：

```bash
kill -9 %1 2>/dev/null
rm -f sensor.log sensor.pid
```

> `&`、`jobs`、`nohup`、`tail -f` 这几样在进程管理那一章没有展开讲，但它们是「让程序稳定在后台跑」的必备工具。
>
> **对应教程**：[进程管理——程序卡了怎么办](../04-system/ch19-process.md)、[重定向与管道](../03-text/ch14-redirect.md)

---

### 4.8 一键脚本

**这一步在 WSL2，sensor 用户下**（4.5 结尾 `sudo -iu sensor` 之后）。

前面几步敲了几十条命令。真正的工作里，你不想每次都手敲一遍。把它写成脚本 `pipeline.sh`（第 26、27、28 章）：

```bash
#!/bin/bash
# pipeline.sh — 综合实战：解包 → 加权 → 编译 → 后台跑起来
# 用法：./pipeline.sh sensor-cfg-1.0.tar.xz
# 每步用退出码判断；失败即退出，成功打印 [OK]
set -u

PKG="${1:?用法: $0 <sensor-cfg-1.0.tar.xz>}"
SENSOR_USER=sensor
SENSOR_HOME=/home/$SENSOR_USER
PKG_DIR="$SENSOR_HOME/sensor-cfg-1.0"
CC=gcc    # 主机编译器；交叉编译见 4.11

# 统一按 $SENSOR_HOME 解析包路径（脚本不一定在包所在目录）
case "$PKG" in
    /*) ;;
    *) PKG="$SENSOR_HOME/$PKG" ;;
esac

step=0
run_step() {
    step=$((step + 1))
    local desc="$1"; shift
    echo "==> 步骤 $step：$desc"
    if ! "$@"; then
        echo "[FAIL] 步骤 $step 失败：$desc" >&2
        exit 1
    fi
    echo "[OK] 步骤 $step 完成：$desc"
}


# 步骤 1：解包
run_step "解包源码" \
    bash -c "tar -xJf '$PKG' -C $SENSOR_HOME"

# 步骤 2：加权（chmod；属主已在 4.5 用 sudo chown 设好，普通用户不能再 chown）
run_step "设置权限" \
    bash -c "chmod 700 $SENSOR_HOME && chmod 644 $PKG_DIR/sensor_daemon.c && chmod 755 $PKG_DIR/pipeline.sh"

# 步骤 3：本机编译（主机 x86，用于 WSL2 上跑；交叉编译见 4.11）
run_step "本机编译 sensor_daemon" \
    bash -c "$CC -Wall -Wextra -g -O0 -o $PKG_DIR/sensor_daemon $PKG_DIR/sensor_daemon.c"

# 步骤 4：后台启动
run_step "后台启动守护进程" \
    bash -c "cd '$PKG_DIR' && { nohup stdbuf -o0 ./sensor_daemon imu > sensor.log 2>&1 & echo \$! > sensor.pid; }"

echo
echo "全部完成。PID = $(cat $PKG_DIR/sensor.pid 2>/dev/null)"
echo "现在试试：kill \$(cat $PKG_DIR/sensor.pid)   ← 缺陷 A，杀不掉"
```

加执行权限并运行：

```bash
# WSL2
chmod +x pipeline.sh
./pipeline.sh sensor-cfg-1.0.tar.xz
```

> **对应教程**：[Shell 脚本基础](../06-script/ch26-bash-basic.md)、[流程控制](../06-script/ch27-flow.md)、[函数与实战案例](../06-script/ch28-function.md)

---

### 4.9 本地 gdb 定位 bug

**这一步在 WSL2。**

假设 `sensor_daemon.c` 就是那份带缺陷的源码。它长这样（这是本章要调试的主角）：

```c
/* sensor_daemon.c — i.MX6ULL 综合实战：传感器采集守护进程
 * 故意保留两个缺陷：
 *   缺陷 A：SIGTERM 处理函数只打印、不退出 → kill 杀不掉
 *   缺陷 B：不带参数时 cfg 为 NULL，print_config 解引用 → SIGSEGV
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

typedef struct {
    char name[32];
    int  sample_rate;
} SensorConfig;

/* 缺陷 A：只打印，忘了 exit()；主循环也不检查标志 */
static void on_sigterm(int signo)
{
    (void)signo;
    printf("[sensor] received SIGTERM, exiting...\n");
}

/* 缺陷 B：没有检查 cfg 是否为 NULL */
static void print_config(SensorConfig *cfg)
{
    printf("sensor=%s sample_rate=%d\n", cfg->name, cfg->sample_rate);
}

int main(int argc, char *argv[])
{
    SensorConfig *cfg = NULL;   /* 故意不初始化 */

    if (argc == 2) {
        cfg = malloc(sizeof(SensorConfig));
        if (cfg == NULL) {
            return 1;
        }
        strncpy(cfg->name, argv[1], sizeof(cfg->name) - 1);
        cfg->sample_rate = 100;
    }

    print_config(cfg);          /* 不带参数时在这里崩溃 */

    signal(SIGTERM, on_sigterm);

    for (;;) {                  /* 缺陷 A 的采样循环，永不退出 */
        printf("[sensor] sampling %s...\n", cfg->name);
        sleep(1);
    }

    free(cfg);
    return 0;
}
```

先用**主机 gcc**（不是交叉编译器）编译一份带调试信息的版本，在 x86 上把 bug 找出来。这样速度快、工具全。编完顺手用 `file` 确认架构（第 33 章）：

```bash
# WSL2，注意：这一版是给 x86 主机调试用的，不是给板子的
gcc -g -O0 -o sensor_daemon sensor_daemon.c

file sensor_daemon
# 预期输出：x86-64
sensor_daemon: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, ... , with debug_info, not stripped
```

跑一下，触发崩溃（**不带参数**）：

```bash
./sensor_daemon
# 预期输出
Segmentation fault (core dumped)
```

用 GDB 打开（第 32 章）：

```bash
gdb ./sensor_daemon
```

会话过程：

```
(gdb) break print_config
Breakpoint 1 at 0x11a9: file sensor_daemon.c, line 24.
(gdb) run
# 预期输出
Breakpoint 1, print_config (cfg=0x0) at sensor_daemon.c:24
24          printf("sensor=%s sample_rate=%d\n", cfg->name, cfg->sample_rate);
(gdb) print cfg
# 预期输出
$1 = (SensorConfig *) 0x0
(gdb) bt
# 预期输出
#0  print_config (cfg=0x0) at sensor_daemon.c:24
#1  0x00005555555551c4 in main (argc=1, argv=0x7fffffffe0a8) at sensor_daemon.c:41
(gdb) quit
```

关键证据是 `print cfg` 返回 `0x0`。指针是空的，`print_config` 却直接解引用 `cfg->name`，于是 `SIGSEGV`。`bt`（backtrace）告诉你调用链是 `main → print_config`，问题就发生在第 24 行。这是本章的**缺陷 B**。

> **对应教程**：[GDB 调试入门](../07-devtools/ch32-gdb.md)、[GCC 与 Makefile 基础](../07-devtools/ch31-gcc-make.md)、[二进制工具箱](../07-devtools/ch33-binutils.md)

### 4.10 用 vim 修复 + VSCode 连 WSL

**这一步在 WSL2，sensor 用户下。**

在 `print_config` 里加一道空指针检查。下面给两种编辑器，**二选一**即可，但两种操作都要会——服务器上未必装了你惯用的那个。

#### 方式一：vim（第 12 章）

```bash
vim sensor_daemon.c
```

vim 里的操作序列：

1. `/cfg` 回车，搜索 `cfg`，跳到第一处。
2. 按 `n` 反复跳到下一个匹配，直到光标落在 `print_config` 函数体附近。
3. 按 `i` 进入插入模式，补上判断。
4. 按 `Esc` 退出插入模式。
5. 输入 `:wq` 保存并退出。

常用按键速查：

| 操作 | 按键 |
|---|---|
| 搜索 | `/cfg` 回车 |
| 下一个匹配 | `n` |
| 进入插入 | `i` |
| 退出插入 | `Esc` |
| 保存退出 | `:wq` |
| 全局替换 | `:%s/old/new/g` |
| 不保存退出 | `:q!` |

虽然我就会进入插入模式和退出插入模式和保存并退出就是了，我这里推荐看b站蛋老师的快速上手教程

修改后的函数：

```c
/* 修复：先检查 cfg 是否为 NULL */
static void print_config(SensorConfig *cfg)
{
    if (cfg == NULL) {
        fprintf(stderr, "no sensor config\n");
        return;
    }
    printf("sensor=%s sample_rate=%d\n", cfg->name, cfg->sample_rate);
}
```

**光改 `print_config` 还不够。** 回到 `main` 里，`print_config(cfg)` 之后还要再补一道 `cfg == NULL` 的判断，否则程序仍然会走到 `for (;;)` 里解引用 `cfg->name`：

```c
    print_config(cfg);

    /* 修复 B：没有配置就退出，不再进入采样循环 */
    if (cfg == NULL) {
        return 1;
    }

    signal(SIGTERM, on_sigterm);

    for (;;) {
        printf("[sensor] sampling %s...\n", cfg->name);
        sleep(1);
    }
```

#### 用 VSCode 直接连 WSL 编辑

不想在终端里编辑，可以让 Windows 的 VSCode 直连 WSL（细节见 [VSCode Remote-SSH 连 WSL](../../workflow/02_vscode_remote_ssh.md)）：

1. Windows 装 VSCode + **WSL** 和 **Remote-SSH** 扩展。
2. `Ctrl+Shift+P` → 输入 `WSL: Connect to WSL` 回车。
3. 左下角变绿 `WSL: Ubuntu`，即已进入 WSL。
4. `File → Open Folder` → `/home/sensor/sensor-cfg-1.0`。
5. 之后保存文件 = 直接写进 WSL 文件系统，和在 WSL 里 `vim` 效果一样。

> 也可以先在 `~/.ssh/config` 里配一个 Host 别名，再用 Remote-SSH 连进去，效果一样。
>
> **对应教程**：[VIM 编辑器实战](../03-text/ch12-vim.md)、[VSCode Remote-SSH 连 WSL](../../workflow/02_vscode_remote_ssh.md)

修完在主机上重新编译验证：

```bash
# WSL2
gcc -g -O0 -o sensor_daemon sensor_daemon.c
./sensor_daemon
# 预期输出
no sensor config
# 退出码 1

./sensor_daemon imu
# 预期输出
sensor=imu sample_rate=100
[sensor] sampling imu...
[sensor] sampling imu...
# 进入采样循环，Ctrl+C 退出
```

主机上缺陷 B 修好了。

---

## 4.11 交叉编译

**这一步在 WSL2，sensor 用户下。**

**先给 sensor 用户配上工具链 PATH。** 4.1 里那行 `export PATH=/opt/arm-gnu-toolchain/bin:$PATH` 是写在原始用户的 `~/.bashrc` 里的；`sudo -iu sensor` 之后加载的是 `/home/sensor/.bashrc`，里面没有这一行，直接敲 `arm-none-linux-gnueabihf-gcc` 会 `command not found`：

```bash
# WSL2，sensor 用户下
echo 'export PATH=/opt/arm-gnu-toolchain/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 验证
arm-none-linux-gnueabihf-gcc --version | head -1
# 预期输出
arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203
```

**先把 4.9 编好的主机版备份掉。** 4.9 里 `gcc -g -O0 -o sensor_daemon` 编出来的是 x86-64 版，直接拿来做交叉编译会被覆盖。先改个名：

```bash
# WSL2，sensor 用户下
cd /home/sensor/sensor-cfg-1.0

# 备份主机版，后面本地 GDB 或主机验证还用得上
cp sensor_daemon sensor_daemon_x86

# 顺手确认一下
file sensor_daemon_x86
# 预期输出：ELF 64-bit LSB pie executable, x86-64 ...
```

现在把这份修好的源码编译成 ARM32 程序。先手动敲一遍，产物起名为 `sensor_daemon_arm`，避免和主机版混淆：

```bash
# WSL2
arm-none-linux-gnueabihf-gcc \
    -Wall -Wextra -g -O0 -static \
    -o sensor_daemon_arm sensor_daemon.c

file sensor_daemon_arm
# 预期输出：ARM
sensor_daemon_arm: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, with debug_info, not stripped
```

> **对照 4.9**：同一份 `sensor_daemon.c`，主机 gcc 编出 `x86-64`，交叉 gcc 编出 `ARM`。

**再走一遍 Makefile 的方式**（第 31 章的推荐布局：Makefile 放项目根、`.o` 和可执行文件也生成在同目录，小项目够用、直观）：

```makefile
CC      = arm-none-linux-gnueabihf-gcc
CFLAGS  = -Wall -Wextra -g -O0 -static
TARGET  = sensor_daemon
SRC     = sensor_daemon.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: all clean
```

```bash
# WSL2
make clean && make
ls
# 预期输出（三个版本并存）
Makefile  README.md  pipeline.sh  sensor_daemon  sensor_daemon.c  sensor_daemon_arm  sensor_daemon_x86
```

**核对三个版本的架构，一目了然：**

```bash
# WSL2
file sensor_daemon_x86 sensor_daemon_arm sensor_daemon
# 预期输出
sensor_daemon_x86: ELF 64-bit LSB pie executable, x86-64, ...
sensor_daemon_arm: ELF 32-bit LSB executable, ARM, EABI5 ..., statically linked, ...
sensor_daemon:     ELF 32-bit LSB executable, ARM, EABI5 ..., statically linked, ...
```

| 文件名 | 谁编的 | 架构 | 用途 |
|---|---|---|---|
| `sensor_daemon_x86` | 主机 gcc | x86-64 | 4.9 本地 GDB 调试 |
| `sensor_daemon_arm` | 交叉 gcc 手动 | ARM32，静态 | 上板（推荐用这份） |
| `sensor_daemon` | 交叉 gcc 经 Makefile | ARM32，静态 | 上板（Makefile 默认产物） |

> **我个人第一次要加 `-static`**：动态链接的 ARM 程序依赖板子上的 ARM 版动态链接器（`ld-linux-armhf.so.3`）和一堆 `.so` 库。极简 rootfs 里很可能缺某个库，程序启动就会报 `not found`。静态链接把所需代码全部塞进可执行文件，不依赖外部库，是「第一次上板」最省心的做法。

> ⚠️ Makefile 中命令行的缩进**必须使用 Tab 键**，不能用空格。看到 `missing separator. Stop.`，大概率是空格混进去了。（虽然我都是 vscode 里写，出问题直接叫 ai 改）

> **提示：项目变大时，CMake 更方便**
>
> 教程第 31 章走的是「同目录」的简单路线。当项目从 1 个 `.c` 变成十几个、还要分模块、多目标时，**CMake 更规范**——它天然是 **out-of-source**（产物集中在 `build/`，源码目录保持干净），交叉编译也只需要一个工具链文件。
>
> 交叉编译工具链文件 `toolchain-arm.cmake`：
>
> ```cmake
> set(CMAKE_SYSTEM_NAME Linux)
> set(CMAKE_SYSTEM_PROCESSOR arm)
> set(CMAKE_C_COMPILER /opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc)
> set(CMAKE_FIND_ROOT_PATH /opt/arm-gnu-toolchain)
> set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
> set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
> set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
> ```
>
> `CMakeLists.txt`：
>
> ```cmake
> cmake_minimum_required(VERSION 3.16)
> project(sensor_daemon C)
> add_compile_options(-Wall -Wextra -g -O0)
> add_executable(sensor_daemon sensor_daemon.c)
> target_link_options(sensor_daemon PRIVATE -static)
> ```
>
> 构建（注意 `build/` 目录，源码目录保持干净）：
>
> ```bash
> cmake -B build -DCMAKE_TOOLCHAIN_FILE=toolchain-arm.cmake
> cmake --build build
> file build/sensor_daemon
> # 预期输出：ELF 32-bit LSB executable, ARM, EABI5 ...
> ```

> **对应教程**：[交叉编译与 imx-forge 衔接](../07-devtools/ch35-crosscompile.md)、[GCC 与 Makefile 基础](../07-devtools/ch31-gcc-make.md)、[二进制工具箱](../07-devtools/ch33-binutils.md)

---

### 4.12 连接实物板子：串口

**这一步在 Windows（MobaXterm）。**

MobaXterm是我个人使用的一种连接工具，里面有ssh，x11，vcn，串口等等。由于我用不习惯它的终端（谁家好人shift+insert是复制啊），所以我基本上只使用串口和x11了。这是下载链接：[官方网站](https://mobaxterm.mobatek.net/)
众所周知，串口是「救砖通道」——U-Boot 倒计时、内核 panic、rootfs 挂载失败，这些时刻网络还没起来，SSH 一个字节都送不出来，只有串口从第一行输出起就在岗。

用 **MobaXterm_Personal_24.2** 连接：

1. 用 USB 转串口线把板子的调试串口接到电脑。
2. 打开设备管理器，查串口号（如 `COM3`）。
3. MobaXterm → `Session` → `Serial`：
   - **Serial port**：`COM3`
   - **Speed**：`115200`
   - Data bits `8`、Stop bits `1`、Parity `None`
   - **Flow control**：`None`（流控开着板子可能不出字）
4. 点 OK，板子开机，串口里能看到 U-Boot 和内核日志。
5. 回车进入登录：

```
imx6ull login: root
# 密码为空则直接回车
```

```bash
# 板子上执行（通过串口）
uname -a                 # Linux ... armv7l
which sshd               # 预期：找不到，可能是我买二手的原因，反正我没找到。
which tftp               # 预期：/usr/bin/tftp 或 busybox 的 tftp
ifconfig                 # 看板子 IP，下一步 tftp 要用
```

> 串口参数（115200、8N1、无流控）是这套板子的标准值。Windows 直连与 usbipd 透进 WSL 两条通道怎么选、日志怎么留，见 [串口终端：开发台的第二块屏幕](../../workflow/03_serial_terminal.md)。
>
> **对应教程**：[网络配置](../05-network/ch21-netconfig.md)、[串口终端：开发台的第二块屏幕](../../workflow/03_serial_terminal.md)


### 4.13 传输上板：tftp

**这一步分两侧：WSL2 起服务，板子拉取。**

没有 SSH ⇒ **不能用 scp（终究还是ssh嘛）**。给极简板子传文件，用 **tftp**（第 24 章讲过 tftp，第 25 章讲防火墙）。
ps：我个人喜欢在板子设置静态ip地址，感兴趣的可以问问ai怎么做。

**WSL2 侧准备服务**（第 20 章 systemd）：

> **先切回原始用户。** 4.5 结尾 `sudo -iu sensor` 之后你一直在 sensor 用户下，而 sensor 不在 sudoers 里，`sudo` 会失败。先 `exit` 退出 sensor 的登录 shell，或另开一个 WSL2 终端。
>
> 另外 WSL2 要能用 `systemctl`，需要 `/etc/wsl.conf` 里已开启 systemd：
>
> ```ini
> [boot]
> systemd=true
> ```
>
> 改完执行 `wsl --shutdown` 重启 WSL2 才生效。

```bash
# WSL2，原始用户下
sudo systemctl start tftpd-hpa
sudo systemctl enable tftpd-hpa

# 确认服务在听 69 端口
sudo ss -lunp | grep :69

# tftp 根目录不存在就建（默认 /srv/tftp 或 /var/lib/tftpboot，以 /etc/default/tftpd-hpa 为准）
sudo mkdir -p /srv/tftp

# 把产物放进 tftp 根目录（推的是 4.11 手动交叉编译出来的 ARM 静态版）
sudo cp /home/sensor/sensor-cfg-1.0/sensor_daemon_arm /srv/tftp/sensor_daemon
sudo chmod 644 /srv/tftp/sensor_daemon

# 防火墙放行（第 25 章）
sudo ufw allow 69/udp
```

**板子侧拉取**（在 MobaXterm 串口里执行）：

```bash
# 板子上执行；192.168.1.16 是 WSL2 的 IP
mkdir -p /home/sensor
tftp -g -r sensor_daemon -l /home/sensor/sensor_daemon 192.168.1.16

# 或 busybox 写法
busybox tftp -g -r sensor_daemon -l /home/sensor/sensor_daemon 192.168.1.16

# tftp 拉下来默认是 644，必须加执行位
chmod +x /home/sensor/sensor_daemon

# 确认到手
ls -l /home/sensor/sensor_daemon
# 预期输出（这个 x 是 chmod 给的，不是 tftp 自动给的）
-rwxr-xr-x    1 root     root        ...  /home/sensor/sensor_daemon
```

> ⚠️ **防火墙有两层**
>
> WSL2 的网络是 `networkingMode=mirrored`，此时 **Windows 防火墙也管 WSL 的入站流量**。除了 WSL 里的 `ufw allow 69/udp`，还要在 Windows PowerShell（管理员）里放行：
>
> ```powershell
> New-NetFirewallRule -DisplayName "tftp-udp" -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow -Profile Any
> ```
>
> 详见 [WSL2 开发注意事项](../../workflow/01_wsl2_env_config.md)。
>
> 如果 WSL2 不是 `networkingMode=mirrored`（默认 NAT），板子访问不到 WSL2 的 `192.168.x.x`。这种情况要么在 `/etc/wsl.conf` 里改成 `networkingMode=mirrored`，要么在 Windows 主机上装 tftpd，要么做端口转发。

> **对应教程**：[文件传输](../05-network/ch24-transfer.md)、[防火墙：ufw](../05-network/ch25-firewall.md)、[服务管理：systemd](../04-system/ch20-systemd.md)、[主机与板子传文件](../../workflow/06_host_board_transfer.md)

---

### 4.14 上板验证

**这一步在板子（串口）。**

```bash
# 板子上执行
ls -l /home/sensor/sensor_daemon
# 预期输出（x 来自 4.13 的 chmod +x）
-rwxr-xr-x    1 root     root        ...  /home/sensor/sensor_daemon

# 带参数跑 → 缺陷 A（SIGTERM 只打印不退出）
/home/sensor/sensor_daemon imu &
ps | grep sensor_daemon
kill <PID>
# 预期输出：打印 received SIGTERM 后仍在跑 → 用 kill -9

# 不带参数跑 → 缺陷 B 已修复
/home/sensor/sensor_daemon
# 预期输出
no sensor config
# 无 Segmentation fault
```

**缺陷 A 复现、缺陷 B 已修复**，说明整条链路（环境→下载→校验→解包→加权→用户→进程→调试→修复→交叉编译→tftp 上板）走通了。

### 4.15 教程 ↔ 实战 对照表

走完整条链，回头看 35 章各自落在哪一步：

| 章 | 标题 | 用到了？ | 环节 | 判定 |
|:---:|---|:---:|:---:|:---:|
| 1 | WSL2：Windows 里秒开 Linux | 背景 | 全篇 | 🟡 |
| 2 | 虚拟机安装 Ubuntu | 未用 | —— | ⚪ |
| 3 | 换源、语言、基础工具初始化 | ✅ | 4.1 | ✅ |
| 4 | Windows 与 Linux 文件互传 | 🟡 | 4.1 | 🟡 |
| 5 | Docker 开发环境搭建 | 未用 | —— | ⚪ |
| 6 | 终端与 Shell 入门 | ✅ | 全篇 | ✅ |
| 7 | 目录导航 | ✅ | 4.2 / 4.6 | ✅ |
| 8 | 文件操作 | ✅ | 4.5 / 4.6 | ✅ |
| 9 | 文件查看 | 🟡 | 4.6 | 🟡 |
| 10 | 搜索与查找 | ✅ | 4.2 / 4.6 | ✅ |
| 11 | 压缩归档 | ✅ | 4.6 | ✅ |
| 12 | VIM 编辑器实战 | ✅ | 4.10 | ✅ |
| 13 | 文本处理三剑客 | 未用 | —— | ⚪ |
| 14 | 重定向与管道 | ✅ | 4.7 | ✅ |
| 15 | 用户与组管理 | ✅ | 4.5 | ✅ |
| 16 | 权限模型详解 | ✅ | 4.6 | ✅ |
| 17 | 软件安装全解 | ✅ | 4.1 | ✅ |
| 18 | 磁盘管理 | 未用 | —— | ⚪ |
| 19 | 进程管理 | ✅ | 4.7 | ✅ |
| 20 | 服务管理：systemd | ✅ | 4.13 | ✅ |
| 21 | 网络配置 | ✅ | 4.12 / 4.13 | ✅ |
| 22 | 网络诊断 | ✅ | 4.13 | ✅ |
| 23 | SSH 远程连接 | ❌ | —— | ⚪ 板子无 SSH |
| 24 | 文件传输 | ✅ | 4.13（tftp） | ✅ |
| 25 | 防火墙：ufw | ✅ | 4.13 | ✅ |
| 26 | Shell 脚本基础 | ✅ | 4.8 | ✅ |
| 27 | 流程控制 | ✅ | 4.8 | ✅ |
| 28 | 函数与实战案例 | ✅ | 4.8 | ✅ |
| 29 | 定时任务：crontab | 未用 | —— | ⚪ |
| 30 | 环境变量与 Shell 配置文件 | ✅ | 4.1（PATH） | ✅ |
| 31 | GCC 与 Makefile 基础 | ✅ | 4.9 / 4.11 | ✅ |
| 32 | GDB 调试入门 | ✅ | 4.9 | ✅ |
| 33 | 二进制工具箱 | ✅ | 4.9 / 4.11（`file`） | ✅ |
| 34 | Git 日常操作手册 | 未用 | —— | ⚪ |
| 35 | 交叉编译与 imx-forge 衔接 | ✅ | 4.11 | ✅ |

**实战需要、教程没展开的（超纲）**：

| 环节 | 超纲内容 | 教程相近内容 |
|---|---|---|
| 4.1 | 交叉工具链安装（官方 tar.xz + /opt + PATH） | 35 章有概念，[start/01](../../start/01_start_from_toolchain.md) 有全流程 |
| 4.4 | `wget` 下 GitHub、`sha256sum -c`、`gpg --verify` | 第 3 章装了 wget，没讲 GitHub 与校验 |
| 4.7 | `&` / `jobs` / `nohup` | 第 19 章只提了一句 `bg`/`fg` |
| 4.8 | 退出码判断 + 函数封装 | 第 26–28 章有 Bash，没讲退出码模式 |
| 4.12 | 串口连接（MobaXterm 参数） | 35 章没有串口 |
| 4.13 | tftp 服务端配置、串口 XMODEM | 第 24 章讲了 tftp 客户端 |
| 4.11 | CMake 交叉编译工具链文件 | 第 31 章只提了 CMake 的名字 |

**教程讲了、本实战没用的**：第 2、5、13、18、29、34 章，以及第 23 章（板子无 SSH）。

---

## 练习题

**练习 36.1** ⭐（理解）

为什么 `wget https://github.com/<USER>/<REPO>/blob/main/sensor_daemon.c` 下载回来的不是源码？正确的地址应该是什么？

> **提示**：想想浏览器地址栏里的 `blob` 代表什么，`raw.githubusercontent.com` 又代表什么。

**练习 36.2** ⭐⭐（应用）

写一个脚本 `verify-and-unpack.sh`：接收一个 `.tar.xz` 文件名作为参数，先用对应的 `.sha256` 校验，校验通过才解包，失败则打印错误并以非零状态退出。要求用上 `set -u`、`if` 和 `${1:?...}`。

> **提示**：`sha256sum -c` 成功返回 0，失败返回非零。解 `.xz` 记得用 `-J`。


---

## 本章结语

这十五步走完，你将初步完成一个工作流：**从网上的源码，到板子上跑起来的程序。** 这正是 imx-forge 后续教程（U-Boot、内核、驱动）每天都在重复的动作。

---

[← 上一章](../07-devtools/ch35-crosscompile.md)
[专栏首页 →](../index.md)
