---
title: 内核配置：一份 defconfig 的由来
---

# 内核配置：一份 defconfig 的由来

> 同一棵主线源码树，怎么长出一份属于咱们这块 i.MX6ULL 板子的可编译配置？本篇就答这一问。上一篇 [BSP vs 主线对比](./04_bsp_vs_mainline.md) 把两个世界的架构差异摆上了台面，本篇把差异翻译成一份能喂给 make 的 .config。编译产物验证与 QEMU 首启留给下一篇 [设备树：从参考板改出 AES 板，编译并首启](./06_dts_migration.md) 收官，本篇的边界就是配置本身。

::: tip 前置知识·环境
- 编译环境与工具链：[从零开始搭建主线内核编译环境](./02_env_setup.md)
- 主线源码树获取：[取源码：从 stable 树拉下 v7.2.9](./03_source_fetch.md)
- 架构差异背景：[BSP vs 主线对比](./04_bsp_vs_mainline.md)

本篇全部命令咱们都在主机 ~/imx-forge 仓库根目录执行，操作对象是 third_party/linux_mainline 这棵 Linux 7.2.9 主线源码树，交叉工具链为 arm-none-linux-gnueabihf-（Arm GNU Toolchain 15.2.Rel1）。
:::

## 配置的本质：五千多项三选一

同一份内核源码，编出来的镜像能小到几兆，也能大到上百兆，行为更是天差地别。分水岭就一个文件：.config。它的本体是一张巨大的三选一问卷——=y 把驱动编进内核镜像，=m 编成独立的 .ko 模块，not set 就是不要。咱们仓库这份配置到底什么规模？一条计数命令就有感觉：

```bash
# 主机 ~/imx-forge
grep -c '^CONFIG' out/linux/.config
```

```text
1839
```

1839 行生效的赋值，再算上 3509 行显式的 is not set，整张问卷五千多个决定。桌面发行版的思路是不确定的硬件全编成模块，插上什么现场加载什么；嵌入式板子反着来，咱们盘子里就那么几样外设，该在的必须在。所以开发板社区普遍走一块板一份 config 的路线：给这块板留一份能直接出可用内核的配置清单，后来的人 make 一下就能对齐，不必对着 menuconfig 的上千个菜单从零点一遍。imx-forge 也是这个路数。这份清单放在哪、怎么生成，有点讲究，咱们一样一样看。

## make xxx_defconfig 那一下发生了什么

空口讲机制没意思，咱们拿证据说话。CONFIG_FEC 是 i.MX 系列网卡驱动的开关，咱们在三个文件里分别找它的下落：配置模板、上游底版、最终产物。

```bash
# 主机 ~/imx-forge
/usr/bin/grep -c 'CONFIG_FEC=' driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
/usr/bin/grep -c 'CONFIG_FEC=' third_party/linux_mainline/arch/arm/configs/imx_v6_v7_defconfig
/usr/bin/grep -n 'CONFIG_FEC=' out/linux/.config
```

```text
0
0
1585:CONFIG_FEC=y
```

前两个文件里一行都没有，.config 里却端端正正躺着 CONFIG_FEC=y。网卡驱动总不会是天上下来的吧？咱们把三处一摆，defconfig 的机制就清楚了。

敲下 make xxx_defconfig 的时候，kbuild 到 arch/arm/configs/ 目录下找同名文件，咱们这棵树里的实况是：

```bash
# 主机 ~/imx-forge
ls third_party/linux_mainline/arch/arm/configs/ | grep imx_v6_v7
```

```text
imx_v6_v7_defconfig
```

找到之后，这份文件在咱们手里并不会被原样拿来当 .config 用。它是一份精简清单，kbuild 拿它跟全量 Kconfig 合并：清单里写了的项按清单来，没写的项逐个回退到各 Kconfig 文件里声明的默认值。FEC 的谜底就埋在默认值里——drivers/net/ethernet/freescale/Kconfig 的 FEC 条目写着 default ARCH_MXC || SOC_IMX28 if ARM，而 ARCH_MXC=y 恰好由 imx_v6_v7_defconfig 提供。于是没有任何一方提名 FEC，kbuild 合并时照样替咱们把它开了。这也解释了模板凭什么可以只写差异：全量五千多项要是都得手写，这份文件就没法维护了。

至于为什么挑 imx_v6_v7_defconfig 当底：NXP 自家的参考板 imx6ul-14x14-evk，跟咱们这块阿尔法板是同一颗 i.MX6UL/6ULL 家族 SoC，CPU 频控、串口、uSDHC、DMA 这类 SoC 级配置九成能直接复用。数字也支持这个判断，底版实测 481 行、463 个赋值，SOC_IMX6UL=y 就在第 27 行。所以咱们要做的事很明确：这份 imx_v6_v7_defconfig 本身就内含 imx6ul-evk 在内的全系 i.MX 板配置，咱们站在它之上，把板级差异和主线化取舍叠上去。

## 本仓库的配置真理源：575 行模板与一个占位符

咱们仓库里配置的唯一真理源，是 driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template。wc 实测 575 行，内部用分节注释切成 39 个段落，从 General Setup 一路排到 MTD：

```bash
# 主机 ~/imx-forge
wc -l driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
/usr/bin/grep -n '^# ---' driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
```

```text
575 driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template
8:# --- General Setup ---
25:# --- Architecture (i.MX6ULL specific) ---
45:# --- CPU Frequency & Power Management ---
61:# --- Modules ---
69:# --- Networking ---
90:# --- Ethernet (important for i.MX6ULL) ---
...
533:# --- MTD (NOR/NAND Flash) ---
```

输出合计 40 行（wc 一行加 39 个分节），咱们在上面截了头尾，完整清单以实际执行为准。

模板里唯一的花样藏在末尾，咱们直接看最后两行：

```ini
CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"
CONFIG_EXTRA_FIRMWARE_DIR="${FIRMWARE_DIR}"
```

EXTRA_FIRMWARE 的用途，是把 regulatory.db 这类固件文件直接嵌进内核镜像，省得咱们运行期去 rootfs 里找；固件目录因机器而异，所以留了 ${FIRMWARE_DIR} 占位符。scripts/build_helper/build-linux.sh 的 prepare_defconfig 函数负责补上它，核心就两行：

```bash
# 节选自 scripts/build_helper/build-linux.sh（prepare_defconfig 函数）
FIRMWARE_DIR=$(realpath "${FIRMWARE_DIR}")
sed "s|\${FIRMWARE_DIR}|${FIRMWARE_DIR}|g" "${TEMPLATE_FILE}" > "${TARGET_FILE}"
```

sed 把占位符替换成仓库内 driver/firmwares 的绝对路径，产物写到内核树的 arch/arm/configs/imx_aes_mainline_defconfig，随后 make 拿这份生成的 defconfig 去生成 .config。替换前后的对照不用另外做，产物里就是现成的样例，咱们在产物里把这一行找出来（/usr/bin/grep -n CONFIG_EXTRA_FIRMWARE_DIR out/linux/.config）：

```text
CONFIG_EXTRA_FIRMWARE_DIR="/home/charliechen/imx-forge/driver/firmwares"
```

想脱离构建脚本手工做一遍等价操作也不难：把模板拷进内核树的 arch/arm/configs/ 并改名为 imx_aes_mainline_defconfig，把占位符替换成自己机器上固件目录的绝对路径，然后 make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O="$PWD/out/linux" imx_aes_mainline_defconfig 即可（O= 为什么要写绝对路径，menuconfig 一节里专门交代）。那个路径没有唯一正确值，跟着您自己仓库放在哪走。

::: warning 坑：占位符没替换就 configure
${FIRMWARE_DIR} 若原样混进了配置，kbuild 在嵌入固件环节会拿这个字面路径去找 regulatory.db，目录当然不存在，构建当场断在一个看起来像固件丢失的报错上，根因其实是模板没有经过替换。手工生成 defconfig 时这一步最容易漏，您替换完拿 grep 查一下 ${ 没有残留，再往下走。
:::

## 显示、音频、网络：真正叠了板级意志的三组

39 节里大部分是对上游底版的继承与扩展，真正叠了板级意志的就少数几组，咱们挑三组细看。其余的照分节注释按需读模板原文就行，不必逐行背。

### 显示：DRM 一条道，旧驱动连源码都没了

第 259 行的 # --- Multimedia / Display --- 节，是主线化痕迹最重的一节。fbdev 版的 mxsfb 驱动主线早年自带，后来整族移出主线，这棵 7.2.9 树里连源码文件都不存在了，咱们当场就能验证：

```bash
# 主机 ~/imx-forge
ls third_party/linux_mainline/drivers/video/fbdev/mxsfb.c
ls third_party/linux_mainline/drivers/gpu/drm/mxsfb/
```

```text
ls: cannot access 'third_party/linux_mainline/drivers/video/fbdev/mxsfb.c': No such file or directory
Kconfig  Makefile  lcdif_drv.c  lcdif_drv.h  lcdif_kms.c  lcdif_regs.h  mxsfb_drv.c  mxsfb_drv.h  mxsfb_kms.c  mxsfb_regs.h
```

旧世界只剩一个空地址，eLCDIF 的驱动住在 DRM 家里。模板相应地把 CONFIG_DRM、CONFIG_DRM_MXSFB、CONFIG_DRM_PANEL_SIMPLE、CONFIG_BACKLIGHT_PWM、CONFIG_PWM_IMX27 一串全开成 =y。这跟咱们上一篇的架构对比正好接上：DRM_PANEL_SIMPLE 对应的 panel-dpi 通用驱动，就是下一篇设备树里 panel 节点 compatible 要配对的那个驱动。配置不开，设备树写得再对，驱动也不会 probe。点亮屏幕的完整过程，[DRM 显示系统移植](./07_display_drm.md) 有专章。

### 音频：=y 还是 =m，Issue #43 用一场无声换来的答案

第 311 行的 # --- Sound --- 节里，有一行模板作者自己写的注释，值得咱们原样贴出来：

```ini
# fsl-asoc-card（WM8960 等 machine 驱动）必须 =y：build 不 modules_install，=m 会让声卡整机静音（Issue #43）
CONFIG_SND_SOC_FSL_ASOC_CARD=y
CONFIG_SND_SOC_WM8960=y
CONFIG_SND_IMX_SOC=y
```

这四行在模板里并不是连着的一段：SND_IMX_SOC 单独在第 317 行，作者注释与 FSL_ASOC_CARD 相连在第 321、322 行，WM8960 在第 327 行，中间隔着 AC97_CODEC、CS42XX8_I2C 几行别的条目，这里按语义凑成了一块。您去模板里对照时按行号分开找，别当成连续段落。

上游底版里这一项本来是 CONFIG_SND_SOC_FSL_ASOC_CARD=m（第 315 行），模板把它翻成了 =y，背后是笔者这个仓库历史上真摔过的一跤。WM8960 声卡是典型的三件套架构：SAI 接口驱动、codec 驱动、machine 驱动（就是 fsl-asoc-card），底下再由 SDMA 提供 DMA 通道。这条链上任何一个环节以模块形态缺席，板子上就是彻底无声，alsa 连声卡设备都不会注册出来。模块为什么会缺席？本仓库的构建只 make zImage dtbs，不做 modules，也不做 modules_install，编成 =m 的 .ko 没有任何一步会把它们装进 rootfs，等于白编。

同样的取舍也发生在第 416 行的 # --- DMA (i.MX6ULL uses SDMA) --- 节：底版里 CONFIG_IMX_SDMA=m（第 400 行），模板改成 =y，注释写明 alpha 板的 SAI2 音频走 SDMA。这一节咱们还得把固件供给的两条路线辨清楚，别混：SDMA 运行需要的固件文件走 rootfs 的 /lib/firmware，由 rootfs/buildroot/post-build.sh 在构建根文件系统时下载并放进去；模板里 EXTRA_FIRMWARE 嵌进去的 regulatory.db，则是直接打进内核镜像的另一条路。两条路解决的问题不同。

由此咱们可以提炼一条自己改配置时通用的取舍原则：启动早期就要工作的东西，以及构建管线不负责安装模块时的全部关键路径，一律 =y；明确是可选实验件、且 rootfs 里有 modprobe 保障的，才放心 =m。rootfs 挂在 NFS 上的场景把这个逻辑推到极端——内核得先让网卡（FEC）和 NFS 客户端跑起来，才挂得上根文件系统，之后才谈得上从根文件系统里加载模块，所以 ROOT_NFS、FEC 这类启动链上的选项天生就该内置，模板里 CONFIG_ROOT_NFS=y 也是这么来的。

### 网络：模板里没有的 FEC，与必须写明的 PHY

以太网这节（第 90 行，# --- Ethernet (important for i.MX6ULL) ---）最反直觉的点，咱们在 make xxx_defconfig 那一节已经摆过：模板通篇没有 FEC，最终配置里的 FEC=y 由 Kconfig 默认值加 ARCH_MXC=y 贡献。模板真正动手写的是 PHY 一侧：

```ini
CONFIG_MICREL_PHY=y
CONFIG_AT803X_PHY=y
CONFIG_DP83867_PHY=y
CONFIG_CAN_FLEXCAN=y
```

咱们阿尔法板两个网口挂的都是 KSZ8081，它属于 Micrel（现 Microchip）PHY 家族，MICREL_PHY 必须开；AT803X 与 DP83867 是底版带来的其它常见 PHY，留着不碍事。CAN 的选项实名是 CONFIG_CAN_FLEXCAN，不是裸的 FLEXCAN，按符号实名去搜，比如 /usr/bin/grep -E '^CONFIG_FLEXCAN=' out/linux/.config，恒为空，这一条验收时还会再撞见。双网口的 PHY 细节与设备树写法，[双网口移植](./09_network_dual_phy.md) 有专章。

## menuconfig：改配置的正规姿势

模板管基线，咱们日常调参靠交互界面。内核社区的标准流程，是从现有配置起步进 menuconfig，搜选项、改值，再把改动缩回片段存走：

```bash
# 主机 ~/imx-forge
make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O="$PWD/out/linux" menuconfig
```

这行命令的 O= 必须写成绝对路径，这个坑咱们在这儿交代清楚。make 的 -C 在读入 Makefile 之前就把工作目录切进了内核源码树，之后的相对路径一律按源码树来解析。您写 O=out/linux，实际落点是 third_party/linux_mainline/out/linux 这个源码树内的新目录，全篇在说的仓库根 out/linux 反而没被碰；menuconfig 打开的也因此成了一份没有 .config 的从零默认配置，跟前文刚分析的那份对不上。写成绝对路径，才能对准仓库根的 out/linux。

进了界面，咱们按 / 弹出搜索框，输入选项名或关键词回车，结果列表每个条目前有数字代号，按对应数字直接跳到那一项；光标压在选项上按空格，就在 y、m、not set 之间轮换。搜索结果还会列出该选项的 Depends on 依赖链，哪一项没满足一眼可见。很多朋友都撞过同一个问题：某项搜得到却怎么也改不动，多半就是依赖没开。

咱们改完保存退出，.config 就地更新。想让改动回到可版本管理的形态，就跑 savedefconfig：

```bash
# 主机 ~/imx-forge
make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O="$PWD/out/linux" savedefconfig
```

它在输出目录 out/linux 下生成 defconfig 文件（O= 构建时不在源码树根），内容是当前 .config 相对全部 Kconfig 默认值的有差异行；这个目录在默认构建里会被整目录删掉，diff 完记得立刻把文件拷出来。575 行模板的来历就是这么个缩法，反着走一遍，咱们的改动也能回到同样的精简形态，合回仓库模板后下次构建自动生效。

::: warning 未实测标注
本节交互步骤（menuconfig 的按键流转、搜索界面呈现、savedefconfig 的产物内容）是内核社区标准操作，但本环境是无头容器，无法替您真按一遍键盘；具体按键表现以您机器实跑为准，搜索语法与 savedefconfig 行为在内核 7.x 各版本间保持稳定。
:::

::: warning 坑：改在 .config 里的成果，一觉醒来没了
out/linux 整个目录是构建产物，构建脚本默认模式开跑就 rm -rf 重建它，直接改产物 .config 的成果会跟着一起蒸发。根因是产物目录与真理源的分工没守住。解法：任何想长期生效的配置改动，走 savedefconfig 缩回片段、合回仓库模板，让构建脚本替咱们展开。
:::

## 验收：关键项逐个命中

配置做没做对，不靠感觉。咱们一条计数命令打底，再拿关键项对照表逐个过。

```bash
# 主机 ~/imx-forge
grep -c '^CONFIG' out/linux/.config
```

```text
1839
```

1839 这个数别当魔数记：内核版本一换、选项增删，它就会漂。咱们验收看的是关键项逐个命中，总数漂了不用慌：

```bash
# 主机 ~/imx-forge
/usr/bin/grep -E '^CONFIG_(SOC_IMX6UL|DRM_MXSFB|SND_SOC_WM8960|FEC|MMC_SDHCI_ESDHC_IMX|SERIAL_IMX_CONSOLE|CAN_FLEXCAN|SPI_IMX|TOUCHSCREEN_GOODIX)=' out/linux/.config
```

```text
CONFIG_SOC_IMX6UL=y
CONFIG_FEC=y
CONFIG_CAN_FLEXCAN=y
CONFIG_TOUCHSCREEN_GOODIX=y
CONFIG_SERIAL_IMX_CONSOLE=y
CONFIG_SPI_IMX=y
CONFIG_DRM_MXSFB=y
CONFIG_SND_SOC_WM8960=y
CONFIG_MMC_SDHCI_ESDHC_IMX=y
```

| 验收项 | .config 真实行 | 管的是什么 |
|---|---|---|
| SOC_IMX6UL | CONFIG_SOC_IMX6UL=y | SoC 级总开关，不开后面全白搭 |
| DRM_MXSFB | CONFIG_DRM_MXSFB=y | eLCDIF 显示控制器（DRM 家） |
| SND_SOC_WM8960 | CONFIG_SND_SOC_WM8960=y | WM8960 codec 驱动 |
| FEC | CONFIG_FEC=y（Kconfig 默认值贡献） | 双网口控制器 |
| MMC_SDHCI_ESDHC_IMX | CONFIG_MMC_SDHCI_ESDHC_IMX=y | SD/eMMC（uSDHC 主机驱动） |
| SERIAL_IMX_CONSOLE | CONFIG_SERIAL_IMX_CONSOLE=y | 串口控制台，没它启动日志都看不见 |
| CAN_FLEXCAN | CONFIG_CAN_FLEXCAN=y | FlexCAN 总线 |
| SPI_IMX | CONFIG_SPI_IMX=y | ECSPI 控制器 |
| TOUCHSCREEN_GOODIX | CONFIG_TOUCHSCREEN_GOODIX=y | GT9147 触摸 |

命名陷阱这儿有一个，咱们提前交代：搜错了符号实名，结果恒为空，比如 /usr/bin/grep -E '^CONFIG_(FLEXCAN|MMC_USDHC)=' out/linux/.config。uSDHC 主机驱动在这棵树里走 SDHCI 家族，实名 MMC_SDHCI_ESDHC_IMX；FlexCAN 挂在 CAN 菜单下，实名 CAN_FLEXCAN。名字不对，很容易误判成配置丢了，其实是您搜的词不对。

触摸、显示、网络的逐项移植故事，后面各有专章展开。配置这一步咱们干的事，就是把驱动请进门。

### 配置阶段速查表

| 现象 | 根因 | 解法 |
|---|---|---|
| make 报找不到 imx_aes_mainline_defconfig | 模板没生成目标文件，内核树里没有它 | 重跑 build-linux.sh，或手工拷模板加 sed 替换 |
| 构建断在固件嵌入，报 regulatory.db 找不到 | ${FIRMWARE_DIR} 占位符没被替换 | 检查生成文件末尾两行，grep '${' 应无残留 |
| 改过的配置重编译后回到旧值 | 改动写在产物 .config 里，被 distclean 清掉 | savedefconfig 缩回片段，合回仓库模板 |
| 板子起来无声卡设备 | fsl-asoc-card、SDMA 以 =m 存在且无人安装模块 | 模板保持 =y（Issue #43 的答案） |
| menuconfig 里某项搜到但改不动 | Depends on 依赖没开 | 按搜索界面提示先开依赖项 |

## 继续学习

- 上一篇：[BSP vs 主线对比](./04_bsp_vs_mainline.md)
- 下一篇：[设备树：从参考板改出 AES 板，编译并首启](./06_dts_migration.md)
- 跨卷深读：[DRM 显示系统移植](./07_display_drm.md)
