#!/bin/bash
#
# buildroot_menuconfig.sh - buildroot 配置管理(D2-008)
#
# 打开 buildroot menuconfig 调整配置。修改后可保存回 defconfig(见末尾提示)。
#
# Usage:
#   ./scripts/build_helper/buildroot_menuconfig.sh [OPTIONS]
#
# Options:
#   --defconfig NAME   目标 defconfig 名(默认 imx6ull_aes_defconfig,用于首次初始化)
#   --output-dir PATH  buildroot O= 目录(默认 out/release-latest/buildroot)
#   --savedefconfig    退出后自动 savedefconfig 到 rootfs/buildroot/configs/<defconfig>
#   --help, -h

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/scripts/lib/logging.sh" ]]; then
    source "${PROJECT_ROOT}/scripts/lib/logging.sh"
else
    GREEN='\033[0;32m'; log_info() { echo -e "${GREEN}[buildroot-cfg]${NC} $1"; }
fi

BUILDROOT_DIR="${PROJECT_ROOT}/third_party/buildroot"
BR2_EXTERNAL_DIR="${PROJECT_ROOT}/rootfs/buildroot"
DEFCONFIG="imx6ull_aes_defconfig"
OUTPUT_DIR="${PROJECT_ROOT}/out/release-latest/buildroot"
SAVE_DEFCONFIG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --defconfig) DEFCONFIG="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --savedefconfig) SAVE_DEFCONFIG=1; shift ;;
        --help|-h) sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -f "${BUILDROOT_DIR}/Makefile" ]]; then
    echo "Buildroot submodule not initialized: ${BUILDROOT_DIR}"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
# 首次进入:若无 .config,先应用 defconfig
if [[ ! -f "${OUTPUT_DIR}/.config" ]]; then
    log_info "Initializing .config from ${DEFCONFIG}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" "${DEFCONFIG}"
fi

make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" menuconfig

if [[ ${SAVE_DEFCONFIG} -eq 1 ]]; then
    log_info "Saving minimized defconfig → rootfs/buildroot/configs/${DEFCONFIG}"
    make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" savedefconfig
    cp "${OUTPUT_DIR}/defconfig" "${BR2_EXTERNAL_DIR}/configs/${DEFCONFIG}"
    log_info "Saved."
else
    echo ""
    log_info "如需保存修改回 defconfig,运行:"
    log_info "  ./scripts/build_helper/buildroot_menuconfig.sh --savedefconfig"
    log_info "或手动: make -C third_party/buildroot O=${OUTPUT_DIR} BR2_EXTERNAL=${BR2_EXTERNAL_DIR} savedefconfig"
fi
