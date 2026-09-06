---
title: clangd 交叉编译配置：让跳转又快又准
---

# clangd 交叉编译配置：让跳转又快又准

> 远程会话开了，驱动源文件也开了，您按下 F12 想跳进 `copy_to_user` 的定义，迎接咱们的却是一片红色波浪线。代码没写错，是索引器压根没吃到交叉编译的命令行。本篇把 clangd 的索引链路配置通：编译数据库从哪来、仓库根那份 `.clangd` 每一段管什么、后台索引怎么提速；索引这摊归 clangd，构建一键化是下一篇 tasks.json 的事，断点调试归调试卷的 cppdbg，三块各管各的。

::: tip 前置知识 · 咱们的环境
- VSCode 远程开发会话的建立回 [02 VSCode Remote-SSH](02_vscode_remote_ssh.md)，本篇在会话里操作
- 从装插件开始的 IDE 配置全流程，[driver 卷的 IDE 配置指南](../driver/00_chardev_base/06p_ide_setup.md) 有完整一份，本篇不重复装插件那几步
- 路径上下文：本篇所有命令都在仓库根 `~/imx-forge` 下执行，索引对象是 `third_party/linux_mainline` 这棵 mainline 内核源码树，外部构建输出在 `out/mainline/linux`，交叉工具链前缀 `arm-none-linux-gnueabihf-`（Arm GNU Toolchain 15.2.Rel1）
- 仓库根的 `.clangd` 文件真实存在，咱们下面 cat 它做证据
:::

## 一、为什么弃 cpptools 的 IntelliSense 选 clangd

内核树是那种能把通用索引器拖垮的工程：三万多个 C 文件，`drivers/` 下面一套 `include/asm-generic` 再乘一套 `arch/arm/include` 的双架构头文件，加上 `__KERNEL__`、`CONFIG_*` 上千个宏开关。cpptools 的做法是让咱们在 `includePath` 里手工猜路径，猜漏一个目录就跳错文件，猜全了首次索引又要等上很久。更麻烦的是它按宿主机环境猜，而咱们这份代码要用交叉工具链编——头文件、宏、ABI 全是 ARM 的，宿主视角天生对不上。

clangd 换了个思路：不猜，直接读 `compile_commands.json`。这份文件里记着每个 `.c` 文件编译时的完整命令行，交叉编译器前缀、全部 `-I`、全部 `-D` 都在，跳转和补全自然与实际编译一致。代价是咱们要先把这份文件弄出来，再告诉 clangd 哪些 flag 可以剥掉，这正是后面两节的事。

## 二、compile_commands.json：make 目标而非 bear

### 内核原生目标，不用 bear

很多教程拿 bear 包住 make 来抓编译命令，内核树用不着：构建系统自带 `compile_commands.json` 这个目标，由 `scripts/clang-tools/gen_compile_commands.py` 汇总构建输出目录里的 `.cmd` 文件（每次编译由 fixdep 写入的真实命令行）生成。咱们的仓库没有把它集成进构建脚本，得手动敲一次。

这个坑笔者亲自撞过。照着感觉敲下面这条命令，会收获一屏报错：

```bash
# 主机 ~/imx-forge;O= 写了相对路径,这是错误示范
make -C third_party/linux_mainline \
  ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- \
  O=out/mainline/linux \
  compile_commands.json
```

```text
make: Entering directory '/home/charliechen/imx-forge/third_party/linux_mainline'
make[1]: Entering directory '/home/charliechen/imx-forge/third_party/linux_mainline/out/mainline/linux'
***
*** Configuration file ".config" not found!
***
*** Please run some configurator (e.g. "make oldconfig" or
*** "make menuconfig" or "make xconfig").
***
/home/charliechen/imx-forge/third_party/linux_mainline/Makefile:881: include/config/auto.conf.cmd: No such file or directory
make[2]: *** [/home/charliechen/imx-forge/third_party/linux_mainline/Makefile:890: .config] Error 1
make[1]: *** [/home/charliechen/imx-forge/third_party/linux_mainline/Makefile:248: __sub-make] Error 2
make[1]: Leaving directory '/home/charliechen/imx-forge/third_party/linux_mainline/out/mainline/linux'
make: *** [Makefile:248: __sub-make] Error 2
make: Leaving directory '/home/charliechen/imx-forge/third_party/linux_mainline'
```

咱们看 `Entering directory` 那行就明白了：`make -C` 先切进源码树，`O=` 的相对路径于是被解析到 `third_party/linux_mainline/out/...` 底下，那棵树里当然没有 `.config`。和调试卷记录过的 buildroot `O=` 相对路径坑是同一个机制。改成 `$PWD` 打头的绝对路径就通：

```bash
# 主机 ~/imx-forge;O= 必须绝对路径
make -C third_party/linux_mainline \
  ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- \
  O=$PWD/out/mainline/linux \
  compile_commands.json
```

### 前提：先完整构建过一次

这个目标不是只扫扫文件。它挂着 `vmlinux.a`、`KBUILD_VMLINUX_LIBS`、`modules.order` 这些依赖，make 会先把没编完的部分补齐。笔者这次真跑，它先补编了一串 `CC [M]` 的模块，69 秒后才吐出结果：

```text
  CC [M]  net/bluetooth/bnep/netdev.o
  LD [M]  net/bluetooth/bnep/bnep.o
  GEN     compile_commands.json
```

所以正确的顺序是老老实实先跑一遍 `build-mainline-linux.sh` 完成内核构建，再来生成索引。`.cmd` 文件的数目得交代时点：笔者的 out 树在这次补编前有 4114 个，这次补编自己又长出 1592 个，生成后总共 5706 个——您拿 `find out/mainline/linux -name '*.cmd' | wc -l` 复核时，以自己树上的实数为准。

从没构建过的树是另一回事。out 树里连 `.config` 都没有时（从没跑过 `scripts/build_helper/build-mainline-linux.sh` 的树就是这样），这条命令撞上的还是前面那同一屏配置缺失报错，走不到编译那一步，所以完整构建这道门槛咱们绕不过去。`.config` 已在、目标缺失时，它才会当场补齐依赖，等价于一次完整构建。

另外咱们得记住 `make clean` 的边界。它删的只是 out 树里那份 json，动手的是内核 Makefile 的 CLEAN_FILES 清单，`compile_commands.json` 明确列在 Makefile:1694。`M=` 外部模块那条分支的 clean 规则在 2003 行也列了它，不过管不到咱们这条树内链路。源码树根那份拷贝不受影响，索引照常工作。不过那份拷贝从不自动更新——改配置或换 defconfig 重建之后，想让索引跟上新命令行，得重新生成一遍再拷一次就好。

### 验证：大小、条目、内容

生成后 json 落在 out 树，`.clangd` 要的是源码树根那份，咱们拷过去再验：

```bash
# 主机 ~/imx-forge;拷到 .clangd 指向的目录
cp out/mainline/linux/compile_commands.json third_party/linux_mainline/
ls -lh third_party/linux_mainline/compile_commands.json
```

```text
-rw-r--r-- 1 charliechen charliechen 9.0M Sep  2 13:02 third_party/linux_mainline/compile_commands.json
```

9.0M，3145 条记录，其中 3070 条 `.c`、75 条 `.S`，单 `drivers/` 就占 1524 条。咱们挑一条真实现场看看它的长相（ahci_imx 驱动，命令行中段省略）：

```json
{
  "command": "arm-none-linux-gnueabihf-gcc -Wp,-MMD,drivers/ata/.ahci_imx.o.d -nostdinc -I/home/charliechen/imx-forge/third_party/linux_mainline/arch/arm/include -I./arch/arm/include/generated -I/home/charliechen/imx-forge/third_party/linux_mai……",
  "directory": "/home/charliechen/imx-forge/out/mainline/linux",
  "file": "/home/charliechen/imx-forge/third_party/linux_mainline/drivers/ata/ahci_imx.c"
}
```

三个字段正好是 clangd 要的全部：拿 `command` 里的 `-I` 和 `-D` 解析这个 `file`，工作目录取 `directory`。交叉前缀、ARM 头文件路径，一条命令里全齐。拷贝这步您别担心污染 git：内核自己的 `.gitignore` 第 181 行就忽略了 `compile_commands.json`，笔者 `git check-ignore` 验证过。

## 三、.clangd 三段配置

仓库根那份 `.clangd` 是现成的，咱们 cat 出来看全文：

```yaml
# .clangd
CompileFlags:
  CompilationDatabase: third_party/linux_mainline
  Remove:
    - -mno-fp-ret-in-387
    - -mpreferred-stack-boundary=*
    - -mindirect-branch=*
    - -mindirect-branch-register
    - -fno-allow-store-data-races
    - -fconserve-stack
    - -mrecord-mcount
    - -mfunction-return=*
    - -mskip-rax-setup
    - -mharden-sls=*
    - -mno-fdpic
    - -fno-ipa-sra
    - -fzero-init-padding-bits=all

Diagnostics:
  Suppress:
    - drv_unknown_argument
    - invalid-token-paste
    - invalid_token_after_toplevel_declarator
```

### CompilationDatabase 指路

`CompilationDatabase: third_party/linux_mainline` 告诉 clangd 去这个目录找 `compile_commands.json`。路径相对项目根解析，所以上一节咱们才把 json 拷进源码树；您要是嫌拷贝这一步烦，把它改成 `out/mainline/linux` 也行，代价是 clean 之后配置指向一个不存在的文件，两种约定挑一种守到底就好。

### Remove 的 13 项，哪些真出现

这 13 项剥的都是 clang 不认识的 GCC flag。哪些在这棵树里真的出现？笔者拿 grep 把 3070 条 `.c` 命令数了一遍：`-fno-allow-store-data-races`、`-fconserve-stack`、`-mno-fdpic`、`-fno-ipa-sra`、`-fzero-init-padding-bits=all` 五项每条必带，是 Remove 列表真正干活的部分，不剥的话 clangd 满屏报 `drv_unknown_argument`。其余 8 项在这棵树里计数是 0：retpoline 一族、栈对齐、x87 是 x86 的项，-mrecord-mcount 是 x86/aarch64 的 ftrace 项，-mharden-sls 则是 ARM 家族自己的 GCC 选项、只是这套 defconfig 没开对应加固所以没带上。网上不少资料把它们解释成宿主机工具的编译命令带进来的，笔者实测对不上：json 里 3145 条全是目标代码的命令，就算用脚本把 scripts/ 下编译给宿主机用的命令也全扫进来，x86 项还是 0。它们是内核社区流传的通用模板里防身用的，留着无害，剥了也不影响 ARM 代码解析，咱们照抄即可。

### Suppress 压掉三个误报

剥完 flag 还会剩三个干扰诊断：`drv_unknown_argument`（个别漏网 flag）、`invalid-token-paste`（内核里合法的宏拼接写法）、`invalid_token_after_toplevel_declarator`（内核常见的非标准顶层声明）。都是 clangd 按 clang 方言较真较出来的，与代码正确性无关，咱们直接 Suppress 掉。

## 四、settings.json 与索引性能

::: warning 未实测标注
装 clangd 扩展、写 settings.json、按 `Ctrl+Shift+P` 执行 clangd: Restart language server、F12 验证跳转，这几步是 VSCode 的 GUI 流程，笔者的采集环境自动化不了。本机 `which clangd` 找不到系统级二进制，扩展首次启动会提示下载自带的一份。咱们以仓库根 `.clangd` 与 [driver 卷的 IDE 配置指南](../driver/00_chardev_base/06p_ide_setup.md) 附录里的模板为准。
:::

仓库没提交 `.vscode/` 目录（个人工作区文件，git 里没有），这份 settings.json 咱们自己在远程会话里写：

```json
{
  "C_Cpp.intelliSenseEngine": "disabled",
  "clangd.arguments": [
    "--background-index",
    "--clang-tidy",
    "--header-insertion=iwyu",
    "--completion-style=detailed",
    "--function-arg-placeholders",
    "--fallback-style=llvm"
  ]
}
```

第一行是共存的关键：cpptools 的索引引擎一关，它就不再和 clangd 抢解析权，后台索引、补全、诊断全归 clangd。剩下的参数里 `--background-index` 管首次索引在后台跑，`--clang-tidy` 顺带做静态检查，其余是补全风格偏好，您按口味增减。

索引性能还有一口气可挤。咱们这个仓库除了内核树，还有 third_party/buildroot、qt 侧的 host/qt6-host、out 产物这些大目录，全在 clangd 的扫描范围里白吃 CPU。把它们从后台索引里摘出去，走的是 `.clangd` 配置文件自己的条件块：`If` 的 `PathExclude` 按路径排除，再配 `Index.Background: Skip`，命中的文件就不进后台索引。在仓库根 `.clangd` 末尾追加下面这段。路径模式按 clangd 文档的规则写：路径相对 `.clangd` 所在目录解析、不带前导斜杠，且要求整条路径完全匹配，所以三条都不带 `.*/` 前缀，得写成 `third_party/buildroot/` 这样的相对形式。

```yaml
# 仓库根 .clangd,追加在文件末尾;可选的提速项
---
If:
  PathExclude:
    - third_party/buildroot/.*
    - host/qt6-host/.*
    - out/.*
Index:
  Background: Skip
```

::: warning 未实测标注
这段提速配置笔者同样没有在本机 clangd 版本上实际验证过；`If.PathExclude` 与 `Index.Background: Skip` 是 clangd 官方配置文档（clangd.llvm.org/config）里写明的特性，上面三条路径模式也按同一份文档的规则写。真要上机，建议开 clangd 日志复核，确有目录被跳过再算数。[driver 卷的 IDE 配置指南](../driver/00_chardev_base/06p_ide_setup.md) 第六步·问题 3 给的却是仓库根放 `.clangd-ignore` 文件这条路，这个文件名在 clangd 官方文档里查无此特性，只以 feature request 的形式开放着，您要照那篇操作的话建议人眼复核这一处。
:::

## 五、与调试引擎的共存

关掉 cpptools 的 IntelliSense 之后，一个自然的疑问是：断点调试还能用吗？能，而且正好是这套配置的用意。cpptools 这个扩展身兼两职，索引引擎和调试引擎（cppdbg）是两回事，咱们关的只是前者。索引、补全、诊断归 clangd；断点、单步、变量查看归 cppdbg，两边各干各的，一个在您敲键盘时服务，一个在您按 F5 时服务。调试卷的第一篇正是这么落地的：它的第四节给了全仓第一份 launch.json，`miDebuggerPath` 指向工具链里的 `arm-none-linux-gnueabihf-gdb`，那套配置与本章互不依赖。您要看调试链路怎么搭，去 [gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md) 的第四节；要看从装插件开始的 IDE 全流程，回 [driver 卷的 IDE 配置指南](../driver/00_chardev_base/06p_ide_setup.md)。

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| clangd 跳转变慢或干脆没反应 | json 没生成，或 `.clangd` 的路径与 json 实际位置对不上 | 先完整构建再生成，拷到 `third_party/linux_mainline`，重启 language server |
| 生成时报 `Configuration file ".config" not found!` | `O=` 写了相对路径，被解析到源码树底下；或从没构建过，out 树里连 `.config` 都没有 | `O=$PWD/out/mainline/linux` 用绝对路径；从没构建过的先完整构建一遍 |
| 满屏 `unknown argument` 一类误报 | Remove/Suppress 没配，或 YAML 缩进有误 | 对照仓库根 `.clangd` 逐项核对 |
| 改了 `.clangd` 不生效 | clangd 缓存了旧配置 | 命令面板执行 clangd: Restart language server |
| 把 `CompilationDatabase` 指到 out 树又跑了 `make clean` | clean 删的就是配置指向的那份 json，索引直接失灵 | 重新生成并拷回源码树根 |
| 改配置或换 defconfig 重建后，索引还在悄悄用过期命令行 | 拷贝约定下 `make clean` 只删 out 树里的原件，源码树根那份拷贝安然无恙，但它从不自动更新 | 重新生成并拷回源码树根 |
| 后台索引迟迟跑不完 | 无关大目录都在被扫 | 在 `.clangd` 里配 `If.PathExclude` 加 `Index.Background: Skip`，见本篇第四节 |

## 继续学习

- 上一篇：[03 串口终端](03_serial_terminal.md)，命令行打通了板子，本篇把编辑器的索引补齐
- 下一篇：[05 tasks.json 命令模板](05_tasks_json.md)，索引好了，接着把构建也做成一键
- 深读：调试引擎共存与 launch.json 全文见 [gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md)；从装插件开始的 IDE 全流程见 [driver 卷的 IDE 配置指南](../driver/00_chardev_base/06p_ide_setup.md)
