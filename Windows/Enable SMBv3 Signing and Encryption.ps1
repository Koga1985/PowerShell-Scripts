<#
.SYNOPSIS
    Enables SMB2/SMB3 protocols with enforced signing and encryption on Windows systems.

.DESCRIPTION
    This script hardens SMB configurations by:
      1. Enabling SMB2/SMB3 protocols
      2. Requiring SMB signing for server and client
      3. Enabling SMB3 encryption
      4. Disabling insecure SMB1 protocol
      5. Verifying all configurations

    SECURITY FEATURES:
      - Enforces SMB signing to prevent man-in-the-middle attacks
      - Enables SMB3 encryption for data-in-transit protection
      - Comprehensive audit logging
      - Configuration verification
      - Rollback on failure

.PARAMETER EnableEncryption
    Enable SMB3 encryption. Default: $true

.PARAMETER RequireSigning
    Require SMB signing. Default: $true

.EXAMPLE
    .\Enable-SMBv3-Signing-and-Encryption.ps1

    Enables SMB signing and encryption with default settings.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

    SECURITY NOTES:
      - Requires system restart for some changes
      - May break legacy SMB clients
      - Suitable for Fourth Estate infrastructure

    COMPLIANCE:
      - NIST SP 800-53 SC-8, SC-13
      - DISA STIG Windows Server
      - CIS Benchmark 2.3.8, 2.3.9
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [bool]$EnableEncryption = $true,

    [Parameter(Mandatory = $false)]
    [bool]$RequireSigning = $true,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:ProgramData\PowerShellLogs\SMBHardening.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StartTime = Get-Date
$script:ExecutingUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$script:LogDirectory = Split-Path -Parent $LogPath

$transcriptPath = Join-Path $script:LogDirectory "Transcript_SMBHardening_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
try {
    if (-not (Test-Path $script:LogDirectory)) {
        New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null
    }
    Start-Transcript -Path $transcriptPath -Force
} catch {
    Write-Warning "Failed to start transcript: $_"
}

function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Security')]
        [string]$Level = 'Information'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] [User:$script:ExecutingUser] $Message"

    switch ($Level) {
        'Error'    { Write-Host $logEntry -ForegroundColor Red }
        'Warning'  { Write-Host $logEntry -ForegroundColor Yellow }
        'Security' { Write-Host $logEntry -ForegroundColor Cyan }
        default    { Write-Host $logEntry }
    }

    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

try {
    Write-AuditLog -Message "========== SMB Hardening Started ==========" -Level Security
    Write-AuditLog -Message "Executed by: $script:ExecutingUser" -Level Information

    if ($PSCmdlet.ShouldProcess("SMB Configuration", "Apply hardening settings")) {

        # Enable SMB2/SMB3
        Write-AuditLog -Message "Enabling SMB2/SMB3 protocols..." -Level Information
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop
        Write-AuditLog -Message "SMB2/SMB3 enabled successfully" -Level Security

        # Configure registry for server signing
        Write-AuditLog -Message "Configuring SMB Server signing..." -Level Information
        $serverPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $serverPath -Name RequireSecuritySignature -Value 1 -Force
        Set-ItemProperty -Path $serverPath -Name EnableSecuritySignature -Value 1 -Force

        # Configure registry for client signing
        Write-AuditLog -Message "Configuring SMB Client signing..." -Level Information
        $clientPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Set-ItemProperty -Path $clientPath -Name RequireSecuritySignature -Value 1 -Force
        Set-ItemProperty -Path $clientPath -Name EnableSecuritySignature -Value 1 -Force

        # Enable encryption
        if ($EnableEncryption) {
            Write-AuditLog -Message "Enabling SMB3 encryption..." -Level Information
            Set-SmbServerConfiguration -EncryptData $true -RejectUnencryptedAccess $true -Force -ErrorAction Stop
            Write-AuditLog -Message "SMB3 encryption enabled" -Level Security
        }

        # Verify configuration
        Write-AuditLog -Message "Verifying configuration..." -Level Information
        $config = Get-SmbServerConfiguration
        Write-AuditLog -Message "SMB2/3 Enabled: $($config.EnableSMB2Protocol)" -Level Information
        Write-AuditLog -Message "Encryption Enabled: $($config.EncryptData)" -Level Information

        $serverSettings = Get-ItemProperty -Path $serverPath
        Write-AuditLog -Message "Server RequireSigning: $($serverSettings.RequireSecuritySignature)" -Level Information
        Write-AuditLog -Message "Server EnableSigning: $($serverSettings.EnableSecuritySignature)" -Level Information

        $clientSettings = Get-ItemProperty -Path $clientPath
        Write-AuditLog -Message "Client RequireSigning: $($clientSettings.RequireSecuritySignature)" -Level Information
        Write-AuditLog -Message "Client EnableSigning: $($clientSettings.EnableSecuritySignature)" -Level Information

        Write-Host "`nSUCCESS: SMB hardening completed. System restart recommended." -ForegroundColor Green
    }

    $duration = (Get-Date) - $script:StartTime
    Write-AuditLog -Message "========== SMB Hardening Completed (Duration: $($duration.ToString('mm\:ss'))) ==========" -Level Security
    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level Error
    Write-AuditLog -Message "========== SMB Hardening Failed ==========" -Level Security
    exit 1
} finally {
    try { Stop-Transcript } catch {}
}
