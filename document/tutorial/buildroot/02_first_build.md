# 第一次构建 IMX-Forge rootfs

::: info 本节你将学到
- `imx6ull_aes_defconfig` 九段各自在配什么：架构、工具链、系统、ccache、BusyBox、ALSA、Qt6、overlay/post-build、输出策略
- 一条 `./scripts/build_helper/build-buildroot.sh` 背后实际做了哪几步：设 `BR2_EXTERNAL`、`O=`、按 PATH 探测工具链路径写进 `.config`、跑 `defconfig` + `make`、最后 `rsync` 产物
- Buildroot 的 `target/` 目录为什么不直接拿去烧卡，我们又是怎么把它同步到 `out/release-latest/rootfs/` 的
- 为什么不在 defconfig 里打 ext4 镜像，而是留给 `build_imx6ull_image.sh` 用 `mke2fs -d` 现打
:::

::: tip 前置知识 · 环境
- 已读 [01 Buildroot 工作原理](01_how_buildroot_works.md)，对 Buildroot "下载→配置→编译→装包→打 rootfs" 这条流水线有整体印象
- 本机或 CI 容器里装好了 Arm GNU Toolchain 15.2.rel1（`arm-none-linux-gnueabihf-gcc` 在 PATH 里能找到）
- Buildroot submodule 已初始化（`third_party/buildroot/` 下有 `Makefile`）；如果没有，先跑 `git submodule update --init third_party/buildroot`
:::

上一章我们把 Buildroot 的工作原理从头捋了一遍，知道它本质上是一堆 Makefile + Kconfig，替你把下载、配置、交叉编译、组装 rootfs 全自动化了。说实话，原理看懂是一回事，真正敲下一条命令把它编出来、拿到一个能挂上板的 rootfs 目录树，又是另一回事。这一章我们就干这件非常具体的事：把 IMX-Forge 的 Buildroot rootfs 真正构建出来，亲眼看一遍从一条命令到产物中间到底发生了什么。

先把目标说清楚。这一章不打算把 Buildroot 的每个配置项都讲一遍（那是后面几章的活），而是带你走通"从 defconfig 到产物"这条完整路径。我们会逐段读 `imx6ull_aes_defconfig`，搞清楚每一段在配什么、为什么这么配；然后把 `build-buildroot.sh` 这个封装脚本拆开，看它替你做了哪些事；最后讲清楚产物落在哪、怎么拿去验证。读完这一章，你应该能独立跑通一次构建，对日志里吐出来的每一行心里都有数。

## 先看全貌：imx6ull_aes_defconfig 九段导读

IMX-Forge 的 Buildroot 主配置文件在 `rootfs/buildroot/configs/imx6ull_aes_defconfig`。这个文件只有七十多行，但每一行都有讲究。我们现在要做的是按它在文件里的分段，逐段拆开来看。

文件开头有一段总体说明的注释，先把定位讲清楚了：

```
# buildroot 只构建 rootfs 用户空间(Stage 3+4);kernel/uboot 由 build_helper
# 外部构建,产物在 out/release-latest/{uboot,linux}/;镜像由 build_imx6ull_image.sh
# 从 out/release-latest/rootfs/ 组装。本 defconfig 不设 BR2_LINUX_KERNEL / BR2_TARGET_UBOOT。
```

这三行注释是整个 defconfig 的灵魂：**Buildroot 在 IMX-Forge 里只管用户空间**。它不编内核、不编 U-Boot，所以你在整个文件里找不到 `BR2_LINUX_KERNEL` 和 `BR2_TARGET_UBOOT`。这不是遗漏，而是分工——kernel 和 U-Boot 走 `scripts/build_helper/` 那套外部构建，最后由镜像打包脚本把三者拼起来。理解了这一点，后面很多"为什么这里没有"的疑问自然就消解了。

### 第一段：Architecture

```
# ===== Architecture(ARM Cortex-A7, hard-float, NEON VFPv4)=====
BR2_arm=y
BR2_cortex_a7=y
BR2_ARM_EABIHF=y
BR2_ARM_FPU_NEON_VFPV4=y
```

这四行定义了目标架构。i.MX6ULL 的核心是 ARM Cortex-A7，所以 `BR2_arm=y` 选 ARM 架构，`BR2_cortex_a7=y` 选具体的 CPU core。`BR2_ARM_EABIHF=y` 表示用 hard-float ABI（硬件浮点），`BR2_ARM_FPU_NEON_VFPv4=y` 指定 NEON + VFPv4 协处理器。这几行直接决定了编译器用什么 ABI、浮点参数怎么传，必须和工具链前缀后缀（`gnueabihf` 里的那个 `hf`）对上，对不上后面链接阶段就会炸。

### 第二段：Toolchain（概要，详见第 03 章）

```
# ===== External preinstalled toolchain:Arm GNU Toolchain 15.2.rel1 =====
# 路径 /opt/arm-gnu-toolchain 仅为 CI 容器默认;本地由 build-buildroot.sh 按 PATH 中 gcc
# 位置写进 .config(sed + olddefconfig;Kconfig 不取命令行 BR2_),换机器无需改此处。
BR2_TOOLCHAIN_EXTERNAL=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y
BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y
BR2_TOOLCHAIN_EXTERNAL_PATH="/opt/arm-gnu-toolchain"
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="$(ARCH)-none-linux-gnueabihf"
BR2_TOOLCHAIN_EXTERNAL_GCC_15=y
BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_6=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y
BR2_TOOLCHAIN_EXTERNAL_CXX=y
BR2_TOOLCHAIN_EXTERNAL_FORTRAN=y
BR2_TOOLCHAIN_EXTERNAL_OPENMP=y
# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set
BR2_TOOLCHAIN_EXTERNAL_HAS_SSP=y
BR2_TOOLCHAIN_EXTERNAL_LOCALE=y
BR2_TOOLCHAIN_EXTERNAL_WCHAR=y
BR2_TOOLCHAIN_EXTERNAL_THREADS=y
BR2_TOOLCHAIN_EXTERNAL_THREADS_POSIX=y
```

这一大段声明了我们复用的外部工具链：Arm GNU Toolchain 15.2.rel1，GCC 15，glibc，内核 headers 6.6。几个关键点先点一下，细节留到 [第 03 章](03_external_toolchain.md) 展开。

`BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y` 告诉 Buildroot 工具链已经装好了，别去下载。`BR2_TOOLCHAIN_EXTERNAL_PATH="/opt/arm-gnu-toolchain"` 写的是 CI 容器里的默认路径，但注意注释那句"换机器不用改这里"——`build-buildroot.sh` 会按你 PATH 里的 `arm-none-linux-gnueabihf-gcc` 真实位置算出路径，用 sed 覆盖进 `.config`，所以这个值只是个占位默认值。`BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="$(ARCH)-none-linux-gnueabihf"` 定义工具链前缀，`$(ARCH)` 是 Buildroot 的 Kconfig 变量，展开后就是 `arm`，所以完整前缀是 `arm-none-linux-gnueabihf`。

这里有个真正的坑。`# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set` 这行看着像注释，实际上是一个**必须显式关闭**的 Kconfig 符号。现代 glibc 早就删掉了 SUN RPC 支持，如果 Buildroot 以为你的工具链还带 RPC，编某些包时会去找 `rpc/rpc.h`，直接报错给你看。这一点第 03 章会专门拆。剩下的几行就是逐项声明工具链能力：C++（`_CXX`）、Fortran（`_FORTRAN`）、OpenMP、栈保护（`_HAS_SSP`）、locale、宽字符、POSIX 线程。Buildroot 会拿这些声明去决定哪些包能编、哪些特性测试代码能过——声明和实际对不上，构建就会挂在半路上。

### 第三段：System

```
# ===== System(串口 ttymxc0 115200,busybox init,eudev 动态设备节点)=====
BR2_TARGET_GENERIC_GETTY_PORT="ttymxc0"
BR2_TARGET_GENERIC_GETTY_BAUDRATE_115200=y
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
BR2_INIT_BUSYBOX=y
```

这四行定义了系统的基本运行姿态。串口控制台落在 `ttymxc0` 上、波特率 `115200`——i.MX6ULL 的调试串口就是它，Buildroot 会据此生成 `/etc/inittab` 里的 getty 行，串口参数配错了你连 login 提示符都看不到。`BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y` 选 eudev 做设备节点动态管理，这样 `/dev` 下的节点不用手建，热插拔也能自动处理。`BR2_INIT_BUSYBOX=y` 则选 BusyBox init 当 PID 1，这是最轻量的 init 方案，对应 `/etc/inittab` + `/etc/init.d/rcS` 那套传统流程，[第 08 章](08_init_system.md) 会专门讨论 init 系统的选型。

### 第四段：ccache

```
# ===== ccache(加速重复构建)=====
BR2_CCACHE=y
```

就一行，开了 ccache。ccache 会缓存编译中间产物，第二次构建直接复用，重复编译时间大幅缩短。这行的效果和细节在 [第 09 章](09_ccache_rebuild.md) 展开，这里只要知道它开着、能帮你省时间就够了。第一次全量构建用不上它，但只要你改配置重编第二次，就会真香。

### 第五段：BusyBox

```
# ===== busybox(用项目导出的完整 .config,877 applet 全功能;关 x86-only SHA HWACCEL)=====
BR2_PACKAGE_BUSYBOX=y
BR2_PACKAGE_BUSYBOX_CONFIG="$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config"
```

BusyBox 是整个 rootfs 的核心——init、shell、常用命令全靠它一个二进制撑着。`BR2_PACKAGE_BUSYBOX_CONFIG` 指向了 br2-external tree 里的一个完整 `.config` 文件（`fragments/busybox.config`，1200 多行，开了 877 个 applet），相当于把上游 Buildroot 那个精简版 BusyBox 换成了我们调好的全功能版。`$(BR2_EXTERNAL_imxforge_PATH)` 是 Buildroot 自动展开的变量，指向我们的 br2-external 根目录（`rootfs/buildroot/`），这样不管仓库 clone 到哪，路径都是对的。

### 第六段：ALSA

```
# ===== ALSA(wm8960 音频章节:alsa-lib + utils,替代 install_alsa.sh 手工交叉编译)=====
BR2_PACKAGE_ALSA_LIB=y
BR2_PACKAGE_ALSA_LIB_MIXER=y
BR2_PACKAGE_ALSA_LIB_PCM=y
BR2_PACKAGE_ALSA_LIB_UCM=y
BR2_PACKAGE_ALSA_UTILS=y
BR2_PACKAGE_ALSA_UTILS_APLAY=y
BR2_PACKAGE_ALSA_UTILS_AMIXER=y
BR2_PACKAGE_ALSA_UTILS_ALSACTL=y
BR2_PACKAGE_ALSA_UTILS_ALSAUCM=y
BR2_PACKAGE_ALSA_UTILS_SPEAKER_TEST=y
```

这段装的是 ALSA 音频栈：alsa-lib 的 mixer/pcm/ucm 子模块，加上 alsa-utils 里的 aplay、amixer、alsactl、alsaucm、speaker-test。这是给 WM8960 音频章节准备的——以前是手写一个 `install_alsa.sh` 脚本手工交叉编译 alsa-lib 和 alsa-utils，版本一升级就得回来改脚本，烦得不行；现在全交给 Buildroot 管理，注释里的"替代"说的就是这个迁移。

### 第七段：Qt6（纯注释，按需 merge）

```
# ===== Qt6:由 fragments/qt6.config 提供(按需 merge)=====
# CI 默认最小 rootfs(无 Qt6,~15min);compile-support-3rd-party label 或本地
# build-buildroot.sh --with-qt6 触发 Qt6 全模块(2-4h)。见 fragments/qt6.config。
```

这一段没有 `BR2_` 配置行，是个纯注释段，但它在文件里占了独立的 `=====` 分隔位置，解释了一个关键设计：**Qt6 不写进主 defconfig，而是放到 `fragments/qt6.config` 里按需 merge**。原因是 Qt6 全模块编译要 2-4 小时，默认最小 rootfs 不含它；只有打上 `compile-support-3rd-party` label 的 CI 任务、或本地执行 `build-buildroot.sh --with-qt6` 时，才会用 `merge_config.sh` 把这个 fragment 合进 `.config`。所以主 defconfig 在这里只留个说明，真正的配置住在 fragment 文件里。对应到脚本里，就是后面要讲的 Step 1b。

### 第八段：Overlay + post-build

```
# ===== Overlay + post-build(补 linuxrc/rcS/inittab + 跑 varified 校验)=====
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_imxforge_PATH)/post-build.sh"
```

这两行是 rootfs 定制的核心机制。`BR2_ROOTFS_OVERLAY` 指向 overlay 目录，Buildroot 打包 rootfs 时会把这里的文件原封不动地叠到 `target/` 上。`BR2_ROOTFS_POST_BUILD_SCRIPT` 指定一个在 rootfs 打包**前**执行的脚本，我们的 `post-build.sh` 干的活不少：补 `linuxrc -> bin/busybox` 软链、补 `/etc/securetty`、下载 SDMA 固件、（有 Qt6 时）下载 CJK 字体，最后跑一个校验闸门 `varified_rootfs_ok.sh`——rootfs 不完整就直接中止构建，不让残次品流到下游。这两行对应的机制就是 [第 06 章](06_rootfs_customization.md) "rootfs 定制三板斧" 的前两板斧，这里先留个印象。

### 第九段：Rootfs 输出

这一段也是个纯注释段，没有配置行，但它的内容非常重要，解释了"为什么 defconfig 里找不到 ext4 镜像选项"：

```
# ===== Rootfs 输出 =====
# 不用 buildroot 自带 ext2/ext4 镜像:它尺寸固定,加 Qt6 后需不断手调;
# 且最终 SD/eMMC 镜像由 build_imx6ull_image.sh 从 out/release-latest/rootfs/ 用
# mke2fs -d 现打(按实际内容动态尺寸,更灵活),NFS root 直接挂 rootfs/ 目录。
# 故 buildroot 只产 target/(→ rsync 到 rootfs/),不打 fs image。
```

这段话的逻辑链是这样的。Buildroot 本来可以在 `images/` 下吐 ext4 镜像（通过 `BR2_TARGET_ROOTFS_EXT2` 等选项），但我们故意不开。原因有两个：一是 Buildroot 自带的 ext2/ext4 生成器尺寸是写死的，加 Qt6 后 rootfs 膨胀到几百 MB，你得不断回头手调尺寸参数；二是最终烧录的 SD/eMMC 镜像由 `build_imx6ull_image.sh` 统一组装，它用 `mke2fs -d` 从 rootfs 目录现打 ext4，尺寸按实际内容动态算，灵活得多。而且 NFS root 场景下直接挂 `rootfs/` 目录就行，根本用不上 ext4 这个文件。所以 Buildroot 这边只管把 `target/` 吐出来，镜像格式的事留给下游。这个决策后面还会单独展开讲。

## 一键构建：build-buildroot.sh 背后做了什么

看完 defconfig，接下来我们看构建脚本。你平时只需要敲一条命令：

```bash
./scripts/build_helper/build-buildroot.sh
```

这条命令看着短，背后却封装了好几步逻辑。我们按脚本里的 Step 划分，一段段拆开，看看它到底替你做了哪些事。

### 前置检查：submodule 和 br2-external

脚本一上来先确认两个前提条件满足：

```bash
if [[ ! -f "${BUILDROOT_DIR}/Makefile" ]]; then
    log_error "Buildroot submodule not initialized: ${BUILDROOT_DIR}"
    log_error "Run: git submodule update --init third_party/buildroot"
    exit 1
fi
if [[ ! -f "${BR2_EXTERNAL_DIR}/external.desc" ]]; then
    log_error "BR2_EXTERNAL tree missing external.desc: ${BR2_EXTERNAL_DIR}"
    exit 1
fi
```

第一个检查确认 Buildroot submodule 已初始化（`third_party/buildroot/Makefile` 存在），第二个确认 br2-external tree 完整（`rootfs/buildroot/external.desc` 存在）。这两个文件缺一不可，缺了构建根本无从谈起，脚本直接 `exit 1` 把你拦住，省得跑半天才在别的地方报一个莫名其妙的错。

### PATH 过滤：WSL 的空格坑

Buildroot 有一个出了名的严格检查：如果 PATH 里包含带空格的路径（比如 WSL 里混进来的 `/mnt/c/Program Files`），它会直接甩一句 `"Your PATH contains spaces"` 然后罢工。脚本专门做了过滤：

```bash
# WSL 默认 PATH 带 Windows 路径(如 /mnt/c/Program Files)会触发此错误;Docker 环境 PATH
# 干净,此过滤为 no-op。过滤掉含空白字符的 PATH 组件。
for d in "${_path_dirs[@]}"; do
    [[ "$d" == *' '* || "$d" == *$'\t'* || "$d" == *$'\n'* ]] && continue
    CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$d"
done
```

如果你在 Docker/CI 环境里跑，PATH 本来就干净，这段是 no-op，什么也不干。但如果你跟我一样在 WSL 里本地构建，这段过滤能帮你直接省掉一个一头雾水的报错——说实话，第一次撞到 "Your PATH contains spaces" 的时候我还真没想到是 Windows 路径混进来了。

### 工具链路径探测：换机器不用改 defconfig

这是脚本里最精巧的一段，也是前面"换机器不用改 defconfig"那个承诺真正落地的地方。defconfig 里 `BR2_TOOLCHAIN_EXTERNAL_PATH` 写死了 `/opt/arm-gnu-toolchain`，但这只是 CI 容器的路径，你本机可能装在别的位置。脚本怎么处理？它按 PATH 里 `arm-none-linux-gnueabihf-gcc` 的真实位置反推：

```bash
for _d in "${_pd[@]}"; do
    _c="${_d}/arm-none-linux-gnueabihf-gcc"
    [[ -x "$_c" ]] || continue
    _r="$(readlink -f "$_c" 2>/dev/null || printf '%s' "$_c")"
    [[ "$(basename "$_r")" == "ccache" ]] && continue   # ccache 包装,跳过
    _tc_gcc="$_c"; break
done
if [[ -n "${_tc_gcc}" ]]; then
    TC_ROOT="$(cd "$(dirname "$(readlink -f "${_tc_gcc}")")/.." && pwd)"
else
    TC_ROOT="/opt/arm-gnu-toolchain"   # fallback = defconfig 默认(CI 容器)
fi
```

这段逻辑有几个细节值得注意。第一，它遍历 PATH 找 `arm-none-linux-gnueabihf-gcc`，找到后取其父目录的父目录作为工具链根。第二，它特意跳过了 ccache 包装——CI 和本地如果开了 ccache，会在 PATH 前段塞一个 `ccache-bin/arm-none-linux-gnueabihf-gcc -> /usr/bin/ccache` 符号链接，`readlink -f` 解析过去指向 `/usr/bin/ccache`，要是拿这个算工具链根就会变成 `/usr`，Buildroot 去找 `/usr/bin/arm-none-linux-gnueabihf-gcc` 直接报 "Cannot execute cross-compiler"。所以脚本判断 `basename` 是 `ccache` 的就跳过，取下一个真实候选。第三，如果 PATH 里完全找不到，就 fallback 到 `/opt/arm-gnu-toolchain` 并打个 warn。

::: details 为什么不直接用 `command -v`？
脚本注释解释了这个选择：`command -v` 会命中 PATH 里第一个匹配，而 ccache 的包装通常塞在 PATH 前段，`command -v arm-none-linux-gnueabihf-gcc` 会先返回 ccache 那个符号链接。手动遍历可以逐个检查、跳过 ccache，拿到第一个真实的编译器。
:::

### Step 1：跑 defconfig

```bash
if [[ ${CLEAN} -eq 1 || ${RECONFIGURE} -eq 1 || ! -f "${OUTPUT_DIR}/.config" ]]; then
    log_info "Step 1: Applying defconfig ${DEFCONFIG}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" "${DEFCONFIG}"
else
    log_info "Step 1: Reusing existing .config (use --reconfigure to re-apply defconfig)"
fi
```

这里调用了 Buildroot 的 defconfig 机制，三个参数各有讲究。`-C "${BUILDROOT_DIR}"` 是进 Buildroot 源码目录（`third_party/buildroot/`）执行。`O="${OUTPUT_DIR}"` 指定 out-of-tree 输出目录，Buildroot 官方手册（`common-usage.adoc` → *Building out-of-tree*）说得很清楚：加 `O=<directory>` 就能把所有输出放到源码树外面。我们的输出目录是 `out/release-latest/buildroot`，不污染 submodule，这样多个构建还能共用同一份 Buildroot 源码，只要 `O=` 不同就行。`BR2_EXTERNAL="${BR2_EXTERNAL_DIR}"` 则把我们的 br2-external tree 注入进去，Buildroot 会读这个目录下的 `external.desc`（里面写了 `name: imxforge`），把 `configs/`、`fragments/`、`overlay/` 这些定制内容纳入构建体系。

最后一个参数 `imx6ull_aes_defconfig` 是要应用的 defconfig 目标名，Buildroot 会在 `BR2_EXTERNAL` 指定目录的 `configs/` 下找到它，生成 `.config`。注意这里的增量逻辑：如果 `.config` 已经存在且没传 `--reconfigure` 或 `--clean`，脚本会跳过 defconfig 直接复用旧配置，这样你反复跑构建时不用每次都重新生成 `.config`。

### Step 1c：把工具链路径写进 .config

这一步是 Step 1 的补充，也是前面"换机器不用改 defconfig"承诺的真正落地：

```bash
if ! grep -q "^BR2_TOOLCHAIN_EXTERNAL_PATH=\"${TC_ROOT}\"$" "${OUTPUT_DIR}/.config"; then
    log_info "Step 1c: Toolchain path → ${TC_ROOT} (from PATH)"
    sed -i 's|^BR2_TOOLCHAIN_EXTERNAL_PATH=.*|BR2_TOOLCHAIN_EXTERNAL_PATH="'"${TC_ROOT}"'"|' "${OUTPUT_DIR}/.config"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" olddefconfig
fi
```

逻辑很直白：先 grep 检查 `.config` 里的路径是否已经是目标值，不是才动。用 sed 把 `BR2_TOOLCHAIN_EXTERNAL_PATH=` 那行替换成 PATH 探测出的真实路径，然后跑一次 `olddefconfig` 让 Buildroot 规范化配置、补齐依赖项。

::: warning 踩坑预警：为什么不用 `make BR2_TOOLCHAIN_EXTERNAL_PATH=xxx` 传进去？
脚本注释说得很直白：**Buildroot 的 Kconfig 符号不取 `make BR2_X=Y` 命令行覆盖**。Kconfig 只读 `.config` 文件，命令行传的 `BR2_` 变量在 `make` 执行时有效，但不会写回 `.config`，defconfig 流程也不会读它。所以必须用 sed 直接改 `.config` 文件，再跑 `olddefconfig` 让 Buildroot 重新解析依赖。这一点真的坑了我半天，第 03 章还会展开讲。
:::

### Step 1b（可选）：合并 Qt6 fragment

如果你传了 `--with-qt6`（或设了 `BUILDROOT_QT6=1` 环境变量），脚本会在这时候把 Qt6 fragment 合进 `.config`：

```bash
if [[ ${WITH_QT6} -eq 1 ]]; then
    QT6_FRAGMENT="${BR2_EXTERNAL_DIR}/fragments/qt6.config"
    "${BUILDROOT_DIR}/support/kconfig/merge_config.sh" -m -O "${OUTPUT_DIR}" \
        "${OUTPUT_DIR}/.config" "${QT6_FRAGMENT}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" olddefconfig
fi
```

`merge_config.sh` 是 Linux 内核提供的 fragment 合并工具（Buildroot 自带一份），`-m` 表示合并后不跑 `alldefconfig`，因为我们接下来要手动跑 `olddefconfig`。Qt6 全模块编译要 2-4 小时，所以默认最小 rootfs 不含 Qt6，CI 里由 `compile-support-3rd-party` label 触发。这块细节留到 [第 11 章](11_qt6_integration.md)，这里只要知道它在 Step 1 之后、Step 2 之前插入就行。

### Step 2：make 构建

```bash
make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" -j"${NPROC}" 2>&1 | tee "${LOG}"
```

到这一步就是正式编译了。`-j$(nproc)` 开满核并行（Buildroot 支持包级别的 `make -jN`，每个包内部并行编译）。日志通过 `tee` 同时输出到屏幕和 `buildmeter-full.log`，如果 buildmeter 进度条可用，还会把日志喂给进度条脚本，在终端上显示包级别的构建进度——这个进度条在跑 Qt6 那种长构建时特别能救命。

这一步也是整条流程里最耗时的。最小 rootfs（无 Qt6）大约 15 分钟，含 Qt6 则 2-4 小时，具体取决于你的机器和缓存状态。先别急着离开屏幕，你会发现第一次构建经常在某个包的下载或 patch 阶段卡一下，值得盯着日志看。

## 产物在哪：target/ 到 rootfs/

Buildroot 构建完成后，输出目录（`out/release-latest/buildroot/`）的结构和官方手册（`quickstart.adoc`）描述的一致：`build/` 放各组件的编译中间产物，`host/` 装 Buildroot 为 host 编译的工具以及目标工具链的 sysroot，`images/` 本该是 rootfs 镜像文件（ext4、tar 等）但因为我们没开 ext4 选项这里基本是空的，而 `target/` 则是**几乎完整**的 rootfs 目录树。

关于 `target/`，Buildroot 官方手册有一段很关键的警告：

> *target/* which contains 'almost' the complete root filesystem for the target: everything needed is present except the device files in */dev/* (Buildroot can't create them because Buildroot doesn't run as root and doesn't want to run as root). Also, it doesn't have the correct permissions (e.g. setuid for the busybox binary). Therefore, this directory *should not be used on your target*.

简单说，`target/` 缺 `/dev` 设备节点、权限也不对（Buildroot 不以 root 运行），官方建议用 `images/` 下的镜像而不是直接拿 `target/` 上板。但我们的场景不太一样：因为用了 eudev 动态设备节点管理，`/dev` 是运行时由内核 + eudev 自动填充的，不需要构建时静态创建；权限问题则交给镜像打包阶段处理。加上我们走 NFS root 时直接挂目录，所以 `target/` 对我们反而是最方便的产物形式。

脚本用一步 rsync 把 `target/` 同步到最终的 release 目录：

```bash
TARGET_DIR="${OUTPUT_DIR}/target"
rsync -a --delete \
    --exclude ".gitkeep" \
    --exclude ".stamp" \
    --exclude "var/lib/seedrng" \
    --exclude "var/lib/urandom" \
    --exclude "var/lib/misc" \
    --exclude "var/lib/dhcp" \
    --exclude "var/lib/network" \
    "${TARGET_DIR}/" "${RELEASE_ROOTFS}/"
```

`--delete` 保证 release rootfs 和 Buildroot target 完全一致，删掉旧的多余文件。后面那一串 `--exclude` 是排除 NFS root 的运行时目录——板子跑起来后，`var/lib/seedrng`、`var/lib/dhcp` 这些目录是 root 写的，host 端非特权用户删不掉，不排除的话 `rsync --delete` 下次就会失败。这些本来就是运行时缓存，host 端不需要同步。

rsync 完成后，脚本还有一道最终闸门：

```bash
if [[ ! -x "${RELEASE_ROOTFS}/bin/busybox" ]]; then
    log_error "Verification failed: ${RELEASE_ROOTFS}/bin/busybox missing"
    exit 1
fi
```

确认 `bin/busybox` 存在且可执行——如果连这个都没有，说明 rootfs 根本没构建成功，趁早拦住别往下走。注意这只是一道快速检查，更完整的校验（`varified_rootfs_ok.sh`）已经在 `post-build.sh` 里跑过了。

最终产物在 `out/release-latest/rootfs/`。这就是下游镜像打包脚本 `build_imx6ull_image.sh` 消费的 rootfs 目录。

## 为什么不在 Buildroot 里打 ext4

前面读 defconfig 第九段时已经提过这个决策，这里我们把"为什么"展开讲透。

Buildroot 自带的 ext2/ext4 镜像生成器（`BR2_TARGET_ROOTFS_EXT2` 系列）有一个特点：**镜像尺寸是配置时写死的**。你在 defconfig 里得显式指定 `BR2_TARGET_ROOTFS_EXT2_SIZE`（比如 128M），留空 Buildroot 会直接 `$(error ...)` 报错退出。问题在于，rootfs 内容是动态变的——最小 rootfs 可能只有 30MB，加了 Qt6 直接膨胀到 300MB 以上。每次内容一变，你就得回头调尺寸参数，调大了浪费 flash 空间，调小了 rootfs 塞不下，两头受气。

这里有个细节值得单独说一句：Buildroot 内部用的生成工具其实和下游一样，都是 e2fsprogs 的 `mkfs.ext2/3/4`（也就是 `mke2fs`），命令里同样带 `-d $(TARGET_DIR)` 从目标目录填充内容，这一点在 `third_party/buildroot/fs/ext2/ext2.mk` 里可以看到。所以 IMX-Forge 把镜像格式的事从 Buildroot 里剥出来，真正的差异点不在工具，而在**尺寸策略**：Buildroot 要求你在配置里写死一个固定尺寸，而 `build_imx6ull_image.sh` 用 `mke2fs -d` 现打时是按 rootfs 目录的实际内容动态算镜像尺寸的。

`mke2fs -d` 的 `-d` 参数指定一个源目录，工具会按目录内容的实际大小动态计算 ext4 镜像尺寸，不需要你手填固定值。这也顺带方便了 NFS root 场景：直接把 `rootfs/` 目录通过 NFS 挂到板子上当根文件系统，根本不需要 ext4 这个文件，连打包这一步都省了。这种"各管一段"的分工，比让 Buildroot 一把梭去管镜像格式要灵活得多。

## 跑起来验证

rootfs 构建出来后，怎么确认它真的能用？我们来上板测试一下，两种方式按你的场景选。

### 方式一：NFS root 直接挂目录

这是开发期最方便的方式。`out/release-latest/rootfs/` 是一个完整的目录树，通过 NFS 导出后，板子内核用 `root=/dev/nfs nfsroot=...` 参数启动，直接挂这个目录当根文件系统，不需要打 ext4、不需要烧卡，改了 rootfs 内容后重启板子就能看到效果。调试阶段我几乎全程用这种方式。

这里有个坑要提醒你。如果 `rootfs/` 目录之前被 NFS 挂载过（板子还在跑），里面可能有 root 属主的运行时文件，host 端非特权用户删不掉，下次 rsync 时会报错。脚本注释给了处理方法：

```bash
# 处理:sudo rm -rf ${RELEASE_ROOTFS} 后重跑本脚本
```

直接 `sudo rm -rf` 干掉旧目录，重新跑一次 `build-buildroot.sh` 就行。别手滑删错路径，不然你会收获一个重新构建的漫长下午。

### 方式二：最小镜像烧录

如果你要上 SD 卡或 eMMC，走 `build_imx6ull_image.sh` 把 kernel + dtb + rootfs 打包成完整镜像。它会从 `out/release-latest/rootfs/` 用 `mke2fs -d` 生成 ext4 rootfs 分区，再和 U-Boot、内核镜像拼成一张可烧录的 SD 卡镜像。

不管走哪种方式，rootfs 起来后，你会发现串口上开始刷 BusyBox init 的启动日志，最后落到 `ttymxc0` 上的 login 提示符。用 root 登录（无密码或默认密码取决于你的配置），能跑 `busybox` 的各种命令，就说明这个 rootfs 基本可用了。打个 `ls /`、`cat /etc/inittab` 看看，再 `aplay -l` 确认下 ALSA 设备在不在，整个链路就算走通了。

## 常用选项速查

最后列一下 `build-buildroot.sh` 的几个常用选项，方便日常使用：

| 选项 | 作用 |
|------|------|
| `--clean` | 只清理 Buildroot 输出目录（`rm -rf`）后退出，不构建。清理后需再跑一次（不带 `--clean`）才会构建 |
| `--reconfigure` | 强制重新跑 defconfig（不删输出目录）。改了 defconfig 后用这个 |
| `--source-only` | 只下载源码包到 `dl/`（`make source`），不构建。适合预先缓存源码 |
| `--with-qt6` | 合并 Qt6 fragment，构建含 Qt6 的完整 rootfs（2-4 小时） |
| `--output-dir PATH` | 指定 Buildroot `O=` 输出目录（默认 `out/release-latest/buildroot`） |
| `--release-rootfs PATH` | 指定最终 rootfs 同步目标（默认 `out/release-latest/rootfs`） |
| `--defconfig NAME` | 指定 defconfig 名（默认 `imx6ull_aes_defconfig`） |

一个典型的工作流是这样的：第一次完整构建用默认参数；改了 defconfig 后用 `--reconfigure` 让新配置生效；想清空从头来用 `--clean` 然后重新构建。

::: warning 踩坑预警：`--clean` 是先清理再退出
`--clean` 只做清理，**不会接着构建**。脚本日志会提示你："Cleaned (--clean only). To build, re-run without --clean"。很多人第一次用会以为 `--clean` 是"清理后重建"，实际上你得跑两次——先 `--clean`，再不带 `--clean` 跑一次。一定确认你理解了这点，不然会盯着屏幕纳闷怎么清完就退出了。
:::

## 下一步

这一章我们跑通了从 defconfig 到 rootfs 产物的完整路径，但有一个东西只是顺带提了几下、一直没展开——**工具链**。defconfig 里那一长串 `BR2_TOOLCHAIN_EXTERNAL_*` 到底每一行在干什么？为什么 `INET_RPC` 非关不可？`build-buildroot.sh` 为什么非要用 sed 改 `.config`、却不能传命令行变量？真正的坑都藏在这里面。

事情到这里，工具链这件事值得单独拎出来讲透。下一章 [03 External Toolchain 复用](03_external_toolchain.md)，我们把工具链从头拆到尾。
