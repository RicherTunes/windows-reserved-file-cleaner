# Windows Reserved File Cleaner

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows-blue?logo=windows" alt="Platform">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

A PowerShell script to find and safely delete files with Windows reserved device names (`nul`, `con`, `aux`, etc.) that AI coding assistants accidentally create.

```
  ██╗    ██╗██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗
  ██║    ██║██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝
  ██║ █╗ ██║██║██╔██╗ ██║██║  ██║██║   ██║██║ █╗ ██║███████╗
  ╚███╔███╔╝██║██║ ╚████║██████╔╝╚██████╔╝╚███╔███╔╝███████║
   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚══════╝

  ██████╗ ███████╗███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
  ██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
  ██████╔╝█████╗  ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██║  ██║
  ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═════╝

  ███████╗██╗██╗     ███████╗     ██████╗██╗     ███████╗ █████╗ ███╗   ██╗███████╗██████╗
  ██╔════╝██║██║     ██╔════╝    ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██╔════╝██╔══██╗
  █████╗  ██║██║     █████╗      ██║     ██║     █████╗  ███████║██╔██╗ ██║█████╗  ██████╔╝
  ╚═╝     ╚═╝╚══════╝╚══════╝     ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝
```

---

## The Problem

AI coding assistants like **Claude Code**, **GitHub Copilot**, **Cursor**, and others sometimes generate Unix-style output redirection commands that create literal files named `nul`, `con`, `aux`, etc. on Windows:

```bash
# AI might suggest this command, which creates a literal "nul" file on Windows
echo "test" > nul

# Or redirect output to "nul" thinking it discards output
command > nul 2>&1
```

**These files cannot be deleted through normal means:**
- Windows Explorer shows an error
- `del nul` doesn't work
- `Remove-Item nul` fails
- Right-click → Delete fails

This is because Windows reserves these names for legacy device compatibility (dating back to MS-DOS).

---

## The Solution

This script uses the `\\?\` extended path prefix to bypass Windows reserved name checking and safely delete these files.

---

## Quick Start

### Option 1: One-liner (Download and List)

```powershell
# Download and scan your system (safe - list only, no deletion)
irm https://raw.githubusercontent.com/RicherTunes/windows-reserved-file-cleaner/main/Remove-ReservedFiles.ps1 -OutFile Remove-ReservedFiles.ps1; .\Remove-ReservedFiles.ps1 -List
```

### Option 2: Clone and Run

```powershell
git clone https://github.com/RicherTunes/windows-reserved-file-cleaner.git
cd windows-reserved-file-cleaner
.\Remove-ReservedFiles.ps1 -List
```

---

## Usage Examples

### Scan and List Files (Safe Mode)

```powershell
# List all reserved-name files on all drives
.\Remove-ReservedFiles.ps1 -List

# List files in a specific folder
.\Remove-ReservedFiles.ps1 -Path "D:\Projects" -List

# List with verbose output
.\Remove-ReservedFiles.ps1 -List -Verbose
```

### Delete Files

```powershell
# Interactive: confirm each file before deletion
.\Remove-ReservedFiles.ps1 -Interactive

# Delete all with single confirmation prompt
.\Remove-ReservedFiles.ps1

# Delete all without any confirmation (use with caution!)
.\Remove-ReservedFiles.ps1 -Force
```

### Dry Run (Preview Only)

```powershell
# See what would be deleted without actually deleting
.\Remove-ReservedFiles.ps1 -WhatIf
```

### Exclude Folders

```powershell
# Skip node_modules and .git folders
.\Remove-ReservedFiles.ps1 -Exclude "node_modules", ".git"

# Skip multiple patterns
.\Remove-ReservedFiles.ps1 -Exclude "node_modules", ".git", "vendor", "dist"
```

### Safe Deletion (Recoverable)

```powershell
# Move to Recycle Bin instead of permanent delete
.\Remove-ReservedFiles.ps1 -UseRecycleBin

# Backup files before deletion
.\Remove-ReservedFiles.ps1 -BackupPath "C:\Backup\reserved-files"

# Both: backup AND use Recycle Bin
.\Remove-ReservedFiles.ps1 -UseRecycleBin -BackupPath "C:\Backup"
```

### Targeted Scanning

```powershell
# Scan only 3 levels deep (faster)
.\Remove-ReservedFiles.ps1 -List -MaxDepth 3

# Scan network drive
.\Remove-ReservedFiles.ps1 -Path "\\server\share\projects" -List
```

### Export and Logging

```powershell
# Output as JSON (for automation)
.\Remove-ReservedFiles.ps1 -List -OutputFormat JSON

# Output as CSV (for spreadsheets)
.\Remove-ReservedFiles.ps1 -List -OutputFormat CSV

# Save detailed log file
.\Remove-ReservedFiles.ps1 -Force -LogFile "cleanup.log"

# Generate HTML report
.\Remove-ReservedFiles.ps1 -List -Report "scan-report.html"
```

### Automation & Scheduled Tasks

```powershell
# Save your preferred settings
.\Remove-ReservedFiles.ps1 -Exclude "node_modules",".git" -UseRecycleBin -SaveConfig

# Install weekly scheduled scan (runs Sundays at 3 AM)
.\Remove-ReservedFiles.ps1 -InstallTask

# Remove scheduled task
.\Remove-ReservedFiles.ps1 -UninstallTask

# Check for updates
.\Remove-ReservedFiles.ps1 -CheckUpdate
```

---

## Parameters Reference

### Core Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Path` | string[] | Paths to scan. Defaults to all fixed drives. |
| `-List` | switch | List files only, no deletion prompts. |
| `-Interactive` | switch | Prompt for each file (Y/N/All/Quit). |
| `-Force` | switch | Delete all without confirmation. |
| `-WhatIf` | switch | Dry run - show what would be deleted. |
| `-Exclude` | string[] | Patterns to exclude (e.g., "node_modules"). |

### Safety & Recovery

| Parameter | Type | Description |
|-----------|------|-------------|
| `-UseRecycleBin` | switch | Move to Recycle Bin instead of permanent delete. |
| `-BackupPath` | string | Copy files here before deletion. |
| `-WarnSize` | int | Warn for files larger than this (KB, default: 100). |
| `-MaxDepth` | int | Max directory depth (1-100, default: unlimited). |

### Output & Logging

| Parameter | Type | Description |
|-----------|------|-------------|
| `-OutputFormat` | string | Output format: Table (default), CSV, or JSON. |
| `-LogFile` | string | Path to save detailed log file. |
| `-Report` | string | Generate HTML report at this path. |
| `-Quiet` | switch | Suppress banner and decorations (for scripting). |
| `-Verbose` | switch | Show detailed scanning progress. |

### Retry & Reliability

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Retry` | int | Retry attempts for locked files (0-10, default: 0). |
| `-RetryDelay` | int | Seconds between retries (1-60, default: 2). |

### Configuration & Automation

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Config` | string | Path to config file (default: ~/.reserved-cleaner.json). |
| `-SaveConfig` | switch | Save current parameters as defaults. |
| `-InstallTask` | switch | Install weekly scheduled task (requires admin). |
| `-UninstallTask` | switch | Remove scheduled task (requires admin). |
| `-CheckUpdate` | switch | Check for new versions online. |
| `-Version` | switch | Display version information and exit. |

---

## Reserved Names Detected

The script detects all **22 Windows reserved device names**:

| Category | Names |
|----------|-------|
| Null device | `NUL` |
| Console | `CON` |
| Printer | `PRN` |
| Auxiliary | `AUX` |
| Serial ports | `COM1`, `COM2`, `COM3`, `COM4`, `COM5`, `COM6`, `COM7`, `COM8`, `COM9` |
| Parallel ports | `LPT1`, `LPT2`, `LPT3`, `LPT4`, `LPT5`, `LPT6`, `LPT7`, `LPT8`, `LPT9` |

Detection is **case-insensitive** (`nul`, `NUL`, and `Nul` are all matched).

---

## Sample Output

```
  ╔════════════════════════════════════════════════════════════════╗
  ║              SCAN RESULTS                                      ║
  ╚════════════════════════════════════════════════════════════════╝

  Found 3 reserved-name file(s):

       nul    |        0 B | 2025-01-15 10:30 | D:\Projects\my-app\nul
       NUL    |      156 B | 2025-01-20 14:22 | C:\Users\Dev\code\NUL
  [R]  aux    |        0 B | 2025-01-22 09:15 | D:\temp\aux

  Legend: [R] = Read-only file

  ╔════════════════════════════════════════════════════════════════╗
  ║              OPERATION SUMMARY                                 ║
  ╚════════════════════════════════════════════════════════════════╝

  Total files found:    3
  Successfully deleted: 3

  [SUCCESS] All files cleaned successfully!
```

---

## Features

- **Safe by default** - Lists files first, requires confirmation before deletion
- **Path validation** - Sanitizes paths to prevent command injection
- **Read-only support** - Handles read-only files automatically
- **Locked file detection** - Clear error messages when files are in use
- **Exclusion patterns** - Skip folders like `node_modules`, `.git`, etc.
- **Multiple output formats** - Table, CSV, JSON for automation
- **Detailed logging** - Optional log file for audit trails
- **Progress indication** - Shows scan progress and file counts
- **CI/CD friendly** - Proper exit codes (0=success, 1=error, 2=partial)
- **Admin safety** - Extra confirmation when running as admin on system drive
- **Beautiful CLI** - ASCII art banner, colored output, clear status icons

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all operations completed |
| 1 | Error - no files were deleted |
| 2 | Partial - some files deleted, some failed |

Use these for CI/CD pipelines or automation scripts.

---

## How It Works

Windows reserves certain filenames for legacy device compatibility. The `\\?\` prefix tells Windows to pass the path directly to the filesystem without interpretation, bypassing the reserved name check:

```powershell
# This fails:
Remove-Item -Path "C:\Projects\nul"

# PowerShell's Remove-Item doesn't support \\?\, so we use cmd.exe:
cmd /c "del /f /q \\?\C:\Projects\nul"
```

---

## Creating Test Files

To test the script, you can create reserved-name files using cmd.exe:

```cmd
mkdir C:\temp\reserved-test
echo test > \\?\C:\temp\reserved-test\nul
echo test > \\?\C:\temp\reserved-test\con
echo test > \\?\C:\temp\reserved-test\aux
```

Then run:
```powershell
.\Remove-ReservedFiles.ps1 -Path "C:\temp\reserved-test" -List
```

---

## Requirements

- **Windows 10/11** or Windows Server 2016+
- **PowerShell 5.1** (built-in) or PowerShell 7+

---

## Troubleshooting

### "Access denied" error
Run PowerShell as Administrator:
1. Right-click PowerShell
2. Select "Run as administrator"
3. Run the script again

### File is locked
Close any applications that might be using the file (IDEs, file explorers, etc.) and try again.

### Script won't run (execution policy)
```powershell
# Option 1: Bypass for this session
powershell -ExecutionPolicy Bypass -File .\Remove-ReservedFiles.ps1 -List

# Option 2: Unblock the downloaded file
Unblock-File .\Remove-ReservedFiles.ps1
```

---

## FAQ

**Q: Is this safe to run?**
A: Yes. By default, it only lists files and asks for confirmation before any deletion. Use `-List` to scan without any deletion capability.

**Q: Will this delete important system files?**
A: No. It only targets files with exact reserved names (nul, con, aux, etc.) which are never legitimate files on Windows.

**Q: Can I automate this?**
A: Yes. Use `-Force` for unattended deletion, `-OutputFormat JSON` for parsing, and check exit codes for success/failure.

**Q: Why can't I just delete these files normally?**
A: Windows intercepts these filenames at the API level for legacy compatibility. The `\\?\` prefix bypasses this check.

---

## Contributing

Issues and pull requests are welcome! If you find a bug or have a feature request, please [open an issue](https://github.com/RicherTunes/windows-reserved-file-cleaner/issues).

---

## License

MIT License - See [LICENSE](LICENSE) file for details.

---

## See Also

- [DEV Community - Delete NUL file on Windows 11](https://dev.to/tishonator/how-to-delete-the-un-deletable-nul-file-created-by-claude-console-on-windows-11-33a9)
- [Microsoft Q&A - Can't delete NUL file](https://learn.microsoft.com/en-us/answers/questions/2642852/cant-delete-nul-file-(solved))
- [Microsoft Docs - Naming Files, Paths, and Namespaces](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file)

---

<p align="center">
  Made with frustration after AI tools kept creating <code>nul</code> files on Windows.
</p>
