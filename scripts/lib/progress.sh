#!/bin/bash
#
# progress.sh — buildmeter 进度条接入(给 build_helper 构建脚本用)
#
# buildmeter(AELS org,github.com/Awesome-Embedded-Learning-Studio/buildmeter)
# 解析 make stdout 画实时进度条:kernel kbuild 数 CC/LD/AR/AS,buildroot 数 >>> pkg。
#
# 本文件只负责"定位 buildmeter"——不接管 pipe。调用方自己拼
#   make ... 2>&1 | python3 "$FORGE_PROGRESS_PY" <kind> [--total N]
# 以便各自保留 make 参数 + 退出码处理(配合 set -o pipefail,make 失败不被吞)。
#
# buildmeter 是 third_party/buildmeter submodule(正式接入,非临时克隆)。默认路径从
# 本文件(scripts/lib)位置算项目根,不依赖调用方是否设了 PROJECT_ROOT。
#
# 环境变量:
#   FORGE_PROGRESS_PY        cli.py 路径(默认 ${PROJECT_ROOT}/third_party/buildmeter/src/buildmeter/cli.py)
#   FORGE_PROGRESS_TAIL      bar 下方滑动显示的最近 raw 行数(默认 5)
#   FORGE_PROGRESS_DISABLE=1 强制关闭(回退裸 make)
# source 后可用:
#   $FORGE_PROGRESS_PY       cli.py 绝对路径(buildmeter 缺失时空串)
#   forge_progress_enabled   返回 0=可用,1=不可用(缺失/被禁)

# 默认:third_party/buildmeter submodule。PROJECT_ROOT 由 source 方(build_helper
# 脚本)提供 —— 它们都在 source 本文件前用 SCRIPT_DIR 算好 PROJECT_ROOT。不自己用
# BASH_SOURCE 算:在 bash -c / 嵌套 source 下 BASH_SOURCE[0] 会退化成空串,dirname
# 拿到 "."。PROJECT_ROOT 未设 → 路径无效 → forge_progress_enabled 返回 false → 回退裸 make。
: "${FORGE_PROGRESS_PY:=${PROJECT_ROOT}/third_party/buildmeter/src/buildmeter/cli.py}"
: "${FORGE_PROGRESS_TAIL:=5}"   # bar 下方滑动显示的最近 raw 行数(buildmeter --tail)

forge_progress_enabled() {
    [[ "${FORGE_PROGRESS_DISABLE:-0}" == "1" ]] && return 1
    [[ -f "${FORGE_PROGRESS_PY}" ]] || return 1
    command -v python3 &>/dev/null || return 1
    return 0
}
