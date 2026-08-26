#!/bin/bash
#
# make-qemu-dtb.sh - Compile the QEMU variant board DTB
#
# Usage: make-qemu-dtb.sh [OPTIONS]
#
# Options:
#   --output=PATH   Output dtb path (default: out/qemu/imx6ull-aes-qemu.dtb)
#   -h, --help      Show this help message
#
# Compiles scripts/qemu_helper/imx6ull-aes-qemu.dts against the kernel's
# include tree (it #includes imx6ull.dtsi + imx6ull-aes.dtsi, so the kernel
# source tree must carry our applied board patch). Uses the kernel's own
# scripts/dtc wrapper so include resolution matches the kernel build.
#
# Environment variables:
#   PROJECT_ROOT   Project root directory (auto-detected if not set)
#   LINUX_SRC      Kernel source tree with the board patch applied
#                  (default: third_party/linux_mainline)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
LINUX_SRC="${LINUX_SRC:-${PROJECT_ROOT}/third_party/linux_mainline}"

DEFAULT_OUTPUT="${PROJECT_ROOT}/out/qemu/imx6ull-aes-qemu.dtb"

OUTPUT=""

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# //g; s/^#//g'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output=*)  OUTPUT="${1#*=}" ;;
        -h|--help)   usage ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            ;;
    esac
    shift
done

OUTPUT="${OUTPUT:-${DEFAULT_OUTPUT}}"

log()  { echo "[make-qemu-dtb] $*" >&2; }
die()  { echo "[make-qemu-dtb] error: $*" >&2; exit 1; }

DTS="${SCRIPT_DIR}/imx6ull-aes-qemu.dts"
OUT_BUILD="${PROJECT_ROOT}/out/mainline/linux"
DTC="${OUT_BUILD}/scripts/dtc/dtc"
[[ -f "${DTS}" ]] || die "dts not found: ${DTS}"
[[ -d "${LINUX_SRC}/arch/arm/boot/dts" ]] || die "kernel dts tree not found: ${LINUX_SRC} (is the submodule initialized + patch applied?)"
[[ -x "${DTC}" ]] || die "kernel dtc not built at ${DTC}: run build-mainline-linux.sh once first"

mkdir -p "$(dirname "${OUTPUT}")"

log "compiling ${DTS}"
log "  includes from ${LINUX_SRC}/arch/arm/boot/dts"

# The kernel build runs cpp over dts files (#include handling); dtc itself
# does not. Mirror scripts/Makefile.lib: cpp -x assembler-with-cpp, then dtc.
# i.MX dtsi files live in the nxp/imx/ subdirectory.
DTS_SRC_DIR="${LINUX_SRC}/arch/arm/boot/dts"
DTS_IMX_DIR="${DTS_SRC_DIR}/nxp/imx"
PP="${OUTPUT%.dtb}.pp.dts"

rm -f "${OUTPUT}" "${PP}"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
    -I "${DTS_IMX_DIR}" -I "${DTS_SRC_DIR}" -I "${DTS_SRC_DIR}/include" \
    -I "${LINUX_SRC}/include" \
    -I "${OUT_BUILD}/arch/arm/boot/dts" \
    -o "${PP}" "${DTS}" || die "cpp preprocessing failed"

if ! "${DTC}" \
    -i "${DTS_SRC_DIR}" \
    -@ -Wno-unit_address_vs_reg \
    -o "${OUTPUT}" "${PP}" 2>&1 | grep -v '^WARNING'; then
    die "dtc failed"
fi
rm -f "${PP}"

[[ -f "${OUTPUT}" ]] || die "dtc produced no output"
log "done: ${OUTPUT}"
log "boot it with scripts/qemu_helper/run-qemu.sh (picked up automatically)"
