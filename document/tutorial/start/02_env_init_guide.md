---
title: 环境初始化：env-init.sh
---

# 环境初始化：env-init.sh

> 工具链装好了，满心欢喜去编 U-Boot，第一屏输出就栽在 `bison: command not found` 上：上一篇装的交叉工具链只管给 ARM 板子编代码，而构建过程自己在主机上还要吃一堆原生工具。本篇讲的 env-init.sh 就是管这半套环境的脚本：按构建阶段查依赖、缺了当场交互式补装、还能被各构建脚本直接导入。咱们上一篇装的是工具链本体，这一篇补齐主机侧依赖；板子硬件的速查留给下一篇。

::: tip 前置知识 · 环境
- 交叉工具链的安装与 PATH 配置，您回 [从 0 开始构建嵌入式 Linux 开发环境](01_start_from_toolchain.md) 看，本篇不重复这个过程
- 脚本本体在仓库根下的 scripts/init/env-init.sh，三百多行，建议您开着编辑器对照读
- 路径上下文：本篇所有命令都在仓库根 ~/imx-forge 的主机终端执行，检查对象是 Ubuntu/WSL2 主机的软件包，交叉工具链位于 /opt/arm-gnu-toolchain，本篇不涉及板端操作，也不改动任何源码树
:::

## 一、它管的是工具链之外的那半环境

装完工具链那天笔者干的第一件事就是编 U-Boot，然后在第一屏输出里见到了 `bison: command not found`。这不难理解：上一篇咱们装的 `arm-none-linux-gnueabihf-gcc` 是给 ARM 板子编代码的，可 U-Boot 和内核的构建过程自己也要在主机上跑一堆原生工具——内核要先用主机的 gcc 编出构建期的辅助程序，设备树靠 dtc 编译，bison 和 flex 负责语法生成，做镜像时还得 sfdisk 来写分区表。这些包没有一个跟交叉编译沾边，全躺在 apt 仓库里等咱们自己想起来。

env-init.sh 干的就是收拢这摊子事：它把构建 U-Boot、内核、BusyBox、镜像各自需要的主机包列成清单，一次查完，缺了能当场补装。后面咱们贴的输出全部来自这个脚本的真实运行。

它在构建链里的位置您也该知道。五个 build-*.sh 里，导入它的是 build-uboot.sh 和 build-linux.sh 这两个：前者第 37 行 source、第 76 行一句 `check_uboot_dependencies || exit 1`，后者的写法一模一样。所以走 U-Boot 和内核这两条分步路时，您不需要手动跑它。另外三个得分开说：build-mainline-linux.sh 不导入它，而是把同样一份清单的检查内联在自己脚本里，清单和探测方式与 env-init 的 Stage 2 一致，但缺包时它不问 y/n，打印一行 sudo apt install 提示后直接退出，不会像 env-init 那样当场交互式补装。build-buildroot.sh 没有这层 stage 式主机依赖检查，主机依赖的事留给 Buildroot 自己的构建检查。build-qemu.sh 则对 ninja、glib-2.0、pixman-1 这三个 QEMU 构建特有的主机包做了点状检查，缺了当场报错退出，提示里连 apt 包名都给好了，只是不查 env-init 那份 stage 清单——Buildroot 和 QEMU 的依赖本来就不在这张表里，这三条检查算是它自己的兜底。需要亲手跑它的场景是换了新机器、想单独验证环境，或者在排查一个来路不明的构建失败时，把依赖这层因素先排除掉。

## 二、用法：帮助与按阶段检查

帮助信息是脚本自己打印的，咱们先看实跑输出：

```bash
# 主机 ~/imx-forge
./scripts/init/env-init.sh --help
```

```text
Usage: env-init.sh [OPTIONS]

检查主机依赖包并可选安装缺失的依赖。

OPTIONS:
    --stage <1|2|3|5>    检查特定构建阶段的依赖包
                         1 = U-Boot依赖
                         2 = Linux依赖（NXP BSP & Mainline）
                         3 = BusyBox依赖
                         5 = 镜像生成依赖（sfdisk 等）
    -h, --help           显示此帮助信息

EXAMPLES:
    env-init.sh              # 检查所有依赖包
    env-init.sh --stage 1    # 只检查U-Boot依赖包
    env-init.sh --help       # 显示帮助信息
```

不带参数就是查全部，`--stage` 后跟阶段号只查那一档。笔者在本机跑了一次 stage 3，外面裹了一层 timeout 保护：提问走的是 /dev/tty，关标准输入拦不住它，万一缺包，能把脚本掐掉的只有这层 timeout；本机这两个包都齐，提问没有真触发，纯属保险：

```bash
# 主机 ~/imx-forge
timeout 30 ./scripts/init/env-init.sh --stage 3
```

```text
[INFO] 检查 Stage 3 (BusyBox) 依赖包...
[INFO] 检查 BusyBox 依赖包...
[INFO]   ✓ build-essential
[INFO]   ✓ libncurses-dev
[INFO] All BusyBox dependencies found
```

开头两行是主流程和检查函数各报了一次名，属正常现象；ANSI 颜色码已略去。您可能注意到合法值里没有 4，这事咱们放到下一节说。

## 三、依赖都分在哪个 stage

咱们把脚本顶部按构建目标分好的那四组清单整理成下表，这就是全部，没有藏着的第五组：

| Stage | 构建目标 | 依赖包 |
|---|---|---|
| 1 | U-Boot | build-essential、bc、bison、flex、device-tree-compiler、python3、python3-pyelftools、swig、libssl-dev、libgnutls28-dev、libncurses-dev、imagemagick |
| 2 | Linux 内核（imx 轨与主线共用） | build-essential、bc、bison、flex、device-tree-compiler、python3、libssl-dev、libgnutls28-dev、libncurses-dev |
| 3 | BusyBox | build-essential、libncurses-dev |
| 5 | 镜像生成 | fdisk（提供 sfdisk 命令） |

关于 Stage 2 咱们把话说准：项目默认走 imx 轨（NXP BSP 的内核），切主线内核靠 release-all.sh 的 `--mainline` 开关，默认值 `KERNEL_TRACK="imx"` 写在脚本第 58 行，而两轨的主机依赖完全一致，所以一张表就够用。Stage 3 的 BusyBox 表脚本里确实备着；不过要如实提醒您，rootfs 的现行方案是 Buildroot，Buildroot 自己那套依赖不在这张 stage 表里，从构建到裁剪的完整流程咱们放到 [Buildroot 根文件系统](../buildroot/) 卷去讲。至于为什么没有 Stage 4，帮助信息里的 `1|2|3|5` 就是全部答案，4 是空号，传进去只会得到一句 Usage 提示。

这张表还有个耐看的细节：脚本查的不是包记录，而是能力。build-essential 用 gcc 和 make 两条命令是否存在来判断；python3-pyelftools 靠 `python3 -c "import elftools"` 试导入；imagemagick 对应的是 convert 命令；fdisk 这个包名底下实际查的是 sfdisk——Ubuntu 把 sfdisk 从 util-linux 拆进了独立的 fdisk 包。libncurses-dev 和 libgnutls28-dev 还留了头文件兜底，dpkg 里查不到记录但 /usr/include 下有头文件的机器（比如从源码自装的）也算过。换句话说，只要您机器上真能干活，它就不闹。

## 四、缺包了：交互式安装

查到缺包时，脚本会把缺的列出来，附一条拼好的 apt 命令，然后问您要不要自动装。应答的分支很朴素：输入 y 或 Y，脚本先用 `sudo -v` 验一下权限，再执行 `sudo apt update && sudo apt install -y` 把缺的包一次装上；输入 n、N 或者任何别的字符，都会跳过安装，检查函数返回 1，调用它的构建脚本随之退出。

有个实现细节得单独说：脚本读答案优先走 /dev/tty 而不是标准输入。也就是说就算您把脚本塞进管道执行，这个提问也会直接落到终端上等人亲手敲。CI 里这么跑，结局分两种情形：执行器带伪终端（比如 docker run -t）时 /dev/tty 打得开，却永远等不到输入，任务真挂在 y/n 提示上；完全没有控制终端时 /dev/tty 打不开，read 当场报错，set -e 让脚本立刻以退出码 1 结束——那是快速失败，不是挂住。对策咱们放在故障排除一节。

::: warning 未实测标注
y 确认后的自动安装分支需要 sudo 权限、网络和 apt 源三方配合，笔者在写作环境里只读了源码没有真装；这个分支的行为以 scripts/init/env-init.sh 里 check_dependencies 函数的源码为准，您机器上的实际输出以现场为准。
:::

## 五、被构建脚本导入着用

咱们再来看它更常见的用法：被别的脚本 source。build-uboot.sh 里的相关写法长这样，节选自真实脚本：

```bash
# 主机 ~/imx-forge（节选自 scripts/build_helper/build-uboot.sh）
source "${SCRIPT_DIR}/../init/env-init.sh"
# ……中间是参数解析等逻辑……
check_host_dependencies() {
    check_uboot_dependencies || exit 1
}
```

节选末尾那行检查在真实脚本里就包在 check_host_dependencies() 函数体里，由 main() 在开场调用（第 288 行），正式动手编译之前先过这道关。source 进来为什么不会立刻开始检查？咱们翻到脚本末尾会看到一道守卫：只有直接运行（basename 是 env-init.sh）才执行主流程——被 source 时只定义函数，何时查、查哪组，全由调用方决定。顶部的日志函数也带着未定义才定义的判断，重复导入没有副作用。可以导入的检查函数一共五个：check_all_dependencies() 查全部依赖，check_uboot_dependencies() 管 U-Boot，check_linux_dependencies() 管内核（imx 轨与主线共用），check_busybox_dependencies() 管 BusyBox，check_image_dependencies() 管镜像生成（Stage 5）。

您在自己写构建脚本时，照抄上面那段 source 加一行检查就够了。最后那个查镜像依赖的函数容易被漏掉，这份脚本的旧版文档就没列它。

## 六、缺包时的完整输出长什么样

下面这屏的来历得跟您交代清楚：它不是实跑转录。笔者写作时机器上包是齐的，没有真造一台缺 bison 的机器去跑安装，这屏是按 check_dependencies 的源码推演出来的结构。推演的规则很机械：已找到的包每个一行 ✓，缺的每个一行 ✗，各自按字母序排，✓ 加 ✗ 恰好凑齐 Stage 1 的全部 12 个包；这里按 --stage 1 直接运行来推，所以开头带着 Stage 1 的报名行，若是被构建脚本 source 后调用检查函数，就没有这行。省略的地方都在块内标了出来；Installing 与安装成功两行之间省掉的，是 sudo apt update 和 apt install 自己刷出的大段输出：

```text
[INFO] 检查 Stage 1 (U-Boot) 依赖包...
[INFO] 检查 U-Boot 依赖包...
[INFO]   ✓ bc
[INFO]   ✓ device-tree-compiler
……（其余 8 个已找到的包，每个一行，按字母序，略）……
[WARN]   ✗ bison (not found)
[WARN]   ✗ build-essential (not found)
[ERROR] Missing dependencies: bison build-essential

[INFO] Install missing packages with:
  sudo apt install bison build-essential

Would you like to install these dependencies automatically? (y/n): y
[INFO] Installing dependencies...
……（sudo apt update 与 sudo apt install -y 刷出的大段输出，略）……
[INFO] Dependencies installed successfully
```

::: warning 未实测标注
这屏为按 check_dependencies 源码推演的结构，非实跑采集；已找到/缺失包按字母序、Stage 1 共 12 包的推演规则以 scripts/init/env-init.sh 的源码为准，您机器上的实际输出以现场为准。
:::

## 七、注意事项

使用上有几条边界咱们心里要有数。安装动作需要网络，apt 源不通时按 y 也救不了场，先解决源再谈安装。脚本的检查混着命令探测、dpkg 记录和头文件兜底，安装那一步才轮到 apt——所以离开 Debian/Ubuntu 一族（包括 WSL2 里的 Ubuntu），缺了 dpkg 和 apt 这两层就没人兜底，别的发行版得您自己对照依赖表移植。交互确认那条路要有真终端，两种失败形态第四节拆过了，这里只补一句：任务看着像死机时，先确认它是不是停在 y/n 提问上，再决定杀不杀。

## 八、故障排除

遇到下表现象时，咱们按根因对症处理：

| 现象 | 根因 | 解法 |
|---|---|---|
| 脚本停在 y/n 提示不动，CI 任务挂起 | 执行器带伪终端（如 docker run -t），/dev/tty 打得开但永远等不到输入 | 在交互终端里跑；CI 里预先装齐依赖，或照输出里那行 sudo apt install 手动补 |
| 脚本没走到提问就报错退出，退出码 1，末尾带 /dev/tty 的报错 | 完全没有控制终端，read 从 /dev/tty 打不开，set -e 让脚本当场结束 | 同上：预装齐依赖或手动 apt install，让脚本根本走不到提问那步 |
| 确认安装后仍然失败 | 网络不通或软件源过期 | 检查网络，sudo apt update 后重试，再不行手动安装输出里列出的包 |
| 某个包始终找不到 | 软件源没启用 universe 仓库 | sudo add-apt-repository universe 后 sudo apt update |
| --stage 4 报 Usage 退出 | 合法值只有 1/2/3/5，4 是空号 | 用 --help 核对，按构建目标选号 |

五种情况里前两种最常见，笔者在 CI 里挂过一回就再也没忘。

## 九、相关脚本

最后咱们把 scripts/build_helper/ 目录的真实内容摆出来，这也是本机的实跑输出：

```bash
# 主机 ~/imx-forge
ls scripts/build_helper/
```

```text
build-buildroot.sh
build-linux.sh
build-mainline-linux.sh
build-qemu.sh
build-uboot.sh
buildroot_menuconfig.sh
clean_buildroot.sh
```

和依赖检查关系最近的几个脚本，咱们各配一句话：build-uboot.sh 是 U-Boot 的分步构建脚本，开场就做依赖检查；build-linux.sh 编 imx 轨（NXP BSP）内核；build-mainline-linux.sh 编主线内核；build-buildroot.sh 用 Buildroot 出 rootfs。再往上一层还有一键编排入口 scripts/release-all.sh，从依赖到镜像一条龙，注意名字是连字符，不是下划线。

## 继续学习

- 上一篇：[从 0 开始构建嵌入式 Linux 开发环境](01_start_from_toolchain.md)，交叉工具链本体的安装与验证，本篇查的主机包是它的另一半
- 下一篇：[板子硬件接口速查表](03_hardware_quick_reference.md)，环境备齐之后，咱们去认识 i.MX6ULL 这块板子上的接口
- 跨卷深读：[Docker 教程](../docker/) 把依赖全部打包进镜像，免去本篇这套检查；[Buildroot 根文件系统](../buildroot/) 是 rootfs 现行方案的完整流程，它的依赖不在 stage 表里
