# buildroot_menuconfig.sh - buildroot 配置管理(D2-008)

## 脚本概述

打开 buildroot `menuconfig` 交互调整 rootfs 配置。修改后可选保存回 defconfig(`--savedefconfig`)。

## 使用方法

```bash
# 打开 menuconfig(基于 imx6ull_aes_defconfig)
./scripts/build_helper/buildroot_menuconfig.sh

# 退出后自动 savedefconfig 回 rootfs/buildroot/configs/
./scripts/build_helper/buildroot_menuconfig.sh --savedefconfig
```

## 参数

| 参数 | 说明 |
|------|------|
| `--defconfig NAME` | 目标 defconfig(默认 imx6ull_aes_defconfig,首次初始化用) |
| `--output-dir PATH` | buildroot O= 目录(默认 out/release-latest/buildroot) |
| `--savedefconfig` | 退出后 savedefconfig 到 `rootfs/buildroot/configs/<defconfig>` |
| `--help, -h` | 显示帮助 |

## 备注

- Qt6 等可选模块在 `fragments/qt6.config`(不在主 defconfig);menuconfig 改的是主 defconfig + .config 运行时配置。
- savedefconfig 生成的是 minimal defconfig(只含非默认项)。

## 相关

- [`build-buildroot.sh`](build-buildroot.sh.md)(D2-007):构建
- [`clean_buildroot.sh`](clean_buildroot.sh.md)(D2-009):清理
