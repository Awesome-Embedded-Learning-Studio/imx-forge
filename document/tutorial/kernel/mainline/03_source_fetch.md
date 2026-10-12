---
title: 取源码：从 stable 树拉下 v7.2.9
---

# 取源码：从 stable 树拉下 v7.2.9

> 上一篇把编译环境备齐，这一篇咱们干移植的第一件实事：把内核源码树拉到自己的硬盘上，并固定在 v7.2.9 这一个点上。下载源码听着没什么技术含量，坑恰恰都藏在两个决定里——从哪棵树拉，拉到哪个点；弄反了，后面每一篇一开局就对不上号。收尾标准八个字：树在位，版本可验证。本篇只取树：内核配置留给 05，设备树留给 06，编译与启动在 06 收官，这里都不碰。从本篇起，工作台就是您自己的目录，不再依赖任何现成仓库。

::: tip 前置知识 · 环境
- 宿主依赖与交叉工具链 arm-none-linux-gnueabihf 的安装在[从零开始搭建主线内核编译环境](02_env_setup.md)里完成；本篇不编译，工具链还派不上用场，但目录约定沿用那一篇
- 本篇只需要 git，命令都在您自己的机器上跑；示例统一把树放在 ~/experiments/linux-mainline，放哪儿都行，后文路径跟着您的选择走
- 本卷的从零流程与任何现成仓库解耦：您跟着做，手里只有这一棵自己克隆的树
:::

## 一、移植第一步：把树固定在一个可复现的点上

拿源码有什么可讲的？`git clone` 一下就完了，很多朋友的第一反应都是这句。咱们把这一下拆开看，里面压着两个决定：从哪棵树拉，拉到哪个点。这两个决定都做对，后面的配置、设备树、编译才有的谈；做错一个，下一篇一开局就会撞上本篇第二节的报错。

拉到哪个点，答案是把 tag 固定下来，不追分支。教程这类文本有个底线要求：可重放。本篇里每条命令的输出都原样印在正文中，一年后您拿这篇文档照做，拉下来的树必须还能产出一样的版本号。分支头做不到这一点——它天天在动，今天 clone 与下个月 clone 拿到的是两棵不同的树，文档里印的输出全部对不上号，您还没法判断是自己做错了，还是树变了。

tag 没有这个问题：它指向的提交永远不变，升版本是显式的一次动作，而不是默认跟着某个分支漂。所以本卷所有章节统一对着 v7.2.9 写。这个版本是 stable 团队 2026-10-03 发布的补丁点，带着 v7.2.0 以来每一轮的修复，第四节咱们当场验货。

## 二、躲不开的坑：主树上没有 v7.2.9

这条坑笔者真实踩过，现象从一条报错开始。假使照着直觉，从最有名的那个内核仓库取 v7.2.9：

```bash
# 主机 临时空目录(git init 一个空仓库再跑,或者只 fetch 不落工作区)
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

## 三、把树拉到家：一条浅克隆命令

目标明确，咱们要的就是把本卷跟完，那么一条命令就够：

```bash
# 主机 ~/experiments(您打算放源码的地方)
git clone --depth 1 --branch v7.2.9 \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
    linux-mainline
cd linux-mainline
```

`--branch` 后面跟分支名也跟 tag 名，这里给的是 tag，git 会把工作区直接停在 v7.2.9 上；`--depth 1` 让 git 只搬这一个提交的对象，不用把 30 万条提交历史背回来，时间与磁盘都省下一大截。代价也得说清：历史只有一层，`git log` 只剩一条记录。以后您想看某个驱动是怎么一步步演变成现在这样的，就得往深补：`git fetch --deepen=<N>` 一层一层加深，`--unshallow` 一次补全，按需选。

::: warning 未实测标注
克隆的完整下载过程受网络影响太大，笔者没法替您掐表，耗时与体积以您本机为准。不过这条命令的产物形态是确定的：浅仓库、工作区停在 tag、远端只挂 stable 一个地址。笔者手头的树正是这个形态，下一节的验证逐项见分晓。
:::

树到手之后还有一个归宿问题值得您想一下：这棵树在工程项目里怎么放。把内核当部件管理的项目，常用 git 子模块把这棵树固定在某个提交上，克隆、升级都由脚本代劳。那条路跟您手头这棵树互不干扰，属于自动化工程，本卷从零流程用不上；想了解机制的话，后面的工程化篇章单独讲。

## 四、验证：树在位，版本可复现

收尾标准就八个字：树在位，版本可验证。咱们进树一口气跑六条：

```bash
# 主机 ~/experiments/linux-mainline(内核树内)
make -s kernelversion
git log -1 --format='%h %ci %s'
git describe --tags
git rev-parse 'v7.2.9' 'v7.2.9^{}'
git remote -v
git rev-parse --is-shallow-repository
```

```text
7.2.9
5fce16164 2026-10-03 12:43:16 +0200 Linux 7.2.9
v7.2.9
bd50482a9c7a6eb91468f1064a346a75e677e692
5fce161649b4d779d1b76d9fcd52dc77779774b8
origin	https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git (fetch)
origin	https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git (push)
true
```

咱们逐条过。头一行 `kernelversion` 由内核顶层 Makefile 提供，`-s` 让 make 别吭声、只吐版本号，7.2.9 就是本卷的基准数。第二行 `log -1` 给出树顶提交：5fce16164，提交说明就一句 Linux 7.2.9，日期 2026-10-03，与 stable 团队发布这个补丁点的时间一致。第三行 `describe --tags` 输出是光杆的 v7.2.9，不带任何后缀，说明 HEAD 不多不少正停在 tag 上，一格未漂。

第四行的两个哈希是防您混淆用的。第二节从 stable 树探到的 bd50482 与这里树顶的 5fce1616 不是同一个对象，这不是哪里出了错：v7.2.9 是附注 tag，tag 自己也是一个 git 对象（bd50482），它再指向真正的提交（5fce1616）；`rev-parse` 不带 `^{}` 给前者，带 `^{}` 给后者。两组数与第二节远端探到的值两两相合，这棵树就是 v7.2.9 原样。

`remote -v` 只有一行 origin，指向 stable 树，干净利落——咱们从哪克隆，origin 就是谁。最后那个 true 是浅仓库的回执，与 `--depth 1` 对上了账。六条全过，收尾标准达成。

## 五、树结构初览：嵌入式视角挑三处看

内核树顶层 `ls` 下来 32 个条目，一次看完没有意义，咱们只看后面几篇要反复回来的地方。

板级设备树集中在 `arch/arm/boot/dts/nxp/imx/` 底下，咱们拿探针数一数 imx6ull 打头的文件（刚克隆完的树上跑，上游原样）：

```bash
# 主机 ~/experiments/linux-mainline(内核树内)
ls arch/arm/boot/dts/nxp/imx/ | grep -c '^imx6ull'
ls arch/arm/boot/dts/nxp/imx/ | grep '^imx6ull' | head -5
ls arch/arm/configs/ | grep imx_v6
```

```text
70
imx6ull-14x14-evk.dts
imx6ull-colibri-aster.dts
imx6ull-colibri-aster.dtsi
imx6ull-colibri-emmc-aster.dts
imx6ull-colibri-emmc-eval-v3.dts
imx_v6_v7_defconfig
```

70 个 imx6ull 打头的文件，此时名单里还没有任何 aes 字样——那是咱们 06 篇要亲手造的板子，现在一个都不存在。名单头一个 imx6ull-14x14-evk.dts 是 NXP 官方评估板的板级描述，咱们这块正点原子的板子跟它是近亲：同一个 SoC，内存、屏幕、PHY 的接法各有取舍，06 篇就从它出发动手改。

`arch/arm/configs/` 那一行也先记下：全 ARM 平台的 defconfig 都放在这里，imx_v6_v7_defconfig 是 NXP 系 SoC 的通用基线，05 那一篇会带咱们回到这里，从它出发做配置。

`drivers/` 按子系统分家，后面外设各篇的主角都住在这里，咱们在 v7.2.9 里把三个地址都点过名：显示的 eLCDIF 驱动在 drivers/gpu/drm/mxsfb/（lcdif_drv.c），网卡 FEC 驱动在 drivers/net/ethernet/freescale/（fec_main.c），触摸的 Goodix 驱动在 drivers/input/touchscreen/（goodix.c）。目录名就是子系统名，找驱动先猜目录再 `ls`，多数时候比全局搜索快。平台层 arch/arm/mach-imx/ 如今只剩 SoC 级杂项支撑（anatop、CPU 电源管理这类），时钟驱动搬去了 drivers/clk/imx/，6ULL 对应的是 clk-imx6ul.c，复位控制器在 drivers/reset/reset-imx7.c，本卷基本不进去改，知道位置就行。

顶层的 Makefile 是整棵树的构建入口，`kernelversion` 目标就定义在它里面，05 的 defconfig 加载也归它管；它连注释带代码实测 2373 行，05 开工前您值得翻一遍开头的注释。

## 六、收尾：一棵干净的树

这一篇咱们只添了目录、没改一个源码文件，`git status` 应该是空的。从下一篇起，这棵树要开始留痕了：05 会生成 .config 和您自己的 defconfig，06 会添两三个设备树文件、在 Makefile 里注册一行，再编出 zImage 和 dtb。痕迹越来越多是正常的，它们就是移植这件事在树上走过的脚印。

仓库式的自动化（配置模板、设备树拷贝、一键构建脚本）能把这条从零流程收敛成一条命令，那是工程化篇章的内容；本卷主线始终只认您手头这棵自己克隆、自己动手的树。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| couldn't find remote ref refs/tags/v7.2.9 | x.y.z 补丁点 tag 只在 stable 树，主树只有 x.0 发布点与 rc | URL 的 torvalds 换成 stable，克隆命令其余不变 |
| 换了镜像还是找不到 v7.2.9 | 该镜像镜像的是主树，tag 集与 torvalds 一致（笔者实测过清华那个） | `git ls-remote <镜像地址> refs/tags/v7.2.9` 验过再换 |
| 浅克隆后 git log 只有一条，别的 tag 切不动 | `--depth 1` 只搬一层历史 | `git fetch --deepen=<N>` 按需加深，`--unshallow` 补全 |
| kernelversion 出的不是 7.2.9，或 describe 带后缀 | 树没停在 tag 上，或地址拉错了树 | `describe --tags` 核对，输出必须是光杆 v7.2.9 |

## 继续学习

- 上一篇：[从零开始搭建主线内核编译环境](02_env_setup.md)，宿主依赖与交叉工具链在那篇装好，本篇拉下来的树就是给它的原料
- 下一篇：[BSP vs 主线对比](04_bsp_vs_mainline.md)，树到手之后先弄清它跟 NXP BSP 那棵差在哪，后面的配置与设备树才有对照物
- 深读：[内核配置：一份 defconfig 的由来](05_defconfig.md)在这棵树里做配置，[设备树：从参考板改出 AES 板，编译并首启](06_dts_migration.md)在这棵树里造板子并首启，本篇路过的目录到那边各有整篇展开
