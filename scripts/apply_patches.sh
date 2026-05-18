#!/bin/bash
#
# 自动应用补丁脚本
# 用于CI环境中自动应用 patches/ 目录下的补丁。
#
# 当前策略：按文件名排序，仅应用最新的 .patch 文件。
# 说明：架构文档中提到的 series 机制是后续增强方向；本脚本暂不实现
# series 顺序应用，以避免改变现有 CI 和构建行为。
#
# 用法：
#   ./scripts/apply_patches.sh <component>
#
# 示例：
#   ./scripts/apply_patches.sh linux_mainline
#   ./scripts/apply_patches.sh uboot-imx

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMPONENT="$1"

if [[ -z "$COMPONENT" ]]; then
    echo "用法: $0 <component>"
    echo "示例: $0 linux_mainline"
    exit 1
fi

PATCH_DIR="${PROJECT_ROOT}/patches/${COMPONENT}"

if [[ ! -d "$PATCH_DIR" ]]; then
    echo "补丁目录不存在: $PATCH_DIR"
    exit 0
fi

# 检查是否有补丁文件
shopt -s nullglob
patch_files=("${PATCH_DIR}"/*.patch)
shopt -u nullglob

if [[ ${#patch_files[@]} -eq 0 ]]; then
    echo "没有找到补丁文件: ${PATCH_DIR}/*.patch"
    exit 0
fi

echo "========================================"
echo "应用 ${COMPONENT} 补丁"
echo "========================================"
echo "补丁目录: ${PATCH_DIR}"
echo "补丁数量: ${#patch_files[@]}"
echo ""

# 按文件名排序，只应用最后一个补丁文件
IFS=$'\n' patch_files=($(sort <<<"${patch_files[*]}"))
unset IFS

if [[ ${#patch_files[@]} -gt 0 ]]; then
    # 取最后一个补丁
    patch="${patch_files[${#patch_files[@]}-1]}"
    patch_name=$(basename "$patch")
    echo "应用: ${patch_name} (共 ${#patch_files[@]} 个补丁，仅应用最新)"

    if git apply --3way "$patch"; then
        echo "  ✓ 成功"
    else
        echo "  ⚠ 失败 (跳过)"
        # 不再尝试 --reject，直接跳过避免文件损坏
    fi
    echo ""
fi

echo "========================================"
echo "补丁应用完成"
echo "========================================"
