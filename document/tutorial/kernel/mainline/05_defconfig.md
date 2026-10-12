---
title: 内核配置：一份 defconfig 的由来
---

# 内核配置：一份 defconfig 的由来

> 树在手（[取源码：从 stable 树拉下 v7.2.9](./03_source_fetch.md)），架构差异心里有数（[BSP vs 主线对比](./04_bsp_vs_mainline.md)），这一篇咱们在自己的树里回答一个实在问题：一份能点亮这块板子的 defconfig 从哪来。答案的骨架是三层：先铺一条 NXP 全家桶基线，再盘清楚基线离这块板差多远，最后把差的那一小撮亲手补上、收进一份属于您自己的配置文件。编译与启动留给下一篇 [设备树：从参考板改出 AES 板，编译并首启](./06_dts_migration.md) 收官。

::: tip 前置知识 · 环境
- 编译环境与工具链：[从零开始搭建主线内核编译环境](./02_env_setup.md)
- 主线源码树：[取源码：从 stable 树拉下 v7.2.9](./03_source_fetch.md)
- 架构差异背景：[BSP vs 主线对比](./04_bsp_vs_mainline.md)

从本篇起，咱们的 make 命令一律在源码树顶层 ~/experiments/linux-mainline 执行，但都带 O= 参数指向另一个目录 ~/experiments/linux-build：源码树只放源码，编译产物（.config、zImage、dtb）全部落进构建目录。这样有两个好处：源码树随时能 git status 出一个干净状态；您到下一篇编外挂模块时还会看到，这个构建目录更是唯一的合法姿势。交叉工具链前缀 arm-none-linux-gnueabihf-（Arm GNU Toolchain 15.2.Rel1）。
:::

## 一、先把基线铺出来：一条命令

咱们先把要改的东西看清楚。内核源码同一份，编出来的镜像能小到几兆也能大到上百兆，行为更是天差地别，分水岭就一个文件：.config。它的本体是一张巨大的三选一问卷：=y 把驱动编进内核镜像，=m 编成独立的 .ko 模块，not set 就是不要。桌面发行版的思路是不确定的硬件全编成模块，插上什么现场加载什么；嵌入式板子反着来，盘子里就那么几样外设，该在的必须在。

铺基线是条命令的事：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx_v6_v7_defconfig
```

```text
#
# configuration written to .config
#
```

kbuild 到 arch/arm/configs/ 目录下找同名文件，找到了 imx_v6_v7_defconfig，把配置写进 O= 指定的构建目录里的 .config（您注意，不是源码树根，两目录制之后 .config 一直住在构建目录里）。这份基线什么规模？咱们拿两条计数命令找找感觉：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -c '^CONFIG' ~/experiments/linux-build/.config
grep -c 'is not set' ~/experiments/linux-build/.config
```

```text
2019
4136
```

2019 行生效的赋值，再算上 4136 行显式的 is not set，整张问卷六千多个决定。为什么挑 imx_v6_v7_defconfig 当底：它是 NXP 系 SoC 的通用基线，咱们这块阿尔法板的近亲 imx6ul-14x14-evk 就在它的覆盖范围里，CPU 频控、串口、uSDHC、DMA 这类 SoC 级配置九成能直接复用。文件本身实测 481 行，SOC_IMX6UL=y 就在第 27 行：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
wc -l arch/arm/configs/imx_v6_v7_defconfig
grep -n 'SOC_IMX6UL' arch/arm/configs/imx_v6_v7_defconfig
```

```text
481 arch/arm/configs/imx_v6_v7_defconfig
27:CONFIG_SOC_IMX6UL=y
```

::: warning 坑：O= 的路径要写绝对路径
O=~/experiments/linux-build 这种波浪号写法在 bash 里能展开，在 zsh 里不会——zsh 只展开词首的波浪号，跟在等号后面的不展开，make 就拿到一个字面的 ~/experiments/linux-build 当相对路径，跑到源码树里去找这个不存在的目录。O= 一律写全 /home/您/… 或 ~/… 前面不带等号直接 cd 过去的形式，别赌手气。
:::

## 二、make xxx_defconfig 那一下发生了什么

空口讲机制没意思，拿证据说话。CONFIG_FEC 是 i.MX 系列网卡驱动的开关，咱们在两个地方分别找它的下落：基线文件、最终产物。

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -c 'CONFIG_FEC=' arch/arm/configs/imx_v6_v7_defconfig
grep -n 'CONFIG_FEC=' ~/experiments/linux-build/.config
```

```text
0
1901:CONFIG_FEC=y
```

基线文件里一行都没有，.config 里却端端正正躺着 CONFIG_FEC=y。网卡驱动总不会是天上下来的吧？把两边一摆，defconfig 的机制就清楚了：这份基线文件并不是全量清单，它是一份精简差异，kbuild 拿它跟全量 Kconfig 合并——清单里写了的项按清单来，没写的项逐个回退到各 Kconfig 文件里声明的默认值。FEC 的谜底就埋在默认值里：drivers/net/ethernet/freescale/Kconfig 的 FEC 条目写着 default ARCH_MXC || SOC_IMX28 if ARM，而 ARCH_MXC=y 恰好由 imx_v6_v7_defconfig 提供。于是没有任何一方提名 FEC，kbuild 合并时照样替咱们把它开了。

这也解释了基线凭什么可以只有 481 行：咱们想想，全量六千多项要是都得手写，这份文件就没法维护了。

## 三、盘基线：原生配置离这块板有多远

基线铺好了，先别急着动手改，盘一盘它离这块板还差多少。咱们拿验收清单当探针，把板子的关键驱动逐个点名：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -E '^CONFIG_(SOC_IMX6UL|DRM_MXSFB|DRM_PANEL_SIMPLE|BACKLIGHT_PWM|PWM_IMX27|SND_SOC_WM8960|SND_IMX_SOC|FEC|MICREL_PHY|MMC_SDHCI_ESDHC_IMX|SERIAL_IMX_CONSOLE|CAN_FLEXCAN|SPI_IMX|TOUCHSCREEN_GOODIX|ROOT_NFS|USB_CHIPIDEA|RTC_DRV_SNVS|REGULATOR_FIXED_VOLTAGE)=' ~/experiments/linux-build/.config
```

```text
CONFIG_SOC_IMX6UL=y
CONFIG_FEC=y
CONFIG_MICREL_PHY=y
CONFIG_CAN_FLEXCAN=y
CONFIG_TOUCHSCREEN_GOODIX=y
CONFIG_SERIAL_IMX_CONSOLE=y
CONFIG_SPI_IMX=y
CONFIG_REGULATOR_FIXED_VOLTAGE=y
CONFIG_DRM_MXSFB=y
CONFIG_DRM_PANEL_SIMPLE=y
CONFIG_BACKLIGHT_PWM=y
CONFIG_SND_IMX_SOC=y
CONFIG_SND_SOC_WM8960=y
CONFIG_USB_CHIPIDEA=y
CONFIG_MMC_SDHCI_ESDHC_IMX=y
CONFIG_RTC_DRV_SNVS=y
CONFIG_PWM_IMX27=y
CONFIG_ROOT_NFS=y
```

十八条逐项命中，一个不缺。SoC 总开关、双网口的 FEC 与 KSZ8081 PHY、DRM 显示与背光、WM8960 codec、GT9147 触摸、ECSPI、FlexCAN、eMMC、串口控制台、SNVS RTC、NFS 根文件系统，全部是 =y。原生基线已经答完了九成的卷子，这是本篇最想让您带走的一个事实：**从零做板子的内核配置，大头是继承，不是重写。**

那差的一成在哪？咱们把音频链单独点名：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -E '^CONFIG_(IMX_SDMA|SND_SOC_FSL_ASOC_CARD|SND_SOC_FSL_SAI)=' ~/experiments/linux-build/.config
```

```text
CONFIG_SND_SOC_FSL_SAI=m
CONFIG_SND_SOC_FSL_ASOC_CARD=m
CONFIG_IMX_SDMA=m
```

三项全是 =m。咱们接下来三节就处理这三个 =m：它为什么是这块板子上真正的坑、怎么翻、翻了之后怎么收进文件。

## 四、动手：只翻两项

咱们先看改配置的正规姿势，menuconfig 交互界面：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- menuconfig
```

您进了界面按 / 弹出搜索框，输入选项名回车，结果列表每项前有数字代号，按对应数字直接跳转；光标压在选项上按空格，就在 y、m、not set 之间轮换。咱们要翻的就两项：SND_SOC_FSL_ASOC_CARD 与 IMX_SDMA，都翻成内置。menuconfig 同样认 O=，保存的就是构建目录里的那份 .config。

::: warning 未实测标注
menuconfig 的按键流转与界面呈现是内核社区标准操作，但交互界面没法在文稿里截图作证，具体表现以您实跑为准；下一小节的脚本等价操作是笔者实际执行并验证过的，两者改的是同一份 .config。
:::

脚本等价操作给咱们省了点鼠标功夫，两行命令，效果与在菜单里翻完全相同：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
./scripts/config --file ~/experiments/linux-build/.config --set-val CONFIG_SND_SOC_FSL_ASOC_CARD y --set-val CONFIG_IMX_SDMA y
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- olddefconfig
```

scripts/config 是内核自带的配置编辑脚本，咱们用 --file 告诉它去改构建目录里的那份 .config（不带 --file 它只会盯着当前目录，在两目录制下会扑空），olddefconfig 让 kbuild 按新值重新解析一遍全量依赖。解析完咱们验收，注意 SAI 的下落：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -E '^CONFIG_(SND_SOC_FSL_ASOC_CARD|SND_SOC_FSL_SAI|IMX_SDMA|SND_SOC_WM8960)=' ~/experiments/linux-build/.config
```

```text
CONFIG_SND_SOC_FSL_SAI=y
CONFIG_SND_SOC_FSL_ASOC_CARD=y
CONFIG_SND_SOC_WM8960=y
CONFIG_IMX_SDMA=y
```

咱们只翻了 ASOC_CARD 和 IMX_SDMA 两项，SAI 没动过却自己变成了 =y。谜底在 sound/soc/fsl/Kconfig 的 fsl-asoc-card 条目里，它身上挂着长长一串 select：

```text
config SND_SOC_FSL_ASOC_CARD
	tristate "Generic ASoC Sound Card with ASRC support"
	depends on OF && I2C
	select SND_SIMPLE_CARD_UTILS
	select SND_SOC_IMX_AUDMUX
	select SND_SOC_IMX_PCM_DMA
	select SND_SOC_FSL_ESAI
	select SND_SOC_FSL_SAI
	select SND_SOC_FSL_SSI
	select SND_SOC_FSL_SPDIF
	select SND_SOC_TLV320AIC31XX
	select SND_SOC_WM8994
	select MFD_WM8994
```

select 的意思是：本项被选中时，被 select 的项强制跟着变。所以看起来要翻一大串音频接口驱动，实际动手只有两项——机器驱动 fsl-asoc-card 与 DMA 控制器 SDMA，前者一翻，SAI、ESAI、SPDIF 这些接口驱动全被它自动拽成内置。这个机制下一节还会帮咱们省一次事。

## 五、把成果收进一份文件：savedefconfig

咱们手上这份改动留在 .config 里只是半成品，.config 本身不适合当长期成果保存：它是产物，躺在构建目录里，make mrproper 一跑就没了。内核社区的正规收尾是 savedefconfig：把当前 .config 相对全部 Kconfig 默认值的差异缩成一份最小清单。

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- savedefconfig
wc -l ~/experiments/linux-build/defconfig
grep -E 'SDMA|ASOC|FSL_SAI' ~/experiments/linux-build/defconfig
```

```text
478
CONFIG_SND_SOC_FSL_ASOC_CARD=y
CONFIG_IMX_SDMA=y
```

savedefconfig 的产物 defconfig 落在构建目录根上。478 行的清单里，咱们本篇的动手痕迹只有两行，正是亲手翻的那两项。SAI 不占行的道理第四节讲过：它是被 select 强制的值，不是任何人的选择，kbuild 重新解析时自己会推出来，无需记录。给它起个板子的名字，挪进源码树的 arch/arm/configs/，它就是属于这块板的一份 defconfig：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
mv ~/experiments/linux-build/defconfig arch/arm/configs/imx6ull_aes_defconfig
```

从此这个源码树里就有了 imx_v6_v7_defconfig（NXP 家的）与 imx6ull_aes_defconfig（您的板子的）两份清单，后者一键复现：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=~/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx6ull_aes_defconfig
```

::: warning 坑：改在 .config 里的成果，一觉醒来没了
.config 是产物不是源码，mrproper 一跑就没了。任何想长期生效的配置改动，都走 savedefconfig 缩回片段、落进 arch/arm/configs/ 里您自己的那份文件。以后调参的标准循环是：改（menuconfig 或 scripts/config）→ 收（savedefconfig）→ 合（覆盖自己的 defconfig 文件）。
:::

## 六、=y 还是 =m：无声事件换来的原则

为什么那三项 =m 咱们非翻不可？这不是品味问题，是这块板子的构建方式决定的。WM8960 声卡是典型的三件套架构：SAI 接口驱动、codec 驱动、machine 驱动（就是 fsl-asoc-card），底下再由 SDMA 提供 DMA 通道。这条链上任何一个环节以模块形态缺席，板子上就是彻底无声，alsa 连声卡设备都不会注册出来。

模块为什么会缺席？咱们这套从零流程只 make zImage dtbs，不做 modules，也不做 modules_install，编成 =m 的 .ko 没有任何一步会把它们装进 rootfs，等于白编。这个教训在本项目历史上真摔过一跤：声卡整机静音，排查到最后发现 fsl-asoc-card 与 SDMA 都以 =m 形态存在而无人安装，把整条链翻成 =y 才出声。

咱们由此可以提炼一条自己改配置时通用的取舍原则：启动早期就要工作的东西，以及构建管线不负责安装模块时的全部关键路径，一律 =y；明确是可选实验件、且 rootfs 里有 modprobe 保障的，才放心 =m。rootfs 挂在 NFS 上的场景把这个逻辑推到极端：内核得先让网卡（FEC）和 NFS 客户端跑起来，才挂得上根文件系统，之后才谈得上从根文件系统里加载模块，所以 ROOT_NFS、FEC 这类启动链上的选项天生就该内置，验收清单里它们全是 =y 也是这么来的。

## 七、选修课与验收

基线之上，除了必须翻的音频两项，还有一类可选优化，本卷不展开、留个名录：把 191 项用不上的家族驱动裁掉、关掉 SMP（i.MX6ULL 是单核，单核化还能连带换成更轻量的 TINY_RCU）、用 EXTRA_FIRMWARE 把 regulatory.db 这类固件直接嵌进镜像。这些做完，zImage 从本篇的约 10.4MB 瘦到约 9.2MB（笔者两个版本都编过，实测数字）。裁剪是纯收益但非必需，您先跑通，再谈瘦身。

配置做没做对，不靠感觉，逐项验收：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
grep -E '^CONFIG_(SND_SOC_FSL_ASOC_CARD|SND_SOC_FSL_SAI|IMX_SDMA|SND_SOC_WM8960|SOC_IMX6UL|DRM_MXSFB|FEC|SERIAL_IMX_CONSOLE)=' ~/experiments/linux-build/.config
```

```text
CONFIG_SOC_IMX6UL=y
CONFIG_FEC=y
CONFIG_SERIAL_IMX_CONSOLE=y
CONFIG_DRM_MXSFB=y
CONFIG_SND_SOC_FSL_SAI=y
CONFIG_SND_SOC_FSL_ASOC_CARD=y
CONFIG_SND_SOC_WM8960=y
CONFIG_IMX_SDMA=y
```

| 验收项 | .config 真实行 | 管的是什么 |
|---|---|---|
| SOC_IMX6UL | CONFIG_SOC_IMX6UL=y | SoC 级总开关，不开后面全白搭 |
| DRM_MXSFB | CONFIG_DRM_MXSFB=y | eLCDIF 显示控制器（DRM 家） |
| SND_SOC_WM8960 | CONFIG_SND_SOC_WM8960=y | WM8960 codec 驱动 |
| SND_SOC_FSL_ASOC_CARD | CONFIG_SND_SOC_FSL_ASOC_CARD=y | machine 驱动，本篇亲手翻的 |
| IMX_SDMA | CONFIG_IMX_SDMA=y | SDMA DMA 控制器，本篇亲手翻的 |
| FEC | CONFIG_FEC=y（Kconfig 默认值贡献） | 双网口控制器 |
| MMC_SDHCI_ESDHC_IMX | CONFIG_MMC_SDHCI_ESDHC_IMX=y | SD/eMMC（uSDHC 主机驱动） |
| SERIAL_IMX_CONSOLE | CONFIG_SERIAL_IMX_CONSOLE=y | 串口控制台，没它启动日志都看不见 |
| TOUCHSCREEN_GOODIX | CONFIG_TOUCHSCREEN_GOODIX=y | GT9147 触摸 |

命名陷阱这儿有一个，提前交代：搜错了符号实名，结果恒为空，比如 grep -E '^CONFIG_(FLEXCAN|MMC_USDHC)=' .config 恒为空。uSDHC 主机驱动在这棵树里走 SDHCI 家族，实名 MMC_SDHCI_ESDHC_IMX；FlexCAN 挂在 CAN 菜单下，实名 CAN_FLEXCAN。名字不对，很容易误判成配置丢了，其实是您搜的词不对。

::: warning 未实测标注
第七节的 zImage 体积对比来自笔者对两个配置版本各做的一次完整编译；您机器上的绝对数值会随工具链版本浮动，但瘦身带来的相对差距是稳定的。
:::

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| 首次用 O= 报 The source tree is not clean，明明刚 mrproper 过 | mrproper 清理 arch/<架构>/include/generated 时跟着 ARCH 走，不带 ARCH=arm 只清了主机架构的残留 | 报错信息里的原话照做：make ARCH=arm mrproper，再重新铺 O= |
| O=~/xxx 报找不到目录，源码树里多出个叫 ~ 的文件夹 | zsh 不展开跟在等号后面的波浪号，make 拿到字面 ~/xxx 当相对路径 | O= 一律写绝对路径；顺手删掉误建的 ~ 目录 |
| make xxx_defconfig 跑完在源码树根找不到 .config | 两目录制下配置产物写在 O= 指定的构建目录 | 到 ~/experiments/linux-build/.config 找 |
| scripts/config 改完 olddefconfig，值没生效 | 两目录制下脚本默认盯着当前目录的 .config，改了个不存在的文件 | 加 --file ~/experiments/linux-build/.config |
| make 报找不到 imx_v6_v7_defconfig | 拼写或目录不对，文件在 arch/arm/configs/ 下 | `ls arch/arm/configs/` 核对实名 |
| menuconfig 里某项搜到但改不动 | Depends on 依赖没开 | 按搜索界面提示先开依赖项 |
| 只翻了 SAI，savedefconfig 里却找不到它 | SAI 被 fsl-asoc-card select 强制，不是用户选择 | 正常现象，值已内置，无需记录 |
| 改过的配置重编译后回到旧值 | 改动写在产物 .config 里，被 mrproper 清掉 | savedefconfig 缩回片段，合进自己的 defconfig 文件 |
| 板子起来无声卡设备 | 音频链以 =m 存在且无人安装模块 | 翻 ASOC_CARD 与 IMX_SDMA 两项为 =y |
| grep 某配置恒为空 | 搜错了符号实名（FLEXCAN、MMC_USDHC 都是错的） | 用 CAN_FLEXCAN、MMC_SDHCI_ESDHC_IMX |

## 继续学习

- 上一篇：[BSP vs 主线对比](./04_bsp_vs_mainline.md)
- 下一篇：[设备树：从参考板改出 AES 板，编译并首启](./06_dts_migration.md)，配置管驱动在不在，设备树管驱动找不找得到硬件，二者齐了才能首启
- 跨卷深读：[DRM 显示系统移植](./07_display_drm.md)
