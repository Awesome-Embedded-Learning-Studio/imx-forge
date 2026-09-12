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
#
# 说明：脚本会自动进入 third_party/<component> 再打补丁，
# 因此在仓库根目录或子模块目录下执行均可。

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

if [[ ! -d "${PATCH_DIR}" ]]; then
    echo "补丁目录不存在: ${PATCH_DIR}"
    exit 0
fi

# 组件名 → third_party 子目录（与 release.sh 的 _release_submodule_path 保持一致；
# 同时兼容 CI 里使用的 linux_mainline/uboot-imx 写法）
case "$COMPONENT" in
    uboot|uboot-imx)      SRC_DIR="third_party/uboot-imx" ;;
    linux-imx)            SRC_DIR="third_party/linux-imx" ;;
    linux_mainline|linux-mainline) SRC_DIR="third_party/linux_mainline" ;;
    *)                    SRC_DIR="third_party/${COMPONENT}" ;;
esac

echo "========================================"
echo "应用 ${COMPONENT} 补丁"
echo "========================================"
echo "补丁目录: ${PATCH_DIR}"
echo "目标源码: ${SRC_DIR}"
echo ""

# 子模块必须已初始化，否则补丁无处可打
if ! git -C "${PROJECT_ROOT}/${SRC_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "✗ 子模块未初始化: ${SRC_DIR}" >&2
    echo "  先执行: git submodule update --init ${SRC_DIR}" >&2
    exit 1
fi

# 检查是否有补丁文件
shopt -s nullglob
patch_files=("${PATCH_DIR}"/*.patch)
shopt -u nullglob

if [[ ${#patch_files[@]} -eq 0 ]]; then
    echo "没有找到补丁文件: ${PATCH_DIR}/*.patch"
    exit 0
fi

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

    cd "${PROJECT_ROOT}/${SRC_DIR}"
    if git apply --3way "$patch"; then
        echo "  ✓ 成功"
    else
        echo "  ✗ 失败: ${patch_name}" >&2
        echo "" >&2
        echo "补丁没有打上，后续构建会缺 imx_aes_defconfig / imx6ull-aes.dts 这类项目自有文件。" >&2
        echo "常见原因：" >&2
        echo "  a) 子模块不在仓库锁定的 commit 上（patch 基准漂移）；" >&2
        echo "  b) 此前用旧方式打过补丁（文件只在工作区、未进暂存区），--3way 会拒绝重打。" >&2
        echo "  两种情况都按下面步骤清理后重试即可。" >&2
        echo "" >&2
        echo "排查与修复：" >&2
        echo "  1. 查看子模块状态: git submodule status ${SRC_DIR}" >&2
        echo "     （前缀为 '+' 表示偏离了锁定的 commit）" >&2
        echo "  2. 回到锁定 commit: git submodule update ${SRC_DIR}" >&2
        echo "  3. 清掉打了一半的文件后重试:" >&2
        echo "     git -C ${SRC_DIR} checkout -- . && git -C ${SRC_DIR} clean -fdx" >&2
        echo "  4. 重新执行: ./scripts/apply_patches.sh ${COMPONENT}" >&2
        exit 1
    fi
    echo ""
fi

echo "========================================"
echo "补丁应用完成"
echo "========================================"
