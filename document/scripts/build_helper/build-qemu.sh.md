# build-qemu.sh - 自建 QEMU(arm-softmmu)构建脚本详解

## 脚本概述

`build-qemu.sh` 把 `third_party/qemu` 子模块(pinned v11.1.0)编译成教学用的 `qemu-system-arm`,产物落在 `out/qemu/build/qemu-system-arm`,由 `run-qemu.sh` 自动优先选用。它是板级模拟「B 档对齐」的基础设施:11.1 相对 Ubuntu 24.04 自带的 8.2.2,给了我们 eLCDIF 显示真模型、树内 FlexCAN 模型、以及 MMDC/OCOTP/QSPI/USBMISC 的 unimplemented 桩(读零软失败)——这些在 8.2 上全是会让内核 external abort 的地址空洞。

### 核心功能

- **单 target 编译**:`--target-list=arm-softmmu` 只编 ARM 系统模拟,16 核机器上分钟级完成(全 target 要 5-10 倍时间)
- **裁剪加速**:`--disable-tools --disable-docs`(不要 qemu-img/Sphinx 文档),CI 友好
- **slirp 用户网络**:`--enable-slirp` 让 meson 走 subproject 自建 libslirp,宿主机不需要 `libslirp-dev`;没有它 `-nic user` 直接报错
- **meson 自举**:QEMU 的 configure 用自带 mkvenv 在 build 目录建 pyvenv 装合适版本 meson(系统 1.3 太老也没关系,需要 `python3-venv`)
- **幂等**:build 目录已配置过则直接增量 ninja,`--reconfigure` 强制重配

### 一次性宿主依赖(需要 sudo)

```bash
sudo apt-get install -y ninja-build flex bison libglib2.0-dev \
    libpixman-1-dev libfdt-dev zlib1g-dev python3-venv
```

`libpixman-1-dev` 不能省:QEMU 11 把 pixman 从 subprojects 移除、变成硬系统依赖,而它正是 eLCDIF framebuffer 渲染的核心库。dtc(libfdt)有 meson wrap 可自动编译,但系统包更省事。

### 在开发工作流中的位置

| 场景 | 命令 |
|------|------|
| 初次搭建 | `scripts/build_helper/build-qemu.sh`(先 `git submodule update --init third_party/qemu`) |
| 日常启动 | `scripts/qemu_helper/run-qemu.sh`(自动检测自编二进制,缺失则回退系统版并告警) |
| CI/换机 | 同初次搭建;CI 里建议走 docker(见 `docker/Dockerfile` 的 qemu builder stage,规划中) |

### 版本说明

pinned **v11.1.0**(2026-08-11 发布)。Bin Meng 的 U-Boot 引导链系列(2026-08)仍在 upstream 评审、未进任何 release——最早随 11.2(约 2026-12)落地,届时升级 pin 并重估 `run-qemu.sh` 的直启说明。升级只需在子模块里 `git fetch --depth 1 origin tag vX.Y.Z && git checkout vX.Y.Z`,主仓提交新 gitlink。
