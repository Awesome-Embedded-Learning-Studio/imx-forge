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
# 临时阶段:buildmeter 在 ~/buildmeter(本地克隆),不进 imx-forge 仓、不 pip。
# 成熟后改 vendor/pip 只动本文件默认路径,调用方零改动。
#
# 环境变量:
#   FORGE_PROGRESS_PY        cli.py 路径(默认 ~/buildmeter/src/buildmeter/cli.py)
#   FORGE_PROGRESS_TAIL      bar 下方滑动显示的最近 raw 行数(默认 5)
#   FORGE_PROGRESS_DISABLE=1 强制关闭(回退裸 make)
# source 后可用:
#   $FORGE_PROGRESS_PY       cli.py 绝对路径(buildmeter 缺失时空串)
#   forge_progress_enabled   返回 0=可用,1=不可用(缺失/被禁)

# 默认:本地克隆位置(临时验证用;可被环境变量覆盖)
: "${FORGE_PROGRESS_PY:=$HOME/buildmeter/src/buildmeter/cli.py}"
: "${FORGE_PROGRESS_TAIL:=5}"   # bar 下方滑动显示的最近 raw 行数(buildmeter --tail)

forge_progress_enabled() {
    [[ "${FORGE_PROGRESS_DISABLE:-0}" == "1" ]] && return 1
    [[ -f "${FORGE_PROGRESS_PY}" ]] || return 1
    command -v python3 &>/dev/null || return 1
    return 0
}
