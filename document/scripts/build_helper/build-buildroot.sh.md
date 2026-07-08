# build-buildroot.sh - buildroot rootfs 构建入口(D2-007)

## 脚本概述

封装 buildroot 的 `defconfig + make`,产出 i.MX6ULL AES 板的 rootfs 用户空间到 `out/release-latest/rootfs/`。buildroot 只构建 rootfs(Stage 3+4);kernel/uboot 由 build_helper 双轨体系外部提供,镜像由 `build_imx6ull_image.sh` 从 rootfs 目录组装。

### 核心功能

- 应用 `imx6ull_aes_defconfig`(ARM Cortex-A7 / 外部 arm-gnu 15.2 工具链 / busybox / alsa / eudev)
- 可选 merge `fragments/qt6.config`(`--with-qt6`)出 Qt6 全模块 rootfs
- **buildmeter 进度条**:`make` 输出 pipe 给 [buildmeter](https://github.com/Awesome-Embedded-Learning-Studio/buildmeter),显示 `N pkgs done` + 当前包名/阶段 + ninja 子进度(`[N/M]`/`[NN%]`)+ 尾部 finalizing phase + `All Packages: N` 总数(来自 `make show-targets` 预扫描)。详见 [progress.sh](../lib/progress.sh.md)
- `make` 后 rsync `target/` → `out/release-latest/rootfs/`(排除 NFS root 运行时目录)
- buildroot `post-build.sh` 内联补 linuxrc / home / securetty / SDMA 固件 / 字体 + 跑 varified 校验闸门

## 使用方法

```bash
# 默认:最小 rootfs(无 Qt6,~15min)
./scripts/build_helper/build-buildroot.sh

# Qt6 全模块(2-4h;CI 由 compile-support-3rd-party label 触发)
./scripts/build_helper/build-buildroot.sh --with-qt6
# 或:BUILDROOT_QT6=1 ./scripts/build_helper/build-buildroot.sh

# 强制重新 defconfig(不删 output)
./scripts/build_helper/build-buildroot.sh --reconfigure
```

## 参数

| 参数 | 说明 |
|------|------|
| `--with-qt6` | merge `fragments/qt6.config`(Qt6 全模块) |
| `--defconfig NAME` | buildroot defconfig 名(默认 imx6ull_aes_defconfig) |
| `--reconfigure` | 强制重新 defconfig(不删 output) |
| `--clean` | 只删 buildroot output(`rm -rf`)后**退出,不构建**;要构建再跑本脚本(不带 `--clean`) |
| `--source-only` | 仅 `make source` 下载源码到 dl/,不构建 |
| `--output-dir PATH` | buildroot O= 目录(默认 out/release-latest/buildroot) |
| `--release-rootfs PATH` | 最终 rootfs 目录(默认 out/release-latest/rootfs) |

## 环境变量

| 变量 | 说明 |
|------|------|
| `BUILDROOT_QT6=1` | 等效 `--with-qt6`(CI 用) |
| `DEFAULT_BUILDROOT_DEFCONFIG` | 覆盖默认 defconfig 名 |
| `FORGE_PROGRESS_DISABLE=1` | 关掉 buildmeter 进度条,回退裸 make |
| `FORGE_PROGRESS_TAIL` | 进度条下方滑动显示的最近 raw 行数(默认 5) |

## 输出产物

- `out/release-latest/buildroot/target/`(buildroot rootfs)
- `out/release-latest/buildroot/dl/`(源码缓存,可复用)
- `out/release-latest/buildroot/buildmeter-full.log`(完整构建日志,`tee` 落盘;buildmeter 进度条只取尾部窗口,排查看这个)
- `out/release-latest/rootfs/`(rsync 副本,NFS export / 镜像脚本消费)

## 相关

- [`buildroot_menuconfig.sh`](buildroot_menuconfig.sh.md)(D2-008):调整配置
- [`clean_buildroot.sh`](clean_buildroot.sh.md)(D2-009):清理
- `rootfs/buildroot/`:external tree(defconfig / fragments / overlay / post-build.sh)
