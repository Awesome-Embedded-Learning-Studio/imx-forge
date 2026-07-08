#!/bin/bash
#
# U-Boot build script for mx6ull_14x14_evk_emmc
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

# buildmeter progress bar (optional; auto-falls back to bare make if buildmeter
# is absent or FORGE_PROGRESS_DISABLE=1). See scripts/lib/progress.sh.
source "${SCRIPT_LIB_DIR}/progress.sh" 2>/dev/null || true

# 导入依赖检查脚本
source "${SCRIPT_DIR}/../init/env-init.sh"

# Configuration
ARCH=arm
CROSS_COMPILE=arm-none-linux-gnueabihf-
DEFCONFIG=mx6ull_aes_emmc_defconfig
DEFAULT_DEVICE_TREE="imx6ull-aes"

# Directories
UBOOT_SRC_DIR="${PROJECT_ROOT}/third_party/uboot-imx"
: "${OUTPUT_DIR:=${PROJECT_ROOT}/out/uboot}"

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"

# Get number of CPU cores for parallel build
NPROC=$(nproc)
log_info "Using ${NPROC} parallel jobs"

# Check host dependencies
check_host_dependencies() {
    check_uboot_dependencies || exit 1
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

# Check if device tree exists
check_device_tree() {
    log_info "Checking device tree..."

    DTS_FILE="${UBOOT_SRC_DIR}/arch/arm/dts/${DEFAULT_DEVICE_TREE}.dts"

    if [ ! -f "${DTS_FILE}" ]; then
        log_error "Device tree file not found: ${DTS_FILE}"
        exit 1
    fi

    log_info "Device tree found: ${DTS_FILE}"

    # Also check for the .dtsi base file if it exists
    BASE_DTS="${UBOOT_SRC_DIR}/arch/arm/dts/${DEFAULT_DEVICE_TREE}.dtsi"
    if [ -f "${BASE_DTS}" ]; then
        log_info "Base device tree found: ${BASE_DTS}"
    fi
}

# Check if defconfig exists
check_defconfig() {
    log_info "Checking defconfig..."

    DEFCONFIG_FILE="${UBOOT_SRC_DIR}/configs/${DEFCONFIG}"

    if [ ! -f "${DEFCONFIG_FILE}" ]; then
        log_error "Defconfig file not found: ${DEFCONFIG_FILE}"
        exit 1
    fi

    log_info "Defconfig found: ${DEFCONFIG_FILE}"
}

# Clean build
do_distclean() {
    log_info "Running distclean... Using Remove All as to make all clear!"
    # Remove and recreate output directory for clean build
    log_info "  Removing ${OUTPUT_DIR}"
    rm -rf "${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"
}

# Configure U-Boot
do_configure() {
    log_info "Configuring U-Boot with ${DEFCONFIG}..."
    local cmd="make -C ${UBOOT_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUTPUT_DIR} ${DEFCONFIG}"
    echo -e "${YELLOW}[CMD]${NC} ${cmd}"
    ${cmd}
}

# Build U-Boot
do_build() {
    log_info "Building U-Boot..."
    local cmd="make -C ${UBOOT_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUTPUT_DIR} -j${NPROC}"
    echo -e "${YELLOW}[CMD]${NC} ${cmd}"
    if forge_progress_enabled; then
        # uboot 也是 kbuild(同 kernel):dry-run 预扫描出 %。binman 的 'Error 103'/
        # 'images are invalid' 是已知噪音(非真错),--ignore-errors 过滤免误报。
        log_info "Pre-scanning dry-run (make -n -k) for progress total…"
        local total=$(${cmd} -n -k 2>/dev/null | python3 "${FORGE_PROGRESS_PY}" uboot --count-only || true)
        if [[ -n "${total}" ]]; then
            ${cmd} 2>&1 | python3 "${FORGE_PROGRESS_PY}" uboot --total "${total}" \
                --tail "${FORGE_PROGRESS_TAIL}" --ignore-errors 'Error 103|images are invalid'
        else
            ${cmd} 2>&1 | python3 "${FORGE_PROGRESS_PY}" uboot \
                --tail "${FORGE_PROGRESS_TAIL}" --ignore-errors 'Error 103|images are invalid'
        fi
    else
        ${cmd}
    fi
}

# Verify build artifacts
verify_build_artifacts() {
    log_info "Verifying build artifacts in ${OUTPUT_DIR}..."

    local has_error=0

    # 1. Verify ELF file architecture
    if [ -f "${OUTPUT_DIR}/u-boot" ]; then
        # Use readelf from cross toolchain if available, otherwise system readelf
        local readelf_cmd="${CROSS_COMPILE}readelf"
        if ! command -v ${readelf_cmd} &> /dev/null; then
            readelf_cmd="readelf"
        fi

        if command -v ${readelf_cmd} &> /dev/null; then
            ARCH_INFO=$(${readelf_cmd} -h ${OUTPUT_DIR}/u-boot 2>/dev/null | grep "Machine:" | awk '{print $2}')
            if [[ "${ARCH_INFO}" == *"ARM"* ]]; then
                log_info "  ✓ u-boot: ${ARCH_INFO}"

                # Display entry point address
                ENTRY_ADDR=$(${readelf_cmd} -h ${OUTPUT_DIR}/u-boot 2>/dev/null | grep "Entry point" | awk '{print $4}')
                if [ -n "${ENTRY_ADDR}" ]; then
                    log_info "    Entry: 0x${ENTRY_ADDR}"
                fi
            else
                log_error "  ✗ u-boot: Wrong architecture (${ARCH_INFO})"
                has_error=1
            fi
        else
            log_info "  ? u-boot: present (readelf not available for verification)"
        fi
    else
        log_error "  ✗ u-boot: not found"
        has_error=1
    fi

    # 2. Verify binary file
    if [ -f "${OUTPUT_DIR}/u-boot.bin" ]; then
        SIZE=$(stat -c%s ${OUTPUT_DIR}/u-boot.bin 2>/dev/null || stat -f%z ${OUTPUT_DIR}/u-boot.bin 2>/dev/null)
        log_info "  ✓ u-boot.bin: ${SIZE} bytes"
    else
        log_error "  ✗ u-boot.bin: not found"
        has_error=1
    fi

    # 3. Verify device tree blob
    if [ -f "${OUTPUT_DIR}/u-boot.dtb" ]; then
        # Try to verify device tree content with dtc
        if command -v dtc &> /dev/null; then
            DTS_INFO=$(dtc -I dtb -O dts ${OUTPUT_DIR}/u-boot.dtb 2>/dev/null | grep -E "compatible|fsl,imx6ull" | head -3)
            if [[ "${DTS_INFO}" == *"fsl,imx6ull"* ]] || [[ "${DTS_INFO}" == *"imx6ull-14x14-evk"* ]]; then
                log_info "  ✓ u-boot.dtb: i.MX6ULL device tree detected"
            else
                log_info "  ✓ u-boot.dtb: present"
            fi
        else
            # Check file size as basic validation
            DTB_SIZE=$(stat -c%s ${OUTPUT_DIR}/u-boot.dtb 2>/dev/null || stat -f%z ${OUTPUT_DIR}/u-boot.dtb 2>/dev/null)
            log_info "  ✓ u-boot.dtb: ${DTB_SIZE} bytes"
        fi
    else
        log_error "  ✗ u-boot.dtb: not found"
        has_error=1
    fi

    # 4. Verify iMX image if it exists (flashable artifact)
    if [ -f "${OUTPUT_DIR}/u-boot-dtb.imx" ]; then
        if [ -f "${UBOOT_SRC_DIR}/tools/mkimage" ]; then
            IMX_INFO=$(${UBOOT_SRC_DIR}/tools/mkimage -l ${OUTPUT_DIR}/u-boot-dtb.imx 2>/dev/null | grep "Image Type")
            if [ -n "${IMX_INFO}" ]; then
                log_info "  ✓ u-boot-dtb.imx: ${IMX_INFO}"
            else
                SIZE=$(stat -c%s ${OUTPUT_DIR}/u-boot-dtb.imx 2>/dev/null || stat -f%z ${OUTPUT_DIR}/u-boot-dtb.imx 2>/dev/null)
                log_info "  ✓ u-boot-dtb.imx: ${SIZE} bytes"
            fi
        else
            SIZE=$(stat -c%s ${OUTPUT_DIR}/u-boot-dtb.imx 2>/dev/null || stat -f%z ${OUTPUT_DIR}/u-boot-dtb.imx 2>/dev/null)
            log_info "  ✓ u-boot-dtb.imx: ${SIZE} bytes"
        fi
    else
        log_error "  ✗ u-boot-dtb.imx: not found"
        has_error=1
    fi

    # 5. Summary
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
    log_info "Starting U-Boot build for ${DEFCONFIG}"
    log_info "========================================"

    # Pre-build checks
    check_host_dependencies
    check_toolchain
    check_device_tree
    check_defconfig

    log_info "========================================"
    log_info "All checks passed, starting build..."
    log_info "========================================"

    # Prepare logo before build
    log_info "Preparing logo..."
    "${SCRIPT_DIR}/../logo_helper/logo_helper.sh" 800x480 document/logo/logo.png third_party/uboot-imx/tools/logos/denx.bmp

    # Build process
    do_distclean
    do_configure
    do_build

    log_info "========================================"

    # Verify build artifacts
    verify_build_artifacts || exit 1

    log_info "========================================"
    log_info "Build completed successfully!"

    # Display output files summary (flashable artifacts)
    log_info "Flashable artifacts in ${OUTPUT_DIR}:"
    [ -f "${OUTPUT_DIR}/u-boot-dtb.imx" ] && log_info "  ✓ u-boot-dtb.imx (for i.MX boot)"
    [ -f "${OUTPUT_DIR}/u-boot-dtb.bin" ] && log_info "  ✓ u-boot-dtb.bin"
    [ -f "${OUTPUT_DIR}/u-boot.dtb" ] && log_info "  ✓ u-boot.dtb"

    log_info "========================================"
}

# Run main function
main "$@"
