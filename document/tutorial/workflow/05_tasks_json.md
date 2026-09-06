---
title: VSCode tasks.json：把构建绑到快捷键
---

# VSCode tasks.json：把构建绑到快捷键

> release-all 跑完整链路、单个组件重编、menuconfig 调选项，这些是咱们每天敲得最多的命令，路径一长就打错。本篇用 VSCode 的任务系统接管它们：`Ctrl+Shift+B` 直达默认构建，其余任务在命令面板里点一下就跑。上一篇咱们把代码跳转配置好了，这一篇把构建变成一次按键；产物怎么送到板子上，留给下一篇。

::: tip 前置知识 · 咱们的环境
- 环境基础回 [WSL2 开发注意事项](01_wsl2_env_config.md)；[clangd 交叉编译配置](04_clangd_cross_compile.md) 的 settings.json 与本篇的 tasks.json 同住一个 `.vscode/`，建议您先做完那边再来
- 本篇引用的脚本笔者都在仓库里实测过：`/home/charliechen/imx-forge/scripts/release-all.sh`（572 行）与 `/home/charliechen/imx-forge/scripts/build_helper/` 下的七个构建脚本
- 路径上下文：咱们的操作都在宿主仓库根 `~/imx-forge`（WSL2 Ubuntu）进行，tasks.json 是宿主侧的个人配置文件，不参与任何交叉编译
:::

## 一、把构建脚本绑到快捷键

咱们一天里敲得最熟的几条命令长这样：`./scripts/release-all.sh` 跑完整链路，`./scripts/build_helper/build-mainline-linux.sh` 重编主线内核，`./scripts/build_helper/buildroot_menuconfig.sh` 进菜单调选项。路径越长手滑的概率越高，笔者就不止一次把 `buildroot_menuconfig` 敲成 `buildroot-menuconfig`，然后对着 `command not found` 愣两秒。VSCode 的任务系统就是给这类命令做代理的：命令写进 `tasks.json`，`Ctrl+Shift+B` 触发默认构建任务，其余的在命令面板（`Ctrl+Shift+P` → `Tasks: Run Task`）里按名字选。

这些任务放哪？仓库根下的 `.vscode/` 目录。笔者写本篇时 ls 过仓库根，这个目录当前并不存在，原因在 .gitignore 第 12 行：

```bash
# 主机 ~/imx-forge
grep -n vscode .gitignore
```

```text
12:.vscode/
```

也就是说 `.vscode/` 属于个人配置，git 不追踪、不随仓库分发——换机器得自己重建。笔者把这当作特性：您机器上的任务清单迟早会长出自己的定制条目，混进仓库反而尴尬。新建目录只要一步：

```bash
# 主机 ~/imx-forge
mkdir -p .vscode
```

接着核验模板要用的脚本。build_helper 下就这七个文件，笔者 ls 的原样输出：

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

顶层的 `scripts/` 笔者也一并看过：`release-all.sh`、`apply_patches.sh`、`patch_maker.sh`、`manual_mount_nfs.sh` 都在，另有 `driver_helper`、`qemu_helper`、`image_builder`、`lib`、`server_helper` 等目录。下面模板里的每条 command 都从这份清单里来，没有一条是凭记忆写的路径。

## 二、八个任务模板

下面几段同属一个 tasks 数组，咱们按段贴进同一个 `.vscode/tasks.json`（与上一篇的 settings.json 同目录）。头一段是文件骨架加 release-all 一键全量任务：

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build: release-all (一键全量)",
      "type": "shell",
      "command": "./scripts/release-all.sh",
      "group": { "kind": "build", "isDefault": true },
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": ["$gcc"]
    },
```

release-all 是全量构建的默认任务，`group` 里的 `isDefault: true` 把它标成咱们用 `Ctrl+Shift+B` 直达的那条，按一下就从头跑完整条发布链。接着四条单独重编任务，U-Boot、两棵内核树、Buildroot 各自单独重编：

```json
    {
      "label": "build: U-Boot",
      "type": "shell",
      "command": "./scripts/build_helper/build-uboot.sh",
      "group": "build",
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": ["$gcc"]
    },
    {
      "label": "build: 主线内核 (mainline)",
      "type": "shell",
      "command": "./scripts/build_helper/build-mainline-linux.sh",
      "group": "build",
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": ["$gcc"]
    },
    {
      "label": "build: NXP imx 内核",
      "type": "shell",
      "command": "./scripts/build_helper/build-linux.sh",
      "group": "build",
      "presentation": { "reveal": "always", "panel": "shared" },
      "problemMatcher": ["$gcc"]
    },
    {
      "label": "build: Buildroot rootfs",
      "type": "shell",
      "command": "./scripts/build_helper/build-buildroot.sh",
      "group": "build",
      "presentation": { "reveal": "always", "panel": "shared" }
    },
```

这四条同样进了 build 组、没带 isDefault，咱们从 Run Task 里按名字挑着跑，哪层产物坏了就单独补哪层。menuconfig 与 clean 两条不进 build 组：

```json
    {
      "label": "config: Buildroot menuconfig",
      "type": "shell",
      "command": "./scripts/build_helper/buildroot_menuconfig.sh",
      "presentation": { "reveal": "always", "panel": "dedicated" }
    },
    {
      "label": "clean: Buildroot",
      "type": "shell",
      "command": "./scripts/build_helper/clean_buildroot.sh",
      "presentation": { "reveal": "always", "panel": "shared" }
    },
```

menuconfig 调 rootfs 配置，clean 清理 Buildroot 输出，咱们也从 Run Task 里选。这里有个字段差异值得留神：menuconfig 的 panel 给的是 dedicated，跟其余任务的 shared 不一样，ncurses 全屏界面得独占终端，为什么咱们下一节的字段表里说。最后一条为您的编辑器生成 compile_commands.json，喂给上一篇配好的 clangd：

```json
    {
      "label": "clangd: 生成 compile_commands.json",
      "type": "shell",
      "command": "make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=${workspaceFolder}/out/mainline/linux compile_commands.json",
      "detail": "需先构建过一次内核，见 clangd 配置篇；json 生成后拷回或软链到 third_party/linux_mainline/（.clangd 指向那里）",
      "presentation": { "reveal": "always", "panel": "shared" }
    }
  ]
}
```

这条 make 的 `O=` 咱们特意写成 `${workspaceFolder}`，VSCode 跑任务时会把它替换成工作区根的绝对路径。为什么不用相对路径：内核顶层 Makefile 对 `O=` 的解析发生在 `make -C` 切进源码树之后，写 `out/mainline/linux` 会落到 `third_party/linux_mainline/out/mainline/linux` 里去——仓库里那个空目录就是这个写法踩出来的残留；真产物在仓库根的 `out/mainline/linux`，`build-mainline-linux.sh` 里用的就是绝对路径。生成后咱们还要把 json 拷回或软链成 `third_party/linux_mainline/compile_commands.json`，根目录 `.clangd` 的 CompilationDatabase 指的是那里，这是 04 篇定下的约定。这条命令笔者在本仓库真跑过一遍，`GEN compile_commands.json` 一行输出，9.3MB 的 json 按预期落在 `out/mainline/linux/` 下。

咱们贴完保存，八条齐了。

::: warning 未实测标注
任务涉及的按键与菜单属 GUI 行为，本采集环境按不了键，无法替咱们真按一次 Ctrl+Shift+B；模板本身（JSON 结构与全部脚本路径）已在宿主上逐文件核验存在，make 那条命令笔者真跑核对过；[02 篇](02_vscode_remote_ssh.md)末尾提过配好 tasks.json 之后 Ctrl+Shift+B 一键触发，您若改过键位绑定则按自己的来。
:::

## 三、字段逐个说

表格里这些字段决定任务怎么跑、输出怎么看，咱们逐个过：

| 字段 | 作用 |
|------|------|
| `label` | 任务名，命令面板里按它选 |
| `type: shell` | 当作 shell 命令执行 |
| `group: build` | 归入构建组；`isDefault: true` 的那条是 `Ctrl+Shift+B` 直接执行的默认任务 |
| `presentation.reveal: always` | 始终显示终端输出 |
| `panel: shared` | 多任务共用一个终端面板；`dedicated` 则各开一个 |
| `problemMatcher: ["$gcc"]` | 解析 gcc 报错格式，报错进问题面板 |
| `detail` | 任务条目旁的一句说明，纯给人看 |

`$gcc` 这个内置匹配器认得 `file:line:col: error:` 的输出形态，内核与 U-Boot 的编译报错会被抓进问题面板——咱们点一下就跳到源码行。Buildroot 的输出流里混着大量非 gcc 行，配不配它差别不大，模板里那两条索性没给。咱们给 menuconfig 用 dedicated，是因为 ncurses 全屏界面与普通输出抢同一个终端会互相干扰，独占一个面板各自安好。

release-all.sh 自己的 usage 小节把阶段表写得明明白白，笔者原文摘来（脚本第 80 行起）：

```text
Stages:
  1  U-Boot bootloader
  2  Linux kernel
  3  Rootfs via buildroot (busybox + 用户空间)
  4  RootFS verification gate
  5  SD/eMMC full image creation
```

咱们想只跑到某一阶段，复制一份默认任务、给 command 加 `--stage N` 就行，比如只想重打镜像时：

```json
{
  "label": "build: release-all 仅出镜像 (stage 5)",
  "type": "shell",
  "command": "./scripts/release-all.sh --continue --stage 5",
  "group": "build",
  "presentation": { "reveal": "always", "panel": "shared" },
  "problemMatcher": []
}
```

usage 给出的示例里 `--stage 5` 单独跑也行（只出默认 eMMC 镜像），`--continue` 则明确跳过已完成的阶段、从现有的 release-latest 接着干，还配了 `--boot-media sd`/`both` 控制介质。这些参数组合您照自己的节奏挑，绑成几条任务都行。

## 四、可扩展的脚本清单

仓库里还有一批脚本值得进咱们的任务清单，路径笔者都逐个核验过：

| 脚本 | 用途 |
|------|------|
| `./scripts/apply_patches.sh` | 应用组件补丁 |
| `./scripts/patch_maker.sh` | 从源码树改动生成补丁 |
| `./scripts/manual_mount_nfs.sh` | 手动挂载 NFS rootfs |
| `./scripts/driver_helper/build_driver.sh` | 外挂驱动构建（同目录还有 deploy、review、show_device_tree、template_creator 与两份 driver_helper.conf 配置） |
| `./scripts/build_helper/build-qemu.sh` 与 `./scripts/qemu_helper/run-qemu.sh` | 自建 QEMU 模拟器（arm-softmmu）与板级模拟启动 |
| `./scripts/qemu_helper/make-rootfs-img.sh` | QEMU rootfs 镜像制作 |

driver_helper 目录笔者 ls 过，除 build_driver.sh 外还有 deploy_driver.sh、review_driver.sh、show_device_tree.sh、template_creator.sh、driver_helper.conf（和它的 .template 模板）与一份 README.md。加任务的套路就是照葫芦画瓢：复制任一条现有任务，改 label 与 command，再决定要不要进 build 组。进不进 build 组，决定任务挂不挂到 `Ctrl+Shift+B` 上：isDefault 那条被它直接执行，组里其余任务仍从 Run Task 里选，您掂量着放。

## 五、加一个调试任务：板端起 gdbserver

调试卷的 [gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md) 把整条链路讲完了：rootfs 里装上 gdbserver、宿主交叉 gdb 连上去、launch.json 接管。那一篇里起服务的一步是在板端敲 `gdbserver :2345 /root/demo`，如果您天天调同一个程序，这一步也能固化成任务：

```json
{
  "label": "debug: 板端起 gdbserver",
  "type": "shell",
  "command": "ssh root@192.168.60.200 'gdbserver :2345 /root/demo'",
  "detail": "IP 与程序路径按您板子实际情况改（本系列文档记录的板子地址是 192.168.60.200，见 rootfs/05）；rootfs 需带 dropbear 与 gdbserver",
  "presentation": { "reveal": "always", "panel": "dedicated" },
  "problemMatcher": []
}
```

它没进 build 组，只能从 Run Task 手动触发，免得咱们手滑把一个长会话挂进构建快捷键。panel 用 dedicated，是因为这个任务连上之后会一直占着终端，混进构建输出两边都搅乱。problemMatcher 留空，gdbserver 的输出不是编译日志，没有可解析的报错格式。宿主侧的连接（launch.json 或命令行 gdb）不在任务里做，那是调试卷的主场，这里只固化板端这一步。QEMU 场景下 gdbserver 得在客户机串口控制台里起，起的命令换成 `gdbserver :12345 /root/demo`，宿主侧连接地址换成 localhost:12345——端口与连接细节见调试篇的实测记录。也正因为两端端口都变，这条 ssh 任务主要服务于实际的板子。

还有个生命周期机制要提醒您：任务终端被关掉时，ssh 会话断开，远端前台跑的 gdbserver 也跟着退——这多半正是咱们想要的清理效果。想更明确地控制的话，gdbserver 有 `--once`（一个会话结束自动退出），要常驻就交给 nohup。

::: warning 未实测标注
ssh 到板端这一变体在本环境没法真跑（笔者手边没有上电的 i.MX6ULL）；命令形态与调试篇的实测链路一致，QEMU 场景的端口与连接地址也见调试篇的实测记录；IP、账号与程序路径以您板子的实参为准。
:::

## 踩坑速查表

| 现象 | 根因 | 解法 |
|------|------|------|
| 按 Ctrl+Shift+B 没任务可跑，弹出 tasks.json 解析错误或任务列表为空 | JSON 语法错误，常见末尾逗号 | 按严格 JSON 排查，保存后任务列表即刷新 |
| 构建输出被顶掉，回头找不到报错行 | panel: shared 让新任务复用同一终端 | 高频任务改 dedicated，或用终端自带查找 |
| 两个任务同 label，后加的不出现 | label 是唯一标识，重名互相覆盖 | label 里带上组件名区分 |
| 任务跑一半想中断 | 全量构建耗时长，等它自己结束不现实 | 终端面板右上角终止任务或直接删终端，增量重跑接着来 |
| 跑 clangd 生成任务报 `Configuration file ".config" not found` | `O=` 指的输出目录里没构建过内核，没有 .config 可读 | 先跑一次主线内核构建，详见上一篇 |
| stage 5 单独跑失败 | release-latest 里缺前面阶段的产物，镜像没有输入 | 先完整跑一遍全链路，或按 usage 用 --continue 接续 |

## 继续学习

- 上一篇：[clangd 交叉编译配置](04_clangd_cross_compile.md)，settings.json 与本篇 tasks.json 同住 `.vscode/`
- 下一篇：[主机与板子传文件：scp、rsync 与 NFS root 的三种选法](06_host_board_transfer.md)，构建一键化之后，产物怎么送到板子上
- 深读：[gdbserver 远程调试全链](../debug/01_gdbserver_remote_debug.md)，本篇第五节那个调试任务的另一半链路在那里