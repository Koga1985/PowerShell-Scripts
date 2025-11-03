<#
.SYNOPSIS
    Self-healing Active Directory health monitoring and repair for Fourth Estate infrastructure.

.DESCRIPTION
    Monitors Active Directory domain controllers and replication health, automatically
    attempting remediation when issues are detected. Includes comprehensive audit logging.

    Functions:
      1. Checks connectivity to all domain controllers
      2. Monitors AD replication status
      3. Initiates replication repair when needed
      4. Validates DNS resolution
      5. Attempts network configuration renewal if needed

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for enhanced script reliability
    - Comprehensive audit logging to file and Windows Event Log
    - Read-only operations unless repair is needed
    - All remediation actions logged for compliance
    - Automatic detection and repair with minimal intervention

.COMPLIANCE
    - NIST SP 800-53 Rev 5: AU-2, AU-3, AU-12 (Audit and Accountability)
    - NIST SP 800-53 Rev 5: SI-7 (Software, Firmware, and Information Integrity)
    - DISA STIG Active Directory Security Technical Implementation Guide
    - DoD Fourth Estate Active Directory resilience requirements

.EXAMPLE
    .\Self_Healing_AD.ps1
    Runs AD health check and automatic remediation.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Global:AuditLogPath = "$env:ProgramData\ADSelfHealing\Logs\audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$Global:EventLogSource = "ADSelfHealing"
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
    param ([Parameter(Mandatory=$true)][string]$Message, [string]$Level = 'INFO', [string]$Action = 'ADHealth')
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $auditEntry = "$timestamp | $env:COMPUTERNAME | $username | $Level | $Action | $Message"
        Add-Content -Path $Global:AuditLogPath -Value $auditEntry -ErrorAction SilentlyContinue
        $eventType = if ($Level -eq 'ERROR') {'Error'} elseif ($Level -eq 'WARNING') {'Warning'} elseif ($Level -eq 'SECURITY') {'SuccessAudit'} else {'Information'}
        $eventId = if ($Level -eq 'ERROR') {8001} elseif ($Level -eq 'WARNING') {8002} elseif ($Level -eq 'SECURITY') {8003} else {8000}
        Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource -EventId $eventId -EntryType $eventType -Message $auditEntry -ErrorAction SilentlyContinue
        $color = if ($Level -eq 'ERROR') {'Red'} elseif ($Level -eq 'WARNING') {'Yellow'} elseif ($Level -eq 'SECURITY') {'Cyan'} else {'White'}
        Write-Host $auditEntry -ForegroundColor $color
    } catch { Write-Warning "Failed to write audit log: $_" }
}

function Repair-AD {
    <#
    .SYNOPSIS
        Main AD health check and repair function.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  AD SELF-HEALING CHECK v2.0" -ForegroundColor Cyan
    Write-Host "  Fourth Estate Edition" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-AuditLog -Message "AD self-healing check started" -Level SECURITY -Action "HealthCheck"

    # Get domain controllers
    try {
        Write-Host "Retrieving domain controllers..." -ForegroundColor Cyan
        $domainControllers = Get-ADDomainController -Filter * -ErrorAction Stop
        Write-AuditLog -Message "Found $($domainControllers.Count) domain controllers" -Level INFO
        Write-Host "Found $($domainControllers.Count) domain controllers" -ForegroundColor White
    } catch {
        Write-AuditLog -Message "Error retrieving domain controllers: $_" -Level ERROR
        Write-Host "ERROR: Cannot retrieve domain controllers: $_" -ForegroundColor Red
        return
    }

    # Check connectivity
    Write-Host "`nChecking connectivity to domain controllers..." -ForegroundColor Cyan
    $reachableDCs = @()
    foreach ($dc in $domainControllers) {
        try {
            $pingResult = Test-Connection -ComputerName $dc.HostName -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($pingResult) {
                Write-Host "  OK: $($dc.HostName) is reachable" -ForegroundColor Green
                Write-AuditLog -Message "DC reachable: $($dc.HostName)" -Level INFO
                $reachableDCs += $dc
            } else {
                Write-Host "  WARNING: $($dc.HostName) is not reachable" -ForegroundColor Yellow
                Write-AuditLog -Message "DC unreachable: $($dc.HostName)" -Level WARNING
            }
        } catch {
            Write-Host "  ERROR: Failed to ping $($dc.HostName)" -ForegroundColor Red
            Write-AuditLog -Message "Ping failed for DC: $($dc.HostName)" -Level ERROR
        }
    }

    # Check replication if DCs are reachable
    if ($reachableDCs.Count -gt 0) {
        Write-Host "`nChecking AD replication health..." -ForegroundColor Cyan
        try {
            $replicationMetadata = Get-ADReplicationPartnerMetadata -Target * -ErrorAction Stop
            $replicationIssues = $replicationMetadata | Where-Object { $_.LastReplicationSuccess -lt (Get-Date).AddDays(-1) }

            if ($replicationIssues) {
                Write-Host "  WARNING: Replication issues detected" -ForegroundColor Yellow
                Write-AuditLog -Message "Replication issues detected, initiating repair" -Level WARNING -Action "ReplicationRepair"

                foreach ($meta in $replicationMetadata) {
                    Write-Host "  Forcing replication: $($meta.Server) <- $($meta.Partner)" -ForegroundColor Yellow
                    Write-AuditLog -Message "Forcing replication from $($meta.Partner) to $($meta.Server)" -Level SECURITY -Action "ReplicationRepair"
                    repadmin /replicate $meta.Server $meta.Partner | Out-Null
                }
                Write-Host "  SUCCESS: Replication repair initiated" -ForegroundColor Green
                Write-AuditLog -Message "Replication repair completed" -Level SECURITY -Action "ReplicationRepair"
            } else {
                Write-Host "  OK: AD replication is healthy" -ForegroundColor Green
                Write-AuditLog -Message "AD replication is healthy" -Level INFO
            }
        } catch {
            Write-Host "  ERROR: Failed to check replication: $_" -ForegroundColor Red
            Write-AuditLog -Message "Error checking replication: $_" -Level ERROR
        }
    } else {
        Write-Host "`nWARNING: No domain controllers are reachable" -ForegroundColor Yellow
        Write-AuditLog -Message "No domain controllers reachable, checking DNS" -Level WARNING -Action "DNSCheck"

        # Check DNS resolution
        try {
            $dcHostName = $domainControllers[0].HostName
            Write-Host "Checking DNS resolution for $dcHostName..." -ForegroundColor Cyan
            $dnsRecord = Resolve-DnsName -Name $dcHostName -ErrorAction SilentlyContinue

            if ($dnsRecord) {
                Write-Host "  OK: DNS resolution successful, but DC still unreachable" -ForegroundColor Yellow
                Write-Host "  Check network connectivity and firewall rules" -ForegroundColor Yellow
                Write-AuditLog -Message "DNS resolution works but DCs unreachable - network issue" -Level WARNING
            } else {
                Write-Host "  ERROR: DNS resolution failed" -ForegroundColor Red
                Write-Host "  Attempting to renew IP configuration..." -ForegroundColor Yellow
                Write-AuditLog -Message "DNS resolution failed, renewing IP config" -Level WARNING -Action "NetworkRepair"

                ipconfig /renew | Out-Null
                Write-Host "  SUCCESS: IP configuration renewed" -ForegroundColor Green
                Write-Host "  Re-run this script after network changes take effect" -ForegroundColor Yellow
                Write-AuditLog -Message "IP configuration renewed" -Level SECURITY -Action "NetworkRepair"
            }
        } catch {
            Write-Host "  ERROR: DNS check failed: $_" -ForegroundColor Red
            Write-AuditLog -Message "DNS check failed: $_" -Level ERROR
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  AD HEALTH CHECK COMPLETED" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Audit log: $Global:AuditLogPath" -ForegroundColor Gray

    Write-AuditLog -Message "AD self-healing check completed" -Level SECURITY -Action "HealthCheck"
}

# Run the repair function
Repair-AD
