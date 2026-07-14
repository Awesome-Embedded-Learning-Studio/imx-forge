---
title: clangd 交叉编译配置
---

# clangd 交叉编译配置

> 目标：在 VSCode 里对内核/驱动源码做到**准确跳转、补全、诊断**。默认的 C/C++ 插件在交叉编译场景下跳转不准，本篇配置 clangd + compile_commands.json 解决。

::: info 与已有文档的关系
[driver/00_chardev_base/06p_ide_setup](../driver/00_chardev_base/06p_ide_setup.md) 是一篇完整的 IDE 配置指南。本篇是其**工作流提炼版**，只讲 clangd 这一块的要点和踩坑，详细原理请参考那篇。
:::

## 一、为什么用 clangd 不用 C/C++ 插件

VSCode 默认的 Microsoft C/C++ 插件靠 `includePath` 猜头文件路径，在交叉编译 + 海量内核宏的场景下跳转经常不准。clangd 直接读 `compile_commands.json`——里面记录了**每个 .c 文件编译时的完整命令行**（交叉编译前缀、`-I`、`-D` 宏全在），所以跳转/补全和实际编译一致。

切换步骤：装 `clangd` 扩展，关掉 C/Cpp 的 IntelliSense：

```json
// .vscode/settings.json
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

## 二、compile_commands.json 怎么来

::: warning 不是 bear，也不在构建脚本里
compile_commands.json 由 **Linux 内核构建系统内置**的 `make compile_commands.json` 目标生成，不是 `bear` 工具，也没集成进 `build-mainline-linux.sh`。
:::

### 生成命令

项目用 `O=` 外部构建，输出在 `out/mainline/linux`：

```bash
make -C third_party/linux_mainline \
  ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- \
  O=out/mainline/linux \
  compile_commands.json
```

### 前提：必须先构建过一次内核

内核的 `gen_compile_commands.py` 是扫描构建输出目录里的 `.cmd` 文件（每次 `make zImage dtbs` 时由 fixdep 写入）来汇总的。**没跑过完整内核构建就没有 `.cmd` 文件可扫描**，生成的 json 是空的。

所以正确顺序：

1. 先跑一次 [build-mainline-linux.sh](../../scripts/build_helper/build-mainline-linux.sh.md) 完成内核构建；
2. 再跑上面的 `make compile_commands.json`。

生成后 `compile_commands.json` 出现在 `out/mainline/linux/` 下。

::: tip 内核 clean 会删掉它
`make clean` 会删除 `compile_commands.json`（它是构建产物）。clean 后需重新生成。
:::

## 三、.clangd 配置详解

项目根的 `.clangd` 文件已经配好，三块内容：

```yaml
CompileFlags:
  CompilationDatabase: third_party/linux_mainline
  Remove:
    - -mno-fp-ret-in-387
    - -mpreferred-stack-boundary=*
    # ... 共 13 项
Diagnostics:
  Suppress:
    - drv_unknown_argument
    - invalid-token-paste
    - invalid_token_after_toplevel_declarator
```

### CompilationDatabase 指向哪

`third_party/linux_mainline` 是相对项目根的路径——clangd 会在该目录下找 `compile_commands.json`。

::: warning 路径要对上
如果你生成的 compile_commands.json 在 `out/mainline/linux/`，而 `.clangd` 指向 `third_party/linux_mainline`，需要把 json **拷贝/软链**到 `third_party/linux_mainline/compile_commands.json`，或把 `CompilationDatabase` 改成 `out/mainline/linux`。项目当前约定是放回源码树根。
:::

### Remove 里的 13 个 flag 是什么

这些是 **x86 宿主机特有的 GCC 编译标志**，不是 ARM 的。它们出现在 compile_commands.json 里，是因为内核构建时会编译大量 host-side 工具（`scripts/`、`tools/`、`scripts/dtc/` 等），这些工具用宿主机 x86 gcc 编译，命令行带 x86 专属 flag。clangd 用 clang 解析，clang 不认识这些 GCC x86 flag，会报 `drv_unknown_argument`，所以要在 `Remove` 里剥掉。

逐类：

| flag | 含义 |
|------|------|
| `-mno-fp-ret-in-387` | x87 FPU 返回约定（x86） |
| `-mpreferred-stack-boundary=*` | x86 栈对齐 |
| `-mindirect-branch=*` / `-mindirect-branch-register` / `-mfunction-return=*` | x86 retpoline（Spectre 缓解） |
| `-mrecord-mcount` / `-mskip-rax-setup` / `-mharden-sls=*` | x86 ftrace / 直线推测缓解 |
| `-mno-fdpic` | FDPIC ABI |
| `-fno-allow-store-data-races` / `-fconserve-stack` / `-fno-ipa-sra` / `-fzero-init-padding-bits=all` | GCC 特定优化 |

::: warning 纠正一个常见误读
这些 flag 不是"ARM 特定优化选项"——它们是 x86 宿主编译器 flag，来自内核 host-side 工具的编译命令。剥掉它们不影响 ARM 目标代码的解析。
:::

### Suppress 诊断

即使 Remove 后，clangd 仍可能冒出三个干扰诊断，直接压制：`drv_unknown_argument`、`invalid-token-paste`、`invalid_token_after_toplevel_declarator`。

## 四、常见问题

| 现象 | 解法 |
|------|------|
| clangd 不工作，状态栏无反应 | 确认装了 clangd 扩展、`C_Cpp.intelliSenseEngine: disabled`、`.clangd` 在项目根 |
| 跳转不到内核符号 | compile_commands.json 为空——先构建内核再生成 |
| 满屏 `unknown argument` 报错 | `.clangd` 的 Remove 列表没生效，检查 YAML 缩进 |
| 改了 .clangd 不生效 | clangd 缓存了，`Ctrl+Shift+P` → `clangd: Restart language server` |
| 改了驱动源码跳转还是旧的 | clangd 后台索引延迟，重启 language server |

## 继续学习

- 完整 IDE 配置指南：[driver/00_chardev_base/06p_ide_setup](../driver/00_chardev_base/06p_ide_setup.md)
- 内核构建流程：[kernel/mainline/02_env_setup](../kernel/mainline/02_env_setup.md)
- 上一篇：[WSL2 开发注意事项](01_wsl2_notes.md)
- 下一篇：[tasks.json 命令模板](03_tasks_json_templates.md)
