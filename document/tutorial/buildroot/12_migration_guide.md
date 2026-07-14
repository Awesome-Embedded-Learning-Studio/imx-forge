# 手搓→Buildroot 迁移对照

::: info 本节你将学到
- 把旧版 IMX-Forge 的"手搓 rootfs"全流程（`build-busybox.sh` + `merge_overlay_rootfs.sh` + `third_party_install/*.sh` + `varified_rootfs_ok.sh`）逐项对应到 Buildroot 的新做法
- 哪些工作 Buildroot 的 skeleton + packages 直接接管了，哪些还得靠 `post-build.sh` 和 `BR2_ROOTFS_OVERLAY` 补齐
- Qt6 从手工 `qt-compile-pipeline` 迁到 fragment merge 后，构建命令、配置文件、模块清单分别怎么变
- 我们这次迁移真实踩过的五个坑（`INET_RPC`、securetty、shadertools 拉取、br2-external 变量大小写、NFS bind-mount 重启），免得你照着旧笔记再踩一遍
:::

::: tip 前置知识 · 环境
- 这一章是"对照"性质，建议先读完 [01 工作原理](01_how_buildroot_works.md) 和 [02 第一次构建](02_first_build.md)，至少知道 `imx6ull_aes_defconfig`、`post-build.sh`、`overlay/` 这三件套各自管什么
- 如果你没用过旧版 IMX-Forge 的手搓 rootfs，可以把这章当"为什么我们要迁"的复盘来读；如果你正在从旧分支升级过来，那它就是你的迁移清单
- 手边能打开 `rootfs/buildroot/` 这个 br2-external tree，对照 `configs/imx6ull_aes_defconfig`、`post-build.sh`、`fragments/` 看会更顺
:::

老实说，这一章本来不在我最初的计划里——Buildroot 那 11 章一路写下来，从工作原理讲到 Qt6 集成，逻辑上已经闭环了。但写到一半我意识到一个问题：IMX-Forge 不是从零开始的全新项目，它有一整套跑通了的"手搓 rootfs"历史。PR #89（`a61b8287`）那句"手搓 rootfs 准备下架"说得很轻巧，可对一个已经在旧分支上攒了一堆自定义配置、自定义脚本、自定义 Qt 编译流水线的使用者来说，"下架"两个字背后是一整张迁移清单。如果你就是从旧版升级过来的，光知道"现在用 Buildroot 了"没用，你得知道你原来干的每一件事，现在分别去哪儿干了。

所以这一章我们就来做这件事：把旧手搓 rootfs 的完整构建链拆开，一项一项对应到 Buildroot 的新机制上。我尽量不空谈，每一项都给出"旧脚本在哪、新配置在哪、为什么这么换"。如果你对照着改自己的分支，应该能做到逐条核对、不漏东西。

## 先看全局：一张对照表

在展开细节之前，我们先把整张迁移地图铺出来。旧版手搓 rootfs 的构建链是这么几块拼起来的：`scripts/build_helper/build-busybox.sh` 负责编 BusyBox；`scripts/merge_overlay_rootfs.sh` 把 overlay 合进 `rootfs/nfs`；`scripts/varified_rootfs_ok.sh` 既负责"构造"（建目录骨架、写 `fstab`/`inittab`/`rcS`），又负责"校验"，构造时还会扫一遍 `scripts/third_party_install/*.sh`，把 `install_alsa.sh`、`install_qt_with_compile.sh`、`install_firmwares.sh`、`install_fonts.sh`、`install_libc.sh` 按字母序全跑一遍，手工交叉编译一堆第三方库。这套东西能跑，但每加一个组件就得新写一个 `install_xxx.sh`，维护成本越来越高。

Buildroot 接管后，这张链路重新分工如下：

| 旧做法（手搓） | 新做法（Buildroot） | 接管者 |
|---------------|-------------------|--------|
| `build-busybox.sh` 手编 BusyBox | `BR2_PACKAGE_BUSYBOX` + `fragments/busybox.config` | buildroot busybox 包 |
| `merge_overlay_rootfs.sh` 合 overlay | `BR2_ROOTFS_OVERLAY` 指向 `overlay/` | buildroot 构建中自动 rsync |
| 建目录骨架（bin/dev/etc/…） | skeleton-init-sysv / skeleton-init-busybox | buildroot skeleton |
| 写 `/etc/fstab`、`/etc/inittab`、`/etc/init.d/rcS` | busybox inittab 模板 + initscripts 包 | buildroot 自动生成 |
| `varified_rootfs_ok.sh` 的"构造"职责 | 上述 skeleton + packages + `post-build.sh` | buildroot + post-build |
| `install_alsa.sh` 手工交叉编译 alsa | `BR2_PACKAGE_ALSA_LIB` / `ALSA_UTILS` 等 | buildroot alsa 包 |
| `qt-compile-pipeline` + `qt.conf` 八模块 | `fragments/qt6.config`（buildroot 原生 Qt6 6.9.1） | buildroot qt6 包 + fragment |
| `install_firmwares.sh`（SDMA 固件） | `post-build.sh` ③ 按需下载 | post-build 脚本 |
| `install_fonts.sh`（DejaVu/CJK） | buildroot `dejavu` 包 + `post-build.sh` ③-bis | buildroot 包 + post-build |
| `varified_rootfs_ok.sh` 的"校验"职责 | `post-build.sh` ④ 调它当闸门 | 仍是 `varified_rootfs_ok.sh` |
| 镜像 `mke2fs` 现打 | 仍由 `build_imx6ull_image.sh` 打，buildroot 只产 `target/` | image builder |

这张表先留个印象，接下来我们逐块展开。

## BusyBox：从自己 `make` 到交给 defconfig

旧版编 BusyBox，走的是 `scripts/build_helper/build-busybox.sh`：自己 `make menuconfig` 存一份 `.config`、自己设 `ARCH=arm` 和 `CROSS_COMPILE=arm-none-linux-gnueabihf-`、自己 `make && make install`，产出的 `_install` 目录再想办法塞进 rootfs。这条链路最大的问题是 BusyBox 的 `.config` 和 rootfs 构建是脱节的——你改了 BusyBox 的 applet，得记得重新跑一遍 busybox 脚本，再重新合并 rootfs，少一步就对不上。

迁到 Buildroot 之后，BusyBox 变成了一个普通的包，在 `imx6ull_aes_defconfig` 里就两行：

```
BR2_PACKAGE_BUSYBOX=y
BR2_PACKAGE_BUSYBOX_CONFIG="$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config"
```

第一行把 BusyBox 选进来，第二行把它的配置文件指向我们自己的 `fragments/busybox.config`。这里有个细节值得多说一句：Buildroot 自带的 BusyBox 默认配置是精简版，大概 562 个 applet；而我们 `fragments/busybox.config` 是项目导出的完整配置，877 个 applet 全功能，跟旧脚本编出来的一致。为什么坚持用完整配置而不是 Buildroot 的精简默认？因为嵌入式板上你永远不知道哪个 applet 哪天就用到了，与其到时候发现 `xxd`、`ftpd` 这种被裁掉了再去补编，不如一开始就全开，反正 BusyBox 本身就不大。

另外这个 fragment 还顺手关掉了一个 x86-only 的 SHA 硬加速选项（对齐旧脚本里的 `fix_arm_config` 那步），那个选项在 ARM 上编不过，留着只会报错。Buildroot 在引用 `BR2_PACKAGE_BUSYBOX_CONFIG` 之后会跑 `make oldconfig` 自动适配 BusyBox 版本差异，所以即便 Buildroot 2026.02 自带的 BusyBox 版本和你导出配置时的版本不完全一致，也能平滑对上。

⚠️ **注意**：`$(BR2_EXTERNAL_imxforge_PATH)` 这个变量名里的 `imxforge` 必须**全小写**，且必须和 `external.desc` 里的 `name:` 字段一字不差。写成 `BR2_EXTERNAL_IMXFORGE_PATH`（大写）Buildroot 是解析不出来的——别问我是怎么知道的，这个坑我在迁移初期踩过，配置文件路径找不到，BusyBox 用了 Buildroot 的精简默认，编出来的 rootfs 少了一大半命令。真正的坑往往不在配置内容，而在这种大小写细节上。

## 目录骨架、inittab、fstab：merge 脚本退场，skeleton 接管

旧版最"手工"的一块，其实是 rootfs 的目录骨架和启动配置。`varified_rootfs_ok.sh` 当年身兼两职：它一边校验完整性，一边"构造"——把 `bin dev etc lib mnt proc root sbin sys tmp usr home` 这些目录建出来，手写 `/etc/fstab`（proc、devpts、tmpfs 三行），手写 `/etc/inittab`（sysinit 调 rcS、askfirst 起壳、shutdown 卸载），手写 `/etc/init.d/rcS`（`mount -a` + `mkdir /dev/pts` + `mdev -s`）。这套东西能跑通，但每次重建 rootfs 都得重跑一遍，而且手写的 inittab/fstab 是"刚好够用"的最小版本，少很多标准挂载点。

Buildroot 这边把这一摊全接管了。它的 skeleton 体系（`skeleton-init-sysv`、`skeleton-init-busybox`、`skeleton-init-common`）负责把完整的目录树铺好，BusyBox 的 inittab 由 `package/busybox/inittab` 这个模板自动生成——含完整的 sysinit 挂载链、getty、rcK，比我们手写那 6 行完善得多。`/etc/fstab` 也是 skeleton 自动生成的 7 行完整版，多了 `/dev/shm`、`/run`、`/sys` 这些标准挂载点。开机脚本则走天然的 `Sxx` 编号体系（`S01syslogd`、`S02klogd`、`S10mdev`、`S11modules`……），由 initscripts 包按编号依次跑，比旧版"全堆 rcS 里"清晰太多。

这一段在 [08 Init 系统](08_init_system.md) 那章的"对照"小节里已经详细比过，这里就不重复展开了。结论是：**凡是和"让系统能启动"有关的底座，Buildroot 全包了**。你需要做的只剩 Buildroot 默认没覆盖、或者和我们项目配置咬合不上的几处——这些全收在 `post-build.sh` 里，我们后面专门讲。

## Overlay 合并：从 rsync 脚本到 `BR2_ROOTFS_OVERLAY`

旧版往 rootfs 里塞自定义内容，靠的是 `merge_overlay_rootfs.sh`，它把 `rootfs/overlay/<name>/` 下的内容 rsync 进目标 rootfs（默认 `rootfs/nfs`）。这个脚本本身不复杂，但它的存在意味着"合并"是一个独立的、容易漏掉的步骤——你得记得在编完 BusyBox、装完第三方库之后，再单独跑一次合并，否则 rootfs 里没有你的自定义文件。

Buildroot 把"合并 overlay"做成了一个原生的配置项：

```
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"
```

设上这一行之后，Buildroot 在构建过程中会自动把这个目录的内容叠加到 rootfs target（同名文件覆盖），不需要你单独跑任何脚本。机制上它和你手写 rsync 是一回事，但"时机"对了——它在 buildroot 打包 rootfs 之前、所有包装好之后执行，所以你的自定义文件一定能覆盖包安装的默认文件，也不会被后续步骤冲掉。

目前我们的 `rootfs/buildroot/overlay/` 是空的（只放了 README），自定义内容主要走 post-build 脚本动态生成。但这个目录预留着，以后你要加固定的自定义配置（比如改过的 `etc/` 文件、板端应用脚本），直接往里丢就行，不用再写任何合并逻辑。另外,旧版的 `rootfs/overlay/rootfs/` 那个目录从来没启用过（`.gitignore` 里 `*` 全忽略了），现在 `BR2_ROOTFS_OVERLAY` 指向的是 br2-external tree 里的新 `overlay/`，别往旧路径放东西。

## ALSA：从手工交叉编译到 Buildroot 包

wm8960 音频那一摊（第 12 章驱动教程），旧版 rootfs 要装 alsa-lib 和 alsa-utils 是手工干的：`scripts/third_party_install/install_alsa.sh` 自己下载 alsa-lib 源码、自己配 `--host=arm-none-linux-gnueabihf`、自己 `make && make install` 到 rootfs，alsa-utils 同理。手工交叉编译音频库的痛苦在于依赖管理——alsa-utils 依赖 alsa-lib，版本要对齐，sysroot 要指对，稍微一个参数错就是一串编译错误。

迁到 Buildroot 之后，alsa-lib 和 alsa-utils 变成了开箱即用的包，在 defconfig 里勾选就行：

```
BR2_PACKAGE_ALSA_LIB=y
BR2_PACKAGE_ALSA_LIB_MIXER=y
BR2_PACKAGE_ALSA_LIB_PCM=y
BR2_PACKAGE_ALSA_LIB_UCM=y
BR2_PACKAGE_ALSA_UTILS=y
BR2_PACKAGE_ALSA_UTILS_APLAY=y        # aplay + arecord（同一二进制）
BR2_PACKAGE_ALSA_UTILS_AMIXER=y
BR2_PACKAGE_ALSA_UTILS_ALSACTL=y
BR2_PACKAGE_ALSA_UTILS_ALSAUCM=y
BR2_PACKAGE_ALSA_UTILS_SPEAKER_TEST=y
```

这一串把 alsa-lib 的 mixer/pcm/ucm 子项和 alsa-utils 的 aplay/amixer/alsactl/alsaucm/speaker-test 全选上了，正好覆盖 wm8960 调试需要的全部工具。依赖关系 Buildroot 自己处理（alsa-utils 自动依赖 alsa-lib），版本由 Buildroot 2026.02 统一管理，你再也不用操心 sysroot 指哪、`--host` 写什么。这就是从"手工交叉编译"迁到"包管理"最大的收益——把依赖这件事交还给构建系统。

## Qt6：从 qt-compile-pipeline 到 fragment merge

Qt6 是整个迁移里最重的一块，也是收益最大的一块。旧版的 Qt6 编译走的是一套自研的 `qt-compile-pipeline`：靠一堆 `qt.conf`、`host.conf`、`target.conf`、`third_party.conf` 配置文件驱动，手工指定八个模块（qtbase、declarative、multimedia、charts、shadertools、serialport、virtualkeyboard、core5compat），host 和 target 分两轮编译，mkspecs、sysroot、`-device` 参数全得自己捋。这套流水线能编出 Qt6，但它本质上是在 Buildroot 之外另造了一套构建系统，维护成本极高，换个 Qt 版本就得重调一遍。

迁到 Buildroot 之后，Qt6 变成了一个可选的 fragment。Buildroot 2026.02 原生带的 Qt6 正好是 **6.9.1**，和我们旧 pipeline 编的版本一致，所以产物层面是平滑替换，不会有版本断层。配置写在 `fragments/qt6.config` 里：

```
BR2_PACKAGE_QT6=y
BR2_PACKAGE_QT6BASE=y
BR2_PACKAGE_QT6BASE_GUI=y
BR2_PACKAGE_QT6BASE_WIDGETS=y
BR2_PACKAGE_QT6BASE_LINUXFB=y        # FEATURE_linuxfb=ON（裸 framebuffer）
BR2_PACKAGE_QT6BASE_TSLIB=y          # FEATURE_tslib=ON（触摸校准）
...
BR2_PACKAGE_QT6DECLARATIVE=y        # QML/QtQuick
BR2_PACKAGE_QT6MULTIMEDIA=y         # 多媒体（FFmpeg + ALSA 后端，wm8960）
BR2_PACKAGE_QT6CHARTS=y
BR2_PACKAGE_QT6SHADERTOOLS=y        # qt6declarative 依赖
BR2_PACKAGE_QT6SERIALPORT=y
BR2_PACKAGE_QT6VIRTUALKEYBOARD=y
BR2_PACKAGE_QT6CORE5COMPAT=y
```

这八个子模块和旧 `qt.conf` 里的 `QT_MODULES` 清单是一一对应的，一个不少。i.MX6ULL 没 GPU，所以平台选项走 linuxfb + tslib，关掉 XCB/EGLFS/OpenGL，这跟旧 `target.conf` 的取向完全一致。tslib 和 fontconfig 作为依赖被 Buildroot 自动拉进来（`BR2_PACKAGE_TSLIB`、`BR2_PACKAGE_FONTCONFIG`、`BR2_PACKAGE_DEJAVU`），不用你手管。

触发方式上，Qt6 全模块编译要 2 到 4 小时，不能默认开。所以 CI 默认构建最小 rootfs（不含 Qt6，约 15 分钟），Qt6 由 `compile-support-3rd-party` 这个 label 触发；本地则用 `build-buildroot.sh --with-qt6` 或设 `BUILDROOT_QT6=1`。底层原理是 `build-buildroot.sh` 用 Buildroot 自带的 `merge_config.sh -m` 把 `qt6.config` 合进 `.config`，再跑 `olddefconfig` 重解依赖。这套 fragment 机制在 [04 配置体系](04_kconfig_fragments.md) 那章详细讲过，这里就不展开了。

## 固件与字体：install 脚本收进 post-build

旧版装 SDMA 固件和字体，分别靠 `install_firmwares.sh` 和 `install_fonts.sh`，由 `varified_rootfs_ok.sh` 扫 `third_party_install/` 时统一调用。这俩脚本干的是"下载二进制资源、塞进 rootfs 指定路径"的活，逻辑简单但同样是个独立步骤。

迁到 Buildroot 之后，这类"运行时资源"的安装收进了 `post-build.sh`。先说固件：i.MX6ULL 的 SDMA 驱动（音频 DMA 等会用到）运行时要加载 `sdma-imx6q.bin`，`post-build.sh` 第 ③ 段从 armbian firmware 仓库下载它，缓存到 `out/.firmware-cache` 做幂等，再放进 `lib/firmware/imx/sdma/`。下载失败只告警、不中止构建——因为这是网络问题，不该卡住 rootfs 构建，SDMA 驱动顶多报个缺固件的错，不影响 rootfs 完整性。

字体稍微讲究一点，分两路。西文和基础符号的 DejaVu 直接用 Buildroot 的 `dejavu` 包（随 Qt6 fragment 一起选上）；中文字体 Noto Sans CJK 和表情 Noto Color Emoji 则由 `post-build.sh` 第 ③-bis 段按需下载。这里有个判断逻辑值得注意：CJK/Emoji 字体只在 rootfs 实际包含 Qt6 时才下载（用 `libQt6Core.so` 是否存在来探测），因为最小 rootfs 没 GUI、不需要字体，省下来将近 30MB。Noto Sans CJK 那个发布包是个 zip，里面有七个不同字重的 ttc，我们只取 Regular 那个省体积，约 18MB。

这样一收口，所有"下载二进制塞 rootfs"的逻辑都集中在 `post-build.sh` 一个文件里，按段落编号（① linuxrc、② 目录/securetty、③ 固件、③-bis 字体、④ 校验）排开，比散在 `third_party_install/` 五六个脚本里好查太多了。

## 校验闸门：varified 脚本从"又构造又校验"瘦身为"只校验"

这一项是整个迁移里设计上最干净的一刀。旧的 `varified_rootfs_ok.sh` 名字叫"校验"，实际干了"构造 + 校验 + 调第三方安装"三件事，职责严重过载——这也埋过雷（Issue #76 就是因为构造和校验混在一起，残缺 rootfs 差点流到镜像里）。Buildroot 接管后，构造职责彻底移交：目录骨架归 skeleton，配置文件归包，第三方库归 Buildroot package，运行时资源归 post-build。`varified_rootfs_ok.sh` 原地瘦身为**纯校验闸门**。

它现在只做三件事：检查目录结构（`bin/dev/etc/lib/...` 一个都不能少）、检查关键配置文件（`etc/fstab`、`etc/init.d/rcS`、`etc/inittab`）、以及当 rootfs 含 Qt 时校验 Qt 产物（`libQt6Core.so` 在、`plugins/platforms/` 非空）。调用时机也变了——它不再独立跑，而是由 `post-build.sh` 第 ④ 段在 buildroot 构建过程中、rootfs 打包前调用，任一致命检查不过就直接非零退出，中止整个 buildroot make。这才是"闸门"该有的样子：在产物成型的那一刻拦住，绝不让残缺 rootfs 往下走。

## 镜像组装：Buildroot 只产 target/，mke2fs 交给 image builder

最后说一个容易被忽略的分工变化。你可能注意到，我们的 defconfig 里**没有** `BR2_TARGET_UBOOT`、也**没有** `BR2_LINUX_KERNEL`——也就是说 Buildroot 不编内核、不编 U-Boot。这俩仍然走 `scripts/build_helper/` 那套外部双轨构建，产物落在 `out/release-latest/{uboot,linux}/`。Buildroot 在 IMX-Forge 里只管 Stage 3+4，即用户空间 rootfs。

进一步，Buildroot 连 rootfs 的文件系统镜像都不打。注释里写得很清楚：Buildroot 自带的 ext2/ext4 镜像输出是固定尺寸的，加了 Qt6 之后得不断手调大小，很烦；而且最终的 SD/eMMC 镜像是由 `build_imx6ull_image.sh` 从 `out/release-latest/rootfs/` 用 `mke2fs -d` 按实际内容现打的，尺寸动态、更灵活。所以 Buildroot 这边只产 `output/target/` 这棵目录树，`build-buildroot.sh` 的 Step 3 再用 `rsync -a --delete` 把它同步到 `out/release-latest/rootfs/`，供镜像打包脚本消费；NFS root 则直接挂这个目录。

这个"各管一段、最后拼装"的分工，比让 Buildroot 一把梭去编内核、编 bootloader、打镜像要干净得多——你想单独替换某一块（比如换个内核版本、换个 rootfs 配置），互不干扰。

## 迁移踩过的坑

最后把这次迁移真实踩过的坑列一下，这大概是这一章最值钱的部分——如果你正打算照着迁，照这张清单先排一遍雷，能省下大把时间。

**坑一：`INET_RPC` 必须显式关掉。** 现代 glibc 工具链已经不内置 RPC（sunrpc）支持了，而 Buildroot 的某些包默认会去探这个能力。defconfig 里有一行 `# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set`，这一行绝对不能少。少了的症状是某些网络相关的包在链接时报 `undefined reference to ... xdr ...` 之类的错。这是因为 glibc 早就把 RPC 拆出去了（变成 libtirpc），工具链特性声明里必须如实反映"没有 RPC"，Buildroot 才会去拉 libtirpc 来补。这个在 [03 External Toolchain](03_external_toolchain.md) 里详细讲过。

**坑二：`/etc/securetty` 不补，root 登录被全拒。** 我们的 `fragments/busybox.config` 开了 `CONFIG_FEATURE_SECURETTY=y`，这意味着 BusyBox 的 login 会去读 `/etc/securetty`，只允许列在里面的 tty 以 root 登录。但 Buildroot 的 skeleton 默认**不生成**这个文件——结果就是串口 `ttymxc0` 上 root 登录直接被拒，提示密码错误或者直接拒绝。`post-build.sh` 第 ②-bis 段专门补了这个文件，把常用串口和控制台（`console`、`tty1-6`、`ttyS0/1`、`ttymxc0/1/2`、`ttyAMA0`、`ttyUSB0`）都列进去。这一点真的坑了我半天，明明 rootfs 完整、密码也对，就是登不进去，最后才发现是 securetty 缺失。

**坑三：Qt6 的 shadertools / host qt6base 拉取。** `qt6declarative` 依赖 `qt6shadertools`，而 shadertools 的构建又需要 host 侧的 qt6base（带 NETWORK）。这条依赖链在 Buildroot 里有时会因为 QUICK 模式的源码拉取顺序出问题，表现是编到 qt6declarative 时报 host qt6base 找不到符号。解法是遇到这种情况对 host qt6base 做一次 `make clean` 再重建，让它按完整依赖重新编一遍。本地迁 Qt6 的时候如果编到一半挂在这，别急着怀疑 fragment 配置错，先试试这条。

**坑四：br2-external 变量名大小写。** 前面提过一次，这里再强调：defconfig 里引用 br2-external 路径必须用 `$(BR2_EXTERNAL_imxforge_PATH)`，`imxforge` 全小写，和 `external.desc` 里 `name: imxforge` 一致。Buildroot 的变量名规则是从 `external.desc` 的 name 字段直接派生的，大小写敏感。写成大写 `IMXFORGE` 是解析不出来的，路径会变空，引用它的配置项全部失效。

**坑五：换 rootfs 后必须重启 nfs-ganesha。** 这个不算 Buildroot 本身的坑，但迁移时一定会碰到：我们用 NFS root 启动板子，host 上由 nfs-ganesha 通过 bind-mount 把 `out/release-latest/rootfs/` 暴露给板子。每次你用新构建的 rootfs 替换掉旧的 bind-mount 源之后，**必须 restart nfs-ganesha**，否则板子挂载 NFS root 会报 ESTALE——因为 ganesha 缓存的还是旧 inode。这条对任何 rootfs 互换都成立，不只是 Buildroot 迁移，但迁移期你换 rootfs 换得最频繁，最容易中招。

## 下一步

到这里，整个 Buildroot 系列就收尾了。从第 01 章的工作原理，一路走到配置体系、br2-external tree、自定义 package、init 系统、ccache 重建、调试排错、Qt6 集成，最后到这一章的迁移对照——你现在应该既会"从零用 Buildroot 建 rootfs"，也懂"怎么把旧手搓 rootfs 平滑迁过来"。

如果你是顺着旧版 IMX-Forge 升级过来的，照着这一章的对照表和踩坑清单走一遍，基本能把旧分支上的自定义内容全部迁到 Buildroot 体系下。如果是从头跟到这的新读者，恭喜你走完了全程，现在你手里有一套可复现、一键重建、能编 Qt6 的 i.MX6ULL rootfs 构建链了——给板子拍张照不过分。

想回过头查某一章，或者重新规划学习路径，可以回专栏首页：[Buildroot 根文件系统（目录）](index.md)。
