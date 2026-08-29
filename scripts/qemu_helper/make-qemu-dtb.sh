#!/bin/bash
#
# make-qemu-dtb.sh - Build the DTB QEMU boots: the REAL board dtb + U-Boot fixups
#
# Usage: make-qemu-dtb.sh [OPTIONS]
#
# Options:
#   --output=PATH   Output dtb path (default: out/qemu/imx6ull-aes.dtb)
#   -h, --help      Show this help message
#
# Equivalence rule: QEMU boots the very same device tree the real board
# does — imx6ull-aes.dts from the kernel tree, byte-for-byte, no variant.
# The only edits are the ones U-Boot makes at boot time before bootz:
#
#   1. local-mac-address on both fec nodes (U-Boot's "ethaddr" fdt fixup).
#      Without it the kernel's of_get_mac_address() waits forever on an
#      nvmem cell and both FECs sit in deferred-probe limbo.
#
# Those edits are applied with fdtput to the compiled blob — exactly where
# a bootloader would apply them — so the dts/dtsi stay single-source and
# anything verified in QEMU holds for the real board (and vice versa).
#
# Environment variables:
#   PROJECT_ROOT   Project root directory (auto-detected if not set)
#   LINUX_SRC      Kernel source tree with the board patch applied
#                  (default: third_party/linux_mainline)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
LINUX_SRC="${LINUX_SRC:-${PROJECT_ROOT}/third_party/linux_mainline}"

DEFAULT_OUTPUT="${PROJECT_ROOT}/out/qemu/imx6ull-aes.dtb"

# U-Boot-equivalent MAC addresses (would come from ethaddr/eth1addr env)
FEC1_MAC="00 11 22 33 44 01"
FEC2_MAC="00 11 22 33 44 02"

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

DTS="${LINUX_SRC}/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dts"
OUT_BUILD="${PROJECT_ROOT}/out/mainline/linux"
DTC="${OUT_BUILD}/scripts/dtc/dtc"
[[ -f "${DTS}" ]] || die "board dts not found: ${DTS} (is the submodule initialized + patch applied?)"
[[ -x "${DTC}" ]] || die "kernel dtc not built at ${DTC}: run build-mainline-linux.sh once first"
command -v fdtput >/dev/null || die "fdtput not found (apt install device-tree-compiler)"

mkdir -p "$(dirname "${OUTPUT}")"

log "compiling the REAL board dts: ${DTS}"
DTS_SRC_DIR="${LINUX_SRC}/arch/arm/boot/dts"
DTS_IMX_DIR="${DTS_SRC_DIR}/nxp/imx"
PP="${OUTPUT%.dtb}.pp.dts"

rm -f "${OUTPUT}" "${PP}"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
    -I "${DTS_IMX_DIR}" -I "${DTS_SRC_DIR}" -I "${DTS_SRC_DIR}/include" \
    -I "${LINUX_SRC}/include" \
    -I "${OUT_BUILD}/arch/arm/boot/dts" \
    -o "${PP}" "${DTS}" || die "cpp preprocessing failed"

# NOTE: judge dtc by ITS exit code — piping into `grep -v WARNING` would
# turn a perfectly clean compile (all lines filtered) into a fake failure.
set +e
"${DTC}" \
    -i "${DTS_SRC_DIR}" \
    -@ -Wno-unit_address_vs_reg \
    -o "${OUTPUT}" "${PP}" 2>&1 | grep -v '^WARNING'
DTC_RC=${PIPESTATUS[0]}
set -e
[[ "${DTC_RC}" -eq 0 ]] || die "dtc failed (rc=${DTC_RC})"
rm -f "${PP}"

# --- bootloader fixups (the only place QEMU boot differs from netboot) -----
log "applying U-Boot-equivalent fixups (local-mac-address)"
fdtput -t bx "${OUTPUT}" /soc/bus@2000000/ethernet@20b4000 local-mac-address ${FEC1_MAC}
fdtput -t bx "${OUTPUT}" /soc/bus@2100000/ethernet@2188000 local-mac-address ${FEC2_MAC}

[[ -f "${OUTPUT}" ]] || die "dtb missing after build"
log "done: ${OUTPUT} (real board tree + bootloader MAC fixup, nothing else)"
log "boot it with scripts/qemu_helper/run-qemu.sh (picked up automatically)"
