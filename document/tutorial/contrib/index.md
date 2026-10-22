---
title: 来稿
---

<PageHeader icon="📮" title="来稿" description="读者与朋友投稿的完整教程——保留作者本人的讲述风格，由维护组做技术校订后收录" />

## 本卷目录

<ChapterNav>
  <ChapterLink num="01" href="01-wsl2-environment">想要真 Linux——WSL2 加 VS Code 环境搭建</ChapterLink>
  <ChapterLink num="02" href="02-wsl2-usbipd">WSL（Ubuntu）连接 Windows 的 USB 设备</ChapterLink>
</ChapterNav>

::: tip 这一卷是什么
来稿卷收录社区朋友的投稿。与主线各卷由维护组按统一大纲撰写不同，这里的文章完整保留作者自己的讲述顺序和语言风格，维护组只做三类事：技术内容校订、站内链接与图片路径适配、元数据整理。作者授权了收录后的修改，署名随文保留。
:::

## 本卷与工作流卷的关系

本卷两篇与 [开发环境配置](../workflow/) 卷题材相邻，但定位不同，可以互相补充着看：

- 工作流卷是维护组的"官方版"：按本仓库的开发台形态（WSL2 + VSCode + 串口终端 + 交叉工具链）切成了网络、编辑器、串口、索引、构建、传文件六个专题，边界划分得很细。
- 来稿这两篇是作者独立视角的"一条龙版"：从 Windows 11 一路装到 VS Code 接入、再到 usbipd 直通 USB 设备，每一步都配了实操截图，适合喜欢跟着图一步步点的朋友。

usbipd（USB 设备直通）部分，主线各卷讲到时都会指向本卷 02 篇的截图版完整流程。

## 投稿方式

想投稿？开一个 [GitHub Issue](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues) 先聊聊题材，稿件收到后维护组会与您确认收录与修改授权，署名与原文风格都会保留。

## 继续学习

<ChapterNav variant="sub">
  <ChapterLink href="../workflow/" variant="sub">← 开发环境配置</ChapterLink>
  <ChapterLink href="../third_party/" variant="sub">第三方 →</ChapterLink>
</ChapterNav>
