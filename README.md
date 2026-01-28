# Windows Reserved File Cleaner

A PowerShell script to find and delete files with Windows reserved device names (`nul`, `con`, `aux`, etc.) that AI coding assistants accidentally create.

## The Problem

AI tools like Claude Code, GitHub Copilot, and others sometimes generate Unix-style output redirection commands that create literal files named `nul`, `con`, `aux`, etc. on Windows:

```bash
# AI might suggest this, which creates a literal "nul" file on Windows
echo "test" > nul
```

These files cannot be deleted through normal means (Explorer, `del`, `Remove-Item`) because Windows treats them as reserved device names.

## The Solution

This script uses the `\\?\` extended path prefix to bypass Windows reserved name checking and safely delete these files.

## Quick Start

```powershell
# Download and run (list mode first to see what's there)
.\Remove-ReservedFiles.ps1 -List

# Delete all found files (with confirmation)
.\Remove-ReservedFiles.ps1
```

## Installation

### Option 1: Download directly
```powershell
# Download the script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/windows-reserved-file-cleaner/main/Remove-ReservedFiles.ps1" -OutFile "Remove-ReservedFiles.ps1"
```

### Option 2: Clone the repository
```powershell
git clone https://github.com/YOUR_USERNAME/windows-reserved-file-cleaner.git
cd windows-reserved-file-cleaner
```

## Usage

### List all reserved-name files (no deletion)
```powershell
.\Remove-ReservedFiles.ps1 -List
```

### Scan specific folders
```powershell
.\Remove-ReservedFiles.ps1 -Path "C:\Projects", "D:\Code" -List
```

### Dry run (see what would be deleted)
```powershell
.\Remove-ReservedFiles.ps1 -WhatIf
```

### Interactive mode (confirm each file)
```powershell
.\Remove-ReservedFiles.ps1 -Interactive
```

### Delete all without confirmation
```powershell
.\Remove-ReservedFiles.ps1 -Force
```

### Verbose output (see scanning progress)
```powershell
.\Remove-ReservedFiles.ps1 -List -Verbose
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-Path` | Paths to scan. Defaults to all fixed drives if not specified. |
| `-List` | List files only, no deletion prompts. |
| `-Interactive` | Prompt for each file individually (Y/N/All/Quit). |
| `-Force` | Delete all without any confirmation. |
| `-WhatIf` | Show what would be deleted without actually deleting. |
| `-Verbose` | Show detailed scanning progress. |

**Default behavior** (no switches): Lists found files, then asks for batch confirmation before deleting.

## Reserved Names Detected

The script detects all 22 Windows reserved device names:

- `NUL`, `CON`, `PRN`, `AUX`
- `COM1` through `COM9`
- `LPT1` through `LPT9`

Detection is case-insensitive (`nul`, `NUL`, and `Nul` are all matched).

## Example Output

```
Found 3 reserved-name file(s):

Name Path                              Size  Modified
---- ----                              ----  --------
nul  D:\Projects\my-app\nul            0 B   2025-01-15 10:30
NUL  C:\Users\Dev\code\test\NUL        156 B 2025-01-20 14:22
aux  D:\temp\aux                       0 B   2025-01-22 09:15

Delete all 3 file(s)? [Y]es/[N]o:
```

## How It Works

Windows reserves certain filenames for legacy device compatibility. The `\\?\` prefix tells Windows to pass the path directly to the filesystem without interpretation, bypassing the reserved name check:

```powershell
# This fails:
Remove-Item -Path "C:\Projects\nul"

# This works:
Remove-Item -LiteralPath "\\?\C:\Projects\nul"
```

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

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Windows 10/11 or Windows Server 2016+

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

Issues and pull requests are welcome! If you find a bug or have a feature request, please open an issue.

## See Also

- [DEV Community - Delete NUL file on Windows 11](https://dev.to/tishonator/how-to-delete-the-un-deletable-nul-file-created-by-claude-console-on-windows-11-33a9)
- [Microsoft Q&A - Can't delete NUL file](https://learn.microsoft.com/en-us/answers/questions/2642852/cant-delete-nul-file-(solved))
