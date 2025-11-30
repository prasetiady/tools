# USB FAT32 Formatter CLI

A simple and user-friendly command-line tool to format USB drives to FAT32 format on Linux. This tool provides safety checks to prevent accidental formatting of system drives and offers both interactive and command-line modes.

## Features

- **Interactive mode**: List available USB devices and select from a menu
- **Command-line mode**: Format a specific device by providing its path
- **Safety checks**: Automatically detects and prevents formatting system drives
- **Device information**: Shows size, filesystem, and mount status before formatting
- **Confirmation prompts**: Requires explicit confirmation before formatting (unless `--force` is used)
- **Auto-unmount**: Automatically unmounts the device before formatting
- **Color-coded output**: Easy-to-read terminal output with color coding
- **Error handling**: Comprehensive error checking and user-friendly messages

## Requirements

- Linux operating system
- Root/sudo privileges (required for formatting)
- `mkfs.vfat` or `mkfs.fat` (usually provided by `dosfstools` package)
- `lsblk` command (usually pre-installed)
- Bash shell

## Installation

1. Make the script executable:
   ```bash
   chmod +x format-usb.sh
   ```

2. (Optional) Move to your PATH for system-wide access:
   ```bash
   sudo mv format-usb.sh /usr/local/bin/format-usb
   ```

3. Install dosfstools if not already installed:
   ```bash
   # Debian/Ubuntu
   sudo apt-get install dosfstools
   
   # Arch Linux
   sudo pacman -S dosfstools
   
   # Fedora/RHEL
   sudo dnf install dosfstools
   ```

## Usage

### Interactive Mode (Recommended)

Simply run the script without arguments to enter interactive mode:

```bash
sudo ./format-usb.sh
```

The script will:
1. Scan for available USB devices
2. Display a numbered list with device information
3. Prompt you to select a device
4. Show device details and ask for confirmation
5. Format the device to FAT32

### Command-Line Mode

Format a specific device by providing its path:

```bash
sudo ./format-usb.sh /dev/sdb
```

**Important**: Always use the base device path (e.g., `/dev/sdb`), not a partition (e.g., `/dev/sdb1`). The script will format the entire device.

### List Available Devices

To see available USB devices without formatting:

```bash
sudo ./format-usb.sh --list
```

### Force Mode (Use with Caution!)

Skip the confirmation prompt:

```bash
sudo ./format-usb.sh --force /dev/sdb
```

**Warning**: This will format the device immediately without asking for confirmation. Use only when you're absolutely certain.

## Options

- `--list, -l`: List available USB devices and exit
- `--force, -f`: Skip confirmation prompt (dangerous!)
- `--help, -h`: Show help message

## Examples

```bash
# Interactive mode - safest option
sudo ./format-usb.sh

# Format specific device
sudo ./format-usb.sh /dev/sdb

# List devices first
sudo ./format-usb.sh --list

# Format without confirmation (use carefully!)
sudo ./format-usb.sh --force /dev/sdb
```

## Safety Features

### System Drive Protection

The script automatically:
- Detects the root filesystem device
- Prevents formatting of system drives
- Warns if attempting to format non-removable devices

### Data Loss Warnings

- Shows device information (size, current filesystem) before formatting
- Requires explicit "yes" confirmation (unless `--force` is used)
- Warns about data loss in clear messages

### Mount Detection

- Automatically detects if the device is mounted
- Attempts to unmount before formatting
- Fails gracefully if unmounting is not possible

## Output Example

```
USB FAT32 Formatter CLI
================================

[INFO] Scanning for USB devices...

Available USB devices:
=====================

1) /dev/sdb
   Size: 7.3GiB Filesystem: vfat Mounted at: /media/user/USB

2) /dev/sdc
   Size: 14.9GiB Filesystem: ext4 Mounted: No

Select device number (1-2): 1

[INFO] Selected device: /dev/sdb
[INFO] Size: 7.3GiB Filesystem: vfat Mounted at: /media/user/USB

[WARNING] You are about to format: /dev/sdb
   Size: 7.3GiB Filesystem: vfat Mounted at: /media/user/USB

[WARNING] ALL DATA ON THIS DEVICE WILL BE ERASED!

Type 'yes' to continue, anything else to cancel: yes

[INFO] Device is mounted, unmounting...
[SUCCESS] Unmounted /media/user/USB
[INFO] Formatting /dev/sdb to FAT32...
mkfs.fat 4.2 (2021-01-31)
[SUCCESS] Device /dev/sdb formatted successfully to FAT32

[SUCCESS] USB drive formatted successfully!
[INFO] You can now safely remove the USB drive
```

## Troubleshooting

### Permission Denied

If you get permission errors, make sure you're running with sudo:

```bash
sudo ./format-usb.sh
```

### Device Not Found

If the device doesn't appear in the list:
- Make sure the USB drive is properly connected
- Try unplugging and replugging the device
- Check if the device appears in `lsblk` output:
  ```bash
  lsblk
  ```

### mkfs.vfat Not Found

Install the `dosfstools` package:

```bash
# Debian/Ubuntu
sudo apt-get install dosfstools

# Arch Linux
sudo pacman -S dosfstools

# Fedora/RHEL
sudo dnf install dosfstools
```

### Cannot Unmount Device

If the device cannot be unmounted:
- Close all file managers and applications accessing the USB drive
- Manually unmount the device:
  ```bash
  sudo umount /dev/sdb
  ```
- Then run the formatter again

### Device Still Shows Old Filesystem

After formatting, you may need to:
- Unplug and replug the USB drive
- Or manually mount it to refresh the filesystem information

### "Cannot format root filesystem device" Error

This is a safety feature. The script detected that you're trying to format a system drive. If you're certain this is a USB drive:
- Double-check the device path
- Verify it's not your system drive using `lsblk`:
  ```bash
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
  ```

## Safety Recommendations

1. **Always use interactive mode first**: It's the safest way to select the correct device
2. **Double-check device information**: Verify the size and model match your USB drive
3. **Backup important data**: Formatting erases all data permanently
4. **Use `--list` to verify**: List devices before formatting to ensure you have the right one
5. **Avoid `--force` in scripts**: Only use `--force` when you're absolutely certain

## How It Works

1. **Device Detection**: Scans `/dev/sd*`, `/dev/nvme*`, and `/dev/mmcblk*` for block devices
2. **Removability Check**: Uses `/sys/block/*/removable` to identify USB devices
3. **System Drive Protection**: Compares devices against the root filesystem mount point
4. **Unmounting**: Uses `findmnt` to find mount points and `umount` to unmount
5. **Formatting**: Uses `mkfs.vfat` or `mkfs.fat` with FAT32 format (`-F 32`)

## License

This tool is provided as-is for educational and utility purposes.

## Contributing

Feel free to submit issues or pull requests to improve this tool.

