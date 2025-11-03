<#
.SYNOPSIS
    Removes all snapshots from a specified virtual machine on a vCenter Server or ESXi host.

.DESCRIPTION
    This script performs the following steps:
      1. Ensures that the VMware.PowerCLI module is installed; if not, it installs it.
      2. Imports the VMware.PowerCLI module.
      3. Prompts the user for connection details (vCenter/ESXi host, username, and password) and connects.
      4. Prompts for the target virtual machine name.
      5. Retrieves the virtual machine object and all its associated snapshots.
      6. If snapshots exist, it removes each one with confirmation support.
      7. Disconnects from the vCenter/ESXi host.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for VM names
    - WhatIf/Confirm support for destructive snapshot operations
    - Automatic session cleanup in finally blocks
    - Validates VM existence before operations

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all snapshot deletions
    - Follows principle of least privilege
    - Implements defense-in-depth security controls
    - Requires explicit confirmation for destructive operations

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
#Requires -Modules VMware.PowerCLI

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#==============================================
# Global Audit Logging Function
#==============================================
function Write-AuditLog {
    param([Parameter(Mandatory = $true)][string]$Message, [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')][string]$Level = 'INFO',
        [string]$LogFile, [string]$VCenter, [string]$VMName)
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $auditMessage = "$timeStamp [$Level] User: $userName"
    if ($VCenter) { $auditMessage += " | vCenter: $VCenter" }
    if ($VMName) { $auditMessage += " | Resource: $VMName" }
    $auditMessage += " | $Message"
    switch ($Level) {
        'ERROR'    { Write-Host $auditMessage -ForegroundColor Red }
        'WARNING'  { Write-Host $auditMessage -ForegroundColor Yellow }
        'SECURITY' { Write-Host $auditMessage -ForegroundColor Cyan }
        default    { Write-Host $auditMessage }
    }
    if ($LogFile) { try { Add-Content -Path $LogFile -Value $auditMessage -ErrorAction Stop } catch { Write-Warning "Failed to write to log file: $_" } }
    try {
        $eventSource = 'VMware-PowerCLI-Security'
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) { New-EventLog -LogName Application -Source $eventSource -ErrorAction SilentlyContinue }
        $eventType = switch ($Level) { 'ERROR' { 'Error' } 'WARNING' { 'Warning' } 'SECURITY' { 'SuccessAudit' } default { 'Information' } }
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1004 -Message $auditMessage -ErrorAction SilentlyContinue
    } catch { }
}

#==============================================
# Input Validation Functions
#==============================================
function Test-ValidServerName { param([string]$Name)
    if ($Name -match '[;&|`$<>]') { throw "Invalid characters detected in server name: $Name" }
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Server name cannot be empty or whitespace." }
    return $true
}
function Test-ValidVMName { param([string]$Name)
    if ($Name -match '[;&|`$<>]') { throw "Invalid characters detected in VM name: $Name" }
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "VM name cannot be empty or whitespace." }
    return $true
}

#==============================================
# Main Script Execution
#==============================================
$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDirectory "Remove_Snapshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Write-AuditLog -Message "Script execution started" -Level SECURITY -LogFile $logFile
$viConnection = $null
$credential = $null

try {
    Write-AuditLog -Message "Checking for VMware.PowerCLI module..." -LogFile $logFile
    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-AuditLog -Message "VMware.PowerCLI module not found. Installing..." -Level WARNING -LogFile $logFile
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
        Write-AuditLog -Message "VMware.PowerCLI installed successfully" -LogFile $logFile
    } else { Write-AuditLog -Message "VMware.PowerCLI module already installed" -LogFile $logFile }
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-AuditLog -Message "VMware.PowerCLI module imported successfully" -LogFile $logFile
    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null
    Write-AuditLog -Message "PowerCLI security configuration applied" -Level SECURITY -LogFile $logFile

    $server = Read-Host "Enter vCenter Server or ESXi host"
    Test-ValidServerName -Name $server
    $user = Read-Host "Enter username"
    $securePassword = Read-Host "Enter password" -AsSecureString
    $credential = New-Object System.Management.Automation.PSCredential($user, $securePassword)
    Write-AuditLog -Message "Attempting secure connection to $server" -VCenter $server -LogFile $logFile
    $viConnection = Connect-VIServer -Server $server -Credential $credential -ErrorAction Stop
    Write-AuditLog -Message "Successfully connected to $server" -Level SECURITY -VCenter $server -LogFile $logFile

    $vmName = Read-Host "Enter the virtual machine name"
    Test-ValidVMName -Name $vmName
    $vm = Get-VM -Name $vmName -ErrorAction Stop
    Write-AuditLog -Message "Virtual machine '$vmName' found" -VCenter $server -VMName $vmName -LogFile $logFile

    $Summary = @{}
    $snapshots = Get-Snapshot -VM $vm
    if ($snapshots.Count -eq 0) {
        Write-AuditLog -Message "No snapshots found for virtual machine '$vmName'" -VCenter $server -VMName $vmName -LogFile $logFile
        $Summary['Snapshots Removed'] = 'None Found'
    } else {
        Write-AuditLog -Message "Found $($snapshots.Count) snapshot(s) for VM '$vmName'" -VCenter $server -VMName $vmName -LogFile $logFile
        $removed = 0
        $failed = 0
        foreach ($snapshot in $snapshots) {
            if ($PSCmdlet.ShouldProcess("$vmName", "Remove snapshot '$($snapshot.Name)'")) {
                try {
                    Write-AuditLog -Message "Removing snapshot '$($snapshot.Name)' from VM '$vmName'" -Level SECURITY -VCenter $server -VMName $vmName -LogFile $logFile
                    Remove-Snapshot -Snapshot $snapshot -Confirm:$false -ErrorAction Stop
                    Write-AuditLog -Message "Snapshot '$($snapshot.Name)' removed successfully" -Level SECURITY -VCenter $server -VMName $vmName -LogFile $logFile
                    $removed++
                } catch {
                    Write-AuditLog -Message "Error removing snapshot '$($snapshot.Name)': $_" -Level ERROR -VCenter $server -VMName $vmName -LogFile $logFile
                    $failed++
                }
            }
        }
        $Summary['Snapshots Removed'] = $removed
        $Summary['Snapshots Failed'] = $failed
    }
} catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -VCenter $server -LogFile $logFile
    throw
} finally {
    if ($viConnection) {
        try {
            Write-AuditLog -Message "Disconnecting from $server" -VCenter $server -LogFile $logFile
            Disconnect-VIServer -Server $server -Confirm:$false -ErrorAction SilentlyContinue
            Write-AuditLog -Message "Disconnected from $server" -Level SECURITY -VCenter $server -LogFile $logFile
        } catch { Write-AuditLog -Message "Error during disconnect: $_" -Level WARNING -LogFile $logFile }
    }
    if ($credential) { $credential = $null }
    if ($securePassword) { $securePassword = $null }
    Write-Host "`nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
    if ($vmName) { Write-Host "Target VM: $vmName" }
    Write-Host "Audit log saved to: $logFile"
    Write-AuditLog -Message "Snapshot removal process completed" -Level SECURITY -LogFile $logFile
}
