#!/bin/bash
#
# Manual NFS Mount Helper Script
#
# Usage:
#   scripts/manual_mount_nfs.sh <source_dir> <target_dir>
#   scripts/manual_mount_nfs.sh --unmount <target_dir>
#

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

# Source shared logging (with fallback for standalone usage)
if [[ -f "${SCRIPT_LIB_DIR}/bash/lib_common.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/bash/lib_common.sh"
else
    # Fallback to local definitions if shared lib not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_debug() { if [[ "${DEBUG:-false}" == "true" ]]; then echo -e "${CYAN}[DEBUG]${NC} $1"; fi; }
fi

# Define log_cmd if not already defined (lib_common.sh doesn't have it)
if ! type -t log_cmd >/dev/null 2>&1; then
    log_cmd() { echo -e "${YELLOW}[CMD]${NC} $1"; }
fi

# Configuration
REQUIRED_DIRS=("bin" "sbin" "usr")
DEFAULT_SOURCE_DIR="${PROJECT_ROOT}/out/release-latest/rootfs"
DEFAULT_TARGET_DIR="${PROJECT_ROOT}/rootfs/nfs"
SHOW_HELP=0
DO_UNMOUNT=0
DO_LAZY_UNMOUNT=0

# Display usage
show_usage() {
    cat << EOF
Usage: sudo $0 [OPTIONS]

Options:
  --unmount, -u         Unmount instead of mount
  --lazy-unmount        Lazy unmount (detach immediately, clean up later)
  --source=PATH         Custom source directory (default: out/release-latest/rootfs)
  --target=PATH         Custom target directory (default: rootfs/nfs)
  --help, -h            Show this help message
  --debug               Enable debug output

Description:
  Quick helper to mount release rootfs to NFS rootfs for kernel access.

  This script requires root privileges (sudo) to perform mount operations.

  Default behavior (no arguments):
    - Mounts out/release-latest/rootfs to rootfs/nfs

  The script performs safety checks and uses bind mounts.

  Lazy unmount:
    Use --lazy-unmount if regular unmount fails with "target is busy"
    This detaches the filesystem immediately and cleans up when not busy

Examples:
  # Mount default: out/release-latest/rootfs -> rootfs/nfs
  sudo $0

  # Unmount
  sudo $0 --unmount

  # Lazy unmount (if target is busy)
  sudo $0 --unmount --lazy-unmount

  # Use custom directories
  sudo $0 --source=/tmp/my_build/rootfs --target=rootfs/nfs

EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        log_info ""
        log_info "Please run with sudo:"
        log_info "  sudo $0 $*"
        log_info ""
        exit 1
    fi
}

check_directory_safe() {
    local dir="$1"
    local dir_name="${2:-directory}"

    if [[ "$dir" == "/" ]]; then
        log_error "The $dir_name cannot be '/'"
        return 1
    fi

    local abs_dir
    if ! abs_dir=$(cd "$dir" 2>/dev/null && pwd); then
        log_error "Cannot access $dir_name: $dir"
        return 1
    fi

    if [[ "$abs_dir" == "/" ]]; then
        log_error "The $dir_name resolves to '/' (unsafe)"
        return 1
    fi

    log_debug "Directory safety check passed for $dir_name: $abs_dir"
    return 0
}

check_valid_rootfs() {
    local rootfs="$1"
    local label="${2:-Directory}"
    local missing=()
    local found=()

    for dir in "${REQUIRED_DIRS[@]}"; do
        if [[ -d "${rootfs}/${dir}" ]]; then
            found+=("$dir")
        else
            missing+=("$dir")
        fi
    done

    if [[ ${#found[@]} -gt 0 ]]; then
        log_debug "  Found required directories: ${found[*]}"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "${label} does not appear to be a valid rootfs: ${rootfs}"
        log_error "Missing required directories: ${missing[*]}"
        log_error "Please ensure it has at least: bin, sbin, usr"
        return 1
    fi

    log_info "  ${label} is a valid rootfs"
    return 0
}

mount_bind() {
    local source_dir="$1"
    local target_dir="$2"

    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory does not exist: $source_dir"
        return 1
    fi

    if [[ ! -d "$target_dir" ]]; then
        log_info "Creating target directory: $target_dir"
        mkdir -p "$target_dir" || {
            log_error "Failed to create target directory"
            return 1
        }
    fi

    log_info "Mounting: $source_dir -> $target_dir"
    log_cmd "mount --bind $source_dir $target_dir"
    if mount --bind "$source_dir" "$target_dir"; then
        log_success "Successfully mounted"
        log_info "Verify with: mount | grep $(basename "$target_dir")"
        return 0
    else
        log_error "Mount failed"
        return 1
    fi
}

unmount_bind() {
    local target_dir="$1"
    local lazy="${2:-false}"

    if [[ ! -d "$target_dir" ]]; then
        log_error "Target directory does not exist: $target_dir"
        return 1
    fi

    if ! mountpoint -q "$target_dir" 2>/dev/null; then
        log_warn "Target is not a mount point: $target_dir"
        return 1
    fi

    if [[ "$lazy" == "true" ]]; then
        log_info "Lazy unmounting: $target_dir"
        log_info "This will detach immediately and clean up when not busy"
        log_cmd "umount -l $target_dir"
        if umount -l "$target_dir"; then
            log_success "Successfully lazy unmounted"
            log_info "The filesystem will be cleaned up when no longer in use"
            return 0
        else
            log_error "Lazy unmount failed"
            return 1
        fi
    else
        log_info "Unmounting: $target_dir"
        log_cmd "umount $target_dir"
        if umount "$target_dir"; then
            log_success "Successfully unmounted"
            return 0
        else
            log_error "Unmount failed"
            log_warn "The target might be busy. Try with --lazy-unmount"
            log_warn "Or check with: sudo lsof +D $target_dir"
            return 1
        fi
    fi
}

main() {
    local source_dir="$DEFAULT_SOURCE_DIR"
    local target_dir="$DEFAULT_TARGET_DIR"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                SHOW_HELP=1
                shift
                ;;
            --unmount|-u)
                DO_UNMOUNT=1
                shift
                ;;
            --lazy-unmount)
                DO_LAZY_UNMOUNT=1
                shift
                ;;
            --source=*)
                source_dir="${1#*=}"
                shift
                ;;
            --source)
                shift
                source_dir="$1"
                shift
                ;;
            --target=*)
                target_dir="${1#*=}"
                shift
                ;;
            --target)
                shift
                target_dir="$1"
                shift
                ;;
            --debug)
                export DEBUG=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                log_info ""
                show_usage
                exit 1
                ;;
        esac
    done

    # Check for help flag before validation
    if [ ${SHOW_HELP} -eq 1 ]; then
        show_usage
        exit 0
    fi

    # Check if running as root
    check_root "$@"

    log_info "========================================"
    log_info "Manual NFS Mount Helper"
    log_info "========================================"
    log_info ""

    # Use default values if not overridden
    if [[ ${DO_UNMOUNT} -eq 0 ]]; then
        log_info "Source directory: ${source_dir}"
        log_info "Target directory: ${target_dir}"
        log_info ""

        # Validate source directory exists and is safe
        if [[ ! -d "$source_dir" ]]; then
            log_error "Source directory does not exist: $source_dir"
            exit 1
        fi

        if ! check_directory_safe "$source_dir" "source directory"; then
            log_error "Source directory validation failed"
            exit 1
        fi

        # Verify the source actually looks like a rootfs (has bin/sbin/usr).
        # Non-fatal: warn so custom layouts can still proceed.
        if ! check_valid_rootfs "$source_dir" "Source directory"; then
            log_warn "Source doesn't look like a rootfs; continuing anyway"
        fi
        log_info "  Source directory is safe"
        log_info ""

        # Check if target is already mounted FIRST (before other validations)
        if mountpoint -q "$target_dir" 2>/dev/null; then
            log_warn "Target is already a mount point: $target_dir"
            log_info "Use '--unmount' to unmount first"
            exit 1
        fi

        # Validate target directory
        if [[ -d "$target_dir" ]]; then
            # Target is just a mount point; only check safety, not rootfs validity.
            # An empty placeholder dir is the normal, expected state before mounting.
            log_info "Target directory exists, validating..."
            if ! check_directory_safe "$target_dir" "target directory"; then
                log_error "Target directory validation failed"
                exit 1
            fi
        else
            # Target doesn't exist, check parent directory is safe
            local parent_dir
            parent_dir="$(dirname "$target_dir")"
            if ! check_directory_safe "$parent_dir" "parent directory"; then
                log_error "Parent directory validation failed"
                exit 1
            fi
            log_info "  Target directory does not exist (will be created)"
        fi
        log_info "  Target directory is safe"
        log_info ""
    else
        # Unmount mode
        log_info "Target directory: ${target_dir}"
        log_info ""

        if [[ ! -d "$target_dir" ]]; then
            log_error "Target directory does not exist: $target_dir"
            exit 1
        fi

        if ! check_directory_safe "$target_dir" "target directory"; then
            log_error "Target directory validation failed"
            exit 1
        fi
        log_info "  Target directory is safe"
        log_info ""
    fi

    # Perform operation
    if [[ ${DO_UNMOUNT} -eq 1 ]]; then
        local lazy="false"
        if [[ ${DO_LAZY_UNMOUNT} -eq 1 ]]; then
            lazy="true"
        fi
        if ! unmount_bind "$target_dir" "$lazy"; then
            exit 1
        fi
    else
        if ! mount_bind "$source_dir" "$target_dir"; then
            exit 1
        fi
    fi

    log_info ""
    log_info "========================================"
    log_success "Operation completed successfully!"
    log_info "========================================"
}

main "$@"
