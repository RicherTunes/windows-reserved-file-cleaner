# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-28

### Added
- **Recycle Bin support** (`-UseRecycleBin`): Move files to Recycle Bin instead of permanent deletion
- **Backup before delete** (`-BackupPath`): Copy files to a backup directory before deletion
- **Max depth limit** (`-MaxDepth`): Limit directory recursion depth for faster targeted scans
- **Large file warnings** (`-WarnSize`): Highlight files larger than threshold (default: 100 KB)
- **HTML reports** (`-Report`): Generate beautiful dark-themed HTML scan reports
- **Configuration file** (`-Config`, `-SaveConfig`): Save and load default settings
- **Scheduled tasks** (`-InstallTask`, `-UninstallTask`): Set up automatic weekly scans
- **Update checking** (`-CheckUpdate`): Check for new versions online
- **UNC path support**: Properly handle network paths (`\\server\share`)
- **Enhanced statistics**: Show space freed, scan speed (files/sec), duration
- **Elevation prompt**: Offer to restart as Administrator when needed

### Changed
- Version bumped to 1.1.0
- Improved summary output with more statistics
- Better error messages for common failure scenarios

### Fixed
- Proper handling of empty results in quiet JSON/CSV mode

## [1.0.0] - 2026-01-28

### Added
- Initial release
- Scan and delete files with Windows reserved device names (NUL, CON, PRN, AUX, COM1-9, LPT1-9)
- Multiple operation modes: List, Interactive, Force, WhatIf (dry run)
- Path validation to prevent command injection attacks
- Read-only file handling with automatic attribute removal
- Locked file detection with helpful error messages and retry logic
- Exclusion patterns to skip folders like `node_modules`, `.git`
- Multiple output formats: Table, CSV, JSON
- Detailed logging with `-LogFile` parameter
- Progress indication during scans
- CI/CD friendly exit codes (0=success, 1=error, 2=partial)
- Admin safety confirmation when using `-Force` on system drives
- Quiet mode (`-Quiet`) for scripting/automation
- ASCII art banner and color-coded status output
- Comprehensive documentation with examples

### Technical Details
- Uses `\\?\` extended path prefix via `cmd.exe` to bypass Windows reserved name restrictions
- PowerShell 5.1+ compatible
- Works on Windows 10/11 and Windows Server 2016+

[1.1.0]: https://github.com/RicherTunes/windows-reserved-file-cleaner/releases/tag/v1.1.0
[1.0.0]: https://github.com/RicherTunes/windows-reserved-file-cleaner/releases/tag/v1.0.0
