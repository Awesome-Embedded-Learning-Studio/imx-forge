---
title: 源码与环境准备：把 v2026.10 检出到能编译
---

# 源码与环境准备：把 v2026.10 检出到能编译

> 这一篇是 U-Boot 卷的备料篇，咱们把开发用的电脑带到能编译 U-Boot 的状态就收手，编译这一步倒是一行都不跑，那是下一篇（首次编译）的正题。上一篇把启动链条与 v2026.10 的版本口径铺好了，本篇接的是它的下一句：咱们的电脑要装齐什么，源码从哪来、咱们把它锁在哪个提交上，树里哪些位置跟咱们有关，下一篇的 make 才有得跑。

## 一、这台电脑需要什么：UBOOT_PKGS 里的 12 个包

### 清单住在 env-init.sh 里

感谢 [Heizer-Tan](https://github.com/Heizer-Tan) 老师整理的依赖，`scripts/init/env-init.sh`。这个脚本按构建目标分了好几个数组，U-Boot 用的一份叫 UBOOT_PKGS，构建脚本 build-uboot.sh 每次开跑前的依赖检查调的就是它。咱们把数组的原文贴出来：

```text
# scripts/init/env-init.sh 第 43 行起的 UBOOT_PKGS 数组
UBOOT_PKGS=(
    "build-essential"
    "bc"
    "bison"
    "flex"
    "device-tree-compiler"
    "python3"
    "python3-pyelftools"
    "swig"
    "libssl-dev"
    "libgnutls28-dev"
    "libncurses-dev"
    "imagemagick"
)
```

12 个包咱们按它们在构建里干的活分组过一遍，每个都交代它为什么必须在场。

### 挨个说它为什么必须在场

头一组咱们按构建本体与配置解析来认。build-essential 是主机这边的基础工具箱，gcc、make 和 libc 的开发文件都在里面，交叉工具链再全也得有主机侧的 make 来驱动整个构建，缺了它连 make 都没有。bc 是咱们清单里看着最不像编译依赖的一个，其实它是个命令行计算器，跟着上游构建环境带上来的，上游 tools/docker/Dockerfile 里也装了它。全树 Makefile 里它的调用点只有一处，scripts/Makefile.xpl 的第 348 行给 SPL 镜像算 bss 补齐，属于编译环节的活。咱们两块板的 defconfig 里都没有 SPL 配置项，单镜像的构建走不到那一步，脚本把它列进依赖属于沿用上游的惯例，装上了也不碍事。

第二组是干解析器生成的 bison 和 flex 这对搭档，bison 管的是语法分析，flex 管的是词法分析。Kconfig 读 defconfig 与 Kconfig 文件靠的就是这一对生成出来的解析代码，咱们装的两个包只是生成器本身，解析代码是构建时现生成现用的。device-tree-compiler 也就是咱们常说的设备树编译器 dtc，U-Boot 树里自带了一份，系统里咱们再装一份更稳，后面咱们核对设备树产物时用的就是它。

第三组是给 Python 用的两个包，python3 与 python3-pyelftools 都到齐了。构建系统里有 Python 写的脚本，pyelftools 负责解析 ELF 格式的文件，核查脚本对它的验收方式咱们见过：拿 python3 真的 import 一次 elftools 模块，装没装好的问题一试便知。swig 是把 C 的接口包装给别的语言用的接口生成器，U-Boot 的某些工具环节要它在场。

剩下的四个咱们归到一堆按用途认。libssl-dev 是给 mkimage 这批主机工具做 FIT 签名与公钥处理用的，挂的是 CONFIG_TOOLS_LIBCRYPTO。libgnutls28-dev 是给 mkeficapsule 链接用的，mkeficapsule 是生成 EFI 胶囊更新镜像的主机工具。libncurses-dev 管的是终端界面，make menuconfig 那个配置界面就是拿它画的，后面调配置咱们离不开这个界面。imagemagick 管的是图像处理，开机 logo 要从 PNG 转成镜像里认的 BMP 格式，这件事由构建脚本调的 logo_helper 来干，它用的 convert 命令就出自这个包。

### 装与核

安装命令笔者只给一条，12 个包照着数组的顺序来：

```bash
# 主机 ~/imx-forge
sudo apt install build-essential bc bison flex device-tree-compiler python3 \
    python3-pyelftools swig libssl-dev libgnutls28-dev libncurses-dev imagemagick
```

装没装对咱们不靠感觉，env-init.sh 自己会替咱们核，U-Boot 这一档对应的检查是 --stage 1：

```bash
# 主机 ~/imx-forge
bash scripts/init/env-init.sh --stage 1
```

这是笔者在本机跑出的真实输出，终端里每行前面还挂着绿色的 [INFO] 颜色码，这里把颜色去了：

```text
[INFO] 检查 Stage 1 (U-Boot) 依赖包...
[INFO] 检查 U-Boot 依赖包...
[INFO]   ✓ bc
[INFO]   ✓ bison
[INFO]   ✓ build-essential
[INFO]   ✓ device-tree-compiler
[INFO]   ✓ flex
[INFO]   ✓ imagemagick
[INFO]   ✓ libgnutls28-dev
[INFO]   ✓ libncurses-dev
[INFO]   ✓ libssl-dev
[INFO]   ✓ python3
[INFO]   ✓ python3-pyelftools
[INFO]   ✓ swig
[INFO] All U-Boot dependencies found
```

12 个包全都打上了勾。核查要是翻出了缺项，脚本会把缺的排在 ✗ 一侧列出来，咱们答一次 y 它就代装，答了 n 就跳过。脚本代装前会拿 sudo -v 探一下咱们的权限，当前的用户没有 sudo，或者有别的 apt 进程占着包管理器的锁，这一步过不去的话，依赖就装不成了。脚本的脾气，start 卷 env-init 那一篇有完整的说明。

## 二、交叉工具链就位：前缀是一段自述

### 工具链在哪、怎么验

本卷统一用 ARM 官方的 GNU 工具链，装的位置在 `/opt/arm-gnu-toolchain`，start 卷工具链篇用的就是这个装法。PATH 里带上它的 bin 目录之后，前缀接 gcc 就能叫出它的真名，咱们看它在哪、是什么版本：

```bash
# 主机 ~/imx-forge
command -v arm-none-linux-gnueabihf-gcc
arm-none-linux-gnueabihf-gcc --version | head -1
```

```text
/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc
arm-none-linux-gnueabihf-gcc (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203
```

command -v 报出的是可执行文件的完整路径，工具链就住在这个路径指向的目录里。版本行咱们拆着读：Arm GNU Toolchain 15.2.Rel1 是发行包的名字，15.2.1 是 gcc 本尊的版本号，20251203 是它的构建日期。后面凡是 `CROSS_COMPILE=arm-none-linux-gnueabihf-` 出现的地方，指的都是这一套。

### 前缀四个字段各说什么

arm-none-linux-gnueabihf- 这串前缀本身就是它的一段自述，咱们按连字符把它分成四个字段。arm 说的是目标架构，生成的机器码是 ARM 指令。none 说的是厂商字段为空，这套工具链没有经过哪个芯片厂商的定制。linux 说的是目标系统跑 Linux，C 库配套的是 glibc 那一套。gnueabihf 说的是 ABI，指的是 GNU EABI 加硬浮点，hf 就是 hard-float 的缩写，函数调用的时候浮点参数直接走浮点寄存器。i.MX6ULL 里面的 Cortex-A7 带硬件 FPU，硬浮点这套正好把它的算力用上，本卷从 start 卷起咱们就统一用硬浮点，工具链名与构建脚本里的前缀一字不差。

### 主机 gcc 为什么不行

为什么不直接用系统的 gcc？咱们用的电脑 CPU 是 x86_64（uname -m 的实跑输出），它执行的指令集与板子上 ARMv7 那套完全是两种语言，主机 gcc 生成的机器码板子认不得。还有一层是 C 库：主机程序链的是 x86_64 版的 glibc，板子要的是 ARM 硬浮点 ABI 的 glibc，二进制形态也通用不了。交叉工具链干的就是这件事——程序本体跑在 x86_64 上，产出的代码与库落向 ARM。原理的完整版，笔者写在 linux-basics 卷的交叉编译一章，值得深读的正是[第 35 章 交叉编译与 imx-forge 衔接](../linux-basics/07-devtools/ch35-crosscompile.md)。

## 三、源码从哪来、锁在哪

### 子模块与 .gitmodules

U-Boot 的源码不进 imx-forge 仓库本体，它以子模块的身份挂在 third_party/uboot-mainline 下，主仓库的树里记的只是一个提交号，git 的术语叫它 gitlink。咱们把机制认下来再看配置：从哪拉、怎么拉，`.gitmodules` 里的这一段是全部的家底：

```text
[submodule "third_party/uboot-mainline"]
	path = third_party/uboot-mainline
	url = https://github.com/u-boot/u-boot.git
	shallow = true
	ignore = dirty
```

url 指向的是 u-boot 官方仓库本身，中间没有别人的镜像。shallow = true 告诉 git 拉的时候取浅历史，全量克隆就不用做了，几十年的完整提交历史咱们用不上。ignore = dirty 让主仓库的 git status 忽略子模块工作区的未提交改动，AES 补丁是 staged 在子模块里的，主仓库这边的 git status 就不该被它搅得天天有动静。笔者在本机量过，工作区一共占了 361M，它的 git 目录不在树里，挂在主仓库的 .git/modules/third_party/uboot-imx 里，另占了约 59M，合计大约是 420M 的样子。

### 核实锁在哪个提交

咱们自己拿三条只读命令就能核出锁在哪个提交上：

```bash
# 主机 ~/imx-forge/third_party/uboot-mainline
git log --oneline -1
git rev-parse HEAD
git rev-parse v2026.10^{commit}
```

```text
55084065 Prepare v2026.10
5508406582f6f7120dce0c4b3059819a41788db2
5508406582f6f7120dce0c4b3059819a41788db2
```

咱们逐行读：头一行说 HEAD 停在 55084065，提交标题写的是 Prepare v2026.10。后两行做到了一个字符都不差，HEAD 与 v2026.10 标签指的是同一个提交。标签在咱们本机的树里也在场，笔者又补了一条 describe：

```bash
# 主机 ~/imx-forge/third_party/uboot-mainline
git describe --tags HEAD
```

```text
v2026.10
```

有一个细节笔者如实交代。shallow = true 的浅克隆不一定带着标签，谁要是刚从净的克隆起步，第三条命令可能报出来的就是 unknown revision，那时拿第二条的完整哈希与 5508406582f6f7120dce0c4b3059819a41788db2 对号就行，哈希本身就是锁——标签只是给这个哈希起的好记名字。想把标签补下来的话，咱们用 `git fetch origin refs/tags/v2026.10` 拉回来再核一遍。

### 开发树与 CI：同一份补丁，两种上法

本机这棵树的补丁已经打上并 staged，AES 板卡的 13 个文件全在工作区里，咱们数一遍：

```bash
# 主机 ~/imx-forge/third_party/uboot-mainline
git diff --cached --stat | tail -1
```

```text
 13 files changed, 1734 insertions(+)
```

CI 走的是另一条路，用的是净源码加补丁，咱们把两条路分开认。发布编排把子模块重置到净的 v2026.10，再叠上 `patches/uboot-mainline/charlies_board.patch` 的补丁，发布的产物就从这套组合里编出来。本机的树是开发树，补丁是常驻工作区的，下一节 grep 6ull 的清单里能看到 mx6ull_aes_emmc_defconfig，就是补丁带进来的。两条路的工程细节住在 build 卷的 out 目录结构与补丁工作流两篇里，本篇就不展开了。

## 四、树里跟咱们有关的位置

### configs：14 份 6ULL 配置

配置的入口全在 configs/ 目录，一个 defconfig 对应的板型就一份。跟 6ULL 有关的，咱们 grep 一把：

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/configs | grep 6ull
```

```text
colibri-imx6ull-emmc_defconfig
colibri-imx6ull_defconfig
mx6ull_14x14_evk_defconfig
mx6ull_14x14_evk_plugin_defconfig
mx6ull_aes_emmc_defconfig
o4-imx6ull-nano_defconfig
seeed_npi_imx6ull_defconfig
somlabs_visionsom_6ull_defconfig
tqma6ullx_mba6ul_mmc_defconfig
tqma6ullx_mba6ul_qspi_defconfig
tqma6ullx_mba6ul_uuu_defconfig
tqma6ullxl_mba6ul_mmc_defconfig
tqma6ullxl_mba6ul_qspi_defconfig
tqma6ullxl_mba6ul_uuu_defconfig
```

一共 14 份的清单，咱们分堆认。colibri 的两份，EVK 的两份，普通版与 plugin 版（plugin 指带 plugin 启动形态的镜像变体），TQ 的模块板占六份，seeed、somlabs、o4-imx6ull-nano 这些第三方板占了三份，跟在 EVK 两份后面的 mx6ull_aes_emmc_defconfig，是补丁带进来的咱们自己的板。本篇第五节试跑用的 mx6ull_14x14_evk_defconfig 是官方 EVK 的参考底版，与上游逐字节是一致的，上一篇核 staged 与工作区两份 diff 的时候，都查不到它的名字。第 6 站（参考配置逐行核对）拿它逐行讲配置怎么读。

### board/nxp：参考底版与咱们的板卡

板级 C 代码住的地方在 board/nxp，跟咱们有关的两个目录，笔者把文件清单都列出来：

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/board/nxp/mx6ul_14x14_evk
ls third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc
```

```text
Kconfig
MAINTAINERS
Makefile
mx6ul_14x14_evk.c

Kconfig
MAINTAINERS
Makefile
imximage.cfg
imximage_lpddr2.cfg
mx6ull_aes_emmc.c
plugin.S
```

前一个目录是官方 EVK 的板级代码，装了四个文件，第 7 站（最小板卡适配）拿它给咱们当参照底版。后一个目录是 AES 板的，装了七个文件，全都是补丁带来的：板级 C 代码 mx6ull_aes_emmc.c，两份镜像头的配置 imximage.cfg 与 imximage_lpddr2.cfg（前者管默认颗粒，后者备给换 LPDDR2 内存的场合），管汇编入口的 plugin.S，加上 Kconfig、MAINTAINERS、Makefile 三件登记用的配置件，构建系统靠它们认出 AES 板的身份。AES 目录的逐个文件在第 7 站与第 9 站（DDR 与镜像头）展开。

### arch/arm/dts：两套设备树源文件

设备树的源文件都收在 arch/arm/dts 里，跟咱们有关的是两套四份，笔者 grep 出来：

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/arch/arm/dts | grep -E 'imx6ull-14x14-evk|^imx6ull-aes'
```

```text
imx6ull-14x14-evk-u-boot.dtsi
imx6ull-14x14-evk.dts
imx6ull-aes.dts
imx6ull-aes.dtsi
```

EVK 的一套有两份，一份是板卡自己的 imx6ull-14x14-evk.dts，另一份是 U-Boot 专用的扩展，它的名字是 imx6ull-14x14-evk-u-boot.dtsi，两份合起来管 EVK 的设备树。AES 的一套也是两份，imx6ull-aes.dts 是 AES 的本体，它的公共部分收在 imx6ull-aes.dtsi 里。U-Boot 编镜像的时候把设备树一并编成 dtb 塞进产物，AES 两份的来历与逐节点写法是第 8 站（AES 设备树）的正题，咱们到时再翻。

## 五、O= 独立输出目录与 distclean

### 产物为什么不混进源码树

编译的产物与配置结果要是散在源码树里，麻烦就跟了咱们一整个开发周期。最常见的情形是：咱们改了 configs/ 下的 defconfig，重新 make 了一遍，改动却像没生效似的。根因在 make 认的是已经生成的 .config，旧的一份还躺在输出目录里，make 沿用它继续编了下去，defconfig 源文件上的改动根本没进到配置里，排查半天的线索全指向自己。仓库的做法是把产物圈进独立目录——build-uboot.sh 里 OUTPUT_DIR 定在 out/uboot，配置与编译两步传给 make 的时候都带了 O=：

```text
# scripts/build_helper/build-uboot.sh，65 行与 151 行附近
: "${OUTPUT_DIR:=${PROJECT_ROOT}/out/uboot}"
local cmd="make -C ${UBOOT_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUTPUT_DIR} ${DEFCONFIG}"
```

之后我们都会把输出丢到专门的目录中，现代的CMake等都是这样做的，要不然源码树简直没法看，你的IDE会爆炸。

::: warning 混用两种输出方式
有的一步带 O=，有的又在源码根里直接 make，两份 .config 与两堆产物就这么并存了。后果是同一份源码编出了两种镜像，咱们核产物时核到的就是旧的那枚，改动看着怎么都不生效。根因是 .config 跟着各自的输出目录走，两边是互不同步的。本卷的命令统一带 O=，约定从本篇起就不再变了。
:::

### distclean 清到什么程度

清理的路数有两档。make distclean 是 U-Boot 自带的目标，把生成物与 .config 一起收走的是它。仓库的脚本走得更干脆，do_distclean 不调 make 而是直接把输出目录删掉重建，咱们看它的原文：

```text
# scripts/build_helper/build-uboot.sh 的 do_distclean，144-145 行
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
```

O= 模式下 distclean 要清的东西本来也都在输出目录里，两档的效果等价，脚本挑了不容易留尾巴的那档。咱们手动操作时记两组对应关系就行：改了 defconfig，咱们就重跑 defconfig 目标让它重新生成 .config。想全部重来的话，把 O= 目录整个删掉就干净了。下一篇开跑前的清理走的就是这套。

## 继续学习

- [第 35 章 交叉编译与 imx-forge 衔接](../linux-basics/07-devtools/ch35-crosscompile.md)：交叉编译原理的完整版
- [环境初始化：env-init.sh](../start/02_env_init_guide.md)：依赖核查脚本的完整说明
- [净源码里没有咱们的板卡](./06_aes_vs_evk_diff.md)：EVK 与 AES 的逐行对账与补丁纪律
- [七步造出咱们的板卡](./07_board_porting.md)：board/nxp 两个目录的正题
- [设备树](./08_device_tree_aes.md)：两套设备树文件的来历与写法
