#!/bin/bash

# USB FAT32 Formatter CLI Tool
# Formats USB drives to FAT32 format with safety checks
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
FORCE=false
LIST_ONLY=false
TARGET_DEVICE=""

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [DEVICE]

USB FAT32 Formatter - Format USB drives to FAT32 format

OPTIONS:
    --list, -l        List available USB devices and exit
    --force, -f       Skip confirmation prompt (use with caution!)
    --help, -h        Show this help message

DEVICE:
    Target device to format (e.g., /dev/sdb)
    If not provided, interactive mode will be used

EXAMPLES:
    $0                          # Interactive mode - select device from menu
    $0 /dev/sdb                 # Format specific device
    $0 --list                   # List available USB devices
    $0 --force /dev/sdb         # Format without confirmation (dangerous!)

WARNING: This will erase all data on the selected USB drive!

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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to get root filesystem device
get_root_device() {
    local root_mount=$(findmnt -n -o SOURCE / 2>/dev/null | cut -d'[' -f1)
    if [[ -n "$root_mount" ]]; then
        # Extract base device (e.g., /dev/sda from /dev/sda1)
        echo "$root_mount" | sed 's/[0-9]*$//'
    fi
}

# Function to check if device is removable
is_removable() {
    local device="$1"
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    
    if [[ -f "/sys/block/$base_device/removable" ]]; then
        local removable=$(cat "/sys/block/$base_device/removable" 2>/dev/null)
        [[ "$removable" == "1" ]]
    else
        return 1
    fi
}

# Function to get device information
get_device_info() {
    local device="$1"
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    local full_device="/dev/$base_device"
    
    local info=()
    
    # Get size
    if command -v lsblk &> /dev/null; then
        local size=$(lsblk -b -d -n -o SIZE "$full_device" 2>/dev/null)
        if [[ -n "$size" ]]; then
            # Convert bytes to human readable
            local size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
            info+=("Size: $size_human")
        fi
    fi
    
    # Get filesystem
    local fs=$(lsblk -n -o FSTYPE "$full_device" 2>/dev/null | head -n1)
    if [[ -n "$fs" ]]; then
        info+=("Filesystem: $fs")
    else
        info+=("Filesystem: Unknown/Unformatted")
    fi
    
    # Get mount status
    local mount_point=$(findmnt -n -o TARGET "$full_device" 2>/dev/null)
    if [[ -n "$mount_point" ]]; then
        info+=("Mounted at: $mount_point")
    else
        info+=("Mounted: No")
    fi
    
    # Get model/vendor
    if [[ -f "/sys/block/$base_device/device/model" ]]; then
        local model=$(cat "/sys/block/$base_device/device/model" 2>/dev/null | tr -d ' ')
        if [[ -n "$model" ]]; then
            info+=("Model: $model")
        fi
    fi
    
    echo "${info[*]}"
}

# Function to list available USB devices
list_usb_devices() {
    local root_device=$(get_root_device)
    local devices=()
    local device_names=()
    local seen_devices=()
    
    log "INFO" "Scanning for USB devices..."
    echo
    
    # Find all block devices
    for device in /dev/sd* /dev/nvme* /dev/mmcblk*; do
        [[ -b "$device" ]] || continue
        
        local base_device=$(basename "$device" | sed 's/[0-9]*$//')
        local full_device="/dev/$base_device"
        
        # Skip if it's the root device
        if [[ -n "$root_device" ]] && [[ "$full_device" == "$root_device" ]]; then
            continue
        fi
        
        # Skip if we've already seen this base device
        local already_seen=false
        for seen in "${seen_devices[@]}"; do
            if [[ "$seen" == "$full_device" ]]; then
                already_seen=true
                break
            fi
        done
        [[ "$already_seen" == "true" ]] && continue
        
        # Check if removable (check base device, not partition)
        if is_removable "$full_device"; then
            devices+=("$full_device")
            device_names+=("$base_device")
            seen_devices+=("$full_device")
        fi
    done
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        log "WARNING" "No USB devices found"
        return 1
    fi
    
    echo "Available USB devices:"
    echo "====================="
    echo
    
    local index=1
    for i in "${!devices[@]}"; do
        local device="${devices[$i]}"
        local info=$(get_device_info "$device")
        echo "$index) $device"
        echo "   $info"
        echo
        ((index++))
    done
    
    return 0
}

# Function to validate device
validate_device() {
    local device="$1"
    
    # Check if device exists
    if [[ ! -b "$device" ]]; then
        log "ERROR" "Device does not exist: $device"
        return 1
    fi
    
    # Get base device (remove partition number)
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    local full_device="/dev/$base_device"
    
    # Check if it's the root device
    local root_device=$(get_root_device)
    if [[ -n "$root_device" ]] && [[ "$full_device" == "$root_device" ]]; then
        log "ERROR" "Cannot format root filesystem device: $device"
        return 1
    fi
    
    # Check if removable
    if ! is_removable "$device"; then
        log "WARNING" "Device $device does not appear to be removable"
        log "WARNING" "Proceeding anyway, but please verify this is correct"
    fi
    
    return 0
}

# Function to unmount device
unmount_device() {
    local device="$1"
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    local full_device="/dev/$base_device"
    
    # Check if mounted
    local mount_points=$(findmnt -n -o TARGET "$full_device" 2>/dev/null)
    if [[ -n "$mount_points" ]]; then
        log "INFO" "Device is mounted, unmounting..."
        while IFS= read -r mount_point; do
            if umount "$mount_point" 2>/dev/null; then
                log "SUCCESS" "Unmounted $mount_point"
            else
                log "ERROR" "Failed to unmount $mount_point"
                return 1
            fi
        done <<< "$mount_points"
    fi
    
    return 0
}

# Function to format device to FAT32
format_device() {
    local device="$1"
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    local full_device="/dev/$base_device"
    
    log "INFO" "Formatting $full_device to FAT32..."
    
    # Check for mkfs.vfat or mkfs.fat
    local mkfs_cmd=""
    if command -v mkfs.vfat &> /dev/null; then
        mkfs_cmd="mkfs.vfat"
    elif command -v mkfs.fat &> /dev/null; then
        mkfs_cmd="mkfs.fat"
    else
        log "ERROR" "mkfs.vfat or mkfs.fat not found. Please install dosfstools"
        return 1
    fi
    
    # Format with FAT32
    # -F 32: FAT32 format
    # -I: Ignore disk label and force formatting (required when partitions exist)
    # -n: volume label (optional, we'll use a default)
    # -v: verbose
    if $mkfs_cmd -F 32 -I -n "USB_DRIVE" -v "$full_device" 2>&1; then
        log "SUCCESS" "Device $full_device formatted successfully to FAT32"
        return 0
    else
        log "ERROR" "Failed to format device $full_device"
        return 1
    fi
}

# Function to confirm action
confirm_action() {
    local device="$1"
    local info=$(get_device_info "$device")
    
    echo
    log "WARNING" "You are about to format: $device"
    echo "   $info"
    echo
    log "WARNING" "ALL DATA ON THIS DEVICE WILL BE ERASED!"
    echo
    read -p "Type 'yes' to continue, anything else to cancel: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Operation cancelled"
        return 1
    fi
    
    return 0
}

# Function to select device interactively
select_device_interactive() {
    local devices=()
    local device_names=()
    local seen_devices=()
    local root_device=$(get_root_device)
    
    log "INFO" "Scanning for USB devices..."
    
    # Find all block devices
    for device in /dev/sd* /dev/nvme* /dev/mmcblk*; do
        [[ -b "$device" ]] || continue
        
        local base_device=$(basename "$device" | sed 's/[0-9]*$//')
        local full_device="/dev/$base_device"
        
        # Skip if it's the root device
        if [[ -n "$root_device" ]] && [[ "$full_device" == "$root_device" ]]; then
            continue
        fi
        
        # Skip if we've already seen this base device
        local already_seen=false
        for seen in "${seen_devices[@]}"; do
            if [[ "$seen" == "$full_device" ]]; then
                already_seen=true
                break
            fi
        done
        [[ "$already_seen" == "true" ]] && continue
        
        # Check if removable (check base device, not partition)
        if is_removable "$full_device"; then
            devices+=("$full_device")
            device_names+=("$base_device")
            seen_devices+=("$full_device")
        fi
    done
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        log "ERROR" "No USB devices found"
        return 1
    fi
    
    echo
    echo "Available USB devices:"
    echo "====================="
    echo
    
    local index=1
    for i in "${!devices[@]}"; do
        local device="${devices[$i]}"
        local info=$(get_device_info "$device")
        echo "$index) $device"
        echo "   $info"
        echo
        ((index++))
    done
    
    echo
    read -p "Select device number (1-${#devices[@]}): " selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#devices[@]} ]]; then
        log "ERROR" "Invalid selection"
        return 1
    fi
    
    local selected_index=$((selection - 1))
    TARGET_DEVICE="${devices[$selected_index]}"
    
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --list|-l)
            LIST_ONLY=true
            shift
            ;;
        --force|-f)
            FORCE=true
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
            TARGET_DEVICE="$1"
            shift
            ;;
    esac
done

# Check for root privileges
check_root

# Main execution
echo -e "${BLUE}USB FAT32 Formatter CLI${NC}"
echo "================================"
echo

# List only mode
if [[ "$LIST_ONLY" == "true" ]]; then
    list_usb_devices
    exit $?
fi

# Get target device
if [[ -z "$TARGET_DEVICE" ]]; then
    # Interactive mode
    if ! select_device_interactive; then
        exit 1
    fi
fi

# Validate device
if ! validate_device "$TARGET_DEVICE"; then
    exit 1
fi

# Show device info
log "INFO" "Selected device: $TARGET_DEVICE"
info=$(get_device_info "$TARGET_DEVICE")
log "INFO" "$info"

# Confirm action (unless --force)
if [[ "$FORCE" != "true" ]]; then
    if ! confirm_action "$TARGET_DEVICE"; then
        exit 0
    fi
fi

# Unmount device
if ! unmount_device "$TARGET_DEVICE"; then
    log "ERROR" "Failed to unmount device. Please unmount manually and try again"
    exit 1
fi

# Format device
if format_device "$TARGET_DEVICE"; then
    echo
    log "SUCCESS" "USB drive formatted successfully!"
    log "INFO" "You can now safely remove the USB drive"
    exit 0
else
    exit 1
fi

