#!/bin/bash
#
# build-all.sh - Unified build script for mini Linux distribution
#
# Usage:
#   ./scripts/build-all.sh [OPTIONS]
#
# Options:
#   --fast-build    - Pass --fast-build to linux build (skip distclean)
#   --mainline      - Build Linux from upstream/mainline kernel track
#   --boot-media M  - Image boot media: emmc, sd, or both
#   --stage N       - Run only specific stage (1-5)
#   --help, -h      - Show this help message
#
# Stages:
#   1 - U-Boot bootloader
#   2 - Linux kernel
#   3 - BusyBox userland
#   4 - RootFS completion (third-party dependencies)
#   5 - SD/eMMC full image creation
#
# Output directory: out/release-latest/
#

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

# Source shared logging
if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[build-all]${NC} $1"; }
    log_error() { echo -e "${RED}[build-all]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[build-all]${NC} $1"; }
fi

# Configuration
BUILD_OUTPUT_DIR="${PROJECT_ROOT}/out/release-latest"
CROSS_COMPILE=arm-none-linux-gnueabihf-

# Device tree selection (can be overridden via environment variable)
# Example: DEFAULT_DEVICE_TREE="imx6ull-14x14-evk-emmc" ./scripts/release-all.sh
: "${DEFAULT_DEVICE_TREE:=imx6ull-aes}"

# Build options
FAST_BUILD=0
CONTINUE_BUILD=0
SPECIFIC_STAGE=""
KERNEL_TRACK="imx"
BOOT_MEDIA="${DEFAULT_BOOT_MEDIA:-emmc}"

# Display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --fast-build      Pass --fast-build to linux build (skip distclean)
  --mainline        Build Linux from upstream/mainline kernel track
  --boot-media M    Image boot media for stage 5: emmc, sd, or both
                    (default: emmc, or DEFAULT_BOOT_MEDIA)
  --continue        Continue from existing release-latest (skip completed stages)
  --stage N         Run only specific stage (1-5)
  --help, -h        Show this help message

Environment Variables:
  DEFAULT_DEVICE_TREE  Device tree name for symlinks (default: imx6ull-aes)
  DEFAULT_BOOT_MEDIA   Image boot media for stage 5 (default: emmc)
  DEFAULT_IMAGE_SIZE_MB Fixed image size passed to image builder (optional)

Stages:
  1  U-Boot bootloader
  2  Linux kernel
  3  BusyBox userland
  4  RootFS completion with third-party dependencies
  5  SD/eMMC full image creation

Examples:
  $0                                          # Build all stages
  $0 --stage 1                                # Build U-Boot only
  $0 --stage 5                                # Build default eMMC image only
  $0 --continue --stage 5                     # Continue and build image from existing release-latest
  $0 --continue --stage 5 --boot-media sd     # Continue and build SD image
  $0 --continue --stage 5 --boot-media both   # Continue and build both eMMC and SD images
  $0 --fast-build                             # Build all with fast build mode
  $0 --stage 2 --fast-build                   # Build Linux with fast build mode
  $0 --mainline --stage 2                     # Build mainline Linux into release layout
  $0 --mainline --stage 2 --fast-build        # Build mainline Linux with fast build mode
  $0 --continue                               # Continue from existing build (skip completed stages)
  $0 --continue --stage 4                     # Continue and run only Stage 4
  DEFAULT_DEVICE_TREE=custom-dtb $0           # Use custom device tree

Output directory: ${BUILD_OUTPUT_DIR}/
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast-build)
            FAST_BUILD=1
            shift
            ;;
        --mainline)
            KERNEL_TRACK="mainline"
            shift
            ;;
        --boot-media)
            if [[ $# -lt 2 ]]; then
                log_error "--boot-media requires a value"
                exit 1
            fi
            BOOT_MEDIA="$2"
            shift 2
            ;;
        --boot-media=*)
            BOOT_MEDIA="${1#*=}"
            shift
            ;;
        --continue)
            CONTINUE_BUILD=1
            shift
            ;;
        --stage)
            if [[ $# -lt 2 ]]; then
                log_error "--stage requires a value"
                exit 1
            fi
            SPECIFIC_STAGE="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

validate_boot_media() {
    case "${BOOT_MEDIA}" in
        emmc|sd|both)
            ;;
        *)
            log_error "Invalid boot media: ${BOOT_MEDIA} (must be emmc, sd, or both)"
            exit 1
            ;;
    esac
}

image_name_for_media() {
    local media="$1"

    if [[ "${DEFAULT_DEVICE_TREE}" == imx6ull* ]]; then
        echo "${DEFAULT_DEVICE_TREE}-${media}.img"
    else
        echo "imx6ull-${DEFAULT_DEVICE_TREE}-${media}.img"
    fi
}

# Stage 1: U-Boot
stage_1_uboot() {
    log_info "========================================="
    log_info "Stage 1/5: Building U-Boot"
    log_info "========================================="

    export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/uboot"

    log_info "Output directory: ${OUTPUT_DIR}"
    echo ""

    bash "${SCRIPT_DIR}/release_builder/build_release_uboot.sh"

    # Verify key artifacts
    if [[ -f "${OUTPUT_DIR}/u-boot-dtb.imx" ]]; then
        log_info "U-Boot build successful"
    else
        log_error "U-Boot build failed - u-boot-dtb.imx not found"
        exit 1
    fi
}

# Stage 2: Linux
stage_2_linux() {
    log_info "========================================="
    log_info "Stage 2/5: Building Linux Kernel (${KERNEL_TRACK})"
    log_info "========================================="

    export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/linux"

    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "Kernel track: ${KERNEL_TRACK}"

    local build_script="${SCRIPT_DIR}/release_builder/build_release_linux.sh"
    if [[ "${KERNEL_TRACK}" == "mainline" ]]; then
        build_script="${SCRIPT_DIR}/release_builder/build_release_mainline_linux.sh"
    fi

    local build_args=()
    if [[ ${FAST_BUILD} -eq 1 ]]; then
        log_info "Fast build mode enabled"
        build_args+=(--fast-build)
    fi
    echo ""
    bash "${build_script}" "${build_args[@]}"

    # Verify key artifacts
    local zimage="${OUTPUT_DIR}/arch/arm/boot/zImage"
    local dtb="${OUTPUT_DIR}/arch/arm/boot/dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb"
    local build_info="${OUTPUT_DIR}/build_info.txt"

    if [[ -f "${zimage}" ]]; then
        log_info "Linux build successful"
    else
        log_error "Linux build failed - zImage not found"
        exit 1
    fi

    if [[ -f "${dtb}" ]]; then
        log_info "DTB build successful: ${DEFAULT_DEVICE_TREE}.dtb"
    else
        log_error "Linux build failed - DTB not found: ${dtb}"
        exit 1
    fi

    if [[ -f "${build_info}" ]] && grep -q "Kernel Track: ${KERNEL_TRACK}" "${build_info}"; then
        log_info "Build info records kernel track: ${KERNEL_TRACK}"
    elif [[ "${KERNEL_TRACK}" == "mainline" ]]; then
        log_error "Linux build failed - build_info.txt does not record mainline kernel track"
        exit 1
    fi
}

# Stage 3: BusyBox
stage_3_busybox() {
    log_info "========================================="
    log_info "Stage 3/5: Building BusyBox"
    log_info "========================================="

    export OUTPUT_DIR="${BUILD_OUTPUT_DIR}/busybox"
    export INSTALL_DIR="${BUILD_OUTPUT_DIR}/rootfs"

    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "Install directory: ${INSTALL_DIR}"
    echo ""

    bash "${SCRIPT_DIR}/release_builder/build_release_busybox.sh"
    
    # Verify key artifacts
    if [[ -f "${OUTPUT_DIR}/busybox" ]]; then
        log_info "BusyBox build successful"
    else
        log_error "BusyBox build failed - busybox binary not found"
        exit 1
    fi

    if [[ -f "${INSTALL_DIR}/bin/busybox" ]]; then
        log_info "BusyBox installed to rootfs"
    else
        log_warn "BusyBox installation may have issues"
    fi
}

# Stage 4: RootFS completion
stage_4_rootfs() {
    log_info "========================================="
    log_info "Stage 4/5: Completing RootFS"
    log_info "========================================="

    export ROOTFS_DIR="${BUILD_OUTPUT_DIR}/rootfs"
    mkdir -p "$ROOTFS_DIR"
    log_info "RootFS directory: ${ROOTFS_DIR}"
    echo ""
    log_info "Running Command: ${SCRIPT_DIR}/varified_rootfs_ok.sh --rootfs-dir=${ROOTFS_DIR}"
    bash "${SCRIPT_DIR}/varified_rootfs_ok.sh" --rootfs-dir="${ROOTFS_DIR}"

    echo ""
    log_info "Merging Rootfs Overlay from rootfs/overlay/rootfs to ${ROOTFS_DIR}"
    bash "${SCRIPT_DIR}/merge_overlay_rootfs.sh" --rootfs-dir="${ROOTFS_DIR}" --overlay-name=rootfs

    log_info "RootFS completion successful"
}

# Stage 5: Full image creation
stage_5_image() {
    log_info "========================================="
    log_info "Stage 5/5: Creating full flash image (${BOOT_MEDIA})"
    log_info "========================================="

    local image_builder="${SCRIPT_DIR}/image_builder/build_imx6ull_image.sh"
    if [[ ! -x "${image_builder}" ]]; then
        log_error "Image builder not found or not executable: ${image_builder}"
        exit 1
    fi

    local media_list=()
    if [[ "${BOOT_MEDIA}" == "both" ]]; then
        media_list=(emmc sd)
    else
        media_list=("${BOOT_MEDIA}")
    fi

    for media in "${media_list[@]}"; do
        log_info "Building ${media} image"
        bash "${image_builder}" \
            --release-dir="${BUILD_OUTPUT_DIR}" \
            --device-tree="${DEFAULT_DEVICE_TREE}" \
            --boot-media="${media}"
    done

    log_info "Full image creation successful"
}

# Create convenience symlinks
create_symlinks() {
    log_info "========================================="
    log_info "Creating convenience symlinks"
    log_info "========================================="

    local images_dir="${BUILD_OUTPUT_DIR}/images"
    mkdir -p "${images_dir}"

    # U-Boot images
    if [[ -f "${BUILD_OUTPUT_DIR}/uboot/u-boot-dtb.imx" ]]; then
        ln -sf "../uboot/u-boot-dtb.imx" "${images_dir}/"
        log_info "  + images/u-boot-dtb.imx"
    fi

    # Linux images
    if [[ -f "${BUILD_OUTPUT_DIR}/linux/arch/arm/boot/zImage" ]]; then
        mkdir -p "${images_dir}"
        ln -sf "../linux/arch/arm/boot/zImage" "${images_dir}/"
        log_info "  + images/zImage"
    fi

    # Device trees (if available)
    local dtb_path="${BUILD_OUTPUT_DIR}/linux/arch/arm/boot/dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb"
    if [[ -f "${dtb_path}" ]]; then
        ln -sf "../linux/arch/arm/boot/dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb" "${images_dir}/"
        log_info "  + images/${DEFAULT_DEVICE_TREE}.dtb"
    else
        log_warn "  ! DTB not found: ${DEFAULT_DEVICE_TREE} (non-fatal)"
    fi

    log_info "Symlinks created in ${images_dir}/"
}

# Show final summary
show_summary() {
    log_info "========================================="
    log_info "Build Summary"
    log_info "========================================="
    log_info ""
    log_info "Build artifacts location: ${BUILD_OUTPUT_DIR}/"
    log_info ""
    log_info "Directory structure:"
    log_info "  uboot/        - U-Boot bootloader"
    log_info "  linux/        - Linux kernel"
    log_info "  busybox/      - BusyBox userland"
    log_info "  rootfs/       - Complete root filesystem"
    log_info "  images/       - Flashable images (symlinks)"
    log_info ""
    log_info "Flashable images:"
    local images_dir="${BUILD_OUTPUT_DIR}/images"
    if [[ -d "${images_dir}" ]]; then
        for f in "${images_dir}"/*; do
            if [[ -e "$f" ]]; then
                log_info "  - $(basename "$f")"
            fi
        done
    fi
    log_info ""
    log_info "To use the rootfs:"
    log_info "  - For NFS mount: bash scripts/manual_mount_nfs.sh"
    log_info "  - Or copy to SD card"
    log_info ""
}

# Check if a stage has already been completed
is_stage_completed() {
    local stage=$1

    case "${stage}" in
        1)
            [[ -f "${BUILD_OUTPUT_DIR}/uboot/u-boot-dtb.imx" ]]
            ;;
        2)
            [[ -f "${BUILD_OUTPUT_DIR}/linux/arch/arm/boot/zImage" ]] &&
            [[ -f "${BUILD_OUTPUT_DIR}/linux/arch/arm/boot/dts/nxp/imx/${DEFAULT_DEVICE_TREE}.dtb" ]] &&
            [[ -f "${BUILD_OUTPUT_DIR}/linux/build_info.txt" ]] &&
            grep -q "Kernel Track: ${KERNEL_TRACK}" "${BUILD_OUTPUT_DIR}/linux/build_info.txt"
            ;;
        3)
            [[ -f "${BUILD_OUTPUT_DIR}/busybox/busybox" && -f "${BUILD_OUTPUT_DIR}/rootfs/bin/busybox" ]]
            ;;
        4)
            # Stage 4 completion is hard to verify, assume incomplete
            false
            ;;
        5)
            local images_dir="${BUILD_OUTPUT_DIR}/images"
            case "${BOOT_MEDIA}" in
                emmc)
                    [[ -f "${images_dir}/$(image_name_for_media emmc)" ]]
                    ;;
                sd)
                    [[ -f "${images_dir}/$(image_name_for_media sd)" ]]
                    ;;
                both)
                    [[ -f "${images_dir}/$(image_name_for_media emmc)" ]] &&
                    [[ -f "${images_dir}/$(image_name_for_media sd)" ]]
                    ;;
            esac
            ;;
    esac
}

# Main build process
main() {
    log_info "========================================="
    log_info "Mini Distribution Build"
    log_info "========================================="
    log_info "Project root: ${PROJECT_ROOT}"
    log_info "Build output: ${BUILD_OUTPUT_DIR}"
    log_info "Cross compiler: ${CROSS_COMPILE}gcc"
    log_info "Kernel track: ${KERNEL_TRACK}"
    log_info "Boot media: ${BOOT_MEDIA}"
    log_info "========================================="
    log_info ""

    validate_boot_media

    # Determine which stages to run
    local stages=()
    if [[ -n "${SPECIFIC_STAGE}" ]]; then
        if [[ "${SPECIFIC_STAGE}" =~ ^[1-5]$ ]]; then
            stages=("${SPECIFIC_STAGE}")
            log_info "Running stage ${SPECIFIC_STAGE} only"
        else
            log_error "Invalid stage number: ${SPECIFIC_STAGE} (must be 1-5)"
            exit 1
        fi
    else
        stages=(1 2 3 4 5)
        log_info "Running all stages (1-5)"
    fi
    log_info ""

    # Create build output directory
    # If release-latest exists, handle based on mode
    # Note: Stage 4 should not clear the folder, as it depends on previous stages
    if [[ -d "${BUILD_OUTPUT_DIR}" ]]; then
        if [[ ${CONTINUE_BUILD} -eq 1 ]]; then
            log_info "Continuing from existing build: ${BUILD_OUTPUT_DIR}"
        elif [[ "${SPECIFIC_STAGE}" != "4" && "${SPECIFIC_STAGE}" != "5" ]]; then
            local datetime=$(date +%Y%m%d-%H%M%S)
            local archive_dir="${PROJECT_ROOT}/out/release-${datetime}"
            log_info "Archiving existing ${BUILD_OUTPUT_DIR} -> ${archive_dir}"
            mv "${BUILD_OUTPUT_DIR}" "${archive_dir}"
        fi
    fi
    mkdir -p "${BUILD_OUTPUT_DIR}"

    # Run stages
    for stage in "${stages[@]}"; do
        if [[ ${CONTINUE_BUILD} -eq 1 ]] && is_stage_completed "${stage}"; then
            log_info "Skipping stage ${stage} (already completed)"
            continue
        fi

        case "${stage}" in
            1) stage_1_uboot ;;
            2) stage_2_linux ;;
            3) stage_3_busybox ;;
            4) stage_4_rootfs ;;
            5) stage_5_image ;;
        esac
        echo ""
    done

    # Create convenience symlinks
    create_symlinks
    echo ""

    # Show summary
    show_summary

    log_info "========================================="
    log_info "Build completed successfully!"
    log_info "========================================="
}

main "$@"
