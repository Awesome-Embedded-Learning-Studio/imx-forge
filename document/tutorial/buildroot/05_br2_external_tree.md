# br2-external tree 逐文件

::: info 本节你将学到
- br2-external tree 到底是什么、Buildroot 为什么要搞这么一层"外部树"机制,以及它怎么让我们在不碰 submodule 源码的前提下注入全部定制
- IMX-Forge 的 br2-external tree 里每一个文件(`external.desc` / `Config.in` / `external.mk` / `configs/` / `fragments/` / `overlay/` / `post-build.sh`)各自扮演什么角色、为什么 IMX-Forge 的 tree 长成现在这个样子
- `$(BR2_EXTERNAL_imxforge_PATH)` 这个贯穿 defconfig 的变量是怎么由 `external.desc` 自动派生出来的,名字写错会炸在哪里
- overlay 和 post-build.sh 这两条定制路径的本质区别——一个是"静态文件叠加"、一个是"脚本运行",以及 post-build.sh 里那几个"Buildroot 默认不给、但板子必须要"的补丁为什么不能省
:::

::: tip 前置知识 · 环境
- 已经读完 [04 配置体系](./04_kconfig_fragments.md),对 defconfig、fragment、`$(BR2_EXTERNAL_imxforge_PATH)` 有基本印象,知道 `make savedefconfig` 和 `merge_config.sh` 各自干什么
- 跑通过至少一次 `./scripts/build_helper/build-buildroot.sh`,对 `out/release-latest/buildroot/` 的产物结构有点手感
- 对 br2-external 听过名字就行,细节我们这章从头拆
:::

## 前言:我们一直在用一个还没打开过的盒子

前面几章里,`$(BR2_EXTERNAL_imxforge_PATH)` 这个变量我们已经见过不下五六次了——defconfig 里指 busybox.config、指 overlay、指 post-build.sh,到处都是它。`build-buildroot.sh` 每次跑 `make` 都要带一个 `BR2_EXTERNAL=...` 参数。但你如果现在打开 `rootfs/buildroot/` 这个目录逛一圈,会发现它其实就那么几个文件,加起来还没一个 defconfig 长。

这个看起来不起眼的小目录,就是 IMX-Forge 全部 rootfs 定制的"大脑"。Buildroot 源码本身在 `third_party/buildroot/` 里是个 submodule、pin 死在 2026.02,我们一行都不去改它;所有"这块板子特有的东西"——defconfig、配置 fragment、文件覆盖、构建后脚本——全挂在 `rootfs/buildroot/` 这棵 br2-external tree 上,通过 Buildroot 的 `BR2_EXTERNAL` 机制注入。这样做的好处很直接:升级 Buildroot 只需要挪 submodule 指针,我们的定制完全不会和上游冲突,也不会被一次 `git submodule update` 冲掉。

上一章我们重点讲的是配置"怎么写、怎么存、怎么 merge",相当于学会了往这棵树里塞东西的语法。这一章我们要换个角度,把这棵树本身拆开,逐个文件看清楚它为什么是这样组织的、每个文件各自承担什么职责。读完之后,你再看到 `rootfs/buildroot/` 这个目录,就不会觉得它是一堆散文件,而是一张职责清晰的分工图。

## br2-external 到底是什么:把定制留在树外

在逐文件拆解之前,我们先把 br2-external 这个机制本身讲明白,不然后面每个文件"为什么在那儿"你会觉得没来由。

Buildroot 的全部源码、全部默认 package、全部 defconfig 模板,都在它自己的源码树里。你要加一个自己的 package、改一个自己的 defconfig,最直白的办法当然是直接改 Buildroot 的源码——但这会让你的定制和上游版本死死耦合,下次升级 Buildroot 就是一场 merge 冲突的灾难。社区给的标准答案就是 **br2-external tree**:你在外面维护一棵独立的小目录,只要里面放一个 `external.desc` 声明"我叫某某",Buildroot 就会把这棵目录当成自己的一部分来扫描——里面的 `Config.in` 会被 source 进主菜单、`configs/*.defconfig` 会出现在 `make list-defdeps` 列表里、`external.mk` 会被 include 进 Makefile 体系。

注入的方式就是在每次 `make` 的时候带上 `BR2_EXTERNAL=<path>`,你看 `build-buildroot.sh` 里每一条 make 命令都带着它:

```bash
make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" "${DEFCONFIG}"
```

这里 `BR2_EXTERNAL_DIR` 就是 `rootfs/buildroot/` 的绝对路径。脚本甚至在动手之前会先确认这棵树的身份证在不在:

```bash
if [[ ! -f "${BR2_EXTERNAL_DIR}/external.desc" ]]; then
    log_error "BR2_EXTERNAL tree missing external.desc: ${BR2_EXTERNAL_DIR}"
    exit 1
fi
```

没有 `external.desc`,Buildroot 压根不认这棵树,后面所有的 `$(BR2_EXTERNAL_imxforge_PATH)` 都会展开成空字符串,构建必然崩。所以这个文件就是整棵树的"入口门票",我们接下来就先从它讲起。

## external.desc:整棵树的身份证

整棵 br2-external tree 里最短、但也最关键的文件,就是 `external.desc`。它只有两行:

```
name: imxforge
desc: IMX-Forge buildroot external tree — 定制 imx6ull-aes rootfs(defconfig/fragments/overlay/post-build)
```

第一行 `name` 是 Buildroot 强制要求的,它定义了这棵 br2-external tree 的名字。这个名字不是写给你看的——`desc` 那行才是给人读的描述——`name` 是写给 Buildroot 的机器标识,Buildroot 拿它去派生一大堆东西。官方手册(`customize-outside-br.adoc`)的原话讲得很清楚:

> `name`, mandatory, defines the name for that br2-external tree. That name must only use ASCII characters in the set `[A-Za-z0-9_]`. Buildroot sets the variable `BR2_EXTERNAL_$(NAME)_PATH` to the absolute path of the br2-external tree.

也就是说,我们这里写 `name: imxforge`,Buildroot 就会自动定义一个 Kconfig/Makefile 变量 `BR2_EXTERNAL_imxforge_PATH`,它的值就是这棵树的绝对路径。你在 defconfig 里反复看到的 `$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config`、`$(BR2_EXTERNAL_imxforge_PATH)/overlay`,就是这么展开成 `rootfs/buildroot/fragments/busybox.config` 的。这个变量不需要你手动 export,也不需要你在任何地方声明,`external.desc` 一被 Buildroot 读到它就自动有了。

### 踩坑预警:name 必须精确匹配,而且不能用减号

这个变量是 Buildroot 按 `external.desc` 里的 `name` **原样拼接**出来的,大小写、下划线一个字符都不能错。常见的翻车姿势有这么几种:把变量写成大写的 `$(BR2_EXTERNAL_IMXFORGE_PATH)`——找不到,因为 `name` 是小写的 `imxforge`,Buildroot 拼出来的是混合大小写;或者哪天手痒把 `external.desc` 里的 `name` 改成了 `imx_forge`,却忘了同步去改 defconfig 里的变量名——构建时 Buildroot 就会报找不到 `busybox.config`,因为变量名对不上、路径展开成空。

⚠️ 这里千万确认一件事:手册里明确约束 `name` 只能含 `[A-Za-z0-9_]`,**连减号 `-` 都不行**。所以千万别把它起成 `imx-forge`(我们项目的仓库名带减号),必须像现在这样写成 `imxforge`。这也是为什么变量里是 `imxforge` 而不是 `imx-forge`——这不是随手写的,是被 Buildroot 的命名规则逼出来的。

日后你只要遇到"明明文件就在那儿、Buildroot 却说找不到配置文件"这种诡异报错,第一反应就应该是去对一遍 `external.desc` 的 `name` 和你在 defconfig/脚本里写的变量名是否一字不差。这个坑我们在上一章从配置的角度讲过一次,这里从 tree 组织的角度再强调一遍,因为它确实是 br2-external 最容易让人血压拉满的地方。

## Config.in 与 external.mk:两个安静的占位

讲完身份证,接下来这两个文件目前都是"占位"状态,但我们还是得说清楚它们的位置和职责,不然你以后想加自定义 package 的时候会不知道往哪儿下手。

先看 `Config.in`。Buildroot 在 source 主菜单的时候,会顺带把每棵 br2-external tree 根目录下的 `Config.in` 也 source 进去,这样你就能在 `make menuconfig` 里看到一个属于你自己的子菜单。我们这个文件目前长这样:

```makefile
# IMX-Forge buildroot external tree 配置入口
#
# buildroot 只构建 rootfs 用户空间(Stage 3+4);kernel/uboot 由 build_helper 外部提供。
# 当前无自定义 package;defconfig 与 fragment 在 configs/ 与 fragments/ 下。

menuconfig BR2_PACKAGE_IMXFORGE
	bool "imxforge custom packages (placeholder)"
	help
	  Placeholder for future IMX-Forge custom buildroot packages.
```

它定义了一个 `menuconfig BR2_PACKAGE_IMXFORGE`,也就是一个可以展开成子菜单的 bool 选项。如果你现在跑 `make menuconfig`,会在菜单里看到一行 `imxforge custom packages (placeholder)`,点进去是个空菜单。之所以保留它,是因为将来我们要往 br2-external tree 里加自己的 package(比如一个板端的应用程序、一个自写的库),那些 package 的 `Config.in` 就会挂在这个菜单底下。这件事我们留到 [07 添加自定义 package](./07_custom_package.md) 再展开,现在它先占个位,证明这条入口是通的。

再看 `external.mk`,它更简单,注释加起来才两行:

```makefile
# IMX-Forge buildroot external tree
# 当前无自定义 package 构建逻辑;本文件由 buildroot 自动 include,留空即可。
```

Buildroot 会把这棵 tree 的 `external.mk` 自动 include 进它的 Makefile 体系。如果你有自己的 package,这个文件里会写诸如 `$(eval $(generic-package))` 之类的构建逻辑(到第七章你会看到完整套路)。我们目前没有任何自定义 package 要编——rootfs 里的东西要么是 Buildroot 自带的 package(busybox、alsa-lib、eudev),要么是 overlay 里的静态文件,要么是 post-build.sh 运行时下载的——所以这个文件就老老实实留空。它的存在本身就是意义:Buildroot 找它、include 它,哪怕里面什么都没有。

你会发现这两个文件现在的状态都是"为了结构完整而存在"。这其实是 br2-external tree 一个很正常的发展阶段:骨架先搭好,等业务需要了再往里填肉。先别急着觉得它们多余——等你到第七章真的要加 package 时,会庆幸这两个入口早就准备好了。

## configs/:defconfig 的家

`configs/` 目录里放的就是我们在 [04 配置体系](./04_kconfig_fragments.md) 里反复提到的那份 `imx6ull_aes_defconfig`。Buildroot 的规则是,放在 br2-external tree 的 `configs/` 下的 `*_defconfig` 文件,会自动出现在 `make list-defconfigs` 的列表里,可以用 `make <name>_defconfig` 直接加载。我们的 `imx6ull_aes_defconfig` 就是这么被 `build-buildroot.sh` 的 Step 1 加载的:

```bash
make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" imx6ull_aes_defconfig
```

这条命令能让 Buildroot 在两棵树(自己的源码树 + 我们的 br2-external tree)的 `configs/` 下都去找 `imx6ull_aes_defconfig`,找到后展开成 `out/release-latest/buildroot/.config`。

defconfig 的具体内容我们在 [03 External Toolchain](./03_external_toolchain.md) 里拆过工具链那一坨、在 [04 配置体系](./04_kconfig_fragments.md) 里讲过它和 fragment 的关系,这里不重复。但从"tree 组织"的角度,有一件事值得专门拎出来看——这份 defconfig 里好几处都用 `$(BR2_EXTERNAL_imxforge_PATH)` 指向了同一棵 tree 里的其他文件:

```makefile
BR2_PACKAGE_BUSYBOX_CONFIG="$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config"
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_imxforge_PATH)/post-build.sh"
```

这就是 br2-external tree 最优雅的地方:它让 defconfig 可以用相对自身位置的路径去引用同一个 tree 里的兄弟文件,而不用写死绝对路径。不管你这棵 tree 被 clone 到哪台机器、哪个目录,只要 `external.desc` 的 `name` 没变,所有引用都自动正确。你换台机器构建,根本不用去 sed 一堆硬编码路径——这一点在手搓 rootfs 时代是想都不敢想的。

另外,这份 defconfig 里有一条贯穿始终的设计纪律值得记住:它**不设 `BR2_LINUX_KERNEL`、不设 `BR2_TARGET_UBOOT`**。文件开头的注释把这件事讲得很明白——Buildroot 在 IMX-Forge 里只负责 rootfs 用户空间(Stage 3+4),kernel 和 U-Boot 由 `scripts/build_helper/` 那套双轨体系外部构建,产物落在 `out/release-latest/{uboot,linux}/`,最后由 `build_imx6ull_image.sh` 把三部分拼成烧录镜像。让 Buildroot 只干它该干的那一段,比让它一把梭去编内核要干净得多,这也是整棵 tree 组织方式的基调。

## fragments/:两份"同名不同命"的配置

`fragments/` 目录下有两个文件:`busybox.config` 和 `qt6.config`。它们都叫 config、都放在同一个目录下,看起来像是同一类东西,但机制其实完全不同——这个坑我们在上一章的末尾提过一句,这里从 tree 组织的角度再把它钉死,因为新手几乎一定会被这个命名误导。

`busybox.config` 是一份**完整的 BusyBox `.config`**,一千多行、八百多个 applet 的全量配置。它在 defconfig 里是通过 `BR2_PACKAGE_BUSYBOX_CONFIG` 直接指过去的:

```makefile
BR2_PACKAGE_BUSYBOX_CONFIG="$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config"
```

Buildroot 编 BusyBox 的时候,会拿这份文件当输入配置,相当于"BusyBox 用哪套选项,全由这个文件说了算"。你想加减一个 applet,直接编辑这个文件就行,或者跑 `make busybox-update-config` 把 menuconfig 的改动存回来。

`qt6.config` 则完全是另一种东西。它是 Buildroot 层的一个**增量 fragment**,里面只写"和默认值不同的那几行":

```makefile
BR2_PACKAGE_QT6=y
BR2_PACKAGE_QT6BASE=y
BR2_PACKAGE_QT6BASE_GUI=y
BR2_PACKAGE_QT6BASE_LINUXFB=y        # FEATURE_linuxfb=ON(裸 framebuffer)
BR2_PACKAGE_QT6BASE_TSLIB=y          # FEATURE_tslib=ON(触摸校准)
...
```

它不是被某个 `BR2_PACKAGE_*_CONFIG` 指过去的,而是在构建时由 `merge_config.sh -m` 叠加到 `.config` 上、再用 `olddefconfig` 重解依赖。这件事默认不发生,只有你显式 `--with-qt6` 或 CI 打了 `compile-support-3rd-party` label 才会触发。

所以千万别被"都叫 config、都躺在 fragments/"这个表象骗了。一个是子组件的全量 Kconfig 配置(busybox),一个是 Buildroot 顶层的增量配置(qt6),合并方式、触发时机、生效路径全都不一样。把它们放在同一个 `fragments/` 目录下,纯粹是因为"都是配置类的散件",并不代表它们是同一种机制。理解了这个区别,你以后往 `fragments/` 里加东西的时候,就知道该仿照哪一个了。

## overlay/:静态文件叠加层

讲完配置类的文件,接下来是两个"定制文件系统本身"的机制,我们先看简单的一个——`overlay/`。

Buildroot 提供了一个叫 `BR2_ROOTFS_OVERLAY` 的配置项,你给它一个目录路径,Buildroot 在构建过程中会把那个目录的内容**原样叠加**到 rootfs 的 target 目录上(同名文件覆盖)。我们的 defconfig 里这么写:

```makefile
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"
```

这个机制特别适合放那些"不需要任何逻辑、复制进去就行"的东西。比如你想往 rootfs 里塞一个自定义的 `/etc/rc.local`、一段开机播放的视频、一个写好的配置文件,只要在 `overlay/` 里照着 rootfs 的目录结构建好对应路径,Buildroot 构建的时候会自动帮你 rsync 进去,完全不用写脚本。

不过你打开我们现在的 `overlay/` 会发现它几乎是空的,只有一个 README 在解释它的用途:

> buildroot `BR2_ROOTFS_OVERLAY` 源目录。构建时本目录内容会叠加到 rootfs target(覆盖同名文件),替代原 `scripts/merge_overlay_rootfs.sh` 的运行时 cp 合并。

这里的"替代原 `merge_overlay_rootfs.sh`"是个有故事的来由。IMX-Forge 早期手搓 rootfs 的时候,我们自己写过一个 `merge_overlay_rootfs.sh` 脚本,在构建完之后用一堆 `cp` 命令把 overlay 目录合进 rootfs。那套路子能用,但每次加文件都要改脚本、维护一份"哪个文件复制到哪儿"的映射,非常容易漏。换成 Buildroot 原生的 `BR2_ROOTFS_OVERLAY` 之后,这件事变成了"丢进 overlay 目录就完事",脚本那一层直接消失。这又是一个"重复造轮子最后换回原生机制"的例子。

目前 `overlay/` 预留着,后续要往 rootfs 里加静态文件(比如自定义的 etc 配置、板端应用脚本),直接丢进来就行。但如果你要干的事情需要"判断条件"——比如"只有 rootfs 里有 Qt6 才下载中文字体"——overlay 就搞不定了,因为它是无脑复制,不会管 target 里有什么。这种需要逻辑的活儿,就轮到下一个文件出场了。

## post-build.sh:Buildroot 默认不给的,我们补

这是整棵 br2-external tree 里最长、也最能体现"为这块板子量身定制"的文件。`post-build.sh` 对应 defconfig 里的:

```makefile
BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_imxforge_PATH)/post-build.sh"
```

Buildroot 在 `make` 过程中、rootfs 打包之前,会调用这个脚本,并且把 target 目录(也就是 `output/target`,即将变成 rootfs 的那个目录树)作为第一个参数 `$1` 传进来。所以这个脚本的角色就是:在 rootfs 即将定型的前一刻,对它做最后的修补。

为什么需要这么一道工序?因为 Buildroot 的默认 skeleton 是通用的,它照顾不到每块板子的特殊需求;而我们这块 i.MX6ULL 板子有一堆"Buildroot 默认不给、但上板必须要"的东西。这个脚本一口气补了四类,我们一类一类来看。

### 补丁一:linuxrc 软链,给 NFS 和老式 init 留兼容

脚本拿到 target 目录之后,第一件事是补一个 `linuxrc` 软链:

```bash
# ① linuxrc 软链(仅当 busybox 已装且 linuxrc 不存在)
if [[ -x "${TARGET_DIR}/bin/busybox" && ! -e "${TARGET_DIR}/linuxrc" ]]; then
    echo "[post-build] Creating linuxrc -> bin/busybox"
    ln -sf bin/busybox "${TARGET_DIR}/linuxrc"
fi
```

这里的背景是,Buildroot 的默认 skeleton 不会在根目录建 `linuxrc` 这个软链。但有些启动方式——尤其是 NFS root 挂载、或者老式的 init 实现——会去根目录找 `/linuxrc` 作为内核挂载 rootfs 后执行的第一个程序。找不到它,启动链路就可能断在这一步。BusyBox 本身是支持当 init 用的,所以我们只需要在根目录建一个指向 `bin/busybox` 的软链,把"入口"补上就行。

注意这里有个条件判断:`&& ! -e "${TARGET_DIR}/linuxrc"`,意思是只有当 linuxrc 不存在时才建。这是为了幂等——重复跑构建不会报错,也不会覆盖掉可能已经存在的正确链接。

### 补丁二:home 目录,Buildroot 用 root 当家

接下来是两个小修补,先看建 home 目录:

```bash
# ② 补建 buildroot skeleton 不保证、但项目期望的目录
mkdir -p "${TARGET_DIR}/home"
```

这件事乍一看很不起眼,但它背后有个 Buildroot 的设计取向:Buildroot 的默认 skeleton 用 `/root` 作为 root 用户的家目录,根本不建 `/home`。而我们项目里有些校验脚本(后面要跑的那个 varified 闸门)期望 rootfs 里有 `/home` 这个目录存在。`mkdir -p` 一行就能补上,既不影响 Buildroot 原来的设计,又满足了我们的额外期望。

### 补丁三:securetty,不补它 root 一个都登不上

这个补丁是整个 post-build.sh 里最能救人命的,我们先看代码:

```bash
# ②-bis /etc/securetty:项目 busybox.config 带 CONFIG_FEATURE_SECURETTY=y,login 要求
#     该文件列出允许 root 登录的 tty;buildroot skeleton 不建它 → root 登录被全拒。
#     补全常用串口/控制台(ttymxc0 是 imx6ull 调试串口)。
if [[ ! -f "${TARGET_DIR}/etc/securetty" ]]; then
    printf '%s\n' console tty1 tty2 tty3 tty4 tty5 tty6 \
        ttyS0 ttyS1 ttymxc0 ttymxc1 ttymxc2 ttyAMA0 ttyUSB0 \
        > "${TARGET_DIR}/etc/securetty"
fi
```

⚠️ 这里的坑真的坑过我半天,新手几乎一踩一个准。事情是这样的:我们那份 `busybox.config` 里开了 `CONFIG_FEATURE_SECURETTY=y`,这个选项会让 BusyBox 的 `login` 程序在 root 登录时去读 `/etc/securetty`,只有登录终端(tty)列在这个文件里,才允许 root 登录。这本是个合理的安全特性——但 Buildroot 的默认 skeleton 根本不建 `/etc/securetty` 这个文件。

结果就是:rootfs 构建出来一切正常,烧到板子上串口也出启动日志,可你一敲 root 想登录,直接被弹回来,让你输密码都进不去。串口、telnet、哪儿都一样——因为那个文件不存在,等于没有任何一个 tty 被"允许",root 登录被全拒。你对着一个能启动但登不进去的板子,真的会血压拉满。

解法就是 post-build.sh 干的这件事:在 rootfs 定型前补一个 `/etc/securetty`,把常用的终端都列进去。重点要确认 `ttymxc0` 在里面——那是 i.MX6ULL 的调试串口,我们 defconfig 里 `BR2_TARGET_GENERIC_GETTY_PORT="ttymxc0"` 用的就是它。没有这一行,你板子的串口登录就是死的。

这个补丁完美诠释了"为什么要 post-build.sh"——它不是简单的复制文件(虽然这个 case 看起来像),而是要理解"BusyBox 开了什么选项、Buildroot skeleton 缺了什么、两者凑在一起会炸成什么样",然后用一个针对性的修补把这条链路接上。

### 补丁四:SDMA 固件和 CJK 字体,按需下载

接下来这段是 post-build.sh 里逻辑最绕的部分,它干了两件"从网上下载东西塞进 rootfs"的活,而且都是"按需"的——要根据 rootfs 里实际有什么来决定下不下载。

第一件是 i.MX 的 SDMA 固件:

```bash
# ③ i.MX SDMA 固件:SDMA 驱动(音频 dma 等)运行时需要,从 armbian firmware 仓库下载。
IMX_FW_DIR="${TARGET_DIR}/lib/firmware/imx/sdma"
FW_CACHE="${PROJECT_ROOT}/out/.firmware-cache"
mkdir -p "${IMX_FW_DIR}" "${FW_CACHE}"
if [[ ! -s "${FW_CACHE}/sdma-imx6q.bin" ]]; then
    echo "[post-build] Downloading sdma-imx6q.bin..."
    if ! curl -fL --retry 3 --connect-timeout 30 -o "${FW_CACHE}/sdma-imx6q.bin" \
        "https://github.com/armbian/firmware/raw/master/imx/sdma/sdma-imx6q.bin"; then
        echo "[post-build] WARN: sdma-imx6q.bin 下载失败(网络/代理?),rootfs 将不含 SDMA 固件" >&2
        rm -f "${FW_CACHE}/sdma-imx6q.bin"
    fi
fi
[[ -s "${FW_CACHE}/sdma-imx6q.bin" ]] && cp -a "${FW_CACHE}/sdma-imx6q.bin" "${IMX_FW_DIR}/"
```

i.MX6ULL 的 SDMA 引擎(音频 DMA、一些外设的数据搬运都靠它)在运行时需要一份固件 `sdma-imx6q.bin`,内核驱动会去 `/lib/firmware/imx/sdma/` 下找。Buildroot 不会自动给你塞这份固件,所以我们在这个脚本里从 armbian 的 firmware 仓库下载。这里有几个设计细节值得品:一是用了 `out/.firmware-cache` 做缓存,这样重复构建不会反复下载;二是下载失败只是告警(`echo ... >&2`)而不是中止构建,因为网络问题不该阻塞 rootfs 本身的产出,大不了上板后 SDMA 驱动报个缺固件的警告,rootfs 完整性不受影响。

第二件是中文字体和 Emoji 字体,这段更讲究"按需":

```bash
# ③-bis Noto CJK + Emoji 字体:仅当 rootfs 含 Qt6 时下载(Qt GUI 才需;最小 rootfs
#      无 Qt6 → 跳过省 ~30MB)。
if [[ -f "${TARGET_DIR}/usr/lib/libQt6Core.so" ]]; then
    # ... 下载 NotoSansCJK-Regular.ttc 和 NotoColorEmoji.ttf 到 /usr/share/fonts/
else
    echo "[post-build] Qt6 not in rootfs — 跳过 CJK/Emoji 字体(最小 rootfs)"
fi
```

注意那个判断条件 `if [[ -f "${TARGET_DIR}/usr/lib/libQt6Core.so" ]]`——它去 target 目录里找 Qt6 的核心库,只有存在(也就是这次构建带了 Qt6)才下载中文字体。这是一个很聪明的做法:最小 rootfs(不带 Qt6)根本不需要 GUI 字体,省下三十多兆;只有 `--with-qt6` 触发的完整构建才会把字体拉下来。这种"根据 rootfs 实际内容决定补什么"的逻辑,正是 overlay 做不到、必须用 post-build.sh 脚本的原因——overlay 是无脑复制,而这个脚本能"看菜下饭"。

这两段下载逻辑也都有一个共同特点:下载和缓存都在 `out/` 目录里做,不会污染 br2-external tree 本身。tree 里的脚本只是"指令",真正产生的副作用(缓存文件、下载产物)都落在 out 里,符合"tree 是声明式的、out 是构建产物"这个分层。

### 最后一关:varified 校验闸门

补完所有东西,脚本最后一步是一道硬闸门:

```bash
# ④ 校验闸门(致命;失败则 buildroot make 中止)
echo "[post-build] Running rootfs verification gate..."
bash "${PROJECT_ROOT}/scripts/varified_rootfs_ok.sh" --rootfs-dir="${TARGET_DIR}"
```

它调用项目自己的 `varified_rootfs_ok.sh` 脚本,对 target 目录做一遍完整性校验(检查关键文件在不在、目录结构对不对)。这个脚本开头有 `set -e`,所以 varified 一旦失败,post-build.sh 立刻非零退出,Buildroot 的 `make` 也会跟着中止——也就是说,一份不完整的 rootfs 根本没机会走到打包那一步。这是 issue #76 留下来的纪律:rootfs 必须完整,否则宁可构建失败也不放过半个残次品。

把 post-build.sh 这四类补丁串起来看,你会发现它们有一个共同的基调:Buildroot 的默认产出是"通用的、能跑的",但我们要的是"在这块 i.MX6ULL 板子上跑得舒服、登得进去、该有的固件和字体都在"的 rootfs。post-build.sh 就是这两者之间的那座桥,而且因为它是脚本而不是静态文件,它能做判断、能按需下载、能在最后一刻把校验闸门拉下来——这些都不是 overlay 那种简单复制能替代的。

## overlay 还是 post-build:什么时候用哪个

讲完这两条定制路径,我们来回答一个你肯定会问的问题:以后我想往 rootfs 里加点东西,到底该丢进 overlay,还是写进 post-build.sh?

判断标准其实很简单,我们回头看这两者的本质差别就行。overlay 是"静态文件叠加",Buildroot 会把 overlay 目录里的内容原样复制到 target 上,它不会执行任何逻辑、不会判断条件、不会因为 rootfs 里有什么而改变行为。所以凡是"复制进去就行、不需要动脑子"的东西——一个写好的配置文件、一段固定的脚本、一张开机 logo——统统丢进 overlay,这是最省心的选择。

post-build.sh 则是一个会运行的脚本,它能访问 target 目录、能做条件判断、能联网下载、能在失败时中止整个构建。所以凡是需要"看情况"的事情——像我们这里"只有带了 Qt6 才下字体""只有 busybox 装了才补 linuxrc""最后跑一遍完整性校验"——就只能交给 post-build.sh。它强大,但代价是每加一段逻辑你都得自己保证它幂等、保证它不会在奇怪的构建状态下崩。

还有第三种定制时机叫 post-image 脚本(`BR2_ROOTFS_POST_IMAGE_SCRIPT`),它在 rootfs 镜像打包**之后**运行,适合干"拿打包好的镜像再做点事"的活儿。不过 IMX-Forge 目前不用 Buildroot 自带的镜像打包(defconfig 里解释了:我们让 Buildroot 只产 target 目录,最终 SD/eMMC 镜像由 `build_imx6ull_image.sh` 用 `mke2fs -d` 现打,尺寸更灵活),所以这棵 tree 里暂时没有 post-image 脚本。等你真的需要的时候,在 defconfig 里加一行 `BR2_ROOTFS_POST_IMAGE_SCRIPT` 指过去就行,机制和 post-build 完全对称。

理清这三条路径之后,你以后面对任何 rootfs 定制需求,都能立刻判断它该落在哪一层。

## 小结

我们这一章把 `rootfs/buildroot/` 这棵 br2-external tree 从头到尾拆了一遍。`external.desc` 是整棵树的身份证,它的 `name: imxforge` 派生出贯穿全局的 `$(BR2_EXTERNAL_imxforge_PATH)` 变量——名字必须精确匹配、且只能含字母数字下划线,连减号都不行。`Config.in` 和 `external.mk` 目前是两个占位,等着第七章往里填自定义 package。`configs/` 放着那份不碰 kernel/uboot、只管 rootfs 的 defconfig。`fragments/` 里躺着两份"同名不同命"的配置:busybox.config 是子组件全量配置、qt6.config 是顶层增量 fragment,机制完全不同。`overlay/` 是静态文件叠加层,替代了旧的手搓合并脚本。而 `post-build.sh` 是最能体现这块板子特殊性的文件,它补 linuxrc、补 home、补救命用的 securetty、按需下载 SDMA 固件和中文字体,最后还拉一道 varified 校验闸门。

把这些串起来,你就完整理解了 IMX-Forge 的 rootfs 定制是怎么组织的:Buildroot 源码树一行不改,所有定制通过一棵职责清晰的 br2-external tree 注入,每份文件各司其职。

## 下一步

现在我们搞清楚了 br2-external tree 里每个文件是干什么的,但 rootfs 定制的"三板斧"——overlay、post-build 脚本、post-image 脚本——我们只是顺带摸了一下。下一章我们就把这三板斧正式展开,手把手带你改 rootfs:加配置文件、加开机脚本、定制用户和权限,把今天看到的机制真正用起来。

→ [06 Rootfs 定制三板斧](./06_rootfs_customization.md)
