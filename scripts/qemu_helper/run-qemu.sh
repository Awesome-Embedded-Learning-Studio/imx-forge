#!/bin/bash
#
# run-qemu.sh - Boot the AES board in QEMU (mcimx6ul-evk machine)
#
# Usage: run-qemu.sh [OPTIONS]
#
# Options:
#   --kernel=PATH     zImage (default: out/mainline/linux/arch/arm/boot/zImage)
#   --dtb=PATH        Device tree blob (default: out/qemu/imx6ull-aes.dtb —
#                     the REAL board dtb with U-Boot-equivalent MAC fixups;
#                     rebuilt automatically, see --no-build)
#   --rootfs-img=PATH ext4 rootfs image (default: out/qemu/rootfs.ext4,
#                     rebuilt automatically when the rootfs tree changed)
#   --append=ARGS     Extra kernel cmdline appended to the default bootargs
#   --display=TYPE    Show the LCD in a host window instead of headless:
#                     gtk (WSLg/desktop) or vnc. Console stays on this
#                     terminal (Ctrl-A C still switches to the monitor).
#   --no-build        Skip the automatic dtb/rootfs-image rebuild below
#   --smoke           Non-interactive boot test: capture UART to log, assert
#                     boot reaches the login prompt, exit 0/1 accordingly.
#                     Default expectation "buildroot login:" can be overridden
#                     with --expect="PATTERN" (grep -E, may repeat).
#   --expect=PATTERN  (with --smoke) grep -E pattern the UART log must contain
#   --timeout=SEC     (with --smoke) give up after SEC seconds (default 180)
#   --log=PATH        (with --smoke) UART log path (default: out/qemu/uart.log)
#   -h, --help        Show this help message
#
# Boot path: direct kernel boot (-kernel zImage -dtb). This is the upstream-
# documented path that works on stock QEMU (>= 5.x, tested with 8.2.2): no
# boot-ROM/SPL emulation exists for this machine, so U-Boot images with IVT
# headers (u-boot-dtb.imx) cannot be booted via -bios. The U-Boot chain
# enablement series (Bin Meng, 2026-08) is still under upstream review and
# NOT part of any release yet; revisit with QEMU >= 11.2 (~2026-12).
#
# QEMU binary selection: the self-built 11.1 (scripts/build_helper/
# build-qemu.sh — eLCDIF display model, FlexCAN, MMDC/OCOTP/QSPI/USBMISC
# stubs) is used when present; otherwise the system qemu-system-arm
# (8.2 on Ubuntu 24.04: no LCDIF, several address holes) with a warning.
#
# The SD card is attached to USDHC2 (if=sd,index=1) => guest /dev/mmcblk1.
# The rootfs image has no partition table, so root=/dev/mmcblk1 (whole card).
#
# Auto-rebuild (default on, --no-build to skip): stale artifacts are the
# classic footgun here — editing imx6ull-aes.dtsi or re-running the buildroot
# build silently boots the old dtb/rootfs. Before starting QEMU this script
# refreshes, in dependency order:
#   1. dtb:          recompiles whenever the real board dts or any dtsi it
#                    includes is newer than out/qemu/imx6ull-aes.dtb
#   2. rootfs image: rebuilds whenever the rootfs tree changed after the
#                    image was created (find -newer, content changes only —
#                    mtimes inside the tree are compared, not just the dir)
# Only the default paths are managed this way; explicit --dtb/--rootfs-img
# overrides are used verbatim and never rebuilt.
#
# Networking: -nic user. On this machine QEMU wires user netdevs to the fec
# controllers itself (qemu_configure_nic_device); fec2 is the one with a PHY.
# Guest DHCP gets 10.0.2.15 with host-forwarding available via QEMU_NET_EXTRA.
#
# Upstream models what we use: UART1 (console), USDHC2 (rootfs), FEC2 (net),
# GIC/CCM/GPCv2/SNVS/GPIO. Devices absent in QEMU (PWM/ADC/SAI/GT9147/FlexCAN/
# SDMA...) probe-fail or defer with "unimplemented" guest errors — expected
# console noise, not fatal.
#
# Environment variables:
#   PROJECT_ROOT    Project root directory (auto-detected if not set)
#   QEMU_NET_EXTRA  Extra -nic/-netdev options appended verbatim (e.g.
#                   hostfwd=tcp::5022-:22 with -nic user)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

MAINLINE_OUT="${PROJECT_ROOT}/out/mainline/linux"
DEFAULT_KERNEL="${MAINLINE_OUT}/arch/arm/boot/zImage"
# The REAL board dtb (same tree the hardware boots), compiled by
# make-qemu-dtb.sh with U-Boot-equivalent MAC fixups applied to the blob.
# Single-source equivalence: anything verified here holds on hardware.
DEFAULT_DTB="${PROJECT_ROOT}/out/qemu/imx6ull-aes.dtb"
DEFAULT_ROOTFS_IMG="${PROJECT_ROOT}/out/qemu/rootfs.ext4"
DEFAULT_LOG="${PROJECT_ROOT}/out/qemu/uart.log"

KERNEL=""
DISPLAY_TYPE=""
DTB=""
DTB_SET=0
ROOTFS_IMG=""
ROOTFS_SET=0
EXTRA_APPEND=""
SMOKE=0
NO_BUILD=0
TIMEOUT=180
LOG_PATH=""
EXPECTS=()

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# //g; s/^#//g'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel=*)      KERNEL="${1#*=}" ;;
        --dtb=*)         DTB="${1#*=}"; DTB_SET=1 ;;
        --rootfs-img=*)  ROOTFS_IMG="${1#*=}"; ROOTFS_SET=1 ;;
        --append=*)      EXTRA_APPEND="${EXTRA_APPEND:+${EXTRA_APPEND} }${1#*=}" ;;
        --display=*)    DISPLAY_TYPE="${1#*=}" ;;
        --no-build)      NO_BUILD=1 ;;
        --smoke)         SMOKE=1 ;;
        --expect=*)      EXPECTS+=("${1#*=}") ;;
        --timeout=*)     TIMEOUT="${1#*=}" ;;
        --log=*)         LOG_PATH="${1#*=}" ;;
        -h|--help)       usage ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            ;;
    esac
    shift
done

KERNEL="${KERNEL:-${DEFAULT_KERNEL}}"
DTB="${DTB:-${DEFAULT_DTB}}"
ROOTFS_IMG="${ROOTFS_IMG:-${DEFAULT_ROOTFS_IMG}}"
LOG_PATH="${LOG_PATH:-${DEFAULT_LOG}}"

log()  { echo "[run-qemu] $*"; }
die()  { echo "[run-qemu] error: $*" >&2; exit 1; }

# --- auto-rebuild stale artifacts (default paths only) ----------------------
rebuild_dtb_if_stale() {
    local imx_dtsi_dir="${PROJECT_ROOT}/third_party/linux_mainline/arch/arm/boot/dts/nxp/imx"

    if [[ ! -f "${DTB}" ]]; then
        log "dtb missing, building: ${DTB}"
        "${SCRIPT_DIR}/make-qemu-dtb.sh" || die "make-qemu-dtb.sh failed"
        return
    fi

    # the real board dts or any dtsi it includes newer than our dtb?
    local newer
    newer="$(find "${imx_dtsi_dir}" \
        \( -name 'imx6ull-aes*' -o -name 'imx6ull.dtsi' -o -name 'imx6ul.dtsi' \
        -o -name 'imx6ull-evk.dtsi' \) \
        -newer "${DTB}" -print -quit 2>/dev/null)"
    if [[ -n "${newer}" ]]; then
        log "dtb stale (newer: ${newer#"${PROJECT_ROOT}/"}), rebuilding"
        "${SCRIPT_DIR}/make-qemu-dtb.sh" || die "make-qemu-dtb.sh failed"
    fi
}

rebuild_rootfs_if_stale() {
    local tree="${PROJECT_ROOT}/out/release-latest/rootfs"

    if [[ ! -f "${ROOTFS_IMG}" ]]; then
        log "rootfs image missing, building: ${ROOTFS_IMG}"
        "${SCRIPT_DIR}/make-rootfs-img.sh" || die "make-rootfs-img.sh failed"
        return
    fi
    [[ -d "${tree}" ]] || return 0

    # content inside the tree newer than the image? (touch on the top dir is
    # not enough — buildroot rewrites files in place)
    local newer
    newer="$(find "${tree}" -newer "${ROOTFS_IMG}" -print -quit 2>/dev/null)"
    if [[ -n "${newer}" ]]; then
        log "rootfs tree changed (newer: ${newer#"${PROJECT_ROOT}/"}), rebuilding image"
        "${SCRIPT_DIR}/make-rootfs-img.sh" || die "make-rootfs-img.sh failed"
    fi
}

if [[ "${NO_BUILD}" -eq 0 ]]; then
    [[ "${DTB_SET}" -eq 0 ]] && rebuild_dtb_if_stale
    [[ "${ROOTFS_SET}" -eq 0 ]] && rebuild_rootfs_if_stale
fi

QEMU_BIN=""
SELF_BUILT="${PROJECT_ROOT}/out/qemu/build/qemu-system-arm"
if [[ -x "${SELF_BUILT}" ]]; then
    QEMU_BIN="${SELF_BUILT}"
elif command -v qemu-system-arm >/dev/null; then
    QEMU_BIN="$(command -v qemu-system-arm)"
    log "WARNING: system ${QEMU_BIN} ($(${QEMU_BIN} --version | head -1 | awk '{print $4}')): no eLCDIF model, MMDC/OCOTP/QSPI/USBMISC are address holes — run scripts/build_helper/build-qemu.sh for the full experience"
else
    die "qemu-system-arm not found (apt install qemu-system-arm, or run build-qemu.sh)"
fi

[[ -f "${KERNEL}" ]]     || die "kernel not found: ${KERNEL} (run build-mainline-linux.sh)"
[[ -f "${DTB}" ]]        || die "dtb not found: ${DTB}"
[[ -f "${ROOTFS_IMG}" ]] || die "rootfs image not found: ${ROOTFS_IMG} (run make-rootfs-img.sh)"

BOOTARGS="console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw ${EXTRA_APPEND}"

QEMU_ARGS=(
    -machine mcimx6ul-evk
    -m 512M
    -kernel "${KERNEL}"
    -dtb "${DTB}"
    -append "${BOOTARGS}"
    -drive "file=${ROOTFS_IMG},if=sd,index=1,format=raw"
    # slirp's built-in TFTP server shares ~/tftp with the guest (10.0.2.2),
    # same directory the real board netboots from (copy_to_tftp.sh)
    -nic user,tftp="${HOME}/tftp"
)
if [[ -n "${QEMU_NET_EXTRA:-}" ]]; then
    # shellcheck disable=SC2206
    QEMU_ARGS+=(${QEMU_NET_EXTRA})
fi

# --- interactive run --------------------------------------------------------
if [[ "${SMOKE}" -eq 0 ]]; then
    log "starting QEMU (interactive, Ctrl-A X to quit)"
    log "machine: mcimx6ul-evk  memory: 512M  console: ttymxc0"
    log "bootargs: ${BOOTARGS}"
    if [[ -n "${DISPLAY_TYPE}" ]]; then
        log "LCD window: -display ${DISPLAY_TYPE} (eLCDIF 1024x600 panel)"
        exec "${QEMU_BIN}" "${QEMU_ARGS[@]}"             -display "${DISPLAY_TYPE}" -serial mon:stdio
    fi
    exec "${QEMU_BIN}" "${QEMU_ARGS[@]}" -nographic
fi

# --- smoke test --------------------------------------------------------------
if [[ ${#EXPECTS[@]} -eq 0 ]]; then
    EXPECTS=("buildroot login:")
fi

mkdir -p "$(dirname "${LOG_PATH}")"

log "smoke test: timeout ${TIMEOUT}s, expecting: ${EXPECTS[*]}"
set +e
timeout --foreground "${TIMEOUT}" "${QEMU_BIN}" "${QEMU_ARGS[@]}" \
    -nographic -no-reboot >"${LOG_PATH}" 2>&1
QEMU_RC=$?
set -e

# timeout(1) exits 124 on timeout; QEMU killed by our timeout is the normal
# smoke-test end (a successful boot idles at the login prompt forever).
case "${QEMU_RC}" in
    0|124) ;;
    *) die "QEMU exited with rc=${QEMU_RC}, see ${LOG_PATH}" ;;
esac

FAILED=0
for pat in "${EXPECTS[@]}"; do
    if grep -qE -- "${pat}" "${LOG_PATH}"; then
        log "PASS: matched '${pat}'"
    else
        log "FAIL: pattern not found: '${pat}'"
        FAILED=1
    fi
done

if [[ "${FAILED}" -eq 0 ]]; then
    log "smoke test PASS (log: ${LOG_PATH})"
    exit 0
fi

log "last 40 lines of UART log:"
tail -n 40 "${LOG_PATH}" >&2 || true
exit 1
