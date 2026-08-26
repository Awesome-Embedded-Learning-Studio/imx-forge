#!/bin/bash
#
# make-rootfs-img.sh - Build a QEMU-ready ext4 rootfs image from a directory tree
#
# Usage: make-rootfs-img.sh [OPTIONS]
#
# Options:
#   --rootfs-dir=DIR   Rootfs directory tree (default: out/release-latest/rootfs)
#   --output=PATH      Output image path (default: out/qemu/rootfs.ext4)
#   --size-mb=N        Image size in MiB, must be a power of two (default: 256)
#                      QEMU's SD model encodes capacity into the CSD register,
#                      which only supports power-of-two sizes — other sizes make
#                      the guest see a 0-byte card. Rootfs trees larger than the
#                      image fail at mke2fs time.
#   --append-size-mb=N Resize an existing image in place instead of rebuilding
#                      (handy when the tree grew between CI runs)
#   -h, --help         Show this help message
#
# The image is a single ext4 filesystem built directly from the directory tree
# (same mke2fs -d approach as scripts/image_builder/build_imx6ull_image.sh),
# without a partition table. It is attached as a raw SD card to QEMU:
#   -drive file=rootfs.ext4,if=sd,index=1,format=raw
# The guest sees it as /dev/mmcblk1 (USDHC2); with no partition table the
# filesystem spans the whole card, so root=/dev/mmcblk1.
#
# Environment variables:
#   PROJECT_ROOT   Project root directory (auto-detected if not set)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

DEFAULT_ROOTFS_DIR="${PROJECT_ROOT}/out/release-latest/rootfs"
DEFAULT_OUTPUT="${PROJECT_ROOT}/out/qemu/rootfs.ext4"
DEFAULT_SIZE_MB=256

ROOTFS_DIR=""
OUTPUT=""
SIZE_MB=""
RESIZE_MB=""

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# //g; s/^#//g'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rootfs-dir=*)  ROOTFS_DIR="${1#*=}" ;;
        --output=*)      OUTPUT="${1#*=}" ;;
        --size-mb=*)     SIZE_MB="${1#*=}" ;;
        --append-size-mb=*) RESIZE_MB="${1#*=}" ;;
        -h|--help)       usage ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            ;;
    esac
    shift
done

ROOTFS_DIR="${ROOTFS_DIR:-${DEFAULT_ROOTFS_DIR}}"
OUTPUT="${OUTPUT:-${DEFAULT_OUTPUT}}"
SIZE_MB="${SIZE_MB:-${DEFAULT_SIZE_MB}}"

log()  { echo "[make-rootfs-img] $*"; }
die()  { echo "[make-rootfs-img] error: $*" >&2; exit 1; }

is_power_of_two() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" != 0 && ("$1" & ("$1" - 1)) == 0 ))
}

# --- resize-only mode ------------------------------------------------------
if [[ -n "${RESIZE_MB}" ]]; then
    [[ -f "${OUTPUT}" ]] || die "--append-size-mb requires an existing image: ${OUTPUT}"
    is_power_of_two "${RESIZE_MB}" || die "size must be a power of two (got ${RESIZE_MB})"
    log "resizing ${OUTPUT} to ${RESIZE_MB} MiB"
    truncate -s "${RESIZE_MB}M" "${OUTPUT}"
    log "done: $(du -h "${OUTPUT}" | cut -f1) ${OUTPUT}"
    exit 0
fi

# --- full build -------------------------------------------------------------
[[ -d "${ROOTFS_DIR}" ]] || die "rootfs directory not found: ${ROOTFS_DIR}"
[[ -d "${ROOTFS_DIR}/etc" ]] || die "not a rootfs tree (no etc/): ${ROOTFS_DIR}"
command -v mke2fs >/dev/null || die "mke2fs not found (install e2fsprogs)"

is_power_of_two "${SIZE_MB}" || die "size must be a power of two (got ${SIZE_MB})"

mkdir -p "$(dirname "${OUTPUT}")"

log "building ext4 image from ${ROOTFS_DIR}"
truncate -s "${SIZE_MB}M" "${OUTPUT}"
mke2fs -q -t ext4 -d "${ROOTFS_DIR}" -L rootfs -m 0 -F "${OUTPUT}"

log "done: $(du -h "${OUTPUT}" | cut -f1) ${OUTPUT}"
log "attach in QEMU with:"
log "  -drive file=${OUTPUT},if=sd,index=1,format=raw   # guest: /dev/mmcblk1"
