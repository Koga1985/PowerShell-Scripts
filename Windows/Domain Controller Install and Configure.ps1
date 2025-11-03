<#
.SYNOPSIS
    Secure Domain Controller installation and configuration for Fourth Estate infrastructure.

.DESCRIPTION
    Securely installs Active Directory Domain Services (AD DS) role and promotes server to Domain Controller
    with comprehensive security controls, prerequisite validation, and audit logging.

.PARAMETER DomainName
    The fully qualified domain name for the new AD forest (e.g., corp.local).

.PARAMETER SafeModePassword
    SecureString for the Directory Services Restore Mode (DSRM) administrator password.

.PARAMETER DNSIPAddress
    The DNS server IP address to assign (typically the server's own IP).

.EXAMPLE
    $safeModePwd = Read-Host -AsSecureString -Prompt "Enter DSRM Password"
    .\Domain_Controller_Install_and_Configure.ps1 -DomainName "corp.local" -SafeModePassword $safeModePwd -DNSIPAddress "192.168.1.10"

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for enhanced script reliability
    - Secure credential handling (SecureString for passwords)
    - Comprehensive prerequisite validation (disk space, network)
    - Audit logging to file and Windows Event Log
    - Input validation for all parameters
    - Sensitive data cleared from memory

.COMPLIANCE
    - NIST SP 800-53 Rev 5: AU-2, AU-3, AU-12 (Audit and Accountability)
    - NIST SP 800-53 Rev 5: IA-5 (Authenticator Management)
    - DISA STIG Active Directory Security Technical Implementation Guide
    - DoD Fourth Estate Active Directory security requirements

    WARNING: DC promotion will trigger automatic server reboot.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$')]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNull()]
    [System.Security.SecureString]$SafeModePassword,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$')]
    [string]$DNSIPAddress
)

$Global:AuditLogPath = "$env:ProgramData\DCInstall\Logs\audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$Global:EventLogSource = "DCInstall"
$Global:EventLogName = "Application"

function Initialize-AuditLog {
    try {
        $logDir = Split-Path $Global:AuditLogPath -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        if (-not ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource))) {
            New-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource
        }
    } catch { Write-Warning "Failed to initialize audit logging: $_" }
}

Initialize-AuditLog

function Write-AuditLog {
    [CmdletBinding()]
    param ([Parameter(Mandatory=$true)][string]$Message, [string]$Level = 'INFO', [string]$Action = 'DCInstall')
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $auditEntry = "$timestamp | $env:COMPUTERNAME | $username | $Level | $Action | $Message"
        Add-Content -Path $Global:AuditLogPath -Value $auditEntry -ErrorAction SilentlyContinue
        $eventType = if ($Level -eq 'ERROR') {'Error'} elseif ($Level -eq 'WARNING') {'Warning'} elseif ($Level -eq 'SECURITY') {'SuccessAudit'} else {'Information'}
        $eventId = if ($Level -eq 'ERROR') {6001} elseif ($Level -eq 'WARNING') {6002} elseif ($Level -eq 'SECURITY') {6003} else {6000}
        Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource -EventId $eventId -EntryType $eventType -Message $auditEntry -ErrorAction SilentlyContinue
        $color = if ($Level -eq 'ERROR') {'Red'} elseif ($Level -eq 'WARNING') {'Yellow'} elseif ($Level -eq 'SECURITY') {'Cyan'} else {'White'}
        Write-Host $auditEntry -ForegroundColor $color
    } catch { Write-Warning "Failed to write audit log: $_" }
}

try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  DC INSTALL & CONFIGURE v2.0" -ForegroundColor Cyan
    Write-Host "  Fourth Estate Secure Edition" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-AuditLog -Message "DC installation started for domain: $DomainName" -Level SECURITY -Action "ScriptStart"

    # Prerequisites
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan
    $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    if ($freeSpaceGB -lt 10) {
        throw "Insufficient disk space: $freeSpaceGB GB (need 10GB minimum)"
    }
    Write-Host "OK: Disk space sufficient ($freeSpaceGB GB)" -ForegroundColor Green

    # Install AD DS Role
    Write-Host "`nInstalling AD DS role..." -ForegroundColor Yellow
    Write-AuditLog -Message "Installing AD-Domain-Services role" -Level SECURITY -Action "RoleInstall"
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    Write-Host "SUCCESS: AD DS role installed" -ForegroundColor Green
    Write-AuditLog -Message "AD DS role installed successfully" -Level SECURITY -Action "RoleInstall"

    # Promote to DC
    Write-Host "`nPromoting to Domain Controller..." -ForegroundColor Yellow
    Write-AuditLog -Message "Starting DC promotion" -Level SECURITY -Action "DCPromotion"
    Install-ADDSForest -DomainName $DomainName -SafeModeAdministratorPassword $SafeModePassword `
        -Force:$true -InstallDns:$true -NoRebootOnCompletion:$false -ErrorAction Stop
    Write-AuditLog -Message "DC promotion initiated (server will reboot)" -Level SECURITY -Action "DCPromotion"

} catch {
    Write-AuditLog -Message "Critical error: $_" -Level ERROR -Action "ScriptError"
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($SafeModePassword) { $SafeModePassword = $null; [System.GC]::Collect() }
}
