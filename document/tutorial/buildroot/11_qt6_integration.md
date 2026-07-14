# Qt6 集成实战

::: info 本节你将学到
- 为什么 Qt6 在 IMX-Forge 里是"按需"的——默认最小 rootfs 不带它,要靠 fragment 显式 merge,以及这么设计背后的体积和构建时间考量
- i.MX6ULL 没有 GPU 这件事,怎么从头到尾决定了 Qt6 的平台插件选型:linuxfb + tslib,而不是 EGLFS 或 XCB
- `fragments/qt6.config` 里每一个选项为什么这么开,八个子模块各自扮演什么角色,哪些是"别偷懒必须显式写"的
- 两个真正卡人的构建陷阱:`QT6DECLARATIVE_QUICK` 的隐藏依赖链,以及 host qt6base 改配置后 stamp 缓存不触发、必须手动 `make clean` 重建
- post-build 怎么靠"嗅探" `libQt6Core.so` 决定要不要下载中文字体,以及怎么在板子上真正把一个 Qt 程序跑起来
:::

::: tip 前置知识 · 环境
- [第 04 章:配置体系](04_kconfig_fragments.md) 里讲过 fragment 的合并机制(`merge_config.sh -m` + `olddefconfig`),本章默认你懂了那套流程,重点放在 Qt6 本身的设计取舍和踩坑
- [第 06 章:Rootfs 定制三板斧](06_rootfs_customization.md) 的 post-build 脚本,本章会拆 post-build.sh 里 Qt6 专属的字体逻辑
- 对 Qt 的 QPA(Qt Platform Abstraction)有点概念就行:知道一个 Qt 程序要靠一个"平台插件"去对接具体的显示和输入后端,剩下的我们边走边讲
- 环境:Buildroot 2026.02(`third_party/buildroot/`),原生 Qt6 **6.9.1**;i.MX6ULL AES 板,512M 内存,无 GPU
:::

## 前言:从手编 Qt 到 Buildroot 原生包

说实话,IMX-Forge 早期的 Qt6 是一条独立流水线——`third_party/qt-compile-pipeline` 这个子模块,自己维护一套 CMake 交叉编译脚本,自己 `configure` qt6base 和一坨子模块,然后把编译产物手动拷进 rootfs。这套东西跑起来没问题,但维护起来是真的累:版本要自己跟、依赖库要自己交叉编、`.a` 静态库一通全量拷贝把 rootfs 撑到了 442MB,每次重建 Qt 都像是在做手工活。

事情的转机在于 Buildroot 2026.02 把 Qt6 收成了原生包,而且版本正好是 **6.9.1**——和我们原来 qt-compile-pipeline 用的版本完全一致。这意味着我们不用再维护一条独立的 Qt 编译线,直接让 Buildroot 用它自家的 `package/qt6*` 去编,版本、ABI、特性全对齐,产物还天然就是 rootfs 的一部分,省掉了手动拷贝和那堆臃肿的 `.a` 文件。迁完之后 rootfs 从 442MB 直接掉到 173MB,这一刀砍得相当痛快。

但"原生包"不等于"无脑开"。i.MX6ULL 这颗 SoC 没有 GPU,显示走的是裸 framebuffer,这从根本上决定了 Qt6 的平台插件只能选 linuxfb、触摸校准只能靠 tslib,EGLFS、XCB、OpenGL 这一堆全得关掉。再加上 Qt6 全模块(八个子模块)编下来要 2 到 4 小时,显然不能塞进默认 defconfig。所以我们用了一个 fragment 把 Qt6 的配置单独隔出来,默认最小 rootfs 不碰它,只在需要的时候 merge 进来。这个机制本身在 [第 04 章](04_kconfig_fragments.md) 讲过,本章要讲的是 Qt6 这套配置里每一个选项为什么这么选,以及两个真正把我卡了半天的构建陷阱。

## 没有 GPU 这件事,怎么决定了一切

在动任何配置之前,我们得先想清楚一个根本问题:Qt 程序在板子上靠什么把画面画出来、靠什么读触摸输入?这就是 QPA——Qt 平台抽象层——干的事。Qt 会根据 `QT_QPA_PLATFORM` 环境变量(或编译时默认值)去加载一个平台插件,由这个插件对接底层的显示和输入后端。桌面环境上你用的大多是 `xcb` 或 `wayland`,但 i.MX6ULL 上这两条路都走不通。

i.MX6ULL 没有 GPU,也没有跑 X Server 或 Wayland compositor 的必要。它的显示后端就是内核的 framebuffer——`/dev/fb0`,一个你可以直接往里写像素的线性显存。Qt 对应的平台插件叫 **linuxfb**,它直接 mmap 这块 framebuffer、把 QWidget 的绘制结果 blit 上去,不需要任何窗口系统。这就是我们唯一合理的选择,也是 `qt6.config` 里 `BR2_PACKAGE_QT6BASE_LINUXFB=y` 这一行存在的全部理由。

至于 EGLFS——Qt 那个直接走 OpenGL ES + EGL 的后端,在树莓派那种有 GPU 的板子上很常用——在我们这没用,因为没有 GPU 就没有 OpenGL ES,开了也是白开。XCB(走 X11)更不用想,rootfs 里压根没 X。所以你会看到我们的 fragment 里干净利落地只开了 `LINUXFB`,没有 `EGLFS`、没有 `XCB`、没有任何 OpenGL 选项。这不是漏写,是刻意关掉的。

触摸这边同理。正点原子这块屏的触摸控制器(Goodix GT9147)在内核里已经是个标准的 input 设备,会冒出来成一个 `/dev/input/eventN`。Qt 自己不去直接读这个原始事件,而是通过 **tslib** 这一层做事件过滤和校准——tslib 负责把原始触摸事件做去抖、线性校准(就是 `ts_calibrate` 那五点校准),然后 Qt 的 tslib 插件从校准后的事件流里读坐标。这就是为什么 fragment 里紧挨着 `BR2_PACKAGE_QT6BASE_LINUXFB=y` 的就是 `BR2_PACKAGE_QT6BASE_TSLIB=y`,以及一个独立的 `BR2_PACKAGE_TSLIB=y`——前者是让 Qt6 编译时带上 tslib 支持的 QPA 输入插件,后者是 tslib 库本身。这两个缺一不可,只开 Qt 侧不开 tslib 库,链接的时候会报找不到 `-lts`。

你可以把整套机制理解为:linuxfb 管"画到屏幕上",tslib 管"把触摸坐标读准",它俩一个输出一个输入,合在一起就是 i.MX6ULL 上 Qt 程序运行的全部底座。后面所有配置,都是在这块底座上做加法。

## qt6.config 逐段拆解

平台策略定了,现在我们来看 `fragments/qt6.config` 这个文件到底写了什么。[第 04 章](04_kconfig_fragments.md) 已经贴过它的全文并讲了 fragment 的合并机制,这里我们不重复那个,而是逐段拆解每一个选项背后的取舍。文件在 `rootfs/buildroot/fragments/qt6.config`。

### qt6base 核心选项:显示、输入、GUI 能力

```makefile
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
```

`BR2_PACKAGE_QT6` 是整个 Qt6 套件的父开关,`BR2_PACKAGE_QT6BASE` 是基础模块(QtCore / QtGui / QtWidgets 等核心库)。后面这堆 `QT6BASE_*` 子选项,本质上对应 Qt6Base 在 CMake configure 阶段的那些 `-DFEATURE_xxx=ON`。比如 `QT6BASE_LINUXFB` 对应 `FEATURE_linuxfb=ON`,`QT6BASE_GUI` 对应把 QtGui 模块编进来。Buildroot 的 qt6base package recipe 会把这些 Kconfig 选项翻译成对应的 CMake 参数喂给 Qt 的构建系统。

你会发现 GUI、WIDGETS、NETWORK、XML、SQL、SQLITE、PNG、JPEG、GIF、FONTCONFIG 这些全都显式列了出来,看起来很啰嗦。但这里有个 fragment 机制的特点你得记住:`merge_config.sh` 只做逐行设值,不会替你解 Kconfig 的 `select` 依赖。换句话说,虽然 Buildroot 的 `Config.in` 里 `QT6BASE_GUI` 可能隐式 `select` 了某些子选项,但 fragment 合并时这些隐式关系是"后置"的——先逐行写值,再靠 `olddefconfig` 兜底。所以我们倾向于把需要的全显式写出来,让 fragment 自包含、读起来一目了然,不依赖 Buildroot 内部 select 关系的隐式行为。这一点 [第 04 章](04_kconfig_fragments.md) 也强调过,这里不再展开。

图片编解码那几行(`PNG` / `JPEG` / `GIF`)和 `FONTCONFIG` 是 GUI 程序的刚需——你要显示图片就得有对应的解码器,要正常渲染字体就得有 fontconfig 做字体匹配。`SQL` + `SQLITE` 则是给那些需要本地数据库的 Qt 应用准备的,SQLite 是个纯文件型的嵌入式数据库,开了几乎零成本。

### 紧跟其后的依赖包:tslib、字体、DejaVu

```makefile
BR2_PACKAGE_TSLIB=y                  # qt6base TSLIB 依赖
BR2_PACKAGE_FONTCONFIG=y             # 字体配置(Qt FONTCONFIG)
BR2_PACKAGE_DEJAVU=y                 # DejaVu 字体(西文 + 基础符号)
```

这三行是 qt6base 跑起来需要的运行时依赖,不属于 Qt6 套件但必须一起进 rootfs。`TSLIB` 前面讲过了,`FONTCONFIG` 对应 `QT6BASE_FONTCONFIG` 的运行时库。`DEJAVU` 是 Buildroot 的 dejavu 字体包,提供西文和基础符号的字形——这是 Qt 程序能"显示出字"的最低保障,没有它你的按钮文字会变成一片空白方块。至于中文字体,DejaVu 不覆盖 CJK,那是 post-build 阶段单独下载 Noto CJK 的事,我们后面会专门讲。

### 八个子模块:对齐 qt-compile-pipeline 的全套能力

```makefile
BR2_PACKAGE_QT6DECLARATIVE=y        # QML/QtQuick
BR2_PACKAGE_QT6DECLARATIVE_QUICK=y  # QtQuick(拉 qt6shadertools + host qmlprofiler 需 HOST_QT6BASE_NETWORK)
BR2_PACKAGE_QT6MULTIMEDIA=y         # 多媒体(FFmpeg + ALSA 后端,wm8960)
BR2_PACKAGE_QT6CHARTS=y
BR2_PACKAGE_QT6SHADERTOOLS=y        # qt6declarative 依赖
BR2_PACKAGE_QT6SERIALPORT=y
BR2_PACKAGE_QT6VIRTUALKEYBOARD=y
BR2_PACKAGE_QT6CORE5COMPAT=y
```

这一段是 Qt6 的功能子模块,我们逐个说。`QT6DECLARATIVE` 是 QML 和 QtQuick 引擎,现在很多 Qt 应用都用 QML 写界面,这是个高频需求。`QT6MULTIMEDIA` 是多媒体模块,底层走 FFmpeg 解码 + ALSA 后端——在我们这块板上它正好对接 wm8960 音频芯片的 ALSA 声卡设备,和 [wm8960 音频章节](../driver/12_wm8960_audio_driver/index.md) 那条链路是通的。`QT6CHARTS` 提供图表组件,`QT6SERIALPORT` 是串口通信,`QT6VIRTUALKEYBOARD` 是虚拟键盘(触摸屏上没物理键盘时用),`QT6CORE5COMPAT` 是 Qt5 到 Qt6 的兼容层,给那些还在用旧 API 的代码一个过渡。

这里面最需要你注意的是 `QT6DECLARATIVE` 和 `QT6DECLARATIVE_QUICK` 这一对,以及紧跟着的 `QT6SHADERTOOLS`。`DECLARATIVE` 开了 QML 引擎,但 QtQuick 那套声明式 UI 框架是单独一个选项 `DECLARATIVE_QUICK`——这个选项不选的话,你的 QML 程序 configure 阶段就会失败,真正的坑在后面我们会单独讲。`QT6SHADERTOOLS` 提供 QML 编译期需要的 `qsb`(Qt Shader Baker)工具,它是 `DECLARATIVE_QUICK` 的硬依赖,所以也必须开。

这八个模块加起来对齐的是我们原 qt-compile-pipeline 里 `qt.conf` 的 `QT_MODULES` 八件套,能力上一个不少。

## 触发构建:三条路径,同一条 merge

Qt6 的配置写好了,但默认它不参与构建。我们先看怎么让它跑起来,再看踩坑。触发的入口有三个,但最终走的都是同一条 fragment merge 路径。

最直接的是本地构建加一个标志位:

```bash
./scripts/build_helper/build-buildroot.sh --with-qt6
```

或者在环境变量里设:

```bash
BUILDROOT_QT6=1 ./scripts/build_helper/build-buildroot.sh
```

这两种是等价的——脚本开头有一行 `[[ "${BUILDROOT_QT6:-0}" == "1" ]] && WITH_QT6=1`,环境变量和命令行参数最终都汇到同一个 `WITH_QT6` 开关上。

第三条路是 CI。我们看一下 `.github/workflows/ci-full.yml` 里的编排,它靠一个 PR 标签来决定要不要编 Qt6:

```yaml
# .github/workflows/ci-full.yml
HAS_COMPILE_3RD_PARTY_LABEL: ${{ contains(github.event.pull_request.labels.*.name, 'compile-support-3rd-party') }}
```

CI 检测 PR 上有没有 `compile-support-3rd-party` 这个 label,有的话把这个值传进构建容器:

```yaml
-e BUILDROOT_QT6=${{ ... && '1' || '0' }} \
```

也就是说,CI 默认跑的是最小 rootfs(不带 Qt6,大约 15 分钟构建完),只有你显式给 PR 打上那个 label,才会触发 Qt6 全模块编译。设计成这样纯粹是因为 Qt6 全编要 2 到 4 小时,不可能每次 CI 都陪它耗着。label 没打的时候,CI 的构建摘要里会明确写一句"Qt6/字体: 已跳过(最小 rootfs;添加 compile-support-3rd-party 标签启用)",免得你以为 Qt6 丢了。

不管哪条路径,`WITH_QT6=1` 之后脚本干的事是一样的——把 `qt6.config` 这个 fragment 合进 `.config`,然后 `olddefconfig` 重解依赖:

```bash
if [[ ${WITH_QT6} -eq 1 ]]; then
    QT6_FRAGMENT="${BR2_EXTERNAL_DIR}/fragments/qt6.config"
    log_info "Step 1b: Merging Qt6 fragment"
    "${BUILDROOT_DIR}/support/kconfig/merge_config.sh" -m -O "${OUTPUT_DIR}" \
        "${OUTPUT_DIR}/.config" "${QT6_FRAGMENT}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" olddefconfig
fi
```

`merge_config.sh -m` 把 fragment 逐行叠加到 `.config`,接着 `olddefconfig` 把 `select` 指向的符号自动补齐、解掉冲突,最后得到一份干净的配置。这两行的具体含义 [第 04 章](04_kconfig_fragments.md) 讲得很细,这里只要记住一件事:fragment 合进来之后,Qt6 的所有依赖(qt6shadertools、host 工具链那一堆)都是 `olddefconfig` 自动替你拉起来的,你不用在 fragment 里把它们全列出来。

接下来就是 `make -j$(nproc)`,正常构建。Buildroot 会按依赖顺序先把 host 侧的工具(qmake、qsb 等)编出来,再编 target 侧的 Qt6 库,最后编子模块。整个过程日志会 tee 到 `out/release-latest/buildroot/buildmeter-full.log` 里,接了进度条的话你能看到包级别的推进。编完之后 `target/` 目录 rsync 到 `out/release-latest/rootfs/`,rootfs 里就有了完整的 Qt6 运行时。

到这里如果一切顺利,你大概会觉得很轻松。但事情到这里还没完——真正的坑在后面。

## 真正的坑在后面:两个 Qt6 构建陷阱

Qt6 是 IMX-Forge 迁到 Buildroot 的阶段三踩坑最密集的部分。其中有两个坑足以让你在 configure 阶段或链接阶段直接卡死,而且报错信息一点都不直观。我们把它们一个个拆开。

### 陷阱一:QT6DECLARATIVE_QUICK 的隐藏依赖链

第一个坑出在 `qt6declarative` 的 configure 阶段。现象是:你开了 `BR2_PACKAGE_QT6DECLARATIVE=y`,觉得 QML 引擎到手了,结果 configure 报一个 `ShaderToolsConfig not found`,或者提示 `qmlprofiler` 这个 host 工具没建出来,然后整个 declarative 模块直接失败退出。

根因在于 `BR2_PACKAGE_QT6DECLARATIVE` 和 `BR2_PACKAGE_QT6DECLARATIVE_QUICK` 是两个独立的选项。前者只拉 QML 语言引擎(QtCore 那套绑定),后者才是 QtQuick 那套声明式 UI 框架。而 QtQuick 在编译期依赖 `qt6shadertools`——它需要 `qsb` 工具把着色器编译成 SPIR-V 字节码嵌进 QML 场景里。同一时间,`qt6declarative` 的 host 工具 `qmlprofiler` 又要求 `HOST_QT6BASE_NETWORK` 是开的(host 侧 qt6base 要带网络模块)。

这两条隐藏依赖如果你只开 `QT6DECLARATIVE` 不开 `QUICK`,Buildroot 的 `olddefconfig` 不一定自动替你补全(取决于版本里 Config.in 的 select 写得有多完整),于是 configure 阶段就炸了。解法很直接——fragment 里 `QUICK` 和 `SHADERTOOLS` 都显式开:

```makefile
BR2_PACKAGE_QT6DECLARATIVE_QUICK=y  # QtQuick(拉 qt6shadertools + host qmlprofiler 需 HOST_QT6BASE_NETWORK)
BR2_PACKAGE_QT6SHADERTOOLS=y        # qt6declarative 依赖
```

这就是为什么我们的 fragment 里这一行带着那么长的注释——注释本身就是踩坑留下的伤疤。结论:**只要你用了 QML/QtQuick,`DECLARATIVE_QUICK` 和 `SHADERTOOLS` 必须一起开,别指望 select 自动补。**

### 陷阱二:host qt6base 改配置后,stamp 缓存不触发重建

第二个坑更阴,它是 Buildroot 增量构建机制的一个通用 gotcha,但在 Qt6 这儿特别容易中招。现象是这样的:你某次构建时改动了 host qt6base 的配置(比如之前没开 GUI/NETWORK,后来 declarative 需要就补上了),然后直接重跑 `make`,结果 host qt6base 用的还是旧的 stamp——它以为自己的构建产物是最新的、没有重新编译。但旧的产物里根本没有 GUI/NETWORK 模块,于是依赖它的 host qt6shadertools 的 `qsb` 工具就建不出来,后面 target 侧的 declarative 编译全挂。

底层机制是 Buildroot 给每个 package 维护了一组 `.stamp_*` 文件(`.stamp_built`、`.stamp_installed` 等)来标记构建阶段是否完成。当你只改 Kconfig 配置而没有清掉这个 package 的 build 目录时,Buildroot 看到 stamp 还在,就跳过了重新 configure 和编译。这个行为对"改了一行 source 代码"的场景是合理的(增量),但对"改了 configure 选项"的场景就是灾难——选项变了,产物却没重建。

解法是手动清掉这个 package 的构建再重编。如果你已经踩进去了,最快的方式是把整个 buildroot output 清掉重来(粗暴但彻底):

```bash
./scripts/build_helper/build-buildroot.sh --clean
./scripts/build_helper/build-buildroot.sh --with-qt6
```

`--clean` 会 `rm -rf out/release-latest/buildroot`,把所有 stamp 和中间产物全干掉,再跑一次就是干净的完整构建。代价是多花时间,但能保证配置改动真正生效。

⚠️ **注意**:这个坑不只针对 Qt6。任何时候你改了一个 package 的 Kconfig 选项(不是 source 代码),都要警惕 stamp 缓存导致旧产物残留。Buildroot 没有"配置变了自动 clean 对应 package"的机制,这是它增量构建模型的固有缺陷。养成一个习惯:**改了配置选项就 `--clean`,改了 source 代码才靠增量。** 这一点真的坑了我半天。

## 字体这一摊:post-build 怎么"嗅探" rootfs 里有没有 Qt6

Qt6 编完了,程序也进了 rootfs,但还有个实际问题:中文字体。前面说过 DejaVu 只覆盖西文和基础符号,中文全是空白方块。手动管理字体又回到了手搓时代的老路,所以我们把这个活儿也塞进了 `post-build.sh`——但有个前提:只有 rootfs 里真有 Qt6 时才需要下中文字体,最小 rootfs(不带 Qt6)完全不需要,省下大约 30MB。

post-build.sh 用一个很朴素的判断来做这个"嗅探":检查 target 目录里有没有 `libQt6Core.so`。这是 Qt6 最基础的库,有它就说明 Qt6 被编进来了:

```bash
# post-build.sh ③-bis
if [[ -f "${TARGET_DIR}/usr/lib/libQt6Core.so" ]]; then
    # ... 下载 Noto CJK + Emoji 字体 ...
else
    echo "[post-build] Qt6 not in rootfs — 跳过 CJK/Emoji 字体(最小 rootfs)"
fi
```

进了这个 `if` 之后,post-build 会从 GitHub 下载两样东西:一份 **Noto Sans CJK Regular**(中文,大约 18MB,从一个含七个分权重 ttc 的 zip 里只取 Regular 那个,省体积),一份 **Noto Color Emoji**(表情符号,大约 9MB)。下载过程带 `--retry 3` 和缓存(`out/.fonts-cache`),所以不是每次构建都重新拉,只有缓存里没有的时候才下。下完拷到 `target/usr/share/fonts/` 里,fontconfig 启动时会自动扫到它们。

这套逻辑的好处是**完全跟着 Qt6 走**:你加 `--with-qt6`,Qt6 进了 rootfs,字体自动跟着下;不加 `--with-qt6`,最小 rootfs 里没有 `libQt6Core.so`,字体逻辑整段跳过,不多花一秒、不多占一字节。你不需要记着"编了 Qt6 还得去下字体",post-build 替你把这件事和 Qt6 的存在性绑在了一起。

需要留意的是下载依赖网络。如果构建环境网络不通(比如某些 CI runner 的代理问题),post-build 会打一条 WARN 但不中止构建——字体缺失不会让 rootfs 构建失败,只会让板子上 Qt 程序的中文显示不出来。这个降级策略是有意的:网络问题不该阻塞 rootfs 的完整性,字体属于锦上添花。

## 上板:把一个 Qt 程序跑起来

到这里 rootfs 已经带着完整的 Qt6 运行时了,最后一步是真正在板子上把程序跑起来。我们假设你已经按 [第 02 章](02_first_build.md) 的流程把 rootfs 部署到板子上(SD 卡或 NFS root),串口能登录。现在交叉编一个最简单的 QtWidgets 程序丢上去,看它能不能在屏幕上画出来。

运行 Qt 程序的关键是设对几个环境变量,让 Qt 知道走哪个平台插件、从哪读触摸:

```bash
# 在板子上(serial console / ssh)
export QT_QPA_PLATFORM=linuxfb:fb=/dev/fb0
export QT_QPA_PLATFORM_PLUGIN_PATH=/usr/lib/qt6/plugins
export TSLIB_TSDEVICE=/dev/input/event0
export TSLIB_FBDEVICE=/dev/fb0
export TSLIB_PLUGINDIR=/usr/lib/ts
export TSLIB_CALIBFILE=/etc/pointercal
export QT_QPA_FB_TSLIB=1
```

我们逐个说这些变量为什么是这些值。`QT_QPA_PLATFORM=linuxfb:fb=/dev/fb0` 告诉 Qt 用 linuxfb 这个平台插件,并且显式指定 framebuffer 设备是 `/dev/fb0`——i.MX6ULL 的 LCD 控制器映射出来的就是 fb0。`QT_QPA_PLATFORM_PLUGIN_PATH` 指向平台插件(qml、tslib 输入插件等)的安装目录,Buildroot 会把它放在 `/usr/lib/qt6/plugins` 下,如果你的路径不一样以实际为准。

tslib 那一组变量是触摸校准的标配。`TSLIB_TSDEVICE` 指向触摸屏的 input 事件设备,具体是 `event0` 还是 `event1` 取决于你的触摸控制器在内核里注册的顺序——正点原子这块屏的 Goodix 触摸在 i2c-1 上,上电后你可以 `cat /proc/bus/input/devices` 看它落在哪个 eventN 上,别照抄。`TSLIB_FBDEVICE` 是 framebuffer,和上面的 fb0 一致。`TSLIB_PLUGINDIR` 指向 tslib 的滤镜插件目录(线性校准、去抖这些),`TSLIB_CALIBFILE` 是校准结果存放的位置。`QT_QPA_FB_TSLIB=1` 则是 Qt linuxfb 插件这边的一个开关,告诉它"触摸输入从 tslib 走,别自己去读 event 设备"。

先别急着跑你的程序,触摸校准得先做一次。tslib 自带一个 `ts_calibrate` 工具(Buildroot 的 tslib 包会装上),在屏幕上点五个点生成校准数据写到 `TSLIB_CALIBFILE`:

```bash
ts_calibrate    # 五点校准,结果写到 /etc/pointercal
ts_test         # 可选:拖一个图标满屏跑,验证校准是否准
```

校准完之后,就可以跑你的 Qt 程序了:

```bash
./my_qt_app
```

如果一切正常,屏幕上应该出现你的窗口,触摸也能响应。如果程序一闪而过或者报 `Could not load plugin`,十有八九是上面的环境变量路径不对,或者 `/dev/fb0` 权限不够(root 下跑通常没问题)。如果是触摸没反应但画面正常,先检查 `ts_test` 能不能拖动那个图标——能拖说明 tslib 链路通,问题在 Qt 的 `QT_QPA_FB_TSLIB`;不能拖说明 tslib 本身没配对,回去查 `TSLIB_TSDEVICE` 是不是指对了 event 设备。

走到这一步,Qt6 在 i.MX6ULL 上就算真正活了:linuxfb 负责画面输出到 framebuffer,tslib 负责把触摸坐标校准读准,八个子模块提供 QML、多媒体、图表、串口、虚拟键盘这些能力,中文字体由 post-build 自动补齐。和原来 qt-compile-pipeline 那条手工流水线比,现在只要一个 `--with-qt6`,Buildroot 把从源码到 rootfs 的整条链路全接管了,版本对齐、产物干净、可复现。给板子拍张照,屏幕上亮着你的 Qt 界面,这趟折腾就算收工了。

## 下一步

Qt6 集成讲完了,但如果你是从旧版 IMX-Forge(手搓 rootfs + qt-compile-pipeline)升级过来的,你大概还想知道:原来那堆 `install_*.sh` 脚本、merge_overlay、手编 Qt 的流水线,现在分别被 Buildroot 的什么机制替代了,迁移的时候要注意哪些不兼容的点。下一章就是一份完整的迁移对照表,把旧方案和新方案逐项对齐:[第 12 章:手搓→Buildroot 迁移对照](12_migration_guide.md)。
