#!/bin/bash
#
# Build a bootable i.MX6ULL SD/eMMC image from a release directory.
#
# Default input/output layout:
#   out/release-latest/
#     uboot/u-boot-dtb.imx
#     linux/arch/arm/boot/zImage
#     linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
#     rootfs/
#     images/imx6ull-aes-emmc.img
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT_LIB_DIR="${PROJECT_ROOT}/scripts/lib"

if [[ -f "${SCRIPT_LIB_DIR}/logging.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging.sh"
else
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warn() { echo "[WARN] $1"; }
    log_cmd() { echo "[CMD] $1"; }
fi

RELEASE_DIR="${PROJECT_ROOT}/out/release-latest"
DEVICE_TREE="${DEFAULT_DEVICE_TREE:-imx6ull-aes}"
IMAGE_NAME=""
BOOT_MEDIA="${DEFAULT_BOOT_MEDIA:-emmc}"
UBOOT_MMC_DEV=""
LINUX_ROOT_DEV=""
BOOT_SIZE_MB=64
ROOTFS_SIZE_MB=""
FIXED_IMAGE_SIZE_MB="${DEFAULT_IMAGE_SIZE_MB:-}"
UBOOT_OFFSET_KB=1
BOOT_START_MB=16
KEEP_WORKDIR=0
WORK_DIR=""

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --release-dir=PATH      Release directory containing uboot/linux/rootfs
                          (default: out/release-latest)
  --device-tree=NAME      Linux DTB name without .dtb, or an explicit .dtb path
                          (default: imx6ull-aes)
  --boot-media=sd|emmc    Target boot media; controls U-Boot mmc dev and root device
                          (default: emmc, or DEFAULT_BOOT_MEDIA)
  --image-name=NAME       Output image file name
                          (default: <dtb>-<boot-media>.img)
  --boot-size-mb=N        Boot partition size in MiB (default: 64)
  --rootfs-size-mb=N      Rootfs partition size in MiB (default: auto)
  --image-size-mb=N       Final image size in MiB; remaining space is used by rootfs
                          (default: auto, or DEFAULT_IMAGE_SIZE_MB)
  --keep-workdir          Keep temporary filesystem images for debugging
  --help, -h              Show this help message

Examples:
  $0
  $0 --release-dir=out/release-latest
  $0 --release-dir=out/release-20260608-121544 --device-tree=imx6ull-aes
  $0 --boot-media=emmc
  $0 --boot-media=sd
  $0 --image-size-mb=1024
  DEFAULT_IMAGE_SIZE_MB=2048 $0
  DEFAULT_DEVICE_TREE=imx6ull-aes DEFAULT_BOOT_MEDIA=sd $0

Output:
  The generated image is written to <release-dir>/images/.
EOF
}

die() {
    log_error "$1"
    exit 1
}

cleanup_workdir() {
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
}

abs_path() {
    local path="$1"
    if [[ "${path}" = /* ]]; then
        realpath -m "${path}"
    else
        realpath -m "${PROJECT_ROOT}/${path}"
    fi
}

require_tool() {
    local tool="$1"
    command -v "${tool}" >/dev/null 2>&1 || die "Required tool not found: ${tool}"
}

stat_size() {
    local path="$1"
    stat -c%s "${path}" 2>/dev/null || stat -f%z "${path}" 2>/dev/null
}

ceil_div() {
    local value="$1"
    local divisor="$2"
    echo $(((value + divisor - 1) / divisor))
}

mb_to_sectors() {
    local mb="$1"
    echo $((mb * 1024 * 1024 / 512))
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release-dir=*)
                RELEASE_DIR="${1#*=}"
                ;;
            --release-dir)
                shift
                [[ $# -gt 0 ]] || die "--release-dir requires a value"
                RELEASE_DIR="$1"
                ;;
            --device-tree=*)
                DEVICE_TREE="${1#*=}"
                ;;
            --device-tree)
                shift
                [[ $# -gt 0 ]] || die "--device-tree requires a value"
                DEVICE_TREE="$1"
                ;;
            --boot-media=*)
                BOOT_MEDIA="${1#*=}"
                ;;
            --boot-media)
                shift
                [[ $# -gt 0 ]] || die "--boot-media requires a value"
                BOOT_MEDIA="$1"
                ;;
            --image-name=*)
                IMAGE_NAME="${1#*=}"
                ;;
            --image-name)
                shift
                [[ $# -gt 0 ]] || die "--image-name requires a value"
                IMAGE_NAME="$1"
                ;;
            --boot-size-mb=*)
                BOOT_SIZE_MB="${1#*=}"
                ;;
            --boot-size-mb)
                shift
                [[ $# -gt 0 ]] || die "--boot-size-mb requires a value"
                BOOT_SIZE_MB="$1"
                ;;
            --rootfs-size-mb=*)
                ROOTFS_SIZE_MB="${1#*=}"
                ;;
            --rootfs-size-mb)
                shift
                [[ $# -gt 0 ]] || die "--rootfs-size-mb requires a value"
                ROOTFS_SIZE_MB="$1"
                ;;
            --image-size-mb=*)
                FIXED_IMAGE_SIZE_MB="${1#*=}"
                ;;
            --image-size-mb)
                shift
                [[ $# -gt 0 ]] || die "--image-size-mb requires a value"
                FIXED_IMAGE_SIZE_MB="$1"
                ;;
            --keep-workdir)
                KEEP_WORKDIR=1
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
}

validate_number() {
    local name="$1"
    local value="$2"
    [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} must be an integer: ${value}"
    [[ "${value}" -gt 0 ]] || die "${name} must be greater than 0"
}

resolve_boot_media() {
    case "${BOOT_MEDIA}" in
        sd)
            UBOOT_MMC_DEV=0
            LINUX_ROOT_DEV="/dev/mmcblk0p2"
            ;;
        emmc)
            UBOOT_MMC_DEV=1
            LINUX_ROOT_DEV="/dev/mmcblk1p2"
            ;;
        *)
            die "--boot-media must be either sd or emmc: ${BOOT_MEDIA}"
            ;;
    esac
}

resolve_artifacts() {
    RELEASE_DIR="$(abs_path "${RELEASE_DIR}")"

    [[ -d "${RELEASE_DIR}" ]] || die "Release directory not found: ${RELEASE_DIR}"

    UBOOT_IMAGE="${RELEASE_DIR}/uboot/u-boot-dtb.imx"
    KERNEL_IMAGE="${RELEASE_DIR}/linux/arch/arm/boot/zImage"
    ROOTFS_DIR="${RELEASE_DIR}/rootfs"

    if [[ "${DEVICE_TREE}" = /* || "${DEVICE_TREE}" == *.dtb ]]; then
        DTB_IMAGE="$(abs_path "${DEVICE_TREE}")"
        DTB_NAME="$(basename "${DTB_IMAGE}" .dtb)"
    else
        DTB_NAME="${DEVICE_TREE}"
        DTB_IMAGE="${RELEASE_DIR}/linux/arch/arm/boot/dts/nxp/imx/${DTB_NAME}.dtb"
    fi

    [[ -f "${UBOOT_IMAGE}" ]] || die "U-Boot image not found: ${UBOOT_IMAGE}"
    [[ -f "${KERNEL_IMAGE}" ]] || die "Kernel image not found: ${KERNEL_IMAGE}"
    [[ -f "${DTB_IMAGE}" ]] || die "DTB not found: ${DTB_IMAGE}"
    [[ -d "${ROOTFS_DIR}" ]] || die "Rootfs directory not found: ${ROOTFS_DIR}"
    [[ -f "${ROOTFS_DIR}/bin/busybox" ]] || log_warn "Rootfs does not contain bin/busybox: ${ROOTFS_DIR}"

    if [[ -z "${IMAGE_NAME}" ]]; then
        if [[ "${DTB_NAME}" == imx6ull* ]]; then
            IMAGE_NAME="${DTB_NAME}-${BOOT_MEDIA}.img"
        else
            IMAGE_NAME="imx6ull-${DTB_NAME}-${BOOT_MEDIA}.img"
        fi
    fi
    [[ "${IMAGE_NAME}" == *.img ]] || IMAGE_NAME="${IMAGE_NAME}.img"

    IMAGES_DIR="${RELEASE_DIR}/images"
    OUTPUT_IMAGE="${IMAGES_DIR}/${IMAGE_NAME}"
}

calculate_layout() {
    validate_number "--boot-size-mb" "${BOOT_SIZE_MB}"
    if [[ -n "${ROOTFS_SIZE_MB}" ]]; then
        validate_number "--rootfs-size-mb" "${ROOTFS_SIZE_MB}"
    fi
    if [[ -n "${FIXED_IMAGE_SIZE_MB}" ]]; then
        validate_number "--image-size-mb" "${FIXED_IMAGE_SIZE_MB}"
    fi
    if [[ -n "${ROOTFS_SIZE_MB}" && -n "${FIXED_IMAGE_SIZE_MB}" ]]; then
        die "Use either --rootfs-size-mb or --image-size-mb, not both"
    fi

    local kernel_bytes
    local dtb_bytes
    kernel_bytes="$(stat_size "${KERNEL_IMAGE}")"
    dtb_bytes="$(stat_size "${DTB_IMAGE}")"

    local boot_need_mb
    boot_need_mb="$(ceil_div "$((kernel_bytes + dtb_bytes + 8 * 1024 * 1024))" "$((1024 * 1024))")"
    if [[ "${BOOT_SIZE_MB}" -lt "${boot_need_mb}" ]]; then
        log_warn "Boot partition size increased from ${BOOT_SIZE_MB} MiB to ${boot_need_mb} MiB"
        BOOT_SIZE_MB="${boot_need_mb}"
    fi

    local rootfs_used_mb
    rootfs_used_mb="$(du -sm "${ROOTFS_DIR}" | awk '{print $1}')"

    if [[ -n "${FIXED_IMAGE_SIZE_MB}" ]]; then
        local min_image_mb=$((BOOT_START_MB + BOOT_SIZE_MB + rootfs_used_mb + 8))
        if [[ "${FIXED_IMAGE_SIZE_MB}" -lt "${min_image_mb}" ]]; then
            die "--image-size-mb (${FIXED_IMAGE_SIZE_MB}) is too small; need at least ${min_image_mb} MiB"
        fi

        IMAGE_SIZE_MB="${FIXED_IMAGE_SIZE_MB}"
        ROOTFS_SIZE_MB=$((IMAGE_SIZE_MB - BOOT_START_MB - BOOT_SIZE_MB - 8))
    elif [[ -z "${ROOTFS_SIZE_MB}" ]]; then
        ROOTFS_SIZE_MB=$((rootfs_used_mb + rootfs_used_mb / 4 + 64))
        if [[ "${ROOTFS_SIZE_MB}" -lt 128 ]]; then
            ROOTFS_SIZE_MB=128
        fi
    elif [[ "${ROOTFS_SIZE_MB}" -le "${rootfs_used_mb}" ]]; then
        die "--rootfs-size-mb (${ROOTFS_SIZE_MB}) must be larger than rootfs usage (${rootfs_used_mb} MiB)"
    fi

    BOOT_START_SECTOR="$(mb_to_sectors "${BOOT_START_MB}")"
    BOOT_SIZE_SECTORS="$(mb_to_sectors "${BOOT_SIZE_MB}")"
    ROOTFS_START_SECTOR=$((BOOT_START_SECTOR + BOOT_SIZE_SECTORS))
    ROOTFS_SIZE_SECTORS="$(mb_to_sectors "${ROOTFS_SIZE_MB}")"
    if [[ -z "${FIXED_IMAGE_SIZE_MB}" ]]; then
        IMAGE_SIZE_MB=$((BOOT_START_MB + BOOT_SIZE_MB + ROOTFS_SIZE_MB + 8))
    fi
}

create_boot_tree() {
    local boot_dir="$1"
    local dtb_file
    dtb_file="$(basename "${DTB_IMAGE}")"

    mkdir -p "${boot_dir}/boot"
    cp "${KERNEL_IMAGE}" "${boot_dir}/zImage"
    cp "${DTB_IMAGE}" "${boot_dir}/${dtb_file}"
    cp "${KERNEL_IMAGE}" "${boot_dir}/boot/zImage"
    cp "${DTB_IMAGE}" "${boot_dir}/boot/${dtb_file}"

    cat > "${boot_dir}/boot.cmd" << EOF
setenv bootargs console=ttymxc0,115200 root=${LINUX_ROOT_DEV} rootwait rw
ext4load mmc ${UBOOT_MMC_DEV}:1 \${loadaddr} /zImage
ext4load mmc ${UBOOT_MMC_DEV}:1 \${fdt_addr_r} /${dtb_file}
bootz \${loadaddr} - \${fdt_addr_r}
EOF
}

create_partition_fs() {
    local src_dir="$1"
    local label="$2"
    local size_mb="$3"
    local fs_image="$4"

    truncate -s "${size_mb}M" "${fs_image}"
    log_cmd "mke2fs -t ext4 -d ${src_dir} -L ${label} ${fs_image}"
    mke2fs -q -t ext4 -d "${src_dir}" -L "${label}" -m 0 -F "${fs_image}"
}

write_partition_table() {
    local image="$1"

    truncate -s "${IMAGE_SIZE_MB}M" "${image}"

    sfdisk --quiet --no-reread "${image}" << EOF
label: dos
unit: sectors

start=${BOOT_START_SECTOR}, size=${BOOT_SIZE_SECTORS}, type=83, bootable
start=${ROOTFS_START_SECTOR}, size=${ROOTFS_SIZE_SECTORS}, type=83
EOF
}

write_image_payloads() {
    local image="$1"
    local boot_fs="$2"
    local rootfs_fs="$3"

    log_cmd "dd U-Boot to ${image} at ${UBOOT_OFFSET_KB} KiB"
    dd if="${UBOOT_IMAGE}" of="${image}" bs=1K seek="${UBOOT_OFFSET_KB}" conv=notrunc status=none

    log_cmd "dd boot partition to sector ${BOOT_START_SECTOR}"
    dd if="${boot_fs}" of="${image}" bs=512 seek="${BOOT_START_SECTOR}" conv=notrunc status=none

    log_cmd "dd rootfs partition to sector ${ROOTFS_START_SECTOR}"
    dd if="${rootfs_fs}" of="${image}" bs=512 seek="${ROOTFS_START_SECTOR}" conv=notrunc status=none
}

write_manifest() {
    local manifest="$1"
    local sha_file="$2"
    local dtb_file
    dtb_file="$(basename "${DTB_IMAGE}")"

    cat > "${manifest}" << EOF
image=${OUTPUT_IMAGE}
release_dir=${RELEASE_DIR}
uboot=${UBOOT_IMAGE}
kernel=${KERNEL_IMAGE}
dtb=${DTB_IMAGE}
rootfs=${ROOTFS_DIR}
boot_media=${BOOT_MEDIA}
uboot_mmc_dev=${UBOOT_MMC_DEV}
linux_root_dev=${LINUX_ROOT_DEV}

layout:
  uboot_offset_kib=${UBOOT_OFFSET_KB}
  boot_partition_start_sector=${BOOT_START_SECTOR}
  boot_partition_size_mib=${BOOT_SIZE_MB}
  rootfs_partition_start_sector=${ROOTFS_START_SECTOR}
  rootfs_partition_size_mib=${ROOTFS_SIZE_MB}
  image_size_mib=${IMAGE_SIZE_MB}

boot_files:
  /zImage
  /${dtb_file}
  /boot/zImage
  /boot/${dtb_file}
  /boot.cmd

manual_uboot_boot:
  setenv bootargs console=ttymxc0,115200 root=${LINUX_ROOT_DEV} rootwait rw
  ext4load mmc ${UBOOT_MMC_DEV}:1 \${loadaddr} /zImage
  ext4load mmc ${UBOOT_MMC_DEV}:1 \${fdt_addr_r} /${dtb_file}
  bootz \${loadaddr} - \${fdt_addr_r}
EOF

    if command -v sha256sum >/dev/null 2>&1; then
        (cd "${IMAGES_DIR}" && sha256sum "$(basename "${OUTPUT_IMAGE}")") > "${sha_file}"
    fi
}

main() {
    parse_args "$@"

    require_tool realpath
    require_tool sfdisk
    require_tool mke2fs
    require_tool truncate
    require_tool dd
    require_tool du
    require_tool awk
    require_tool stat

    resolve_boot_media
    resolve_artifacts
    calculate_layout

    mkdir -p "${IMAGES_DIR}"
    WORK_DIR="$(mktemp -d "${PROJECT_ROOT}/out/imx6ull-image.XXXXXX")"
    if [[ "${KEEP_WORKDIR}" -eq 0 ]]; then
        trap cleanup_workdir EXIT
    else
        log_warn "Keeping temporary work directory: ${WORK_DIR}"
    fi

    local boot_dir="${WORK_DIR}/boot-tree"
    local boot_fs="${WORK_DIR}/boot.ext4"
    local rootfs_fs="${WORK_DIR}/rootfs.ext4"
    local tmp_image="${WORK_DIR}/${IMAGE_NAME}"
    local manifest="${OUTPUT_IMAGE}.manifest"
    local sha_file="${OUTPUT_IMAGE}.sha256"

    log_info "========================================="
    log_info "Building i.MX6ULL flash image"
    log_info "========================================="
    log_info "Release dir: ${RELEASE_DIR}"
    log_info "Output image: ${OUTPUT_IMAGE}"
    log_info "Boot media: ${BOOT_MEDIA} (U-Boot mmc ${UBOOT_MMC_DEV}, root ${LINUX_ROOT_DEV})"
    log_info "Device tree: ${DTB_NAME}"
    log_info "Boot partition: ${BOOT_SIZE_MB} MiB @ ${BOOT_START_MB} MiB"
    log_info "Rootfs partition: ${ROOTFS_SIZE_MB} MiB"
    log_info "Image size: ${IMAGE_SIZE_MB} MiB"
    log_info "========================================="

    create_boot_tree "${boot_dir}"
    create_partition_fs "${boot_dir}" "BOOT" "${BOOT_SIZE_MB}" "${boot_fs}"
    create_partition_fs "${ROOTFS_DIR}" "ROOTFS" "${ROOTFS_SIZE_MB}" "${rootfs_fs}"
    write_partition_table "${tmp_image}"
    write_image_payloads "${tmp_image}" "${boot_fs}" "${rootfs_fs}"

    mv "${tmp_image}" "${OUTPUT_IMAGE}"
    write_manifest "${manifest}" "${sha_file}"

    log_info "Image created: ${OUTPUT_IMAGE}"
    [[ -f "${sha_file}" ]] && log_info "SHA256: ${sha_file}"
    log_info "Manifest: ${manifest}"
}

main "$@"
