#!/bin/bash
#
# copy_to_tftp.sh - Copy kernel and DTB files to TFTP directory
#
# Usage: copy_to_tftp.sh [OPTIONS]
#
# Options:
#   --config=PATH     Path to config file (tftp.conf or tftp-<BOARD>.conf)
#   --kernel=PATH     Path to kernel file (overrides config)
#   --dtb=PATH        Path to DTB file (overrides config)
#   --rootfs=PATH     Path to rootfs image (optional, overrides config)
#   --uboot=PATH      Path to U-Boot image (optional, overrides config)
#   --tftp-path=PATH  TFTP directory (overrides config)
#   --list-configs    List available config files
#   -h, --help        Show this help message
#
# Config files are searched in the following order:
#   1. --config=PATH (if specified)
#   2. $(dirname $0)/tftp-${BOARD_NAME}.conf (default: tftp-imx6ull-aes.conf)
#   3. $PWD/tftp-${BOARD_NAME}.conf
#   4. $(dirname $0)/tftp.conf
#   5. $PWD/tftp.conf
#
# Environment variables:
#   BOARD_NAME    Board name for config lookup (default: "imx6ull-aes")
#   PROJECT_ROOT   Project root directory (auto-detected if not set)
#

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values (can be overridden by config file or command line)
DEFAULT_KERNEL="${PROJECT_ROOT}/out/linux/arch/arm/boot/zImage"
DEFAULT_DTB="${PROJECT_ROOT}/out/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb"
DEFAULT_TFTP_PATH="${HOME}/tftp"
DEFAULT_COPY_METHOD="auto"

# Initialize variables
KERNEL=""
DTB=""
ROOTFS=""
UBOOT=""
TFTP_PATH=""
COPY_METHOD=""
CONFIG_FILE=""
PRESERVE_NAMES=""
VERIFY_CHECKSUM=""
BOARD_NAME="${BOARD_NAME:-}"

# Print usage message
usage() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //g' | sed 's/^#//g'
    cat << EOF

Examples:
  # Use default config
  copy_to_tftp.sh

  # Use specific board config
  BOARD_NAME=imx6ull-aes copy_to_tftp.sh

  # Override kernel path
  copy_to_tftp.sh --kernel=out/linux/arch/arm/boot/zImage-custom

  # Use custom config file
  copy_to_tftp.sh --config=/path/to/custom.conf

  # List available configs
  copy_to_tftp.sh --list-configs
EOF
    exit 0
}

# List available config files
list_configs() {
    echo "Available TFTP config files:"
    echo "============================"
    find "$SCRIPT_DIR" -maxdepth 1 -name "tftp*.conf" -type f 2>/dev/null | while read -r f; do
        local name=$(basename "$f" .conf)
        if [[ "$name" == "tftp" ]]; then
            echo "  - $f (default)"
        else
            local board="${name#tftp-}"
            echo "  - $f (board: $board)"
        fi
    done

    # Also check PWD
    if [[ "$SCRIPT_DIR" != "$PWD" ]]; then
        find "$PWD" -maxdepth 1 -name "tftp*.conf" -type f 2>/dev/null | while read -r f; do
            local name=$(basename "$f" .conf)
            if [[ "$name" == "tftp" ]]; then
                echo "  - $f (default, in PWD)"
            else
                local board="${name#tftp-}"
                echo "  - $f (board: $board, in PWD)"
            fi
        done
    fi

    echo ""
    echo "Usage: copy_to_tftp.sh --config=<path>"
    echo "   or: BOARD_NAME=<name> copy_to_tftp.sh"
    exit 0
}

# Find and load config file
load_config() {
    local config_file=""
    local search_paths=()

    # Default to imx6ull-aes if BOARD_NAME not set
    BOARD_NAME="${BOARD_NAME:-imx6ull-aes}"

    # 1. Explicit --config parameter
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            config_file="$CONFIG_FILE"
        else
            echo "Warning: Config file '$CONFIG_FILE' not found"
        fi
    fi

    # 2. If not found, search for board-specific config
    if [[ -z "$config_file" ]]; then
        search_paths=(
            "$PWD/tftp-${BOARD_NAME}.conf"
            "$SCRIPT_DIR/tftp-${BOARD_NAME}.conf"
        )
        for path in "${search_paths[@]}"; do
            if [[ -f "$path" ]]; then
                config_file="$path"
                break
            fi
        done
    fi

    # 3. Fall back to default tftp.conf
    if [[ -z "$config_file" ]]; then
        search_paths=(
            "$PWD/tftp.conf"
            "$SCRIPT_DIR/tftp.conf"
        )
        for path in "${search_paths[@]}"; do
            if [[ -f "$path" ]]; then
                config_file="$path"
                break
            fi
        done
    fi

    # Load the config file if found
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        echo "Loading config: $config_file"
        # Set PROJECT_ROOT for the config file
        export PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

        # Source the config file
        # shellcheck source=/dev/null
        source "$config_file" || {
            echo "Warning: Error loading config file '$config_file'"
        }
    elif [[ -n "$CONFIG_FILE" ]]; then
        echo "Error: Specified config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Apply config values (only if not already set by command line)
    KERNEL="${KERNEL:-${TFTP_KERNEL:-$DEFAULT_KERNEL}}"
    DTB="${DTB:-${TFTP_DTB:-$DEFAULT_DTB}}"
    ROOTFS="${ROOTFS:-${TFTP_ROOTFS:-}}"
    UBOOT="${UBOOT:-${TFTP_UBOOT:-}}"
    TFTP_PATH="${TFTP_PATH:-${TFTP_DEST_DIR:-$DEFAULT_TFTP_PATH}}"
    COPY_METHOD="${COPY_METHOD:-${TFTP_COPY_METHOD:-$DEFAULT_COPY_METHOD}}"
    PRESERVE_NAMES="${PRESERVE_NAMES:-${TFTP_PRESERVE_NAMES:-true}}"
    VERIFY_CHECKSUM="${VERIFY_CHECKSUM:-${TFTP_VERIFY_CHECKSUM:-false}}"
    POST_MESSAGE="${POST_MESSAGE:-${TFTP_POST_MESSAGE:-}}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config=*)
            CONFIG_FILE="${1#*=}"
            ;;
        --kernel=*)
            KERNEL="${1#*=}"
            ;;
        --dtb=*|--dts=*)
            DTB="${1#*=}"
            ;;
        --rootfs=*)
            ROOTFS="${1#*=}"
            ;;
        --uboot=*)
            UBOOT="${1#*=}"
            ;;
        --tftp-path=*)
            TFTP_PATH="${1#*=}"
            ;;
        --list-configs)
            list_configs
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option '$1'"
            usage
            ;;
    esac
    shift
done

# Set PROJECT_ROOT
export PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Load config file
load_config

# Change to project root
cd "${PROJECT_ROOT}" || exit 1

# Expand tilde in paths
TFTP_PATH="${TFTP_PATH/#\~/$HOME}"

# Determine copy command
if [[ "$COPY_METHOD" == "rsync" ]]; then
    COPY_CMD="rsync -ah --progress"
elif [[ "$COPY_METHOD" == "cp" ]]; then
    COPY_CMD="cp -v"
elif [[ "$COPY_METHOD" == "auto" ]]; then
    if command -v rsync &> /dev/null; then
        COPY_CMD="rsync -ah --progress"
    else
        COPY_CMD="cp -v"
    fi
else
    echo "Warning: Unknown copy method '$COPY_METHOD', using cp"
    COPY_CMD="cp -v"
fi

# Get kernel version and info
get_kernel_info() {
    local kernel="$1"
    local info=""
    local version=""

    # First, try to get version from kernel.release file (if kernel is in build tree)
    local kernel_dir=$(dirname "$kernel")
    # Go up a few levels to find the kernel root
    local version_file=""
    for i in {1..5}; do
        if [[ -f "$kernel_dir/include/config/kernel.release" ]]; then
            version_file="$kernel_dir/include/config/kernel.release"
            break
        fi
        kernel_dir=$(dirname "$kernel_dir")
    done

    if [[ -f "$version_file" ]]; then
        version=$(cat "$version_file" 2>/dev/null | tr -d '\n')
        if [[ -n "$version" ]]; then
            info="Version: $version"
        fi
    fi

    # If not found, try extracting from zImage using strings
    if [[ -z "$info" ]] && command -v strings &> /dev/null; then
        version=$(strings "$kernel" 2>/dev/null | grep -E "Linux version [0-9]" | head -1)
        if [[ -z "$version" ]]; then
            version=$(strings "$kernel" 2>/dev/null | grep -m1 -E "^[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        fi
        if [[ -n "$version" ]]; then
            version=$(echo "$version" | sed 's/\s\+/ /g' | cut -c1-80)
            info="Version: $version"
        fi
    fi

    # Add build timestamp
    local build_time=$(stat -c %y "$kernel" 2>/dev/null | cut -d'.' -f1)
    if [[ -n "$build_time" ]]; then
        if [[ -n "$info" ]]; then
            info="${info}
  Built: ${build_time}"
        else
            info="Built: ${build_time}"
        fi
    fi

    echo "$info"
}

# Get DTB info
get_dtb_info() {
    local dtb="$1"
    local info=""

    # Try to extract compatible strings from DTB
    if command -v strings &> /dev/null; then
        local compat=$(strings "$dtb" 2>/dev/null | grep -A5 "compatible" | tr '\0' ' ' | head -1)
        if [[ -n "$compat" ]]; then
            info="Compatible: $compat"
        fi
    fi

    # Try dtc if available for more detailed info
    if command -v dtc &> /dev/null; then
        local model=$(dtc -I dtb -O dts "$dtb" 2>/dev/null | grep "model" | head -1 | sed 's/.*= "\(.*\)".*/\1/')
        if [[ -n "$model" ]]; then
            info="Model: $model"
        fi
    fi

    # Add timestamp
    local build_time=$(stat -c %y "$dtb" 2>/dev/null | cut -d'.' -f1)
    if [[ -n "$build_time" ]]; then
        if [[ -n "$info" ]]; then
            info="${info}
  Built: ${build_time}"
        else
            info="Built: ${build_time}"
        fi
    fi

    echo "$info"
}

# Check and copy a file
check_and_copy() {
    local src="$1"
    local dst="$2"
    local desc="$3"
    local optional="${4:-false}"

    # Skip if source is empty
    if [[ -z "$src" ]]; then
        return 0
    fi

    if [[ ! -f "${src}" ]]; then
        if [[ "$optional" == "true" ]]; then
            echo "Warning: ${desc} not found at '${src}' (skipping)"
            return 0
        else
            echo "Error: ${desc} not found at '${src}'"
            return 1
        fi
    fi

    # Create destination directory
    mkdir -p "$(dirname "${dst}")"

    # Show file info
    local size=$(du -h "$src" | cut -f1)
    echo "Copying ${desc} (${size})..."

    # Verify checksum if requested
    if [[ "$VERIFY_CHECKSUM" == "true" ]]; then
        if command -v sha256sum &> /dev/null; then
            local checksum=$(sha256sum "$src" | cut -d' ' -f1)
            echo "  SHA256: $checksum"
        elif command -v md5sum &> /dev/null; then
            local checksum=$(md5sum "$src" | cut -d' ' -f1)
            echo "  MD5: $checksum"
        fi
    fi

    # Copy file
    ${COPY_CMD} "${src}" "${dst}"
    if [[ $? -eq 0 ]]; then
        echo "  ✓ Copied to: ${dst}"
        return 0
    else
        echo "  ✗ Failed to copy ${desc}"
        return 1
    fi
}

# Main execution
echo "========================================"
echo "TFTP Copy Helper"
echo "========================================"
echo "Project: ${PROJECT_ROOT}"
echo ""
echo "Source files:"
echo "  Kernel:  ${KERNEL}"
echo "  DTB:     ${DTB}"
[[ -n "$ROOTFS" ]] && echo "  RootFS:  ${ROOTFS}"
[[ -n "$UBOOT" ]] && echo "  U-Boot:  ${UBOOT}"
echo ""
echo "Destination:"
echo "  TFTP dir: ${TFTP_PATH}"
echo ""

# Prepare destination filename
if [[ "$PRESERVE_NAMES" == "true" ]]; then
    KERNEL_DST="${TFTP_PATH}/$(basename "${KERNEL}")"
    DTB_DST="${TFTP_PATH}/$(basename "${DTB}")"
    ROOTFS_DST="${TFTP_PATH}/$(basename "${ROOTFS}")"
    UBOOT_DST="${TFTP_PATH}/$(basename "${UBOOT}")"
else
    # Add board name prefix
    local prefix="${BOARD_NAME:-board}"
    KERNEL_DST="${TFTP_PATH}/${prefix}-$(basename "${KERNEL}")"
    DTB_DST="${TFTP_PATH}/${prefix}-$(basename "${DTB}")"
    ROOTFS_DST="${TFTP_PATH}/${prefix}-$(basename "${ROOTFS}")"
    UBOOT_DST="${TFTP_PATH}/${prefix}-$(basename "${UBOOT}")"
fi

# Copy files
errors=0
check_and_copy "${KERNEL}" "${KERNEL_DST}" "Kernel" || ((errors++))
check_and_copy "${DTB}" "${DTB_DST}" "DTB" || ((errors++))
check_and_copy "${ROOTFS}" "${ROOTFS_DST}" "RootFS" "true" || ((errors++))
check_and_copy "${UBOOT}" "${UBOOT_DST}" "U-Boot" "true" || ((errors++))

echo ""
if [[ $errors -eq 0 ]]; then
    echo "========================================"
    echo "✓ All files copied successfully!"
    echo "========================================"
    echo ""
    echo "Summary:"
    echo "--------"

    # Show kernel info
    if [[ -f "$KERNEL_DST" ]]; then
        echo "Kernel:"
        kernel_info=$(get_kernel_info "$KERNEL")
        if [[ -n "$kernel_info" ]]; then
            echo "  $kernel_info"
        fi
        kernel_size=$(du -h "$KERNEL_DST" | cut -f1)
        echo "  Size: $kernel_size"
        echo "  Path: $KERNEL_DST"
        echo ""
    fi

    # Show DTB info
    if [[ -f "$DTB_DST" ]]; then
        echo "Device Tree:"
        dtb_info=$(get_dtb_info "$DTB")
        if [[ -n "$dtb_info" ]]; then
            echo "  $dtb_info"
        fi
        dtb_size=$(du -h "$DTB_DST" | cut -f1)
        echo "  Size: $dtb_size"
        echo "  Path: $DTB_DST"
        echo ""
    fi

    # Show other files
    if [[ -n "$ROOTFS" && -f "$ROOTFS_DST" ]]; then
        rootfs_size=$(du -h "$ROOTFS_DST" | cut -f1)
        echo "RootFS: $ROOTFS_DST ($rootfs_size)"
        echo ""
    fi
    if [[ -n "$UBOOT" && -f "$UBOOT_DST" ]]; then
        uboot_size=$(du -h "$UBOOT_DST" | cut -f1)
        echo "U-Boot: $UBOOT_DST ($uboot_size)"
        echo ""
    fi

    [[ -n "$POST_MESSAGE" ]] && echo "$POST_MESSAGE"
    exit 0
else
    echo "========================================"
    echo "✗ $errors file(s) failed to copy"
    echo "========================================"
    exit 1
fi
