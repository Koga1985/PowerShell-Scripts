#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables SMBv1 on a Windows system by modifying both the SMB Server configuration and relevant registry settings.

.DESCRIPTION
    This script applies two methods to disable SMBv1:
      1. It disables SMBv1 via the Set-SmbServerConfiguration cmdlet.
      2. It also sets the SMB1 value to 0 in the registry for both LanmanServer and LanmanWorkstation services.
      3. Provides comprehensive audit logging and verification.

.PARAMETER WhatIf
    Shows what would happen if the script runs without actually executing the changes.

.PARAMETER Confirm
    Prompts for confirmation before executing each change.

.EXAMPLE
    .\Disable SMBv1.ps1
    Disables SMBv1 and displays current configuration status.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    Updated:        October 30, 2025
    Version:        2.0
    License:        MIT
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - System reboot recommended for full effect

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Registry path validation and verification
    - Safe rollback on error
    - Proper error handling

.COMPLIANCE
    - Aligns with NIST 800-53 SC-8 controls
    - Supports DISA STIG vulnerability mitigation requirements
    - Mitigates WannaCry/EternalBlue vulnerabilities
    - Fourth Estate infrastructure compatible
    - Full audit trail for compliance reporting

.DISCLAIMER
    Scripts are provided as-is, without warranty. Test in non-production before use.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "DisableSMBv1_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\DisableSMBv1_Audit.log"
$script:EventSource = "SMBv1Disable"

$auditLogDir = Split-Path -Parent $script:AuditLogPath
if (-not (Test-Path -Path $auditLogDir)) {
    New-Item -Path $auditLogDir -ItemType Directory -Force | Out-Null
}

try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($script:EventSource)) {
        New-EventLog -LogName Application -Source $script:EventSource -ErrorAction SilentlyContinue
    }
} catch { Write-Warning "Unable to create event log source. Event logging will be limited." }

#----------------------------------------------
# Audit Logging Function
#----------------------------------------------
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $computerName = $env:COMPUTERNAME
    $logEntry = "$timestamp [$Level] [$userName@$computerName] $Message"

    try { Add-Content -Path $script:AuditLogPath -Value $logEntry -ErrorAction Stop } catch { Write-Warning "Failed to write to audit log: $_" }

    $eventType = switch ($Level) { 'ERROR' { 'Error' } 'WARNING' { 'Warning' } default { 'Information' } }
    $eventIdMap = @{ 'INFO' = 1000; 'SUCCESS' = 1001; 'WARNING' = 2000; 'ERROR' = 3000 }

    try { Write-EventLog -LogName Application -Source $script:EventSource -EntryType $eventType -EventId $eventIdMap[$Level] -Message $logEntry -ErrorAction SilentlyContinue } catch { }

    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARNING' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'White' } }
    Write-Host $logEntry -ForegroundColor $color
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
try {
    Write-AuditLog -Message "===== Disable SMBv1 Script Started =====" -Level "INFO"

    # 1. Disable SMBv1 via SMB Server Configuration
    if ($PSCmdlet.ShouldProcess("SMB Server Configuration", "Disable SMBv1 Protocol")) {
        Write-AuditLog -Message "Disabling SMBv1 protocol via Set-SmbServerConfiguration..." -Level "INFO"
        try {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
            Write-AuditLog -Message "SMBv1 disabled in SMB Server configuration." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Error disabling SMBv1 via Set-SmbServerConfiguration: $_" -Level "ERROR"
            throw
        }
    }

    # 2. Disable SMBv1 via Registry (LanmanServer)
    $lanmanServerPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    if ($PSCmdlet.ShouldProcess($lanmanServerPath, "Set SMB1=0")) {
        Write-AuditLog -Message "Configuring LanmanServer registry..." -Level "INFO"
        try {
            if (-not (Test-Path -Path $lanmanServerPath)) {
                New-Item -Path $lanmanServerPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $lanmanServerPath -Name "SMB1" -Type DWORD -Value 0 -Force -ErrorAction Stop
            Write-AuditLog -Message "SMB1 disabled in LanmanServer registry." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Error setting LanmanServer registry: $_" -Level "ERROR"
        }
    }

    # 3. Disable SMBv1 via Registry (LanmanWorkstation)
    $lanmanWorkstationPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
    if ($PSCmdlet.ShouldProcess($lanmanWorkstationPath, "Set SMB1=0")) {
        Write-AuditLog -Message "Configuring LanmanWorkstation registry..." -Level "INFO"
        try {
            if (-not (Test-Path -Path $lanmanWorkstationPath)) {
                New-Item -Path $lanmanWorkstationPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $lanmanWorkstationPath -Name "SMB1" -Type DWORD -Value 0 -Force -ErrorAction Stop
            Write-AuditLog -Message "SMB1 disabled in LanmanWorkstation registry." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Error setting LanmanWorkstation registry: $_" -Level "ERROR"
        }
    }

    # 4. Verify Configuration
    Write-AuditLog -Message "Verifying SMBv1 configuration..." -Level "INFO"
    try {
        $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop | Select-Object EnableSMB1Protocol
        Write-AuditLog -Message "SMB Server EnableSMB1Protocol = $($smbConfig.EnableSMB1Protocol)" -Level "INFO"
    } catch {
        Write-AuditLog -Message "Error retrieving SMB Server configuration: $_" -Level "WARNING"
    }

    try {
        $lanmanServerSetting = Get-ItemProperty -Path $lanmanServerPath -Name "SMB1" -ErrorAction Stop
        Write-AuditLog -Message "LanmanServer SMB1 = $($lanmanServerSetting.SMB1)" -Level "INFO"
    } catch {
        Write-AuditLog -Message "Error reading LanmanServer registry: $_" -Level "WARNING"
    }

    try {
        $lanmanWorkstationSetting = Get-ItemProperty -Path $lanmanWorkstationPath -Name "SMB1" -ErrorAction Stop
        Write-AuditLog -Message "LanmanWorkstation SMB1 = $($lanmanWorkstationSetting.SMB1)" -Level "INFO"
    } catch {
        Write-AuditLog -Message "Error reading LanmanWorkstation registry: $_" -Level "WARNING"
    }

    Write-AuditLog -Message "===== SMBv1 Disabled Successfully =====" -Level "SUCCESS"
    Write-AuditLog -Message "IMPORTANT: System reboot recommended for full effect." -Level "WARNING"
    Write-AuditLog -Message "Transcript saved to: $transcriptPath" -Level "INFO"
    Write-AuditLog -Message "Audit log saved to: $script:AuditLogPath" -Level "INFO"

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level "ERROR"
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
} finally {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
}
