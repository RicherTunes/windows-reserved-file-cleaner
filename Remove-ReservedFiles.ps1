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

.PARAMETER Quiet
    Suppress banner and non-essential output (for scripting).

.PARAMETER Retry
    Number of retry attempts for locked files (default: 0).

.PARAMETER RetryDelay
    Delay in seconds between retry attempts (default: 2).

.PARAMETER UseRecycleBin
    Move files to Recycle Bin instead of permanent deletion.

.PARAMETER BackupPath
    Copy files to this directory before deletion.

.PARAMETER MaxDepth
    Maximum directory recursion depth (default: unlimited).

.PARAMETER WarnSize
    Warn before deleting files larger than this size in KB (default: 100).

.PARAMETER Report
    Generate an HTML report at the specified path.

.PARAMETER Config
    Path to configuration file (default: ~/.reserved-cleaner.json).

.PARAMETER SaveConfig
    Save current parameters as default configuration.

.PARAMETER InstallTask
    Install a Windows scheduled task for weekly scans.

.PARAMETER UninstallTask
    Remove the Windows scheduled task.

.PARAMETER CheckUpdate
    Check for new versions online.

.PARAMETER Version
    Display version information and exit.

.PARAMETER Verbose
    Show detailed scanning progress.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -List
    Lists all reserved-name files on all fixed drives.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -Path "D:\Projects" -UseRecycleBin
    Delete files by moving them to Recycle Bin (recoverable).

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -Force -BackupPath "C:\Backup"
    Backup files before deleting them.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -List -MaxDepth 3
    Scan only 3 levels deep.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -Report "scan-report.html"
    Generate an HTML report of the scan.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -SaveConfig
    Save current settings as defaults.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -InstallTask
    Set up automatic weekly scanning.
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
    [string]$OutputFormat = 'Table',
    [switch]$Quiet,
    [ValidateRange(0, 10)]
    [int]$Retry = 0,
    [ValidateRange(1, 60)]
    [int]$RetryDelay = 2,
    [switch]$UseRecycleBin,
    [string]$BackupPath,
    [ValidateRange(1, 100)]
    [int]$MaxDepth = 0,
    [ValidateRange(0, 1048576)]
    [int]$WarnSize = 100,
    [string]$Report,
    [string]$Config,
    [switch]$SaveConfig,
    [switch]$InstallTask,
    [switch]$UninstallTask,
    [switch]$CheckUpdate,
    [switch]$Version
)

#region Script Configuration

$Script:ScriptVersion = "1.1.0"
$Script:REPO_URL = "https://github.com/RicherTunes/windows-reserved-file-cleaner"
$Script:RELEASES_API = "https://api.github.com/repos/RicherTunes/windows-reserved-file-cleaner/releases/latest"
$Script:TASK_NAME = "ReservedFileCleaner-WeeklyScan"
$Script:DEFAULT_CONFIG_PATH = Join-Path $env:USERPROFILE ".reserved-cleaner.json"

# Exit codes
$Script:EXIT_SUCCESS = 0
$Script:EXIT_ERROR = 1
$Script:EXIT_PARTIAL = 2

# Reserved device names (22 total)
$ReservedNames = @('NUL', 'CON', 'PRN', 'AUX') +
                 (1..9 | ForEach-Object { "COM$_"; "LPT$_" })

# Log buffer for file output
$Script:LogBuffer = [System.Collections.ArrayList]::new()

# Statistics tracking
$Script:Stats = @{
    StartTime = $null
    EndTime = $null
    FilesScanned = 0
    FilesFound = 0
    FilesDeleted = 0
    FilesFailed = 0
    FilesSkipped = 0
    BytesFreed = 0
    Errors = [System.Collections.ArrayList]::new()
}

#endregion

#region ASCII Art and Display Functions

function Show-Version {
    Write-Host "Windows Reserved File Cleaner v$Script:ScriptVersion"
    Write-Host "Repository: $Script:REPO_URL"
    Write-Host ""
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "OS: $([System.Environment]::OSVersion.VersionString)"
}

function Show-Banner {
    if ($Script:Quiet) { return }

    $cyan = [ConsoleColor]::Cyan
    $white = [ConsoleColor]::White
    $gray = [ConsoleColor]::Gray

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor $cyan
    Write-Host "      WINDOWS RESERVED FILE CLEANER v$Script:ScriptVersion" -ForegroundColor $white
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
        [ConsoleColor]$Color = [ConsoleColor]::White,
        [switch]$ForceShow
    )
    if ($Script:Quiet -and -not $ForceShow) { return }
    Write-Host "  $Icon " -ForegroundColor $Color -NoNewline
    Write-Host $Message
}

function Write-Success { param([string]$Message, [switch]$ForceShow) Write-Step "[OK]" $Message ([ConsoleColor]::Green) -ForceShow:$ForceShow }
function Write-Info    { param([string]$Message, [switch]$ForceShow) Write-Step "[i]" $Message ([ConsoleColor]::Cyan) -ForceShow:$ForceShow }
function Write-Warn    { param([string]$Message, [switch]$ForceShow) Write-Step "[!]" $Message ([ConsoleColor]::Yellow) -ForceShow:$ForceShow }
function Write-Err     { param([string]$Message, [switch]$ForceShow) Write-Step "[X]" $Message ([ConsoleColor]::Red) -ForceShow:$ForceShow }

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

#region Configuration Functions

function Get-ConfigPath {
    if ($Config) { return $Config }
    return $Script:DEFAULT_CONFIG_PATH
}

function Import-Configuration {
    $configPath = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) { return @{} }

    try {
        $content = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $config = @{}
        $content.PSObject.Properties | ForEach-Object { $config[$_.Name] = $_.Value }
        Write-Log "Loaded configuration from: $configPath"
        return $config
    }
    catch {
        Write-Log "Failed to load config: $_" 'WARN'
        return @{}
    }
}

function Export-Configuration {
    param([hashtable]$Settings)

    $configPath = Get-ConfigPath

    try {
        $Settings | ConvertTo-Json -Depth 2 | Out-File -FilePath $configPath -Encoding UTF8
        Write-Success "Configuration saved to: $configPath"
        return $true
    }
    catch {
        Write-Err "Failed to save configuration: $_"
        return $false
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

function Test-IsUNCPath {
    param([string]$TestPath)
    return $TestPath.StartsWith("\\") -and -not $TestPath.StartsWith("\\?\")
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

function Request-Elevation {
    if (Test-IsAdmin) { return $true }

    Write-Warn "This operation requires administrator privileges."
    $response = Read-Host "  Restart as Administrator? [Y]es/[N]o"

    if ($response -match '^[Yy]') {
        $scriptPath = $PSCommandPath
        $arguments = $MyInvocation.Line -replace [regex]::Escape($MyInvocation.InvocationName), ""
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments"
        exit $EXIT_SUCCESS
    }

    return $false
}

#endregion

#region Core Functions

function Find-ReservedFiles {
    param(
        [string[]]$ScanPaths,
        [string[]]$ExcludePatterns,
        [int]$MaxRecursionDepth = 0
    )

    $results = [System.Collections.ArrayList]::new()
    $totalPaths = $ScanPaths.Count
    $currentPathIndex = 0

    Write-Host ""
    Write-Info "Starting scan..."
    Write-Host ""

    $Script:Stats.StartTime = Get-Date

    foreach ($scanPath in $ScanPaths) {
        $currentPathIndex++
        $percentComplete = [Math]::Round(($currentPathIndex - 1) / $totalPaths * 100)

        Write-Progress -Activity "Scanning for reserved-name files" `
                       -Status "[$percentComplete%] Scanning: $scanPath" `
                       -PercentComplete $percentComplete `
                       -CurrentOperation "Files checked: $($Script:Stats.FilesScanned)"

        Write-Log "Scanning: $scanPath"

        # Handle UNC paths
        $isUNC = Test-IsUNCPath -TestPath $scanPath
        if ($isUNC) {
            Write-Log "UNC path detected: $scanPath" 'INFO'
        }

        try {
            $gciParams = @{
                LiteralPath = $scanPath
                Recurse = $true
                File = $true
                ErrorAction = 'SilentlyContinue'
            }

            # Add depth limit if specified
            if ($MaxRecursionDepth -gt 0) {
                $gciParams['Depth'] = $MaxRecursionDepth
            }

            Get-ChildItem @gciParams | ForEach-Object {
                $Script:Stats.FilesScanned++

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
                    $Script:Stats.FilesFound++
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

    $Script:Stats.EndTime = Get-Date
    $duration = $Script:Stats.EndTime - $Script:Stats.StartTime

    Write-Log "Scan complete. Found $($results.Count) reserved-name file(s). Scanned $($Script:Stats.FilesScanned) files in $($duration.TotalSeconds.ToString('F1'))s"
    Write-Info "Scanned $($Script:Stats.FilesScanned) files across $totalPaths location(s) in $($duration.TotalSeconds.ToString('F1'))s"

    return $results
}

function Backup-ReservedFile {
    param(
        [string]$FilePath,
        [string]$BackupDirectory
    )

    if (-not $BackupDirectory) { return @{ Success = $true } }

    try {
        # Create backup directory if needed
        if (-not (Test-Path -LiteralPath $BackupDirectory)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }

        # Create unique backup filename
        $fileName = Split-Path $FilePath -Leaf
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupName = "${fileName}_${timestamp}_$(Get-Random -Maximum 9999)"
        $backupPath = Join-Path $BackupDirectory $backupName

        # Use extended path for copy
        $ntPath = "\\?\$FilePath"
        Copy-Item -LiteralPath $ntPath -Destination $backupPath -Force -ErrorAction Stop

        Write-Log "Backed up: $FilePath -> $backupPath"
        return @{ Success = $true; BackupPath = $backupPath }
    }
    catch {
        Write-Log "Backup failed for ${FilePath}: $_" 'ERROR'
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Move-ToRecycleBin {
    param([string]$FilePath)

    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $ntPath = "\\?\$FilePath"

        # FileSystem.DeleteFile with RecycleOption
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $FilePath,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )

        Write-Log "Moved to Recycle Bin: $FilePath"
        return @{ Success = $true; Error = $null; Status = 'Recycled' }
    }
    catch {
        # Fall back to cmd.exe deletion if recycle fails
        Write-Log "Recycle Bin failed, trying direct delete: $FilePath" 'WARN'
        return $null  # Signal to try regular deletion
    }
}

function Remove-ReservedFile {
    param(
        [string]$FilePath,
        [switch]$IsReadOnly,
        [int]$RetryCount = 0,
        [int]$RetryDelaySeconds = 2,
        [switch]$ToRecycleBin,
        [string]$BackupDir
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

    # Backup if requested
    if ($BackupDir) {
        $backupResult = Backup-ReservedFile -FilePath $FilePath -BackupDirectory $BackupDir
        if (-not $backupResult.Success) {
            return @{
                Success = $false
                Error   = "Backup failed: $($backupResult.Error)"
                Status  = 'BackupFailed'
            }
        }
    }

    # Try Recycle Bin if requested
    if ($ToRecycleBin) {
        $recycleResult = Move-ToRecycleBin -FilePath $FilePath
        if ($recycleResult) {
            return $recycleResult
        }
        # If null, fall through to regular deletion
        Write-Log "Falling back to permanent deletion for: $FilePath" 'WARN'
    }

    # Use extended path prefix to bypass reserved name checking
    $ntPath = "\\?\$FilePath"

    $attempt = 0
    $maxAttempts = $RetryCount + 1

    while ($attempt -lt $maxAttempts) {
        $attempt++

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
                $isLocked = $errorMsg -match 'being used by another process'
                $isAccessDenied = $errorMsg -match 'Access is denied'

                # Retry logic for locked files
                if ($isLocked -and $attempt -lt $maxAttempts) {
                    Write-Log "File locked, attempt $attempt of $maxAttempts. Retrying in $RetryDelaySeconds seconds: $FilePath" 'WARN'
                    if (-not $Script:Quiet) {
                        Write-Host "         Retry $attempt/$maxAttempts in ${RetryDelaySeconds}s (file locked)..." -ForegroundColor Gray
                    }
                    Start-Sleep -Seconds $RetryDelaySeconds
                    continue
                }

                if ($isLocked) {
                    return @{
                        Success = $false
                        Error   = "File is locked by another application. Close any programs using this file and try again."
                        Status  = 'Locked'
                    }
                }
                elseif ($isAccessDenied) {
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

    return @{
        Success = $false
        Error   = "Unexpected error during deletion"
        Status  = 'Unknown'
    }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -lt 1KB) { return "$Bytes B" }
    elseif ($Bytes -lt 1MB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    elseif ($Bytes -lt 1GB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    else { return "{0:N1} GB" -f ($Bytes / 1GB) }
}

function Format-Duration {
    param([TimeSpan]$Duration)

    if ($Duration.TotalSeconds -lt 60) {
        return "$($Duration.TotalSeconds.ToString('F1'))s"
    }
    elseif ($Duration.TotalMinutes -lt 60) {
        return "$($Duration.Minutes)m $($Duration.Seconds)s"
    }
    else {
        return "$($Duration.Hours)h $($Duration.Minutes)m $($Duration.Seconds)s"
    }
}

#endregion

#region Display Functions

function Show-Results {
    param(
        $Files,
        [string]$Format = 'Table'
    )

    # In quiet mode with JSON/CSV, output only the data
    if ($Script:Quiet -and $Format -ne 'Table') {
        if ($Files.Count -eq 0) {
            switch ($Format) {
                'CSV' { Write-Output '"Name","Path","Size","Modified","ReadOnly","Attributes"' }
                'JSON' { Write-Output '[]' }
            }
            return
        }

        $outputData = $Files | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.Name
                Path       = $_.Path
                Size       = $_.Size
                Modified   = $_.Modified.ToString("yyyy-MM-dd HH:mm:ss")
                ReadOnly   = $_.ReadOnly
                Attributes = $_.Attributes
            }
        }

        switch ($Format) {
            'CSV' { $outputData | ConvertTo-Csv -NoTypeInformation }
            'JSON' { $outputData | ConvertTo-Json -Depth 2 }
        }
        return
    }

    if (-not $Script:Quiet) {
        Write-Host ""
        Write-Host "  ================================================================" -ForegroundColor Cyan
        Write-Host "                         SCAN RESULTS" -ForegroundColor White
        Write-Host "  ================================================================" -ForegroundColor Cyan
        Write-Host ""
    }

    if ($Files.Count -eq 0) {
        Write-Success "No reserved-name files found. Your system is clean!"
        return
    }

    if (-not $Script:Quiet) {
        Write-Host "  Found " -NoNewline
        Write-Host "$($Files.Count)" -ForegroundColor Yellow -NoNewline
        Write-Host " reserved-name file(s):"
        Write-Host ""
    }

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
            foreach ($f in $Files) {
                $icon = if ($f.ReadOnly) { "[R]" } else { "   " }
                $sizeStr = (Format-FileSize $f.Size).PadLeft(10)
                $dateStr = $f.Modified.ToString("yyyy-MM-dd HH:mm")

                # Warn for large files
                if ($f.Size -gt ($WarnSize * 1KB)) {
                    $icon = "[!]"
                }

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
            Write-Host "  Legend: [R] = Read-only, [!] = Large file (>$WarnSize KB)" -ForegroundColor Gray
        }
    }
}

function Show-Summary {
    param(
        [int]$Total,
        [int]$Deleted,
        [int]$Failed,
        [int]$Skipped,
        [long]$BytesFreed
    )

    if ($Script:Quiet) { return }

    $duration = if ($Script:Stats.EndTime -and $Script:Stats.StartTime) {
        $Script:Stats.EndTime - $Script:Stats.StartTime
    } else {
        [TimeSpan]::Zero
    }

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
    Write-Host "  Space freed:          " -NoNewline
    Write-Host "$(Format-FileSize $BytesFreed)" -ForegroundColor Cyan

    Write-Host "  Duration:             " -NoNewline
    Write-Host "$(Format-Duration $duration)" -ForegroundColor Gray

    if ($Script:Stats.FilesScanned -gt 0 -and $duration.TotalSeconds -gt 0) {
        $filesPerSec = [Math]::Round($Script:Stats.FilesScanned / $duration.TotalSeconds)
        Write-Host "  Scan speed:           " -NoNewline
        Write-Host "$filesPerSec files/sec" -ForegroundColor Gray
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

#endregion

#region Report Generation

function New-HtmlReport {
    param(
        $Files,
        [string]$OutputPath
    )

    $duration = if ($Script:Stats.EndTime -and $Script:Stats.StartTime) {
        $Script:Stats.EndTime - $Script:Stats.StartTime
    } else {
        [TimeSpan]::Zero
    }

    $totalSize = ($Files | Measure-Object -Property Size -Sum).Sum
    $scanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reserved File Cleaner Report</title>
    <style>
        :root { --bg: #1a1a2e; --card: #16213e; --accent: #0f3460; --text: #e4e4e4; --success: #4ade80; --warning: #fbbf24; --error: #f87171; --info: #60a5fa; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); padding: 2rem; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: var(--info); margin-bottom: 0.5rem; }
        .subtitle { color: #888; margin-bottom: 2rem; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
        .stat-card { background: var(--card); padding: 1.5rem; border-radius: 8px; border-left: 4px solid var(--accent); }
        .stat-value { font-size: 2rem; font-weight: bold; color: var(--info); }
        .stat-label { color: #888; font-size: 0.9rem; margin-top: 0.25rem; }
        .stat-card.success .stat-value { color: var(--success); }
        .stat-card.warning .stat-value { color: var(--warning); }
        .stat-card.error .stat-value { color: var(--error); }
        table { width: 100%; border-collapse: collapse; background: var(--card); border-radius: 8px; overflow: hidden; }
        th, td { padding: 1rem; text-align: left; border-bottom: 1px solid var(--accent); }
        th { background: var(--accent); font-weight: 600; }
        tr:hover { background: rgba(255,255,255,0.05); }
        .size { font-family: monospace; color: var(--info); }
        .path { font-family: monospace; font-size: 0.85rem; word-break: break-all; }
        .readonly { color: var(--warning); }
        .footer { margin-top: 2rem; text-align: center; color: #666; font-size: 0.85rem; }
        .footer a { color: var(--info); }
        .empty-state { text-align: center; padding: 3rem; color: var(--success); }
        .empty-state h2 { font-size: 1.5rem; margin-bottom: 0.5rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Windows Reserved File Cleaner</h1>
        <p class="subtitle">Scan Report - $scanDate</p>

        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value">$($Script:Stats.FilesScanned.ToString('N0'))</div>
                <div class="stat-label">Files Scanned</div>
            </div>
            <div class="stat-card $(if ($Files.Count -gt 0) { 'warning' } else { 'success' })">
                <div class="stat-value">$($Files.Count)</div>
                <div class="stat-label">Reserved Files Found</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$(Format-FileSize $totalSize)</div>
                <div class="stat-label">Total Size</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$(Format-Duration $duration)</div>
                <div class="stat-label">Scan Duration</div>
            </div>
        </div>

$(if ($Files.Count -eq 0) {
@"
        <div class="empty-state">
            <h2>No Reserved Files Found</h2>
            <p>Your system is clean!</p>
        </div>
"@
} else {
@"
        <table>
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Size</th>
                    <th>Modified</th>
                    <th>Path</th>
                </tr>
            </thead>
            <tbody>
$($Files | ForEach-Object {
    $roClass = if ($_.ReadOnly) { ' class="readonly"' } else { '' }
    $roIndicator = if ($_.ReadOnly) { ' [R]' } else { '' }
    "                <tr>
                    <td$roClass>$($_.Name)$roIndicator</td>
                    <td class=`"size`">$(Format-FileSize $_.Size)</td>
                    <td>$($_.Modified.ToString('yyyy-MM-dd HH:mm'))</td>
                    <td class=`"path`">$($_.Path)</td>
                </tr>"
})
            </tbody>
        </table>
"@
})

        <div class="footer">
            Generated by <a href="$Script:REPO_URL">Windows Reserved File Cleaner</a> v$Script:ScriptVersion
        </div>
    </div>
</body>
</html>
"@

    try {
        $html | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Success "HTML report saved to: $OutputPath"
        return $true
    }
    catch {
        Write-Err "Failed to save HTML report: $_"
        return $false
    }
}

#endregion

#region Scheduled Task Functions

function Install-ScheduledTask {
    if (-not (Test-IsAdmin)) {
        Write-Err "Installing a scheduled task requires administrator privileges."
        if (-not (Request-Elevation)) {
            return $false
        }
    }

    $scriptPath = $PSCommandPath
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -List -LogFile `"$env:USERPROFILE\reserved-cleaner-scan.log`""

    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    try {
        Register-ScheduledTask -TaskName $Script:TASK_NAME `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description "Weekly scan for Windows reserved-name files created by AI tools" `
            -RunLevel Highest `
            -Force | Out-Null

        Write-Success "Scheduled task installed: $Script:TASK_NAME"
        Write-Info "The scan will run every Sunday at 3:00 AM"
        Write-Info "Log file: $env:USERPROFILE\reserved-cleaner-scan.log"
        return $true
    }
    catch {
        Write-Err "Failed to install scheduled task: $_"
        return $false
    }
}

function Uninstall-ScheduledTask {
    if (-not (Test-IsAdmin)) {
        Write-Err "Removing a scheduled task requires administrator privileges."
        return $false
    }

    try {
        Unregister-ScheduledTask -TaskName $Script:TASK_NAME -Confirm:$false -ErrorAction Stop
        Write-Success "Scheduled task removed: $Script:TASK_NAME"
        return $true
    }
    catch {
        if ($_.Exception.Message -match 'does not exist') {
            Write-Warn "Scheduled task not found: $Script:TASK_NAME"
        }
        else {
            Write-Err "Failed to remove scheduled task: $_"
        }
        return $false
    }
}

#endregion

#region Update Functions

function Get-LatestVersion {
    try {
        $response = Invoke-RestMethod -Uri $Script:RELEASES_API -TimeoutSec 10 -ErrorAction Stop
        $latestVersion = $response.tag_name -replace '^v', ''
        $downloadUrl = $response.assets | Where-Object { $_.name -eq 'Remove-ReservedFiles.ps1' } | Select-Object -ExpandProperty browser_download_url

        return @{
            Version = $latestVersion
            DownloadUrl = if ($downloadUrl) { $downloadUrl } else { $response.zipball_url }
            ReleaseUrl = $response.html_url
            ReleaseNotes = $response.body
        }
    }
    catch {
        Write-Log "Failed to check for updates: $_" 'ERROR'
        return $null
    }
}

function Test-NewVersionAvailable {
    $latest = Get-LatestVersion
    if (-not $latest) {
        Write-Warn "Could not check for updates. Please check your internet connection."
        return $false
    }

    $current = [Version]$Script:ScriptVersion
    $latestVer = [Version]$latest.Version

    if ($latestVer -gt $current) {
        Write-Host ""
        Write-Host "  ================================================================" -ForegroundColor Green
        Write-Host "                    NEW VERSION AVAILABLE" -ForegroundColor White
        Write-Host "  ================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Current version:  " -NoNewline
        Write-Host "v$Script:ScriptVersion" -ForegroundColor Yellow
        Write-Host "  Latest version:   " -NoNewline
        Write-Host "v$($latest.Version)" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Release URL: $($latest.ReleaseUrl)" -ForegroundColor Cyan
        Write-Host ""
        return $true
    }
    else {
        Write-Success "You are running the latest version (v$Script:ScriptVersion)"
        return $false
    }
}

#endregion

#region Log Functions

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

# Set script-level quiet flag
$Script:Quiet = $Quiet

# Handle version request
if ($Version) {
    Show-Version
    exit $EXIT_SUCCESS
}

# Handle update check
if ($CheckUpdate) {
    Show-Banner
    Test-NewVersionAvailable | Out-Null
    exit $EXIT_SUCCESS
}

# Handle scheduled task operations
if ($InstallTask) {
    Show-Banner
    if (Install-ScheduledTask) { exit $EXIT_SUCCESS } else { exit $EXIT_ERROR }
}

if ($UninstallTask) {
    Show-Banner
    if (Uninstall-ScheduledTask) { exit $EXIT_SUCCESS } else { exit $EXIT_ERROR }
}

# Load configuration
$loadedConfig = Import-Configuration
if ($loadedConfig.Count -gt 0 -and -not $Quiet) {
    Write-Log "Using saved configuration"
}

# Handle save config
if ($SaveConfig) {
    Show-Banner
    $configToSave = @{
        Exclude = $Exclude
        WarnSize = $WarnSize
        Retry = $Retry
        RetryDelay = $RetryDelay
        UseRecycleBin = $UseRecycleBin.IsPresent
        MaxDepth = $MaxDepth
    }
    if (Export-Configuration -Settings $configToSave) { exit $EXIT_SUCCESS } else { exit $EXIT_ERROR }
}

# Show banner
Show-Banner

# Log start
Write-Log "=== Windows Reserved File Cleaner v$Script:ScriptVersion started ==="
$paramString = "Path=$Path, List=$List, Force=$Force, UseRecycleBin=$UseRecycleBin, MaxDepth=$MaxDepth"
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
    # Handle UNC paths specially
    if (Test-IsUNCPath -TestPath $p) {
        if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
            $validPaths += $p
            Write-Info "UNC path detected: $p"
        }
        else {
            Write-Warn "UNC path not accessible: $p"
        }
        continue
    }

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

# Show options
if ($Exclude) { Write-Info "Excluding patterns: $($Exclude -join ', ')" }
if ($MaxDepth -gt 0) { Write-Info "Max depth: $MaxDepth levels" }
if ($UseRecycleBin) { Write-Info "Using Recycle Bin (files can be recovered)" }
if ($BackupPath) { Write-Info "Backup directory: $BackupPath" }

# Create backup directory if specified
if ($BackupPath -and -not (Test-Path -LiteralPath $BackupPath)) {
    try {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Info "Created backup directory: $BackupPath"
    }
    catch {
        Write-Err "Failed to create backup directory: $_"
        exit $EXIT_ERROR
    }
}

# Find files
$files = Find-ReservedFiles -ScanPaths $validPaths -ExcludePatterns $Exclude -MaxRecursionDepth $MaxDepth

# Display results
Show-Results -Files $files -Format $OutputFormat

# Generate HTML report if requested
if ($Report) {
    New-HtmlReport -Files $files -OutputPath $Report
}

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
$bytesFreed = 0
$errors = [System.Collections.ArrayList]::new()

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host "                        DELETION MODE" -ForegroundColor White
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host ""

if ($UseRecycleBin) {
    Write-Info "Files will be moved to Recycle Bin (recoverable)"
}

if ($Force) {
    Write-Info "Force mode - deleting all files..."
    Write-Host ""

    foreach ($file in $files) {
        # Warn for large files
        if ($file.Size -gt ($WarnSize * 1KB)) {
            Write-Warn "Large file: $($file.Path) ($(Format-FileSize $file.Size))"
        }

        $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly `
            -RetryCount $Retry -RetryDelaySeconds $RetryDelay `
            -ToRecycleBin:$UseRecycleBin -BackupDir $BackupPath

        if ($result.Success) {
            Write-Success "Deleted: $($file.Path)"
            $deleted++
            $bytesFreed += $file.Size
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
            $largeIndicator = ""
            if ($file.Size -gt ($WarnSize * 1KB)) { $largeIndicator = " [LARGE FILE]" }

            Write-Host ""
            Write-Host "  File: " -NoNewline
            Write-Host $file.Path -ForegroundColor Yellow
            Write-Host "  Size: $sizeStr$roIndicator$largeIndicator" -ForegroundColor Gray
            Write-Host ""
            $choice = Read-Host "  Delete this file? [Y]es / [N]o / [A]ll / [Q]uit"
        }

        switch -Regex ($choice) {
            '^[Yy]' {
                $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly `
                    -RetryCount $Retry -RetryDelaySeconds $RetryDelay `
                    -ToRecycleBin:$UseRecycleBin -BackupDir $BackupPath

                if ($result.Success) {
                    Write-Success "Deleted: $($file.Path)"
                    $deleted++
                    $bytesFreed += $file.Size
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
                $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly `
                    -RetryCount $Retry -RetryDelaySeconds $RetryDelay `
                    -ToRecycleBin:$UseRecycleBin -BackupDir $BackupPath

                if ($result.Success) {
                    Write-Success "Deleted: $($file.Path)"
                    $deleted++
                    $bytesFreed += $file.Size
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
            $result = Remove-ReservedFile -FilePath $file.Path -IsReadOnly:$file.ReadOnly `
                -RetryCount $Retry -RetryDelaySeconds $RetryDelay `
                -ToRecycleBin:$UseRecycleBin -BackupDir $BackupPath

            if ($result.Success) {
                Write-Success "Deleted: $($file.Path)"
                $deleted++
                $bytesFreed += $file.Size
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

# Update stats
$Script:Stats.FilesDeleted = $deleted
$Script:Stats.FilesFailed = $failed
$Script:Stats.FilesSkipped = $skipped
$Script:Stats.BytesFreed = $bytesFreed
$Script:Stats.EndTime = Get-Date

# Show summary
Show-Summary -Total $files.Count -Deleted $deleted -Failed $failed -Skipped $skipped -BytesFreed $bytesFreed

# Log completion
$completionMsg = "=== Operation completed: $deleted deleted, $failed failed, $skipped skipped, $(Format-FileSize $bytesFreed) freed ==="
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
