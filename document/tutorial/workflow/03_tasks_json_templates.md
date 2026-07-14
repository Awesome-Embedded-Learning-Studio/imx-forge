---
title: tasks.json 命令模板
---

# tasks.json 命令模板

> 目标：把常用的构建脚本变成 VSCode 里 `Ctrl+Shift+B` 一键调用的任务，不用每次手敲长路径。

## 一、为什么用 tasks.json

IMX-Forge 的构建脚本分散在 `scripts/` 和 `scripts/build_helper/` 下，命令偏长：

```bash
./scripts/build_helper/build-mainline-linux.sh --release
./scripts/release-all.sh --stage 3
```

手敲容易打错路径和参数。VSCode 的 `tasks.json` 能把这些命令固化成任务，配合快捷键和问题匹配器（problemMatcher），还能把编译告警/错误直接链回源码行。

## 二、建立 .vscode/ 目录

仓库当前**没有** `.vscode/` 目录（已被 .gitignore 忽略，属个人配置）。新建：

```bash
mkdir -p .vscode
```

放两个文件：

- `settings.json`——clangd 配置（见 [上一篇](02_clangd_cross_compile.md)）
- `tasks.json`——本篇的构建任务

`settings.json`：

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
  ],
  "files.associations": { "*.c": "c", "*.h": "c" }
}
```

## 三、tasks.json 模板

下面这份模板覆盖了日常最常用的几类任务。复制进 `.vscode/tasks.json`：

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
    {
      "label": "clangd: 生成 compile_commands.json",
      "type": "shell",
      "command": "make -C third_party/linux_mainline ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/mainline/linux compile_commands.json",
      "detail": "需先构建过一次内核，见 clangd 配置篇",
      "presentation": { "reveal": "always", "panel": "shared" }
    }
  ]
}
```

### 字段说明

| 字段 | 作用 |
|------|------|
| `label` | 任务名，`Ctrl+Shift+B` 或命令面板里显示 |
| `type: shell` | 当作 shell 命令执行 |
| `group: build` | 归入"构建"组；`isDefault: true` 的那个是 `Ctrl+Shift+B` 直接跑的默认任务 |
| `presentation.reveal: always` | 始终显示终端输出 |
| `panel: shared` | 多任务共用一个终端面板；`dedicated` 则各开一个 |
| `problemMatcher: ["$gcc"]` | 解析 gcc 报错格式，点击错误可跳到源码行 |

## 四、用法

- **`Ctrl+Shift+B`**：跑默认任务（release-all）
- **`Ctrl+Shift+P` → `Tasks: Run Task`**：选任意一个任务
- 编译报错时，终端输出的 `file:line:col: error:` 会被 problemMatcher 抓住，点击即可跳转

::: tip release-all 的分阶段
`release-all.sh` 支持 `--stage N` 只跑到某一阶段（U-Boot→内核→rootfs→验证→镜像）。要单独跑某阶段，复制一个任务把 `command` 改成 `./scripts/release-all.sh --stage 2` 即可。参数详见 [release-all 脚本说明](../../scripts/release-all.sh.md)。
:::

::: warning compile_commands 任务的前提
"生成 compile_commands.json" 任务要求**先跑过一次主线内核构建**（否则 `.cmd` 文件不存在，json 为空）。详见 [clangd 配置篇](02_clangd_cross_compile.md)。
:::

## 五、按需扩展

仓库里还有这些脚本可以加成任务：

| 脚本 | 用途 |
|------|------|
| `./scripts/apply_patches.sh` | 应用补丁 |
| `./scripts/patch_maker.sh` | 生成补丁 |
| `./scripts/manual_mount_nfs.sh` | 手动挂载 NFS rootfs |
| `./scripts/driver_helper/` | 驱动构建辅助（`make modules_prepare` 等） |

加法：在 `tasks` 数组里照上面的格式补一段即可。

## 继续学习

- 构建系统全貌：[build/ 构建系统专栏](../build/)
- 各脚本说明：[scripts/ 文档](../../scripts/)
- 上一篇：[clangd 交叉编译配置](02_clangd_cross_compile.md)
