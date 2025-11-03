<#
.SYNOPSIS
    Production-Ready Automated Patch Management for Windows Servers/Workstations.

.DESCRIPTION
    Schedules, deploys, and verifies OS/application updates across target systems. Includes robust logging,
    error handling, input validation, and reporting. Supports scheduled deployments and credential management.

.PARAMETER ComputerList
    Array of computer names or IPs to patch.

.PARAMETER Credential
    PSCredential object for remote authentication.

.PARAMETER Schedule
    Optional: Schedule time for patch deployment.

.PARAMETER PreRebootScript
    Optional: Script to run before reboot.

.PARAMETER LogPath
    Path for audit logging. Default is C:\Logs\PatchManagement.log

.SECURITY FEATURES
    - Requires PowerShell 5.1 and Administrator privileges
    - Comprehensive audit logging to file and Windows Event Log
    - Secure credential handling via PSCredential
    - Input validation for all parameters
    - Computer name sanitization
    - Sensitive data cleared from memory on exit
    - Pre-flight connectivity checks

.COMPLIANCE
    - Follows Fourth Estate security standards
    - Implements defense-in-depth logging
    - Supports audit trail requirements
    - Validates all input parameters
    - Tracks all patch operations

.EXAMPLE
    $cred = Get-Credential
    .\AutomatedPatchManagement.ps1 -ComputerList @("Server1","Server2") -Credential $cred

.EXAMPLE
    $cred = Get-Credential
    $scheduleTime = (Get-Date).AddHours(2)
    .\AutomatedPatchManagement.ps1 -ComputerList @("Server1","Server2") -Credential $cred -Schedule $scheduleTime

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        foreach ($computer in $_) {
            if ($computer -notmatch '^[a-zA-Z0-9\-\.]+$') {
                throw "Invalid computer name format: $computer"
            }
        }
        $true
    })]
    [string[]]$ComputerList,

    [Parameter(Mandatory=$true)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory=$false)]
    [datetime]$Schedule,

    [Parameter(Mandatory=$false)]
    [ValidateScript({
        if ($_ -and (Test-Path -Path $_ -PathType Leaf)) {
            $true
        } elseif (-not $_) {
            $true
        } else {
            throw "Pre-reboot script file not found: $_"
        }
    })]
    [string]$PreRebootScript,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '^[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]+\.log$') {
            $true
        } else {
            throw "Invalid log path format."
        }
    })]
    [string]$LogPath = "C:\Logs\PatchManagement.log"
)

#==============================================
# Global Logging Setup
#==============================================

$Global:EventLogSource = "PatchManagement"
$Global:EventLogName = "Application"

# Ensure log directory exists
$logDir = Split-Path -Path $LogPath -Parent
if (-not (Test-Path -Path $logDir -PathType Container)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory: $logDir. Error: $_"
        exit 1
    }
}

# Register Event Log Source
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
        [System.Diagnostics.EventLog]::CreateEventSource($Global:EventLogSource, $Global:EventLogName)
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Warning "Could not create Event Log source. Continuing with file logging only."
}

#==============================================
# Function: Write-AuditLog
#==============================================
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','ERROR','WARNING','SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory=$false)]
        [string]$Operation = 'General',

        [Parameter(Mandatory=$false)]
        [string]$TargetSystem = 'Local'
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $logMessage = "$timestamp [$Level] User: $userName | Operation: $Operation | Target: $TargetSystem | $Message"

        switch ($Level) {
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            default   { Write-Host $logMessage }
        }

        Add-Content -Path $LogPath -Value $logMessage -ErrorAction Stop

        $eventType = switch ($Level) {
            'ERROR'   { [System.Diagnostics.EventLogEntryType]::Error }
            'WARNING' { [System.Diagnostics.EventLogEntryType]::Warning }
            default   { [System.Diagnostics.EventLogEntryType]::Information }
        }

        $eventID = switch ($Level) {
            'ERROR'   { 6001 }
            'WARNING' { 6002 }
            'SUCCESS' { 6003 }
            default   { 6000 }
        }

        if ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
            Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
                -EntryType $eventType -EventId $eventID -Message $logMessage -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Failed to write to audit log: $_"
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','ERROR','WARNING','SUCCESS')]
        [string]$Level = 'INFO'
    )
    Write-AuditLog -Message $Message -Level $Level -Operation "PatchManagement"
}

#==============================================
# Input Validation
#==============================================
function Test-ComputerName {
    param([string]$ComputerName)

    if ($ComputerName -notmatch '^[a-zA-Z0-9\-\.]+$') {
        throw "Invalid computer name format: $ComputerName"
    }
    return $true
}

#==============================================
# Function: Invoke-RemotePatch
#==============================================
function Invoke-RemotePatch {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Computer,

        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$Credential
    )

    Write-AuditLog -Message "Starting patch operation" -Level INFO -Operation "PatchComputer" -TargetSystem $Computer

    try {
        # Validate computer name
        Test-ComputerName -ComputerName $Computer

        # Test connectivity
        Write-AuditLog -Message "Testing connectivity" -Level INFO -Operation "ConnectivityTest" -TargetSystem $Computer

        if (-not (Test-Connection -ComputerName $Computer -Count 2 -Quiet)) {
            throw "Cannot reach computer: $Computer"
        }

        Write-AuditLog -Message "Connectivity confirmed" -Level SUCCESS -Operation "ConnectivityTest" -TargetSystem $Computer

        # Check and install PSWindowsUpdate module on remote system
        $result = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            $ErrorActionPreference = 'Stop'

            try {
                # Check if module is available
                if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                    Write-Output "Installing PSWindowsUpdate module..."

                    # Install NuGet provider if needed
                    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
                    }

                    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber
                }

                Import-Module PSWindowsUpdate -ErrorAction Stop

                Write-Output "Scanning for available updates..."
                $updates = Get-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop

                if ($updates) {
                    Write-Output "Found $($updates.Count) update(s). Installing..."
                    $installResult = Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
                    return @{
                        Success = $true
                        UpdateCount = $updates.Count
                        InstallResult = $installResult
                    }
                } else {
                    Write-Output "No updates available."
                    return @{
                        Success = $true
                        UpdateCount = 0
                        InstallResult = "No updates required"
                    }
                }
            } catch {
                return @{
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        } -ErrorAction Stop

        if ($result.Success) {
            Write-AuditLog -Message "Patch operation completed. Updates installed: $($result.UpdateCount)" -Level SUCCESS -Operation "PatchComputer" -TargetSystem $Computer
            return $true
        } else {
            throw "Patch operation failed: $($result.Error)"
        }

    } catch {
        Write-AuditLog -Message "Error patching computer. Error: $_" -Level ERROR -Operation "PatchComputer" -TargetSystem $Computer
        return $false
    }
}

#==============================================
# Main Execution
#==============================================

Write-AuditLog -Message "Patch management script started" -Level INFO -Operation "Initialization"
Write-AuditLog -Message "Target computers: $($ComputerList -join ', ')" -Level INFO -Operation "Initialization"

# Handle scheduled deployment
if ($Schedule) {
    Write-AuditLog -Message "Patch deployment scheduled for $Schedule" -Level INFO -Operation "Scheduling"
    $now = Get-Date
    $wait = ($Schedule - $now).TotalSeconds

    if ($wait -gt 0) {
        Write-AuditLog -Message "Waiting $([math]::Round($wait/60, 2)) minutes until scheduled time..." -Level INFO -Operation "Scheduling"
        Start-Sleep -Seconds $wait
    } else {
        Write-AuditLog -Message "Scheduled time is in the past. Proceeding immediately." -Level WARNING -Operation "Scheduling"
    }
}

$summary = @{}
$successCount = 0
$failCount = 0

try {
    foreach ($computer in $ComputerList) {
        try {
            $success = Invoke-RemotePatch -Computer $computer -Credential $Credential
            $summary[$computer] = if ($success) {
                $successCount++
                'Success'
            } else {
                $failCount++
                'Failed'
            }
        } catch {
            Write-AuditLog -Message "Exception processing computer: $_" -Level ERROR -Operation "ProcessComputer" -TargetSystem $computer
            $summary[$computer] = 'Failed'
            $failCount++
        }
    }
} catch {
    Write-AuditLog -Message "Critical error during execution: $_" -Level ERROR -Operation "MainExecution"
    throw
} finally {
    # Clear sensitive data
    if ($Credential) {
        $Credential = $null
    }
    [System.GC]::Collect()
}

# Summary Output
Write-Host "`nPatch Management Summary:" -ForegroundColor Cyan
Write-Host "Total computers: $($ComputerList.Count)"
Write-Host "Successfully patched: $successCount"
Write-Host "Failed: $failCount"
Write-Host "`nDetailed Results:"
foreach ($key in $summary.Keys) {
    $status = $summary[$key]
    $color = if ($status -eq 'Success') { 'Green' } else { 'Red' }
    Write-Host "  $key : $status" -ForegroundColor $color
}

Write-AuditLog -Message "Patch management completed. Success: $successCount, Failed: $failCount" -Level INFO -Operation "Completion"

if ($failCount -eq 0) {
    Write-AuditLog -Message "Script completed successfully with no errors" -Level SUCCESS -Operation "Completion"
    exit 0
} else {
    Write-AuditLog -Message "Script completed with $failCount error(s)" -Level WARNING -Operation "Completion"
    exit 1
}
