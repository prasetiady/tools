# Apple File Cleaner CLI

A simple command-line tool to recursively delete Apple-related system files from directories. This tool helps clean up macOS-generated files that can clutter your file system.

## Features

- **Recursive cleaning**: Searches through all subdirectories
- **Dry-run mode**: Preview what would be deleted without actually deleting
- **Comprehensive patterns**: Removes all common Apple system files
- **Color-coded output**: Easy-to-read terminal output
- **Verbose mode**: Detailed file listing
- **Safe operation**: No confirmation prompts (as requested)

## Apple Files Cleaned

The tool removes the following Apple-related files:

- `.DS_Store` - Finder metadata files
- `._*` - AppleDouble resource fork files
- `.Spotlight-V100` - Spotlight index files
- `.Trashes` - Trash folder metadata
- `.fseventsd` - File system event store
- `.TemporaryItems` - Temporary file metadata
- `.DocumentRevisions-V100` - Document revision files
- `.VolumeIcon.icns` - Volume icon files
- `.AppleDB` - Apple database files
- `.AppleDesktop` - Desktop metadata
- `.AppleDouble` - AppleDouble files

## Installation

1. Download the script:
   ```bash
   curl -O https://raw.githubusercontent.com/your-repo/apple-file-cleaner/main/clean-apple-files.sh
   ```

2. Make it executable:
   ```bash
   chmod +x clean-apple-files.sh
   ```

3. (Optional) Move to your PATH:
   ```bash
   sudo mv clean-apple-files.sh /usr/local/bin/clean-apple-files
   ```

## Usage

### Basic Usage

```bash
# Clean current directory
./clean-apple-files.sh

# Clean specific directory
./clean-apple-files.sh /path/to/directory
```

### Options

- `--dry-run, -n`: Show what would be deleted without actually deleting
- `--verbose, -v`: Show detailed output with file paths
- `--help, -h`: Show help message

### Examples

```bash
# Preview what would be deleted (recommended first run)
./clean-apple-files.sh --dry-run

# Clean current directory with verbose output
./clean-apple-files.sh --verbose

# Dry run on specific directory with detailed output
./clean-apple-files.sh --dry-run --verbose /home/user/projects

# Clean a specific directory
./clean-apple-files.sh /path/to/your/project
```

## Safety Recommendations

1. **Always use dry-run first**: Run with `--dry-run` to see what will be deleted
2. **Backup important data**: Ensure you have backups before running
3. **Test on a copy**: Try the tool on a copy of your data first
4. **Check permissions**: Make sure you have write permissions to the target directory

## Output Example

```
Apple File Cleaner CLI
================================

[INFO] Scanning directory: /home/user/projects
[INFO] DRY RUN MODE - No files will be deleted

[INFO] Found 3 file(s) matching pattern: .DS_Store
  /home/user/projects/folder1/.DS_Store
  /home/user/projects/folder2/.DS_Store
  /home/user/projects/folder3/.DS_Store

[INFO] Found 1 file(s) matching pattern: ._*
  /home/user/projects/folder1/._document.pdf

[INFO] Would delete 4 Apple file(s)

[INFO] Operation completed
```

## Requirements

- Bash shell (available on all Unix-like systems)
- `find` command (standard on most systems)
- `realpath` command (usually available, fallback can be added if needed)

## License

This tool is provided as-is for educational and utility purposes.

## Contributing

Feel free to submit issues or pull requests to improve this tool.

## Troubleshooting

### Permission Denied
If you get permission errors, make sure you have write access to the target directory:
```bash
ls -la /path/to/directory
```

### Script Not Found
If you get "command not found", make sure the script is executable and in your PATH:
```bash
chmod +x clean-apple-files.sh
./clean-apple-files.sh --help
```

### No Files Found
This is normal if there are no Apple files in the target directory. The tool will report "No Apple files found".
