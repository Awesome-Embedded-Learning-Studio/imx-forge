# 调试与排错

::: info 本节你将学到
- 看懂 Buildroot 的 stamp 文件与构建日志,定位"卡在哪一步"
- 搞定下载失败、工具链特性声明不匹配、host 头文件泄漏、rootfs 残缺、校验闸门失败这几类高频报错
- 用 `dl/` 缓存做离线构建,用 `make legal-info` 出许可证清单
- 用 `BR2_INSTRUMENTATION_SCRIPTS`、`<pkg>-graph-depends`、`make printvars`、`gdbserver` 这些 Buildroot 自带手段做更深一层的诊断
- 记住 IMX-Forge Buildroot 四个真实踩过的坑,别再踩第二遍
:::

::: tip 前置知识 · 环境
- 读过 [09 ccache 与重建策略](09_ccache_rebuild.md),知道 `<pkg>-rebuild` 和 `make clean all` 的差别
- 读过 [05 br2-external tree 逐文件](05_br2_external_tree.md),对 `imx6ull_aes_defconfig`、`post-build.sh`、`overlay/` 的分工有印象
- 手边有 IMX-Forge 仓库,能打开 `scripts/varified_rootfs_ok.sh`、`rootfs/buildroot/configs/imx6ull_aes_defconfig`、`rootfs/buildroot/post-build.sh` 对照
:::

说实话,写这一章之前我犹豫过。Buildroot 的报错信息有时候长得像天书,一个 `make` 跑两小时最后崩在一行 GCC 报错,谁看到都头大。但正因为这样,"出错时第一反应该看哪里"这件事值得讲清楚。Buildroot 不是黑盒,它在 `output/` 下留下了相当完整的痕迹:每个包构建到哪一步、下载了什么、编译命令长什么样,全都能查。再加上 IMX-Forge 自己加的那道 rootfs 校验闸门,只要你知道这些痕迹在哪、怎么读,大多数问题十分钟内就能锁定根因。这一章就把这些"第一反应"挨个过一遍。

## 日志在哪:先读懂 stamp 文件

Buildroot 跟 BusyBox 那套"敲一下命令等结果"的思路不一样,它是一个分步、有状态的构建系统。理解它的关键,是搞懂 stamp 文件(标记文件)这套机制。

Buildroot 把每个包的构建拆成若干步,每完成一步就在该包的构建目录下写一个空的标记文件 `.stamp_<step>`。这些步骤按官方手册(`package-make-target.adoc`)的顺序是:

```
source → depends → extract → patch → configure → build
       → install-staging / install-target → install
```

每个包的构建目录长这样:`output/build/<package>-<version>/`。比如你在 IMX-Forge 里编 BusyBox,对应的目录就是 `out/release-latest/buildroot/build/busybox-<版本号>/`(具体版本随 Buildroot 2026.02 自带的 busybox 走,可在 `output/build/` 下 `ls` 确认)。进去 `ls -a` 你会看到一串 `.stamp_*` 文件:

```
.stamp_extracted
.stamp_patched
.stamp_configured
.stamp_built
.stamp_target_installed   # 装进 target/ 了
```

这套机制真正的价值在于反推。一个包构建失败了,你去看它的构建目录:如果 `.stamp_configured` 在、但 `.stamp_built` 不在,那失败就发生在 configure 之后、build 这一步。这比盯着几千行日志猜"到底崩在哪"高效得多。

调试时我们要善用这套 stamp。官方手册(`rebuilding-packages.adoc`)给了三个手动操控的命令,粒度从轻到重递增。`make <pkg>-rebuild` 会删掉 `.stamp_built`(连同其后的 install 标记),从编译步重跑编译和安装,但不会重新 configure,适合你只改了源码(`OVERRIDE_SRCDIR` 或手改 build 目录)的情况;`make <pkg>-reconfigure` 再往前一步,从 configure 步重跑,适合你改了配置选项;`make <pkg>-dirclean` 最狠,整个删掉包的构建目录,从 extract 开始全重来,这是"最干净"的单包重建,改了底层依赖或换 patch 后首选。

::: tip 踩坑预警:单包重建不会自动重打 rootfs
手册反复强调一件事:`<pkg>-rebuild` / `reconfigure` 只动这个包本身,不会重新打包 rootfs 镜像。要让改动真正落到 rootfs,后面还得跟一个 `make` 或 `make all`。在 IMX-Forge 里这一步由 `build-buildroot.sh` Step 3 的 `rsync target/ → release rootfs` 兜底,所以你跑完单包重建后,再 `./scripts/build_helper/build-buildroot.sh` 走一遍就行。
:::

至于构建日志本身,`build-buildroot.sh` 把完整 `make` 输出 tee 到了一个文件,你可以直接 grep:

```
out/release-latest/buildroot/buildmeter-full.log
```

这是整个构建的完整记录,进度条和 buildmeter 都是从它读的。报错后第一件事就是 `grep -n "Error\|error:" buildmeter-full.log | tail`,看最后崩在哪。

还有一个日常利器——`make V=1`,它会把 make 实际执行的每条命令都打出来。Buildroot 默认把编译输出压得很扁,看不清传给编译器什么参数;加上 `V=1` 之后每条 gcc 命令都裸奔在你面前,排查 `-I` 路径错、宏没定义这类问题尤其管用。

## 常见报错速查

下面这五类是 IMX-Forge 迁移到 Buildroot 后真实遇到过、或 Buildroot 用户高频撞墙的场景。我们一条一条按"症状—原因—怎么修"走一遍。

### ① 下载失败:dl/ 缓存、BR2_DL_DIR 与离线场景

症状通常是 `make` 卡在某包的 `source` 步,日志里是 `wget` / `curl` 超时或 404。Buildroot 把所有下载的源码包统一放在 `BR2_DL_DIR`,默认就是 buildroot 树里的 `dl/` 目录;在 IMX-Forge 里实际落在 `out/release-latest/buildroot/dl/`。

官方手册(`download-location.adoc`)把两件事讲清楚了:一是 `BR2_DL_DIR` 既能写在 `.config` 里,也能用同名环境变量指定;二是环境变量优先级更高,会覆盖 `.config` 里的值。所以如果你维护多个 Buildroot 工程,完全可以把下载目录共享出来:

```bash
export BR2_DL_DIR=/shared/buildroot-dl    # 写进 ~/.bashrc
```

这样所有工程的源码包都走同一个缓存,下载一次到处复用。

定位下载问题最直接的办法,是进 `dl/<pkg>/` 看对应版本号的 tarball 在不在,不在就是没下下来。`build-buildroot.sh` 给了一个只下载不构建的开关,专门用来在网络好的时候把 `dl/` 灌满:

```bash
./scripts/build_helper/build-buildroot.sh --source-only
# 等价于 make source,只把源码拉到 dl/,不编译
```

跑完 `dl/` 就齐了,后面断网也能编(见下面离线构建小节)。

### ② 工具链特性声明不匹配

我们用的是 Arm GNU Toolchain 15.2 外部工具链,`imx6ull_aes_defconfig` 里声明了一堆它的"特性":

```
BR2_TOOLCHAIN_EXTERNAL_GCC_15=y
BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_6=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y
BR2_TOOLCHAIN_EXTERNAL_HAS_SSP=y
BR2_TOOLCHAIN_EXTERNAL_LOCALE=y
BR2_TOOLCHAIN_EXTERNAL_WCHAR=y
BR2_TOOLCHAIN_EXTERNAL_THREADS=y
BR2_TOOLCHAIN_EXTERNAL_THREADS_POSIX=y
```

这些声明必须和工具链的真实能力对得上,否则 Buildroot 会在配置阶段(`olddefconfig` 之后)报类似 `toolchain doesn't support ...` 的错;更隐蔽的情况是某些包因为这些特性没声明,直接在 menuconfig 里消失、不可选(官方 FAQ 把这归为 "some packages not visible",根子就是依赖的工具链特性没满足)。

排法很直接:确认你装的工具链版本和 defconfig 声明一致。换工具链版本时,`GCC_15`、`HEADERS_6_6` 这些都要跟着改。`build-buildroot.sh` 会按 PATH 里的 `arm-none-linux-gnueabihf-gcc` 自动反推工具链根目录写进 `.config`,所以路径不用你手动改,但版本特性声明是你自己的事。

::: tip 踩坑预警:换工具链必须完整重建
手册明确说,改了工具链配置后要做完整重建(`make clean all`),别指望增量构建能自动跟上。这是因为工具链是地基,地基一动整个 target 都得重编,增量构建根本兜不住。
:::

### ③ 交叉编译里的 -I/usr/include 泄漏

这是嵌入式交叉编译最经典的坑,在 Buildroot 里也躲不开。症状是某个包编译时报一堆"宿主机头文件类型不匹配"的错,比如 `sys/types.h` 定义冲突、`struct stat` 大小对不上。

根因在于这个包的构建系统(Makefile / CMake / meson)没老老实实只用 staging sysroot 里的头文件,而是把宿主机的 `/usr/include` 也塞进了 `-I` 路径。Buildroot 已经把交叉编译环境配好了——头文件在 `output/host/<tuple>/sysroot/usr/include`,库在对应 `lib/` 下,正常的包只该用它。但有些写得不规范的包会去 `pkg-config --cflags` 拿到宿主机的路径,或者干脆硬编码 `/usr/include`。

定位办法就是前面说的 `make V=1`:看崩的那个包的 gcc 命令行里 `-I` 和 `--sysroot` 指向哪。健康的交叉编译命令应该带 `--sysroot=.../host/arm-none-linux-gnueabihf/sysroot`,且不该出现裸的 `-I/usr/include`。一旦看到宿主机路径泄漏,通常要在这个包的 `.mk` 里覆盖 `CFLAGS` / `PKG_CONFIG_PATH`,或者在 configure 选项里关掉那个探测宿主机特性的开关。

### ④ rootfs 缺设备节点或缺用户表

Buildroot 官方 FAQ(`faq-troubleshooting.adoc`)特意提醒过一件事:不要把 `output/target/` 目录直接拿去当 chroot 或 NFS root。原因是 target 目录里的"文件权限/属主/设备节点"都还没最终规范化——这些是在最后生成镜像(tarball、ext4 等)的 `post-image` 阶段,以 root 权限补齐的。你直接拿 `target/` 用,chroot 进去多半一堆命令失败。

这正是 IMX-Forge 把校验和打包拆开的原因:`build-buildroot.sh` Step 3 用 `rsync --delete` 把 `target/` 同步到 `out/release-latest/rootfs/`,最后的镜像由 `build_imx6ull_image.sh` 用 `mke2fs -d` 现打,设备节点在那个环节才补齐。

还有两个相关的"缺东西"坑要提一下。一个是缺用户表:你在 defconfig 里加了自定义用户/组(Buildroot 的 `BR2_ROOTFS_USERS_TABLES`),却忘了把表文件放进 br2-external tree,构建能过但 rootfs 里压根没那个用户。另一个是缺设备节点:我们用 `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y`(eudev 动态创建),所以静态设备节点表不是必须的;但如果你切回 `mdev` 或静态 `tmpfs`,就得在 `BR2_ROOTFS_DEVICE_TABLE` 里声明 `/dev/console`、`/dev/null` 这些。

### ⑤ varified_rootfs_ok.sh 闸门失败(issue #76 教训)

这是 IMX-Forge 独有的一道关,也是这一章最值得讲的一条。`post-build.sh` 在 Buildroot 打包前会调用 `scripts/varified_rootfs_ok.sh` 做完整性校验,任何一项致命检查不过就非零退出,整个构建当场中止:

```bash
# post-build.sh 结尾
echo "[post-build] Running rootfs verification gate..."
bash "${PROJECT_ROOT}/scripts/varified_rootfs_ok.sh" --rootfs-dir="${TARGET_DIR}"
```

这道闸门不是摆设。issue #76 的教训就在这:曾经有一次,残缺的 rootfs 流到了最终镜像里(目录不全、关键配置缺失),烧到板子上起不来,排查半天才发现是 rootfs 根本没编完整。加了这道闸门后,rootfs 不完整会在构建阶段直接被拦下,绝不流到镜像。

那它具体查什么?读一遍脚本就清楚了,分三步走。Step 1 是安全检查,拒绝把 `/` 当 rootfs、拒绝不可达的路径;Step 2 查必需目录,检查 `REQUIRED_DIRS=("bin" "sbin" "usr")` 至少存在,这是硬底线,缺一个直接 exit 1;Step 3 做完整性校验,逐个核对 `ROOTFS_DIRS`(12 个标准目录)和三个关键配置文件:

```bash
ROOTFS_DIRS=("bin" "dev" "etc" "lib" "mnt" "proc" "root" "sbin" "sys" "tmp" "usr" "home")
config_files=("etc/fstab" "etc/init.d/rcS" "etc/inittab")
```

如果 rootfs 里检测到 Qt(`libQt6Core.so*` 存在),还会额外校验 Qt 产物:必须有 `libQt6Core.so*`、`plugins/platforms/` 不能为空(linuxfb 插件),否则一样是致命错。

所以如果你在构建末尾看到这样的报错:

```
[ERROR]   ✗ etc/inittab missing
[ERROR] Rootfs verification failed
```

那不是 Buildroot 本身的 bug,是闸门在告诉你 rootfs 缺东西了。常见的诱因有 overlay 路径写错(`BR2_ROOTFS_OVERLAY` 没指对)、post-build 脚本被改坏、或者 busybox init 的 inittab 没装进来。对照 `varified_rootfs_ok.sh` 里 `verify_rootfs()` 的清单,缺哪个补哪个就行。

## 离线构建:把 dl/ 整个缓存带走

有些场景下你拿不到外网——封闭开发环境、CI 跑在隔离网络里、或者就是要保证构建 100% 可复现、不依赖上游 tarball 服务器。Buildroot 对此有现成支持,把 `dl/` 目录整个缓存下来就行。

`build-buildroot.sh --source-only` 帮你把所有包的源码拉满到 `out/release-latest/buildroot/dl/`:

```bash
# 在有网的环境跑一次
./scripts/build_helper/build-buildroot.sh --source-only
```

然后把整个 `dl/` 目录打包,带到无网环境,解压到同样位置(或者通过 `BR2_DL_DIR` 指过去)。再跑构建时,Buildroot 发现 tarball 都在本地,就不再去网络下载了。

官方手册提醒的一点很关键:如果你想留一份"确定能编出完全相同版本"的 Buildroot 快照,把 `dl/` 目录连同 buildroot 源码一起保存。这样即使上游删了某个版本的 tarball,你照样能编出 byte-identical 的结果——版本可复现性在嵌入式交付时往往是刚需。

## make legal-info:许可证合规清单

只要你的产品要出货,就得面对开源许可证合规这件事。Buildroot 内建了 `make legal-info` 来帮你收集合规材料,跑法很简单(在 buildroot O= 目录下):

```bash
make -C third_party/buildroot O=out/release-latest/buildroot legal-info
```

它会往 `output/legal-info/` 子目录里吐一堆东西。按官方手册(`legal-notice.adoc`)的说法,首先是一份 `README`,汇总说明外加 Buildroot 没能收集到的材料的警告,这个必看;`buildroot.config` 是你这份构建用的 .config,留着复现用;`sources/` 和 `host-sources/` 收所有 target 包 / host 包的源码,设了 `<PKG>_REDISTRIBUTE = NO` 的不收,打的 patch 也会按 `series` 顺序收进来;`manifest` 文件(host 和 target 各一份)列出每个包的版本、许可证等信息,未定义的标 "unknown";最后 `licenses/` 和 `host-licenses/` 是各包的许可证正文。

什么时候要跑?一句话:产品要对外发布前必跑一次。尤其是你引入了 GPL 这类强传染性许可证的包时,`legal-info` 产出的源码和许可证清单就是你的交付材料基础。

但手册也诚实地泼了盆冷水——`legal-info` 的输出基于每个包 `.mk` 里声明的许可证信息,这些声明"尽力准确"但不保证完全无误,外部工具链的源码、Buildroot 自身的源码它也不收。所以正式交付前,你和你的法务得过一遍 README 里的警告,不能直接把 `legal-info/` 当作现成的合规交付件。

## Buildroot 自带的调试手段

除了看 stamp 和日志,Buildroot 还给了几个趁手的诊断工具,我们挨个过。

### 包依赖关系:show-depends 与 graph-depends

搞不清一个包依赖谁、被谁依赖,是加包/删包时最常见的困惑。手册(`package-make-target.adoc`)提供了一组目标:

```bash
make <pkg>-show-depends              # 一阶依赖
make <pkg>-show-recursive-depends    # 递归所有依赖
make <pkg>-show-rdepends             # 谁直接依赖它(反向)
make <pkg>-show-recursive-rdepends   # 谁直接或间接依赖它
make <pkg>-graph-depends             # 画依赖图(Graphviz)
make <pkg>-graph-both-depends        # 正反向都画
```

比如你想知道 Qt6declarative 拉了哪些东西,`make qt6declarative-graph-depends` 一跑,生成的图比纯文本直观得多,尤其适合排查"为什么莫名编进了一堆包"这种事。

### 打印内部变量:make printvars

想看 Buildroot 给某个包算出来的 `DEPENDENCIES`、`SITE`、`VERSION` 到底是什么,用 `printvars`(手册 `make-tips.adoc`):

```bash
make -s printvars VARS='BUSYBOX_%DEPENDENCIES'
# BUSYBOX_DEPENDENCIES=skeleton toolchain
# BUSYBOX_FINAL_DEPENDENCIES=skeleton toolchain
# BUSYBOX_RDEPENDENCIES=ncurses util-linux
```

加 `QUOTED_VARS=YES` 输出带引号,能直接 eval 进 shell 脚本;`RAW_VARS=YES` 则输出未展开的原始 Make 表达式,方便你确认变量到底从哪推导来的。这个在排查 defconfig/fragment 合并后的实际配置时极其有用。

### BR2_INSTRUMENTATION_SCRIPTS:插桩每一步

手册 `debugging-buildroot.adoc` 给了一个更重的手段:用一个或多个脚本插桩 Buildroot 的每个构建步骤。设 `BR2_INSTRUMENTATION_SCRIPTS` 为脚本路径列表,Buildroot 会在每个包每步的 start / end 调用你的脚本,传三个参数:

```
$1 = start | end
$2 = 步骤名(extract / patch / configure / build / install-host / install-target / install-staging / install-image)
$3 = 包名
```

脚本里还能读到 `BR2_CONFIG`、`HOST_DIR`、`STAGING_DIR`、`TARGET_DIR`、`BUILD_DIR`、`BINARIES_DIR`、`BASE_DIR`、`PARALLEL_JOBS` 这些变量。典型用途是统计每个包每步耗时、或者在步骤间做额外的完整性校验。IMX-Forge 默认不开它,但你要做深度性能分析时,这是个好入口。

```bash
make BR2_INSTRUMENTATION_SCRIPTS="/path/to/timer.sh"
```

### 在板子上 gdb 调试

手册 `using-buildroot-debugger.adoc` 讲了交叉调试的套路:调试器跑在宿主机,gdbserver 跑在板子上。因为我们用外部工具链,最省事的是开 `BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY`,把工具链自带的 gdbserver 拷到 target;如果工具链没带,Buildroot 也能自己编(`BR2_PACKAGE_HOST_GDB` + `BR2_PACKAGE_GDB` + `BR2_PACKAGE_GDB_SERVER`)。

板子上起 gdbserver 监听端口:

```bash
gdbserver :2345 foo
```

宿主机用交叉 gdb 连过去(手册给的命令):

```bash
<buildroot>/output/host/bin/<tuple>-gdb \
  -ix <buildroot>/output/staging/usr/share/buildroot/gdbinit foo
(gdb) target remote <板子IP>:2345
```

注意 `foo` 要用带调试符号的版本,从 build 目录里拿,别用 `output/target/` 里 stripped 过的。

## IMX-Forge Buildroot 踩坑集

最后把我们迁移过程中实打实栽过的四个坑记一笔。这四条都在 MEMORY 里有案底,这里把来龙去脉讲清楚。

### 坑一:工具链的 INET_RPC 必须关掉

`imx6ull_aes_defconfig` 里有一行容易被忽略的注释式禁用:

```
# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set
```

这不是手抖,是必须的。Arm GNU Toolchain 用的 glibc 在 2.26 之后移除了 sunrpc(旧的 RPC 接口),工具链里压根没有这个特性。如果你从别的 Buildroot 配置抄过来、不小心把它设成 `=y`,Buildroot 会去工具链里找 RPC 支持,找不到就报错。结论很简单:用现代 glibc 工具链,这一项永远是 `not set`。

### 坑二:/etc/securetty 不补,root 登录被全拒

`post-build.sh` 里有这么一段:

```bash
# /etc/securetty:项目 busybox.config 带 CONFIG_FEATURE_SECURETTY=y,login 要求
# 该文件列出允许 root 登录的 tty;buildroot skeleton 不建它 → root 登录被全拒。
if [[ ! -f "${TARGET_DIR}/etc/securetty" ]]; then
    printf '%s\n' console tty1 tty2 tty3 tty4 tty5 tty6 \
        ttyS0 ttyS1 ttymxc0 ttymxc1 ttymxc2 ttyAMA0 ttyUSB0 \
        > "${TARGET_DIR}/etc/securetty"
fi
```

现象是这样的:rootfs 烧好,串口能登录到提示符,但输 root 回车后被直接踢出来,或者反复要求密码。原因在于我们的 BusyBox 配置开了 `CONFIG_FEATURE_SECURETTY=y`,login 程序会查 `/etc/securetty`,只有列在里面的 tty 才允许 root 登录;而 Buildroot 的 skeleton 默认不生成这个文件。所以必须在 post-build 里补上,并把我们的调试串口 `ttymxc0` 写进去。这个坑隐蔽就隐蔽在——只有你用 root 登录时才触发,普通用户一点事没有。

### 坑三:br2-external 的 name 必须是小写

`rootfs/buildroot/external.desc` 里:

```
name: imxforge
```

Buildroot 会根据这个 `name` 生成一个路径变量,格式是 `BR2_EXTERNAL_<name>_PATH`,其中 `<name>` 就是 `external.desc` 里写的原样。这里的 `name: imxforge` 对应的变量是 `BR2_EXTERNAL_imxforge_PATH`(全小写),不是 `BR2_EXTERNAL_IMXFORGE_PATH`。

`imx6ull_aes_defconfig` 里引用 overlay 和 post-build 用的就是这个变量:

```
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_imxforge_PATH)/post-build.sh"
BR2_PACKAGE_BUSYBOX_CONFIG="$(BR2_EXTERNAL_imxforge_PATH)/fragments/busybox.config"
```

一旦你手贱把变量名写成大写,或者把 `external.desc` 的 name 改成带大写/连字符的,defconfig 里的路径就解析不出来,overlay 和 post-build 全失效,rootfs 会缺一大堆东西。更坑的是,这一切 Buildroot 不会报明显错误,只是 silently 不应用。这是一个典型的"静默失败"坑,排查时先确认这个变量名的大小写是否和 `external.desc` 的 name 对得上。

### 坑四:Qt6declarative QUICK 拉 shadertools,host qt6base 要 make clean

这条留给 Qt6,第 11 章会详细讲,这里先点出来。`fragments/qt6.config` 里这一行是有代价的:

```
BR2_PACKAGE_QT6DECLARATIVE_QUICK=y   # QtQuick(拉 qt6shadertools + host qmlprofiler 需 HOST_QT6BASE_NETWORK)
```

开 QUICK 会拉 `qt6shadertools`,而 shadertools 的 host 工具(`qmlprofiler` 等)要求 host qt6base 带上 NETWORK 特性(`HOST_QT6BASE_NETWORK`)。问题在于 host qt6base 可能在更早的构建里已经编过一次(没带 network),cache 里是旧产物,这时 `qt6declarative` 会因为 host 工具缺符号而编不过。

排法是对 host qt6base 做一次 `make clean` 级别的重建,让它带着新的 NETWORK 选项重编:

```bash
make qt6base-dirclean   # 连 host 带 target 全清
# 然后重跑 build-buildroot.sh --with-qt6
```

这就是为什么 Qt6 全模块构建偶尔会"第一次编不过、清一下再编就过了"。第 11 章会讲 Qt6 的完整集成,含这个坑的标准排法。

## 下一步

这一章把 Buildroot 的排错思路过了一遍:从 stamp 文件读懂构建状态、用 `V=1` 和 `buildmeter-full.log` 抓现场、用 `dl/` 和 `legal-info` 做离线与合规、用 `graph-depends` / `printvars` / instrumentation / gdbserver 做深度诊断,外加 IMX-Forge 自己的校验闸门和四个真实坑。掌握这些,你在构建报错时就不会两眼一抹黑了。

接下来 [11 Qt6 集成实战](11_qt6_integration.md),我们把这一章提到的 Qt6 fragment(`qt6.config`)和"坑四"完整展开,讲清楚怎么把 Qt6 全模块(linuxfb + tslib,无 GPU)编进 Buildroot rootfs,以及那个 host qt6base make clean 的标准排法。
