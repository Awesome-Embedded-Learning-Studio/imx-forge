# IMX-Forge Buildroot External Tree

本目录是 buildroot 的 **br2-external tree**,用于定制 i.MX6ULL AES 板的 rootfs 用户空间。buildroot 源码本身在 `third_party/buildroot/`(submodule,pin 2026.02);本目录的定制文件通过 `BR2_EXTERNAL` 注入,不污染 submodule。

## 设计原则

buildroot **只构建 rootfs(Stage 3+4)**。kernel / U-Boot 由 `scripts/build_helper/` 双轨体系外部构建,产物在 `out/release-latest/{uboot,linux}/`;镜像由 `scripts/image_builder/build_imx6ull_image.sh` 从 `out/release-latest/rootfs/` 组装。buildroot 不设 `BR2_LINUX_KERNEL` / `BR2_TARGET_UBOOT`。

## 目录结构

```
rootfs/buildroot/
├── external.desc              # br2-external 标识(name: imxforge)
├── Config.in                  # external 配置入口(当前为占位)
├── external.mk               # external makefile(当前为空)
├── configs/
│   └── imx6ull_aes_defconfig  # 主 defconfig(external toolchain + busybox + qt6 + alsa + firmware-imx)
├── fragments/
│   ├── busybox.config         # busybox fragment(关 x86-only SHA HWACCEL)
│   └── qt6.config             # (阶段三)Qt6 模块与平台选项
├── overlay/                   # BR2_ROOTFS_OVERLAY 源(替代 merge_overlay_rootfs.sh)
├── post-build.sh              # BR2_ROOTFS_POST_BUILD_SCRIPT(补 linuxrc/rcS + 跑 varified 校验)
└── README.md                  # 本文件
```

## 工具链

复用项目预装的 Arm GNU Toolchain 15.2.rel1(`/opt/arm-gnu-toolchain`,Docker 预装),通过 external preinstalled toolchain 配置:GCC 15 / glibc / kernel headers 6.6。

## 构建命令

```bash
# 一键(封装脚本)
./scripts/build_helper/build-buildroot.sh

# 手动
make -C third_party/buildroot \
    O=$(pwd)/out/release-latest/buildroot \
    BR2_EXTERNAL=$(pwd)/rootfs/buildroot \
    imx6ull_aes_defconfig
make -C third_party/buildroot O=$(pwd)/out/release-latest/buildroot
```

构建产物在 `out/release-latest/buildroot/output/target/`(rootfs 目录树)和 `images/`(ext4)。`build-buildroot.sh` 会把 `target/` 同步到 `out/release-latest/rootfs/` 供镜像打包脚本消费。

## 相关

- 路线图:D4-001(P2)、D2-007/008/009(P1)—— 见 `document/todo/directions/`
- 取代的脚本:`scripts/third_party_install/`、`scripts/build_helper/build-busybox.sh`、`scripts/merge_overlay_rootfs.sh` 等(见分支 commit)
