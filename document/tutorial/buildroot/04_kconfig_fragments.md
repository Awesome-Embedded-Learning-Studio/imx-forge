# 配置体系:Kconfig/menuconfig/fragments

::: info 本节你将学到
- Buildroot 的 Kconfig 配置体系:`Config.in` / `choice` / `select` / `depends on` 怎么互相约束,`.config`(全量)和 `defconfig`(最小)到底是什么关系
- `menuconfig` 怎么打开、改完怎么持久化(存回 `defconfig` 还是丢进 fragment),以及为什么推荐用 `make savedefconfig` 而不是直接提交 `.config`
- IMX-Forge 怎么用 fragment(`fragments/qt6.config`、`fragments/busybox.config`)按需把配置 merge 进 `defconfig`,`$(BR2_EXTERNAL_imxforge_PATH)` 这个变量是从哪冒出来的
- CI 靠 `compile-support-3rd-party` label 决定要不要编 Qt6,本地用 `build-buildroot.sh --with-qt6` 走同一条 merge 路径
:::

::: tip 前置知识 · 环境
- 已经读过本专栏的 [01 工作原理](./01_how_buildroot_works.md) 和 [02 第一次构建](./02_first_build.md),知道 Buildroot 在 IMX-Forge 里只管 rootfs 用户空间,kernel/uboot 由 `build_helper` 外部构建
- [03 External Toolchain](./03_external_toolchain.md) 里讲过的 `BR2_TOOLCHAIN_EXTERNAL_*` 那一坨配置,这章会拿它当 `.config` 的真实例子
- 对 Kconfig 有基本概念就行(看过内核的 `make menuconfig` 就算),细节我们边走边讲
:::

## 前言:为什么配置这一层值得单独拎出一章

在 [02 第一次构建](./02_first_build.md) 里我们一把跑通了 `build-buildroot.sh`,rootfs 就这么"变"出来了。说实话,跑通的那一下确实挺爽,但你合上终端没两分钟就会冒出一连串问题:我想加个 `htop`、想关掉 `ccache`、想让 BusyBox 多带个 `tc` applet,到底该改哪里?是直接编辑生成出来的 `.config`,还是去改那个 `imx6ull_aes_defconfig`?为什么 Qt6 明明写在仓库里却默认不编?`$(BR2_EXTERNAL_imxforge_PATH)` 这种变量又是从哪里冒出来的?

这些问题看起来东一榔头西一棒子,但它们都指向同一件事:Buildroot 的配置体系。Buildroot 用的就是内核那套 Kconfig,所以 `Config.in`、`menuconfig`、`defconfig`、`savedefconfig` 的玩法你多半眼熟;但 Buildroot 在这之上又叠了一层 br2-external 机制和 fragment 合并,加上 IMX-Forge 自己的构建脚本编排,完整链路就比单纯 `make menuconfig` 要绕一些。这一章我们把这些全拆开,每一步都落在仓库里的真实文件上,读完你就能自如地"改一处配置、知道它会影响什么、并且能把它持久化下来"。

## Kconfig 基础:Config.in / choice / select / depends on

Buildroot 的每一个配置选项(从架构选型到每一个 package)都用 Kconfig 语言描述,散落在无数个 `Config.in` 文件里。整体语法和内核完全一样,核心就四个关键字,我们一个一个说。

`config FOO` 定义一个符号 `FOO`,在 `.config` 里就是 `BR2_FOO=y` 或 `# BR2_FOO is not set`,Buildroot 的顶层符号几乎都以 `BR2_` 开头;紧跟一行 `bool` / `tristate` / `string` / `int` 声明它的类型,Buildroot 里 package 大多是 `bool`(编或不编,不像内核驱动还能编成模块)。

接下来是两条依赖关系,这是理解整张依赖图的钥匙。`depends on BAR` 是正向依赖,只有 `BAR` 满足时这个选项才出现、才可选,不满足时它在 menuconfig 里直接灰掉给你看;反过来 `select BAZ` 是反向依赖,选中本项时会强制把 `BAZ` 也选中,这就是为什么你勾一个 package,它依赖的一堆库会"自动冒出来"——根本不是什么魔法,是 `select` 在背后替你勾上的。

我们自己的 br2-external tree 里就有一个真实的例子,在 `rootfs/buildroot/Config.in`:

```makefile
# IMX-Forge buildroot external tree 配置入口
menuconfig BR2_PACKAGE_IMXFORGE
    bool "imxforge custom packages (placeholder)"
    help
      Placeholder for future IMX-Forge custom buildroot packages.
```

这里 `menuconfig` 是个"可展开成子菜单的 bool",顶层显示一行 `imxforge custom packages (placeholder)`,选中后才会进入它的子菜单。目前我们还没有自定义 package(到 [07 添加自定义 package](./07_custom_package.md) 才会往这里填东西),所以它只是个占位符,但结构是完整的:`config`/`bool`/`help` 三件套一个不少。

还有一个常被忽略的关键字 `choice`,专门处理"多选一"的场景,比如工具链选型、init 系统选型。我们的 defconfig 里 `BR2_INIT_BUSYBOX=y` 就是某个 `choice` 里的一个选项,选了它就不能同时选 `BR2_INIT_SYSTEMD`。`depends on` / `select` / `choice` 三者配合,就构成了 Buildroot 那张庞大的依赖图,这也是为什么你随手改一个开关,menuconfig 经常会连带弹出一堆新选项或灰掉一片。

理解了这层机制,你就明白 `make olddefconfig` 在干什么了:它根据 `Config.in` 里的依赖关系,自动把 `select` 指向的符号补齐、把不满足 `depends on` 的符号关掉,让 `.config` 处于一个自洽的状态。这一点在后面讲 fragment 合并时会反复用到,先记在心里。

## `.config`(全量) vs `defconfig`(最小):savedefconfig 干的事

跑完一次构建后,`out/release-latest/buildroot/.config` 会是一个全量配置——Buildroot 所有符号(几千个)全部列出来,每个要么 `=y`、要么 `is not set`、要么带个值。这个文件是 Kconfig 实际消费的对象,但它不适合提交进版本库。原因有二:一是太长、噪音太大,review 的时候根本看不出"你到底改了啥";二是 Buildroot 升级后,新符号的默认值会变,全量 `.config` 不会自动跟随,容易把旧行为悄悄锁死。

所以社区的做法是只维护一个最小化的 `defconfig`,只记录"和默认值不同的那些行"。这正是 `make savedefconfig` 干的事:它把当前 `.config` 里所有等于默认值的符号剔除,剩下的存成 `defconfig`。官方手册(`customize-configuration.adoc`)的原话是:

> The Buildroot configuration can be stored using the command `make savedefconfig`. This strips the Buildroot configuration down by removing configuration options that are at their default value.

推荐存放路径是 `configs/<boardname>_defconfig`,这样它会出现在 `make list-defconfigs` 列表里,也能用 `make <boardname>_defconfig` 直接加载。我们仓库里的就是 `rootfs/buildroot/configs/imx6ull_aes_defconfig`。

回过来看这个 defconfig,它确实只挑了"我们真正在意"的几块(精简后):

```makefile
# 架构
BR2_arm=y
BR2_cortex_a7=y
BR2_ARM_EABIHF=y
BR2_ARM_FPU_NEON_VFPV4=y

# 外部工具链(只写"关键差异",其余 select/默认由 olddefconfig 补)
BR2_TOOLCHAIN_EXTERNAL=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y
BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y
BR2_TOOLCHAIN_EXTERNAL_PATH="/opt/arm-gnu-toolchain"
BR2_TOOLCHAIN_EXTERNAL_GCC_15=y
BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_6=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y
...

# 系统、init、ccache
BR2_TARGET_GENERIC_GETTY_PORT="ttymxc0"
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
BR2_INIT_BUSYBOX=y
BR2_CCACHE=y
```

你会发现,除了 `BR2_arm=y` 这一组架构选项,这里既没有写工具链的每个 C 库特性,也没有把成百上千的 package 符号铺一遍——这些要么是默认值,要么是被 `select` 自动带出来的。你只要表达"我要什么",`make imx6ull_aes_defconfig` 这一个目标本身就会把最小 defconfig 展开成完整 `.config`(随后 Step 1c 的 `olddefconfig` 只在做工具链路径规范化时额外跑一次,并不参与"从 defconfig 还原全量"这一步)。这就是 defconfig 的精髓:可读、可 review、对 Buildroot 版本升级鲁棒。

::: details 为什么 defconfig 比全量 .config 更抗升级
假设 Buildroot 某个版本给 `BR2_PACKAGE_FOO` 加了一个子选项 `BR2_PACKAGE_FOO_BAR`,默认 `y`。你若提交全量 `.config`,里面会显式写 `BR2_PACKAGE_FOO_BAR=y`;等下个版本默认改成 `n` 了,你的 `.config` 仍然强制 `y`,行为就被悄悄锁死。而 defconfig 里没这一行(因为它等于当时的默认),升级后自然跟随新默认。所以"只记差异"不只是好看,更是防坑。
:::

## menuconfig 实操:改完怎么持久化

光看 defconfig 不够,实战中你会经常需要临场调几个开关。IMX-Forge 把这件事封装成了 `scripts/build_helper/buildroot_menuconfig.sh`,逻辑很直白:

```bash
# 首次进入:若无 .config,先应用 defconfig
if [[ ! -f "${OUTPUT_DIR}/.config" ]]; then
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" "${DEFCONFIG}"
fi

make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" menuconfig
```

第一次跑会先 `make imx6ull_aes_defconfig` 生成 `.config`,然后打开 ncurses 菜单。你在里面用方向键、空格、回车调选项,退出保存后改动落在 `out/release-latest/buildroot/.config` 里。

但请千万注意,这步只是改了 out 目录里的临时 `.config`,并没有写回 defconfig。下一次 `build-buildroot.sh --clean` 或者你手一抖删了 out 重建,改动就全没了。所以持久化是另一道工序,脚本为此提供了 `--savedefconfig`:

```bash
./scripts/build_helper/buildroot_menuconfig.sh --savedefconfig
```

它会在你退出 menuconfig 之后自动跑 `make savedefconfig`,然后把最小化结果拷回 br2-external tree:

```bash
make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" savedefconfig
cp "${OUTPUT_DIR}/defconfig" "${BR2_EXTERNAL_DIR}/configs/${DEFCONFIG}"
```

不加 `--savedefconfig` 的话,脚本退出时会提示你手动跑那条命令。那这里就有个取舍要做了:menuconfig 改出来的东西,到底该存回 `defconfig`(长期、对所有人都生效),还是只当一个临时 fragment?判断标准很简单——如果这个改动是这块板子的基本属性,比如换 getty 端口、开 ccache,那就存回 `defconfig`,让它对所有构建都生效;反过来如果是"按需可选"的特性,比如 Qt6 这种又大又可选的东西,就写成独立 fragment,构建时再决定要不要 merge 进来。前者用 `--savedefconfig`,后者就是我们下一节的重点,fragment 机制。

顺带一提,Buildroot 对子组件(BusyBox、内核、U-Boot、uClibc)也各有自己的配置文件和"存回"命令。手册里列了一串 helper target,我们这里实际用到的是 BusyBox:`make busybox-update-config` 会把改动存回 `BR2_PACKAGE_BUSYBOX_CONFIG` 指向的那个文件。这点马上就会看到。

## Fragment 机制:把 Qt6 按需 merge 进来

这是本章的重头戏。IMX-Forge 的 Qt6 是个庞然大物,`qt6base` 加上八个子模块(qml/多媒体/charts/串口/虚拟键盘……),全编下来 2-4 小时。显然不能把它塞进默认 defconfig,否则每次构建 rootfs 都得陪它耗着;但又不能完全不放仓库里,否则想编的时候根本无从下手。

解法就是 fragment:把 Qt6 的配置单独写在 `rootfs/buildroot/fragments/qt6.config` 里,默认构建不碰它;只有显式触发时,才把它 merge 进 `.config`。先看这个 fragment 长什么样:

```makefile
# qt6.config — Qt6 全模块 fragment
# buildroot 2026.02 原生 Qt6 = 6.9.1(= 项目原 qt-compile-pipeline 版本)。
# i.MX6ULL 无 GPU:linuxfb + tslib,关 XCB/EGLFS/OpenGL。

# 父项 + qt6base
BR2_PACKAGE_QT6=y
BR2_PACKAGE_QT6BASE=y
BR2_PACKAGE_QT6BASE_GUI=y
BR2_PACKAGE_QT6BASE_WIDGETS=y
BR2_PACKAGE_QT6BASE_LINUXFB=y        # FEATURE_linuxfb=ON(裸 framebuffer)
BR2_PACKAGE_QT6BASE_TSLIB=y          # FEATURE_tslib=ON(触摸校准)
BR2_PACKAGE_QT6BASE_NETWORK=y
BR2_PACKAGE_QT6BASE_XML=y
BR2_PACKAGE_QT6BASE_SQL=y
BR2_PACKAGE_QT6BASE_SQLITE=y
BR2_PACKAGE_QT6BASE_PNG=y
BR2_PACKAGE_QT6BASE_JPEG=y
BR2_PACKAGE_QT6BASE_GIF=y
BR2_PACKAGE_QT6BASE_FONTCONFIG=y
BR2_PACKAGE_TSLIB=y                  # qt6base TSLIB 依赖
BR2_PACKAGE_FONTCONFIG=y
BR2_PACKAGE_DEJAVU=y

# Qt6 子模块(对齐原 qt-compile-pipeline 八模块)
BR2_PACKAGE_QT6DECLARATIVE=y        # QML/QtQuick
BR2_PACKAGE_QT6DECLARATIVE_QUICK=y  # QtQuick
BR2_PACKAGE_QT6MULTIMEDIA=y         # FFmpeg + ALSA 后端,wm8960
BR2_PACKAGE_QT6CHARTS=y
BR2_PACKAGE_QT6SHADERTOOLS=y        # qt6declarative 依赖
BR2_PACKAGE_QT6SERIALPORT=y
BR2_PACKAGE_QT6VIRTUALKEYBOARD=y
BR2_PACKAGE_QT6CORE5COMPAT=y
```

你会发现它写得很"啰嗦":明明 `BR2_PACKAGE_QT6BASE_GUI` 这种在 Buildroot 的 `Config.in` 里可能 `select` 了 `QT6BASE`,为什么 fragment 还要显式全写出来?原因在于 fragment 的合并工具 `merge_config.sh` 只做"逐行设值",不会替你解 Kconfig 依赖。它把每一行原样写进 `.config`,至于这些值之间有没有矛盾、`select` 链是否完整,要靠紧接着的 `olddefconfig` 来兜底。显式写全的好处是 fragment 自包含、读起来一目了然,不依赖 Buildroot 内部 `select` 关系的隐式行为,这一招在排查"明明选了却没编进去"的时候能省你不少时间。

那合并动作具体在哪发生?在 `build-buildroot.sh` 里,由 `--with-qt6`(或环境变量 `BUILDROOT_QT6=1`)触发:

```bash
if [[ ${WITH_QT6} -eq 1 ]]; then
    QT6_FRAGMENT="${BR2_EXTERNAL_DIR}/fragments/qt6.config"
    ...
    log_info "Step 1b: Merging Qt6 fragment ($(basename "${QT6_FRAGMENT}"))"
    # merge_config.sh -m:把 fragment 合进 .config;olddefconfig 重解依赖(填 select)
    "${BUILDROOT_DIR}/support/kconfig/merge_config.sh" -m -O "${OUTPUT_DIR}" \
        "${OUTPUT_DIR}/.config" "${QT6_FRAGMENT}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" olddefconfig
fi
```

这两行是 fragment 机制的核心,我们拆开看。`merge_config.sh -m` 里的 `-m` 表示"只合并,不自动跑 make",它把第二个参数(qt6.config)里的每一行叠加到第一个参数(`.config`)之上——遇到 `BR2_X=y` 就设成 y,遇到 `# BR2_X is not set` 就关掉。合并完的产物只是一个"可能还不自洽"的 `.config`,直接拿去编大概率要出事。所以紧接着要跑一遍 `make olddefconfig`,把依赖关系重新解一遍:`select` 指向的符号被自动补齐、互相冲突的按规则取舍,最终得到一份干净、可构建的 `.config`。这就是脚本注释里"重解依赖(填 select)"的真正含义。

整个流程串起来就是:`defconfig` 先打底,fragment 可选地叠加上去,再由 `olddefconfig` 规范化,最后 `make`。Qt6 这种"又大又可选"的东西就这样挂在主流程旁边,要不要它只是一个开关的事。

::: tip 顺带说一句 busybox.config
同样是 `fragments/` 目录下的文件,`busybox.config` 的用法和 `qt6.config` 完全不一样。它不是被 `merge_config.sh` 合并的 fragment,而是一份完整的 BusyBox `.config`(1240 行、877 个 applet),通过 defconfig 里的 `BR2_PACKAGE_BUSYBOX_CONFIG` 直接指过去:
```makefile
BR2_PACKAGE_BUSYBOX_CONFIG="$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config"
```
Buildroot 编 BusyBox 时会拿它当输入配置,`make oldconfig` 会自动适配 BusyBox 版本差异。所以千万别被"都叫 config、都在 fragments/"误导——一个是 Kconfig 全量配置(busybox),一个是 buildroot 层的增量 fragment(qt6),机制完全不同。想改 BusyBox 选项,直接编辑这个文件,或用 `make busybox-update-config` 存回。
:::

## `$(BR2_EXTERNAL_imxforge_PATH)` 这个变量从哪来

你在 defconfig 和 fragment 里会反复看到一个神秘变量 `$(BR2_EXTERNAL_imxforge_PATH)`。比如:

```makefile
BR2_PACKAGE_BUSYBOX_CONFIG="$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config"
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_imxforge_PATH)/post-build.sh"
```

它不是凭空出现的,而是 Buildroot 的 br2-external 机制根据我们的 `external.desc` 自动生成的。这个文件只有两行:

```
name: imxforge
desc: IMX-Forge buildroot external tree — 定制 imx6ull-aes rootfs(defconfig/fragments/overlay/post-build)
```

官方手册(`customize-outside-br.adoc`)把生成规则讲得很清楚:

> `name`, mandatory, defines the name for that br2-external tree. That name must only use ASCII characters in the set `[A-Za-z0-9_]`. Buildroot sets the variable `BR2_EXTERNAL_$(NAME)_PATH` to the absolute path of the br2-external tree.

也就是说,`name: imxforge` 会让 Buildroot 自动定义一个变量 `BR2_EXTERNAL_imxforge_PATH`,它的值就是 br2-external tree 的绝对路径(即 `rootfs/buildroot/`)。这个变量在 Kconfig(defconfig 里)、Makefile、以及 post-build/post-image 脚本里都能用。手册还给了几个对应关系的例子:`FOO` 对应 `BR2_EXTERNAL_FOO_PATH`、`BAR_42` 对应 `BR2_EXTERNAL_BAR_42_PATH`,规律就是把 `name` 原样塞进 `BR2_EXTERNAL_<NAME>_PATH` 这个模板。

### 踩坑预警:name 必须精确匹配

⚠️ 这一块是真正的坑,一定确认看明白了。

这个变量是按 `external.desc` 里的 `name` 原样拼接的,大小写、下划线一个字符都不能错。常见的翻车姿势有这么两种:一种是把它写成大写 `$(BR2_EXTERNAL_IMXFORGE_PATH)`,结果找不到——因为 `name` 是小写 `imxforge`,变量名也必须是小写;另一种是手贱把 `external.desc` 里的 `name` 改成了 `imx_forge`,却忘了同步改 defconfig 里的变量,构建时 Buildroot 就会报找不到 `busybox.config`,因为变量名对不上、路径展开成了空。

所以一旦出现"明明文件就在那儿、Buildroot 却说找不到配置文件"这种诡异报错,第一反应就应该是去对一遍 `external.desc` 的 `name` 和变量名是否一致。这条规则对下一章要讲的 `Config.in`/`external.mk` 同样成立,它们也靠这个变量互相 source。这个坑我们到 [05 br2-external tree 逐文件](./05_br2_external_tree.md) 还会从另一个角度再讲一次。

手册里还有一条值得记住的约束:`name` 只能含 `[A-Za-z0-9_]`,连减号 `-` 都不行。所以别起名叫 `imx-forge`(项目的仓库名带减号),必须像现在这样用 `imxforge`。这也是为什么变量里是 `imxforge` 而不是 `imx-forge`。

## CI 怎么控制:compile-support-3rd-party label

理解了 fragment,CI 那边的逻辑就很好懂了。defconfig 里的注释把策略写得很明白:

```makefile
# ===== Qt6:由 fragments/qt6.config 提供(按需 merge)=====
# CI 默认最小 rootfs(无 Qt6,~15min);compile-support-3rd-party label 或本地
# build-buildroot.sh --with-qt6 触发 Qt6 全模块(2-4h)。见 fragments/qt6.config。
```

也就是说,默认情况下——包括 CI 的普通构建——`WITH_QT6=0`,只跑 defconfig 那一份最小配置,产出的是不含 Qt6 的精简 rootfs,大约 15 分钟搞定。这是为了保证每次 PR 的 CI 反馈够快,谁也不想开个 PR 改行注释还得等三小时。但只要某个 PR 打上了 `compile-support-3rd-party` label,CI 任务就会设 `BUILDROOT_QT6=1`,于是脚本里 `[[ "${BUILDROOT_QT6:-0}" == "1" ]] && WITH_QT6=1` 成立,触发上面那段 `merge_config.sh` + `olddefconfig`,把 Qt6 全模块编进去。

本地想复现 Qt6 构建,完全走同一条路:

```bash
./scripts/build_helper/build-buildroot.sh --with-qt6
# 或者
BUILDROOT_QT6=1 ./scripts/build_helper/build-buildroot.sh
```

两种写法等价,因为脚本开头就是 `[[ "${BUILDROOT_QT6:-0}" == "1" ]] && WITH_QT6=1`。这样设计的好处是 CI 和本地是同一套机制,fragment 是唯一的真值来源,`--with-qt6` 只是个开关,不存在"CI 有一套魔法、本地另一套"的割裂感。

事情到这里还没完,我们把完整的 build 流程在 `build-buildroot.sh` 里的顺序捋一遍,正好把这一章的所有概念都串起来。第一个跑的是 Step 1,`make imx6ull_aes_defconfig` 把最小 defconfig 展开成 `.config`,此时 `BR2_TOOLCHAIN_EXTERNAL_PATH` 还是 defconfig 里写死的 `/opt/arm-gnu-toolchain`。紧接着 Step 1c,脚本探测 PATH 里真实的工具链位置,用 `sed` 改写 `.config` 里的工具链路径,再跑一遍 `olddefconfig` 规范化;这一步之所以用 sed 而不是 `make BR2_TOOLCHAIN_EXTERNAL_PATH=...`,是因为绝大多数 `BR2_` 配置符号不能用 `make BR2_X=Y` 在命令行覆盖——Kconfig 的 `conf` 工具只读 `.config`、不读 make 变量,所以工具链路径只能靠 sed 改 `.config` 再 olddefconfig(个别变量如 `BR2_DEFCONFIG` 是 Buildroot Makefile 专门拦截处理的例外,本章不展开),这是新手常踩的坑。如果加了 `--with-qt6`,中间还会多一个 Step 1b:`merge_config.sh -m` 合并 qt6.config,再 `olddefconfig` 重解依赖。最后 Step 2 是 `make -j$(nproc)` 正式构建,Step 3 把 `target/` rsync 到 `out/release-latest/rootfs/`。

每一步都对应本章讲的一个概念:defconfig 展开、olddefconfig 规范化、fragment 合并、绝大多数 `BR2_` 符号不能在 make 命令行覆盖。把这些串起来,IMX-Forge 的 Buildroot 配置链路就完整了。

## 小结

我们这一章把 Buildroot 的配置体系从底到顶捋了一遍:Kconfig 的 `Config.in`/`select`/`depends on` 提供依赖图,`.config` 是全量、`defconfig` 是最小差异(靠 `savedefconfig` 生成),`menuconfig` 用来临场调整、改完用 `--savedefconfig` 存回,而 Qt6 这种大块头则交给 fragment(`merge_config.sh -m` + `olddefconfig`)按需 merge。那条贯穿始终的 `$(BR2_EXTERNAL_imxforge_PATH)` 变量,由 `external.desc` 的 `name` 字段自动派生,名字必须精确匹配、且只能含字母数字下划线。掌握这些,日常 90% 的 rootfs 定制需求,改 defconfig 或加个 fragment 就能搞定。

## 下一步

配置会存了、fragment 会合了,但 br2-external tree 本身——那个 `external.desc`、`Config.in`、`external.mk`、`configs/`、`overlay/`、`post-build.sh` 组成的小世界——我们还没逐个文件拆过。下一章我们就钻进去,看每一份文件各自承担什么角色、为什么 IMX-Forge 的 br2-external tree 长成现在这个样子。

→ [05 br2-external tree 逐文件](./05_br2_external_tree.md)
