# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-28

### Added
- Initial release
- Scan and delete files with Windows reserved device names (NUL, CON, PRN, AUX, COM1-9, LPT1-9)
- Multiple operation modes: List, Interactive, Force, WhatIf (dry run)
- Path validation to prevent command injection attacks
- Read-only file handling with automatic attribute removal
- Locked file detection with helpful error messages
- Exclusion patterns to skip folders like `node_modules`, `.git`
- Multiple output formats: Table, CSV, JSON
- Detailed logging with `-LogFile` parameter
- Progress indication during scans
- CI/CD friendly exit codes (0=success, 1=error, 2=partial)
- Admin safety confirmation when using `-Force` on system drives
- ASCII art banner and color-coded status output
- Comprehensive documentation with examples

### Technical Details
- Uses `\\?\` extended path prefix via `cmd.exe` to bypass Windows reserved name restrictions
- PowerShell 5.1+ compatible
- Works on Windows 10/11 and Windows Server 2016+

[1.0.0]: https://github.com/RicherTunes/windows-reserved-file-cleaner/releases/tag/v1.0.0
