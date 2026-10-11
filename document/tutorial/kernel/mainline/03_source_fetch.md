---
title: 取源码：从 stable 树拉下 v7.2.9
---

# 取源码：从 stable 树拉下 v7.2.9

> 上一篇把编译环境备齐，这一篇咱们干移植的第一件实事：把内核源码树拉到硬盘上，并固定在 v7.2.9 这一个点上。下载源码听着没什么技术含量，坑恰恰都藏在两个决定里——从哪棵树拉，拉到哪个点；弄反了，后面每一篇一开局就对不上号。收尾标准八个字：树在位，版本可验证。本篇只取树：内核配置留给 05，设备树留给 06，编译与启动在 06 收官，这里都不碰。

::: tip 前置知识 · 环境
- 宿主依赖与交叉工具链 arm-none-linux-gnueabihf 的安装在[从零开始搭建主线内核编译环境](02_env_setup.md)里完成；本篇不编译，工具链还派不上用场，但目录约定沿用那一篇
- 仓库实路径：内核树是子模块 third_party/linux_mainline；板级设备树的唯一原件在 driver/device_tree/alpha-board/linux/
- 路径上下文：本篇的宿主操作都在仓库根 ~/imx-forge 下进行，对的是 third_party/linux_mainline 这棵停在 v7.2.9 的 stable 树，用的工具只有 git 与 make
:::

## 一、移植第一步：把树固定在一个可复现的点上

拿源码有什么可讲的？`git clone` 一下就完了，很多朋友的第一反应都是这句。咱们把这一下拆开看，里面压着两个决定：从哪棵树拉，拉到哪个点。这两个决定都做对，后面的配置、设备树、编译才有的谈；做错一个，下一篇一开局就会撞上本篇第二节的报错。

拉到哪个点，答案是把 tag 固定下来，不追分支。教程这类文本有个底线要求：可重放。本篇里每条命令的输出都原样印在正文中，一年后您拿这篇文档照做，拉下来的树必须还能产出一样的版本号、一样的 commit 哈希。分支头做不到这一点——它天天在动，今天 clone 与下个月 clone 拿到的是两棵不同的树，文档里印的输出全部对不上号，您还没法判断是自己做错了，还是树变了。

tag 没有这个问题：它指向的 commit 永远不变，升版本在仓库里是显式的一次动作，而不是默认跟着某个分支漂。所以本卷所有章节统一对着 v7.2.9 写。这个版本是 stable 团队 2026-10-03 发布的补丁点，带着 v7.2.0 以来每一轮的修复，本仓库子模块的提交记录里现在就躺着这一条，第四节实测给咱们看。

## 二、躲不开的坑：主树上没有 v7.2.9

这条坑笔者真实踩过，现象从一条报错开始。假使照着直觉，从最有名的那个内核仓库取 v7.2.9：

```bash
# 主机 临时空仓库(仓库外演示,git init 一个空目录再跑)
git fetch https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git refs/tags/v7.2.9
```

```text
fatal: couldn't find remote ref refs/tags/v7.2.9
```

报错没有撒谎，主树上确实没有这个引用。根因是两棵树的分工：torvalds 主树只在每个大版本的发布点上打 tag，外加发布前的候选版本；发布之后所有带第三段号码的补丁版本，从 v7.2.1 一路到 v7.2.9，都不在主树，它们由 stable 团队在另一棵仓库里维护，地址是 `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git`。咱们拿 `git ls-remote` 当探针，把两棵树的 tag 集比一比，结论自己就出来了：

```bash
# 主机 任意目录(不需要本地仓库)
git ls-remote https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git 'refs/tags/v7.2*'
```

```text
237a1c39e8dfd3e1c6f1f023eea37a48ec04cc63	refs/tags/v7.2
8d3ae59288f1e7d58d76558a6ee96d533bc5019f	refs/tags/v7.2^{}
728e68a889bcf257b1e67298b12c360e5c3a13e0	refs/tags/v7.2-rc1
dc59e4fea9d83f03bad6bddf3fa2e52491777482	refs/tags/v7.2-rc1^{}
4c45e14df2f4e77982ad70d6d8e3fe750edd4c37	refs/tags/v7.2-rc2
8cdeaa50eae8dad34885515f62559ee83e7e8dda	refs/tags/v7.2-rc2^{}
...(rc3 至 rc7 与 rc1、rc2 形态相同,此处截断)
```

主树有 v7.2，有一整串 rc，唯独没有 v7.2.x。咱们把同一把探针换到 stable 树上：

```bash
# 主机 任意目录(不需要本地仓库)
git ls-remote https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git refs/tags/v7.2.9
```

```text
bd50482a9c7a6eb91468f1064a346a75e677e692	refs/tags/v7.2.9
```

::: warning 地址指错树，报错不会告诉您该去哪
couldn't find remote ref 这句话只说引用不存在，不说差多远、去哪找。第一次撞上的朋友很容易怀疑自己版本号敲错了，或者怀疑网络出了问题。根因在发布流程的分工：x.0 发布点进主树，x.y.z 补丁点只进 stable 树，两边各管各的。解法是把 URL 里的 torvalds 换成 stable，其余一字不改；用 `git clone --branch v7.2.9` 撞主树同样找不到这个点，报错措辞不同，根因相同。这个排查手法本身值得您带走：`git ls-remote` 加上地址和引用名就是一把探针，任何一棵树、任何一个镜像，tag 在不在当场见分晓。笔者拿它验过一个国内常见镜像 `mirrors.tuna.tsinghua.edu.cn/git/linux.git`：连接正常，但 tag 集与主树一字不差，v7.2.9 同样不在——它是主树的镜像。镜像可以加速，地址必须选镜像了 stable 树的那一个，不然主树的坑原样跟着搬家。
:::

## 三、两条取树的路：快速路与工程路

### 快速路：浅克隆，只要这一个点

您要是目标明确，就是把本卷跟完，浅克隆最省事：

```bash
# 主机 ~/(您打算放源码的地方)
git clone --depth 1 --branch v7.2.9 \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
    linux-mainline
cd linux-mainline
```

`--branch` 后面跟分支名也跟 tag 名，这里给的是 tag；`--depth 1` 让 git 只搬这一个提交的对象，不用把全量历史背回来，时间与磁盘都省下一大截。代价也得说清：历史只有一层，`git log` 只剩一条记录。以后您想看某个驱动是怎么一步步演变成现在这样的，就得往深补：`git fetch --deepen=<N>` 一层一层加深，`--unshallow` 一次补全，按需选。

::: warning 未实测标注
浅克隆命令的完整执行笔者在本环境没有跑完（到 kernel.org 的下载链路太慢，中途停掉了），tag 的存在性由上一节 ls-remote 实测背书；克隆的耗时与体积跟网络强相关，以您本机实测为准。
:::

### 工程路：子模块，树是仓库的一个部件

仓库自己走的是子模块这条路，树被当成仓库的一个部件管理。您在仓库根目录就能看到登记：

```bash
# 主机 ~/imx-forge
cat .gitmodules
```

```ini
[submodule "third_party/linux_mainline"]
	path = third_party/linux_mainline
	url = https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
	shallow = true
	ignore = dirty
```

这是摘录，.gitmodules 里还有 uboot、buildroot 等五个子模块条目，形态相同。URL 指向 stable 树，`shallow = true` 告诉 git 按浅方式取；`ignore = dirty` 的用处第六节揭晓。子模块的机制值得您花一分钟弄明白：父仓库不保存内核源码，只在索引里记一个叫 gitlink 的 commit 指针，标明子模块该停在哪个提交。

```bash
# 主机 ~/imx-forge
git ls-tree HEAD third_party/linux_mainline
```

```text
160000 commit 5fce161649b4d779d1b76d9fcd52dc77779774b8	third_party/linux_mainline
```

`160000` 是 git 专门留给子模块的文件模式号，后面的哈希就是 gitlink。父仓库 HEAD 里记的就是 v7.2.9 这个提交（5fce1616）；此前它固定在 Linux 7.1（8cd9520d），本次把基线挪到 v7.2.9，gitlink 跟着改指这一条，您跑一下 `git log -- third_party/linux_mainline` 就能看到这两代固定点。所谓升级内核版本，在仓库层面的全部动作就是把 gitlink 从一个提交挪到另一个，外加跑一遍构建，仅此而已。

从零把这棵树取下来，两条命令：

```bash
# 主机 ~/imx-forge
git submodule update --init --depth=1 third_party/linux_mainline
git -C third_party/linux_mainline fetch --depth 1 \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
    'refs/tags/v7.2.9:refs/tags/v7.2.9'
```

第二条值得咱们单独解释。子模块 update 认提交不认 tag：它按 gitlink 指的哈希把提交搬下来就收工，tag 引用不在跟随范围。可下一节的验证里，describe 与 rev-parse 都要拿 v7.2.9 这个名字说话，所以得用这条 refspec 把 tag 一并补取回来（快速路的 `--branch v7.2.9` 克隆自带 tag，用不着这一步）。

::: warning 未实测标注
笔者本环境的子模块早已初始化完毕，没法把从零拉取这条链路原样重放一遍；行为以 .gitmodules 里 `shallow = true` 的登记为准。update 取的是 gitlink 指的那一个提交，落位即算成功；tag 引用要靠第二条 fetch 补上，refspec 写法是 git 的标准用法，效果在下一节的验证里当场见分晓。
:::

### 远端名不是地址，update 认的是 init 时的登记

工程路里有个容易混的细节：子模块里 `git remote` 看到的名字，与 .gitmodules 里登记的 URL，是两回事。远端名（origin、stable 这些）只是您本地的昵称，叫什么都行；`git submodule update` 这类动作不看昵称，但它认的地址也不是每次现读 .gitmodules——`git submodule init` 那一刻把 .gitmodules 里的 URL 拷贝进父仓库的 .git/config（`submodule.third_party/linux_mainline.url` 这一条），之后 update、CI 拉取一律认这份登记，您再改 .gitmodules 它不会自动跟着变。`git submodule sync` 就是为这事准备的：把 .gitmodules 的现值重新拷进登记。

这话不是空谈，咱们手里这个仓库自己就是活例子。.gitmodules 已改指 stable 树，父仓库登记的却还是 init 当年的主树地址：

```bash
# 主机 ~/imx-forge
git config --get submodule.third_party/linux_mainline.url
```

```text
https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
```

后果落在您头上很具体：检出若是 7.1 那会儿初始化的，直接跑前面那条从零取树的命令，git 就拿着这份主树登记去找 5fce1616：这个提交只在 stable 树里，git 当场报 did not contain 5fce1616，取树失败。仓库自己的发布脚本 release.sh 在缺提交时兜底走的也是 submodule update，认的是同一份登记，这个坑对它同样成立。所以改过 .gitmodules 的老检出，得先同步登记再取：

```bash
# 主机 ~/imx-forge
git submodule sync -- third_party/linux_mainline
git submodule update --init --depth=1 third_party/linux_mainline
```

不想动登记也可以手动补提交（`git -C third_party/linux_mainline fetch stable`，stable 这个远端是笔者手工补的，您的检出若没有，先 `remote add` 一个再 fetch）。名字与地址的实测放在下一节，咱们拿 `remote -v` 对着看。

## 四、验证：树在位，版本可复现

收尾标准就八个字：树在位，版本可验证。咱们在仓库根一口气跑五条命令（走工程路从零取树的朋友，前面补 tag 的那条 fetch 已经跑过，这里的 describe 与 rev-parse 才有名字可查）：

```bash
# 主机 ~/imx-forge
make -s -C third_party/linux_mainline kernelversion
git -C third_party/linux_mainline log -1 --format='%H %ci %s'
git -C third_party/linux_mainline describe --tags
git -C third_party/linux_mainline rev-parse 'v7.2.9' 'v7.2.9^{}'
git -C third_party/linux_mainline remote -v
```

```text
7.2.9
5fce161649b4d779d1b76d9fcd52dc77779774b8 2026-10-03 12:43:16 +0200 Linux 7.2.9
v7.2.9
bd50482a9c7a6eb91468f1064a346a75e677e692
5fce161649b4d779d1b76d9fcd52dc77779774b8
origin	https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git (fetch)
origin	https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git (push)
stable	https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git (fetch)
stable	https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git (push)
```

咱们逐条过。头一行 `kernelversion` 由内核顶层 Makefile 提供，`-s` 让 make 别吭声、只吐版本号，7.2.9 就是本卷的基准数。第二行 `log -1` 给出树顶提交：5fce1616，提交说明就一句 Linux 7.2.9，日期 2026-10-03，与 stable 团队发布这个补丁点的时间一致。第三行 `describe --tags` 输出是光杆的 v7.2.9，不带任何后缀，说明 HEAD 不多不少，正停在 tag 上，一格未漂。

第四行的两个哈希是防您混淆用的。第二节从 stable 树探到的 bd50482 与这里树顶的 5fce1616 不是同一个对象，这不是哪里出了错：v7.2.9 是附注 tag，tag 自己也是一个 git 对象（bd50482），它再指向真正的提交（5fce1616）；`rev-parse` 不带 `^{}` 给前者，带 `^{}` 给后者。两组数与远端两两相合，这棵树就是 v7.2.9 原样。

最后四行 `remote -v` 正好把上一节的远端名问题落到实测：origin 名下挂着 torvalds 主树的旧地址，那是早年从主树克隆留下的遗迹；stable 名下才是 .gitmodules 登记的地址。两套名字并存互不打架；自动化动作（update、CI 拉取）取的是 init 时拷进父仓库 .git/config 的那份登记，不是每次重读 .gitmodules——上一节要 sync 的原因正在这。您手动 fetch 时才需要自己挑名字。

## 五、树结构初览：嵌入式视角挑三处看

内核树顶层有 33 个条目（笔者 `ls` 数过），一次看完没有意义，咱们只看后面几篇要反复回来的地方。

板级设备树集中在 `arch/arm/boot/dts/nxp/imx/` 底下，咱们拿探针数一数 imx6ull 打头的文件：

```bash
# 主机 ~/imx-forge/third_party/linux_mainline(内核树内)
ls arch/arm/boot/dts/nxp/imx/ | grep -c '^imx6ull'
ls arch/arm/boot/dts/nxp/imx/ | grep '^imx6ull' | head -5
ls arch/arm/configs/ | grep imx_v6
```

```text
72
imx6ull-14x14-evk.dts
imx6ull-aes.dts
imx6ull-aes.dtsi
imx6ull-colibri-aster.dts
imx6ull-colibri-aster.dtsi
imx_v6_v7_defconfig
```

72 个 imx6ull 打头的文件。这份清单摄于跑过构建脚本后的树（含两个 aes 拷入文件），上游 v7.2.9 原样为 70 个，名单里没有 aes 两行。名单头一个 imx6ull-14x14-evk.dts 是 NXP 官方评估板的板级描述，咱们这块正点原子的板子跟它是近亲：同一个 SoC，内存、屏幕、PHY 的接法各有取舍，后面做设备树时它是第一份参考文献。名单里的 imx6ull-aes 两个文件得单独交代：它们不在上游 v7.2.9 里，是 build-linux.sh 从仓库拷进来的板级设备树，刚拉下来的树里没有，第六节马上说。

`arch/arm/configs/` 那一行也先记下：全 ARM 平台的 defconfig 都放在这里，imx_v6_v7_defconfig 是 NXP 系 SoC 的通用基线，05 那一篇会带咱们回到这里，从它出发做配置。

`drivers/` 按子系统分家，后面外设各篇的主角都住在这里，咱们在 v7.2.9 里把三个地址都点过名：显示的 eLCDIF 驱动在 drivers/gpu/drm/mxsfb/（lcdif_drv.c），网卡 FEC 驱动在 drivers/net/ethernet/freescale/（fec_main.c），触摸的 Goodix 驱动在 drivers/input/touchscreen/（goodix.c）。目录名就是子系统名，找驱动先猜目录再 `ls`，多数时候比全局搜索快。平台层 arch/arm/mach-imx/ 如今只剩 SoC 级杂项支撑（anatop、CPU 电源管理这类），时钟驱动搬去了 drivers/clk/imx/，6ULL 对应的是 clk-imx6ul.c，复位控制器在 drivers/reset/reset-imx7.c，本卷基本不进去改，知道位置就行。

顶层的 Makefile 是整棵树的构建入口，`kernelversion` 目标就定义在它里面，05 的 defconfig 加载也归它管；它连注释带代码实测 2373 行（非空 1964 行），05 开工前您值得翻一遍开头的注释。

## 六、这棵树是干净的：仓库的内核机制一句话

旧的项目靠一个大补丁把板级支持打进内核树，搬到 v7.2.9 的这次从零重写把那条路废掉了：内核侧没有任何补丁。板级设备树的唯一原件挪到了 driver/device_tree/alpha-board/linux/ 底下（imx6ull-aes.dts 与 imx6ull-aes.dtsi），咱们只改那个目录，构建脚本 build-linux.sh 每次构建把它们拷进内核树，顺带在 arch/arm/boot/dts/nxp/imx/Makefile 的 dtb 名单里加一行 `imx6ull-aes.dtb \`，拷贝是幂等的，拷过再拷不会叠加。

笔者这份树因为跑过构建，`git status` 里留着痕迹，咱们正好拿它看清机制：

```bash
# 主机 ~/imx-forge
git -C third_party/linux_mainline status --short
```

```text
 M arch/arm/boot/dts/nxp/imx/Makefile
?? arch/arm/boot/dts/nxp/imx/imx6ull-aes.dts
?? arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi
?? arch/arm/configs/imx_aes_mainline_defconfig
```

四行痕迹：一行是 Makefile 里新注册的 dtb 名单项，两个问号开头的是拷进来的板级 dts，外加一个由模板生成的 defconfig。刚拉下来的树没有这些，是 v7.2.9 上游原样；.gitmodules 里那句 `ignore = dirty` 管的就是这件事：让父仓库对子模块内部的构建痕迹视而不见，`git status` 不会天天拿它们烦您。

所以本篇收尾时，您手里这棵树停在 v7.2.9、上游原样、一个补丁都没有——树在位，版本可验证。配置怎么定是 05 的事；拷贝与注册的完整机制，06 设备树迁移那篇展开。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| couldn't find remote ref refs/tags/v7.2.9 | x.y.z 补丁点 tag 只在 stable 树，主树只有 x.0 发布点与 rc | URL 的 torvalds 换成 stable；仓库里以 .gitmodules 登记的地址为准 |
| 换了镜像还是找不到 v7.2.9 | 该镜像镜像的是主树，tag 集与 torvalds 一致（笔者实测过清华那个） | `git ls-remote <镜像地址> refs/tags/v7.2.9` 验过再换 |
| third_party/linux_mainline 是空目录 | 子模块没初始化，gitlink 只是个 commit 指针 | `git submodule update --init --depth=1 third_party/linux_mainline` |
| update 报 did not contain 5fce1616，取树失败 | 老检出 init 时登记进父仓库 .git/config 的还是主树地址，5fce1616 只在 stable 树；改 .gitmodules 不会自动传播 | 先 `git submodule sync -- third_party/linux_mainline` 再 update；或 `git -C third_party/linux_mainline fetch stable` 手动补提交 |
| 浅克隆后 git log 只有一条，别的 tag 切不动 | `--depth 1` 只搬一层历史 | `git fetch --deepen=<N>` 按需加深，`--unshallow` 补全 |
| kernelversion 出的不是 7.2.9，或 describe 带后缀 | 树没停在 tag 上，或地址拉错了树 | `describe --tags` 核对，输出必须是光杆 v7.2.9 |
| `git describe --tags` 报 No names found，或 rev-parse 报 unknown revision | 子模块 update 按提交取树，tag 引用不在 gitlink 的跟随范围 | 按工程路第二条 fetch refspec 把 tag 补取回来，再重新验证 |
| 子模块里 status 多出 imx6ull-aes 文件 | 跑过构建，拷贝脚本留下的痕迹 | 正常现象，`ignore = dirty` 已让父仓库无视；确要还原就删掉三个拷入文件（imx6ull-aes.dts、imx6ull-aes.dtsi、imx_aes_mainline_defconfig），再 `git -C third_party/linux_mainline checkout -- arch/arm/boot/dts/nxp/imx/Makefile` 把 Makefile 那一行还原 |

## 继续学习

- 上一篇：[从零开始搭建主线内核编译环境](02_env_setup.md)，宿主依赖与交叉工具链在那篇装好，本篇拉下来的树就是给它的原料
- 下一篇：[BSP vs 主线对比](04_bsp_vs_mainline.md)，树到手之后先弄清它跟 NXP BSP 那棵差在哪，后面的配置与设备树才有对照物
- 深读：[内核配置：一份 defconfig 的由来](05_defconfig.md)接手 arch/arm/configs/，[设备树：从参考板改出 AES 板，编译并首启](06_dts_migration.md)接手 arch/arm/boot/dts/，本篇路过的两个目录到那边各有整篇展开