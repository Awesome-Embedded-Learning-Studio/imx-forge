# Init 系统

::: info 本节你将学到
- Buildroot 提供哪些 init 系统，IMX-Forge 为什么选 `BR2_INIT_BUSYBOX`
- BusyBox init 的完整启动链路：`/etc/inittab` → `rcS` → `Sxx*` 脚本，以及 getty 登录是怎么冒出来的
- skeleton 包替你铺好了哪些目录和配置（fstab、设备节点、`/var`），为什么 post-build 还要补一个 `/home`
- 给 rootfs 加自启服务的两种姿势：overlay 塞 `S99myapp` vs package 里写 `INSTALL_INIT_SYSV`
- 什么情况下才值得切到 systemd，以及 IMX-Forge 暂时不上的取舍
:::

::: tip 前置知识 · 环境
- 读过 [第 06 章：Rootfs 定制三板斧](06_rootfs_customization.md)，知道 overlay / post-build / post-image 各自在哪一环介入
- 读过 [第 07 章：添加自定义 package](07_custom_package.md)，对 `generic-package` 的几个 `INSTALL_*` 钩子有印象
- 手搓时代的那篇 [inittab 与 init](../rootfs/03_inittab_init.md)——本章最后会拿它做对照
- 环境：Buildroot 2026.02（`third_party/buildroot/`），IMX-Forge br2-external tree（`rootfs/buildroot/`）
:::

## 为什么这一章值得单独讲

说实话，init 这件事在手搓 rootfs 那会儿，是我们一笔一画拼出来的——自己写 `/etc/inittab`、自己写 `rcS`、自己 `mknod` 凑设备节点，一行都不敢漏。到了 Buildroot，这一摊活儿大部分被它内化掉了：选一个 init 系统，skeleton、inittab、rcS、fstab 全都自动生成，听起来像是在享福。

可也正是因为"自动生成"，你会产生一种"这块不用管了"的错觉。先别急——真等你哪天想加个自启服务、换个串口，或者对着一个"root 登录被拒"的串口抓耳挠腮时，就会发现这些文件到底是哪个包生成的、按什么顺序跑的、又有哪些地方是 Buildroot 默认没做、需要你补的，一件都躲不掉。所以这一章我们干的事很明确：把这条链路从 defconfig 一直追到板子上那个 `buildroot login:` 提示符，全部落到 IMX-Forge 的真实文件上。你会发现，真正的坑往往不在 init 本身，而在 Buildroot 默认配置和项目配置之间那几道没咬合的缝。

## Buildroot 支持哪些 init 系统

打开 `make menuconfig`，进 **System configuration → Init system**，会看到一个 choice。对照 Buildroot 源码 `system/Config.in`，选项大致分两类。

通用型那几款是这么一个阵容：BusyBox（`BR2_INIT_BUSYBOX`，实际 init 程序就是 busybox 的 `init` applet，也是 Buildroot 的默认，足够绝大多数嵌入式场景）；systemV（`BR2_INIT_SYSV`，走 `package/sysvinit` 里的 sysvinit，老牌 Unix init，也读 inittab，语法和 BusyBox 略有不同）；OpenRC（`BR2_INIT_OPENRC`，Gentoo/Alpine 那套依赖型启动系统，需要 glibc/musl 加动态库）；以及 systemd（`BR2_INIT_SYSTEMD`，新一代 init，并行启动、socket/D-Bus 激活、cgroup 管理一把梭）。整理成表更直观：

| 选项 | Kconfig | 实际 init 程序 | 说明 |
|------|---------|---------------|------|
| BusyBox | `BR2_INIT_BUSYBOX` | busybox 的 `init` applet | Buildroot 默认，足够绝大多数嵌入式场景 |
| systemV | `BR2_INIT_SYSV` | `package/sysvinit` 里的 sysvinit | 老牌 Unix init，也读 inittab，语法和 BusyBox 略有不同 |
| OpenRC | `BR2_INIT_OPENRC` | `package/openrc` | 依赖型启动系统（Gentoo/Alpine 那套），需要 glibc/musl + 动态库 |
| systemd | `BR2_INIT_SYSTEMD` | `package/systemd` | 新一代 init，并行启动、socket/D-Bus 激活、cgroup 管理 |

特殊型则是给容器和极简场景准备的，`BR2_INIT_CATATONIT`、`BR2_INIT_TINI`、`BR2_INIT_TINYINIT` 都是"几乎啥也不干"的 PID 1；`BR2_INIT_NONE` 更干脆——"我自己来"，Buildroot 不装任何 init，你得起一个 package 或 overlay 自己提供 `/sbin/init`。

官方手册（《Buildroot 2026.02 manual》的 *init system* 一节）给的建议很坦诚：先用 BusyBox init，它对嵌入式系统已经够用；只在系统复杂到需要 D-Bus、服务间通信时才上 systemd。

IMX-Forge 听从这个建议。我们现在要看的是自己的 defconfig：

```bash
# rootfs/buildroot/configs/imx6ull_aes_defconfig
# ===== System(串口 ttymxc0 115200,busybox init,eudev 动态设备节点)=====
BR2_TARGET_GENERIC_GETTY_PORT="ttymxc0"
BR2_TARGET_GENERIC_GETTY_BAUDRATE_115200=y
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
BR2_INIT_BUSYBOX=y
```

为什么选 `BR2_INIT_BUSYBOX`？理由其实很直接。一是轻量，BusyBox 的 init 不过几百行代码的一个 applet，不额外引入任何库，i.MX6ULL 这种 512M 内存的板子跑它毫无压力。二是我们根本不需要依赖管理，IMX-Forge 的 rootfs 服务就那么几个（alsa、网络、可选 Qt 应用），启动顺序靠 `Sxx` 数字编号就能讲清楚，用不着 systemd 那张 unit 依赖图。三是它和 eudev 搭得起来——注意上面 `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y`，设备节点用 eudev 动态管理（比 mdev 重一点，但能配合固件加载、规则文件），而 init 仍是 BusyBox。这两件事是独立的：init 选 BusyBox 不代表你必须用 mdev，别在脑子里把它们绑死。

还有个细节值得提一句：选 `BR2_INIT_BUSYBOX` 时 Buildroot 会自动 `select` 两个包（见 `system/Config.in`），`BR2_PACKAGE_BUSYBOX` 和 `BR2_PACKAGE_INITSCRIPTS`，并在用默认 skeleton 时再 `select BR2_PACKAGE_SKELETON_INIT_SYSV`。这两个包就是下面整条链路的主角，先把名字记住。

## BusyBox init 的启动链路

内核挂载 rootfs 之后，会去 `/sbin/init`（或 bootargs 里的 `init=`）找 PID 1。BusyBox init 启动后第一件事就是读 `/etc/inittab`。Buildroot 自带的 inittab 源文件在 `package/busybox/inittab`，我们完整看一遍（这就是构建后落到 rootfs 的原始内容，省略了头部版权注释）：

```bash
# /etc/inittab —— package/busybox/inittab
# Format for each entry: <id>:<runlevels>:<action>:<process>

# Startup the system
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -o remount,rw /
::sysinit:/bin/mkdir -p /dev/pts /dev/shm
::sysinit:/bin/mount -a
::sysinit:/bin/mkdir -p /run/lock/subsys
::sysinit:/sbin/swapon -a
null::sysinit:/bin/ln -sf /proc/self/fd /dev/fd
null::sysinit:/bin/ln -sf /proc/self/fd/0 /dev/stdin
null::sysinit:/bin/ln -sf /proc/self/fd/1 /dev/stdout
null::sysinit:/bin/ln -sf /proc/self/fd/2 /dev/stderr
::sysinit:/bin/hostname -F /etc/hostname
# now run any rc scripts
::sysinit:/etc/init.d/rcS

# Put a getty on the serial port
#ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100 # GENERIC_SERIAL

# Stuff to do before rebooting
::shutdown:/etc/init.d/rcK
::shutdown:/sbin/swapoff -a
::shutdown:/bin/umount -a -r
```

我们逐段往下走。先看 sysinit 阶段那一坨，它把系统能跑起来的基本盘全铺了：先挂 `/proc`、把根分区重挂成读写、建 `/dev/pts` 和 `/dev/shm`、`mount -a`（读 `/etc/fstab` 挂其余文件系统）、再做 `/dev/fd`、`/dev/stdin` 这些软链、最后设主机名。你回头对比一下手搓教程就会发现，这些活儿当年我们都得自己在 `rcS` 里一行行写，现在 inittab 顶层就替你做掉了，省心不少。

紧接着是关键的一行 `::sysinit:/etc/init.d/rcS`——它把"启动一堆编号脚本"这件事交给了 `rcS`，这是接下来要单独拆的重头戏。再往下，那行带 `# GENERIC_SERIAL` 标记的注释先留个印象，它是给 Buildroot 留的"占位符"，构建时会被 sed 替换成你配置的真实串口，下一节细讲。最后的 shutdown 阶段走 `rcK`（逆序停服务）、关 swap、卸载所有文件系统，和 sysinit 遥相呼应。

### rcS：按编号跑 Sxx 脚本

这里要注意一个容易混淆的点：`rcS` 不是 BusyBox 提供的，而是上面提到的 `initscripts` 包，源文件在 `package/initscripts/init.d/rcS`：

```bash
#!/bin/sh
# Start all init scripts in /etc/init.d
# executing them in numerical order.
#
for i in /etc/init.d/S??* ;do
     [ ! -f "$i" ] && continue          # 忽略失效软链
     case "$i" in
	*.sh)  ( trap - INT QUIT TSTP; set start; . $i ) ;;  # .sh 直接 source，快
	*)     $i start ;;                                   # 其余 fork 子进程
     esac
done
```

逻辑简单到可爱：匹配 `/etc/init.d/S??*`，按文件名字典序（本质上就是数字大小）依次执行，统一传 `start` 参数。`rcK` 一模一样，只是反着来、传 `stop`。所以"哪个服务先起"完全由文件名上的两位数字决定——这也是为什么后面我们自启服务要叫 `S99myapp`，99 基本就是压轴出场。

那么 `/etc/init.d/` 下到底都有哪些 `Sxx`？答案是各个包按需"贡献"。比如 BusyBox 包自己就带了一批（`package/busybox/S01syslogd`、`S02klogd`、`S10mdev`、`S15watchdog`、`S41ifplugd`、`S50crond`、`S50telnet`、`S90httpd`），只有你在 busybox.config 里开了对应 applet，对应的 `Sxx` 才会被装进 rootfs；`initscripts` 包则贡献了一个 `S11modules`，开机时按 `/etc/modules` 加载内核模块。这套机制的好处是，rootfs 里最终有哪些启动脚本，完全跟着你的配置走，不用的东西连脚本都不会出现。

我们随便抓一个 `S01syslogd` 出来看，就明白这套脚本的标准范式长什么样：

```bash
#!/bin/sh
DAEMON="syslogd"
PIDFILE="/var/run/$DAEMON.pid"
[ -r "/etc/default/$DAEMON" ] && . "/etc/default/$DAEMON"

start() {
	printf 'Starting %s: ' "$DAEMON"
	start-stop-daemon --start --background --make-pidfile \
		--pidfile "$PIDFILE" --exec "/sbin/$DAEMON" -- -n $SYSLOGD_ARGS
	# ... 打印 OK / FAIL
}
stop()  { start-stop-daemon --stop --pidfile "$PIDFILE" --exec "/sbin/$DAEMON"; ... }
case "$1" in start|stop|restart) "$1";; *) echo "Usage: ...";; esac
```

记住这个 `start/stop/restart` 加 `start-stop-daemon` 的模板——后面自己写 `S99myapp` 的时候照着抄就行，不用重新发明轮子。

### getty：登录提示符是怎么来的

现在我们回头看那行 `# GENERIC_SERIAL` 注释。Buildroot 的 busybox 包在安装阶段有这么一段（`package/busybox/busybox.mk`）：

```makefile
ifeq ($(BR2_TARGET_GENERIC_GETTY),y)
define BUSYBOX_SET_GETTY
	$(SED) '/# GENERIC_SERIAL$$/s~^.*#~$(SYSTEM_GETTY_PORT)::respawn:/sbin/getty -L $(SYSTEM_GETTY_OPTIONS) $(SYSTEM_GETTY_PORT) $(SYSTEM_GETTY_BAUDRATE) $(SYSTEM_GETTY_TERM) #~' \
		$(TARGET_DIR)/etc/inittab
endef
else
# 没开 getty 就把它还原成注释
endif
```

意思是用 sed 把那行带 `# GENERIC_SERIAL` 标记的整行替换掉，注入 `SYSTEM_GETTY_PORT` 等配置。对照我们的 defconfig（`PORT="ttymxc0"`、`BAUDRATE_115200`，`TERM` 默认 `vt100`），落到板子上的 inittab 里那行会变成：

```
ttymxc0::respawn:/sbin/getty -L ttymxc0 115200 vt100 #
```

`respawn` 表示进程一退出就自动重启——所以你登录、退出、再登录，getty 会一直守在 `ttymxc0` 上不离不弃。这就是为什么你每次重启板子，串口都会准时冒出那个 `buildroot login:` 提示符的底层原因。

这里有个 action 的区别值得拎出来：`respawn` 是"挂了就拉起来，不问"，`askfirst` 是"拉起来前先按回车"。手搓教程里我们用 `console::askfirst:-/bin/sh` 直接进 sh，是为了调试方便；Buildroot 默认走 `getty` 加真正的 login 流程（带密码、带 securetty 校验），更接近生产形态。这两种风格没有对错，只是定位不同。

## skeleton 包：铺好目录骨架

刚才 inittab 里 `mount -a`、`mkdir /dev/pts` 这些命令能跑，前提是 rootfs 里已经有 `/etc/fstab`、`/dev`、`/proc` 这些目录。这是谁铺的？答案是 **skeleton 包**。

选 `BR2_INIT_BUSYBOX` 时（用默认 skeleton），Buildroot select 了 `BR2_PACKAGE_SKELETON_INIT_SYSV`。这个包的源在 `package/skeleton-init-sysv/skeleton/`，构建时整个 rsync 到 target 目录。我们直接看它提供的 fstab（原样落到 rootfs）：

```bash
# package/skeleton-init-sysv/skeleton/etc/fstab —— 原样落到 rootfs
# <file system> <mount pt> <type> <options>                              <dump> <pass>
/dev/root       /           ext2  rw,noauto                              0      1
proc            /proc       proc  defaults                               0      0
devpts          /dev/pts    devpts defaults,gid=5,mode=620,ptmxmode=0666 0      0
tmpfs           /dev/shm    tmpfs mode=1777                              0      0
tmpfs           /tmp        tmpfs mode=1777                              0      0
tmpfs           /run        tmpfs mode=0755,nosuid,nodev                 0      0
sysfs           /sys        sysfs defaults                               0      0
```

对比一下手搓教程里我们手写的那三行 fstab（只有 proc/devpts/tmpfs），Buildroot 这份明显完整得多：`/dev/shm`、`/run`、`/sys` 全配好，连 `/dev/root` 那行 `noauto` 都有——它是专门给 inittab 里那句 `mount -o remount,rw /` 用的。所以 inittab 里的 `mount -a` 一跑，这些虚拟文件系统就齐刷刷挂上了，你什么都不用管。

除了 fstab，skeleton-init-sysv 还建了 `/dev/pts`、`/dev/shm`、`/dev/log`（syslog 的套接字占位）这些目录，以及一整棵 `/var` 树（`/var/log`、`/var/run`、`/var/lock`、`/var/cache`、`/var/spool`、`/var/tmp` 等，多数是指向 `/tmp` 或 `/run` 的软链，比如 `/var/log -> /tmp`、`/var/run -> /run`、`/var/lock -> /run/lock`）。这套目录结构是按 SysV init 的老规矩铺的，你拿到手的 rootfs 一开始就是个"五脏俱全"的样子。

### 为什么 post-build 还要补 `/home`

skeleton-init-sysv 依赖 `skeleton-init-common`，后者提供基础目录和 `/etc/passwd` 等配置。我们看一眼 passwd（来自 `system/skeleton/etc/passwd`）：

```
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/bin/false
...
nobody:x:65534:65534:nobody:/home:/bin/false
```

root 的家目录是 `/root`（skeleton 建了这个目录），但**整套 skeleton 里根本没有 `/home`**——因为 Buildroot 默认只用 root 账号、不建普通用户，自然不需要 `/home`。这本身没毛病。

可 IMX-Forge 这边有自己的要求：`varified_rootfs_ok.sh` 校验闸门期望 rootfs 里有 `/home`，而且后续上 Qt 应用、CFBox 时大概率会加普通用户。所以 post-build 脚本里专门补了这一刀：

```bash
# rootfs/buildroot/post-build.sh
# ② 补建 buildroot skeleton 不保证、但项目 varified_rootfs_ok.sh 期望的目录
#    (buildroot 用 root/ 作用户家,不建 home/;此处补齐)
mkdir -p "${TARGET_DIR}/home"
```

这是个很典型的场景——skeleton 本身够用，但项目有更高要求。能用 post-build 一行 `mkdir` 搞定的，就不必去折腾自定义 skeleton，杀鸡焉用牛刀。

::: tip 踩坑预警：root 登录被拒，多半是 securetty
post-build.sh 里还有一段不起眼但救命的逻辑：

```bash
# ②-bis /etc/securetty:项目 busybox.config 带 CONFIG_FEATURE_SECURETTY=y,login 要求
#     该文件列出允许 root 登录的 tty;buildroot skeleton 不建它 → root 登录被全拒。
if [[ ! -f "${TARGET_DIR}/etc/securetty" ]]; then
    printf '%s\n' console tty1 tty2 tty3 tty4 tty5 tty6 \
        ttyS0 ttyS1 ttymxc0 ttymxc1 ttymxc2 ttyAMA0 ttyUSB0 \
        > "${TARGET_DIR}/etc/securetty"
fi
```

我们导出的 busybox.config 开了 `CONFIG_FEATURE_SECURETTY=y`，于是 BusyBox 的 `login` 会检查 `/etc/securetty`，只有列在里面的 tty 才允许 root 登录。而 Buildroot skeleton **根本不生成这个文件**。结果就是：getty 正常冒提示符，你输完 root 回车，直接被拒，串口上还没有任何直观报错，就一个寂寞的 login 重新弹出来。这一点真的能坑人半天——你会以为密码错了、以为串口不对、以为 rootfs 没起来，就是想不到是缺一个文件。把 `ttymxc0` 写进 securetty 才算解决。这种"Buildroot 默认配置和我们的 busybox.config 没完全咬合"的缝隙，正是 post-build 要填的，也是我反复强调"别以为选了 init 就万事大吉"的原因。
:::

## 加自启服务的两种姿势

假设我们现在要让板子开机自动跑一个 `/usr/bin/myapp`。Buildroot 里有两条路，正好对应你处在哪一章、哪种心智模型。

### 姿势一：overlay 塞一个 `S99myapp`（第 06 章风格）

最轻、最直接的玩法。在 overlay 树里放一个可执行脚本就行：

```
rootfs/buildroot/overlay/
└── etc/init.d/S99myapp
```

内容照着前面 `S01syslogd` 的范式写，基本上是照抄改名字：

```bash
#!/bin/sh
DAEMON="myapp"
PIDFILE="/var/run/$DAEMON.pid"

start() {
	printf 'Starting %s: ' "$DAEMON"
	start-stop-daemon --start -b -m --pidfile "$PIDFILE" --exec /usr/bin/$DAEMON
	echo "OK"
}
stop() {
	start-stop-daemon --stop --pidfile "$PIDFILE"
	rm -f "$PIDFILE"
}
case "$1" in start) start;; stop) stop;; restart) stop; start;; esac
```

别忘了 `chmod +x`，overlay 是保留权限位的，忘了加可执行位脚本就根本不会跑。构建时 Buildroot 会把 overlay 整树 cp 到 target，`S99` 排在所有内置脚本最后，开机自然就跑起来了。

这套姿势适合的场景是：服务就这一个板子用、没有独立的源码包、或者你只是临时验证一下。优点是零侵入，改完 overlay 重新 `make` 就生效；缺点也很明显——服务和它的二进制"分家"了，二进制可能也是你手塞 overlay 的，整件事脱离了 Buildroot 的包管理，重建可复现性会打折扣。临时玩玩没问题，长期维护别这么干。

### 姿势二：package 里写 `INSTALL_INIT_SYSV`（第 07 章风格）

如果你把这个服务做成了正经的 Buildroot package（`myapp.mk` 加 `Config.in`），那就该走包的 init 钩子。手册（《adding packages》一节）里说得很清楚：

> `LIBFOO_INSTALL_INIT_SYSV`、`LIBFOO_INSTALL_INIT_OPENRC`、`LIBFOO_INSTALL_INIT_SYSTEMD` 列出安装 init 脚本的动作。这些命令**只有在对应 init 系统被选中时才会执行**（比如选了 systemd 就只跑 `INSTALL_INIT_SYSTEMD`）。

也就是说，你在 `.mk` 里这么写：

```makefile
# package/myapp/myapp.mk
define MYAPP_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 package/myapp/S99myapp \
		$(TARGET_DIR)/etc/init.d/S99myapp
endef
```

就这样，**只 define、什么都不用挂**。`generic-package` 基础设施在 target-install 阶段（`package/pkg-generic.mk` 的 `.stamp_target_installed` 规则里）会按当前选中的 init 系统自动展开：

```makefile
# package/pkg-generic.mk —— 基础设施自动调用,作者无需手动注册
$(if $(BR2_INIT_SYSTEMD),  $($(PKG)_INSTALL_INIT_SYSTEMD))
$(if $(BR2_INIT_SYSV)$(BR2_INIT_BUSYBOX),  $($(PKG)_INSTALL_INIT_SYSV))
$(if $(BR2_INIT_OPENRC),   $(or $($(PKG)_INSTALL_INIT_OPENRC), $($(PKG)_INSTALL_INIT_SYSV)))
```

只有当 rootfs 的 init 是 BusyBox 或 sysvinit（sysv 系）时，`INSTALL_INIT_SYSV` 这个宏才会被展开；哪天你把整个项目切到 systemd，它会自动换成跑 `INSTALL_INIT_SYSTEMD`（装 `.service` unit），你一行 package 都不用改。这正是基础设施替你做的体面事。

也正因为是基础设施按 init 系统门控的，**千万别手滑去写 `MYAPP_POST_INSTALL_TARGET_HOOKS += MYAPP_INSTALL_INIT_SYSV`**。那样会让脚本在 systemd/openrc 下也被无条件安装、绕过门控，而且在 sysv 系下还会和基础设施的自动调用重复装两遍，得不偿失。该放手让基础设施干的事，就别自己抢。

这套姿势适合的场景是：服务有独立源码、要在多个项目间复用、或者想让它"init 系统无关"。这才是 Buildroot 包管理的正道。两种姿势不冲突，按服务的重要程度选就行——临时验证走 overlay，长期维护做成 package。

## 什么时候才该上 systemd

聊到这你可能会问：既然 systemd 这么强，IMX-Forge 为啥不上？官方手册对 systemd 的态度其实很坦诚：

> systemd brings a fairly big number of large dependencies: dbus, udev and more. It is useful on relatively complex embedded systems, for example the ones requiring D-Bus and services communicating between each other.

从 `system/Config.in` 的依赖也能直观看出 systemd 的"重量级"：它**强制要求 glibc**（`BR2_TOOLCHAIN_USES_GLIBC`）、内核 headers `>= 5.4`、目标/主机 GCC `>= 8`，注释里还"强烈建议内核 >= 5.7"。我们 IMX-Forge 用的是 Arm GNU Toolchain 15.2 加 glibc，工具链这关倒是过得去，但镜像代价是实打实的。

代价有几头。先是体积，systemd 加 dbus 加 udev 一套下来，rootfs 轻易多出十几兆甚至更多，对我们那种最小 rootfs（CI 默认那套，约 15 分钟构建完）是不小的膨胀。再者是依赖树，systemd 一进来，dbus 就成了硬依赖（手册专门有一节讲 systemd 必须配 dbus 或 dbus-broker），`/dev` 管理也随之被 systemd 自带的 udev 接管，不再是独立的 eudev——你原来那套 eudev 规则文件得重新对接。最后是服务启用方式整个变了，手册里提到，选 systemd 时 Buildroot 会在镜像构建末尾**自动执行 `systemctl preset-all`**，把所有服务的 unit 按 preset 规则启用；你想阻止某个服务被自动启用，得往 rootfs 里塞 preset 文件。这套机制比 `Sxx` 编号复杂得多，调试成本明显更高。

所以 IMX-Forge 的取舍很清楚：**目前没有哪个需求真需要 systemd**。我们的服务都是"开机拉起来就完事"的类型，没有 socket 激活、没有服务间 D-Bus 通信、不需要 cgroup 分组管理。BusyBox init 加 `Sxx` 脚本足够清晰、足够小、足够可复现，何必请个大神来供着。等到哪天真要上复杂的容器编排、或者某个上游组件强依赖 systemd 的特性，再考虑切——那时候本章讲的 `INSTALL_INIT_SYSTEMD` 钩子正好派上用场，package 层面是平滑的，主要工作在 defconfig 和镜像瘦身。

## 对照：手搓 inittab 时你干的事，Buildroot 干了哪些

最后我们拿手搓教程的 [03_inittab 与 init](../rootfs/03_inittab_init.md) 做个对照，你会更直观地感受到 Buildroot 到底替你省了多少事。

| 工作 | 手搓时代（03 章） | Buildroot 时代（本章） |
|------|------------------|----------------------|
| `/etc/inittab` | 手写 6 行（sysinit 调 rcS、askfirst 起壳、shutdown 卸载） | **自动生成**（`package/busybox/inittab`），含完整 sysinit 挂载链 + getty + rcK |
| getty / 串口登录 | 用 `console::askfirst:-/bin/sh` 直接进 sh，不走 login | inittab 占位行按 `BR2_TARGET_GENERIC_GETTY_PORT` sed 注入 `ttymxc0::respawn:/sbin/getty ...`，走真 login |
| `rcS` | 手写 `mount -a` + `mkdir /dev/pts` + `mdev -s` | inittab 顶层已 `mount -a`、建 `/dev/pts`；`rcS` 只负责按编号跑 `Sxx`（initscripts 包） |
| `/etc/fstab` | 手写 3 行（proc/devpts/tmpfs） | **自动生成** 7 行完整版（skeleton-init-sysv，含 `/dev/shm` `/run` `/sys`） |
| 设备节点 | rcS 里 `mdev -s`，或手 `mknod console/null` | eudev 动态管理（`BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV`），init 无关 |
| `/var` 目录树 | 自己 mkdir | skeleton-init-sysv 铺好 |
| 开机脚本编号 | 没有 `Sxx` 体系，全堆 rcS | 天然 `S01syslogd` `S02klogd` `S10mdev` `S11modules` ... |

数下来，真正需要你**亲手定制**的就剩 Buildroot 默认没覆盖、或者和项目配置不咬合的那么几处，全在 `post-build.sh` 里：一是 `linuxrc` 软链（`ln -sf bin/busybox linuxrc`，给 NFS root 和老式 `init=/linuxrc` 一个兼容入口，skeleton 默认不建）；二是 `/home` 目录（skeleton 只建 `/root`，项目校验和未来普通用户要 `/home`，`mkdir -p` 补上）；三是 `/etc/securetty`（项目 busybox.config 开了 `FEATURE_SECURETTY` 而 skeleton 不生成，不补就 root 登录被拒）；四是 SDMA 固件、CJK 字体这类运行时资源，post-build 按需下载塞进去。

一句话总结：**Buildroot 接管了"让系统能启动"的全部底座，你只管"让这台板子能干活"的增量。** 这种分工，正是我们放弃手搓、迁到 Buildroot 的核心理由。

## 下一步

init 链路理顺了，你的 rootfs 现在已经能开机、能登录、能按编号跑服务，一条龙打通。但事情到这里还没完——如果每改一行代码都要全量重编，开发节奏分分钟被拖死。下一章我们就来看 Buildroot 怎么靠 ccache 和增量重建把迭代速度拉起来：[第 09 章：ccache 与重建策略](09_ccache_rebuild.md)。
