<#
.SYNOPSIS
    Removes files with Windows reserved device names (nul, con, aux, etc.)

.DESCRIPTION
    AI tools sometimes create literal files named "nul", "con", etc. on Windows
    when outputting Unix-style redirection. These files cannot be deleted normally
    because they're reserved device names. This script uses the \\?\ extended path
    prefix to bypass Win32 reserved name checking and delete them.

.PARAMETER Path
    Paths to scan. Defaults to all fixed drives if not specified.

.PARAMETER List
    List files only, no deletion prompts.

.PARAMETER Interactive
    Prompt for each file individually.

.PARAMETER Force
    Delete all without any confirmation.

.PARAMETER WhatIf
    Show what would be deleted (dry run).

.PARAMETER Exclude
    Glob patterns to exclude from scanning (e.g., "node_modules", "*.git*").

.PARAMETER LogFile
    Path to write log file for audit trail.

.PARAMETER OutputFormat
    Output format for results: Table (default), CSV, or JSON.

.PARAMETER Verbose
    Show detailed scanning progress.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -List
    Lists all reserved-name files on all fixed drives.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -Path "D:\Projects" -Interactive
    Scans D:\Projects and prompts for each file.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -Force -Exclude "node_modules",".git"
    Deletes all reserved-name files, excluding node_modules and .git folders.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -List -OutputFormat JSON -LogFile "scan.log"
    Lists files in JSON format and writes log to scan.log.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Path,
    [switch]$List,
    [switch]$Interactive,
    [switch]$Force,
    [string[]]$Exclude,
    [string]$LogFile,
    [ValidateSet('Table', 'CSV', 'JSON')]
    [string]$OutputFormat = 'Table'
)

# Exit codes
$Script:EXIT_SUCCESS = 0
$Script:EXIT_ERROR = 1
$Script:EXIT_PARTIAL = 2

# Reserved device names (22 total)
$ReservedNames = @('NUL', 'CON', 'PRN', 'AUX') +
                 (1..9 | ForEach-Object { "COM$_"; "LPT$_" })

# Log buffer for file output
$Script:LogBuffer = [System.Collections.ArrayList]::new()

#region ASCII Art and Display Functions

function Show-Banner {
    $cyan = [ConsoleColor]::Cyan
    $white = [ConsoleColor]::White
    $gray = [ConsoleColor]::Gray

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor $cyan
    Write-Host "      WINDOWS RESERVED FILE CLEANER" -ForegroundColor $white
    Write-Host "  ================================================================" -ForegroundColor $cyan
    Write-Host ""
    Write-Host "      _   _ _   _ _        ____ _     _____    _    _   _ _____ ____  " -ForegroundColor $cyan
    Write-Host "     | \ | | | | | |      / ___| |   | ____|  / \  | \ | | ____|  _ \ " -ForegroundColor $cyan
    Write-Host "     |  \| | | | | |     | |   | |   |  _|   / _ \ |  \| |  _| | |_) |" -ForegroundColor $cyan
    Write-Host "     | |\  | |_| | |___  | |___| |___| |___ / ___ \| |\  | |___|  _ < " -ForegroundColor $cyan
    Write-Host "     |_| \_|\___/|_____|  \____|_____|_____/_/   \_\_| \_|_____|_| \_\" -ForegroundColor $cyan
    Write-Host ""
    Write-Host "  Removes files with reserved Windows names (nul, con, aux, etc.)" -ForegroundColor $white
    Write-Host "  These files are often accidentally created by AI coding assistants." -ForegroundColor $gray
    Write-Host ""
}

function Write-Step {
    param(
        [string]$Icon,
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host "  $Icon " -ForegroundColor $Color -NoNewline
    Write-Host $Message
}

function Write-Success { param([string]$Message) Write-Step "[OK]" $Message ([ConsoleColor]::Green) }
function Write-Info    { param([string]$Message) Write-Step "[i]" $Message ([ConsoleColor]::Cyan) }
function Write-Warn    { param([string]$Message) Write-Step "[!]" $Message ([ConsoleColor]::Yellow) }
function Write-Err     { param([string]$Message) Write-Step "[X]" $Message ([ConsoleColor]::Red) }

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    $null = $Script:LogBuffer.Add($logLine)

    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose $Message
    }
}

#endregion

#region Validation Functions

function Test-ValidPath {
    param([string]$PathToTest)

    # Check for command injection characters
    $dangerousChars = @('&', '|', ';', '`', '$', '(', ')', '{', '}', '[', ']', '<', '>')

    foreach ($char in $dangerousChars) {
        if ($PathToTest.Contains($char)) {
            return @{ Valid = $false; Reason = "Path contains potentially dangerous character: $char" }
        }
    }

    # Check if path exists
    if (-not (Test-Path -LiteralPath $PathToTest -ErrorAction SilentlyContinue)) {
        return @{ Valid = $false; Reason = "Path does not exist" }
    }

    return @{ Valid = $true; Reason = $null }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsSystemDrive {
    param([string]$DrivePath)
    $systemDrive = $env:SystemDrive
    return $DrivePath.StartsWith($systemDrive, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ShouldExclude {
    param(
        [string]$FilePath,
        [string[]]$ExcludePatterns
    )

    if (-not $ExcludePatterns) { return $false }

    foreach ($pattern in $ExcludePatterns) {
        if ($FilePath -like "*$pattern*") {
            return $true
        }
    }
    return $false
}

#endregion

#region Core Functions

function Find-ReservedFiles {
    param(
        [string[]]$ScanPaths,
        [string[]]$ExcludePatterns
    )

    $results = [System.Collections.ArrayList]::new()
    $totalPaths = $ScanPaths.Count
    $currentPathIndex = 0
    $filesScanned = 0

    Write-Host ""
    Write-Info "Starting scan..."
    Write-Host ""

    foreach ($scanPath in $ScanPaths) {
        $currentPathIndex++
        $percentComplete = [Math]::Round(($currentPathIndex - 1) / $totalPaths * 100)

        Write-Progress -Activity "Scanning for reserved-name files" `
                       -Status "[$percentComplete%] Scanning: $scanPath" `
                       -PercentComplete $percentComplete `
                       -CurrentOperation "Files checked: $filesScanned"

        Write-Log "Scanning: $scanPath"

        try {
            Get-ChildItem -LiteralPath $scanPath -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $filesScanned++

                    if ($_.Name -in $ReservedNames) {
                        # Check exclusions
                        if (Test-ShouldExclude -FilePath $_.FullName -ExcludePatterns $ExcludePatterns) {
                            Write-Log "Excluded: $($_.FullName)" 'DEBUG'
                            return
                        }

                        $fileInfo = [PSCustomObject]@{
                            Name       = $_.Name
                            Path       = $_.FullName
                            Directory  = $_.DirectoryName
                            Size       = $_.Length
                            Modified   = $_.LastWriteTime
                            ReadOnly   = $_.IsReadOnly
                            Attributes = $_.Attributes.ToString()
                        }

                        $null = $results.Add($fileInfo)
                        Write-Log "Found: $($_.FullName)"
                    }
                }
        }
        catch {
            Write-Log "Error scanning ${scanPath}: $_" 'ERROR'
            Write-Warn "Could not fully scan: $scanPath"
        }
    }

    Write-Progress -Activity "Scanning for reserved-name files" -Completed

    Write-Log "Scan complete. Found $($results.Count) reserved-name file(s). Scanned $filesScanned files total."
    Write-Info "Scanned $filesScanned files across $totalPaths location(s)"

    return $results
}

function Remove-ReservedFile {
    param(
        [string]$FilePath,
        [switch]$IsReadOnly
    )

    # Validate path before passing to cmd.exe
    $validation = Test-ValidPath -PathToTest $FilePath
    if (-not $validation.Valid) {
        return @{
            Success = $false
            Error   = "Path validation failed: $($validation.Reason)"
            Status  = 'ValidationFailed'
        }
    }

    # Use extended path prefix to bypass reserved name checking
    # PowerShell's Remove-Item doesn't support \\?\ prefix, so use cmd.exe
    $ntPath = "\\?\$FilePath"

    try {
        # Handle read-only files with /a flag
        $delFlags = "/f /q"
        if ($IsReadOnly) {
            $delFlags = "/f /q /a"
            Write-Log "File is read-only, using /a flag: $FilePath"
        }

        $output = cmd /c "del $delFlags `"$ntPath`"" 2>&1

        # Check for specific error conditions
        if ($LASTEXITCODE -ne 0) {
            $errorMsg = $output -join ' '

            if ($errorMsg -match 'being used by another process') {
                return @{
                    Success = $false
                    Error   = "File is locked by another application. Close any programs using this file and try again."
                    Status  = 'Locked'
                }
            }
            elseif ($errorMsg -match 'Access is denied') {
                return @{
                    Success = $false
                    Error   = "Access denied. Try running PowerShell as Administrator."
                    Status  = 'AccessDenied'
                }
            }
            else {
                return @{
                    Success = $false
                    Error   = "Deletion failed: $errorMsg"
                    Status  = 'Failed'
                }
            }
        }

        # Verify the file was actually deleted
        if (Test-Path -LiteralPath $FilePath) {
            return @{
                Success = $false
                Error   = "File still exists after deletion attempt. It may be locked or protected."
                Status  = 'StillExists'
            }
        }

        Write-Log "Deleted: $FilePath"
        return @{
            Success = $true
            Error   = $null
            Status  = 'Deleted'
        }
    }
    catch {
        Write-Log "Exception deleting ${FilePath}: $_" 'ERROR'
        return @{
            Success = $false
            Error   = $_.Exception.Message
            Status  = 'Exception'
        }
    }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -lt 1KB) { return "$Bytes B" }
    elseif ($Bytes -lt 1MB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    elseif ($Bytes -lt 1GB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    else { return "{0:N1} GB" -f ($Bytes / 1GB) }
}

function Show-Results {
    param(
        $Files,
        [string]$Format = 'Table'
    )

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "                         SCAN RESULTS" -ForegroundColor White
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($Files.Count -eq 0) {
        Write-Success "No reserved-name files found. Your system is clean!"
        return
    }

    Write-Host "  Found " -NoNewline
    Write-Host "$($Files.Count)" -ForegroundColor Yellow -NoNewline
    Write-Host " reserved-name file(s):"
    Write-Host ""

    switch ($Format) {
        'CSV' {
            $csvData = $Files | ForEach-Object {
                [PSCustomObject]@{
                    Name       = $_.Name
                    Path       = $_.Path
                    Size       = $_.Size
                    Modified   = $_.Modified.ToString("yyyy-MM-dd HH:mm:ss")
                    ReadOnly   = $_.ReadOnly
                    Attributes = $_.Attributes
                }
            }
            $csvData | ConvertTo-Csv -NoTypeInformation | ForEach-Object { Write-Host $_ }
        }
        'JSON' {
            $jsonData = $Files | ForEach-Object {
                [PSCustomObject]@{
                    Name       = $_.Name
                    Path       = $_.Path
                    Size       = $_.Size
                    Modified   = $_.Modified.ToString("yyyy-MM-dd HH:mm:ss")
                    ReadOnly   = $_.ReadOnly
                    Attributes = $_.Attributes
                }
            }
            $jsonData | ConvertTo-Json -Depth 2 | ForEach-Object { Write-Host $_ }
        }
        default {
            # Table format with nice formatting
            foreach ($f in $Files) {
                $icon = if ($f.ReadOnly) { "[R]" } else { "   " }
                $sizeStr = (Format-FileSize $f.Size).PadLeft(10)
                $dateStr = $f.Modified.ToString("yyyy-MM-dd HH:mm")

                Write-Host "  $icon " -ForegroundColor Yellow -NoNewline
                Write-Host $f.Name.PadRight(6) -ForegroundColor White -NoNewline
                Write-Host " : " -ForegroundColor DarkGray -NoNewline
                Write-Host $sizeStr -ForegroundColor Cyan -NoNewline
                Write-Host " : " -ForegroundColor DarkGray -NoNewline
                Write-Host $dateStr -ForegroundColor Gray -NoNewline
                Write-Host " : " -ForegroundColor DarkGray -NoNewline
                Write-Host $f.Path -ForegroundColor White
            }
            Write-Host ""
            Write-Host "  Legend: [R] = Read-only file" -ForegroundColor Gray
        }
    }
}

function Show-Summary {
    param(
        [int]$Total,
        [int]$Deleted,
        [int]$Failed,
        [int]$Skipped
    )

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "                      OPERATION SUMMARY" -ForegroundColor White
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  Total files found:    " -NoNewline
    Write-Host "$Total" -ForegroundColor White

    Write-Host "  Successfully deleted: " -NoNewline
    Write-Host "$Deleted" -ForegroundColor Green

    if ($Failed -gt 0) {
        Write-Host "  Failed to delete:     " -NoNewline
        Write-Host "$Failed" -ForegroundColor Red
    }

    if ($Skipped -gt 0) {
        Write-Host "  Skipped by user:      " -NoNewline
        Write-Host "$Skipped" -ForegroundColor Yellow
    }

    Write-Host ""

    if ($Deleted -eq $Total -and $Total -gt 0) {
        Write-Host "  [SUCCESS] " -ForegroundColor Green -NoNewline
        Write-Host "All files cleaned successfully!" -ForegroundColor White
    }
    elseif ($Deleted -gt 0) {
        Write-Host "  [PARTIAL] " -ForegroundColor Yellow -NoNewline
        Write-Host "Some files could not be deleted. See errors above." -ForegroundColor White
    }
    elseif ($Failed -gt 0) {
        Write-Host "  [FAILED] " -ForegroundColor Red -NoNewline
        Write-Host "No files were deleted. Check permissions or close applications using the files." -ForegroundColor White
    }

    Write-Host ""
}

function Save-Log {
    param([string]$LogPath)

    if (-not $LogPath) { return }

    try {
        $Script:LogBuffer | Out-File -FilePath $LogPath -Encoding UTF8
        Write-Info "Log saved to: $LogPath"
    }
    catch {
        Write-Warn "Could not save log file: $_"
    }
}

#endregion

#region Main Logic

# Show banner
Show-Banner

# Log start
Write-Log "=== Windows Reserved File Cleaner started ==="
$paramString = "Path=$Path, List=$List, Interactive=$Interactive, Force=$Force, Exclude=$Exclude"
Write-Log "Parameters: $paramString"

# Admin and system drive warning
if ($Force -and (Test-IsAdmin)) {
    $hasSystemDrive = $false
    foreach ($p in $Path) {
        if (Test-IsSystemDrive -DrivePath $p) {
            $hasSystemDrive = $true
            break
        }
    }

    if ($hasSystemDrive -or -not $Path) {
        Write-Host ""
        Write-Warn "WARNING: Running with -Force as Administrator on system drive!"
        Write-Warn "This will delete ALL reserved-name files without confirmation."
        Write-Host ""
        $confirm = Read-Host "  Are you sure you want to continue? (Type 'YES' to confirm)"
        if ($confirm -ne 'YES') {
            Write-Info "Operation cancelled by user."
            exit $EXIT_SUCCESS
        }
    }
}

# Determine scan paths
if (-not $Path) {
    $Path = Get-Volume |
            Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } |
            ForEach-Object { "$($_.DriveLetter):\" }

    if (-not $Path) {
        Write-Err "No fixed drives found to scan."
        exit $EXIT_ERROR
    }

    Write-Info "Scanning all fixed drives: $($Path -join ', ')"
}

# Validate paths
$validPaths = @()
foreach ($p in $Path) {
    $validation = Test-ValidPath -PathToTest $p
    if ($validation.Valid) {
        $validPaths += $p
    }
    else {
        Write-Warn "Skipping invalid path: $p ($($validation.Reason))"
        Write-Log "Invalid path skipped: $p - $($validation.Reason)" 'WARN'
    }
}

if ($validPaths.Count -eq 0) {
    Write-Err "No valid paths to scan."
    exit $EXIT_ERROR
}

# Show exclusions if any
if ($Exclude) {
    Write-Info "Excluding patterns: $($Exclude -join ', ')"
}

# Find files
$files = Find-ReservedFiles -ScanPaths $validPaths -ExcludePatterns $Exclude

# Display results
Show-Results -Files $files -Format $OutputFormat

if ($files.Count -eq 0) {
    Save-Log -LogPath $LogFile
    exit $EXIT_SUCCESS
}

# Handle modes
if ($List) {
    Write-Info "List mode - no files were modified."
    Save-Log -LogPath $LogFile
    exit $EXIT_SUCCESS
}

if ($WhatIfPreference) {
    Write-Host ""
    Write-Info "DRY RUN - No files will be deleted:"
    Write-Host ""
    foreach ($file in $files) {
        Write-Host "  Would delete: " -NoNewline
        Write-Host $file.Path -ForegroundColor Yellow
    }
    Save-Log -LogPath $LogFile
    exit $EXIT_SUCCESS
}

# Deletion tracking
$deleted = 0
$failed = 0
$skipped = 0
$errors = [System.Collections.ArrayList]::new()

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host "                        DELETION MODE" -ForegroundColor White
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host ""

if ($Force) {
    # Delete all without confirmation
    Write-Info "Force mode - deleting all files..."
    Write-Host ""

    foreach ($file in $files) {
        $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly
        if ($result.Success) {
            Write-Success "Deleted: $($file.Path)"
            $deleted++
        }
        else {
            Write-Err "Failed: $($file.Path)"
            Write-Host "         Reason: $($result.Error)" -ForegroundColor Gray
            $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error; Status = $result.Status })
            $failed++
        }
    }
}
elseif ($Interactive) {
    # Prompt for each file
    Write-Info "Interactive mode - you will be prompted for each file."
    Write-Host ""

    $deleteAll = $false

    foreach ($file in $files) {
        if ($deleteAll) {
            $choice = 'Y'
        }
        else {
            $sizeStr = Format-FileSize $file.Size
            $roIndicator = ""
            if ($file.ReadOnly) { $roIndicator = " [READ-ONLY]" }

            Write-Host ""
            Write-Host "  File: " -NoNewline
            Write-Host $file.Path -ForegroundColor Yellow
            Write-Host "  Size: $sizeStr$roIndicator" -ForegroundColor Gray
            Write-Host ""
            $choice = Read-Host "  Delete this file? [Y]es / [N]o / [A]ll / [Q]uit"
        }

        switch -Regex ($choice) {
            '^[Yy]' {
                $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly
                if ($result.Success) {
                    Write-Success "Deleted: $($file.Path)"
                    $deleted++
                }
                else {
                    Write-Err "Failed: $($file.Path)"
                    Write-Host "         Reason: $($result.Error)" -ForegroundColor Gray
                    $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error; Status = $result.Status })
                    $failed++
                }
            }
            '^[Aa]' {
                $deleteAll = $true
                $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly
                if ($result.Success) {
                    Write-Success "Deleted: $($file.Path)"
                    $deleted++
                }
                else {
                    Write-Err "Failed: $($file.Path)"
                    Write-Host "         Reason: $($result.Error)" -ForegroundColor Gray
                    $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error; Status = $result.Status })
                    $failed++
                }
            }
            '^[Qq]' {
                Write-Warn "Quitting at user request."
                $skipped = $files.Count - $deleted - $failed
                break
            }
            default {
                Write-Host "  Skipped." -ForegroundColor Gray
                $skipped++
            }
        }
    }
}
else {
    # Default: batch confirmation
    Write-Host "  Delete all " -NoNewline
    Write-Host "$($files.Count)" -ForegroundColor Yellow -NoNewline
    Write-Host " file(s)?"
    Write-Host ""
    $response = Read-Host "  Type [Y]es to confirm or [N]o to cancel"

    if ($response -match '^[Yy]') {
        Write-Host ""
        foreach ($file in $files) {
            $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly
            if ($result.Success) {
                Write-Success "Deleted: $($file.Path)"
                $deleted++
            }
            else {
                Write-Err "Failed: $($file.Path)"
                Write-Host "         Reason: $($result.Error)" -ForegroundColor Gray
                $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error; Status = $result.Status })
                $failed++
            }
        }
    }
    else {
        Write-Info "Operation cancelled by user."
        Save-Log -LogPath $LogFile
        exit $EXIT_SUCCESS
    }
}

# Show summary
Show-Summary -Total $files.Count -Deleted $deleted -Failed $failed -Skipped $skipped

# Log completion
$completionMsg = "=== Operation completed: $deleted deleted, $failed failed, $skipped skipped ==="
Write-Log $completionMsg

# Save log file
Save-Log -LogPath $LogFile

# Exit with appropriate code
if ($failed -eq 0) {
    exit $EXIT_SUCCESS
}
elseif ($deleted -gt 0) {
    exit $EXIT_PARTIAL
}
else {
    exit $EXIT_ERROR
}

#endregion
