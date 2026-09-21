---
layout: home
title: "IMX-Forge · 面向 i.MX6ULL 的嵌入式 Linux 开发工坊"
description: "从工具链、U-Boot、主线内核、根文件系统到驱动实战的 i.MX6ULL 嵌入式 Linux 完整学习路径"

hero:
  kicker: "i.MX6ULL · 嵌入式 Linux 全栈教程"
  name: "IMX-Forge"
  text: "锻造你的嵌入式功底"
  tagline: 面向 NXP i.MX6ULL，从工具链、U-Boot、内核、根文件系统到驱动实战的完整学习路径 —— 把每一层都拆开看清楚。
  actions:
    - theme: brand
      text: 快速开始
      link: /QUICK_START
    - theme: alt
      text: 教程目录
      link: /tutorial/
    - theme: alt
      text: GitHub
      link: https://github.com/Awesome-Embedded-Learning-Studio/imx-forge
    - theme: alt
      text: QQ 交流群
      link: https://qm.qq.com/q/tEsFhL8eB2

features:
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/></svg>'
    title: 零基础？从 Linux 基础开始
    details: 35 章 Ubuntu 实用教程，从命令行到交叉编译，专为嵌入式开发预备营打造，无缝衔接本教程
    link: /tutorial/linux-basics/
    linkText: 开始阅读
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" x2="12" y1="22.08" y2="12"/></svg>'
    title: 开箱即用的开发环境
    details: 预装 ARM GNU Toolchain 15.2，Docker 一键部署，WSL2 深度友好
    link: /tutorial/docker/
    linkText: 环境搭建
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5"/><path d="M2 12l10 5 10-5"/></svg>'
    title: 主线内核路线
    details: 统一收敛到上游主线 Linux（当前 v7.1，真板实测启动）；NXP imx 内核轨已退役，只留参考引用
    link: /tutorial/kernel/
    linkText: 内核卷
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="3 11 22 2 13 21 11 13 3 11"/></svg>'
    title: 完整学习路径
    details: 持续增长的文档覆盖工具链、U-Boot、内核、Rootfs、驱动开发全流程
    link: /tutorial/
    linkText: 查看目录
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M15 2v2"/><path d="M15 20v2"/><path d="M2 15h2"/><path d="M2 9h2"/><path d="M20 15h2"/><path d="M20 9h2"/><path d="M9 2v2"/><path d="M9 20v2"/></svg>'
    title: 系统驱动教程
    details: 从字符设备到 pinctrl/gpio 子系统，从硬件原理到驱动实战
    link: /tutorial/driver/
    linkText: 驱动卷
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>'
    title: 完整构建系统
    details: Bash + Make 自动化构建，CI/CD 验证，一键发布
    link: /architecture/
    linkText: 架构总览
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z"/><path d="m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z"/><path d="M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0"/><path d="M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5"/></svg>'
    title: 实战演练
    details: 完整系统构建与调试，从零到一的嵌入式项目实战
    link: /tutorial/practical/
    linkText: 实战卷
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>'
    title: 常见问题
    details: 收录 Issue 答疑记录，快速解决常见问题
    link: /qa/
    linkText: 翻翻答案
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>'
    title: 参与贡献
    details: 补丁命名规范、Issue/PR 引导、教程写作指南，欢迎一起完善项目
    link: /team/
    linkText: 一起搞
---
