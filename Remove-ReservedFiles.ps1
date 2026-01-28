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

.PARAMETER Verbose
    Show detailed scanning progress.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -List
    Lists all reserved-name files on all fixed drives.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -Path "D:\Projects" -Interactive
    Scans D:\Projects and prompts for each file.

.EXAMPLE
    .\Remove-ReservedFiles.ps1 -Force
    Deletes all reserved-name files without confirmation.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Path,
    [switch]$List,
    [switch]$Interactive,
    [switch]$Force
)

# Reserved device names (22 total)
$ReservedNames = @('NUL', 'CON', 'PRN', 'AUX') +
                 (1..9 | ForEach-Object { "COM$_"; "LPT$_" })

function Find-ReservedFiles {
    param(
        [string[]]$ScanPaths
    )

    $results = [System.Collections.ArrayList]::new()
    $totalPaths = $ScanPaths.Count
    $currentPathIndex = 0

    foreach ($scanPath in $ScanPaths) {
        $currentPathIndex++

        if (-not (Test-Path -LiteralPath $scanPath)) {
            Write-Warning "Path not found: $scanPath"
            continue
        }

        Write-Progress -Activity "Scanning for reserved-name files" `
                       -Status "Scanning: $scanPath" `
                       -PercentComplete (($currentPathIndex - 1) / $totalPaths * 100)

        Write-Verbose "Scanning: $scanPath"

        try {
            Get-ChildItem -LiteralPath $scanPath -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in $ReservedNames } |
                ForEach-Object {
                    $null = $results.Add([PSCustomObject]@{
                        Name     = $_.Name
                        Path     = $_.FullName
                        Size     = $_.Length
                        Modified = $_.LastWriteTime
                    })
                    Write-Verbose "Found: $($_.FullName)"
                }
        }
        catch {
            Write-Warning "Error scanning $scanPath : $_"
        }
    }

    Write-Progress -Activity "Scanning for reserved-name files" -Completed

    return $results
}

function Remove-ReservedFile {
    param(
        [string]$FilePath
    )

    # Use extended path prefix to bypass reserved name checking
    $ntPath = "\\?\$FilePath"

    try {
        Remove-Item -LiteralPath $ntPath -Force -ErrorAction Stop
        return @{ Success = $true; Error = $null }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
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
    param($Files)

    Write-Host "`nFound $($Files.Count) reserved-name file(s):`n" -ForegroundColor Cyan

    $Files | ForEach-Object {
        [PSCustomObject]@{
            Name     = $_.Name
            Path     = $_.Path
            Size     = Format-FileSize $_.Size
            Modified = $_.Modified.ToString("yyyy-MM-dd HH:mm")
        }
    } | Format-Table -AutoSize
}

# Main logic

# Determine scan paths
if (-not $Path) {
    $Path = Get-Volume |
            Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } |
            ForEach-Object { "$($_.DriveLetter):\" }

    if (-not $Path) {
        Write-Error "No fixed drives found to scan."
        exit 1
    }

    Write-Host "Scanning all fixed drives: $($Path -join ', ')" -ForegroundColor Yellow
}

# Validate paths
$validPaths = @()
foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p) {
        $validPaths += $p
    }
    else {
        Write-Warning "Invalid path (skipping): $p"
    }
}

if ($validPaths.Count -eq 0) {
    Write-Error "No valid paths to scan."
    exit 1
}

# Find files
$files = Find-ReservedFiles -ScanPaths $validPaths

if ($files.Count -eq 0) {
    Write-Host "`nNo reserved-name files found." -ForegroundColor Green
    exit 0
}

# Display results
Show-Results -Files $files

# Handle modes
if ($List) {
    exit 0
}

if ($WhatIfPreference) {
    Write-Host "What if: Would delete the following files:`n" -ForegroundColor Yellow
    foreach ($file in $files) {
        Write-Host "  Would delete: $($file.Path)" -ForegroundColor Yellow
    }
    exit 0
}

# Deletion tracking
$deleted = 0
$failed = 0
$errors = [System.Collections.ArrayList]::new()

if ($Force) {
    # Delete all without confirmation
    foreach ($file in $files) {
        $result = Remove-ReservedFile -FilePath $file.Path
        if ($result.Success) {
            Write-Host "Deleted: $($file.Path)" -ForegroundColor Green
            $deleted++
        }
        else {
            Write-Host "Failed:  $($file.Path) - $($result.Error)" -ForegroundColor Red
            $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error })
            $failed++
        }
    }
}
elseif ($Interactive) {
    # Prompt for each file
    $deleteAll = $false

    foreach ($file in $files) {
        if ($deleteAll) {
            $choice = 'Y'
        }
        else {
            $sizeStr = Format-FileSize $file.Size
            Write-Host "`nDelete $($file.Path) ($sizeStr)?" -ForegroundColor Cyan
            $choice = Read-Host "[Y]es/[N]o/[A]ll/[Q]uit"
        }

        switch -Regex ($choice) {
            '^[Yy]' {
                $result = Remove-ReservedFile -FilePath $file.Path
                if ($result.Success) {
                    Write-Host "Deleted: $($file.Path)" -ForegroundColor Green
                    $deleted++
                }
                else {
                    Write-Host "Failed:  $($file.Path) - $($result.Error)" -ForegroundColor Red
                    $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error })
                    $failed++
                }
            }
            '^[Aa]' {
                $deleteAll = $true
                $result = Remove-ReservedFile -FilePath $file.Path
                if ($result.Success) {
                    Write-Host "Deleted: $($file.Path)" -ForegroundColor Green
                    $deleted++
                }
                else {
                    Write-Host "Failed:  $($file.Path) - $($result.Error)" -ForegroundColor Red
                    $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error })
                    $failed++
                }
            }
            '^[Qq]' {
                Write-Host "`nQuitting." -ForegroundColor Yellow
                break
            }
            default {
                Write-Host "Skipped: $($file.Path)" -ForegroundColor Gray
            }
        }
    }
}
else {
    # Default: batch confirmation
    $response = Read-Host "`nDelete all $($files.Count) file(s)? [Y]es/[N]o"

    if ($response -match '^[Yy]') {
        foreach ($file in $files) {
            $result = Remove-ReservedFile -FilePath $file.Path
            if ($result.Success) {
                Write-Host "Deleted: $($file.Path)" -ForegroundColor Green
                $deleted++
            }
            else {
                Write-Host "Failed:  $($file.Path) - $($result.Error)" -ForegroundColor Red
                $null = $errors.Add(@{ Path = $file.Path; Error = $result.Error })
                $failed++
            }
        }
    }
    else {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Summary
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Deleted: $deleted" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed:  $failed" -ForegroundColor Red
}
