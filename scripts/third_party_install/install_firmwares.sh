#!/bin/bash
#
# i.MX Firmware Installation Script for RootFS
#
# This script downloads and installs i.MX6 firmware files to the root filesystem.
# Currently installs:
#   - sdma-imx6q.bin (SDMA firmware for i.MX6 Quad)
#
# Environment variables:
#   ROOTFS_DIR  - Path to the root filesystem (provided by main script)
#   PROJECT_ROOT - Path to the project root (provided by main script)
#
# Usage:
#   This script is automatically executed by varified_rootfs_ok.sh
#   Or run manually: ROOTFS_DIR=rootfs/nfs ./install_firmwares.sh
#

set -e

# IMXFORGE_VERBOSE: 0=正常进度, 1=详细输出
: "${IMXFORGE_VERBOSE:=0}"
if [[ "$IMXFORGE_VERBOSE" == "1" ]]; then
    WGET_ARGS="-v"
else
    WGET_ARGS="--progress=bar:force:noscroll"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[install_firmwares]${NC} $1"; }
log_error() { echo -e "${RED}[install_firmwares]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[install_firmwares]${NC} $1"; }

# Default rootfs directory (for standalone execution)
: "${ROOTFS_DIR:=../rootfs/nfs}"

# Firmware configuration
FIRMWARE_BASE_URL="https://github.com/armbian/firmware/raw/master"
FIRMWARE_DEST_DIR="${ROOTFS_DIR}/lib/firmware/imx/sdma"

# Firmware files to install
FIRMWARE_FILES=(
    "imx/sdma/sdma-imx6q.bin"
)

log_info "Installing i.MX firmware files to: ${ROOTFS_DIR}"

# Check if rootfs directory exists
if [[ ! -d "$ROOTFS_DIR" ]]; then
    log_error "Rootfs directory not found: ${ROOTFS_DIR}"
    exit 1
fi

# Create target directory
mkdir -p "$FIRMWARE_DEST_DIR"

# Download firmware files
log_info "Downloading firmware files..."

for fw_rel_path in "${FIRMWARE_FILES[@]}"; do
    fw_file=$(basename "$fw_rel_path")
    fw_url="${FIRMWARE_BASE_URL}/${fw_rel_path}"
    fw_dest="${FIRMWARE_DEST_DIR}/${fw_file}"

    # Check if already exists
    if [[ -f "$fw_dest" ]]; then
        log_info "  ✓ Already exists: ${fw_file}"
        continue
    fi

    # Download
    log_info "  Downloading: ${fw_file}"
    if wget ${WGET_ARGS} -O "$fw_dest" "$fw_url"; then
        log_info "    ✓ Installed: ${fw_file}"
    else
        log_error "    ✗ Failed to download: ${fw_file}"
        rm -f "$fw_dest"
        exit 1
    fi
done

# Show summary
FW_COUNT=$(find "${FIRMWARE_DEST_DIR}" -type f -name "*.bin" 2>/dev/null | wc -l)

log_info "Firmware installation complete!"
log_info "  Installed ${FW_COUNT} firmware file(s) to ${FIRMWARE_DEST_DIR}"
log_info ""
log_info "Installed firmware files:"
find "${FIRMWARE_DEST_DIR}" -type f -name "*.bin" -exec basename {} \; 2>/dev/null | while read -r fw; do
    log_info "  - ${fw}"
done
