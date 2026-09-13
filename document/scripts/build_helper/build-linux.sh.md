# build-linux.sh - 主线 Linux 内核构建脚本（mainline 单轨）

## 脚本概述

`build-linux.sh` 编译上游主线 Linux 内核（`third_party/linux_mainline` 子模块，当前 pin 在 tag `v7.1`），产出 zImage 与板级 dtb。2026-09 起它是项目**唯一**的内核构建脚本（NXP linux-imx vendor 轨已移除），`release-all.sh` 的 Stage 2 在 release 模式下调用的就是它。

## 用法

```bash
./scripts/build_helper/build-linux.sh [--fast-build] [--release] [--release-version V]
```

| 参数 | 作用 |
|------|------|
| `--fast-build` | 跳过 distclean，增量构建 |
| `--release` | 走 release 编排：reset 到超项目 gitlink 锁定的 commit → 应用 `patches/linux_mainline/` 目录内最新的一个补丁 → 建 `release-build-*` 分支 → 写 `build_info.txt`（详见 [lib/release.sh](../lib/release.sh.md)） |
| `--release-version V` | 写入 build_info.txt 的版本号，默认 `unknown` |

## 关键路径与配置

| 项 | 值 |
|----|----|
| 源码树 | `third_party/linux_mainline`（submodule） |
| 输出目录 | `out/linux`（`OUTPUT_DIR` 环境变量可覆盖；release-all 走 `out/release-latest/linux`） |
| defconfig | `imx_aes_mainline_defconfig` —— 由脚本从模板 `driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template` 生成（替换 `${FIRMWARE_DIR}` 变量后写入源码树），release reset 不影响它 |
| 板级补丁 | `patches/linux_mainline/`，按文件名排序取最新一个 |

## 构建流程

1. **主机依赖检查**：gcc/make/bc/bison/flex/dtc/python3 + libssl/libgnutls/libncurses，缺包时给出 `sudo apt install` 提示后退出
2. **工具链检查**：`arm-none-linux-gnueabihf-` 的 gcc/objcopy/objdump/strip
3. **配置**：从模板生成 defconfig → `make O=out/linux imx_aes_mainline_defconfig`
4. **编译**：`make zImage dtbs`（buildmeter 进度条可选，见 [lib/progress.sh](../lib/progress.sh.md)）
5. **外挂驱动准备**：`make modules_prepare`，并把 `Module.symvers` 软链到 `vmlinux.symvers`（Linux ≥ 6.4 只在 `make modules` 时产出后者，外挂 `.ko` 编译需要前者）
6. **产物校验**：vmlinux ELF 架构、zImage、`imx6ull-aes.dtb`、`.config`

另外脚本会克隆 wireless-regdb 到 `out/firmwares/wireless-regdb`，并把 `regulatory.db` 拷进 `driver/firmwares/`（WIFI 法规数据库）。

## 与 CI 的关系

- ci-build 的 `linux` job（standalone）与 ci-full 的 `stage2-linux`（release 模式）都调用本脚本。
- 本地冒烟验证：构建完成后 `scripts/qemu_helper/run-qemu.sh --smoke`——QEMU 直启到登录提示符，与 CI 的 QEMU Boot Smoke 同一条命令。

## 相关文档

- [release-all.sh](../release-all.sh) - 一键编排入口，Stage 2 调用本脚本
- [lib/release.sh](../lib/release.sh.md) - `--release` 模式的编排共享库
- [lib/progress.sh](../lib/progress.sh.md) - buildmeter 进度条
