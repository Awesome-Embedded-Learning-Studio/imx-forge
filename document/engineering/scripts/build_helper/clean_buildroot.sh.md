# clean_buildroot.sh - buildroot 清理(D2-009)

## 脚本概述

清理 buildroot output,分三档(从轻到重)。

## 使用方法

```bash
# make clean:清构建产物,保留 dl/ 与 .config(重新编译但不重新下载)
./scripts/build_helper/clean_buildroot.sh

# 额外删 dl/(下次构建重新下载源码)
./scripts/build_helper/clean_buildroot.sh --dl

# 删整个 buildroot output(含 dl/、.config、构建树;回到 defconfig 前)
./scripts/build_helper/clean_buildroot.sh --all
```

## 参数

| 参数 | 说明 |
|------|------|
| (无) | `make clean`:清构建产物,保留 dl/ + .config |
| `--dl` | 额外删 dl/(源码包缓存) |
| `--all` | 删整个 buildroot output(含 .config) |
| `--output-dir PATH` | buildroot O= 目录(默认 out/release-latest/buildroot) |
| `--help, -h` | 显示帮助 |

## 备注

- 改 defconfig 后 host 包(如 host qt6base)可能因 stamp 缓存不自动重建,需 `make clean`(默认档)强制重编。
- `--all` 会丢 dl/ 下载缓存,下次构建重新下载(慢)。

## 相关

- [`build-buildroot.sh`](build-buildroot.sh.md)(D2-007):构建
- [`buildroot_menuconfig.sh`](buildroot_menuconfig.sh.md)(D2-008):配置
