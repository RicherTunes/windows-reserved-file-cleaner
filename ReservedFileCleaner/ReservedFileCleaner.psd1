@{
    # Module manifest for ReservedFileCleaner

    # Script module or binary module file associated with this manifest
    RootModule = 'ReservedFileCleaner.psm1'

    # Version number of this module
    ModuleVersion = '1.2.0'

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'RicherTunes'

    # Company or vendor of this module
    CompanyName = 'RicherTunes'

    # Copyright statement for this module
    Copyright = '(c) 2026 RicherTunes. MIT License.'

    # Description of the functionality provided by this module
    Description = 'Find and safely delete files with Windows reserved device names (nul, con, aux, etc.) that AI coding assistants accidentally create. Features include Recycle Bin support, backup before delete, HTML reports, scheduled tasks, and real-time file watching.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Find-ReservedFiles',
        'Remove-ReservedFile',
        'Remove-ReservedFiles',
        'Install-ReservedFileWatcher',
        'Uninstall-ReservedFileWatcher',
        'Install-ReservedFilePreCommitHook',
        'New-ReservedFileReport'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @(
        'rfc'  # Short alias for Remove-ReservedFiles
    )

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for online gallery discoverability
            Tags = @(
                'Windows',
                'Reserved',
                'NUL',
                'CON',
                'AUX',
                'Cleaner',
                'AI',
                'Claude',
                'Copilot',
                'DevTools',
                'Maintenance'
            )

            # A URL to the license for this module
            LicenseUri = 'https://github.com/RicherTunes/windows-reserved-file-cleaner/blob/main/LICENSE'

            # A URL to the main website for this project
            ProjectUri = 'https://github.com/RicherTunes/windows-reserved-file-cleaner'

            # A URL to an icon representing this module
            # IconUri = ''

            # Release notes for this module
            ReleaseNotes = @'
v1.1.0 - Safety & Automation Features
- Recycle Bin support (-UseRecycleBin)
- Backup before delete (-BackupPath)
- HTML report generation (-Report)
- Scheduled task automation (-InstallTask)
- File watcher mode (-Watch)
- Git pre-commit hook support
- Update checking (-CheckUpdate)
- UNC/network path support

v1.0.0 - Initial Release
- Scan and delete Windows reserved-name files
- Multiple modes: List, Interactive, Force, WhatIf
- Path validation and security features
- Retry logic for locked files
- JSON/CSV export
'@

            # Prerelease tag (e.g., 'beta', 'preview')
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance
            RequireLicenseAcceptance = $false
        }
    }

    # HelpInfo URI of this module
    HelpInfoURI = 'https://github.com/RicherTunes/windows-reserved-file-cleaner#readme'
}
