#!/bin/bash

# Apple File Cleaner CLI Tool
# Recursively deletes Apple-related system files from directories
# Author: Generated CLI Tool
# Version: 1.0

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
TARGET_DIR="."
VERBOSE=false

# Apple file patterns to clean
APPLE_PATTERNS=(
    ".DS_Store"
    "._*"
    ".Spotlight-V100"
    ".Trashes"
    ".fseventsd"
    ".TemporaryItems"
    ".DocumentRevisions-V100"
    ".VolumeIcon.icns"
    ".AppleDB"
    ".AppleDesktop"
    ".AppleDouble"
)

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [DIRECTORY]

Apple File Cleaner - Recursively removes Apple system files

OPTIONS:
    --dry-run, -n     Show what would be deleted without actually deleting
    --verbose, -v     Show detailed output
    --help, -h        Show this help message

DIRECTORY:
    Target directory to clean (default: current directory)

EXAMPLES:
    $0                    # Clean current directory
    $0 /path/to/folder    # Clean specific directory
    $0 --dry-run          # Preview what would be deleted
    $0 -n -v /home/user   # Dry run with verbose output

Apple files that will be removed:
    .DS_Store, ._*, .Spotlight-V100, .Trashes, .fseventsd,
    .TemporaryItems, .DocumentRevisions-V100, .VolumeIcon.icns,
    .AppleDB, .AppleDesktop, .AppleDouble

EOF
}

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
    esac
}

# Function to find and process Apple files recursively
clean_apple_files() {
    local target_dir="$1"
    local total_found=0
    local total_deleted=0
    
    log "INFO" "Scanning directory recursively: $target_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN MODE - No files will be deleted"
    fi
    
    echo
    
    # Process each pattern
    for pattern in "${APPLE_PATTERNS[@]}"; do
        local found_files=()
        local count=0
        
        # Find files matching the pattern (recursively search all subdirectories)
        while IFS= read -r -d '' file; do
            found_files+=("$file")
            ((count++))
        done < <(find "$target_dir" -name "$pattern" -type f -print0 2>/dev/null || true)
        
        if [[ $count -gt 0 ]]; then
            log "INFO" "Found $count file(s) matching pattern: $pattern"
            
            for file in "${found_files[@]}"; do
                if [[ "$VERBOSE" == "true" ]]; then
                    echo "  $file"
                fi
                
                if [[ "$DRY_RUN" == "false" ]]; then
                    if rm -f "$file" 2>/dev/null; then
                        ((total_deleted++))
                    else
                        log "WARNING" "Failed to delete: $file"
                    fi
                fi
            done
            
            ((total_found += count))
        fi
    done
    
    echo
    
    # Summary
    if [[ $total_found -eq 0 ]]; then
        log "SUCCESS" "No Apple files found in $target_dir"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "Would delete $total_found Apple file(s)"
        else
            log "SUCCESS" "Deleted $total_deleted out of $total_found Apple file(s)"
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            log "ERROR" "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# Validate target directory
if [[ ! -d "$TARGET_DIR" ]]; then
    log "ERROR" "Directory does not exist: $TARGET_DIR"
    exit 1
fi

# Convert to absolute path
TARGET_DIR=$(realpath "$TARGET_DIR")

# Main execution
echo -e "${BLUE}Apple File Cleaner CLI${NC}"
echo "================================"
echo

clean_apple_files "$TARGET_DIR"

echo
log "INFO" "Operation completed"
