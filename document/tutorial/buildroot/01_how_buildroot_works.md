# Buildroot 工作原理

::: info 本节你将学到
- Buildroot 到底是个什么东西：为什么说它就是"一堆 Makefile + 一套 Kconfig"，它替你自动化了哪些手工活，源码树里每个目录又各管哪一摊
- 一次 `make` 背后的完整流水线：建输出目录 → 生成（或导入）工具链 → 按 `TARGETS` 逐个编（rootfs 镜像打包包含在这一步内）
- `O=` 输出目录里 `build/`、`host/`、`staging/`、`target/`、`images/` 每个目录装了什么，`staging` 和 `target` 为什么要把同一个库装两份
- 为什么 IMX-Forge 故意不设 `BR2_LINUX_KERNEL` / `BR2_TARGET_UBOOT`，而是让 Buildroot 只管用户空间这一段
:::

::: tip 前置知识 · 环境
- 读过 [手搓 Rootfs](../rootfs/) 那几章，自己搭过 BusyBox rootfs，这样你才能切身体会 Buildroot 替你省了哪些事
- 会用 `make menuconfig`（内核或 U-Boot 的都行），Kconfig 的 `y/n/m`、`select`、`depends on` 这些概念不陌生
- 本机已 `git submodule update --init third_party/buildroot`，源码树就位（本章我们直接对着源码讲，下一章才真正动手编）
:::

## 先搞清楚 Buildroot 到底是什么

如果你照着手搓 rootfs 那几章走过一遍，回忆一下当时的流程：自己 `menuconfig` 编 BusyBox、自己装交叉工具链、自己往 rootfs 目录里塞库和配置文件、自己合并 overlay、自己调 `inittab`……每加一个组件，都要重复一轮"下载源码 → 交叉编译 → 想办法塞进 rootfs → 调通"的手工活。说实话，加到 Qt6 这种依赖一箩筐的巨兽时，手工流程就开始失控了——我当初就是在这里被磨得没脾气的。

Buildroot 要解决的就是这件事。官方手册开篇一句话定性（`how-buildroot-works.adoc`）：

> Buildroot is basically a set of Makefiles that download, configure, and compile software with the correct options.

翻译过来就是，Buildroot 本质上是一堆 Makefile，替你把软件包的下载、配置、交叉编译全自动化了，最后组装出一个 rootfs。它还顺带管一套 Kconfig 配置系统，和你配内核、配 U-Boot 用的是同一套东西，所以你会 `make menuconfig` 就基本会用 Buildroot。

你先别急着往下走，注意这个定语的分量："with the correct options"（用正确的选项）。交叉编译最恶心的地方就在"正确的选项"——sysroot 指向哪、`--host` 填什么 target tuple、该不该传 `--sysroot`、库的搜索路径怎么理清……这些破事每一样都能让你卡半天。Buildroot 替你把它们全包了：每个软件包在 Buildroot 里就是一个 `.mk` 文件，里面把"怎么下、怎么配、怎么编、装到 staging 还是 target"写得明明白白，你只要在 menuconfig 里勾上它，剩下的交给 `make`。

一句话定位：Buildroot 是一个用 Makefile + Kconfig 驱动的 rootfs 自动构建框架，你配置要哪些包，它负责把它们全部交叉编译好、组装成可烧录的根文件系统。

## 源码树解剖：每个目录各管一摊

打开 `third_party/buildroot/`，你会看到一堆顶层目录。我们现在要做的是照着官方手册的描述，把每个目录的职责对一遍——这些不是泛泛而谈，手册原文（`how-buildroot-works.adoc`）就是这么分的，我也在源码里逐个验证过。

```text
third_party/buildroot/
├── toolchain/     # 交叉工具链（GCC/binutils/gdb/kernel-headers/uClibc）
├── arch/          # 各处理器架构的定义（Config.in.arm、Config.in.mips…）
├── package/       # 所有用户空间包（每个子目录一个包）
├── linux/         # Linux 内核的构建规则
├── boot/          # 引导加载器（U-Boot、barebox、ATF…）
├── system/        # 系统集成（rootfs 骨架、init 系统选择）
├── fs/            # 根文件系统镜像生成（ext2、squashfs、cpio…）
├── Makefile       # 顶层 Makefile——编排整条流水线
└── Config.in      # 顶层 Kconfig 入口
```

我们挨个说。先看 `toolchain/`，它管的是交叉编译工具链本身。往里翻你会找到 `toolchain-buildroot/`（internal 后端，Buildroot 自己从头编 GCC）、`toolchain-external/`（external 后端，导入一个现成工具链）、`toolchain-wrapper.c`（一个 wrapper 程序，后面讲），还有关键的 `helpers.mk`（工具链特性校验逻辑）。IMX-Forge 用的是 external 后端——复用项目里现成的 Arm GNU Toolchain，不让 Buildroot 自己编，这一点第 03 章会专门讲。

接下来是 `arch/`，放各架构的定义。这里要分两层看：`arch/Config.in` 定义 `BR2_arm` 这种架构大类，而 `arch/Config.in.arm` 进一步定义 `BR2_cortex_a7`、`BR2_ARM_EABIHF` 这些 ARM 具体型号和 ABI 选项。我们 defconfig 开头的 `BR2_arm=y`、`BR2_cortex_a7=y`、`BR2_ARM_EABIHF=y` 就是从这两个地方来的，你按符号回去找就能对上。

再往下就是最核心的 `package/`——所有用户空间工具和库都在这里，一个子目录一个包。这是 Buildroot 包罗万象的地方，从 BusyBox、ALSA 到 Qt6，几千个包全堆在这儿。`linux/` 和 `boot/` 分别是内核和引导加载器的构建规则，但先别急，注意它们只是"规则"，要不要启用、编不编取决于你的配置——IMX-Forge 这两个都没启用，原因后面单开一节讲，这也是我们刻意的设计。

`system/` 管系统集成，里面有个 `skeleton/` 子目录是 rootfs 的初始骨架（`/bin`、`/etc`、`/dev` 这些空目录结构），还有 init 系统的选择（BusyBox init / SysV / systemd）。最后 `fs/` 管的是怎么把 `target/` 目录树打包成最终的文件系统镜像，ext2、squashfs、cpio、ubifs 各种格式各有各的 `.mk`。

### 每个包就两件套：.mk + Config.in

手册接着讲了一个贯穿全树的组织原则，每个目录里至少有两个文件——

> `something.mk` is the Makefile that downloads, configures, compiles and installs the package `something`.
> `Config.in` is a part of the configuration tool description file. It describes the options related to the package.

这就是 Buildroot 的"两件套"约定。我们随便挑一个包来看，就拿 `package/zlib/`：

```text
package/zlib/
├── Config.in      # 声明这个包在菜单里的选项（BR2_PACKAGE_ZLIB）
└── zlib.mk        # 声明怎么下载、配置、编译、安装 zlib
```

`Config.in` 里写的是 Kconfig 选项，它决定了这个包在 `menuconfig` 里显不显示、叫什么名字、依赖什么；`zlib.mk` 里写的是构建逻辑，从哪下载源码、用什么 configure 参数、编完装到 `staging` 还是 `target`。这一套"声明 + 实现"分离的模式，和内核里 Kconfig 与 Makefile 的关系一模一样，你完全可以用配内核的直觉来理解。

再看复杂一点的 `package/busybox/`，除了两件套还多了一堆补丁和配置文件：

```text
package/busybox/
├── Config.in              # BusyBox 在菜单里的选项
├── busybox.mk             # 构建 + 安装逻辑
├── busybox.config         # Buildroot 给的默认 busybox .config
├── busybox.hash           # 源码包的哈希校验（防下载被篡改）
├── 0001-xxx.patch         # 给 BusyBox 打的补丁（按编号顺序应用）
├── 0002-xxx.patch
├── ...
├── inittab                # 默认 inittab 模板
├── S01syslogd             # init 启动脚本（SysV 风格）
└── mdev.conf              # mdev 设备节点配置
```

补丁按 `0001-`、`0002-` 这样编号，Buildroot 构建时会自动按顺序应用。这个机制我们在第 05 章 br2-external tree 里也会用到，这里你先有个印象就行：Buildroot 不只是"下载源码然后编"，它还能给每个包打补丁、塞配置，把定制能力也自动化了。

## 构建流水线：一次 make 背后发生了什么

手册用三个 bullet 描述了顶层 Makefile 在配置完成后干的事（`how-buildroot-works.adoc`），这是理解 Buildroot 的核心，我们逐条拆开：

> 1. Create all the output directories: `staging`, `target`, `build`, etc. in the output directory
> 2. Generate the toolchain target
> 3. Generate all the targets listed in the `TARGETS` variable

第一步是建输出目录。Buildroot 会在 `O=` 指定的输出目录下创建 `build/`、`host/`、`target/`、`images/` 等一堆目录。这些目录的含义下一节单独讲，这里你只要知道 Buildroot 先把舞台搭好就对了。

第二步是生成工具链，这里手册特意区分了两种情况，这句话信息量很大：

> When an internal toolchain is used, this means generating the cross-compilation toolchain. When an external toolchain is used, this means checking the features of the external toolchain and importing it into the Buildroot environment.

internal 后端是真的编译一套工具链出来——下载 GCC、binutils、C 库的源码从头编一遍，这一步动辄二三十分钟。而 external 后端是检查特性加导入：Buildroot 不编任何东西，而是去检测你提供的工具链——GCC 是什么版本、用什么 C 库、支持 C++ 吗、带 RPC 吗……把你 defconfig 里的声明和工具链实际能力做比对，对不上就直接报错中止（第 03 章详细讲这个校验机制）。IMX-Forge 走的是 external，所以这一步不是"编 GCC"而是"检查并导入"，几分钟就过。

第三步是按 `TARGETS` 变量逐个构建。`TARGETS` 是一个全局变量，由所有组件的 `.mk` 文件往里填充，每个包的 `.mk` 都会把自己的名字 append 进去。Makefile 读到 `world` 这个顶层目标时，就把 `TARGETS` 里列的所有包按依赖顺序排好挨个编，这一步编译的就是用户空间的库和程序。等所有包编完、装好，最后生成 rootfs 镜像（如果配了 `fs/` 里的格式的话），它和编包同属第三步，不是独立的第四步。

### 对着 build-buildroot.sh 看这三步落地

我们把这个抽象的流水线对着 IMX-Forge 的 `build-buildroot.sh` 落地看。脚本把整件事也分成了三步，对应手册的三个阶段。

```bash
# build-buildroot.sh 第 153-159 行（Step 1: defconfig）
if [[ ${CLEAN} -eq 1 || ${RECONFIGURE} -eq 1 || ! -f "${OUTPUT_DIR}/.config" ]]; then
    log_info "Step 1: Applying defconfig ${DEFCONFIG}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" "${DEFCONFIG}"
else
    log_info "Step 1: Reusing existing .config (use --reconfigure to re-apply defconfig)"
fi
```

Step 1 是把 defconfig 展开成 `.config`，这一步发生在"流水线"之前，属于配置阶段。`O=` 指定输出目录，`BR2_EXTERNAL=` 把我们的 br2-external tree 注入进去（第 05 章讲）。注意这里传的是 `imx6ull_aes_defconfig` 这个目标不是 `all`，所以只是生成 `.config` 不真正开始编。

```bash
# build-buildroot.sh 第 208-210 行（Step 2: make）
make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" -j"${NPROC}" 2>&1 \
    | tee "${LOG}" \
    | python3 "${FORGE_PROGRESS_PY}" buildroot ...
```

Step 2 才是真正的 `make`，这一行触发了手册说的全部三个阶段：建目录、导入工具链、按 TARGETS 编包。`-j$(nproc)` 是并行编译，后面的 `tee` 和 buildmeter 是 IMX-Forge 加的进度条，属于锦上添花，不影响构建逻辑本身。

```bash
# build-buildroot.sh 第 224-237 行（Step 3: 同步 target/ → release rootfs）
log_info "Step 3: Syncing target/ → ${RELEASE_ROOTFS}"
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

Step 3 是 IMX-Forge 自己加的——Buildroot 编完之后，把 `output/target/` 这个 rootfs 目录树 rsync 到 `out/release-latest/rootfs/`，供镜像打包脚本消费。你会发现那些 `--exclude` 分两类：一类是 Buildroot 构建期残留，`.stamp` 是 Buildroot 内部的 stamp 产物，host 上非特权用户删不掉；另一类是板子以 root 跑的时候会往 `var/lib/dhcp`（DHCP 租约）、`var/lib/seedrng`（随机种子）、`var/lib/misc`、`var/lib/network` 这些目录写的运行时文件，host 上非特权 rsync 同样删不掉。不排除掉的话 `--delete` 会直接失败，这一点真的坑了我半天。

## O= 输出目录全景：对着 IMX-Forge 逐目录讲

前面反复提到 `O=` 输出目录。Buildroot 默认把所有构建产物放在源码树里的 `output/`，但这会把源码树弄脏，而且没法用同一个源码树并行编多个配置。手册支持 out-of-tree 构建（`common-usage.adoc` → *Building out-of-tree*），IMX-Forge 也就用了它：

```bash
$ make O=/tmp/build menuconfig
```

手册还提醒一个坑：`O=` 如果传相对路径，它是相对于 Buildroot 源码目录解释的，不是相对于你的当前工作目录。所以最好养成习惯一律传绝对路径，千万别手滑传个相对路径进去。IMX-Forge 里全程用绝对路径：

```bash
# build-buildroot.sh 第 48 行
OUTPUT_DIR="${PROJECT_ROOT}/out/release-latest/buildroot"
```

也就是说 IMX-Forge 的所有 Buildroot 产物都落在 `out/release-latest/buildroot/` 下。接下来我们对这个目录逐层拆解，下面的变量名都来自 Buildroot 的顶层 Makefile，不是我编的：

```text
out/release-latest/buildroot/
├── .config               # 从 defconfig 展开来的完整配置
├── build/                # 各包的构建目录（解压、编译在这里发生）
├── host/                 # 主机侧工具 + sysroot
│   └── arm-none-linux-gnueabihf/
│       └── sysroot/      # ← 这就是 staging（交叉编译的"厨房"）
├── staging/              # 符号链接 → host/arm-none-linux-gnueabihf/sysroot
├── per-package/          # （仅 BR2_PER_PACKAGE_DIRECTORIES=y 时存在）
├── target/               # 最终 rootfs 目录树（要烧进板子的东西）
├── images/               # 最终生成的文件系统镜像（ext4 等）
├── dl/                   # 下载的源码包缓存
└── graphs/               # 依赖图、构建耗时图
```

我把 Makefile 里的定义原样贴出来，你可以对一下：

```makefile
# third_party/buildroot/Makefile 第 214-222 行
BUILD_DIR       := $(BASE_DIR)/build
BINARIES_DIR    := $(BASE_DIR)/images
BASE_TARGET_DIR := $(BASE_DIR)/target
PER_PACKAGE_DIR := $(BASE_DIR)/per-package
HOST_DIR        := $(BASE_DIR)/host
GRAPHS_DIR      := $(BASE_DIR)/graphs
```

其中 `BASE_DIR` 就是你的 `O=` 路径，也就是 `out/release-latest/buildroot`。我们逐个说。

`build/` 是各包的构建工作区。Buildroot 编一个包时，先把它的源码解压到 `build/<包名>-<版本>/` 里，然后在这个目录里 configure、make。你进去翻能看到解压后的源码树和编译产生的 `.o` 文件——出问题想看某个包到底是怎么编的，来这里就对了。`host/` 装的是主机侧的东西：Buildroot 自己用到的工具（比如 host-python、host-cmake），还有最关键的 sysroot。sysroot 是交叉编译器的"厨房"，所有要被别的包链接的库和头文件都放这儿。

`staging/` 是个符号链接，指向 `host/arm-none-linux-gnueabihf/sysroot`。这个指向关系来自 `package/Makefile.in`：

```makefile
# package/Makefile.in 第 127-128 行
STAGING_SUBDIR = $(GNU_TARGET_NAME)/sysroot
STAGING_DIR    = $(HOST_DIR)/$(STAGING_SUBDIR)
```

`GNU_TARGET_NAME` 对我们就是 `arm-none-linux-gnueabihf`，所以 `STAGING_DIR = host/arm-none-linux-gnueabihf/sysroot`。而 Makefile 第 468 行还做了个根目录下的快捷方式：

```makefile
# Makefile 第 468-470 行
STAGING_DIR_SYMLINK = $(BASE_DIR)/staging
$(STAGING_DIR_SYMLINK): | $(BASE_DIR)
	ln -snf $(STAGING_DIR) $(STAGING_DIR_SYMLINK)
```

这就是为什么你能用 `staging/` 这个短路径访问到 sysroot——它只是个软链接，本体在 `host/` 下面。

接下来是 `target/`，它是最终的 rootfs 目录树，这就是要烧进板子的东西。Buildroot 把所有包的运行时文件（二进制、`.so`、配置、脚本）都装到这儿。`build-buildroot.sh` 的 Step 3 就是把这个 `target/` 同步到 `out/release-latest/rootfs/`。`images/` 是最终镜像，如果你在 `fs/` 里配了 ext4、squashfs 之类的格式，Buildroot 会把 `target/` 打包成镜像文件放到这里。但 IMX-Forge 这里有点特殊，后面专门讲。

最后是 `dl/`，下载缓存。Buildroot 把每个包的源码 tarball 下到这儿，下次重建如果版本没变就直接复用，不用重新下载。想离线构建？手册说跑一次 `make source` 把 `dl/` 填满，断网也能编（`common-usage.adoc` → *Offline builds*）。

### ⚠️ 踩坑预警：target/ 不是你拿来直接用的 rootfs

事情到这里还没完。`target/` 目录里有个 Buildroot 故意放的文件叫 `THIS_IS_NOT_YOUR_ROOT_FILESYSTEM`，内容就是一句警告：这个目录是构建过程中的中间产物，千万别直接拿来当 rootfs 用。原因是它在 `target-finalize` 阶段之前还不完整——设备节点没建、某些权限没设对、库还没做最后的清理。

那 IMX-Forge 怎么用 `target/` 的？`build-buildroot.sh` 是在 `make` 完整跑完之后（包括 `target-finalize` 和 post-build 脚本）才去 rsync `target/` 的，这时候它已经是最终状态了。但你自己手动操作时，千万别在构建跑到一半就去 `target/` 里抠文件出来用——要么等 `make` 完整结束，要么直接用 `images/` 里的成品镜像，不然你会收获一个不完整的 rootfs，到时候查问题查到血压拉满。

## staging 和 target 为什么要装两份

讲到这里你可能有最大的一个疑问：为什么同一个库，Buildroot 要往 `staging/` 和 `target/` 里各装一份？这不是浪费空间吗？不是，这两份的用途完全不同。

`staging/`（也就是 `host/<arch>/sysroot`）是给交叉编译器看的。当 Buildroot 编一个依赖 zlib 的包时，交叉编译器要找到 zlib 的头文件（`.h`）和库（`.so`）才能链接。编译器去哪找？去 `--sysroot` 指向的地方找，而 `--sysroot` 指向哪？就是 staging：

```makefile
# toolchain/toolchain-wrapper.mk 第 17 行
TOOLCHAIN_WRAPPER_ARGS += -DBR_SYSROOT='"$(STAGING_SUBDIR)"'
```

所以 staging 里装的是开发态的东西——头文件、`.so` 符号链接、静态库（`.a`）、pkg-config 的 `.pc` 文件、libtool 的 `.la` 文件……这些是"编别的包时要用，但运行时不需要"的东西，交叉编译器靠它们才知道库的 API 长什么样、链接哪个版本。而 `target/` 是给板子运行的，这里面只放运行时真正需要的文件：二进制程序、动态库的 `.so` 实体、配置文件、启动脚本。开发态的头文件、静态库这些在板子上跑的时候根本用不到，不该出现在 rootfs 里白白占 flash 空间——Buildroot 在 `target-finalize` 阶段会做一轮清理，把 target 里不该有的开发文件剔掉。

所以"装两份"的本质是关注点分离。staging 存全量信息（含开发文件），服务于"如何让下一个包能链接到我"；target 只存运行时必需的东西，服务于"这块板子跑起来需要什么"。

举个具体例子帮你理解：你编了 zlib，staging 里会有 `include/zlib.h`（头文件）加 `lib/libz.so`（动态库符号链接）加 `lib/libz.a`（静态库）。而 target 里通常只有 `lib/libz.so.*`（动态库实体），没有头文件也没有静态库，因为板子上又不需要编代码，只要能 `dlopen` 到 zlib 就行。下一个要链接 zlib 的包去 staging 里找头文件和库就能找到，最终烧进板子的 rootfs 只带 target 里那份精简的运行时库。理解了 staging 和 target 的分工，你后面看任何 `.mk` 文件里的 `INSTALL` 逻辑都会豁然开朗：哪些文件装到 `$(STAGING_DIR)`、哪些装到 `$(TARGET_DIR)`，都是有讲究的。

## 为什么不设 BR2_LINUX_KERNEL 和 BR2_TARGET_UBOOT

讲完 Buildroot 的全貌，我们来聊一个 IMX-Forge 刻意做的设计决策。如果你看过别的 Buildroot 项目，会发现它们往往连内核和 U-Boot 一起在 Buildroot 里编——菜单里勾上 `BR2_LINUX_KERNEL=y`、`BR2_TARGET_UBOOT=y`，Buildroot 就把 kernel、bootloader、rootfs 三件套全包了。IMX-Forge 偏不，我们的 defconfig 开头就明说了这件事：

```text
# rootfs/buildroot/configs/imx6ull_aes_defconfig 第 1-5 行
# imx6ull_aes_defconfig — IMX-Forge buildroot rootfs for i.MX6ULL AES board
#
# buildroot 只构建 rootfs 用户空间(Stage 3+4);kernel/uboot 由 build_helper
# 外部构建,产物在 out/release-latest/{uboot,linux}/;镜像由 build_imx6ull_image.sh
# 从 out/release-latest/rootfs/ 组装。本 defconfig 不设 BR2_LINUX_KERNEL / BR2_TARGET_UBOOT。
```

整个 defconfig 通篇没有 `BR2_LINUX_KERNEL`，没有 `BR2_TARGET_UBOOT`，也没有任何 `BR2_TARGET_ROOTFS_EXT2` 之类的镜像格式选项。为什么？我们一个一个说。

第一个原因是 kernel 和 U-Boot 已经有专门的构建体系了。IMX-Forge 的 `scripts/build_helper/` 是一套双轨构建体系，kernel 和 U-Boot 各自有独立的构建脚本，产物分别落在 `out/release-latest/linux/` 和 `out/release-latest/uboot/`。这两块本来就跑得好好的，设备树、内核补丁、U-Boot 配置都已经在那套体系里磨合过了。让 Buildroot 再插一脚去编内核，只会引入两套并行的内核构建逻辑——同一个内核编两遍、配置可能打架、维护成本翻倍，纯属给自己找麻烦。

第二个原因是分工明确，各管一段，最后拼装。IMX-Forge 的整体构建分工是这样的：

```text
scripts/build_helper/         → kernel + uboot（外部构建）
rootfs/buildroot/             → 用户空间 rootfs（Buildroot，本教程主角）
scripts/image_builder/        → 把三部分组装成烧录镜像
    build_imx6ull_image.sh    → 从 out/release-latest/rootfs/ 打 ext4，拼 u-boot+kernel
```

Buildroot 编完吐到 `out/release-latest/rootfs/`，然后 `build_imx6ull_image.sh` 把 kernel、U-Boot、rootfs 三部分的产物拼在一起，生成最终的 SD/eMMC 烧录镜像。这种"各管一段、最后组装"的流水线比让 Buildroot 一把梭去包揽一切要干净得多——想单独替换 kernel？只跑内核那套脚本就行，rootfs 不用动。想换 rootfs 组件？只重跑 Buildroot，kernel 不用重新编。

第三个原因是镜像格式也更灵活。defconfig 末尾解释了为什么不设 `BR2_TARGET_ROOTFS_EXT2`：

```text
# rootfs/buildroot/configs/imx6ull_aes_defconfig 第 69-72 行
# 不用 buildroot 自带 ext2/ext4 镜像:它尺寸固定,加 Qt6 后需不断手调;
# 且最终 SD/eMMC 镜像由 build_imx6ull_image.sh 从 out/release-latest/rootfs/ 用
# mke2fs -d 现打(按实际内容动态尺寸,更灵活),NFS root 直接挂 rootfs/ 目录。
# 故 buildroot 只产 target/(→ rsync 到 rootfs/),不打 fs image。
```

Buildroot 自带的 ext4 镜像生成要在配置里写死尺寸，加了 Qt6 之后 rootfs 变大就得手动改尺寸，烦。而 `build_imx6ull_image.sh` 用 `mke2fs -d` 从 rootfs 目录现打镜像，尺寸按实际内容动态决定，不用预先估。另外 IMX-Forge 调试阶段常用 NFS root——直接把 `rootfs/` 目录挂到板子上，连镜像都不用打。所以 Buildroot 这边只产 `target/` 目录树（再 rsync 到 `rootfs/`），把"打镜像"这件事留给更专业的 `build_imx6ull_image.sh`。

一句话总结这个设计哲学：让 Buildroot 干它最擅长的事——自动构建用户空间 rootfs；内核、bootloader、镜像打包各自由专门的工具负责。这种克制的分工，正是 IMX-Forge 用 Buildroot 用得舒服的关键。

## 下一步

这一章我们把 Buildroot 的工作原理从头到尾捋了一遍：它是一堆自动化的 Makefile + Kconfig，源码树按 `toolchain/`、`package/`、`fs/` 各司其职，构建流水线分三步走（建目录 → 导入工具链 → 按 TARGETS 编，rootfs 镜像打包包含在第三步内），输出目录里 `staging/` 管编译期、`target/` 管运行期，IMX-Forge 则克制地只让 Buildroot 管用户空间这一段。

原理懂了，下一章我们就真正动手——[02 第一次构建 IMX-Forge rootfs](02_first_build.md) 会带你跑通 `build-buildroot.sh`，把第一个 Buildroot rootfs 编出来、烧进板子。我们会把构建过程的每个阶段对着这一章讲的原理再印证一遍，让你亲眼看一次"输出目录是怎么被填满的"。


