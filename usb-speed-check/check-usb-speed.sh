#!/bin/bash

# USB Speed Check CLI Tool
# Tests read and write speeds of USB drives
# Version: 1.0

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
LIST_ONLY=false
TARGET_DEVICE=""
TEST_SIZE_MB=100
MOUNT_POINT=""
TEMP_MOUNTED=false

# Save original arguments for sudo re-execution
ORIGINAL_ARGS=("$@")

# Function to show usage
show_usage() {
    cat << EOF

USB Speed Check - Test read and write speeds of USB drives

USAGE:
    $0 [OPTIONS] [DEVICE]

OPTIONS:
    --list, -l          List available USB devices and exit
    --size, -s SIZE     Test file size in MB (default: 100)
    --help, -h          Show this help message

DEVICE:
    Target device to test (e.g., /dev/sdb or /dev/sdb1)
    If not provided, interactive mode will be used

EXAMPLES:
    $0                          # Interactive mode - select device from menu
    $0 /dev/sdb1                # Test specific partition
    $0 --list                   # List available USB devices
    $0 --size 256 /dev/sdb1     # Test with 256MB file

NOTE: The device must have a mounted filesystem to test speeds.

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
        exec sudo "$0" "${ORIGINAL_ARGS[@]}"
    fi
}

# Function to get root filesystem device
get_root_device() {
    local root_mount=$(findmnt -n -o SOURCE / 2>/dev/null | cut -d'[' -f1)
    if [[ -n "$root_mount" ]]; then
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
            local size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
            info+=("Size: $size_human")
        fi
    fi

    # Get USB version/speed from sysfs
    local usb_speed=$(get_usb_link_speed "$base_device")
    if [[ -n "$usb_speed" ]]; then
        info+=("USB: $usb_speed")
    fi

    # Get model/vendor
    if [[ -f "/sys/block/$base_device/device/model" ]]; then
        local model=$(cat "/sys/block/$base_device/device/model" 2>/dev/null | xargs)
        if [[ -n "$model" ]]; then
            info+=("Model: $model")
        fi
    fi

    # Get mount point
    local mount_point=$(lsblk -n -o MOUNTPOINT "$full_device" 2>/dev/null | grep -v '^$' | head -n1)
    if [[ -z "$mount_point" ]]; then
        mount_point=$(lsblk -n -o MOUNTPOINT "${full_device}"* 2>/dev/null | grep -v '^$' | head -n1)
    fi
    if [[ -n "$mount_point" ]]; then
        info+=("Mounted: $mount_point")
    else
        info+=("Mounted: No")
    fi

    echo "${info[*]}"
}

# Function to get USB link speed from sysfs
get_usb_link_speed() {
    local base_device="$1"
    local device_path="/sys/block/$base_device/device"

    # Walk up the device tree to find the USB speed
    local current_path=$(readlink -f "$device_path" 2>/dev/null)
    while [[ -n "$current_path" ]] && [[ "$current_path" != "/" ]]; do
        if [[ -f "$current_path/speed" ]]; then
            local speed=$(cat "$current_path/speed" 2>/dev/null)
            if [[ -n "$speed" ]]; then
                case "$speed" in
                    1.5)  echo "USB 1.0 (1.5 Mbps)" ;;
                    12)   echo "USB 1.1 (12 Mbps)" ;;
                    480)  echo "USB 2.0 (480 Mbps)" ;;
                    5000) echo "USB 3.0 (5 Gbps)" ;;
                    10000) echo "USB 3.1 (10 Gbps)" ;;
                    20000) echo "USB 3.2 (20 Gbps)" ;;
                    *)    echo "USB ($speed Mbps)" ;;
                esac
                return
            fi
        fi
        current_path=$(dirname "$current_path")
    done
}

# Function to list available USB devices
list_usb_devices() {
    local root_device=$(get_root_device)
    local devices=()
    local seen_devices=()

    log "INFO" "Scanning for USB devices..."
    echo

    for device in /dev/sd* /dev/nvme* /dev/mmcblk*; do
        [[ -b "$device" ]] || continue

        local base_device=$(basename "$device" | sed 's/[0-9]*$//')
        local full_device="/dev/$base_device"

        if [[ -n "$root_device" ]] && [[ "$full_device" == "$root_device" ]]; then
            continue
        fi

        local already_seen=false
        for seen in "${seen_devices[@]}"; do
            if [[ "$seen" == "$full_device" ]]; then
                already_seen=true
                break
            fi
        done
        [[ "$already_seen" == "true" ]] && continue

        if is_removable "$full_device"; then
            devices+=("$full_device")
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

# Function to select device interactively
select_device_interactive() {
    local devices=()
    local seen_devices=()
    local root_device=$(get_root_device)

    log "INFO" "Scanning for USB devices..."

    for device in /dev/sd* /dev/nvme* /dev/mmcblk*; do
        [[ -b "$device" ]] || continue

        local base_device=$(basename "$device" | sed 's/[0-9]*$//')
        local full_device="/dev/$base_device"

        if [[ -n "$root_device" ]] && [[ "$full_device" == "$root_device" ]]; then
            continue
        fi

        local already_seen=false
        for seen in "${seen_devices[@]}"; do
            if [[ "$seen" == "$full_device" ]]; then
                already_seen=true
                break
            fi
        done
        [[ "$already_seen" == "true" ]] && continue

        if is_removable "$full_device"; then
            devices+=("$full_device")
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

# Function to find or create a mount point for the device
ensure_mounted() {
    local device="$1"
    local base_device=$(basename "$device" | sed 's/[0-9]*$//')
    local full_device="/dev/$base_device"

    # Find partition to mount
    local partition=""

    # If user specified a partition directly, use it
    if [[ "$device" =~ [0-9]$ ]]; then
        partition="$device"
    else
        # Find first partition on the device
        partition=$(lsblk -ln -o NAME,TYPE "$full_device" 2>/dev/null | awk '$2=="part" {print "/dev/"$1; exit}')
        if [[ -z "$partition" ]]; then
            log "ERROR" "No partitions found on $full_device. Format the drive first."
            return 1
        fi
    fi

    # Check if already mounted
    MOUNT_POINT=$(findmnt -n -o TARGET "$partition" 2>/dev/null | head -n1)
    if [[ -n "$MOUNT_POINT" ]]; then
        log "INFO" "Device $partition is mounted at $MOUNT_POINT"
        return 0
    fi

    # Mount temporarily
    MOUNT_POINT=$(mktemp -d /tmp/usb-speed-test.XXXXXX)
    log "INFO" "Mounting $partition at $MOUNT_POINT..."

    if mount "$partition" "$MOUNT_POINT" 2>/dev/null; then
        TEMP_MOUNTED=true
        log "SUCCESS" "Mounted $partition at $MOUNT_POINT"
        return 0
    else
        rmdir "$MOUNT_POINT" 2>/dev/null
        log "ERROR" "Failed to mount $partition. Ensure it has a valid filesystem."
        return 1
    fi
}

# Cleanup function
cleanup() {
    local test_file="$MOUNT_POINT/.usb_speed_test_$$"

    # Remove test file
    rm -f "$test_file" 2>/dev/null

    # Unmount if we mounted it
    if [[ "$TEMP_MOUNTED" == "true" ]] && [[ -n "$MOUNT_POINT" ]]; then
        sync
        umount "$MOUNT_POINT" 2>/dev/null
        rmdir "$MOUNT_POINT" 2>/dev/null
        log "INFO" "Unmounted temporary mount point"
    fi
}

# Function to format speed in human-readable form
format_speed() {
    local speed_bytes="$1"

    if [[ $(echo "$speed_bytes >= 1073741824" | bc 2>/dev/null) -eq 1 ]] 2>/dev/null; then
        echo "$(echo "scale=2; $speed_bytes / 1073741824" | bc) GB/s"
    elif [[ $(echo "$speed_bytes >= 1048576" | bc 2>/dev/null) -eq 1 ]] 2>/dev/null; then
        echo "$(echo "scale=2; $speed_bytes / 1048576" | bc) MB/s"
    elif [[ $(echo "$speed_bytes >= 1024" | bc 2>/dev/null) -eq 1 ]] 2>/dev/null; then
        echo "$(echo "scale=2; $speed_bytes / 1024" | bc) KB/s"
    else
        echo "${speed_bytes} B/s"
    fi
}

# Function to run write speed test
test_write_speed() {
    local test_file="$1"
    local size_mb="$2"

    log "INFO" "Testing write speed (${size_mb}MB)..." >&2

    # Drop caches before test
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

    # Write test using dd with direct I/O
    local dd_output
    dd_output=$(dd if=/dev/zero of="$test_file" bs=1M count="$size_mb" conv=fdatasync oflag=direct 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        # Retry without direct I/O (some filesystems don't support it)
        dd_output=$(dd if=/dev/zero of="$test_file" bs=1M count="$size_mb" conv=fdatasync 2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Write test failed" >&2
        return 1
    fi

    # Parse speed from dd output
    local speed=$(echo "$dd_output" | grep -oP '[\d.]+ [KMGT]?B/s' | tail -1)
    if [[ -z "$speed" ]]; then
        # Try alternate dd output format
        local bytes=$(echo "$dd_output" | grep -oP '(\d+) bytes' | grep -oP '\d+')
        local seconds=$(echo "$dd_output" | grep -oP '[\d.]+ s,' | grep -oP '[\d.]+')
        if [[ -n "$bytes" ]] && [[ -n "$seconds" ]]; then
            local bytes_per_sec=$(echo "scale=0; $bytes / $seconds" | bc 2>/dev/null)
            speed=$(format_speed "$bytes_per_sec")
        fi
    fi

    echo "$speed"
}

# Function to run read speed test
test_read_speed() {
    local test_file="$1"
    local size_mb="$2"

    log "INFO" "Testing read speed (${size_mb}MB)..." >&2

    # Drop caches to ensure we're reading from device
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

    # Read test using dd with direct I/O
    local dd_output
    dd_output=$(dd if="$test_file" of=/dev/null bs=1M count="$size_mb" iflag=direct 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        # Retry without direct I/O
        dd_output=$(dd if="$test_file" of=/dev/null bs=1M count="$size_mb" 2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Read test failed" >&2
        return 1
    fi

    # Parse speed from dd output
    local speed=$(echo "$dd_output" | grep -oP '[\d.]+ [KMGT]?B/s' | tail -1)
    if [[ -z "$speed" ]]; then
        local bytes=$(echo "$dd_output" | grep -oP '(\d+) bytes' | grep -oP '\d+')
        local seconds=$(echo "$dd_output" | grep -oP '[\d.]+ s,' | grep -oP '[\d.]+')
        if [[ -n "$bytes" ]] && [[ -n "$seconds" ]]; then
            local bytes_per_sec=$(echo "scale=0; $bytes / $seconds" | bc 2>/dev/null)
            speed=$(format_speed "$bytes_per_sec")
        fi
    fi

    echo "$speed"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --list|-l)
            LIST_ONLY=true
            shift
            ;;
        --size|-s)
            TEST_SIZE_MB="$2"
            if ! [[ "$TEST_SIZE_MB" =~ ^[0-9]+$ ]] || [[ "$TEST_SIZE_MB" -lt 1 ]]; then
                log "ERROR" "Invalid test size: $2 (must be a positive integer in MB)"
                exit 1
            fi
            shift 2
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
check_root "${ORIGINAL_ARGS[@]}"

# Main execution
echo -e "${BLUE}USB Speed Check CLI${NC}"
echo "================================"
echo

# List only mode
if [[ "$LIST_ONLY" == "true" ]]; then
    list_usb_devices
    exit $?
fi

# Get target device
if [[ -z "$TARGET_DEVICE" ]]; then
    if ! select_device_interactive; then
        exit 1
    fi
fi

# Validate device exists
if [[ ! -b "$TARGET_DEVICE" ]]; then
    log "ERROR" "Device does not exist: $TARGET_DEVICE"
    exit 1
fi

# Show device info
local_base=$(basename "$TARGET_DEVICE" | sed 's/[0-9]*$//')
log "INFO" "Selected device: $TARGET_DEVICE"
info=$(get_device_info "$TARGET_DEVICE")
log "INFO" "$info"
echo

# Get USB link speed
usb_speed=$(get_usb_link_speed "$local_base")
if [[ -n "$usb_speed" ]]; then
    log "INFO" "Interface speed: $usb_speed"
fi

# Ensure device is mounted
if ! ensure_mounted "$TARGET_DEVICE"; then
    exit 1
fi

# Set trap for cleanup
trap cleanup EXIT

# Check available space
available_kb=$(df -k "$MOUNT_POINT" | awk 'NR==2 {print $4}')
available_mb=$((available_kb / 1024))
if [[ $available_mb -lt $TEST_SIZE_MB ]]; then
    log "WARNING" "Not enough free space. Available: ${available_mb}MB, requested: ${TEST_SIZE_MB}MB"
    TEST_SIZE_MB=$((available_mb / 2))
    if [[ $TEST_SIZE_MB -lt 1 ]]; then
        log "ERROR" "Not enough free space to run speed test"
        exit 1
    fi
    log "INFO" "Adjusted test size to ${TEST_SIZE_MB}MB"
fi

# Test file path
TEST_FILE="$MOUNT_POINT/.usb_speed_test_$$"

echo
echo "Running speed test with ${TEST_SIZE_MB}MB test file..."
echo "========================================"
echo

# Write speed test
write_speed=$(test_write_speed "$TEST_FILE" "$TEST_SIZE_MB")

# Read speed test
read_speed=$(test_read_speed "$TEST_FILE" "$TEST_SIZE_MB")

# Display results
echo
echo "========================================"
echo -e "${GREEN}Results for $TARGET_DEVICE${NC}"
echo "========================================"
echo
if [[ -n "$usb_speed" ]]; then
    echo -e "  Interface:    ${BLUE}$usb_speed${NC}"
fi
echo -e "  Test size:    ${TEST_SIZE_MB}MB"
echo -e "  Write speed:  ${YELLOW}${write_speed:-N/A}${NC}"
echo -e "  Read speed:   ${YELLOW}${read_speed:-N/A}${NC}"
echo
echo "========================================"
echo

log "SUCCESS" "Speed test complete"
