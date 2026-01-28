#Requires -Version 5.1

<#
.SYNOPSIS
    PowerShell module for finding and removing Windows reserved-name files.

.DESCRIPTION
    This module provides functions to scan for and safely delete files with
    Windows reserved device names (nul, con, aux, etc.) that AI coding
    assistants accidentally create.
#>

# Module version
$Script:ModuleVersion = '1.2.0'

# Reserved device names (22 total)
$Script:ReservedNames = @('NUL', 'CON', 'PRN', 'AUX') +
                        (1..9 | ForEach-Object { "COM$_"; "LPT$_" })

#region Helper Functions

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    elseif ($Bytes -lt 1MB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    elseif ($Bytes -lt 1GB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    else { return "{0:N1} GB" -f ($Bytes / 1GB) }
}

function Test-IsReservedName {
    param([string]$Name)
    return $Name -in $Script:ReservedNames
}

function Test-SafePath {
    <#
    .SYNOPSIS
        Validates a path for security concerns. Throws if path is invalid.
    #>
    param([string]$Path)

    # Check for dangerous characters that could enable command injection
    $dangerousChars = @(';', '|', '&', '`', '$', '>', '<', '!', '{', '}')
    foreach ($char in $dangerousChars) {
        if ($Path.Contains($char)) {
            throw "Invalid path: contains potentially dangerous character '$char'"
        }
    }
    # No return value - just throws on error
}

function Test-ReservedFileExists {
    <#
    .SYNOPSIS
        Tests if a reserved-name file exists using the extended path prefix.
    #>
    param([string]$FilePath)
    $ntPath = "\\?\$FilePath"
    return [System.IO.File]::Exists($ntPath)
}

#endregion

#region Public Functions

function Find-ReservedFiles {
    <#
    .SYNOPSIS
        Scans directories for files with Windows reserved names.

    .DESCRIPTION
        Recursively scans the specified paths for files named nul, con, aux, prn,
        com1-9, or lpt1-9. These are Windows reserved device names that cannot
        be deleted through normal means.

    .PARAMETER Path
        The paths to scan. Defaults to all fixed drives.

    .PARAMETER Exclude
        Patterns to exclude from scanning (e.g., "node_modules", ".git").

    .PARAMETER MaxDepth
        Maximum directory recursion depth. 0 = unlimited.

    .EXAMPLE
        Find-ReservedFiles -Path "D:\Projects"

    .EXAMPLE
        Find-ReservedFiles -Exclude "node_modules", ".git" -MaxDepth 5
    #>
    [CmdletBinding()]
    param(
        [string[]]$Path,
        [string[]]$Exclude,
        [int]$MaxDepth = 0
    )

    if (-not $Path) {
        $Path = Get-Volume |
                Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } |
                ForEach-Object { "$($_.DriveLetter):\" }
    }

    $results = [System.Collections.ArrayList]::new()

    foreach ($scanPath in $Path) {
        # Validate path for security
        Test-SafePath -Path $scanPath

        if (-not (Test-Path -LiteralPath $scanPath)) { continue }

        $gciParams = @{
            LiteralPath = $scanPath
            Recurse = $true
            File = $true
            ErrorAction = 'SilentlyContinue'
        }

        if ($MaxDepth -gt 0) {
            $gciParams['Depth'] = $MaxDepth
        }

        Get-ChildItem @gciParams | ForEach-Object {
            if ($_.Name -in $Script:ReservedNames) {
                # Check exclusions
                $excluded = $false
                foreach ($pattern in $Exclude) {
                    if ($_.FullName -like "*$pattern*") {
                        $excluded = $true
                        break
                    }
                }

                if (-not $excluded) {
                    $null = $results.Add([PSCustomObject]@{
                        Name       = $_.Name
                        Path       = $_.FullName
                        Directory  = $_.DirectoryName
                        Size       = $_.Length
                        Modified   = $_.LastWriteTime
                        ReadOnly   = $_.IsReadOnly
                    })
                }
            }
        }
    }

    return $results
}

function Remove-ReservedFile {
    <#
    .SYNOPSIS
        Removes a single reserved-name file.

    .DESCRIPTION
        Deletes a file with a Windows reserved name using the \\?\ extended
        path prefix to bypass Windows restrictions.

    .PARAMETER Path
        The full path to the file to delete.

    .PARAMETER UseRecycleBin
        Move to Recycle Bin instead of permanent deletion.

    .PARAMETER BackupPath
        Copy the file to this directory before deletion.

    .PARAMETER Force
        Skip confirmation prompts.

    .EXAMPLE
        Remove-ReservedFile -Path "D:\Projects\nul"

    .EXAMPLE
        Remove-ReservedFile -Path "D:\Projects\nul" -UseRecycleBin

    .EXAMPLE
        Remove-ReservedFile -Path "D:\Projects\nul" -BackupPath "C:\Backup"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Path,

        [switch]$UseRecycleBin,
        [string]$BackupPath,
        [switch]$Force
    )

    process {
        $result = [PSCustomObject]@{
            Path = $Path
            Success = $false
            Error = $null
        }

        # Skip if Path is empty
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $result.Error = "Path cannot be empty"
            Write-Error $result.Error
            return $result
        }

        # Use extended path to check existence for reserved names
        $ntPath = "\\?\$Path"
        if (-not [System.IO.File]::Exists($ntPath)) {
            $result.Error = "File not found: $Path"
            Write-Error $result.Error
            return $result
        }

        # Backup if requested (check for non-empty string)
        if (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
            if (-not (Test-Path $BackupPath)) {
                New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
            }
            $fileName = [System.IO.Path]::GetFileName($Path)
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backupFile = Join-Path $BackupPath "${timestamp}_${fileName}"
            try {
                cmd /c "copy `"$ntPath`" `"$backupFile`"" 2>$null
                Write-Verbose "Backed up to: $backupFile"
            }
            catch {
                Write-Warning "Backup failed: $_"
            }
        }

        if ($UseRecycleBin) {
            try {
                Add-Type -AssemblyName Microsoft.VisualBasic
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $Path,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
                Write-Verbose "Moved to Recycle Bin: $Path"
                $result.Success = $true
                return $result
            }
            catch {
                Write-Warning "Recycle Bin failed, trying direct delete"
            }
        }

        if ($PSCmdlet.ShouldProcess($Path, "Delete")) {
            $output = cmd /c "del /f /q /a `"$ntPath`"" 2>&1
            if ([System.IO.File]::Exists($ntPath)) {
                $result.Error = "Failed to delete: $Path"
                Write-Error $result.Error
            }
            else {
                Write-Verbose "Deleted: $Path"
                $result.Success = $true
            }
        }

        return $result
    }
}

function Remove-ReservedFiles {
    <#
    .SYNOPSIS
        Scans and removes all reserved-name files from specified paths.

    .DESCRIPTION
        Comprehensive function to find and delete files with Windows reserved
        names. Supports multiple safety options including Recycle Bin and backup.

    .PARAMETER Path
        Paths to scan. Defaults to all fixed drives.

    .PARAMETER Exclude
        Patterns to exclude (e.g., "node_modules").

    .PARAMETER UseRecycleBin
        Move files to Recycle Bin instead of permanent deletion.

    .PARAMETER BackupPath
        Copy files to this directory before deletion.

    .PARAMETER Force
        Delete without confirmation.

    .PARAMETER WhatIf
        Show what would be deleted without actually deleting.

    .EXAMPLE
        Remove-ReservedFiles -Path "D:\Projects" -UseRecycleBin

    .EXAMPLE
        Remove-ReservedFiles -Force -BackupPath "C:\Backup"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Path,
        [string[]]$Exclude,
        [switch]$UseRecycleBin,
        [string]$BackupPath,
        [switch]$Force,
        [int]$MaxDepth = 0
    )

    $result = [PSCustomObject]@{
        Found = 0
        Deleted = 0
        Failed = 0
        Files = @()
    }

    $files = Find-ReservedFiles -Path $Path -Exclude $Exclude -MaxDepth $MaxDepth
    $result.Found = $files.Count
    $result.Files = $files

    if ($files.Count -eq 0) {
        Write-Host "No reserved-name files found." -ForegroundColor Green
        return $result
    }

    Write-Host "Found $($files.Count) reserved-name file(s):" -ForegroundColor Yellow

    if (-not $Force -and -not $WhatIfPreference) {
        $confirm = Read-Host "Delete all files? [Y]es/[N]o"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return $result
        }
    }

    foreach ($file in $files) {
        # Skip files with empty or null paths
        if ([string]::IsNullOrWhiteSpace($file.Path)) {
            $result.Failed++
            continue
        }

        if ($PSCmdlet.ShouldProcess($file.Path, "Delete")) {
            $removeParams = @{
                Path = $file.Path
                UseRecycleBin = $UseRecycleBin.IsPresent
                Force = $true
            }
            if ($BackupPath) {
                $removeParams['BackupPath'] = $BackupPath
            }
            $deleteResult = Remove-ReservedFile @removeParams
            if ($deleteResult.Success) {
                $result.Deleted++
            }
            else {
                $result.Failed++
            }
        }
    }

    Write-Host "Deleted $($result.Deleted) file(s)." -ForegroundColor Green
    return $result
}

function Install-ReservedFileWatcher {
    <#
    .SYNOPSIS
        Installs a file system watcher for real-time reserved file detection.

    .DESCRIPTION
        Creates a background job that monitors specified directories for
        the creation of reserved-name files and can automatically delete them.

    .PARAMETER Path
        Paths to monitor.

    .PARAMETER AutoDelete
        Automatically delete detected files.

    .PARAMETER UseRecycleBin
        Move auto-deleted files to Recycle Bin.

    .EXAMPLE
        Install-ReservedFileWatcher -Path "D:\Projects" -AutoDelete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path,

        [switch]$AutoDelete,
        [switch]$UseRecycleBin
    )

    $watcherScript = {
        param($WatchPath, $ReservedNames, $AutoDelete, $UseRecycleBin)

        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $WatchPath
        $watcher.IncludeSubdirectories = $true
        $watcher.EnableRaisingEvents = $true

        $action = {
            $name = $Event.SourceEventArgs.Name
            $fullPath = $Event.SourceEventArgs.FullPath
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)

            if ($baseName -in $ReservedNames -or $name -in $ReservedNames) {
                Write-Host "[DETECTED] Reserved file created: $fullPath" -ForegroundColor Yellow

                if ($AutoDelete) {
                    Start-Sleep -Milliseconds 500  # Wait for file to be released

                    if ($UseRecycleBin) {
                        try {
                            Add-Type -AssemblyName Microsoft.VisualBasic
                            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                                $fullPath,
                                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                            )
                            Write-Host "[RECYCLED] $fullPath" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "[FAILED] Could not recycle: $fullPath" -ForegroundColor Red
                        }
                    }
                    else {
                        $ntPath = "\\?\$fullPath"
                        cmd /c "del /f /q `"$ntPath`"" 2>$null
                        if (-not (Test-Path $fullPath)) {
                            Write-Host "[DELETED] $fullPath" -ForegroundColor Green
                        }
                        else {
                            Write-Host "[FAILED] Could not delete: $fullPath" -ForegroundColor Red
                        }
                    }
                }
            }
        }

        Register-ObjectEvent $watcher "Created" -Action $action | Out-Null
        Register-ObjectEvent $watcher "Renamed" -Action $action | Out-Null

        Write-Host "Watching for reserved files in: $WatchPath" -ForegroundColor Cyan
        Write-Host "Press Ctrl+C to stop..." -ForegroundColor Gray

        while ($true) { Start-Sleep -Seconds 1 }
    }

    foreach ($p in $Path) {
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Warning "Path not found: $p"
            continue
        }

        Write-Host "Starting watcher for: $p" -ForegroundColor Cyan
        $job = Start-Job -ScriptBlock $watcherScript -ArgumentList $p, $Script:ReservedNames, $AutoDelete.IsPresent, $UseRecycleBin.IsPresent
        Write-Host "Watcher job started: $($job.Id)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Use 'Get-Job' to see watcher status" -ForegroundColor Gray
    Write-Host "Use 'Stop-Job -Id <id>' to stop a watcher" -ForegroundColor Gray
}

function Uninstall-ReservedFileWatcher {
    <#
    .SYNOPSIS
        Stops all reserved file watcher jobs.

    .EXAMPLE
        Uninstall-ReservedFileWatcher
    #>
    [CmdletBinding()]
    param()

    $jobs = Get-Job | Where-Object { $_.Command -like '*ReservedNames*' }

    if ($jobs.Count -eq 0) {
        Write-Host "No watcher jobs found." -ForegroundColor Yellow
        return
    }

    $jobs | Stop-Job -PassThru | Remove-Job
    Write-Host "Stopped $($jobs.Count) watcher job(s)." -ForegroundColor Green
}

function Install-ReservedFilePreCommitHook {
    <#
    .SYNOPSIS
        Installs a Git pre-commit hook to prevent committing reserved files.

    .DESCRIPTION
        Creates a pre-commit hook in the current Git repository that scans
        staged files for reserved names and blocks the commit if found.

    .PARAMETER Path
        Path to the Git repository. Defaults to current directory.

    .EXAMPLE
        Install-ReservedFilePreCommitHook

    .EXAMPLE
        Install-ReservedFilePreCommitHook -Path "D:\MyProject"
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path
    )

    $gitDir = Join-Path $Path ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Error "Not a Git repository: $Path"
        return
    }

    $hooksDir = Join-Path $gitDir "hooks"
    if (-not (Test-Path $hooksDir)) {
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    }

    $hookPath = Join-Path $hooksDir "pre-commit"

    $hookContent = @'
#!/bin/sh
# Reserved File Cleaner - Pre-commit Hook
# Prevents committing files with Windows reserved names

RESERVED_NAMES="NUL CON PRN AUX COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9 LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9"

# Get staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACR)

FOUND_RESERVED=0

for file in $STAGED_FILES; do
    filename=$(basename "$file")
    filename_upper=$(echo "$filename" | tr '[:lower:]' '[:upper:]')

    for reserved in $RESERVED_NAMES; do
        if [ "$filename_upper" = "$reserved" ]; then
            echo "ERROR: Cannot commit reserved filename: $file"
            FOUND_RESERVED=1
        fi
    done
done

if [ $FOUND_RESERVED -eq 1 ]; then
    echo ""
    echo "Commit blocked: Windows reserved filenames detected."
    echo "These files cannot be properly handled on Windows."
    echo ""
    echo "To remove these files, run:"
    echo "  Remove-ReservedFiles -Path ."
    echo ""
    exit 1
fi

exit 0
'@

    $hookContent | Out-File -FilePath $hookPath -Encoding ASCII -Force

    # Make executable on Unix-like systems
    if ($IsLinux -or $IsMacOS) {
        chmod +x $hookPath
    }

    Write-Host "Pre-commit hook installed: $hookPath" -ForegroundColor Green
    Write-Host "Commits with reserved filenames will now be blocked." -ForegroundColor Cyan
}

function New-ReservedFileReport {
    <#
    .SYNOPSIS
        Generates an HTML report of reserved files found.

    .PARAMETER Path
        Paths to scan. Not required if -Files is provided.

    .PARAMETER Files
        Pre-scanned file objects to include in the report.

    .PARAMETER OutputPath
        Where to save the HTML report.

    .PARAMETER Exclude
        Patterns to exclude when scanning.

    .EXAMPLE
        New-ReservedFileReport -Path "D:\Projects" -OutputPath "report.html"

    .EXAMPLE
        $files = Find-ReservedFiles -Path "D:\Projects"
        New-ReservedFileReport -Files $files -OutputPath "report.html"
    #>
    [CmdletBinding()]
    param(
        [string[]]$Path,
        [Parameter(ValueFromPipeline)]
        [object[]]$Files,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [string[]]$Exclude
    )

    # If Files not provided, scan the paths
    if (-not $Files -or $Files.Count -eq 0) {
        $files = Find-ReservedFiles -Path $Path -Exclude $Exclude
    }
    else {
        $files = $Files
    }
    $scanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $totalSize = ($files | Measure-Object -Property Size -Sum).Sum

    $html = @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Reserved File Report</title>
<style>
body{font-family:system-ui;background:#1a1a2e;color:#e4e4e4;padding:2rem}
.container{max-width:1200px;margin:0 auto}
h1{color:#60a5fa}
.stats{display:flex;gap:1rem;margin:2rem 0}
.stat{background:#16213e;padding:1rem;border-radius:8px;flex:1}
.stat-value{font-size:2rem;color:#60a5fa}
table{width:100%;border-collapse:collapse;background:#16213e;border-radius:8px}
th,td{padding:1rem;text-align:left;border-bottom:1px solid #0f3460}
th{background:#0f3460}
.clean{color:#4ade80;text-align:center;padding:3rem}
</style></head><body><div class="container">
<h1>Reserved File Scan Report</h1>
<p>Generated: $scanDate</p>
<div class="stats">
<div class="stat"><div class="stat-value">$($files.Count)</div>Files Found</div>
<div class="stat"><div class="stat-value">$(Format-FileSize $totalSize)</div>Total Size</div>
</div>
$(if ($files.Count -eq 0) {
    '<div class="clean"><h2>No Reserved Files Found</h2><p>Your system is clean!</p></div>'
} else {
    "<table><tr><th>Name</th><th>Size</th><th>Path</th></tr>" +
    ($files | ForEach-Object { "<tr><td>$($_.Name)</td><td>$(Format-FileSize $_.Size)</td><td>$($_.Path)</td></tr>" }) +
    "</table>"
})
</div></body></html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Report saved: $OutputPath" -ForegroundColor Green
}

#endregion

# Create alias
Set-Alias -Name rfc -Value Remove-ReservedFiles

# Export functions
Export-ModuleMember -Function @(
    'Find-ReservedFiles',
    'Remove-ReservedFile',
    'Remove-ReservedFiles',
    'Install-ReservedFileWatcher',
    'Uninstall-ReservedFileWatcher',
    'Install-ReservedFilePreCommitHook',
    'New-ReservedFileReport'
) -Alias @('rfc')
