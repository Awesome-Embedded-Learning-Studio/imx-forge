#!/bin/bash
#
# clean_buildroot.sh - buildroot 清理(D2-009)
#
# Usage:
#   ./scripts/build_helper/clean_buildroot.sh [OPTIONS]
#
# Options:
#   (无)      make clean —— 清构建产物,保留 dl/ 与 .config
#   --dl       额外删除 dl/(源码包缓存,下次构建重新下载)
#   --all      删除整个 buildroot output(含 dl/、.config、构建树)
#   --output-dir PATH  buildroot O= 目录(默认 out/release-latest/buildroot)
#   --help, -h

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/scripts/lib/logging.sh" ]]; then
    source "${PROJECT_ROOT}/scripts/lib/logging.sh"
else
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
    log_info() { echo -e "${GREEN}[buildroot-clean]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[buildroot-clean]${NC} $1"; }
fi

BUILDROOT_DIR="${PROJECT_ROOT}/third_party/buildroot"
OUTPUT_DIR="${PROJECT_ROOT}/out/release-latest/buildroot"
MODE="clean"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dl) MODE="dl" ; shift ;;
        --all) MODE="all" ; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --help|-h) sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -d "${OUTPUT_DIR}" ]]; then
    log_info "Nothing to clean: ${OUTPUT_DIR} 不存在"
    exit 0
fi

case "${MODE}" in
    clean)
        log_info "make clean(保留 dl/ 与 .config)"
        make -C "${BUILDROOT_DIR}" O="${OUTPUT_DIR}" clean
        ;;
    dl)
        log_info "Removing dl/(源码包缓存)"
        rm -rf "${OUTPUT_DIR}/dl"
        ;;
    all)
        log_warn "Removing entire buildroot output: ${OUTPUT_DIR}"
        rm -rf "${OUTPUT_DIR}"
        ;;
esac
log_info "Done"
