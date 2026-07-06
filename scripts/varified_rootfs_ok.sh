#!/bin/bash
#
# varified_rootfs_ok.sh - RootFS 校验闸门
#
# 历史职责:既"构造"rootfs(建目录骨架、写 fstab/rcS/inittab、跑第三方安装),又"校验"。
# buildroot 接管后,构造由 buildroot(skeleton + packages + overlay + post-build)负责,
# 本脚本只保留【校验】职责,作为 buildroot post-build 与 release-all 的闸门。
# 任一致命检查不过则非零退出(issue #76 教训:绝不让残缺 rootfs 流到镜像)。
#
# Usage:
#   scripts/varified_rootfs_ok.sh --rootfs-dir=out/release-latest/rootfs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_debug() { if [[ "${DEBUG:-0}" == "1" ]]; then echo -e "${BLUE}[DEBUG]${NC} $1"; fi; }
fi

ROOTFS_DIR=""
SHOW_HELP=0
REQUIRED_DIRS=("bin" "sbin" "usr")
ROOTFS_DIRS=("bin" "dev" "etc" "lib" "mnt" "proc" "root" "sbin" "sys" "tmp" "usr" "home")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) SHOW_HELP=1 ;;
        --rootfs-dir=*) ROOTFS_DIR="${1#*=}" ;;
        --rootfs-dir) shift; ROOTFS_DIR="$1" ;;
        *) log_error "Unknown option: $1"; SHOW_HELP=1 ;;
    esac
    shift
done

: "${ROOTFS_DIR:=${PROJECT_ROOT}/out/release-latest/rootfs}"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --rootfs-dir=PATH    Path to rootfs directory(默认 out/release-latest/rootfs）
  --help, -h           Show this help message

Description:
  校验 rootfs 完整性(目录结构 + 关键配置 + 可选 Qt 产物),作为构建闸门。
  构造职责已移交 buildroot,本脚本只做校验。
EOF
}

check_directory_safe() {
    local dir="$1"
    if [[ "$dir" == "/" ]]; then
        log_error "Rootfs directory cannot be '/'"
        return 1
    fi
    local abs_dir
    abs_dir="$(cd "$dir" 2>/dev/null && pwd)" || {
        log_error "Cannot access directory: $dir"
        log_error "rootfs 未生成或路径不可达;先跑 build-buildroot.sh / release-all.sh"
        return 1
    }
    if [[ "$abs_dir" == "/" ]]; then
        log_error "Rootfs directory resolves to '/' (unsafe)"
        return 1
    fi
    log_debug "Directory safety check passed: $abs_dir"
    return 0
}

check_required_dirs() {
    local rootfs="$1"
    local missing=()
    local found=()
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [[ -d "${rootfs}/${dir}" ]]; then
            found+=("$dir")
        else
            missing+=("$dir")
        fi
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        log_info "Found required directories: ${found[*]}"
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required directories: ${missing[*]}"
        log_error "Please ensure your rootfs has at least: bin, sbin, usr"
        return 1
    fi
    return 0
}

verify_rootfs() {
    local rootfs="$1"
    log_info "Verifying rootfs completion..."
    local all_ok=1
    for dir in "${ROOTFS_DIRS[@]}"; do
        if [[ -d "${rootfs}/${dir}" ]]; then
            log_debug "  ✓ ${dir}/ exists"
        else
            log_error "  ✗ ${dir}/ missing"
            all_ok=0
        fi
    done
    if [[ -e "${rootfs}/linuxrc" ]]; then
        log_debug "  ✓ linuxrc exists"
    else
        log_warn "  ! linuxrc missing (非致命;现代内核用 /sbin/init)"
    fi
    local config_files=("etc/fstab" "etc/init.d/rcS" "etc/inittab")
    for file in "${config_files[@]}"; do
        if [[ -f "${rootfs}/${file}" ]]; then
            log_debug "  ✓ ${file} exists"
        else
            log_error "  ✗ ${file} missing"
            all_ok=0
        fi
    done
    if [[ $all_ok -eq 1 ]]; then
        log_info "Rootfs verification passed"
        return 0
    else
        log_error "Rootfs verification failed"
        return 1
    fi
}

# Qt 产物校验:仅当 rootfs 实际包含 Qt(阶段一无 Qt 时自动跳过,不致命)。
# 致命集:libQt6Core.so*(Qt6 核心)+ plugins/platforms/ 非空(linuxfb 插件)。
# 软警告:qmake(host 工具,裁剪部署可能省略)。
verify_qt_artifacts() {
    local rootfs="$1"
    log_info "Verifying Qt artifacts..."
    local all_ok=1

    local qt_core_hit
    qt_core_hit=$(compgen -G "${rootfs}/usr/lib/libQt6Core.so*" 2>/dev/null | head -1)
    if [[ -n "$qt_core_hit" ]]; then
        log_debug "  ✓ libQt6Core.so found"
    else
        log_error "  ✗ libQt6Core.so* missing under ${rootfs}/usr/lib/"
        all_ok=0
    fi

    local platforms_dir="${rootfs}/usr/lib/qt6/plugins/platforms"
    if [[ -d "$platforms_dir" ]] && [[ -n "$(ls -A "$platforms_dir" 2>/dev/null)" ]]; then
        log_debug "  ✓ Qt platform plugins present"
    else
        log_error "  ✗ Qt platform plugins missing or empty: ${platforms_dir}"
        all_ok=0
    fi

    if [[ -f "${rootfs}/usr/bin/qmake" ]] || [[ -f "${rootfs}/usr/bin/qmake6" ]]; then
        log_debug "  ✓ qmake found"
    else
        log_warn "  ! qmake not found (host tool, may be stripped)"
    fi

    if [[ $all_ok -eq 1 ]]; then
        log_info "Qt artifact verification passed"
        return 0
    else
        log_error "Qt artifact verification failed"
        return 1
    fi
}

main() {
    if [ ${SHOW_HELP} -eq 1 ]; then
        show_usage
        exit 0
    fi

    log_info "========================================"
    log_info "RootFS Verification (gate)"
    log_info "========================================"
    log_info "Rootfs directory: ${ROOTFS_DIR}"
    echo ""

    log_info "Step 1: Safety checks..."
    check_directory_safe "$ROOTFS_DIR" || exit 1
    log_info "  ✓ Directory is safe"
    echo ""

    log_info "Step 2: Verifying required directories..."
    check_required_dirs "$ROOTFS_DIR" || exit 1
    log_info "  ✓ All required directories present"
    echo ""

    log_info "Step 3: Verifying rootfs completion..."
    verify_rootfs "$ROOTFS_DIR" || { log_error "Rootfs verification failed"; exit 1; }
    echo ""

    # Qt 校验:仅当 rootfs 实际包含 Qt 时(阶段一无 Qt 自动跳过)
    if [[ -n "$(compgen -G "${ROOTFS_DIR}/usr/lib/libQt6Core.so*" 2>/dev/null)" ]]; then
        verify_qt_artifacts "$ROOTFS_DIR" || { log_error "Qt artifact verification failed"; exit 1; }
        echo ""
    else
        log_info "Qt artifacts: skipped (no Qt in rootfs — expected for minimal buildroot rootfs)"
        echo ""
    fi

    log_info "========================================"
    log_info "RootFS verification passed!"
    log_info "========================================"
}

main "$@"
