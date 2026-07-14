# Rootfs 定制三板斧

::: info 本节你将学到
- Buildroot 定制 rootfs 的三个切入点——overlay、post-build 脚本、post-image 脚本——各自在构建流水线的哪一环被触发，谁先谁后，以及"谁能看到谁改的东西"由什么决定
- `BR2_ROOTFS_OVERLAY` 怎么把静态文件叠到 target 上，它替代了手搓时代的哪个脚本，IMX-Forge 为什么暂时把它留空
- `BR2_ROOTFS_POST_BUILD_SCRIPT`(我们这位主力 `post-build.sh`)在 `$1 = TARGET_DIR` 里干了哪些 Buildroot skeleton 默认不干的活：补 linuxrc、补 `/home`、补 securetty、拉 SDMA 固件、按需拉 CJK 字体、最后跑校验闸门
- 第三板斧 post-image 为什么 IMX-Forge 偏偏不用它，而是把镜像组装的活儿甩给外部脚本
:::

::: tip 前置知识 · 环境
- 读过 [04 配置体系](./04_kconfig_fragments.md)，知道 `$(BR2_EXTERNAL_imxforge_PATH)` 这个变量是从 `external.desc` 的 `name` 派生出来的；这一章我们会反复用到它指向 `rootfs/buildroot/` 这件事
- 跑通过一次 [02 第一次构建](./02_first_build.md)，脑子里有个 `out/release-latest/buildroot/output/target/` 的画面，知道那是 Buildroot 拼出来的 rootfs 目录树
- 环境不变：Buildroot 2026.02(`third_party/buildroot/`)，br2-external tree 在 `rootfs/buildroot/`
:::

## 前言：为什么光改配置不够

上一章我们把 Kconfig 那一套配得明明白白——加 package、开 ccache、按需 merge Qt6 fragment，改 defconfig 就能搞定日常九成的需求。但事情到这里还没完。你很快会撞上这样一类需求：我想往 rootfs 里塞一个自己写的 `/etc/rc.local`、想补一个 Buildroot skeleton 根本不生成的 `/etc/securetty`、想在打包前从网上拉一份 SDMA 固件塞进 `lib/firmware/`。这些活儿，没有一个是能用 `BR2_PACKAGE_*=y` 表达的——它们不是"编一个包"，而是"在 rootfs 快成型的时候，动手脚"。

Buildroot 给的正解就是三个钩子，我习惯叫它"rootfs 定制三板斧"：**overlay** 叠静态文件、**post-build 脚本**在打包前干杂活、**post-image 脚本**在镜像生成后再收尾。这一章我们就挨个拆，每一步都落在 `rootfs/buildroot/` 里的真实文件上，顺带把笔者踩过的几个坑一起讲透——其中 securetty 那个，真的坑了我半天。

## 三板斧全景：它们各自卡在流水线的哪一环

在动手之前，我们先把三者的触发顺序搞清楚，这一点真的很重要——因为"谁能看到谁改的东西"完全由这个顺序决定。Buildroot 的 `target-finalize` 和 `target-post-image`(在 `third_party/buildroot/Makefile` 里)把这件事写得清清楚楚，我把它从 Makefile 里拎出来，简化后是这样的：

```
target-finalize:
    1. 把所有 package 的产物 rsync 进 target/
    2. 收尾清理(strip 二进制、删 *.a/*.la/文档、生成 os-release……)
    3. rsync BR2_ROOTFS_OVERLAY 的内容进 target/      ← 第一板斧：overlay
    4. 跑 BR2_ROOTFS_POST_BUILD_SCRIPT($1 = target/)  ← 第二板斧：post-build
    (target-finalize 结束)

target-post-image: 依赖 target-finalize + 各文件系统镜像构建
    5. fakeroot：建设备节点、套权限、跑 post-fakeroot 脚本
    6. 生成文件系统镜像(ext2/ext4/squashfs……)
    7. 跑 BR2_ROOTFS_POST_IMAGE_SCRIPT($1 = BINARIES_DIR) ← 第三板斧：post-image
```

这张时间线里有几个细节值得我们先记在脑子里。**overlay 永远在 post-build 之前**，所以 post-build 脚本看到的是"已经被 overlay 叠加过"的 target，它可以放心去修 overlay 带进来的文件，也可以补 overlay 没干完的活。**post-build 跑在 fakeroot 之前**，这意味着它是用你真实的构建用户身份在执行，权限就是你本机当前的权限——这点后面 securetty 那段会用到，也是为什么它能在 target 里随便建文件。而 **post-image 已经是镜像生成之后了**，它拿到的是 `BINARIES_DIR`(里面躺着 `rootfs.ext4` 这类成品)，改的是镜像产物，改不了 target 树本身。

另外那个"清理"步骤(第 2 步)也别忽略：它会在 overlay 之前把 target 里的 `*.a`、`*.la`、文档、pkgconfig 这些"只有开发期才用得上"的东西全删掉。这正是 IMX-Forge 从手搓 rootfs 切过来之后体积从 442MB 瘦到 173MB 的关键之一——手搓脚本当年是把 `.a` 全量拷进去的，Buildroot 默认就帮你 strip 掉了。理解了这条流水线，我们就能挨个上板斧了。

## 第一板斧：overlay——静态文件叠加

最轻的一板斧，但也是最常用的。`BR2_ROOTFS_OVERLAY` 指向一个目录，构建时 Buildroot 会把这个目录的内容**原样 rsync 到 target/ 上，同名文件直接覆盖**。它适合干一类活：往 rootfs 里塞那些"现成的、不需要生成逻辑的"文件——一个自定义的 `/etc/rc.local`、一组板端脚本、一份你提前准备好的配置文件。

我们在 defconfig 里就是这么挂的(`rootfs/buildroot/configs/imx6ull_aes_defconfig`)：

```makefile
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_imxforge_PATH)/overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_imxforge_PATH)/post-build.sh"
```

`$(BR2_EXTERNAL_imxforge_PATH)` 上一章讲过，就是 `rootfs/buildroot/` 的绝对路径，所以 overlay 目录就是 `rootfs/buildroot/overlay/`。

这里有个细节可能会让你意外：这个目录**目前是空的**，除了一个 `README.md`。这不是我们忘了填，而是有意为之。在手搓 rootfs 那会儿，这套活儿是 `scripts/merge_overlay_rootfs.sh` 干的——它在运行时把 `rootfs/overlay/rootfs/` 下的内容 cp 合并进 rootfs。迁到 Buildroot 之后，绝大多数"该往 rootfs 塞的东西"都被更合适的机制接管了：BusyBox 配置走 `fragments/busybox.config`、第三方库走 Buildroot package、目录骨架和 fstab/inittab/rcS 走 skeleton 包。真正剩下的、需要 overlay 承载的静态文件，IMX-Forge 目前没有，所以它就空着。

但结构是完整的，等你哪天要往板子上塞一个自己的应用脚本，直接放进 `rootfs/buildroot/overlay/` 里对应的路径就行。比如你想加一个 `/usr/bin/myapp` 和一个 `/etc/myapp.conf`，就在 overlay 里这么摆：

```
rootfs/buildroot/overlay/
├── usr/bin/myapp        # 构建时会被 rsync 到 target/usr/bin/myapp
└── etc/myapp.conf       # 同理，叠到 target/etc/myapp.conf
```

overlay 不挑文件类型，可执行文件、配置、库都行，连权限和软链都会被 rsync `-a` 原样保留。有一类东西不建议塞 overlay——那些需要"生成逻辑"的内容，比如要根据构建参数决定写什么、要从网上下载的文件。这些活儿交给下一板斧的 post-build 脚本，overlay 只管搬静态文件。这也正是为什么我们的 overlay 暂时空着：剩下的脏活累活，全都被 post-build 脚本包圆了。

## 第二板斧：post-build 脚本——干活的主力

如果说 overlay 是"搬东西"，那 post-build 就是"什么都能干"的那一板斧，也是 IMX-Forge 真正压了重活的地方。`BR2_ROOTFS_POST_BUILD_SCRIPT` 指向的脚本，会在所有 package 安装完、overlay 叠加完、但还没进 fakeroot 打包之前执行，**第一个参数 `$1` 就是 `target/` 目录的绝对路径**。它本质上就是个普通 bash 脚本，你想干啥都行——下载文件、改配置、建软链、跑校验。

我们这位主力就是 `rootfs/buildroot/post-build.sh`，满打满算 90 来行，把 Buildroot 默认不做、但 IMX-Forge 必须要的活全包了。我们逐段拆开看。

### 开头：拿到 target 目录，定好项目根

```bash
set -e

TARGET_DIR="${1:?TARGET_DIR (buildroot post-build \$1) required}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
```

开头这几行值得说一句。`set -e` 是命根子——post-build 里任何一条命令失败，整个 Buildroot `make` 立刻中止，绝不会放一个残缺的 rootfs 过关(这个教训来自 issue #76，后面校验闸门那段还会再提)。`$1` 被 Buildroot 塞成 `target/` 的绝对路径，我们存进 `TARGET_DIR`，后面所有操作都基于它。`PROJECT_ROOT` 是反推出来的，因为脚本里要下载固件、跑项目里的校验脚本，得知道项目根在哪。

### ① linuxrc 软链：Buildroot skeleton 默认不建的东西

```bash
# ① linuxrc 软链(仅当 busybox 已装且 linuxrc 不存在)
if [[ -x "${TARGET_DIR}/bin/busybox" && ! -e "${TARGET_DIR}/linuxrc" ]]; then
    echo "[post-build] Creating linuxrc -> bin/busybox"
    ln -sf bin/busybox "${TARGET_DIR}/linuxrc"
fi
```

第一条活儿是补一个 `/linuxrc -> bin/busybox` 的软链。为什么需要它？这是因为老的 NFS root 和一些老式 init 约定内核挂载 rootfs 后会去找顶层的 `/linuxrc`，而 Buildroot 的 skeleton 默认不建这个软链——它认为你用的是现代 init，直接走 `/sbin/init` 就够了。为了兼容那些还会去碰 `/linuxrc` 的场景，我们手动补上。注意那个 `if` 条件：只在 busybox 已经装进去、且 linuxrc 不存在时才建，这样脚本就是幂等的，重复构建不会报错也不会覆盖。

### ② /home 目录：补 Buildroot skeleton 的一个小遗漏

```bash
# ② 补建 buildroot skeleton 不保证、但项目期望的目录
mkdir -p "${TARGET_DIR}/home"
```

Buildroot skeleton 默认用 `/root/` 当 root 的家目录，不建 `/home`。但我们的项目校验脚本和一些板端习惯会假设 `/home` 存在，所以这里 `mkdir -p` 补上。一条 `mkdir -p`，稳就稳在它不抱怨目录已存在——这正是它和 overlay 的一个微妙差别：overlay 是文件存在即覆盖，而 `mkdir -p` 是"有就跳过、没有就建"，各有所长。

### ②-bis securetty：这一条真的坑了我半天

接下来这段是我个人血压拉满的地方，也是从手搓 rootfs 迁过来第一个炸我的坑：

```bash
# /etc/securetty:项目 busybox.config 带 CONFIG_FEATURE_SECURETTY=y,login 要求
# 该文件列出允许 root 登录的 tty;buildroot skeleton 不建它 → root 登录被全拒。
if [[ ! -f "${TARGET_DIR}/etc/securetty" ]]; then
    printf '%s\n' console tty1 tty2 tty3 tty4 tty5 tty6 \
        ttyS0 ttyS1 ttymxc0 ttymxc1 ttymxc2 ttyAMA0 ttyUSB0 \
        > "${TARGET_DIR}/etc/securetty"
fi
```

事情是这样的：我们的 BusyBox 配置(`fragments/busybox.config`)开了 `CONFIG_FEATURE_SECURETTY=y`，这个选项会让 BusyBox 的 `login` applet 在 root 登录时去翻 `/etc/securetty`，只有当前 tty 出现在这个文件里才放行。问题在于 Buildroot skeleton 压根不生成 `/etc/securetty`——结果就是 rootfs 烧上去，串口登录提示符出来了，你输 root、回车，它直接把你怼回来，而且不告诉你为什么。你会在串口前怀疑人生半天，直到想起来 securetty 这回事。

所以这里我们把 IMX6ULL 会用到的 tty 全列进去：`console`、几个虚拟控制台 `ttyN`、串口 `ttyS0/1`、**`ttymxc0/1/2`(这是 i.MX6ULL 的调试串口，我们的 getty 就跑在 ttymxc0 上)**、以及 `ttyAMA0`/`ttyUSB0` 兜底。这一段是典型的"post-build 干的活"：它不是配出来的，是补 Buildroot 没干的。手搓时代的 rootfs 是自己生成的 securetty，迁过来后这活儿就得 post-build 接手，不然你会收获一个能启动但 root 死活登不进去的 rootfs。

### ③ SDMA 固件：从网上拉的运行时依赖

```bash
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

i.MX 的 SDMA 驱动(音频 DMA 等会用到)运行时需要一份固件 `sdma-imx6q.bin`，放在 `lib/firmware/imx/sdma/` 下。这玩意儿不能进版本库，只能构建时下载，所以 post-build 是它的天然归宿。这一段替代了手搓时代的 `install_firmwares.sh`。

这里有两个设计点想点出来。**第一是缓存**：`FW_CACHE` 放在 `out/.firmware-cache`，下载一次就不再下了，增量构建不会反复去敲 GitHub 的门。**第二是失败不致命**：下载失败只是往 stderr 打个 WARN，不会让构建挂掉——这是因为网络问题(代理抽风、离线构建)不应该阻塞 rootfs 本身的产出，顶多 SDMA 驱动在板子上报个缺固件，不影响 rootfs 完整性。这种"可选项失败不拖垮主流程"的取舍，在 post-build 里很常见，你要分清哪些失败必须靠 `set -e` 拦下来，哪些可以降级成告警。

### ③-bis CJK 字体：按需加载，最小 rootfs 不背这个锅

紧接着的字体逻辑很巧妙：它先探测 `target/usr/lib/libQt6Core.so` 在不在，**只有 Qt6 rootfs 才去拉 Noto CJK 和 Emoji 字体**——因为只有跑 Qt GUI 才需要中文字体和表情；最小 rootfs(默认 CI 那份，不含 Qt6)根本用不上，跳过能省差不多 30MB：

```bash
# Noto CJK + Emoji 字体:仅当 rootfs 含 Qt6 时下载(Qt GUI 才需;最小 rootfs 无 Qt6 → 跳过)
if [[ -f "${TARGET_DIR}/usr/lib/libQt6Core.so" ]]; then
    FONTS_DIR="${TARGET_DIR}/usr/share/fonts"
    # ... 下载 NotoSansCJK-Regular.ttc 和 NotoColorEmoji.ttf 到 ${FONTS_DIR}
else
    echo "[post-build] Qt6 not in rootfs — 跳过 CJK/Emoji 字体(最小 rootfs)"
fi
```

这个"探测产物决定行为"的写法，让同一个 post-build 脚本既能服务 Qt6 构建、又能服务最小构建，不用维护两份脚本。DejaVu 那套西文字体则是跟着 Qt6 fragment 里的 `BR2_PACKAGE_DEJAVU=y` 走 Buildroot 包装的，不在这里手工下。

### ④ 校验闸门：绝不让残缺 rootfs 流到镜像

最后一段是 post-build 的压轴，也是整个构建流程里的一道硬闸门：

```bash
# ④ 校验闸门(致命;失败则 buildroot make 中止)
echo "[post-build] Running rootfs verification gate..."
bash "${PROJECT_ROOT}/scripts/varified_rootfs_ok.sh" --rootfs-dir="${TARGET_DIR}"
```

这一行跑的是项目里的 `scripts/varified_rootfs_ok.sh`(对，它历史上就一直拼错成 "varified"，名字沿用至今没改)，它会检查 rootfs 的目录结构(bin/sbin/usr 必须在、dev/etc/lib/proc 等一票目录必须齐全)、关键配置、Qt 产物(如果有的话)，任何一项致命检查不过就直接非零退出。配合脚本开头的 `set -e`，这里一挂，整个 `make` 立刻中止。

这条闸门的来头值得说一下。`varified_rootfs_ok.sh` 在手搓时代是个"又构造又校验"的脚本——它一边建目录骨架、写 fstab/rcS/inittab、跑第三方安装，一边做校验。Buildroot 接管之后，构造那一摊全交出去了(skeleton + packages + overlay + post-build)，这个脚本就瘦成了**纯校验**，在 post-build 里、以及在 `release-all` 编排里各跑一次，确保任何一份流到镜像打包的 rootfs 都是完整的。这个意识来自 issue #76 的教训：曾经有一份残缺的 rootfs 悄悄溜进了镜像，烧上去起不来，排查半天才定位。从那以后校验闸门就成了硬性的一环——post-build 收尾必跑，绝不省。

## 第三板斧：post-image——为什么我们偏偏不用它

讲了半天前两板斧，第三板斧 post-image 我们却根本没配。这事儿得说清楚，免得你以为我漏了。

`BR2_ROOTFS_POST_IMAGE_SCRIPT` 是 Buildroot 提供的第三个钩子，从流水线上看，它在文件系统镜像(ext2/ext4/squashfs 这些)生成**之后**执行，`$1` 是 `BINARIES_DIR`(里面是 `rootfs.ext4` 这类成品)。它的典型用途是把镜像拿去做后处理——裁尺寸、压 squashfs、转成 fastboot 格式、拷到发布目录，或者顺手生成一份烧录脚本。

那 IMX-Forge 为什么不设它？defconfig 末尾那段注释把原因讲得很直白：

```makefile
# ===== Rootfs 输出 =====
# 不用 buildroot 自带 ext2/ext4 镜像:它尺寸固定,加 Qt6 后需不断手调;
# 且最终 SD/eMMC 镜像由 build_imx6ull_image.sh 从 out/release-latest/rootfs/ 用
# mke2fs -d 现打(按实际内容动态尺寸,更灵活),NFS root 直接挂 rootfs/ 目录。
# 故 buildroot 只产 target/(→ rsync 到 rootfs/),不打 fs image。
```

换句话说，我们压根没让 Buildroot 去生成文件系统镜像——defconfig 里没有 `BR2_TARGET_ROOTFS_EXT2` / `EXT4` 这些选项。Buildroot 在我们这儿只干一件事：把 `target/` 目录树产出来。剩下的活儿分两路走。`build-buildroot.sh` 的 Step 3 把 `target/` rsync 到 `out/release-latest/rootfs/`：

```bash
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

然后真正的 SD/eMMC 镜像由 `scripts/image_builder/build_imx6ull_image.sh` 用 `mke2fs -d` 现打——按 rootfs 实际内容动态算尺寸，加 Qt6 也不会撑爆；而开发期最常用的 NFS root，更是连镜像都不需要，板子直接 NFS 挂 `rootfs/` 这个目录就完事。这种"各管一段"的分工，比硬塞一个 post-image 脚本去处理 Buildroot 自己产的固定尺寸 ext4 要灵活得多。

所以 post-image 这板斧，我们认得它、知道它干啥，但就是故意不抡。你以后要是真让 Buildroot 自己出镜像(比如想要一份 ext4 或 squashfs 产物)，再把 `BR2_ROOTFS_POST_IMAGE_SCRIPT` 挂上、写个脚本把镜像拷到发布目录，也是顺手的事。

⚠️ 注意，上面 rsync 那串 `--exclude` 可不是随手写的，踩过才知道疼。板子用 NFS root 启动时会以 root 身份往 `var/lib/seedrng`、`var/lib/urandom`、`var/lib/dhcp`、`var/lib/network` 这些目录里写东西(随机数种子、dhcp 租约、网络状态)，而构建机上的你是非特权用户，`rsync --delete` 想删这些 root 属主的文件会失败、整个 rsync 报错退出。所以提前把这几个运行时目录排除掉——它们是板子的运行时缓存，本就不该跟 host 同步。你以后自己加 exclude 一定确认是"运行时、板子写"的目录，千万别手滑把真该同步的东西也排了。

## 三种姿势怎么选：回头看

到这里三板斧都讲完了，我们回头看，日常该把活儿派给谁。判断的标尺其实就一句话——这活儿有没有生成逻辑：如果是现成的静态文件，overlay 最省事；如果需要判断、下载、生成，就进 post-build 脚本；如果是镜像层面的后处理(而我们又恰好让 Buildroot 出镜像了)，才轮到 post-image。IMX-Forge 目前的分工是 overlay 留空(没有纯静态文件要塞)、post-build 脚本承担所有脏活、post-image 不用(镜像外部组装)。这套组合不是教条，你完全可以等真有静态文件了再往 overlay 里填，也完全可以等需要 Buildroot 原生镜像了再启用 post-image——三板斧都在工具箱里，什么时候取用看你手上的活儿。

## 小结

这一章我们把 rootfs 定制的三个切入点串成了一条流水线：overlay 在 post-build 之前把静态文件叠进 target，post-build 脚本在打包前补 Buildroot skeleton 不干的活(我们这位 `post-build.sh` 补了 linuxrc、`/home`、securetty，拉了 SDMA 固件和按需的 CJK 字体，最后跑 `varified_rootfs_ok.sh` 闸门)，post-image 则在镜像生成后收尾——而 IMX-Forge 因为把镜像组装甩给了外部脚本，这第三板斧故意留空。三者的触发顺序(overlay → post-build → fakeroot → 镜像 → post-image)决定了谁能看到谁的改动，这一点在你排查"为什么我改的文件没生效"时会救你一命。

掌握这些，你就拥有了在 rootfs 成型前后动手脚的全部能力。

## 下一步

三板斧讲的都是"怎么往现成的 Buildroot 体系里塞定制"。可如果你要加的是一个完整的第三方软件——有它自己的源码、有自己的构建系统、想让它像普通 Buildroot 包一样能在 `make menuconfig` 里勾选——那就得自己写一个 package 了。下一章我们就来动手加一个自定义 package，看看 `generic-package` 那套 `Config.in` + `*.mk` 的组合到底怎么搭。

→ [07 添加自定义 package](./07_custom_package.md)


