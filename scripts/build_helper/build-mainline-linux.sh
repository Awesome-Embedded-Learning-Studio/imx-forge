#!/bin/bash
#
# Linux kernel build script for i.MX6ULL
#

set -e

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

# Configuration
ARCH=arm
CROSS_COMPILE=arm-none-linux-gnueabihf-
DEFCONFIG=imx_aes_mainline_defconfig
FAST_BUILD=0
DEVICE_TREE="${DEFAULT_DEVICE_TREE:-imx6ull-aes}"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --fast-build)
            FAST_BUILD=1
            shift
            ;;
    esac
done

# Directories
LINUX_SRC_DIR="${PROJECT_ROOT}/third_party/linux_mainline"
: "${OUTPUT_DIR:=${PROJECT_ROOT}/out/mainline/linux}"

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"

# Get number of CPU cores for parallel build
NPROC=$(nproc)
log_info "Using ${NPROC} parallel jobs"

# Check host dependencies
check_host_dependencies() {
    log_info "Checking host dependencies..."

    MISSING_PKGS=()
    FOUND_PKGS=()

    # Helper: check if command exists
    check_cmd() {
        local cmd=$1
        local pkg=$2
        if command -v ${cmd} &> /dev/null; then
            FOUND_PKGS+=("${pkg}")
            return 0
        else
            MISSING_PKGS+=("${pkg}")
            return 1
        fi
    }

    # Helper: check if dpkg package is installed
    check_dpkg() {
        local pkg=$1
        if dpkg -s ${pkg} &> /dev/null; then
            FOUND_PKGS+=("${pkg}")
            return 0
        else
            MISSING_PKGS+=("${pkg}")
            return 1
        fi
    }

    # Helper: check if header file exists
    check_header() {
        local header=$1
        local pkg=$2
        if [ -f "${header}" ]; then
            FOUND_PKGS+=("${pkg}")
            return 0
        else
            MISSING_PKGS+=("${pkg}")
            return 1
        fi
    }

    # Helper: check Python module
    check_python_module() {
        local module=$1
        local pkg=$2
        if python3 -c "import ${module}" 2>/dev/null; then
            FOUND_PKGS+=("${pkg}")
            return 0
        else
            MISSING_PKGS+=("${pkg}")
            return 1
        fi
    }

    # Check build tools (use || true to prevent exit on set -e)
    check_cmd gcc build-essential || true
    check_cmd make build-essential || true
    check_cmd bc bc || true
    check_cmd bison bison || true
    check_cmd flex flex || true
    check_cmd dtc device-tree-compiler || true
    check_cmd python3 python3 || true

    # Check libssl via dpkg (more reliable than header check)
    if dpkg -s libssl-dev &> /dev/null; then
        FOUND_PKGS+=("libssl-dev")
    else
        MISSING_PKGS+=("libssl-dev")
    fi

    # Check libgnutls via dpkg or header
    if dpkg -s libgnutls28-dev &> /dev/null || [ -f /usr/include/gnutls/gnutls.h ]; then
        FOUND_PKGS+=("libgnutls28-dev")
    else
        MISSING_PKGS+=("libgnutls28-dev")
    fi

    # Check libncurses via dpkg or header
    if dpkg -s libncurses-dev &> /dev/null || [ -f /usr/include/ncursesw/ncurses.h ] || [ -f /usr/include/ncurses/ncurses.h ]; then
        FOUND_PKGS+=("libncurses-dev")
    else
        MISSING_PKGS+=("libncurses-dev")
    fi

    # Remove duplicates from FOUND_PKGS and MISSING_PKGS
    FOUND_PKGS=($(echo "${FOUND_PKGS[@]}" | tr ' ' '\n' | sort -u))
    MISSING_PKGS=($(echo "${MISSING_PKGS[@]}" | tr ' ' '\n' | sort -u))

    # Display results
    for pkg in "${FOUND_PKGS[@]}"; do
        log_info "  ✓ ${pkg}"
    done

    for pkg in "${MISSING_PKGS[@]}"; do
        log_warn "  ✗ ${pkg} (not found)"
    done

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${MISSING_PKGS[*]}"
        echo ""
        log_info "Install missing packages with:"
        echo -e "  ${YELLOW}sudo apt install ${MISSING_PKGS[*]}${NC}"
        echo ""
        exit 1
    fi

    log_info "All host dependencies found"
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

# Prepare defconfig from template
prepare_defconfig() {
    log_info "Preparing defconfig from template..."

    # Default firmware directory
    FIRMWARE_DIR="${FIRMWARE_DIR:-${PROJECT_ROOT}/driver/firmwares}"

    # Resolve to absolute path
    FIRMWARE_DIR=$(realpath "${FIRMWARE_DIR}")

    # Template and target paths
    TEMPLATE_FILE="${PROJECT_ROOT}/driver/device_tree/alpha-board/linux/imx6ull_mainline_defconfig.template"
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
    local cmd="make -C ${LINUX_SRC_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUTPUT_DIR} -j${NPROC} zImage dtbs"
    echo -e "${YELLOW}[CMD]${NC} ${cmd}"
    ${cmd}
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
        SIZE=$(stat -c%s "${OUTPUT_DIR}/arch/arm/boot/zImage" 2>/dev/null || stat -f%z "${OUTPUT_DIR}/arch/arm/boot/zImage" 2>/dev/null)
        log_info "  ✓ zImage: ${SIZE} bytes"
    else
        log_error "  ✗ zImage: not found"
        has_error=1
    fi

    # 3. Verify board DTB
    local dtb_path="${OUTPUT_DIR}/arch/arm/boot/dts/nxp/imx/${DEVICE_TREE}.dtb"
    if [ -f "${dtb_path}" ]; then
        SIZE=$(stat -c%s "${dtb_path}" 2>/dev/null || stat -f%z "${dtb_path}" 2>/dev/null)
        log_info "  ✓ ${DEVICE_TREE}.dtb: ${SIZE} bytes"
    else
        log_error "  ✗ ${DEVICE_TREE}.dtb: not found"
        has_error=1
    fi

    # 4. Verify .config file
    if [ -f "${OUTPUT_DIR}/.config" ]; then
        log_info "  ✓ .config: present"
    else
        log_error "  ✗ .config: not found"
        has_error=1
    fi

    # 5. Check for System.map
    if [ -f "${OUTPUT_DIR}/System.map" ]; then
        log_info "  ✓ System.map: present"
    else
        log_warn "  ! System.map: not found (optional)"
    fi

    # 6. Check for modules directory
    if [ -d "${OUTPUT_DIR}/modules" ]; then
        log_info "  ✓ modules: directory present"
    fi

    # 7. Summary
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

    # Pre-build checks
    check_host_dependencies
    check_toolchain
    # Note: check_defconfig is called after prepare_defconfig since the file is generated from template

    log_info "========================================"
    log_info "All checks passed, starting build..."
    log_info "========================================"

    # Build process
    if [ ${FAST_BUILD} -eq 0 ]; then
        do_distclean
    else
        log_info "Skipping distclean (fast build mode)"
    fi

    # Print build configuration before starting
    log_info "Build Configuration:"
    log_info "  Linux Source:  ${LINUX_SRC_DIR}"
    log_info "  Output Dir:    ${OUTPUT_DIR}"
    log_info "  Architecture:  ${ARCH}"
    log_info "  Cross Compile: ${CROSS_COMPILE}"
    log_info "  Defconfig:     ${DEFCONFIG}"
    log_info "  Device Tree:   ${DEVICE_TREE}"
    log_info "  Parallel Jobs: ${NPROC}"
    log_info "========================================"

    prepare_defconfig
    do_configure
    do_build

    log_info "========================================"

    # Verify build artifacts
    verify_build_artifacts || exit 1

    log_info "========================================"
    log_info "Build completed successfully!"

    # Display output files summary
    log_info "Kernel artifacts in ${OUTPUT_DIR}:"
    [ -f "${OUTPUT_DIR}/vmlinux" ] && log_info "  ✓ vmlinux (ELF kernel)"
    [ -f "${OUTPUT_DIR}/arch/arm/boot/zImage" ] && log_info "  ✓ arch/arm/boot/zImage (compressed kernel)"
    [ -f "${OUTPUT_DIR}/arch/arm/boot/dts/nxp/imx/${DEVICE_TREE}.dtb" ] && log_info "  ✓ arch/arm/boot/dts/nxp/imx/${DEVICE_TREE}.dtb (device tree)"
    [ -f "${OUTPUT_DIR}/System.map" ] && log_info "  ✓ System.map (symbol table)"
    [ -f "${OUTPUT_DIR}/.config" ] && log_info "  ✓ .config (kernel configuration)"

    log_info "========================================"
}

# Run main function
main "$@"
