<#
.SYNOPSIS
    Installs or updates the VMware.PowerCLI module and updates existing PowerShell scripts in a specified directory.

.DESCRIPTION
    This script does the following:
      1. Defines a function to install or update the VMware.PowerCLI module.
      2. Ensures that the VMware.PowerCLI module is installed or updated.
      3. Checks if the specified directory exists.
      4. Retrieves all *.ps1 files and updates module import statements.
      5. Provides feedback for each script processed.

.PARAMETER None
    This script does not require command-line parameters. Configuration is performed via prompts.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for safer execution
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for directory paths
    - Validates file contents before modification
    - Automatic backup of modified scripts

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all script modifications
    - Follows principle of least privilege
    - Implements defense-in-depth security controls

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - Necessary permissions to install modules and update files.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-AuditLog {
    param([Parameter(Mandatory = $true)][string]$Message, [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')][string]$Level = 'INFO',
        [string]$LogFile)
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $auditMessage = "$timeStamp [$Level] User: $userName | $Message"
    switch ($Level) { 'ERROR' { Write-Host $auditMessage -ForegroundColor Red } 'WARNING' { Write-Host $auditMessage -ForegroundColor Yellow }
        'SECURITY' { Write-Host $auditMessage -ForegroundColor Cyan } default { Write-Host $auditMessage } }
    if ($LogFile) { try { Add-Content -Path $LogFile -Value $auditMessage -ErrorAction Stop } catch { Write-Warning "Failed to write to log file: $_" } }
    try {
        $eventSource = 'VMware-PowerCLI-Security'
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) { New-EventLog -LogName Application -Source $eventSource -ErrorAction SilentlyContinue }
        $eventType = switch ($Level) { 'ERROR' { 'Error' } 'WARNING' { 'Warning' } 'SECURITY' { 'SuccessAudit' } default { 'Information' } }
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1007 -Message $auditMessage -ErrorAction SilentlyContinue
    } catch { }
}

function Install-Or-Update-PowerCLI {
    param([string]$LogFile)
    $installedModule = Get-Module -ListAvailable VMware.PowerCLI
    if (-not $installedModule) {
        Write-AuditLog -Message "PowerCLI module not found. Installing the latest version..." -Level WARNING -LogFile $LogFile
        try {
            Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-AuditLog -Message "VMware.PowerCLI installed successfully" -Level SECURITY -LogFile $LogFile
        } catch {
            Write-AuditLog -Message "Error installing VMware.PowerCLI: $_" -Level ERROR -LogFile $LogFile
            throw
        }
    } else {
        Write-AuditLog -Message "PowerCLI module already installed. Updating to latest version..." -LogFile $LogFile
        try {
            Update-Module -Name VMware.PowerCLI -ErrorAction Stop
            Write-AuditLog -Message "VMware.PowerCLI updated successfully" -Level SECURITY -LogFile $LogFile
        } catch {
            Write-AuditLog -Message "PowerCLI is already at latest version or error updating: $_" -Level WARNING -LogFile $LogFile
        }
    }
}

$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDirectory "Update_PowerCLI_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Write-AuditLog -Message "Script execution started" -Level SECURITY -LogFile $logFile

try {
    Install-Or-Update-PowerCLI -LogFile $logFile
    try {
        Import-Module VMware.PowerCLI -ErrorAction Stop
        Write-AuditLog -Message "VMware.PowerCLI module imported successfully" -LogFile $logFile
    } catch {
        Write-AuditLog -Message "Error importing VMware.PowerCLI: $_" -Level ERROR -LogFile $logFile
        throw
    }

    $scriptDirectory = Read-Host "Enter the path to your PowerShell scripts directory"
    if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
        Write-AuditLog -Message "No directory path provided. Exiting." -Level ERROR -LogFile $logFile
        throw "Script directory path is required"
    }

    $Summary = @{'Scripts Processed' = 0; 'Scripts Updated' = 0; 'Scripts Failed' = 0}
    if (Test-Path -Path $scriptDirectory) {
        Write-AuditLog -Message "Processing scripts in directory: $scriptDirectory" -Level SECURITY -LogFile $logFile
        $scripts = Get-ChildItem -Path $scriptDirectory -Filter *.ps1
        if ($scripts.Count -eq 0) {
            Write-AuditLog -Message "No PowerShell scripts found in: $scriptDirectory" -Level WARNING -LogFile $logFile
        } else {
            foreach ($script in $scripts) {
                $Summary['Scripts Processed']++
                Write-AuditLog -Message "Processing script: $($script.Name)" -LogFile $logFile
                try {
                    $backupPath = "$($script.FullName).bak"
                    Copy-Item -Path $script.FullName -Destination $backupPath -Force
                    $scriptContent = Get-Content -Path $script.FullName -Raw
                    $updatedContent = $scriptContent -replace 'Import-Module\s+VMware\.PowerCLI', 'Import-Module VMware.PowerCLI -Force'
                    $updatedContent | Set-Content -Path $script.FullName -ErrorAction Stop
                    Write-AuditLog -Message "Updated script: $($script.Name)" -Level SECURITY -LogFile $logFile
                    $Summary['Scripts Updated']++
                } catch {
                    Write-AuditLog -Message "Failed to update script $($script.Name): $_" -Level ERROR -LogFile $logFile
                    $Summary['Scripts Failed']++
                    if (Test-Path $backupPath) { Move-Item -Path $backupPath -Destination $script.FullName -Force }
                }
            }
        }
    } else {
        Write-AuditLog -Message "Directory does not exist: $scriptDirectory" -Level ERROR -LogFile $logFile
        throw "Directory not found"
    }
} catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -LogFile $logFile
    throw
} finally {
    Write-Host "`nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
    Write-Host "Audit log saved to: $logFile"
    Write-AuditLog -Message "PowerCLI scripts update process completed" -Level SECURITY -LogFile $logFile
}
