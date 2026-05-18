---
layout: home

hero:
  name: "IMX-Forge"
  text: "嵌入式 Linux 开发工坊"
  tagline: 面向 NXP i.MX6ULL，从工具链到 QT 应用的完整学习路径
  image:
    src: /Awesome-Embedded.png
    alt: IMX-Forge Logo
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

features:
  - icon: 🐳
    title: 开箱即用的开发环境
    details: 预装 ARM GNU Toolchain 15.2，Docker 一键部署，WSL2 深度友好
    link: /tutorial/docker/
  - icon: 🔧
    title: 双轨内核策略
    details: NXP BSP (6.12.3) 稳定可靠 + Mainline (7.0rc) 紧跟上游
    link: /tutorial/kernel/
  - icon: 📚
    title: 完整学习路径
    details: 持续增长的文档覆盖工具链、U-Boot、内核、Rootfs、驱动开发全流程
    link: /tutorial/
  - icon: 🔥
    title: 系统驱动教程
    details: 从字符设备到 pinctrl/gpio 子系统，从硬件原理到驱动实战
    link: /tutorial/driver/
  - icon: 🏗️
    title: 完整构建系统
    details: Bash + Make 自动化构建，CI/CD 验证，一键发布
    link: /architecture/
  - icon: 🚀
    title: 实战演练
    details: 完整系统构建与调试，从零到一的嵌入式项目实战
    link: /tutorial/practical/
---
