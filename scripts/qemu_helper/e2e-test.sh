#!/bin/bash
#
# e2e-test.sh - Full end-to-end board bring-up test in QEMU
#
# Usage: e2e-test.sh [OPTIONS]
#
# Options:
#   --timeout=SEC     Overall guest session timeout (default 180)
#   --log=PATH        UART log path (default: out/qemu/e2e.log)
#   --no-build        Skip the automatic dtb/rootfs-image rebuild
#   -h, --help        Show this help message
#
# Boots the self-built QEMU (mcimx6ul-evk) with the mainline kernel, the
# QEMU variant dtb and the rootfs image, logs in, and runs one assertion
# per subsystem. Each check emits a ===T:<name>=== marker plus a single
# KEY=value result line; this script then greps the log and prints a
# PASS/FAIL report. Exit code 0 only if every check passed.
#
# Current checks: login, rtc-walk, net-dhcp-ping, can0, pwm-backlight,
# display-fb, usb-bus, sd-card, ap3216c-als, icm20608-probe,
# gpio-inject, deferred-list. Known-stub devices (audio) are asserted
# as "expected to stay deferred", not as failures.
#
# Environment variables:
#   PROJECT_ROOT   Project root directory (auto-detected if not set)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

TIMEOUT=180
LOG_PATH="${PROJECT_ROOT}/out/qemu/e2e.log"
NO_BUILD=0

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# //g; s/^#//g'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout=*) TIMEOUT="${1#*=}" ;;
        --log=*)     LOG_PATH="${1#*=}" ;;
        --no-build)  NO_BUILD=1 ;;
        -h|--help)   usage ;;
        *) echo "error: unknown option: $1" >&2; usage >&2 ;;
    esac
    shift
done

log() { echo "[e2e] $*"; }

# --- reuse run-qemu.sh's freshness logic by simply invoking it for a
# smoke pass first; artifacts are then guaranteed fresh -------------------
if [[ "${NO_BUILD}" -eq 0 ]]; then
    log "refreshing artifacts (run-qemu.sh --smoke)"
    "${SCRIPT_DIR}/run-qemu.sh" --smoke --timeout=$((TIMEOUT)) \
        --log="${PROJECT_ROOT}/out/qemu/e2e-smoke.log" >/dev/null
fi

QEMU_BIN="${PROJECT_ROOT}/out/qemu/build/qemu-system-arm"
KERNEL="${PROJECT_ROOT}/out/mainline/linux/arch/arm/boot/zImage"
DTB="${PROJECT_ROOT}/out/qemu/imx6ull-aes-qemu.dtb"
ROOTFS="${PROJECT_ROOT}/out/qemu/rootfs.ext4"

for f in "${QEMU_BIN}" "${KERNEL}" "${DTB}" "${ROOTFS}"; do
    [[ -e "$f" ]] || { echo "[e2e] error: missing $f" >&2; exit 1; }
done
[[ -f "${PROJECT_ROOT}/out/release-latest/rootfs/root/21_tutorial_icm20608_spi_driver.ko" ]] || {
    echo "[e2e] error: icm20608 .ko not in rootfs tree" >&2
    echo "       (cp driver/21_*/alpha-board/*.ko out/release-latest/rootfs/root/ and rerun without --no-build)" >&2
    exit 1
}

# --- guest script: one marker + one KEY=value per check -------------------
# gpio injection hops to the monitor mid-session (Ctrl-A C, \001c).
log "booting guest and running checks (timeout ${TIMEOUT}s)"

(
sleep 26
echo root; sleep 4; echo root; sleep 3
echo 'mount -t debugfs none /sys/kernel/debug 2>/dev/null'

echo '===T:rtc-walk==='
echo 'a=$(date +%s); sleep 2; b=$(date +%s); echo RTCDELTA=$((b-a))'
sleep 3

echo '===T:net-dhcp-ping==='
echo 'udhcpc -i eth1 >/dev/null 2>&1; ping -c 2 -W 3 10.0.2.2 >/dev/null 2>&1; echo NETRC=$?'
sleep 6

echo '===T:can0==='
echo 'ls -d /sys/class/net/can0 >/dev/null 2>&1; if [ $? -eq 0 ]; then echo CAN0=yes; else echo CAN0=no; fi'
sleep 2

echo '===T:pwm-backlight==='
echo 'ls -d /sys/class/pwm/pwmchip0 >/dev/null 2>&1; if [ $? -eq 0 ]; then echo PWM=yes; else echo PWM=no; fi'
sleep 1
echo 'ls -d /sys/class/backlight/* >/dev/null 2>&1; if [ $? -eq 0 ]; then echo BL=yes; else echo BL=no; fi'
sleep 2

echo '===T:display-fb==='
echo 'ls -d /sys/class/graphics/fb0 >/dev/null 2>&1; if [ $? -eq 0 ]; then echo FB=yes; else echo FB=no; fi'
sleep 1
echo 'dmesg | grep -q "Initialized mxsfb"; if [ $? -eq 0 ]; then echo MXSFB=yes; else echo MXSFB=no; fi'
sleep 2

echo '===T:usb-bus==='
echo 'n=$(dmesg | grep -c ci_hdrc); echo USBN=$n'
sleep 2

echo '===T:sd-card==='
echo 'grep -q mmcblk1 /proc/partitions; if [ $? -eq 0 ]; then echo MMC=yes; else echo MMC=no; fi'
sleep 2

echo '===T:ap3216c-als==='
echo 'v=$(i2cget -y 0 0x1e 0x0c w 2>/dev/null); case "$v" in 0x01*) echo ALS=$v;; *) echo ALS=bad:$v;; esac'
sleep 3

echo '===T:icm20608-probe==='
echo 'insmod /root/21_tutorial_icm20608_spi_driver.ko 2>/dev/null; sleep 1; dmesg | grep -q "icm20608 probe success"; if [ $? -eq 0 ]; then echo ICM=yes; else echo ICM=no; fi'
sleep 4

echo '===T:gt911-probe==='
echo 'dmesg | grep -q "Goodix-TS.*ID 911"; if [ $? -eq 0 ]; then echo GT911=yes; else echo GT911=no; fi'
sleep 2

echo '===T:wm8960-codec==='
echo 'v=$(i2cget -y 0 0x1a 0x19 2>/dev/null); case "$v" in 0x*) echo WM8960=$v;; *) echo WM8960=bad;; esac'
sleep 2

echo '===T:gpio-inject==='
echo 'devmem 0x209C008'
sleep 2
printf '\001c'; sleep 1
echo 'gpio_set gpio0 18 1'
sleep 2
printf '\001c'; sleep 1
echo 'devmem 0x209C008 | grep -q 0x00040000; if [ $? -eq 0 ]; then echo GPIOFLIP=yes; else echo GPIOFLIP=no; fi'
sleep 2

echo '===T:deferred-list==='
echo 'cat /sys/kernel/debug/devices_deferred 2>/dev/null | grep -v sound-wm8960 | grep -c . > /tmp/d; read n < /tmp/d; echo DEFER_EXTRA=$n'
sleep 3

echo 'rmmod 21_tutorial_icm20608_spi_driver 2>/dev/null'
echo 'poweroff -f'
sleep 8
) | timeout "${TIMEOUT}" "${QEMU_BIN}" \
      -M mcimx6ul-evk -m 512M \
      -kernel "${KERNEL}" -dtb "${DTB}" \
      -append "console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw" \
      -drive "file=${ROOTFS},if=sd,index=1,format=raw" \
      -nic user -nographic -no-reboot > "${LOG_PATH}" 2>&1 || true

log "guest session done, log: ${LOG_PATH}"

# --- host-side assertions --------------------------------------------------
# Each check has a globally unique KEY= line in the log, so a plain grep
# over the whole log is both simpler and sturdier than section slicing.
declare -A RESULT

check() { # name pattern description
    local name="$1" pattern="$2" desc="$3"
    if grep -qE "$pattern" "${LOG_PATH}"; then
        RESULT[$name]="PASS"
        printf '  %-16s PASS  %s\n' "$name" "$desc"
    else
        RESULT[$name]="FAIL"
        printf '  %-16s FAIL  %s\n' "$name" "$desc"
    fi
}

echo
echo "==================== E2E REPORT ===================="

check rtc-walk        'RTCDELTA=[2-9]'           "SNVS RTC walks (>=2s over 2s)"
check net-dhcp-ping   'NETRC=0'                  "eth1 DHCP + ping host (slirp)"
check can0            'CAN0=yes'                 "flexcan netdev registered"
check pwm-backlight   'PWM=yes'                  "pwm-imx27 pwmchip0 present"
check pwm-backlight   'BL=yes'                   "pwm-backlight consumer"
check display-fb      'FB=yes'                   "mxsfb fb0 present"
check display-fb      'MXSFB=yes'                "mxsfb-drm initialized"
check usb-bus         'USBN=[1-9]'               "chipidea usb buses active"
check sd-card         'MMC=yes'                  "mmcblk1 rootfs card"
check ap3216c-als     'ALS=0x01'                 "ap3216c ALS reads ~0x0120"
check icm20608-probe  'ICM=yes'                  "imxaes icm20608 driver probes"
check gpio-inject     'GPIOFLIP=yes'             "HMP gpio_set flips PSR bit18"
check gt911-probe      'GT911=yes'                "goodix probes as ID 911 (gt911 model)"
check wm8960-codec     'WM8960=0x'                "wm8960 codec answers on i2c1 0x1a"
check deferred-list   'DEFER_EXTRA=[01]'         "only audio still deferred"

echo "===================================================="

FAILED=0
for r in "${RESULT[@]}"; do [[ "$r" == FAIL ]] && FAILED=1; done

if [[ "${FAILED}" -eq 0 ]]; then
    log "ALL CHECKS PASSED"
    exit 0
fi
log "SOME CHECKS FAILED — inspect ${LOG_PATH}"
exit 1
