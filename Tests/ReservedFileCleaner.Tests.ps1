#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for the ReservedFileCleaner module.

.DESCRIPTION
    Comprehensive tests for finding and removing Windows reserved device name files.
    Tests include unit tests, integration tests, and edge case handling.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\ReservedFileCleaner.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import the module from the parent directory
    $ModulePath = Join-Path $PSScriptRoot '..\ReservedFileCleaner\ReservedFileCleaner.psm1'
    Import-Module $ModulePath -Force

    # Create a test directory for our tests
    $Script:TestRoot = Join-Path $env:TEMP "ReservedFileCleaner-Tests-$(Get-Random)"
    New-Item -Path $Script:TestRoot -ItemType Directory -Force | Out-Null

    # Helper function to create a reserved file using cmd.exe
    function New-ReservedTestFile {
        param(
            [string]$Directory,
            [string]$Name,
            [string]$Content = "test content"
        )
        $filePath = Join-Path $Directory $Name
        $ntPath = "\\?\$filePath"
        # Use cmd.exe to create the file with the reserved name
        cmd /c "echo $Content > `"$ntPath`"" 2>$null
        return $filePath
    }

    # Helper function to check if a reserved file exists
    function Test-ReservedFileExists {
        param([string]$FilePath)
        $ntPath = "\\?\$FilePath"
        return [System.IO.File]::Exists($ntPath)
    }

    # Helper to remove reserved file for cleanup
    function Remove-ReservedTestFile {
        param([string]$FilePath)
        $ntPath = "\\?\$FilePath"
        if ([System.IO.File]::Exists($ntPath)) {
            cmd /c "del /f /q `"$ntPath`"" 2>$null
        }
    }
}

AfterAll {
    # Clean up test directory
    if (Test-Path $Script:TestRoot) {
        # First remove any reserved files that might remain
        Get-ChildItem -Path $Script:TestRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $ntPath = "\\?\$($_.FullName)"
            cmd /c "del /f /q `"$ntPath`"" 2>$null
        }
        Remove-Item -Path $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "ReservedFileCleaner Module" {
    Context "Module Loading" {
        It "Should export Find-ReservedFiles function" {
            Get-Command -Name Find-ReservedFiles -Module ReservedFileCleaner | Should -Not -BeNullOrEmpty
        }

        It "Should export Remove-ReservedFile function" {
            Get-Command -Name Remove-ReservedFile -Module ReservedFileCleaner | Should -Not -BeNullOrEmpty
        }

        It "Should export Remove-ReservedFiles function" {
            Get-Command -Name Remove-ReservedFiles -Module ReservedFileCleaner | Should -Not -BeNullOrEmpty
        }

        It "Should export Install-ReservedFileWatcher function" {
            Get-Command -Name Install-ReservedFileWatcher -Module ReservedFileCleaner | Should -Not -BeNullOrEmpty
        }

        It "Should export Install-ReservedFilePreCommitHook function" {
            Get-Command -Name Install-ReservedFilePreCommitHook -Module ReservedFileCleaner | Should -Not -BeNullOrEmpty
        }

        It "Should export New-ReservedFileReport function" {
            Get-Command -Name New-ReservedFileReport -Module ReservedFileCleaner | Should -Not -BeNullOrEmpty
        }

        It "Should export rfc alias" {
            Get-Alias -Name rfc -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Find-ReservedFiles" {
    BeforeAll {
        # Create a subdirectory for Find tests
        $Script:FindTestDir = Join-Path $Script:TestRoot "FindTests"
        New-Item -Path $Script:FindTestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        # Clean up
        if (Test-Path $Script:FindTestDir) {
            Get-ChildItem -Path $Script:FindTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ReservedTestFile -FilePath $_.FullName
            }
            Remove-Item -Path $Script:FindTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Basic Detection" {
        BeforeEach {
            # Create fresh test directory for each test
            $Script:CurrentTestDir = Join-Path $Script:FindTestDir "test-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            # Clean up test files
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should find NUL file" {
            $nulPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul"

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "nul"
        }

        It "Should find CON file" {
            $conPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "con"

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "con"
        }

        It "Should find PRN file" {
            $prnPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "prn"

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "prn"
        }

        It "Should find AUX file" {
            $auxPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "aux"

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "aux"
        }

        It "Should find COM port files (COM1-COM9)" {
            $com1Path = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "com1"

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "com1"
        }

        It "Should find LPT port files (LPT1-LPT9)" {
            $lpt1Path = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "lpt1"

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain "lpt1"
        }

        It "Should be case-insensitive" {
            $nulUpper = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "NUL"

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 1
        }

        It "Should find multiple reserved files" {
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" | Out-Null
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "con" | Out-Null
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "aux" | Out-Null

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results.Count | Should -Be 3
        }
    }

    Context "Non-Reserved Files" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:FindTestDir "nonreserved-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should NOT find files with extensions (nul.txt)" {
            "test" | Out-File -FilePath (Join-Path $Script:CurrentTestDir "nul.txt")

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -BeNullOrEmpty
        }

        It "Should NOT find files with similar names (null, cone)" {
            "test" | Out-File -FilePath (Join-Path $Script:CurrentTestDir "null")
            "test" | Out-File -FilePath (Join-Path $Script:CurrentTestDir "cone")

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -BeNullOrEmpty
        }

        It "Should NOT find regular files" {
            "test" | Out-File -FilePath (Join-Path $Script:CurrentTestDir "readme.txt")
            "test" | Out-File -FilePath (Join-Path $Script:CurrentTestDir "config.json")

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -BeNullOrEmpty
        }
    }

    Context "Exclusion Patterns" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:FindTestDir "exclude-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null

            # Create subdirectories
            New-Item -Path (Join-Path $Script:CurrentTestDir "node_modules") -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $Script:CurrentTestDir ".git") -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $Script:CurrentTestDir "src") -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should exclude specified directories" {
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir "node_modules") -Name "nul" | Out-Null
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir "src") -Name "nul" | Out-Null

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir -Exclude "node_modules"

            $results.Count | Should -Be 1
            $results[0].Path | Should -Match "src"
        }

        It "Should support multiple exclusion patterns" {
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir "node_modules") -Name "nul" | Out-Null
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir ".git") -Name "con" | Out-Null
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir "src") -Name "aux" | Out-Null

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir -Exclude "node_modules", ".git"

            $results.Count | Should -Be 1
            $results[0].Name | Should -Be "aux"
        }
    }

    Context "MaxDepth Parameter" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:FindTestDir "depth-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null

            # Create nested directories
            $level1 = Join-Path $Script:CurrentTestDir "level1"
            $level2 = Join-Path $level1 "level2"
            $level3 = Join-Path $level2 "level3"

            New-Item -Path $level1 -ItemType Directory -Force | Out-Null
            New-Item -Path $level2 -ItemType Directory -Force | Out-Null
            New-Item -Path $level3 -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should respect MaxDepth parameter" {
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" | Out-Null
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir "level1") -Name "nul" | Out-Null
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir "level1\level2") -Name "nul" | Out-Null
            New-ReservedTestFile -Directory (Join-Path $Script:CurrentTestDir "level1\level2\level3") -Name "nul" | Out-Null

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir -MaxDepth 2

            # Should find files at root (depth 1) and level1 (depth 2), but not deeper
            $results.Count | Should -BeLessOrEqual 2
        }
    }

    Context "Output Properties" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:FindTestDir "props-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return objects with expected properties" {
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" | Out-Null

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results[0].PSObject.Properties.Name | Should -Contain "Name"
            $results[0].PSObject.Properties.Name | Should -Contain "Path"
            $results[0].PSObject.Properties.Name | Should -Contain "Size"
            $results[0].PSObject.Properties.Name | Should -Contain "Modified"
        }
    }
}

Describe "Remove-ReservedFile" {
    BeforeAll {
        $Script:RemoveTestDir = Join-Path $Script:TestRoot "RemoveTests"
        New-Item -Path $Script:RemoveTestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $Script:RemoveTestDir) {
            Get-ChildItem -Path $Script:RemoveTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ReservedTestFile -FilePath $_.FullName
            }
            Remove-Item -Path $Script:RemoveTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Single File Deletion" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:RemoveTestDir "single-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should delete a NUL file" {
            $nulPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul"
            Test-ReservedFileExists -FilePath $nulPath | Should -BeTrue

            Remove-ReservedFile -Path $nulPath -Force

            Test-ReservedFileExists -FilePath $nulPath | Should -BeFalse
        }

        It "Should delete a CON file" {
            $conPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "con"
            Test-ReservedFileExists -FilePath $conPath | Should -BeTrue

            Remove-ReservedFile -Path $conPath -Force

            Test-ReservedFileExists -FilePath $conPath | Should -BeFalse
        }

        It "Should return success result" {
            $nulPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul"

            $result = Remove-ReservedFile -Path $nulPath -Force

            $result.Success | Should -BeTrue
        }

        It "Should handle non-existent file gracefully" {
            $fakePath = Join-Path $Script:CurrentTestDir "nonexistent-nul"

            $result = Remove-ReservedFile -Path $fakePath -Force -ErrorAction SilentlyContinue

            $result.Success | Should -BeFalse
        }
    }

    Context "Backup Feature" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:RemoveTestDir "backup-$(Get-Random)"
            $Script:BackupDir = Join-Path $Script:RemoveTestDir "backup-dest-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
            New-Item -Path $Script:BackupDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $Script:BackupDir) {
                Remove-Item -Path $Script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should create backup before deletion when BackupPath specified" {
            $nulPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" -Content "backup test content"

            Remove-ReservedFile -Path $nulPath -Force -BackupPath $Script:BackupDir

            # Original should be deleted
            Test-ReservedFileExists -FilePath $nulPath | Should -BeFalse

            # Backup should exist (with timestamp prefix)
            $backupFiles = Get-ChildItem -Path $Script:BackupDir -Filter "*nul*" -ErrorAction SilentlyContinue
            $backupFiles | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Remove-ReservedFiles (Batch)" {
    BeforeAll {
        $Script:BatchTestDir = Join-Path $Script:TestRoot "BatchTests"
        New-Item -Path $Script:BatchTestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $Script:BatchTestDir) {
            Get-ChildItem -Path $Script:BatchTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ReservedTestFile -FilePath $_.FullName
            }
            Remove-Item -Path $Script:BatchTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Batch Deletion" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:BatchTestDir "batch-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should delete multiple reserved files" {
            $nul = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul"
            $con = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "con"
            $aux = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "aux"

            Remove-ReservedFiles -Path $Script:CurrentTestDir -Force

            Test-ReservedFileExists -FilePath $nul | Should -BeFalse
            Test-ReservedFileExists -FilePath $con | Should -BeFalse
            Test-ReservedFileExists -FilePath $aux | Should -BeFalse
        }

        It "Should return count of deleted files" {
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" | Out-Null
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "con" | Out-Null

            $result = Remove-ReservedFiles -Path $Script:CurrentTestDir -Force

            $result.Deleted | Should -Be 2
        }

        It "Should handle empty directory gracefully" {
            $emptyDir = Join-Path $Script:CurrentTestDir "empty"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            $result = Remove-ReservedFiles -Path $emptyDir -Force

            $result.Found | Should -Be 0
            $result.Deleted | Should -Be 0
        }
    }

    Context "WhatIf Support" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:BatchTestDir "whatif-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should not delete files when -WhatIf is used" {
            $nulPath = New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul"

            Remove-ReservedFiles -Path $Script:CurrentTestDir -WhatIf

            Test-ReservedFileExists -FilePath $nulPath | Should -BeTrue
        }
    }
}

Describe "New-ReservedFileReport" {
    BeforeAll {
        $Script:ReportTestDir = Join-Path $Script:TestRoot "ReportTests"
        New-Item -Path $Script:ReportTestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $Script:ReportTestDir) {
            Get-ChildItem -Path $Script:ReportTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ReservedTestFile -FilePath $_.FullName
            }
            Remove-Item -Path $Script:ReportTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "HTML Report Generation" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:ReportTestDir "html-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    # Skip HTML files - they're regular files
                    if ($_.Extension -eq ".html") { return }
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should generate HTML report file" {
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" | Out-Null
            $reportPath = Join-Path $Script:CurrentTestDir "report.html"

            $files = Find-ReservedFiles -Path $Script:CurrentTestDir
            New-ReservedFileReport -Files $files -OutputPath $reportPath

            Test-Path $reportPath | Should -BeTrue
        }

        It "Should create valid HTML content" {
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" | Out-Null
            $reportPath = Join-Path $Script:CurrentTestDir "report.html"

            $files = Find-ReservedFiles -Path $Script:CurrentTestDir
            New-ReservedFileReport -Files $files -OutputPath $reportPath

            $content = Get-Content -Path $reportPath -Raw
            $content | Should -Match "<!DOCTYPE html>"
            $content | Should -Match "Reserved File"
        }

        It "Should include file details in report" {
            New-ReservedTestFile -Directory $Script:CurrentTestDir -Name "nul" | Out-Null
            $reportPath = Join-Path $Script:CurrentTestDir "report.html"

            $files = Find-ReservedFiles -Path $Script:CurrentTestDir
            New-ReservedFileReport -Files $files -OutputPath $reportPath

            $content = Get-Content -Path $reportPath -Raw
            $content | Should -Match "nul"
        }
    }
}

Describe "Install-ReservedFilePreCommitHook" {
    BeforeAll {
        $Script:GitTestDir = Join-Path $Script:TestRoot "GitTests"
        New-Item -Path $Script:GitTestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $Script:GitTestDir) {
            Remove-Item -Path $Script:GitTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Hook Installation" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:GitTestDir "repo-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
            # Initialize a fake git repo structure
            $gitDir = Join-Path $Script:CurrentTestDir ".git"
            $hooksDir = Join-Path $gitDir "hooks"
            New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should create pre-commit hook file" {
            Install-ReservedFilePreCommitHook -Path $Script:CurrentTestDir

            $hookPath = Join-Path $Script:CurrentTestDir ".git\hooks\pre-commit"
            Test-Path $hookPath | Should -BeTrue
        }

        It "Should create executable hook content" {
            Install-ReservedFilePreCommitHook -Path $Script:CurrentTestDir

            $hookPath = Join-Path $Script:CurrentTestDir ".git\hooks\pre-commit"
            $content = Get-Content -Path $hookPath -Raw
            $content | Should -Match "reserved"
        }

        It "Should fail gracefully for non-git directory" {
            $nonGitDir = Join-Path $Script:GitTestDir "nongit-$(Get-Random)"
            New-Item -Path $nonGitDir -ItemType Directory -Force | Out-Null

            { Install-ReservedFilePreCommitHook -Path $nonGitDir -ErrorAction Stop } | Should -Throw

            Remove-Item -Path $nonGitDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Path Validation" {
    Context "Security Checks" {
        It "Should reject paths with command injection attempts" {
            $maliciousPath = "C:\test; rm -rf /"

            { Find-ReservedFiles -Path $maliciousPath -ErrorAction Stop } | Should -Throw
        }

        It "Should reject paths with pipe characters" {
            $maliciousPath = "C:\test | malicious"

            { Find-ReservedFiles -Path $maliciousPath -ErrorAction Stop } | Should -Throw
        }

        It "Should reject paths with backticks" {
            $maliciousPath = "C:\test`command"

            { Find-ReservedFiles -Path $maliciousPath -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Edge Cases" {
    BeforeAll {
        $Script:EdgeTestDir = Join-Path $Script:TestRoot "EdgeTests"
        New-Item -Path $Script:EdgeTestDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $Script:EdgeTestDir) {
            Get-ChildItem -Path $Script:EdgeTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ReservedTestFile -FilePath $_.FullName
            }
            Remove-Item -Path $Script:EdgeTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Special Scenarios" {
        BeforeEach {
            $Script:CurrentTestDir = Join-Path $Script:EdgeTestDir "special-$(Get-Random)"
            New-Item -Path $Script:CurrentTestDir -ItemType Directory -Force | Out-Null
        }

        AfterEach {
            if (Test-Path $Script:CurrentTestDir) {
                Get-ChildItem -Path $Script:CurrentTestDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ReservedTestFile -FilePath $_.FullName
                }
                Remove-Item -Path $Script:CurrentTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle paths with spaces" {
            $spacePath = Join-Path $Script:CurrentTestDir "path with spaces"
            New-Item -Path $spacePath -ItemType Directory -Force | Out-Null
            New-ReservedTestFile -Directory $spacePath -Name "nul" | Out-Null

            $results = Find-ReservedFiles -Path $spacePath

            $results | Should -Not -BeNullOrEmpty
        }

        It "Should handle deeply nested paths" {
            $deepPath = $Script:CurrentTestDir
            1..10 | ForEach-Object {
                $deepPath = Join-Path $deepPath "level$_"
            }
            New-Item -Path $deepPath -ItemType Directory -Force | Out-Null
            New-ReservedTestFile -Directory $deepPath -Name "nul" | Out-Null

            $results = Find-ReservedFiles -Path $Script:CurrentTestDir

            $results | Should -Not -BeNullOrEmpty
        }

        It "Should handle multiple scan paths" {
            $path1 = Join-Path $Script:CurrentTestDir "path1"
            $path2 = Join-Path $Script:CurrentTestDir "path2"
            New-Item -Path $path1, $path2 -ItemType Directory -Force | Out-Null

            New-ReservedTestFile -Directory $path1 -Name "nul" | Out-Null
            New-ReservedTestFile -Directory $path2 -Name "con" | Out-Null

            $results = Find-ReservedFiles -Path $path1, $path2

            $results.Count | Should -Be 2
        }
    }
}
