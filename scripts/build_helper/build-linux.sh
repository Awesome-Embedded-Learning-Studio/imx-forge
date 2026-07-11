#!/bin/bash
#
# Linux kernel build script for i.MX6ULL
#

# -o pipefail: do_build pipes make | buildmeter; without it a failed make would
# be masked by buildmeter's exit-0 and set -e would miss the failure.
set -eo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/../lib"

# Source shared logging (with fallback for standalone usage)
if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    # Fallback to local definitions if shared lib not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_debug() { if [[ "${DEBUG:-0}" == "1" ]]; then echo -e "${BLUE}[DEBUG]${NC} $1"; fi; }
    log_cmd() { echo -e "${YELLOW}[CMD]${NC} $1"; }
fi

# 导入依赖检查脚本
source "${SCRIPT_DIR}/../init/env-init.sh"

# buildmeter progress bar (optional; auto-falls back to bare make if buildmeter
# is absent or FORGE_PROGRESS_DISABLE=1). See scripts/lib/progress.sh.
source "${SCRIPT_LIB_DIR}/progress.sh" 2>/dev/null || true

# Configuration
ARCH=arm
CROSS_COMPILE=arm-none-linux-gnueabihf-
DEFCONFIG=imx_aes_defconfig
DEFAULT_DEVICE_TREE="${DEFAULT_DEVICE_TREE:-imx6ull-aes}"
FAST_BUILD=0

# Parse arguments
# --release 触发 release 编排(reset 净源码→打 patch→建 release 分支→build_info),
# 详见 scripts/lib/release.sh。不传时分步构建行为与之前完全一致。
RELEASE_MODE=0
RELEASE_VERSION="unknown"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast-build) FAST_BUILD=1; shift ;;
        --release) RELEASE_MODE=1; shift ;;
        --release-version)
            [[ $# -ge 2 ]] || { log_error "--release-version requires a value"; exit 1; }
            RELEASE_VERSION="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--fast-build] [--release] [--release-version V]"
            exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Directories
LINUX_SRC_DIR="${PROJECT_ROOT}/third_party/linux-imx"
: "${OUTPUT_DIR:=${PROJECT_ROOT}/out/linux}"

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"

# Get number of CPU cores for parallel build
NPROC=$(nproc)
log_info "Using ${NPROC} parallel jobs"

# Check host dependencies
check_host_dependencies() {
    check_linux_dependencies || exit 1
}

# Check if toolchain exists
check_toolchain() {
    log_info "Checking toolchain..."

    # Check for cross compiler
    if ! command -v ${CROSS_COMPILE}gcc &> /dev/null; then
        log_error "Cross compiler '${CROSS_COMPILE}gcc' not found!"
        log_error "Please ensure the toolchain is installed and in your PATH"
        exit 1
    fi

    # Display toolchain version
    GCC_VERSION=$(${CROSS_COMPILE}gcc --version | head -n1)
    log_info "Toolchain found: ${GCC_VERSION}"

    # Check for essential tools
    for tool in objcopy objdump strip; do
        if ! command -v ${CROSS_COMPILE}${tool} &> /dev/null; then
            log_error "Tool '${CROSS_COMPILE}${tool}' not found!"
            exit 1
        fi
    done

    log_info "All required toolchain components found"
}

# Check if defconfig exists
check_defconfig() {
    log_info "Checking defconfig..."

    DEFCONFIG_FILE="${LINUX_SRC_DIR}/arch/arm/configs/${DEFCONFIG}"

    if [ ! -f "${DEFCONFIG_FILE}" ]; then
        log_warn "Defconfig file not found: ${DEFCONFIG_FILE}"
        log_info "Will prepare defconfig from template"
        return 1
    fi

    log_info "Defconfig found: ${DEFCONFIG_FILE}"
    return 0
}

# Clean build
do_distclean() {
    log_info "Running distclean... Using Remove All as to make all clear!"
    # Remove and recreate output directory for clean build
    log_info "  Removing ${OUTPUT_DIR}"
    rm -rf "${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"
}

# Prepare defconfig from template
prepare_defconfig() {
    log_info "Preparing defconfig from template..."

    # Default firmware directory
    FIRMWARE_DIR="${FIRMWARE_DIR:-${PROJECT_ROOT}/driver/firmwares}"

    # Resolve to absolute path
    FIRMWARE_DIR=$(realpath "${FIRMWARE_DIR}")

    # Template and target paths
    TEMPLATE_FILE="${PROJECT_ROOT}/driver/device_tree/alpha-board/linux/imx_aes_defconfig.template"
    TARGET_FILE="${LINUX_SRC_DIR}/arch/arm/configs/${DEFCONFIG}"

    # Copy template and substitute variable
    sed "s|\${FIRMWARE_DIR}|${FIRMWARE_DIR}|g" "${TEMPLATE_FILE}" > "${TARGET_FILE}"

    log_info "  Template: ${TEMPLATE_FILE}"
    log_info "  Target:   ${TARGET_FILE}"
    log_info "  Firmware Dir: ${FIRMWARE_DIR}"

    # Clone wireless-regdb repository and copy regulatory.db files
    log_info "Preparing wireless regulatory database..."

    local REGDB_REPO_URL="https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git"
    local REGDB_CLONE_DIR="${PROJECT_ROOT}/out/firmwares/wireless-regdb"
    local DRIVER_FIRMWARE_DIR="${PROJECT_ROOT}/driver/firmwares"

    # Ensure target directories exist
    mkdir -p "${PROJECT_ROOT}/out/firmwares"
    mkdir -p "${DRIVER_FIRMWARE_DIR}"

    # Clone repository if not already present
    if [ -d "${REGDB_CLONE_DIR}" ]; then
        log_info "  wireless-regdb repository already exists, skipping clone"
    else
        log_info "  Cloning wireless-regdb repository..."
        git clone "${REGDB_REPO_URL}" "${REGDB_CLONE_DIR}"
    fi

    # Copy regulatory.db files
    if [ -f "${REGDB_CLONE_DIR}/regulatory.db" ]; then
        cp "${REGDB_CLONE_DIR}/regulatory.db" "${DRIVER_FIRMWARE_DIR}/"
        log_info "  Copied regulatory.db to ${DRIVER_FIRMWARE_DIR}"
    else
        log_warn "  regulatory.db not found in repository"
    fi

    if [ -f "${REGDB_CLONE_DIR}/regulatory.db.p7s" ]; then
        cp "${REGDB_CLONE_DIR}/regulatory.db.p7s" "${DRIVER_FIRMWARE_DIR}/"
        log_info "  Copied regulatory.db.p7s to ${DRIVER_FIRMWARE_DIR}"
    else
        log_warn "  regulatory.db.p7s not found in repository"
    fi
}

# Configure Linux kernel
do_configure() {
    log_info "Configuring Linux kernel with ${DEFCONFIG}..."
    local cmd="make -C ${LINUX_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUTPUT_DIR} ${DEFCONFIG}"
    echo -e "${YELLOW}[CMD]${NC} ${cmd}"
    ${cmd}
}

# Build Linux kernel
do_build() {
    log_info "Building Linux kernel..."
    # 显式 zImage dtbs:arm 默认 goal 只出 zImage 不出 dtbs,release-all Stage2 要校验 dtb。
    local cmd="make -C ${LINUX_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUTPUT_DIR} -j${NPROC} zImage dtbs"
    echo -e "${YELLOW}[CMD]${NC} ${cmd}"
    if forge_progress_enabled; then
        local total=""
        if [[ ${FAST_BUILD} -eq 0 ]]; then
            log_info "Pre-scanning dry-run (make -n -k) for progress total (~15s)…"
            total=$(${cmd} -n -k 2>/dev/null | python3 "${FORGE_PROGRESS_PY}" kernel --count-only || true)
        fi
        if [[ -n "${total}" ]]; then
            ${cmd} 2>&1 | python3 "${FORGE_PROGRESS_PY}" kernel --total "${total}" --tail "${FORGE_PROGRESS_TAIL}"
        else
            ${cmd} 2>&1 | python3 "${FORGE_PROGRESS_PY}" kernel --tail "${FORGE_PROGRESS_TAIL}"
        fi
    else
        ${cmd}
    fi
}

# Verify build artifacts
verify_build_artifacts() {
    log_info "Verifying build artifacts in ${OUTPUT_DIR}..."

    local has_error=0

    # 1. Verify vmlinux ELF file
    if [ -f "${OUTPUT_DIR}/vmlinux" ]; then
        # Use readelf from cross toolchain if available, otherwise system readelf
        local readelf_cmd="${CROSS_COMPILE}readelf"
        if ! command -v ${readelf_cmd} &> /dev/null; then
            readelf_cmd="readelf"
        fi

        if command -v ${readelf_cmd} &> /dev/null; then
            ARCH_INFO=$(${readelf_cmd} -h ${OUTPUT_DIR}/vmlinux 2>/dev/null | grep "Machine:" | awk '{print $2}')
            if [[ "${ARCH_INFO}" == *"ARM"* ]]; then
                log_info "  ✓ vmlinux: ${ARCH_INFO}"

                # Display entry point address
                ENTRY_ADDR=$(${readelf_cmd} -h ${OUTPUT_DIR}/vmlinux 2>/dev/null | grep "Entry point" | awk '{print $4}')
                if [ -n "${ENTRY_ADDR}" ]; then
                    log_info "    Entry: 0x${ENTRY_ADDR}"
                fi
            else
                log_error "  ✗ vmlinux: Wrong architecture (${ARCH_INFO})"
                has_error=1
            fi
        else
            log_info "  ? vmlinux: present (readelf not available for verification)"
        fi
    else
        log_error "  ✗ vmlinux: not found"
        has_error=1
    fi

    # 2. Verify zImage (compressed kernel image)
    if [ -f "${OUTPUT_DIR}/arch/arm/boot/zImage" ]; then
        SIZE=$(stat -c%s ${OUTPUT_DIR}/arch/arm/boot/zImage 2>/dev/null || stat -f%z ${OUTPUT_DIR}/arch/arm/boot/zImage 2>/dev/null)
        log_info "  ✓ zImage: ${SIZE} bytes"
    else
        log_error "  ✗ zImage: not found"
        has_error=1
    fi

    # 2b. Verify device tree blob (release-all Stage2 校验 dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb)
    local dtb_path="${OUTPUT_DIR}/arch/arm/boot/dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb"
    if [ -f "${dtb_path}" ]; then
        SIZE=$(stat -c%s "${dtb_path}" 2>/dev/null || stat -f%z "${dtb_path}" 2>/dev/null)
        log_info "  ✓ ${DEFAULT_DEVICE_TREE}.dtb: ${SIZE} bytes"
    else
        log_error "  ✗ ${DEFAULT_DEVICE_TREE}.dtb: not found (${dtb_path})"
        has_error=1
    fi

    # 3. Verify .config file
    if [ -f "${OUTPUT_DIR}/.config" ]; then
        log_info "  ✓ .config: present"
    else
        log_error "  ✗ .config: not found"
        has_error=1
    fi

    # 4. Check for System.map
    if [ -f "${OUTPUT_DIR}/System.map" ]; then
        log_info "  ✓ System.map: present"
    else
        log_warn "  ! System.map: not found (optional)"
    fi

    # 5. Check for modules directory
    if [ -d "${OUTPUT_DIR}/modules" ]; then
        log_info "  ✓ modules: directory present"
    fi

    # 6. Summary
    if [ ${has_error} -eq 0 ]; then
        log_info "All build artifacts verified successfully"
        return 0
    else
        log_error "Build artifact verification failed"
        return 1
    fi
}

# Main build process
main() {
    log_info "Starting Linux kernel build for ${DEFCONFIG}"
    if [ ${FAST_BUILD} -eq 1 ]; then
        log_info "Fast build mode enabled (skipping distclean)"
    fi
    log_info "========================================"

    # Release 编排(--release):reset 净源码→打 patch→建 release 分支。必须在 checks 前
    # (defconfig 由 prepare_defconfig 从超项目模板生成,reset 后会重建,不受影响)。
    if [[ ${RELEASE_MODE} -eq 1 ]]; then
        source "${SCRIPT_LIB_DIR}/release.sh"
        release_prepare "linux-imx" "${LINUX_SRC_DIR}" \
            "${PROJECT_ROOT}/patches/linux-imx/linux-imx-latest.patch"
        log_info "========================================"
    fi

    # Pre-build checks
    check_host_dependencies
    check_toolchain
    
    # Check defconfig and prepare if needed
    if ! check_defconfig; then
        prepare_defconfig || {
            log_error "Failed to prepare defconfig"
            exit 1
        }
    fi

    log_info "========================================"
    log_info "All checks passed, starting build..."
    log_info "========================================"

    # Build process
    if [ ${FAST_BUILD} -eq 0 ]; then
        do_distclean
    else
        log_info "Skipping distclean (fast build mode)"
    fi
    prepare_defconfig
    do_configure
    do_build

    log_info "========================================"

    # Verify build artifacts
    verify_build_artifacts || exit 1

    # Release 收尾(--release):写 build_info.txt(含 `Kernel Track: imx`,release-all Stage2 硬依赖)
    if [[ ${RELEASE_MODE} -eq 1 ]]; then
        release_finalize "linux-imx" "${OUTPUT_DIR}" "${RELEASE_VERSION}"
    fi

    log_info "========================================"
    log_info "Build completed successfully!"

    # Display output files summary
    log_info "Kernel artifacts in ${OUTPUT_DIR}:"
    [ -f "${OUTPUT_DIR}/vmlinux" ] && log_info "  ✓ vmlinux (ELF kernel)"
    [ -f "${OUTPUT_DIR}/arch/arm/boot/zImage" ] && log_info "  ✓ arch/arm/boot/zImage (compressed kernel)"
    [ -f "${OUTPUT_DIR}/arch/arm/boot/dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb" ] && log_info "  ✓ arch/arm/boot/dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb (device tree)"
    [ -f "${OUTPUT_DIR}/System.map" ] && log_info "  ✓ System.map (symbol table)"
    [ -f "${OUTPUT_DIR}/.config" ] && log_info "  ✓ .config (kernel configuration)"

    log_info "========================================"
}

# Run main function
main "$@"
