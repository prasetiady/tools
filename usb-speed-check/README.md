# USB Speed Check CLI

A command-line tool to test read and write speeds of USB drives on Linux. Detects USB interface version and measures actual throughput using `dd`.

## Features

- **USB interface detection**: Identifies USB 1.0/1.1/2.0/3.0/3.1/3.2 link speed from sysfs
- **Write speed test**: Measures actual write throughput with direct I/O
- **Read speed test**: Drops filesystem caches for accurate read measurements
- **Interactive mode**: List available USB devices and select from a menu
- **Auto-mount**: Temporarily mounts unmounted devices and cleans up after
- **Configurable test size**: Adjust test file size (default: 100MB)
- **Color-coded output**: Easy-to-read terminal output with color coding

## Requirements

- Linux operating system
- Root/sudo privileges (required for dropping caches and mounting)
- `dd` command (pre-installed on all Linux systems)
- `lsblk` command (pre-installed on most Linux systems)
- `bc` command (for speed calculations)
- Bash shell

## Installation

1. Make the script executable:
   ```bash
   chmod +x check-usb-speed.sh
   ```

2. (Optional) Install `bc` if not already installed:
   ```bash
   # Debian/Ubuntu
   sudo apt-get install bc

   # Arch Linux
   sudo pacman -S bc

   # Fedora/RHEL
   sudo dnf install bc
   ```

## Usage

### Interactive Mode (Recommended)

Simply run the script without arguments:

```bash
./check-usb-speed.sh
```

The script will automatically request sudo privileges if needed.

### Test a Specific Device

```bash
./check-usb-speed.sh /dev/sdb1
```

### List Available USB Devices

```bash
./check-usb-speed.sh --list
```

### Custom Test Size

```bash
./check-usb-speed.sh --size 256 /dev/sdb1
```

## Options

- `--list, -l`: List available USB devices and exit
- `--size, -s SIZE`: Test file size in MB (default: 100)
- `--help, -h`: Show help message

## Output Example

```
USB Speed Check CLI
================================

[INFO] Selected device: /dev/sdb
[INFO] Size: 14.9GiB USB: USB 3.0 (5 Gbps) Model: DataTraveler Mounted: /media/user/USB

Running speed test with 100MB test file...
========================================

[INFO] Testing write speed (100MB)...
[INFO] Testing read speed (100MB)...

========================================
Results for /dev/sdb
========================================

  Interface:    USB 3.0 (5 Gbps)
  Test size:    100MB
  Write speed:  28.50 MB/s
  Read speed:   115.20 MB/s

========================================

[SUCCESS] Speed test complete
```

## How It Works

1. **Device Detection**: Scans for removable block devices, filtering out system drives
2. **USB Speed Detection**: Walks the sysfs device tree to find the USB link speed
3. **Mount Handling**: Mounts the device if needed, cleans up temporary mounts on exit
4. **Write Test**: Uses `dd` with `oflag=direct` and `conv=fdatasync` to bypass OS cache
5. **Read Test**: Drops filesystem caches (`/proc/sys/vm/drop_caches`) before reading with `iflag=direct`
6. **Cleanup**: Removes test files and unmounts temporary mount points via trap handler

## Troubleshooting

### "No USB devices found"

- Ensure the USB drive is properly connected
- Check if the device appears in `lsblk` output
- Try unplugging and replugging the device

### Low Speed Results

- Close other applications accessing the USB drive
- Try a larger test size (`--size 512`) for more stable results
- Ensure the drive is connected to a USB 3.0 port if it supports it

### "Not enough free space"

The test file size will be automatically reduced to fit available space. To test with a specific size, free up space on the drive first.

## License

This tool is provided as-is for educational and utility purposes.
