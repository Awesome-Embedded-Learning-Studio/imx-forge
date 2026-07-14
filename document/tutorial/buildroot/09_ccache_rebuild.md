# ccache 与重建策略

::: info 本节你将学到
- ccache 的工作原理,以及 Buildroot 怎么把它内化进构建流程
- IMX-Forge 在 defconfig 和 CI 两层是怎么配 ccache 的,这两种配法各有什么坑
- Buildroot 的重建三级粒度:`<pkg>-rebuild` / `<pkg>-reconfigure` / `<pkg>-dirclean`,各自删掉哪些 stamp、从哪一步重跑
- 官方手册给出的一套"什么时候必须全量重建"的判断规则,改了哪些东西增量能搞定、改了哪些东西不 `make clean all` 就是在骗自己
- ccache 缓存和 Buildroot 的 output 目录是什么关系,`make clean` 到底清不清它

:::

::: tip 前置知识 · 环境
- 读过 [02 第一次构建](02_first_build.md),至少跑通过一次 `build-buildroot.sh`,对 `out/release-latest/buildroot/` 下那堆目录有印象
- 读过 [05 br2-external tree 逐文件](05_br2_external_tree.md),知道 `imx6ull_aes_defconfig` 和 `build-buildroot.sh` 各自管哪一摊
- 环境:Buildroot 2026.02(`third_party/buildroot/`),内置 ccache 4.12.3,外部工具链 Arm GNU Toolchain 15.2.rel1
:::

## 为什么要专门讲 ccache 和重建

说实话,第一次全量跑 `build-buildroot.sh` 的时候你可能觉得还行,十几分钟出 rootfs,可以接受。但等你开始频繁改东西,今天调一下 busybox 配置,明天加个 package 试效果,后天又改了 post-build 脚本,每次都十几分钟,累计下来一上午就交代了。要是你开了 Qt6(`--with-qt6`),那更刺激,一次构建两到四小时,改一行代码重编一次,一天能折腾的次数用一只手就数得过来。

ccache 就是来解决这个问题的。它的核心思路很简单:编译器每次编译一个 `.c` 文件,传入的参数和源文件内容其实经常是重复的,那把编译结果缓存起来,下次遇到一模一样的输入就直接吐 `.o`,跳过真正的编译。这对 Buildroot 这种"改一个包、其余包参数没变"的场景命中率极高,重复构建能省掉大量时间。

但 ccache 在 IMX-Forge 里不是开个开关就完事的。我们实际上有两层 ccache 配置:一层是 Buildroot 自己内置的 `BR2_CCACHE=y`,另一层是 CI 环境里用 PATH 符号链接做的"编译器包装器"。这两层大多数时候和平共处,但它们撞在一起的时候,会把工具链检测逻辑带偏,报一个看起来八竿子打不着的 `Cannot execute cross-compiler`。这个坑(commit 886158f3)折腾了我半天,这一章会详细讲。

同样值得专门讲的还有重建策略。Buildroot 跟 `make` 的增量编译不完全是一回事:它不会自动检测你改了什么然后智能决定重编哪些包,这件事官方手册说得很直白,它干脆不尝试做这种检测,全靠你自己判断。所以搞清楚"改了什么该用哪个级别的重建命令",是从"能跑"到"高效地跑"的分水岭。接下来我们就把这两块拆开讲。

## ccache 是什么:编译器缓存的工作原理

在讲 Buildroot 怎么集成之前,我们先搞懂 ccache 底层在干什么,不然后面遇到命中率低或者缓存异常的时候你会两眼一抹黑。

ccache 本质上是一个编译器的前置代理。正常情况下你调 `gcc -c foo.c -o foo.o`,gcc 直接编译。装了 ccache 之后,你在 gcc 前面套一层,`ccache gcc -c foo.c -o foo.o`,ccache 会先算一个 hash:这个 hash 的输入包括预处理后的源文件内容(宏展开后的)、编译器版本、所有编译参数(`-O2`、`-I` 路径、`-D` 宏等等)。算完 hash 去缓存目录里找,如果命中,直接把上次缓存的 `foo.o` 拷过来,整个过程不调用真正的 gcc;如果没命中,才把命令转发给 gcc 做真正的编译,然后把结果塞进缓存。

你可能会问,那命中率高不高?这取决于你的构建模式。Buildroot 的典型场景是"改一个包的配置,其余几十个包的编译参数完全没变",对这些没变的包来说,hash 输入一模一样,全是 cache hit,直接秒过。真正需要重新编译的只有你动过的那个包。这就是 ccache 能大幅加速 Buildroot 重复构建的根本原因。

但有一点要记住,hash 的输入里包含编译参数的绝对路径。Buildroot 编译时 `-I` 和 `--sysroot` 都带绝对路径,指向 `output/host/.../sysroot` 之类的地方。如果你换了 `O=` 输出目录,这些绝对路径就变了,hash 全部对不上,缓存瞬间全 miss。这个问题后面讲 `BR2_CCACHE_USE_BASEDIR` 的时候会说到解决办法。

## Buildroot 内置的 ccache 集成

Buildroot 把 ccache 做成了一等公民,不用你自己搞 PATH 包装那一套。打开 `BR2_CCACHE=y` 之后,Buildroot 会自动做这么几件事:先编译一个 host 端的 ccache(版本跟着 Buildroot 走,2026.02 带的是 4.12.3),装到 `output/host/bin/ccache`;然后在所有包的编译命令前面自动插上 ccache,不管是 host 包还是 target 包都走它。你不需要手动改任何 `.mk` 文件,这个机制是全局的。

我们的 `imx6ull_aes_defconfig` 里就开了一行:

```
# ===== ccache(加速重复构建)=====
BR2_CCACHE=y
```

就这么一行,没有别的。缓存目录由 `BR2_CCACHE_DIR` 配置项决定,默认值是 `$HOME/.buildroot-ccache`。注意这个默认位置是在 Buildroot 的 output 目录之外的,这是有意为之,这样不同的 Buildroot 工程(不同的 `O=` 目录)可以共享同一个缓存,你编完 IMX-Forge 的 rootfs,再编另一个项目的 rootfs,公共包(比如 zlib、openssl)的编译结果还能复用。

这里有个容易混淆的细节得提一下。Buildroot 给 ccache 打了个补丁,把环境变量名从标准的 `CCACHE_DIR` 改成了 `BR_CACHE_DIR`。你可以去看 `package/ccache/ccache.mk`,里面有一段 `HOST_CCACHE_PATCH_CONFIGURATION`,用 sed 把 ccache 源码里所有 `getenv("CCACHE_DIR")` 替换成 `getenv("BR_CACHE_DIR")`。这是因为 `CCACHE_DIR` 这个名字在 Buildroot 的 autotargets 机制里已经被占用了,为了不冲突才改的。所以你在 Buildroot 环境里直接跑 `ccache -s` 查统计信息的时候,它读的是 `BR_CACHE_DIR` 而不是 `CCACHE_DIR`,这个区别在后面排查缓存问题的时候会用到。

查缓存状态有两个途径。在 Buildroot 的 O= 目录下跑 `make ccache-stats`,会输出缓存大小、命中次数、未命中次数这些信息。第一次全量构建的时候你看到的几乎全是 miss,因为没有历史缓存;跑完第二次构建再看,hit rate 应该相当可观。如果你想调缓存大小,也不用手动去碰 ccache 命令,Buildroot 提供了一个统一的入口:

```bash
make CCACHE_OPTIONS="--max-size=5G" ccache-options
```

这条命令会被转发给 ccache 执行,等价于直接跑 `ccache --max-size=5G`。如果你嫌默认缓存太小(默认是 5G,但全量构建攒下来的东西可能不止这些),可以在 defconfig 里用 `BR2_CCACHE_INITIAL_SETUP` 设一个初始命令,Buildroot 编完 ccache 之后会自动跑一次。

## CI 环境里的另一层 ccache:PATH 包装器

到这里为止讲的都是 Buildroot 内部的 ccache,但 IMX-Forge 的 CI 里还有另一层。我们的 kernel 和 U-Boot 不是 Buildroot 编的,它们走的是 `scripts/build_helper/build-uboot.sh` 和 `build-linux.sh`,跟 Buildroot 完全独立。这些构建也要加速,但它们没有 Buildroot 那种内建 ccache 集成,怎么办?

答案是用 ccache 的"编译器包装器"模式。原理是:ccache 除了能像 `ccache gcc ...` 这样显式调用,还能伪装成编译器本身。你在 PATH 前面塞一个目录,里面放几个符号链接,把 `arm-none-linux-gnueabihf-gcc` 指向 `/usr/bin/ccache`,这样构建系统调用 `arm-none-linux-gnueabihf-gcc` 的时候,实际执行的是 ccache,ccache 再去调真正的 gcc。

CI 里就是这么干的,你可以在 `.github/workflows/ci-build.yml` 的 U-Boot 构建步骤里看到完整的套路:

```bash
ccache -M 2G && ccache -z           # 设缓存上限 2G,清零统计计数器
mkdir -p /workspace/ccache-bin
ln -sf /usr/bin/ccache /workspace/ccache-bin/arm-none-linux-gnueabihf-gcc
ln -sf /usr/bin/ccache /workspace/ccache-bin/arm-none-linux-gnueabihf-g++
ln -sf /usr/bin/ccache /workspace/ccache-bin/arm-none-linux-gnueabihf-ar
export PATH="/workspace/ccache-bin:${PATH}"
./scripts/build_helper/build-uboot.sh
ccache -s                            # 构建完打印统计信息
```

三个符号链接把 gcc、g++、ar 都指过去,然后把 `ccache-bin` 塞到 PATH 最前面。这样 U-Boot 的 Makefile 里调 `$(CC)` 的时候,命中的就是 ccache 包装器。Linux NXP BSP 和 Linux Mainline 的构建步骤用的是完全一样的套路,只是缓存大小不同(NXP BSP 给 2G,Mainline 给 5G,因为 mainline 内核源码更大)。

这里还配了四个环境变量,每一个都有来头,我们逐个看:

```
CCACHE_DIR=/workspace/.ccache
CCACHE_BASEDIR=/workspace
CCACHE_NOHASHDIR=true
CCACHE_COMPILERCHECK=content
```

`CCACHE_DIR` 指定缓存存放位置,这里放到了 workspace 下,方便 GitHub Actions 的 `actions/cache` 把它存起来跨 run 复用。`CCACHE_BASEDIR` 和 `CCACHE_NOHASHDIR` 配合使用:前面说过 ccache 的 hash 包含绝对路径,`CCACHE_BASEDIR` 告诉 ccache"以 `/workspace` 为基准,把绝对路径里这个前缀替换成相对路径",`CCACHE_NOHASHDIR=true` 则让 ccache 不把当前工作目录的路径算进 hash。这两个一起,才能保证你在不同路径下构建同一个代码库时缓存能命中。

`CCACHE_COMPILERCHECK=content` 这个也很关键。默认情况下 ccache 会用编译器的 mtime 来判断"编译器是不是换过了",但 CI 环境里每次 run 重新拉镜像,编译器的 mtime 总是新的,会导致缓存全 miss。设成 `content` 之后,ccache 改成对编译器二进制内容做 hash,只要编译器版本没变就认,这就解决了 CI 缓存命中率的问题。

Buildroot 的 CI 构建在 `ci-full.yml` 里也用了同一套 PATH 包装器。也就是说,Buildroot 构建时同时存在两层 ccache:CI 的 PATH 包装器管 kernel/uboot 那部分的编译器调用,Buildroot 内置的 `BR2_CCACHE=y` 管它自己的包编译。这两层的缓存目录是不一样的(PATH 包装器用 `CCACHE_DIR=/workspace/.ccache`,Buildroot 内置用默认的 `$HOME/.buildroot-ccache`),各管各的。

## 真正的坑:ccache 包装器咬到工具链检测

事情到这里还没完。上面那套 PATH 包装器在 CI 里跑得好好的,但它给 `build-buildroot.sh` 的工具链检测逻辑挖了一个很深的坑,这就是 commit 886158f3 修的那个 bug。

我们先看背景。`build-buildroot.sh` 要解决的一个问题是:Buildroot 的 defconfig 里 `BR2_TOOLCHAIN_EXTERNAL_PATH` 需要一个绝对路径指向工具链根目录,但这个路径因机器而异(CI 容器里是 `/opt/arm-gnu-toolchain`,你本地可能装在 `/usr/local/arm-gnu-toolchain` 或者别的什么地方)。所以脚本会在 Step 1c 自动从 PATH 里找到 `arm-none-linux-gnueabihf-gcc` 的位置,反推出工具链根目录,用 sed 写进 `.config`。

旧版代码的逻辑很简单,一行搞定:

```bash
_tc_gcc="$(command -v arm-none-linux-gnueabihf-gcc || true)"
```

`command -v` 在 PATH 里找到第一个匹配的可执行文件,返回它的完整路径。然后脚本拿这个路径 `readlink -f` 解析出真实位置,再往上退一层就是工具链根目录。在没有 ccache 的环境下,这套逻辑完全没问题。

但你把 CI 的 PATH 包装器加进来之后,事情就变了。PATH 最前面是 `/workspace/ccache-bin`,里面有一个 `arm-none-linux-gnueabihf-gcc` 的符号链接指向 `/usr/bin/ccache`。`command -v` 先命中这个符号链接,`readlink -f` 跟着链接解析到底,得到的是 `/usr/bin/ccache`。脚本拿着 `/usr/bin/ccache` 往上退一层,算出 `TC_ROOT=/usr`。然后 Buildroot 去找 `/usr/bin/arm-none-linux-gnueabihf-gcc`,当然找不到(工具链根本不在 `/usr` 下),直接报 `Cannot execute cross-compiler`。

这个报错信息非常有迷惑性。你一看"无法执行交叉编译器",第一反应是工具链没装或者 PATH 没配对,但实际上工具链好好的,只是被 ccache 包装器截胡了,导致脚本把工具链根目录算错了。我当时对着这个报错搜了半天,确认工具链在、PATH 在、权限也没问题,就是搞不明白为什么 Buildroot 说找不到编译器,直到去翻了 `build-buildroot.sh` 算出来的 `TC_ROOT` 才发现它指向了 `/usr`,这才反应过来是 ccache 符号链接的事。

修复方案是遍历整个 PATH,逐个检查每个目录里的 `arm-none-linux-gnueabihf-gcc`,跳过那些 readlink 之后 basename 是 `ccache` 的候选,取第一个真正的编译器:

```bash
_tc_gcc=""
_oifs="$IFS"; IFS=':'; read -ra _pd <<< "${PATH}"; IFS="$_oifs"
for _d in "${_pd[@]}"; do
    [[ -z "$_d" ]] && continue
    _c="${_d}/arm-none-linux-gnueabihf-gcc"
    [[ -x "$_c" ]] || continue
    _r="$(readlink -f "$_c" 2>/dev/null || printf '%s' "$_c")"
    [[ "$(basename "$_r")" == "ccache" ]] && continue   # ccache 包装,跳过
    _tc_gcc="$_c"; break
done
```

逻辑很直白:把 PATH 按 `:` 拆成数组,逐个目录进去找编译器,找到了就 `readlink -f` 解析它到底指向谁,如果解析出来 basename 是 `ccache`,说明这是个包装器符号链接,跳过继续找下一个;直到找到 basename 是 `arm-none-linux-gnueabihf-gcc` 的真实编译器为止。这样不管 CI 在 PATH 前面塞了多少个 ccache 包装器,脚本都能穿透它们找到真正的工具链。

这个坑的教训是:ccache 的 PATH 包装器虽然对加速构建很有效,但它会改变 `command -v` 的行为,任何依赖"从 PATH 找编译器真实路径"的脚本都可能被它带偏。如果你自己在别的地方也写了类似的工具链检测逻辑,记得把 ccache 包装器的情况考虑进去。

⚠️ 注意:如果你本地也配了 ccache 的 PATH 包装器(不只是 CI),这个坑同样会踩到。`build-buildroot.sh` 修复之后已经能自动跳过了,但如果你用的是旧版本的脚本,碰到 `Cannot execute cross-compiler` 先检查一下 PATH 里有没有 ccache 包装器。

## 重建策略:Buildroot 的三级粒度

ccache 解决的是"重新编译更快"的问题,但要搞清楚"哪些东西需要重新编译",那就是重建策略的事了。Buildroot 官方手册(`rebuilding-packages.adoc`)在这一点上非常坦诚:它不做自动检测,改了配置之后哪些包该重编,全靠你自己判断。它给你的武器是三个粒度递增的 make 目标,背后靠的是 stamp 文件机制。

我们先说 stamp 文件。Buildroot 把每个包的构建拆成一系列步骤,每完成一步就在该包的构建目录(`output/build/<package>-<version>/`)下写一个空的标记文件,名字是 `.stamp_<step>`。步骤的顺序是 `source → depends → extract → patch → configure → build → install-staging / install-target → install`。所以你去 `ls -a` 一个包的构建目录,会看到一串 `.stamp_*` 文件,最后完成到哪一步一目了然。(第 10 章会用 stamp 文件来定位构建失败卡在哪一步,这里先知道它的存在就行。)

三个重建命令本质上就是在操作这些 stamp 文件,让 Buildroot 认为某个包"还没做到那一步",从而从指定步骤重跑。

第一个是 `make <pkg>-rebuild`,粒度最细。它删掉 `.stamp_built`(以及它之后的 install 标记),让 Buildroot 从编译步重新跑编译和安装,不重新 configure。适合你只改了源码的情况,比如你用了 `OVERRIDE_SRCDIR` 指向自己的源码目录改了几行,或者直接手改了 build 目录里的文件。configure 阶段的东西(比如 Makefile 已经生成好了)不动,省掉了重新跑 configure 的时间。

第二个是 `make <pkg>-reconfigure`,粒度中等。它进一步删掉 `.stamp_configured`,从 configure 步重跑,自然也包含后面的编译和安装。适合你改了这个包的配置选项(比如在 menuconfig 里给它开了个子功能)的情况。注意 `reconfigure` 已经隐含了 `rebuild`,不需要两个都跑。

第三个是 `make <pkg>-dirclean`,粒度最粗也最干净。它不删 stamp 文件,直接把整个包的构建目录删掉,下次构建时从 extract 开始全重来。这是最彻底的单包重建方式,适合你改了这个包的底层依赖、换了 patch、或者 `rebuild` 之后结果还是不对想排除一切缓存干扰的情况。`dirclean` 的代价是最大的,extract、patch、configure 全部重来,但有时候你就需要这个"从零开始"的确定性。

这里有一个手册反复强调的坑,一定要记住:`<pkg>-rebuild`、`reconfigure`、`dirclean` 这三个命令只作用于指定的包本身,不会重新打包 rootfs 镜像。也就是说,你重建完一个包,Buildroot 确实把新的编译结果装进了 `output/target/`,但如果你有 post-build 脚本或者最终的镜像打包步骤,它们不会自动重跑。要让改动真正落到最终产物,后面还得跟一个 `make` 或 `make all`。

在 IMX-Forge 里这一步更不需要你操心。`build-buildroot.sh` 的 Step 3 会用 `rsync --delete` 把 `output/target/` 同步到 `out/release-latest/rootfs/`,最终的镜像由 `build_imx6ull_image.sh` 用 `mke2fs -d` 现打。所以你跑完单包重建之后,再 `./scripts/build_helper/build-buildroot.sh` 走一遍(它会从 Step 2 的增量构建接着跑,然后 Step 3 做 rsync),改动就到 rootfs 了。

## 什么时候必须全量重建

上面三个命令管的是"重编一个包",但有些改动影响的不止一个包,甚至影响整个构建。这种时候你必须做全量重建,也就是 `make clean all`。`make clean` 删掉 `output/` 下所有构建产物(build 目录、host 目录、target 目录全清),`all` 从头开始构建。ccache 缓存不受影响,后面会专门讲。

那到底什么情况下必须全量重建,什么情况下增量就行?官方手册(`rebuilding-packages.adoc`)给了一套判断规则,我把它按 IMX-Forge 实际会遇到的情况整理一下。

改了目标架构配置,必须全量。比如你改了 CPU 型号、浮点策略(`BR2_ARM_FPU_*`)、EABI 类型这种架构层面的东西,影响的是整个系统每一个包的编译选项,增量重建没法覆盖。改了工具链配置也一样,必须全量。工具链是地基,编译器版本、C 库类型、内核头版本这些东西一变,所有包都要重编。我们在 `imx6ull_aes_defconfig` 里那一堆 `BR2_TOOLCHAIN_EXTERNAL_*` 声明,任何一个动了都要 `make clean all`,别指望增量能自动跟上。

加了一个新包,不需要全量。Buildroot 会发现这个包从没编过,自动编它。但有一个陷阱:如果你加的是一个库,而系统里已经有别的包"可以但没有"链接这个库,那些已编好的包不会自动重编来利用新加的库。手册举的例子是 `ctorrent` 加 `openssl`:你启用 `openssl` 后 Buildroot 会编它,但不会自动重编 `ctorrent` 去链接 `openssl`,你得手动 `make ctorrent-rebuild` 或者干脆全量。

删了一个包,必须全量才能真正清除。Buildroot 不会主动把已删除包装进 target 和 staging 的文件清掉,你得 `make clean all` 才能保证 rootfs 里没有残留。不过手册也说,如果你不急着这一刻清干净,可以等下次有空的时候再全量,反正那些多余文件在 rootfs 里也不影响功能(只是占点空间)。

改了一个包的子选项,通常只需要重编那个包。`make <pkg>-reconfigure` 就够了,不用全量。但同样有例外:如果这个子选项加了某个特性,而另一个已经编好的包恰好能利用这个特性,那个包不会自动重编。不过这种情况比较少见,大多数时候改子选项重编自己就行。

改了 rootfs skeleton(Buildroot 内部的 `system/skeleton/`),必须全量,因为 skeleton 是所有包的安装基础。但如果你改的是自己的 overlay 目录、post-build 脚本或者 post-image 脚本,那就不需要全量重建,直接跑 `make`(或者 `build-buildroot.sh`)就行,Buildroot 会在打包阶段重新处理这些。

还有一个容易忽略的:如果你的包 A 在 `.mk` 里声明了 `FOO_DEPENDENCIES = bar`,然后你改了 `bar` 的配置重编了它,`foo` 不会自动跟着重编。Buildroot 不跟踪这种依赖链式的重建,你要么手动把所有依赖 `bar` 的包都重编一遍,要么直接全量。

总结一下,手册给了一条很好的经验法则:当你面对一个构建错误,不确定之前改的配置会带来什么连锁反应时,先做一次全量重建。如果全量重建还报同样的错,那至少你可以确定这不是增量重建没覆盖到导致的,问题出在别的地方。随着经验积累,你会越来越清楚什么时候真的需要全量、什么时候增量就够,省下的时间也会越来越多。

## ccache 和重建的关系:几个容易搞混的点

讲完重建策略,我们回头把 ccache 和重建之间的关系理清楚,有几个点特别容易搞混。

第一个,`make clean` 和 `make distclean` 都不清 ccache 缓存。这是手册(`make-tips.adoc`)特意提醒的。`make clean` 删的是 `output/` 下的构建产物,`make distclean` 连 `.config` 也一起删,但 ccache 缓存在 `$HOME/.buildroot-ccache`(或者你设的 `BR2_CCACHE_DIR`),在 output 目录外面,所以不受影响。这其实是好事:你全量重建之后 ccache 还在,那些参数没变的包照样能命中缓存,重建速度比第一次快得多。如果你真的想清掉 ccache 缓存(比如缓存坏了或者想从头统计命中率),直接 `rm -rf` 那个目录就行。

第二个,换 `O=` 输出目录之后缓存大面积 miss 的问题。前面提过,ccache 的 hash 包含编译参数里的绝对路径,而 Buildroot 的编译命令带了大量指向 output 目录的绝对路径(`--sysroot`、`-I` 之类)。你换一个 `O=` 目录,这些路径全变,hash 全对不上,缓存形同虚设。解决办法是开 `BR2_CCACHE_USE_BASEDIR`(在 menuconfig 里叫 "Use relative paths"),它会把所有指向 output 目录内部的绝对路径改写成相对路径,这样换目录之后 hash 照样能对上。代价是编译出的 `.o` 里嵌入的路径也变成了相对路径,gdb 调试的时候可能找不到源文件(除非你先 cd 到 output 目录)。IMX-Forge 目前没有显式开这个选项,因为我们的 `O=` 目录是固定的 `out/release-latest/buildroot`,不会频繁换。但如果你要维护多个并行的 Buildroot 构建目录,建议开了它。

第三个,ccache 只在 Buildroot 构建过程中生效。你直接在命令行调 `output/host/bin/arm-none-linux-gnueabihf-gcc` 去编什么东西,不走 ccache。手册说可以用 `BR2_USE_CCACHE=1` 环境变量来强制开启,但默认是不开的。所以如果你发现"明明开了 ccache,为什么手动编译没加速",这就是原因。

最后,关于 `make ccache-stats` 的用法。构建完之后跑一次看看命中率,是个好习惯。如果你发现命中率很低(比如低于 50%),通常意味着编译参数在频繁变化,可能是你在频繁改配置导致 hash 对不上,也可能是 `BR2_CCACHE_USE_BASEDIR` 没开、绝对路径在作怪。盯着这个数字调优,能让 ccache 的收益最大化。

## IMX-Forge 里的实际操作流程

讲了一堆原理和规则,最后落到 IMX-Forge 里,日常操作其实就是这么几个场景。

场景一:你只改了 overlay 里的某个文件,或者改了 `post-build.sh`。这种最简单,不需要重编任何包,直接 `./scripts/build_helper/build-buildroot.sh` 跑一遍就行。Step 2 的增量构建发现没有包需要重编(快速跳过),Step 3 的 rsync 会把改动同步到 rootfs。

场景二:你改了某个包的配置(比如 busybox 的 `.config`)。先 `make busybox-reconfigure` 重编这个包,然后跑 `build-buildroot.sh` 完成 rsync。如果你想更省事,也可以直接 `build-buildroot.sh --reconfigure`(它会重新应用 defconfig),但这会让所有包都检查一遍,稍微慢一点。

场景三:你改了工具链相关的配置,或者动了架构选项。没什么好说的,`make clean all` 全量重建。在 IMX-Forge 里就是先 `build-buildroot.sh --clean` 清掉 output,再 `build-buildroot.sh` 全量构建。有了 ccache,第二次全量会比第一次快不少。

场景四:某个包编出来结果不对,怀疑是增量构建的残留导致的。直接 `make <pkg>-dirclean` 把它的构建目录整个删掉,然后重新构建。如果 dirclean 之后结果还是不对,那就该考虑全量重建了。

这些场景覆盖了日常开发的绝大多数情况。掌握它们之后,你在 IMX-Forge 里改 rootfs 的效率会有质的提升,不用每次都傻等全量构建了。

## 下一步

这一章把 ccache 的工作原理、IMX-Forge 的两层 ccache 配置(以及那个 PATH 包装器坑)、Buildroot 的重建策略过了一遍。核心就两件事:用 ccache 让重复编译变快,用对重建命令避免"改了不生效"或者"没必要的全量重建"。

下一章 [10 调试与排错](10_debugging.md),我们把这一章提到的 stamp 文件拿来当诊断工具,讲清楚构建报错时该怎么从 stamp、日志、`make V=1` 这些痕迹里锁定根因,外加 IMX-Forge 独有的 rootfs 校验闸门和四个真实踩过的坑。
