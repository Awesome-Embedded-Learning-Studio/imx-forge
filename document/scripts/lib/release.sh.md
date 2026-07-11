# release.sh - release 编排共享库

`scripts/lib/release.sh` 封装 release 构建（`build-*.sh --release` 模式）所需的编排能力，前身是已退役的 `scripts/release_builder/build_release_*.sh`。它的存在让 `release-all.sh` 成为**唯一 release 编排入口**——`build_helper/build-*.sh` 既是分步构建入口，也通过 `--release` 承接 release 编排，两者共用同一份代码。

## 职责

一次 release 编排做 6 件事（编译本身仍由 `build-*.sh` 完成）：

1. 设置可复现构建环境（`SOURCE_DATE_EPOCH` + `LC_ALL=C`）
2. 把子模块源码 reset 到纯净状态
3. 捕获 commit / version / branch 元数据
4. 创建 `release-build-<date>-<sha>` 分支
5. 应用补丁（`git apply`，失败回退 `--3way`）
6. 生成 `${OUTPUT_DIR}/build_info.txt`

## API

调用方（`build-uboot.sh` / `build-linux.sh` / `build-mainline-linux.sh`）在 `--release` 模式下使用两个入口：

```bash
source "${SCRIPT_LIB_DIR}/release.sh"

# 编译前:reset 净源码 → 打 patch → 建 release 分支 → 设 SOURCE_DATE_EPOCH
release_prepare "<component>" "<source-dir>" "<patch-arg>" ["<project-root>"]

# ... build-*.sh 原有的 distclean/configure/build/verify 流程不变 ...

# 编译后:写 build_info.txt
release_finalize "<component>" "<output-dir>" ["<release-version>"]
```

### 组件类型

| component | reset 策略 | SOURCE_DATE_EPOCH | patch 处理 |
|-----------|-----------|-------------------|-----------|
| `uboot` | 跟 `origin` 默认分支（`lf_v2025.04` 回退） | 默认当前时间（banner 匹配构建时间） | 必需：`patches/uboot-imx/charlies_board.patch` |
| `linux-imx` | 跟 `origin` 默认分支（`lf-6.12.y` 回退） | 固定 `1609459200`（2021-01-01） | 可选：`patches/linux-imx/linux-imx-latest.patch` |
| `linux-mainline` | 锁定到超项目 gitlink commit（`git rev-parse HEAD:third_party/linux_mainline`） | 固定 `1609459200` | 取目录最新：`patches/linux_mainline/*.patch` |

`patch-arg` 对 `uboot`/`linux-imx` 是 patch 文件路径，对 `linux-mainline` 是 patch 目录路径。`project-root` 仅 `linux-mainline` 需要（解析 gitlink）。

## build_info.txt

`release_finalize` 写入 `${output-dir}/build_info.txt`。两个 linux 轨**必须**含 `Kernel Track:` 行——`release-all.sh` Stage 2 用 `grep -q "Kernel Track: ${KERNEL_TRACK}"` 校验，mainline 轨缺失会硬退出。

```
========================================
Linux Release Build Information       # U-Boot / Linux / Linux Mainline 三种 header
========================================
Release Version: <version>
...
Linux Information:
-------------------
Kernel Track: imx                    # uboot 无此行;linux-imx=imx;linux-mainline=mainline
Commit: <sha>
...
```

## 设计要点

- **不改变调用方 cwd**：git 操作一律 `git -C "$src"`，避免影响 `build-*.sh` 后续步骤（如 `build-uboot.sh` 的 `logo_helper`、`do_build`）。
- **适配 `set -eo pipefail`**：所有 `$(git ... | sed/wc)` 管道尾部加 `|| true`，避免上游 git 非零退出被 pipefail 放大成整个管道失败而误中止（原 `release_builder` 只有 `set -e` 无此问题）。
- **复用调用方日志**：`log_info`/`log_warn`/`log_error` 来自 `logging.sh`，`log_step` 自带兜底。
- **双重 source 守卫**：重复 source 无副作用。

## 相关

- [release-all.sh](../release-all.sh) - 唯一 release 编排入口，Stage 1/2 经 `--release` 调用本库
- [build-uboot.sh](../build_helper/build-uboot.sh) / [build-linux.sh](../build_helper/build-linux.sh) / [build-mainline-linux.sh](../build_helper/build-mainline-linux.sh) - `--release` 模式的调用方
