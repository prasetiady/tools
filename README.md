# Tools Repository

A collection of useful command-line tools for various tasks.

## Available Tools

### Apple File Cleaner
A CLI tool to recursively delete Apple-related system files (`.DS_Store`, `._*`, etc.) from directories.

**Location**: `./apple-file-cleaner/`
**Usage**: See the [Apple File Cleaner README](./apple-file-cleaner/README.md) for detailed documentation.

Quick start:
```bash
cd apple-file-cleaner
./clean-apple-files.sh --dry-run
```

### USB FAT32 Formatter
A user-friendly CLI tool to format USB drives to FAT32 format with safety checks and interactive device selection.

**Location**: `./usb-formatter/`
**Usage**: See the [USB Formatter README](./usb-formatter/README.md) for detailed documentation.

Quick start:
```bash
cd usb-formatter
sudo ./format-usb.sh
```

## Adding New Tools

When adding new tools to this repository:

1. Create a new folder with a descriptive name
2. Include the tool files and a dedicated README.md
3. Update this main README.md to list the new tool
4. Follow consistent naming conventions

## Repository Structure

```
tools/
├── README.md                    # This file
├── apple-file-cleaner/          # Apple File Cleaner tool
│   ├── clean-apple-files.sh     # Main script
│   └── README.md               # Tool documentation
├── usb-formatter/               # USB FAT32 Formatter tool
│   ├── format-usb.sh           # Main script
│   └── README.md               # Tool documentation
└── [future-tools]/             # Additional tools will go here
```

## Contributing

Each tool should be self-contained with its own documentation and installation instructions.
