---
title: 工作流效率
---

<PageHeader icon="⚙️" title="工作流效率" description="WSL2 开发注意事项、clangd 交叉编译配置、VSCode tasks.json 命令模板" />

## 章节目录

<ChapterNav>
  <ChapterLink num="01" href="01_wsl2_notes">WSL2 开发注意事项</ChapterLink>
  <ChapterLink num="02" href="02_clangd_cross_compile">clangd 交叉编译配置</ChapterLink>
  <ChapterLink num="03" href="03_tasks_json_templates">tasks.json 命令模板</ChapterLink>
</ChapterNav>

::: tip 专栏定位
这一组文章不讲"怎么编译内核/驱动"，讲的是**怎么让日常开发更顺滑**——WSL2 下网络与文件系统的坑怎么避、clangd 怎么配才能在 VSCode 里跳转内核源码、tasks.json 怎么把常用构建脚本一键化。

工具链配好之后，日常效率的瓶颈往往不在编译本身，而在这些环境细节。

PS: 笔者这部分有LLM代劳，可能存在一部分的错误，如有错误欢迎批评指正！
:::

## 为什么需要这一专栏

IMX-Forge 的主力开发环境是 WSL2 + VSCode + Docker。这套组合功能强大，但有几个反复让人踩坑的地方：

- **WSL2 网络**：默认 NAT 模式下开发板看不到 WSL2，TFTP/NFS 启动需要切 Mirrored 模式并处理 Windows 防火墙；
- **文件系统性能**：把源码放在 `/mnt/c/` 下编译会慢 5 倍以上，内核源码甚至有同名大小写文件冲突；
- **代码跳转**：交叉编译的内核/驱动源码，默认 VSCode C/C++ 插件跳转不准，需要 clangd + compile_commands.json；
- **重复命令**：每次构建都手敲一长串脚本路径，容易出错。

本专栏把这四类问题各拆成一篇，给出可复制的配置和踩坑速查。

## 前置知识

- 已完成 [Docker 教程](../docker/) 或已配好交叉编译工具链
- 了解 [out/ 目录结构](../build/01_out_directory_structure.md)
- WSL2 系统入门见 [linux-basics/ch01-wsl2](../linux-basics/01-environment/ch01-wsl2.md)（本专栏不重复入门内容，只讲开发注意事项）

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../build/" variant="sub">← 构建系统</ChapterLink>
  <ChapterLink href="../driver/" variant="sub">驱动开发 →</ChapterLink>
</ChapterNav>
