# 添加自定义 package

::: info 本节你将学到
- Buildroot 的五种 package 基础设施(autotools / cmake / meson / qmake / generic)各自适合什么场景,拿到一个上游源码怎么一眼挑对 infra
- 手写一个 `hello` 包的完整三件套:`Config.in`(让包出现在 menuconfig)、`hello.mk`(VERSION/SITE/BUILD_CMDS + `$(eval $(generic-package))`)、`hello.hash`(给下载文件上锁)
- `$(@D)`、`$(TARGET_DIR)`、`$(STAGING_DIR)`、`$(TARGET_CROSS)`、`$(PKG_PKGDIR)` 这几个贯穿 `.mk` 的变量各自指向哪儿,为什么写错就会编出"主机架构"的二进制
- 怎么把这个包挂进 IMX-Forge 的 br2-external tree,填上第 05 章里那个一直空着的 `Config.in` / `external.mk` 占位;以及 `SITE_METHOD` 的 git / file / local 三种本地源码获取方式有什么坑
:::

::: tip 前置知识 · 环境
- 读完 [05 br2-external tree](./05_br2_external_tree.md),知道 `rootfs/buildroot/` 这棵树的结构,记得 `Config.in` 和 `external.mk` 当时是"两个安静的占位",这一章我们就把这两个占位填上
- 读完 [06 rootfs 定制三板斧](./06_rootfs_customization.md),分得清 overlay / post-build / post-image 三条"不改源码的定制路径";这一章讲的是更重的定制,往 Buildroot 的 package 体系里正式注册一个新包
- 跑通过至少一次 `./scripts/build_helper/build-buildroot.sh`,对 `out/release-latest/buildroot/output/target/` 有印象
- 环境:Buildroot 2026.02(`third_party/buildroot/`),br2-external tree 在 `rootfs/buildroot/`,`external.desc` 里 `name: imxforge`
:::

## 前言:为什么需要"正经地"加一个包

前面六章下来,我们已经能用 defconfig + fragment + overlay + post-build 把 rootfs 捏成想要的样子了。但事情到这里还没完,你迟早会撞上一类需求,这三板斧不够用:你想往板子上放一个自己写的应用程序,或者移植一个 Buildroot 树里没有的第三方库。你当然可以把编译好的二进制往 overlay 里一塞了事,说实话我早期也这么干过,但这一塞就把 Buildroot 最值钱的东西全丢了:依赖管理、增量构建、`make legal-info` 的许可证清查、`make <pkg>-rebuild` 的单独重编、ccache 加速,一个都捞不着。

Buildroot 给的正解,是把你的软件正式注册成一个 package。一旦注册,它就和树里那几千个包享受同等待遇:能被别的包 `select`、能走交叉编译工具链、能在 menuconfig 里勾选、能被 ccache 命中。我们现在要做的事,就是从零把这套流程走一遍。先讲怎么挑构建基础设施,再手写一个 `hello` 包打通全流程,最后把它挂进 IMX-Forge 的 br2-external tree,把第 05 章里那个写着 "placeholder" 的 `Config.in` 真正用起来。

## 先选 infra:五种构建系统怎么挑

写一个 package 的 `.mk` 文件,第一件要决定的事是:这个包用哪套基础设施(infra)。Buildroot 官方手册在 `adding-packages.adoc` 里把 package 按构建系统分了十几类,但日常 99% 的场景落在下面这五种里。选对 infra,你能省掉一大半代码;选错了,要么自己手写一堆本可以白拿的逻辑,要么跟 infra 的默认行为打架。

决策树很简单,我们看上游源码根目录里摆着什么文件就知道了。如果根目录躺着 `configure.ac` 或 `Makefile.am`,这是最经典的 autotools 流派,走 `./configure && make`,对应 **autotools-package**,Buildroot 几乎不用你写构建命令,只要给元数据。如果看到的是 `CMakeLists.txt`,那就用 **cmake-package**,`CONF_OPTS` 里塞 `-D` 选项就行,工具链、安装前缀 Buildroot 全帮你设好。`meson.build` 对应 **meson-package**,和 cmake 类似,传 `-Dkey=value`,`host-meson` 会自动加进依赖,不用你自己写。Qt 工程的 `*.pro` 对应 **qmake-package**,`CONF_OPTS` 里塞 `QT_CONFIG+=xxx`。

但如果上面这些文件一个都对不上,源码是手写 Makefile、shell 脚本,或者干脆没构建系统,那就只能用 **generic-package**。这条路 Buildroot 不替你猜构建命令,你得自己写 `BUILD_CMDS` / `INSTALL_TARGET_CMDS`。换句话说,前四种 infra 是 Buildroot 替你把 configure/build/install 全写好了,你只填元数据和选项;generic-package 是 Buildroot 只给你搭骨架,具体怎么编怎么装你自己写。所以选择原则一句话:能套前四种就别用 generic,白捡的逻辑不要白不要。

这一章我们重点讲 generic-package,原因有两个。一是它是所有其他 infra 的底层,理解了它,cmake/autotools 那套就是在它之上加了一层默认实现,你看一眼就懂;二是嵌入式项目里那些"板端小程序"往往就是手写 Makefile,这正是 generic-package 的主场。cmake-package 我们在 [11 Qt6 集成](./11_qt6_integration.md) 里会大量遇到,这里先把地基打好。

## 动手写一个 hello 包:generic-package 全流程

我们先假设有这样一个 hello 程序:源码就一个 `hello.c` 加一个手写 `Makefile`,打包成 `hello-1.0.tar.gz`。我们要把它注册成 `BR2_PACKAGE_HELLO`,需要三个文件:`Config.in`、`hello.mk`、`hello.hash`,放在同一个目录下。接下来我们一个一个填。

### Config.in:让包出现在 menuconfig

`Config.in` 是 Kconfig 描述,决定这个包在 `make menuconfig` 里以什么名字出现、依赖什么。手册(`adding-packages-directory.adoc`)给的骨架是这样的:

```kconfig
config BR2_PACKAGE_HELLO
	bool "hello"
	help
	  A trivial hello-world program, used as a Buildroot package tutorial.

	  http://example.com/hello/
```

有几个 Kconfig 写法要注意,手册里特意强调过:`bool`、`help` 这些行用一个 tab 缩进;help 正文用一个 tab 加两个空格缩进,每行正文 62 个字符(tab 算 8);help 里空一行后写上游 URL,这是 Buildroot 的约定。

如果你的包依赖别的包,这里要用 `select` 或 `depends on`。手册给了一条经验法则:库依赖用 `select`(向后语义,自动帮你勾上),架构、工具链、大件依赖用 `depends on`(向前语义,强制用户知情)。比如 hello 要是依赖 libfoo,就写 `select BR2_PACKAGE_LIBFOO`。这里要先提醒一句,Kconfig 的 `select` 不保证构建顺序,所以 `.mk` 里还得在 `DEPENDENCIES` 里再写一遍,这一点很多朋友会卡在这里——选了却编不出,八成就是漏了 DEPENDENCIES。

### hello.mk:元数据、构建命令、收尾 eval

`.mk` 是核心。generic-package 的写法,我们直接对照官方手册(`adding-packages-generic.adoc`)里的 `libfoo` 范例,裁成一个最小可用的 hello 版本:

```makefile
################################################################################
#
# hello
#
################################################################################

HELLO_VERSION = 1.0
HELLO_SITE = http://example.com/download
HELLO_SOURCE = hello-$(HELLO_VERSION).tar.gz
HELLO_LICENSE = GPL-2.0+
HELLO_LICENSE_FILES = COPYING

define HELLO_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

define HELLO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/hello $(TARGET_DIR)/usr/bin/hello
endef

$(eval $(generic-package))
```

我们逐段拆开讲,因为每一行都有讲究。

前几行是元数据,这里有个硬规矩:所有变量都必须以同一个前缀 `HELLO_` 开头。手册原话,"This prefix is always the uppercased version of the package name"。前缀一旦写错,`$(eval $(generic-package))` 就找不到对应的变量,包会静默地什么也不做——这种错最难调,因为你得不到任何报错,构建一路绿灯,只是最后 rootfs 里没有你的程序。

`HELLO_VERSION` 是必填的,它可以是发布版本号(`1.0`)、git commit 的 sha1、或 git tag(`v1.0`)。手册明确警告不要填分支名(比如 `main`),这是因为 Buildroot 会本地缓存仓库,分支名指向的内容随时在变,没法保证可复现构建,两个人跑同一份配置可能拿到完全不同的源码。`HELLO_SITE` 是下载地址,可以是 URL 也可以是本地路径,后面 SITE_METHOD 那节我们会细讲。`HELLO_SOURCE` 不写的话默认就是 `hello-$(HELLO_VERSION).tar.gz`,所以这里其实能省掉,手册推荐用 xz 压缩的 tarball。`HELLO_LICENSE` 和 `HELLO_LICENSE_FILES` 是给 `make legal-info` 用的,会产生许可证清单,不写不会报错,但 manifest 里会标 `unknown` / `not saved`,正规项目里这两行最好都填上,用 SPDX 短标识(如 `GPL-2.0+`、`MIT`)。

中间两个 `define ... endef` 块,是 generic-package 真正要你"手写"的部分,也是它和 cmake/autotools infra 的根本区别所在。

`HELLO_BUILD_CMDS` 决定怎么编译,我们这里直接调上游的 Makefile,`$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)`。`$(TARGET_CONFIGURE_OPTS)` 这串会展开成 `CC=$(TARGET_CC) CFLAGS=... LDFLAGS=...` 一整套交叉编译变量,这样上游 Makefile 里的 `$(CC)` 拿到的就是我们的交叉编译器,而不是主机的 gcc。底层机制就是这一层环境变量覆盖——写错这一步,你就会编出一个 x86 的二进制塞进 arm rootfs,上板直接 illegal instruction,调到怀疑人生。`$(@D)` 是源码解压目录,下一节我们专门讲。

`HELLO_INSTALL_TARGET_CMDS` 决定怎么装进 target,`$(INSTALL) -D -m 0755` 负责创建目录并拷贝,目标路径用 `$(TARGET_DIR)/usr/bin/hello`。这里有个自觉要养成:只装运行时需要的东西,头文件、静态库、文档不要装进 target。Buildroot 在 `target-finalize` 阶段会统一清理这些,但你自己写 INSTALL 时就该提前把住关,别把脏活都甩给后面的清理步骤。另外如果你的 hello 是个库、要给别的包链接,还得加一行 `HELLO_INSTALL_STAGING = YES` 并写一个 `HELLO_INSTALL_STAGING_CMDS`,把头文件和 `.so` 装进 `$(STAGING_DIR)`。我们这个 hello 是个可执行程序,不需要 staging。

最后一行 `$(eval $(generic-package))` 是收尾。它读你前面定义的所有 `HELLO_*` 变量,展开成一大堆 Makefile 规则(下载、解压、打 patch、构建、安装、清理……)。这一行必须在文件最后、在所有变量定义之后,手册强调过。如果你还想同时编一个 host 版本,再加一行 `$(eval $(host-generic-package))`,它必须跟在 target 版本后面,host 版本会叫 `host-hello`。

### hello.hash:给下载文件上保险

第三个文件是 `hello.hash`。手册原话:"When possible, you must add a third file"。它的作用是校验下载下来的 tarball 没被篡改、没下坏。格式是三段、用两个空格分隔:哈希类型、哈希值、文件名:

```
sha256  efc8103cc3bcb06bda6a781532d12701eb081ad83e8f90004b39ab81b65d4369  hello-1.0.tar.gz
```

哈希类型可以是 `md5` / `sha1` / `sha224` / `sha256` / `sha384` / `sha512`,手册推荐优先用上游发布的强哈希(sha256 或更强);上游没给就自己算一个 sha256,并在上面加一行注释 `# Locally computed:`。一个文件可以挂多条哈希(各占一行),必须全部匹配。手册还提了一个细节:同一个 `.hash` 文件里也能放许可证文件的哈希(文件名就是 `LICENSE_FILES` 里的相对路径),这样 `make legal-info` 跑的时候还能帮你检测上游许可证有没有偷偷变。

校验逻辑是这样的:下载完成后,Buildroot 算一遍哈希,跟 `.hash` 里对得上才放行;对不上就删掉下载文件、中止构建。如果 `.hash` 文件存在但里面没有对应文件的哈希,也算错,这通常说明你 `.hash` 写漏了。哈希目前对 http/ftp/git/svn/scp/local 都会检查;对 CVS 和 Mercurial 不检查,因为这些没法生成可复现的 tarball。

## 关键变量速查:$(@D)、$(TARGET_DIR) 这些到底是什么

写 `.mk` 的过程中,你会反复碰到几个 Buildroot 预定义变量。手册(`adding-packages-generic.adoc` 的 "action definitions" 一节)列得很全,这里把最常用的几个拎出来讲清楚,因为它们写错一个,要么编出主机架构的二进制,要么装错地方,都是难调的坑。

先说指向源码和产物的几个目录变量。`$(@D)` 是源码解压目录,Buildroot 把 tarball 解压到 `output/build/hello-1.0/` 这样的路径,`$(@D)` 就指向它,所以 `BUILD_CMDS` 里几乎必然出现 `-C $(@D)`。`$(TARGET_DIR)` 是目标 rootfs 目录树的根,也就是 `output/target/`,往这里装的东西最终会进板子的 rootfs,只装运行时需要的。`$(STAGING_DIR)` 是 staging 目录(`output/staging/`),放头文件、`.so` 软链、`.a`、pkgconfig 文件,这些是给别的包编译时链接用的、不进 rootfs,所以库包必须 `INSTALL_STAGING = YES`。把 target 和 staging 这两个目录的分工记混,是新手装错东西的最常见原因:该进 staging 的头文件塞进了 target,rootfs 体积白白涨一截;该进 target 的运行时没装,板子上找不到程序。

再说工具链相关的几个。`$(TARGET_CROSS)` 是交叉工具链前缀,比如 `arm-none-linux-gnueabihf-`,拼上 `gcc` 就是交叉编译器;一般你不用手拼,直接用 `$(TARGET_CC)`、`$(TARGET_LD)` 这些具体的工具,而 `$(TARGET_CONFIGURE_OPTS)` 会把它们打包成环境变量传给上游 Makefile——上一节 BUILD_CMDS 里用的就是它。另外还有一个你会越用越多的变量 `$(HELLO_PKGDIR)`,指向你这个包自己的 `.mk` 和 `Config.in` 所在的目录。手册特别提到它的用途:当你想把一个随包携带的配置文件、启动脚本、splash 图等捆绑文件装进 target 时,用它定位源路径,比如 `$(INSTALL) $(HELLO_PKGDIR)/hello.conf $(TARGET_DIR)/etc/`。下一节装 init 脚本就会用到它,你会发现这个变量几乎是"随包资源"的唯一正确入口。此外还有 `$(HOST_DIR)`,host 包的产物装这儿。

手册还提醒一句:在 per-package directory(顶层并行构建)开启时,`$(TARGET_DIR)` / `$(STAGING_DIR)` / `$(HOST_DIR)` 指向的是当前包私有的那一份,而不是全局的;但从包的角度看写法完全一样,不用管。

## 把包挂进 br2-external:填上第 05 章那两个占位

写完了三件套,接下来问题来了:这三个文件放哪儿?Buildroot 树内自带的包放在 `buildroot/package/hello/`。但我们是 br2-external tree,不能污染 submodule。IMX-Forge 的做法是把自定义包挂在 `rootfs/buildroot/package/` 下。

这正是第 05 章里那两个"安静的占位"派上用场的地方。我们回忆一下当时它们的样子。`Config.in` 当时是个占位 `menuconfig`:

```makefile
menuconfig BR2_PACKAGE_IMXFORGE
	bool "imxforge custom packages (placeholder)"
	help
	  Placeholder for future IMX-Forge custom buildroot packages.
```

`external.mk` 当时几乎是空的:

```makefile
# IMX-Forge buildroot external tree
# 当前无自定义 package 构建逻辑;本文件由 buildroot 自动 include,留空即可。
```

手册(`customize-outside-br.adoc`)给的 canonical 接法是这样:把 hello 的三件套放进 `rootfs/buildroot/package/hello/`,然后在 `Config.in` 里 source 它,在 `external.mk` 里 include 它的 `.mk`。

这里有一个很容易踩的语法坑,手册用 `BAR_42` 例子讲清楚过:Kconfig 文件(`Config.in`)里用单美元的环境变量引用 `$BR2_EXTERNAL_..._PATH`,而 Makefile(`external.mk`)里用 Make 的函数语法 `$(BR2_EXTERNAL_...)`。这两种文件长得像、变量名也像,但解析它们的引擎完全不同,写混了就是一道隐蔽的坑。

我们先改 `Config.in`,在占位菜单里挂上 hello:

```kconfig
menuconfig BR2_PACKAGE_IMXFORGE
	bool "imxforge custom packages"
	help
	  Custom buildroot packages for the IMX-Forge imx6ull-aes board.

if BR2_PACKAGE_IMXFORGE
source "$BR2_EXTERNAL_imxforge_PATH/package/hello/Config.in"
endif
```

注意这行 source 用的是 `$BR2_EXTERNAL_imxforge_PATH`(单美元),和我们在 defconfig 里反复看到的 `$(BR2_EXTERNAL_imxforge_PATH)`(双美元)长得不一样,这事儿值得专门拆一下。`Config.in` 和 defconfig 虽然用途不同,但都是 Kconfig 文件,由 Kconfig 解析;而 Kconfig 对环境变量引用本身就支持 `$VAR` 和 `$(VAR)` 两种写法,都能被它展开。所以你在 `Config.in` 里看到单美元、在 defconfig 里看到双美元,本质上都是 Kconfig 在解析,都能正常工作(项目 `configs/imx6ull_aes_defconfig` 里用 `$(BR2_EXTERNAL_imxforge_PATH)` 且构建正常就是实证)。真正的分界线在 `external.mk`:它是一个 Makefile,必须用 Make 的函数语法 `$(BR2_EXTERNAL_imxforge_PATH)`,这一种是 Make 在解析时展开,跟 Kconfig 没关系。所以你要记住的不是"Config.in 用单美元、defconfig 用双美元",而是"Kconfig 文件两种都吃、Makefile 只吃双美元",别把 Makefile 语法写进 Kconfig 文件、或反过来。无论哪种写法,它们指向的都是同一个由 `external.desc` 的 `name` 派生出的绝对路径(即 `rootfs/buildroot/`),这一点第 05 章从 `external.desc` 的 `name` 角度讲过。

再改 `external.mk`,把所有包的 `.mk` 一锅端进来:

```makefile
# IMX-Forge buildroot external tree
include $(sort $(wildcard $(BR2_EXTERNAL_imxforge_PATH)/package/*/*.mk))
```

这里用 `$(BR2_EXTERNAL_imxforge_PATH)`(Make 语法),配 `$(sort $(wildcard ...))` 自动扫 `package/*/*.mk`,以后每加一个包这条都不用改,新建目录就自动生效。这是手册推荐的标准写法,也是 Buildroot 树内自己用的扫描方式。

做完这两步,跑 `make menuconfig` 就能在 "imxforge custom packages" 菜单下看到 `hello` 选项;勾上后 `make` 就会下载、校验、编译、安装。最后在 defconfig(`rootfs/buildroot/configs/imx6ull_aes_defconfig`)里加一行 `BR2_PACKAGE_HELLO=y` 让它默认开启,就像第 04 章讲的那样。

## SITE_METHOD 扫盲:git / file / local 三种本地源码怎么选

上面 hello 用的是最朴素的 http 下载。但实际项目里,源码经常不在公网上,要么是你自己 git 仓里的东西,要么是本地改过的源码目录。`SITE_METHOD` 这个变量就是管"怎么把源码弄进构建目录"的。手册列了一大堆取值(wget / scp / sftp / svn / cvs / git / hg / bzr / file / local / smb),很多情况 Buildroot 会根据 `SITE` 的前缀自动猜,比如 `http://` 开头自动用 wget,`git://` 开头自动用 git。这里重点讲嵌入式开发最常用的三种本地或自托管方式,因为它们之间的差别最容易踩坑,真正的坑也藏在这儿。

**git 方式**,源码在你自己的 git 仓库或 GitHub。写法是:

```makefile
HELLO_VERSION = v1.0
HELLO_SITE = https://github.com/yourorg/hello.git
HELLO_SITE_METHOD = git
```

这里有个坑我必须拎出来单独说:`SITE_METHOD = git` 必须显式写出,千万别省。Buildroot 只有在 `SITE` 以 `git://` 开头时才会自动选 git 方法,手册原文是 "Used by default when `LIBFOO_SITE` begins with `git://`";而对 `https://github.com/yourorg/hello.git` 这种 URL,自动识别取的是 `://` 之前的 scheme,也就是 `https`,会落到 wget 方法,把整个 URL 当普通文件去下载,而不是 git clone,构建必然失败——`.git` 后缀完全不参与判断。所以只要你的 `SITE` 不是 `git://` 开头,就老老实实写 `HELLO_SITE_METHOD = git`。`VERSION` 这里填 tag 或 commit sha1,绝对不要填分支名,前面讲过原因:不可复现。git 方式下,Buildroot 会做一次 clone 然后打包成 tarball 缓存,后续构建直接用缓存、不再 re-fetch;打 patch 用标准的 `*.patch` 机制是支持的。

**file 方式**,你手头有一个现成的 tarball,不想走网络。`SITE` 指向本地 tarball 文件所在的目录:

```makefile
HELLO_SITE = $(BR2_EXTERNAL_imxforge_PATH)/package/hello/src
HELLO_SOURCE = hello-1.0.tar.gz
HELLO_SITE_METHOD = file
```

这种方式 tarball 还是会被拷进下载缓存,哈希照样校验,行为和 http 下载几乎一样,只是源在本地。它适合那种"内部软件、不放公网、但打了正式 tag 包"的场景,patch 机制也正常工作。

**local 方式**,这是最容易踩坑的一种。`SITE` 指向一个本地源码目录(注意是目录、不是 tarball),Buildroot 用 rsync 把目录内容拷进构建目录:

```makefile
HELLO_SITE = $(BR2_EXTERNAL_imxforge_PATH)/package/hello/src
HELLO_SITE_METHOD = local
```

手册在 `local` 这一条上有两句加粗的话,务必记住:"for local packages, no patches are applied"。也就是说,你在 `package/hello/` 下放的那些 `0001-xxx.patch`,对 local 方式的包统统不生效,因为 Buildroot 是 rsync 完就进 configure,中间根本没有打 patch 这一步。

::: warning 踩坑预警:local 不打 patch,要改源码用 POST_RSYNC_HOOKS
如果你选了 `SITE_METHOD = local`,又想对源码做点修改,放在 `package/hello/*.patch` 里是没用的,构建时会被静默忽略——你改了半天 patch,构建一点反应都没有,这种"改了不生效"的沉默失败最磨人。手册给的正解是用 `HELLO_POST_RSYNC_HOOKS`,这个钩子只在 local 源码(或 `OVERRIDE_SRCDIR` 机制)下触发,在 rsync 把源码拷进构建目录之后跑,你可以在钩子里手动 `cp` 或 `patch`。手册甚至给了用途说明:rsync 默认会跳过 `.git` / `.hg` 这些版本控制目录,如果你构建脚本需要读 git 信息,就得在 `POST_RSYNC_HOOKS` 里自己把 `.git` 拷过去;钩子里能用 `$(SRCDIR)`(源目录)和 `$(@D)`(构建目录)这两个变量。

local 方式适合"边改源码边构建"的开发期联调,配合 `OVERRIDE_SRCDIR` 改一次编一次最爽;但一旦源码稳定,建议切回 file 或 git 方式,这样 patch 机制、哈希校验、可复现性才都在。
:::

## 进阶:hooks 和 init 脚本

包写多了你会需要两个进阶能力:在构建流程的某个点插一脚(hooks),以及给包装一个开机启动脚本(init 脚本)。我们挨个看。

### Hooks:在某个步骤前后插自己的逻辑

手册(`adding-packages-hooks.adoc`)说,generic-package 几乎不缺 hooks,因为 `.mk` 本来就让你自己写 `BUILD_CMDS` 这些;但对 cmake/autotools infra,hooks 就很有用,因为你不想为了改一小步就把整个 build 步骤重写。可用的钩子点手册列了一长串,最常用的有这么几个。`HELLO_PRE_CONFIGURE_HOOKS` 和 `HELLO_POST_CONFIGURE_HOOKS` 挂在 configure 前后,比如上游 configure 脚本有 bug,你想在它跑完之后 `sed` 改一下生成的 Makefile,就挂 POST_CONFIGURE。`HELLO_POST_PATCH_HOOKS` 在打完 patch 之后触发,常用来生成某些 `autogen.sh` 产物。`HELLO_POST_RSYNC_HOOKS` 上一节讲过,local 源码专用。`HELLO_POST_INSTALL_TARGET_HOOKS` 在装完 target 之后跑,常用来删掉一些上游 `make install` 多装的东西。

这些变量都是列表,挂法是这样的:

```makefile
define HELLO_POST_CONFIGURE_FIXUP
	$(SED) 's/-O2/-O0/' $(@D)/Makefile
endef
HELLO_POST_CONFIGURE_HOOKS += HELLO_POST_CONFIGURE_FIXUP
```

`+=` 意味着同一个钩子点可以挂多个动作,它们会依次执行。

### LIBFOO_INSTALL_INIT_SYSV:给包装一个开机启动脚本

如果你的 hello 是个守护进程,要开机自启,就要装 init 脚本。手册在 generic-package 参考里给了三个并列变量:`LIBFOO_INSTALL_INIT_SYSV`、`LIBFOO_INSTALL_INIT_OPENRC`、`LIBFOO_INSTALL_INIT_SYSTEMD`。Buildroot 只会跑和当前选中 init 系统对应的那一个:选了 BusyBox/SysV init 就跑 SYSV 那个,选了 systemd 就跑 SYSTEMD 那个。我们 IMX-Forge 用的是 BusyBox init(下一章详解),所以关心 SYSV 这个:

```makefile
define HELLO_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(HELLO_PKGDIR)/S50hello \
		$(TARGET_DIR)/etc/init.d/S50hello
endef
```

这里就用到了前面讲的 `$(HELLO_PKGDIR)`,把随包携带的启动脚本 `S50hello` 从包目录装进 target 的 `/etc/init.d/`。脚本命名遵循 `SNN<name>` 格式,`NN` 是两位数的启动顺序号,手册举的例子是 `S40network` 之前不能起需要网络的程序,`S01syslogd` 在 `S02sysctl` 之前。BusyBox init 在开机时会按字母序跑 `/etc/init.d/S??*`,这部分机制我们在 [08 init 系统](./08_init_system.md) 会完整拆开,这里先知道"装脚本"这一步怎么写就行。

## 踩坑预警:CONFIG_SCRIPTS 的交叉编译陷阱

最后讲一个库包几乎必踩的坑。如果你的包是个库,装进 staging 后会带一个 `xxx-config` 脚本(在 `$(STAGING_DIR)/usr/bin/` 下),别的包用 `pkg-config` 或这脚本去查它的头文件路径和链接参数。问题来了:这些脚本往往是上游用主机路径生成的,里头写死的是 `-I/usr/include`、`-L/usr/lib`,交叉编译时这会指向编译机的主机系统,而不是 staging 目录,结果链接到主机的库,编出来的东西跑到板子上就崩。这种 bug 的症状特别迷惑——编译机上一路绿灯,板子上跑就 segfault,你根本不会怀疑到一个小小的 config 脚本头上。

手册在 generic-package 参考里专门留了 `LIBFOO_CONFIG_SCRIPTS` 这个变量来治这个病。你把脚本名填进去:

```makefile
HELLO_CONFIG_SCRIPTS = hello-config
```

Buildroot 会自动对这些脚本做 sed 修正,把 `-I/usr/include` 改成 `-I$(STAGING_DIR)/usr/include`、`-L/usr/lib` 改成 `-L$(STAGING_DIR)/usr/lib`,让它们给出交叉编译友好的标志。手册还补了一句:列在 `CONFIG_SCRIPTS` 里的脚本会从 `$(TARGET_DIR)/usr/bin` 里删掉,因为板子上根本用不到这些开发期脚本,它们只在编译别的主机/目标包时有用。

如果包安装了多个 config 脚本(比如 imagemagick 那种一堆 `Wand-config`、`Magick-config`),就空格分隔全列上。这个变量对纯可执行程序(像我们的 hello)用不上,但只要你的包带库且暴露了 `-config` 脚本,这一行基本不能省——少写一次,就够你调半天"为什么链接到了 x86 的库"。

## 下一步

这一章我们从挑 infra、写三件套、挂进 br2-external,到 SITE_METHOD、hooks、init 脚本、CONFIG_SCRIPTS,把"加一个自定义 package"的全流程走了一遍。现在 IMX-Forge 那两个一直空着的占位 `Config.in` 和 `external.mk` 终于有了正经的内容。

包写好了、装进去了,接下来一个绕不开的问题是:它怎么在板子开机时跑起来?我们装的 `S50hello` 到底是被谁、按什么顺序调用的?BusyBox init 的 `/etc/inittab` 和 `/etc/init.d/` 是怎么联动的?这就是下一章 [08 init 系统](./08_init_system.md) 要拆的事:我们会从 `post-build.sh` 里补 `linuxrc` 软链的那几行出发,再回到 buildroot skeleton 生成的 `/etc/inittab` 与 `/etc/init.d/rcS`,把 IMX-Forge 的开机流程从头到尾走一遍。

→ [08 Init 系统](./08_init_system.md)
