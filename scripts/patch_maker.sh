#!/bin/bash
# patch_maker.sh - Generate patches from submodule changes
# Usage: patch_maker.sh --submodule_path=<name> [--output=<dir>]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
REPO_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_PATH=""
OUTPUT_DIR=""
SUBMODULE_NAME=""

# Print usage
usage() {
    cat << EOF
Usage: $(basename "$0") --submodule_path=<name> [--output=<dir>]

Generate a patch file from a submodule's branch changes.

Arguments:
  --submodule_path=<name>    Submodule name or path (e.g., linux_mainline)
  --output=<dir>             Output directory (default: patches/<submodule>/)

Examples:
  $(basename "$0") --submodule_path=linux_mainline
  $(basename "$0") --submodule_path=linux_mainline --output=custom_output/

Available submodules:
  - linux_mainline
  - uboot-imx
  - busybox
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --submodule_path=*)
            SUBMODULE_PATH="${1#*=}"
            shift
            ;;
        --output=*)
            OUTPUT_DIR="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SUBMODULE_PATH" ]]; then
    echo -e "${RED}Error: --submodule_path is required${NC}"
    usage
fi

# Remove 'third_party/' prefix if present
SUBMODULE_NAME="${SUBMODULE_PATH#third_party/}"

# Construct full path - try with original name first
SUBMODULE_FULL_PATH="$REPO_BASE_DIR/third_party/$SUBMODULE_NAME"

# If not found, try converting underscores to hyphens for compatibility
if [[ ! -d "$SUBMODULE_FULL_PATH" ]]; then
    SUBMODULE_NAME_HYPHEN="${SUBMODULE_NAME//_/-}"
    SUBMODULE_FULL_PATH="$REPO_BASE_DIR/third_party/$SUBMODULE_NAME_HYPHEN"
    if [[ -d "$SUBMODULE_FULL_PATH" ]]; then
        SUBMODULE_NAME="$SUBMODULE_NAME_HYPHEN"
    fi
fi

# Verify submodule exists
if [[ ! -d "$SUBMODULE_FULL_PATH" ]]; then
    echo -e "${RED}Error: Submodule '$SUBMODULE_NAME' not found at $SUBMODULE_FULL_PATH${NC}"
    echo -e "${YELLOW}Available submodules in third_party/:${NC}"
    ls -1 "$REPO_BASE_DIR/third_party/" 2>/dev/null | grep -v "^README" || echo "  (none)"
    exit 1
fi

# Verify it's a git repository
# Note: submodules have .git as a file containing gitdir path, not a directory
if [[ ! -e "$SUBMODULE_FULL_PATH/.git" ]]; then
    echo -e "${RED}Error: '$SUBMODULE_FULL_PATH' is not a git repository${NC}"
    exit 1
fi

# Change to submodule directory
cd "$SUBMODULE_FULL_PATH" || exit 1

# Detect default branch from origin/HEAD
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo -e "${YELLOW}Warning: Could not detect default branch from origin/HEAD${NC}"
    echo -e "${YELLOW}Trying 'main' or 'master'...${NC}"
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
        DEFAULT_BRANCH="main"
    elif git rev-parse --verify origin/master >/dev/null 2>&1; then
        DEFAULT_BRANCH="master"
    else
        echo -e "${RED}Error: Could not determine default branch${NC}"
        exit 1
    fi
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ -z "$CURRENT_BRANCH" ]]; then
    echo -e "${RED}Error: Not on any branch (detached HEAD state)${NC}"
    exit 1
fi

# Check if current branch is different from default
if [[ "$CURRENT_BRANCH" == "$DEFAULT_BRANCH" ]]; then
    echo -e "${YELLOW}Warning: Current branch '$CURRENT_BRANCH' is the same as default branch${NC}"
    echo -e "${YELLOW}No patches will be generated${NC}"
    exit 0
fi

# Set output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$REPO_BASE_DIR/patches/$SUBMODULE_NAME"
else
    # Handle relative or absolute path
    if [[ "$OUTPUT_DIR" != /* ]]; then
        OUTPUT_DIR="$REPO_BASE_DIR/$OUTPUT_DIR"
    fi
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate patch filename (sanitize branch name - replace / with -)
DATE=$(date +%Y%m%d)
BRANCH_SANITIZED="${CURRENT_BRANCH//\//-}"
PATCH_FILENAME="${SUBMODULE_NAME}-${BRANCH_SANITIZED}-${DATE}.patch"
PATCH_FULL_PATH="$OUTPUT_DIR/$PATCH_FILENAME"

# Count commits
COMMIT_COUNT=$(git rev-list --count "origin/$DEFAULT_BRANCH..$CURRENT_BRANCH" 2>/dev/null || git rev-list --count "$DEFAULT_BRANCH..$CURRENT_BRANCH")

if [[ "$COMMIT_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}No commits found between $DEFAULT_BRANCH and $CURRENT_BRANCH${NC}"
    exit 0
fi

# Display information
echo -e "${GREEN}=== Patch Generation Summary ===${NC}"
echo "Submodule:     $SUBMODULE_NAME"
echo "Default branch: $DEFAULT_BRANCH"
echo "Current branch: $CURRENT_BRANCH"
echo "Commits:        $COMMIT_COUNT"
echo "Output:         $PATCH_FULL_PATH"
echo

# Generate patch (single merged file using --stdout)
echo -e "${GREEN}Generating patch...${NC}"
git format-patch "origin/$DEFAULT_BRANCH..$CURRENT_BRANCH" --stdout > "$PATCH_FULL_PATH" 2>/dev/null || \
git format-patch "$DEFAULT_BRANCH..$CURRENT_BRANCH" --stdout > "$PATCH_FULL_PATH"

# Get file size
FILE_SIZE=$(ls -lh "$PATCH_FULL_PATH" | awk '{print $5}')

echo -e "${GREEN}✓ Patch generated successfully!${NC}"
echo "  File: $PATCH_FULL_PATH"
echo "  Size: $FILE_SIZE"
