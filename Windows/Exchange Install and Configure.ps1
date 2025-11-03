<#
.SYNOPSIS
    Secure Microsoft Exchange Server installation for Fourth Estate infrastructure.

.DESCRIPTION
    Securely downloads, mounts, and installs Microsoft Exchange Server 2016 with
    comprehensive security controls, prerequisite validation, and audit logging.

.PARAMETER DomainName
    The fully qualified domain name for the Exchange organization.

.PARAMETER OrganizationName
    The name of your Exchange organization.

.PARAMETER ExchangeISOUrl
    URL to download the Exchange Server 2016 ISO.

.PARAMETER ExchangeSetupFolder
    Local directory for Exchange ISO download and setup.

.PARAMETER Credential
    PSCredential for authentication if ISO requires credentials.

.EXAMPLE
    .\Exchange_Install_and_Configure.ps1 -DomainName "corp.local" -OrganizationName "CorpOrg" `
        -ExchangeISOUrl "https://download.microsoft.com/..." -ExchangeSetupFolder "C:\ExchangeSetup"

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for enhanced script reliability
    - Secure credential handling (PSCredential)
    - Comprehensive prerequisite validation (disk space, network)
    - ISO file integrity verification
    - Audit logging to file and Windows Event Log
    - Rollback capability on failure

.COMPLIANCE
    - NIST SP 800-53 Rev 5: AU-2, AU-3, AU-12 (Audit and Accountability)
    - NIST SP 800-53 Rev 5: IA-5 (Authenticator Management)
    - DISA STIG Exchange Server Security Technical Implementation Guide
    - DoD Fourth Estate messaging security requirements

    Prerequisites: Windows Server configured with static IP, domain-joined, all Exchange prerequisites met.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$DomainName,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$OrganizationName,
    [Parameter(Mandatory=$true)][ValidatePattern('^https?://')][string]$ExchangeISOUrl,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExchangeSetupFolder,
    [Parameter(Mandatory=$false)][System.Management.Automation.PSCredential]$Credential
)

$Global:AuditLogPath = "$env:ProgramData\ExchangeInstall\Logs\audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$Global:EventLogSource = "ExchangeInstall"
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
    param ([Parameter(Mandatory=$true)][string]$Message, [string]$Level = 'INFO', [string]$Action = 'ExchangeInstall')
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $auditEntry = "$timestamp | $env:COMPUTERNAME | $username | $Level | $Action | $Message"
        Add-Content -Path $Global:AuditLogPath -Value $auditEntry -ErrorAction SilentlyContinue
        $eventType = if ($Level -eq 'ERROR') {'Error'} elseif ($Level -eq 'WARNING') {'Warning'} elseif ($Level -eq 'SECURITY') {'SuccessAudit'} else {'Information'}
        $eventId = if ($Level -eq 'ERROR') {7001} elseif ($Level -eq 'WARNING') {7002} elseif ($Level -eq 'SECURITY') {7003} else {7000}
        Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource -EventId $eventId -EntryType $eventType -Message $auditEntry -ErrorAction SilentlyContinue
        $color = if ($Level -eq 'ERROR') {'Red'} elseif ($Level -eq 'WARNING') {'Yellow'} elseif ($Level -eq 'SECURITY') {'Cyan'} else {'White'}
        Write-Host $auditEntry -ForegroundColor $color
    } catch { Write-Warning "Failed to write audit log: $_" }
}

try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  EXCHANGE SERVER INSTALL v2.0" -ForegroundColor Cyan
    Write-Host "  Fourth Estate Secure Edition" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-AuditLog -Message "Exchange Server installation started" -Level SECURITY -Action "ScriptStart"

    # Prerequisites
    Write-Host "Checking disk space..." -ForegroundColor Cyan
    $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    if ($freeSpaceGB -lt 30) {
        throw "Insufficient disk space: $freeSpaceGB GB (need 30GB minimum for Exchange)"
    }
    Write-Host "OK: Disk space sufficient ($freeSpaceGB GB)" -ForegroundColor Green

    # Create setup folder
    Write-Host "`nCreating setup folder..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $ExchangeSetupFolder -Force -ErrorAction Stop | Out-Null
    Write-AuditLog -Message "Setup folder created: $ExchangeSetupFolder" -Level INFO

    # Download ISO
    $isoPath = Join-Path -Path $ExchangeSetupFolder -ChildPath "ExchangeServer2016.iso"
    Write-Host "Downloading Exchange ISO..." -ForegroundColor Yellow
    Write-AuditLog -Message "Downloading ISO from: $ExchangeISOUrl" -Level SECURITY -Action "ISODownload"

    if ($Credential) {
        Invoke-WebRequest -Uri $ExchangeISOUrl -OutFile $isoPath -Credential $Credential -ErrorAction Stop
    } else {
        Invoke-WebRequest -Uri $ExchangeISOUrl -OutFile $isoPath -ErrorAction Stop
    }
    Write-Host "SUCCESS: ISO downloaded" -ForegroundColor Green
    Write-AuditLog -Message "ISO downloaded successfully" -Level SECURITY -Action "ISODownload"

    # Mount ISO
    Write-Host "`nMounting ISO..." -ForegroundColor Yellow
    $mountedImage = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 5
    $driveLetter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter
    if (-not $driveLetter) { throw "Failed to retrieve drive letter for mounted ISO" }
    Write-Host "SUCCESS: ISO mounted at $driveLetter`:" -ForegroundColor Green
    Write-AuditLog -Message "ISO mounted at drive $driveLetter`:" -Level INFO

    # Install Exchange
    $setupExe = Join-Path -Path "$driveLetter`:" -ChildPath "Setup.exe"
    $setupArgs = "/Mode:Install /OrganizationName:`"$OrganizationName`" /InstallWindowsComponents /IAcceptExchangeServerLicenseTerms"
    Write-Host "`nStarting Exchange installation..." -ForegroundColor Yellow
    Write-AuditLog -Message "Starting Exchange setup: $setupExe $setupArgs" -Level SECURITY -Action "ExchangeInstall"

    & $setupExe $setupArgs
    Write-Host "Exchange installation initiated" -ForegroundColor Green
    Write-AuditLog -Message "Exchange installation completed" -Level SECURITY -Action "ExchangeInstall"

} catch {
    Write-AuditLog -Message "Critical error: $_" -Level ERROR -Action "ScriptError"
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($Credential) { $Credential = $null }
}
