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
VOLUME_LABEL="USB_DRIVE"

# Save original arguments for sudo re-execution
ORIGINAL_ARGS=("$@")

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

# Function to check if running as root, re-execute with sudo if not
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${BLUE}[INFO]${NC} This script requires root privileges. Requesting sudo access..."
        # Re-execute this script with sudo, preserving all original arguments
        exec sudo "$0" "${ORIGINAL_ARGS[@]}"
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

# Function to create partition table and partition
create_partition() {
    local device="$1"
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    local full_device="/dev/$base_device"
    
    log "INFO" "Creating partition table and partition on $full_device..."
    
    # Determine partition table type based on device size
    # Get device size in bytes
    local device_size_bytes=$(blockdev --getsize64 "$full_device" 2>/dev/null)
    if [[ -z "$device_size_bytes" ]]; then
        log "WARNING" "Could not determine device size, using MBR partition table"
        local partition_table="msdos"
    else
        # 2TB = 2 * 1024^4 bytes = 2199023255552 bytes
        if [[ $device_size_bytes -gt 2199023255552 ]]; then
            partition_table="gpt"
            log "INFO" "Device is larger than 2TB, using GPT partition table"
        else
            partition_table="msdos"
            log "INFO" "Using MBR (msdos) partition table for maximum compatibility"
        fi
    fi
    
    # Check for parted command
    if ! command -v parted &> /dev/null; then
        log "ERROR" "parted command not found. Please install parted"
        log "INFO" "On Debian/Ubuntu: sudo apt-get install parted"
        log "INFO" "On Arch: sudo pacman -S parted"
        log "INFO" "On Fedora/RHEL: sudo dnf install parted"
        return 1
    fi
    
    # Determine partition device name first
    local partition_device=""
    if [[ "$base_device" =~ ^nvme ]]; then
        # NVMe devices: /dev/nvme0n1p1
        partition_device="${full_device}p1"
    elif [[ "$base_device" =~ ^mmcblk ]]; then
        # MMC/SD devices: /dev/mmcblk0p1
        partition_device="${full_device}p1"
    else
        # Standard SCSI devices: /dev/sda1
        partition_device="${full_device}1"
    fi
    
    # Create partition table and single partition using all space
    # -s: script mode (non-interactive)
    # mklabel: create partition table
    # mkpart: create partition (primary, fat32, start at 0%, end at 100%)
    if ! parted -s "$full_device" mklabel "$partition_table" 2>&1; then
        log "ERROR" "Failed to create partition table"
        return 1
    fi
    
    if ! parted -s "$full_device" mkpart primary fat32 0% 100% 2>&1; then
        log "ERROR" "Failed to create partition"
        return 1
    fi
    
    log "SUCCESS" "Partition table and partition created successfully"
    
    # Force kernel to reread partition table - try multiple methods
    sync
    
    # Method 1: blockdev --rereadpt (most reliable)
    blockdev --rereadpt "$full_device" 2>/dev/null || true
    
    # Method 2: partprobe (if available)
    if command -v partprobe &> /dev/null; then
        partprobe "$full_device" 2>/dev/null || true
    fi
    
    # Method 3: partx (if available) - explicitly add the partition
    if command -v partx &> /dev/null; then
        partx -a "$full_device" 2>/dev/null || true
    fi
    
    # Method 4: udev trigger
    if command -v udevadm &> /dev/null; then
        udevadm trigger --subsystem-match=block --action=add 2>/dev/null || true
        udevadm settle --timeout=5 2>/dev/null || true
    fi
    
    # Wait and retry - check if partition exists
    local retries=0
    while [[ ! -b "$partition_device" ]] && [[ $retries -lt 15 ]]; do
        sleep 0.3
        ((retries++))
        
        # Try to force re-read every few retries
        if [[ $((retries % 3)) -eq 0 ]]; then
            blockdev --rereadpt "$full_device" 2>/dev/null || true
            if command -v partprobe &> /dev/null; then
                partprobe "$full_device" 2>/dev/null || true
            fi
        fi
    done
    
    # Check if partition was detected
    if [[ -b "$partition_device" ]]; then
        # Output partition device to stdout (for capture)
        printf '%s\n' "$partition_device"
        return 0
    else
        log "ERROR" "Partition device $partition_device not found after creation"
        log "INFO" "Attempting additional methods to force kernel recognition..."
        
        # Try partx to explicitly add the partition
        if command -v partx &> /dev/null; then
            partx -a "$full_device" 2>/dev/null || true
            sleep 1
        fi
        
        # Try udev trigger again
        if command -v udevadm &> /dev/null; then
            udevadm trigger --subsystem-match=block --action=add 2>/dev/null || true
            udevadm settle --timeout=3 2>/dev/null || true
        fi
        
        # Final check
        if [[ -b "$partition_device" ]]; then
            printf '%s\n' "$partition_device"
            return 0
        fi
        
        log "WARNING" "Partition $partition_device still not detected by kernel"
        log "INFO" "The partition exists but may not be recognized. Proceeding with format attempt..."
        # Return the expected partition name anyway - mkfs might still work
        printf '%s\n' "$partition_device"
        return 0
    fi
}

# Function to format device to FAT32
format_device() {
    local device="$1"
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    local full_device="/dev/$base_device"
    
    log "INFO" "Preparing $full_device for FAT32 formatting..."
    
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
    
    # Create partition table and partition to utilize all space
    # We need to capture stdout (partition device) while stderr (logs) goes to terminal
    # Use a temp file to separate stdout from stderr cleanly
    local partition_device
    local temp_stdout=$(mktemp)
    local temp_stderr=$(mktemp)
    
    # Run create_partition, capturing stdout and stderr separately
    if create_partition "$device" > "$temp_stdout" 2> "$temp_stderr"; then
        # Display log messages from stderr
        cat "$temp_stderr" >&2
        
        # Get partition device from stdout
        partition_device=$(cat "$temp_stdout" | tr -d '\n\r' | xargs)
        rm -f "$temp_stdout" "$temp_stderr"
    else
        # Display error messages
        cat "$temp_stderr" >&2
        rm -f "$temp_stdout" "$temp_stderr"
        log "ERROR" "Failed to create partition"
        return 1
    fi
    
    # If partition device not captured, construct it from device name
    if [[ -z "$partition_device" ]] || [[ ! "$partition_device" =~ ^/dev/ ]]; then
        # Fallback: construct expected partition device name
        if [[ "$base_device" =~ ^nvme ]]; then
            partition_device="${full_device}p1"
        elif [[ "$base_device" =~ ^mmcblk ]]; then
            partition_device="${full_device}p1"
        else
            partition_device="${full_device}1"
        fi
        log "INFO" "Using expected partition device: $partition_device"
    fi
    
    if [[ -z "$partition_device" ]] || [[ ! "$partition_device" =~ ^/dev/ ]]; then
        log "ERROR" "Failed to determine partition device name"
        return 1
    fi
    
    # Verify partition device exists before formatting
    if [[ ! -b "$partition_device" ]]; then
        log "ERROR" "Partition device $partition_device does not exist"
        log "INFO" "Please try unplugging and replugging the USB drive, then run the script again"
        return 1
    fi
    
    log "INFO" "Formatting partition $partition_device to FAT32 with label '$VOLUME_LABEL'..."
    
    # Format the partition (not the raw device) with FAT32
    # -F 32: FAT32 format
    # -n: volume label
    # -v: verbose
    # Note: No -I flag needed since we're formatting a partition, not raw device
    if $mkfs_cmd -F 32 -n "$VOLUME_LABEL" -v "$partition_device" 2>&1; then
        log "SUCCESS" "Partition $partition_device formatted successfully to FAT32"
        log "INFO" "All available space has been utilized"
        return 0
    else
        log "ERROR" "Failed to format partition $partition_device"
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
    
    # Ask for volume label
    echo
    read -p "Enter volume label [${VOLUME_LABEL}]: " label_input
    if [[ -n "$label_input" ]]; then
        # FAT32 label max length is 11 characters, uppercase recommended
        VOLUME_LABEL=$(echo "$label_input" | cut -c1-11 | tr '[:lower:]' '[:upper:]')
    fi
    echo
    log "INFO" "Using volume label: $VOLUME_LABEL"
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

# Check for root privileges (re-execute with sudo if needed)
check_root "${ORIGINAL_ARGS[@]}"

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

