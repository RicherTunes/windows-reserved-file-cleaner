# Contributing to Windows Reserved File Cleaner

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Bugs

1. **Check existing issues** - Search [existing issues](https://github.com/RicherTunes/windows-reserved-file-cleaner/issues) to avoid duplicates
2. **Create a new issue** with:
   - Clear, descriptive title
   - Steps to reproduce
   - Expected vs actual behavior
   - PowerShell version (`$PSVersionTable.PSVersion`)
   - Windows version
   - Any error messages (full text)

### Suggesting Features

1. **Open an issue** describing:
   - The use case / problem you're solving
   - Your proposed solution
   - Any alternatives you've considered

### Submitting Code

1. **Fork the repository**
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following the code style below
4. **Test thoroughly** on Windows
5. **Commit with clear messages**:
   ```bash
   git commit -m "Add feature: description of what it does"
   ```
6. **Push and create a Pull Request**

## Code Style

### PowerShell Guidelines

- Use **PascalCase** for function names: `Remove-ReservedFile`
- Use **camelCase** for local variables: `$fileCount`
- Use **PascalCase** for parameters: `-FilePath`
- Include comment-based help for functions
- Use `[CmdletBinding()]` for advanced functions
- Prefer `-ErrorAction` over `try/catch` for simple cases
- Always use `-LiteralPath` instead of `-Path` when dealing with special characters

### Formatting

- 4-space indentation (no tabs)
- Opening braces on same line
- One blank line between functions
- Keep lines under 120 characters when possible

### Example

```powershell
function Get-SomeData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [switch]$Verbose
    )

    $results = [System.Collections.ArrayList]::new()

    Get-ChildItem -LiteralPath $InputPath -File | ForEach-Object {
        $null = $results.Add($_.Name)
    }

    return $results
}
```

## Testing

Before submitting:

1. **Test on Windows** - This is a Windows-only tool
2. **Test all modes**: `-List`, `-Interactive`, `-Force`, `-WhatIf`
3. **Test with edge cases**:
   - Paths with spaces
   - Read-only files
   - Deep directory structures
   - Large scans (1000+ files)

### Creating Test Files

```cmd
mkdir C:\temp\test-reserved
echo test > \\?\C:\temp\test-reserved\nul
echo test > \\?\C:\temp\test-reserved\con
echo test > \\?\C:\temp\test-reserved\aux
attrib +r \\?\C:\temp\test-reserved\aux
```

## Pull Request Process

1. Update `CHANGELOG.md` with your changes under "Unreleased"
2. Update `README.md` if adding new features or parameters
3. Ensure all tests pass
4. Request review from maintainers

## Questions?

Open an issue with the "question" label or start a discussion.

---

Thank you for contributing!
