# build_release_mainline_linux.sh - Linux Mainline 发布构建脚本

## 概述

`build_release_mainline_linux.sh` 用于构建发布布局中的 Linux Mainline 内核。它服务于 `scripts/release-all.sh --mainline --stage 2`，输出目录由 `OUTPUT_DIR` 控制，release-all 默认写入 `out/release-latest/linux`。

这个脚本不会追踪上游 `origin/HEAD`。Mainline 内核源码固定使用 superproject 记录的 `third_party/linux_mainline` gitlink commit；该提交由维护者周期性更新，避免普通 PR 因上游 mainline 变化而破坏构建。

## 使用方法

```bash
./scripts/release_builder/build_release_mainline_linux.sh [--fast-build] [release_version]
```

通常不直接调用，而是通过：

```bash
./scripts/release-all.sh --mainline --stage 2
./scripts/release-all.sh --mainline --stage 2 --fast-build
```

## 参数说明

| 参数 | 说明 | 必需/可选 |
|------|------|-----------|
| `--fast-build` | 传递给 `build-mainline-linux.sh`，跳过输出目录 distclean | 可选 |
| `release_version` | 写入 `build_info.txt` 的发布版本 | 可选 |
| `--help`, `-h` | 显示帮助信息 | 可选 |

## 执行流程

1. 读取 superproject 锁定的 `third_party/linux_mainline` commit。
2. 如果子模块未初始化或本地缺少锁定提交，则执行 `git submodule update --init --depth=1 third_party/linux_mainline`。
3. 清理 `third_party/linux_mainline` 并 checkout 到锁定提交。
4. 创建临时 release 分支。
5. 从 `patches/linux_mainline/*.patch` 中按文件名排序选择最新补丁并应用；补丁冲突会使构建失败。
6. 调用 `scripts/build_helper/build-mainline-linux.sh` 构建 `zImage` 和 DTB。
7. 生成 `build_info.txt`，记录 `Kernel Track: mainline`、锁定提交和补丁信息。

## 依赖关系

### 依赖的脚本

- `scripts/build_helper/build-mainline-linux.sh`

### 依赖的目录

- `third_party/linux_mainline`
- `patches/linux_mainline`

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `OUTPUT_DIR` | 内核构建输出目录 | `out/mainline/linux` |
| `SOURCE_DATE_EPOCH` | 可重现构建时间戳 | `1609459200` |

## 输出产物

- `${OUTPUT_DIR}/arch/arm/boot/zImage`
- `${OUTPUT_DIR}/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb`
- `${OUTPUT_DIR}/vmlinux`
- `${OUTPUT_DIR}/System.map`
- `${OUTPUT_DIR}/build_info.txt`

## 注意事项

- 该脚本会对 `third_party/linux_mainline` 执行 `git reset --hard` 和 `git clean -ffdx`。
- 更新 Mainline 内核版本应通过更新 submodule gitlink commit 完成，而不是修改本脚本去追远程 HEAD。
