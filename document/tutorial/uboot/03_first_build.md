---
title: 第一次编译官方参考板：从 distclean 到四个产物
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 第一次编译官方参考板：从 distclean 到四个产物

> 这一篇咱们把官方参考板 i.MX6ULL 14x14 EVK 的 U-Boot 真正编出来：清理、配置、并行构建一条龙走完，产出四个文件并逐个认清它们各自是什么。上一篇把依赖安装和交叉编译的原理讲完了，本篇全部是动手的活。编出来的东西还不等于板上能跑的东西，中间隔着 BootROM、DDR 和存储介质三条关，下一篇的验证与烧录带着咱们逐条过。

## 一、编译三连：清理、配置、并行构建

### distclean 为什么排在头一个

咱们先看一个刚发生的事实。笔者把 defconfig 跑进一个一次性的输出目录 `/tmp/fb-demo2`，`.config` 就出现在了那个目录里，42877 字节，源码树里一个配置文件都没多。`.config` 是 defconfig 加 Kconfig 依赖关系算出来的完整配置（上一篇讲过这对搭档），编译全程只认它，而它住在输出目录而不是源码树里，这个事实打底，本篇后面关于输出目录的判断全从这里出发。

配置阶段的输出里有一行 `# configuration written to .config`，整个流程只有这一刻 `.config` 会被重写。之后咱们要是改了 `configs/` 里的 defconfig 文件，或者想换一块板子，光敲 `make` 是没有用的——kbuild（U-Boot 从 Linux 内核借来的那套构建系统，make 命令背后真正干活的就是它）拿旧 `.config` 照编不误，改动看起来就像没生效。这话不是笔者猜的：编完之后又跑了一遍不带任何目标的 `make`，前后两次 `md5sum .config` 都是 `a645207e36eab62146e50971eac1660b`，一个字节没动。

换板这件事笔者真试过。同一个输出目录里配 EVK，`.config` 里写着 `CONFIG_TARGET_MX6ULL_14X14_EVK=y`，接着改跑 `mx6ull_aes_emmc_defconfig`（AES 板，本仓库自改的那块），`.config` 立刻变成 `CONFIG_TARGET_MX6ULL_AES_EMMC=y`，旁边多出一个 `.config.old`，那是被换下来的旧配置。生效的原因正是这次重跑了 defconfig 目标，跟 make 没有关系。

`distclean` 干的事在输出里写得明明白白：一行 `CLEAN .config`，跑完 `.config` 就没了，中间产物与生成头文件一并带走，输出目录回到白纸状态。所以换目标板、改过配置、怀疑目录状态对不上劲的时候，distclean 一步到位。全量编译在 16 核上只要 8.8 秒（马上实测给咱们看），清理的代价接近零，犹豫的时候清就完了。真舍不得删配置的场合（比如 menuconfig 调出来的私有改动）用 `clean`，它留 `.config` 删产物。

顺手把最后一个疑点用真实输出交代掉：没有 `.config` 的时候直接 make，kbuild 当场拒绝干活。

```text
***
*** Configuration file ".config" not found!
***
*** Please run some configurator (e.g. "make oldconfig" or
*** "make menuconfig" or "make xconfig").
***
make[1]: *** No rule to make target '.config', needed by 'include/config/auto.conf'.  Stop.
```

`include/config/auto.conf` 是 `.config` 转出来的编译期配置，缺了它 make 连依赖图都搭不起来。这段是笔者拿一个全新目录复现的，一字未改。

### 三条命令与真实输出

这一轮笔者把产物放到 `/tmp/uboot-batch2-evk`，源码树保持干净。第一条命令把输出目录清干净，复用旧目录时必做，全新目录本来就是白纸：

```bash
# 主机 ~/imx-forge
make -C third_party/uboot-mainline O=/tmp/uboot-batch2-evk ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- distclean
```

笔者这一轮就是在已经用过一遍的目录上跑的，输出尾部（`tail -6` 的真实截取）长这样：

```text
  CLEAN   scripts/basic
  CLEAN   scripts/dtc
  CLEAN   scripts/kconfig
  CLEAN   include/config include/generated spl include/asm .config .config.old include/asm
make[1]: Leaving directory '/tmp/uboot-batch2-evk'
make: Leaving directory '/home/charliechen/imx-forge/third_party/uboot-mainline'
```

被收走的就是末条 CLEAN 列出的那批：`.config` 和 `.config.old`（换下来的旧配置，前文刚见过它），连同编译产物与生成头文件一起清掉。

第二条命令做配置：

```bash
# 主机 ~/imx-forge
make -C third_party/uboot-mainline O=/tmp/uboot-batch2-evk ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- mx6ull_14x14_evk_defconfig
```

输出尾部（`tail -4` 的真实截取）长这样：

```text
# configuration written to .config
#
make[1]: Leaving directory '/tmp/uboot-batch2-evk'
make: Leaving directory '/home/charliechen/imx-forge/third_party/uboot-mainline'
```

被截掉的部分笔者对着上一轮的完整记录核了一遍，能对上号：kbuild 编出 fixdep（给每个编译目标登记头文件依赖，增量编译靠它判断谁要重编）、conf 这些主机端工具，跑 YACC 和 LEX 生成 Kconfig 自己的语法与词法分析器源文件，最后由 conf 读入 defconfig、写出完整 `.config`。

这里有个口径差要交代：正点原子系教程里沿用的 `mx6ull_14x14_evk_emmc_defconfig`（旧版教程示例出现过它的名字，现行两篇已不再使用）在这棵 v2026.10 树里不存在，`configs/` 下 mx6ull 系 EVK 相关的只有 `mx6ull_14x14_evk_defconfig` 与 `mx6ull_14x14_evk_plugin_defconfig` 两份，后者比前者多 `CONFIG_USE_IMXIMG_PLUGIN=y`、少 regulator 的两行（`CONFIG_DM_REGULATOR_FIXED=y`、`CONFIG_DM_REGULATOR_GPIO=y`），本篇用前者。这份 defconfig 文件本身只有 1727 字节，算出来的 `.config` 有 42877 字节，差额全是 Kconfig 按依赖关系补上的默认值——defconfig 只存差异（这层机制 [七步造出咱们的板卡](./07_board_porting.md) 会细讲），数字就摆在这儿。

第三条命令做全量编译：

```bash
# 主机 ~/imx-forge
time make -C third_party/uboot-mainline O=/tmp/uboot-batch2-evk ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j$(nproc)
```

尾部八行与计时都是真实截取：

```text
  CAT     u-boot-dtb.bin
  COPY    u-boot.dtb
  COPY    u-boot.bin
  CFGS    u-boot-dtb.cfgout
  MKIMAGE u-boot-dtb.imx
  OFCHK   .config
make[1]: Leaving directory '/tmp/uboot-batch2-evk'
make: Leaving directory '/home/charliechen/imx-forge/third_party/uboot-mainline'
```

```text
real	0m8.835s
user	1m3.131s
sys	0m15.374s
```

user 时间是 real 时间的七倍还多，1 分 03 秒的活 8.8 秒干完，靠的是 `-j$(nproc)` 把任务摊到十六个核上，`nproc` 输出本机核心数。这几行尾部笔者对着上一轮的记录认了一遍，本身就是打包流水线：`CAT` 把裸二进制和设备树拼成 `u-boot-dtb.bin`，`COPY` 备出 `u-boot.dtb` 与 `u-boot.bin`，`CFGS` 把板级配置文件（imximage.cfg 这类）用预处理器展开成 `u-boot-dtb.cfgout`，`MKIMAGE` 接着垫 IVT 头产出 `u-boot-dtb.imx`，用的正是这份 cfgout，`OFCHK` 跑 scripts/check-of.sh 拿 `.config` 对照 of_allowlist.txt，查这类靠上一级固件提供设备树的板子有没有把 `CONFIG_OF_BOARD` 关掉。更早的 `LD u-boot`、`OBJCOPY u-boot-nodtb.bin` 和十来行 `DTC` 在上一轮记录里都有，流程与这一轮一致。

这三连在工程里已经包成了 `scripts/build_helper/build-uboot.sh`：依赖检查与产物校验都在里面，编的目标换成了 AES 板的 `mx6ull_aes_emmc_defconfig`，细节看脚本头部注释和它 source 的 `scripts/lib`。本篇先把手动版走通，手脚知道自己在干什么，脚本才不是黑盒。

### ARCH、CROSS_COMPILE、O= 各自改了 make 的什么

咱们加上 `ARCH=arm`，kbuild 才会进 `arch/arm` 找 CPU 代码、板级代码与链接脚本，上一轮记录里满屏的 `arch/arm/cpu/armv7`、`arch/arm/mach-imx` 就是证据。不带它，kbuild 按主机架构走，i.MX 的那一批文件根本轮不到编。

`CROSS_COMPILE=arm-none-linux-gnueabihf-` 是个前缀而不是路径。这个前缀，make 拿它拼出 `arm-none-linux-gnueabihf-gcc`、`…-ld`、`…-objcopy`，再按 `PATH` 去找。这套前缀对应的工具链跑在主机上、产出 ARM 指令，名字每一段的含义上一篇讲过，后缀 `hf` 是硬浮点 ABI，i.MX6ULL 带 FPU，咱们就选它。

`O=/tmp/uboot-batch2-evk` 管的是文件落点。没有它，`.config` 加几千个中间文件全堆进源码树，`git status` 会变成垃圾场。有了它，输出与源码分家，全量编译开头那行 `Using /home/charliechen/imx-forge/third_party/uboot-mainline as source for U-Boot` 就是 kbuild 在声明源码读哪里、产物写哪里。本仓库的工程脚本把产物放在 `out/uboot`，同一个思路。本轮编完笔者看过 `git status`，除了 AES 板卡那批本地改动，没有一个编译垃圾。

版本号笔者也顺手核对了一遍。`include/config/uboot.release` 里写着 `2026.10-dirty`，`dirty` 是源码树带本地改动的标记，改动的主体就是 AES 板卡那批文件（`arch/arm/dts/imx6ull-aes.dts`、`board/nxp/mx6ull_aes_emmc/` 整个目录、`configs/mx6ull_aes_emmc_defconfig`），基线是上游 v2026.10。

## 二、产物清单：四个文件各自是什么

编译完看产物，四个主角挨个点名（真实输出）：

```bash
# 主机 ~/imx-forge
ls -la /tmp/uboot-batch2-evk/u-boot /tmp/uboot-batch2-evk/u-boot-dtb.imx /tmp/uboot-batch2-evk/u-boot.bin /tmp/uboot-batch2-evk/u-boot.dtb
```

```text
-rwxr-xr-x 1 charliechen charliechen 4659252 Nov 14 15:32 /tmp/uboot-batch2-evk/u-boot
-rw-r--r-- 1 charliechen charliechen  437248 Nov 14 15:32 /tmp/uboot-batch2-evk/u-boot-dtb.imx
-rw-r--r-- 1 charliechen charliechen  431144 Nov 14 15:32 /tmp/uboot-batch2-evk/u-boot.bin
-rw-r--r-- 1 charliechen charliechen   31744 Nov 14 15:32 /tmp/uboot-batch2-evk/u-boot.dtb
```

输出目录里还有 `u-boot-dtb.bin`、`u-boot-nodtb.bin`、`u-boot.map` 这些中间产物，本篇不展开。

笔者上一轮在同一棵树上编过一次，对照很有意思：`u-boot.bin`、`u-boot.dtb`、`u-boot-dtb.imx` 三个数一字节不差（431144、31744、437248），带调试信息的 `u-boot` 长了 8 个字节（4659252 对 4659244）。拿 cmp 把两个 ELF 比了一遍，内容差异上百万字节，调试信息里散着构建时间与路径，每一轮都会浮动。烧录要用的小产物倒是稳定得很，数字对得上号，才敢往板上送。

四个文件是什么，`file` 命令给出了一手判词：

```text
/tmp/uboot-batch2-evk/u-boot:         ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, with debug_info, not stripped
/tmp/uboot-batch2-evk/u-boot.dtb:     Device Tree Blob version 17, size=31744, boot CPU=0, string block size=2234, DT structure block size=29452
/tmp/uboot-batch2-evk/u-boot.bin:     DOS executable (COM), start instruction 0xb80000ea 14f09fe5
/tmp/uboot-batch2-evk/u-boot-dtb.imx: data
```

| 文件 | 它是什么 | 给谁用 |
|---|---|---|
| `u-boot` | 带 debug_info 的完整 ARM ELF，EABI5，静态链接 | 调试用，`readelf`、`objdump`、GDB 的符号全在它身上，尺寸最大，约 4.6MB |
| `u-boot.bin` | 裸二进制，ELF 壳与调试信息剥掉后的纯代码加数据，`u-boot-nodtb.bin` 拼上设备树得到 | 原料，拼接产物的前身 |
| `u-boot.dtb` | 设备树 blob，版本 17，31744 字节，跟 `ls` 对上 | 原料，板子硬件描述的二进制形态 |
| `u-boot-dtb.imx` | 拼接产物前面垫了 IVT 头的 NXP 烧录镜像 | 烧录用，BootROM 只认这个格式 |

逐个说两句。`u-boot` 是给人看的，GDB 加载它才有符号，[从0开始认识 U-Boot](./01_what_is_uboot.md) 预告过的入口地址也印在它头上，笔者拿 `arm-none-linux-gnueabihf-readelf -h u-boot` 把它翻开：

```text
  Class:                             ELF32
  Machine:                           ARM
  Entry point address:               0x87800000
  Flags:                             0x5000200, Version5 EABI, soft-float ABI
```

ELF32、ARM、入口 `0x87800000`，跟上一轮记录一字不差。Flags 里的 soft-float 是 U-Boot 自己的编译选择，启动早期 FPU 还没就绪，它全程避开浮点运算，跟工具链名字里的 `hf` 两码事，下一篇验证时还会碰它。

`u-boot.bin` 那行 `DOS executable (COM)` 是 `file` 认错了，笔者头一回也被这行输出唬住了。裸二进制没有魔数可对，`file` 按启发式硬猜，开头四个字节 `b8 00 00 ea` 按小端拼成指令字 `0xEA0000B8`，最高字节 `0xEA` 开头就是无条件跳转的编码，特征跟老式 DOS 程序的判据对上了，它就顺着猜了个 DOS。板子复位后跑的头一段指令就在这类裸二进制里，`file` 认不出不代表格式有问题。

`u-boot.dtb` 是设备树 blob，`file` 这回认得很准，版本 17、31744 字节，跟 `ls` 的数字一致。板子长什么样（内存多大、串口在哪个控制器、哪个脚接了什么）的描述全压缩在这份二进制里，咱们拿 `dtc -I dtb -O dts` 随时能把它还原回文本。

`u-boot-dtb.imx` 是四个文件里唯一为 i.MX 的 BootROM 定制的。IVT（镜像向量表，BootROM 认镜像用的那张头表）垫在整个镜像开头，第一节打包流水线里 `MKIMAGE` 干的就是这一步。`file` 对它干脆输出 `data`，因为 IVT 不在 `file` 的魔数库里，咱们得拿 `hexdump -n 64 u-boot-dtb.imx` 看一眼头：

```text
0000000 00d1 4020 0000 8780 0000 0000 f42c 877f
0000010 f420 877f f400 877f 0000 0000 0000 0000
0000020 f000 877f b000 0006 0000 0000 01d2 40e8
0000030 01cc 04e4 0c02 6840 ffff ffff 0c02 6c40
```

开头四个字节是 `d1 00 20 40`，`0xD1` 这个标记值是 i.MX6 系列 IVT 的 tag，BootROM 靠它认出这是一张能启动的镜像。偏移 0x04 的字是入口地址，读到 `0x87800000`，跟 ELF 头里的 Entry point 对上了。偏移 0x0C 的字是 DCD 清单（设备配置数据，BootROM 跳转前照单执行的寄存器写入清单）的指针，值 `0x877FF42C`。逐字节的字段表不在这儿铺开，那是扩展卷 boot-chain 的主场，咱们认到 tag、入口和 DCD 指针就够用了。四份产物的详细验证（readelf 全项、dtc 反编译、mkimage 判读）留给下一篇，那里每一步都要跟板子对证。

## 三、编译成功不等于板子能启动

这一节咱们把话说在前头：编译通过只证明源码能变成合法的 ARM 产物。链接器没报错、ELF 头是 ARM 的、四个文件尺寸对得上，这些证据全部只能支撑到产物这一层，板子上那颗芯片认不认这份产物、起来起不来，编译器一概不管。

板子要起来得过三条关，咱们挨条认。头一条认 BootROM 那关：BootROM 读到镜像后先看 IVT，tag 不是 `0xD1`、头不完整，它直接不认，串口一个字符都不会有，这就是上一节把 hexdump 当 imx 镜像体检的原因。

接着是 DDR 那关，藏在 DCD 里：官方 EVK 的镜像把一串寄存器写入清单放在 DCD（设备配置数据）中，大头是 DDR 控制器的配置，清单错一个值，DDR 就没醒，CPU 跳过去连第一条指令都取不到。换成 plugin 版的 defconfig 会改用一小段插件固件干同样的活，两份 defconfig 的关键差异是 `CONFIG_USE_IMXIMG_PLUGIN` 这一行（diff 里另有两行 regulator 配置的增删，与启动方式无关）。

最后一关是存储介质：镜像得写进 BootROM 选中的那块介质（boot 引脚或熔丝决定 SD、eMMC 还是 SPI Flash），还得写在它规定的位置上，[从0开始认识 U-Boot](./01_what_is_uboot.md) 提过卡上那个固定的 1KB 偏移，差一个扇区，读出来的头就是乱码。

下一篇咱们把 `u-boot-dtb.imx` 送上卡：送到正确的偏移，串口线接好，上电抓第一段输出，拿本篇贴出的 ELF 头与 IVT 头逐项核对。四份产物里烧录用的只有 `u-boot-dtb.imx` 一个，其余三个是调试与原料，别一股脑全拷进卡里。

## 四、编译报错速查

这张表的现象列都是笔者真实复现过的（ABI 那行除外，复现情况写在表后），根因追到机制，解法给到命令。按现象查，不用按顺序读。

| 现象 | 根因 | 解法 |
|---|---|---|
| 跑 defconfig 冒出 `/bin/sh: 1: bison: not found`（缺 flex 就报 `flex: not found`），跟着 `scripts/Makefile.host` 报 Error 127 | Kconfig 的语法分析器源文件 `zconf.tab.c` 由 bison 生成，`zconf.lex.c` 由 flex 生成，defconfig 一开始就执行这两步，工具不在 PATH 当场就停 | `sudo apt install bison flex`，上一篇（源码与环境准备）的依赖清单里本来就有它们 |
| `/bin/sh: 1: arm-none-linux-gnueabihf-gcc: not found`，随后 `scripts/kconfig/Makefile:96` 报 Error 127 | `CROSS_COMPILE=` 只是前缀，make 拿它拼出 gcc、ld、objcopy 再按 PATH 找，工具链装了但 bin 目录没进 PATH 就找不着。defconfig 目标要拿交叉 gcc 当预处理器，把 defconfig 文件先过一遍预处理再交给 Kconfig 解析（scripts/kconfig/Makefile:96），make 解析期也会调它几次留噪声，卡死就在这一步，轮不到编 C 文件就暴露 | 把工具链 bin 目录加进 PATH（`export PATH=/opt/arm-gnu-toolchain/bin:$PATH`，路径按自己机器改），或者核对前缀有没有拼错 |
| 板子黑屏无串口输出，回主机拿 `readelf -h` 查产物，Machine 不是 ARM 或 Class 不是 ELF32 | 交叉工具链的字长或 ABI 拿错了，产出的指令集不是这颗 Cortex-A7 认的，链接器不报错是因为产物自身自洽 | `CROSS_COMPILE` 锁定 `arm-none-linux-gnueabihf-`，编完拿 `readelf -h` 对照本篇贴出的 ELF 头（ELF32、ARM、入口 0x87800000） |
| `mkdir: cannot create directory '.tmp_107200': Permission denied`，跟着 fixdep 报 `opening dependency file ... No such file or directory` | `O=` 指向的目录对当前用户只读，常见成因是某一回拿 sudo 跑过编译，目录归了 root | `sudo chown -R 自己的用户名 目录` 拿回属主，或者换一个自己的目录，编译别用 sudo |

复现方法交代一下，免得这表像凭空写的。bison 那行，笔者把 PATH 里的 bison 和 flex 各摘掉试了一次，缺哪个报哪个，Error 127 是 shell 的命令不存在退出码。交叉编译器那行同理，把 PATH 缩成 `/usr/bin:/bin` 就复现出来，还顺带证实了 defconfig 阶段就会调一次交叉 gcc。权限那行拿 `chmod 555` 的只读目录复现，root 属主目录是同一类根因。ABI 那行笔者没法诚实复现，这台机器没装第二套工具链，现象与解法来自机制推演加 ELF 头对照，真板上的表现等下一篇的验证环节补证。

## 继续学习

- [净源码里没有咱们的板卡](./06_aes_vs_evk_diff.md)：本篇编的是官方 EVK，仓库里还住着笔者自改的 AES 板，两块板的差异从这一篇逐行铺开。
- [七步造出咱们的板卡](./07_board_porting.md)：Kconfig 与 defconfig 的深层机制、第一次板级移植，接在本篇与验证之后。
