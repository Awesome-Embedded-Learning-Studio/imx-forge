# progress.sh - buildmeter 进度条接入库

## 脚本概述

`progress.sh` 是 IMX-Forge 项目的共享进度条接入库,为所有构建脚本(build_helper/*)提供统一的实时构建进度条能力。它把 [buildmeter](https://github.com/Awesome-Embedded-Learning-Studio/buildmeter)(AELS org 的构建进度可视化工具)接入到 `make` 流水线里,让漫长的内核 / U-Boot / buildroot 编译不再是"黑盒刷屏",而是带百分比、ETA、当前编译单元 / 包名、滑动日志窗口的实时面板。

本文件**只负责定位 buildmeter**,不接管 pipe —— 调用方自己拼 `make ... | python3 "$FORGE_PROGRESS_PY" <kind>`,以便各自保留 make 参数与退出码处理(配合 `set -o pipefail`,make 失败不被 buildmeter 的 exit-0 吞掉)。

### 核心功能

- **定位 buildmeter**:从 `third_party/buildmeter` submodule 算出 `cli.py` 路径
- **可用性探测**:`forge_progress_enabled` 统一判断(buildmeter 在否 / python3 在否 / 是否被禁)
- **优雅降级**:buildmeter 缺失或被禁时,调用方回退到裸 `make`,构建照常进行
- **可配置滑动窗口**:`FORGE_PROGRESS_TAIL` 控制 bar 下方显示的最近 raw 行数

### 设计理念

构建进度条是"锦上添花",绝不能成为构建的硬依赖。因此这个库的设计重点是**零侵入 + 可降级**:

1. **可选而非必需**:buildmeter 是 git submodule,没克隆 / 没装 python3 / 被显式禁用,三种情况下都安静回退,构建脚本照样能跑
2. **只定位不接管**:pipe 由调用方拼,这样每个构建脚本能保留自己的 make 参数(`-j`、`O=`、target)和退出码语义
3. **不自己算项目根**:复用调用方已经算好的 `PROJECT_ROOT`,避开 `BASH_SOURCE` 在嵌套 source 下的退化坑(见下文)

### 依赖关系

```
progress.sh
    ├─ third_party/buildmeter (git submodule,正式接入)
    │   └─ src/buildmeter/cli.py (入口,由 $FORGE_PROGRESS_PY 指向)
    └─ python3 (运行 cli.py)
```

使用方:

```
├─ build_helper/build-mainline-linux.sh  (kernel profile)
├─ build_helper/build-buildroot.sh        (buildroot profile)
└─ build_helper/build-uboot.sh            (uboot profile)
```

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `FORGE_PROGRESS_PY` | buildmeter `cli.py` 路径 | `${PROJECT_ROOT}/third_party/buildmeter/src/buildmeter/cli.py` |
| `FORGE_PROGRESS_TAIL` | bar 下方滑动显示的最近 raw 行数 | `5` |
| `FORGE_PROGRESS_DISABLE` | `1` = 强制关闭进度条,回退裸 make | `0` |

`PROJECT_ROOT` **不是**本库设的 —— 它由 source 方(build_helper 脚本)在 source 本文件之前算好。所有 build_helper 脚本开头都有:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
```

## 函数详解

### forge_progress_enabled()

**作用**:判断 buildmeter 进度条当前是否可用。

**检查顺序**(任一失败即返回不可用):

1. `FORGE_PROGRESS_DISABLE == 1` → 返回 1(被显式禁用)
2. `$FORGE_PROGRESS_PY` 文件不存在 → 返回 1(buildmeter submodule 未克隆)
3. `python3` 不在 PATH → 返回 1(运行时缺失)

**返回值**:`0` = 可用,`1` = 不可用。

**用法**(调用方典型模式):

```bash
if forge_progress_enabled; then
    make ... 2>&1 | python3 "$FORGE_PROGRESS_PY" kernel --total "$total" --tail "$FORGE_PROGRESS_TAIL"
else
    make ...
fi
```

## 调用方接入模式

### 1. source 本库

```bash
SCRIPT_LIB_DIR="${SCRIPT_DIR}/../lib"
source "${SCRIPT_LIB_DIR}/progress.sh" 2>/dev/null || true
```

`2>/dev/null || true`:progress.sh 不存在时静默跳过(老仓库 / 精简部署也不会挂)。

### 2. 预扫描拿进度分母(可选,仅 clean build)

kernel / uboot 是 kbuild,`make -n -k` dry-run 能枚举出全部编译单元数,作为进度条分母:

```bash
local total=$(${cmd} -n -k 2>/dev/null | python3 "$FORGE_PROGRESS_PY" kernel --count-only || true)
```

`--count-only`:不渲染,只把输入喂给 parser 数单元数,打印总数到 stdout。dry-run 可能非零退出(kbuild 在 vmlinux 链接处断链),`2>/dev/null` 吞报错 + `|| true` 兜退出码。

buildroot **不能**这么干 —— 它的 dry-run 会 halts 早(只 echo 2 个包),所以 buildroot 走 indeterminate 模式,另用 `make show-targets` 数总包数传 `--total`(信息不算 %,只显示 `All Packages: N`)。

### 3. 实时构建 pipe

```bash
if [[ -n "${total}" ]]; then
    ${cmd} 2>&1 | python3 "$FORGE_PROGRESS_PY" kernel --total "${total}" --tail "${FORGE_PROGRESS_TAIL}"
else
    ${cmd} 2>&1 | python3 "$FORGE_PROGRESS_PY" kernel --tail "${FORGE_PROGRESS_TAIL}"
fi
```

有分母 → 显示百分比;无分母(fast-build 增量 / buildroot)→ indeterminate 模式(count + rate + ETA,无 %)。

**务必 `set -o pipefail`**:否则 `make` 失败会被 buildmeter 的 exit-0 掩盖,`set -e` 抓不到失败。

## 三个 Profile

buildmeter 用 profile id 区分不同构建工具的输出格式,cli 第一个位置参数即 kind:

| kind | 解析对象 | 进度单元 | 分母来源 |
|------|----------|----------|----------|
| `kernel` | kbuild `  CC/LD/AR/...` 行 | 编译单元(units) | dry-run 预扫描(准) |
| `uboot` | 同 kernel(kbuild) | 编译单元(units) | dry-run 预扫描(准) |
| `buildroot` | `>>> pkg version stage` 行 + ninja `[N/M]`/`[NN%]` + 尾部 finalizing | 包(pkgs) | `show-targets` 总数(不算 %) |

加新构建工具 = 在 buildmeter 里继承 `BuildParser` + `@register` + 实现 `feed/finalize/done/...`,**核心零改动**。详见 buildmeter 仓库的 `engine.py`。

## 常见坑

### 坑 1:别用 BASH_SOURCE 算项目根

早期版本写过:

```bash
_FORGE_PROGRESS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
```

这在 `bash -c 'source progress.sh'` 或嵌套 source 上下文下会**退化**:`BASH_SOURCE[0]` 变空串,`dirname` 拿到 `.`,最终项目根算成 `/home` 之类的鬼路径 → `cli.py` 找不到 → 进度条静默不亮。

**正确姿势**:不自己算,复用调用方提供的 `PROJECT_ROOT`。`PROJECT_ROOT` 未设 → 路径无效 → `forge_progress_enabled` 返回 false → 回退裸 make,安全。

### 坑 2:pipefail 丢了 make 失败会被吞

```bash
set -eo pipefail   # ← pipefail 必须有
make ... | python3 "$FORGE_PROGRESS_PY" kernel
```

没有 `pipefail`,`make | buildmeter` 这条 pipe 的退出码取**最后一个**(buildmeter,恒 0),`make` 的失败被掩盖,`set -e` 抓不到,构建"假成功"。

### 坑 3:buildroot 的 O= 必须绝对路径

这是 buildroot 本身的坑(非 progress.sh),但接入进度条预扫描时容易踩:`make -C third_party/buildroot O=out/...` 里 `O=` 相对路径会被 make 相对 `-C` 后的 buildroot 目录解析,指向不存在的 `third_party/buildroot/out/...`。改 `O="$(pwd)/out/..."` 绝对路径即可。build-buildroot.sh 用绝对 `OUTPUT_DIR`,无此问题。

## 相关文档

- [build-mainline-linux.sh](../build_helper/build-mainline-linux.sh.md) - kernel profile 调用方
- [build-buildroot.sh](../build_helper/build-buildroot.sh.md) - buildroot profile 调用方
- [build-uboot.sh](../build_helper/build-uboot.sh.md) - uboot profile 调用方
- [logging.sh](./logging.sh.md) - 同级共享库(日志)
- [buildmeter 仓库](https://github.com/Awesome-Embedded-Learning-Studio/buildmeter) - 进度条本体(parser + renderer)
