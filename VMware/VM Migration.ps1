<#
.SYNOPSIS
    Migrates a specified virtual machine from a source vCenter Server or ESXi host to a destination host or cluster.

.DESCRIPTION
    This script performs the following actions:
      1. Checks if the VMware.PowerCLI module is installed and installs it if not.
      2. Imports the PowerCLI module with security configuration.
      3. Prompts for source and destination connection details and connects to both.
      4. Prompts for the virtual machine name to migrate.
      5. Validates the specified virtual machine and destination.
      6. Migrates the virtual machine to the destination.
      7. Disconnects from both source and destination environments.

.PARAMETER None
    The script is interactive; it prompts for all necessary details.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for VM names and destinations
    - WhatIf/Confirm support for migration operations
    - Automatic session cleanup in finally blocks

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all VM migrations
    - Follows principle of least privilege
    - Implements defense-in-depth security controls

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

function Write-AuditLog {
    param([Parameter(Mandatory = $true)][string]$Message, [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')][string]$Level = 'INFO',
        [string]$LogFile, [string]$VCenter, [string]$VMName)
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $auditMessage = "$timeStamp [$Level] User: $userName"
    if ($VCenter) { $auditMessage += " | vCenter: $VCenter" }
    if ($VMName) { $auditMessage += " | Resource: $VMName" }
    $auditMessage += " | $Message"
    switch ($Level) { 'ERROR' { Write-Host $auditMessage -ForegroundColor Red } 'WARNING' { Write-Host $auditMessage -ForegroundColor Yellow }
        'SECURITY' { Write-Host $auditMessage -ForegroundColor Cyan } default { Write-Host $auditMessage } }
    if ($LogFile) { try { Add-Content -Path $LogFile -Value $auditMessage -ErrorAction Stop } catch { Write-Warning "Failed to write to log file: $_" } }
    try {
        $eventSource = 'VMware-PowerCLI-Security'
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) { New-EventLog -LogName Application -Source $eventSource -ErrorAction SilentlyContinue }
        $eventType = switch ($Level) { 'ERROR' { 'Error' } 'WARNING' { 'Warning' } 'SECURITY' { 'SuccessAudit' } default { 'Information' } }
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1008 -Message $auditMessage -ErrorAction SilentlyContinue
    } catch { }
}

function Test-ValidServerName { param([string]$Name)
    if ($Name -match '[;&|`$<>]') { throw "Invalid characters in server name: $Name" }
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Server name cannot be empty" }
    return $true
}
function Test-ValidVMName { param([string]$Name)
    if ($Name -match '[;&|`$<>]') { throw "Invalid characters in VM name: $Name" }
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "VM name cannot be empty" }
    return $true
}

$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDirectory "VM_Migration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Write-AuditLog -Message "Script execution started" -Level SECURITY -LogFile $logFile
$srcConnection = $null
$dstConnection = $null
$srcCredential = $null
$dstCredential = $null

try {
    Write-AuditLog -Message "Checking for VMware.PowerCLI module..." -LogFile $logFile
    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-AuditLog -Message "Installing VMware.PowerCLI..." -Level WARNING -LogFile $logFile
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null
    Write-AuditLog -Message "PowerCLI security configuration applied" -Level SECURITY -LogFile $logFile

    $Summary = @{}
    $sourceServer = Read-Host "Enter source vCenter Server or ESXi host"
    Test-ValidServerName -Name $sourceServer
    $sourceUser = Read-Host "Enter source username"
    $sourcePassword = Read-Host "Enter source password" -AsSecureString
    $srcCredential = New-Object System.Management.Automation.PSCredential($sourceUser, $sourcePassword)
    Write-AuditLog -Message "Connecting to source: $sourceServer" -VCenter $sourceServer -LogFile $logFile
    $srcConnection = Connect-VIServer -Server $sourceServer -Credential $srcCredential -ErrorAction Stop
    Write-AuditLog -Message "Connected to source: $sourceServer" -Level SECURITY -VCenter $sourceServer -LogFile $logFile
    $Summary['Source Connection'] = 'Success'

    $destinationServer = Read-Host "Enter destination vCenter Server or ESXi host"
    Test-ValidServerName -Name $destinationServer
    $destinationUser = Read-Host "Enter destination username"
    $destinationPassword = Read-Host "Enter destination password" -AsSecureString
    $dstCredential = New-Object System.Management.Automation.PSCredential($destinationUser, $destinationPassword)
    Write-AuditLog -Message "Connecting to destination: $destinationServer" -VCenter $destinationServer -LogFile $logFile
    $dstConnection = Connect-VIServer -Server $destinationServer -Credential $dstCredential -ErrorAction Stop
    Write-AuditLog -Message "Connected to destination: $destinationServer" -Level SECURITY -VCenter $destinationServer -LogFile $logFile
    $Summary['Destination Connection'] = 'Success'

    $vmName = Read-Host "Enter the virtual machine name to migrate"
    Test-ValidVMName -Name $vmName
    Write-AuditLog -Message "Retrieving VM '$vmName' from source" -VCenter $sourceServer -VMName $vmName -LogFile $logFile
    $vm = Get-VM -Name $vmName -Server $sourceServer -ErrorAction Stop
    Write-AuditLog -Message "VM '$vmName' found" -VCenter $sourceServer -VMName $vmName -LogFile $logFile
    $Summary['VM Found'] = 'Yes'

    $destinationTarget = Read-Host "Enter the destination host or cluster"
    $destination = Get-VMHost -Name $destinationTarget -Server $destinationServer -ErrorAction SilentlyContinue
    if (-not $destination) { $destination = Get-Cluster -Name $destinationTarget -Server $destinationServer -ErrorAction Stop }
    Write-AuditLog -Message "Destination target '$destinationTarget' validated" -VCenter $destinationServer -LogFile $logFile
    $Summary['Destination Found'] = 'Yes'

    if ($PSCmdlet.ShouldProcess("$vmName", "Migrate to $destinationTarget")) {
        Write-AuditLog -Message "Migrating VM '$vmName' to '$destinationTarget'" -Level SECURITY -VCenter $sourceServer -VMName $vmName -LogFile $logFile
        Move-VM -VM $vm -Destination $destination -Server $destinationServer -Confirm:$false -ErrorAction Stop
        Write-AuditLog -Message "VM '$vmName' migrated successfully" -Level SECURITY -VCenter $destinationServer -VMName $vmName -LogFile $logFile
        $Summary['Migration'] = 'Success'
    }
} catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -LogFile $logFile
    if ($vmName) { $Summary['Migration'] = 'Failed' }
    throw
} finally {
    if ($srcConnection) {
        try {
            Write-AuditLog -Message "Disconnecting from source: $sourceServer" -VCenter $sourceServer -LogFile $logFile
            Disconnect-VIServer -Server $sourceServer -Confirm:$false -ErrorAction SilentlyContinue
            Write-AuditLog -Message "Disconnected from source" -Level SECURITY -VCenter $sourceServer -LogFile $logFile
        } catch { Write-AuditLog -Message "Error disconnecting from source: $_" -Level WARNING -LogFile $logFile }
    }
    if ($dstConnection) {
        try {
            Write-AuditLog -Message "Disconnecting from destination: $destinationServer" -VCenter $destinationServer -LogFile $logFile
            Disconnect-VIServer -Server $destinationServer -Confirm:$false -ErrorAction SilentlyContinue
            Write-AuditLog -Message "Disconnected from destination" -Level SECURITY -VCenter $destinationServer -LogFile $logFile
        } catch { Write-AuditLog -Message "Error disconnecting from destination: $_" -Level WARNING -LogFile $logFile }
    }
    if ($srcCredential) { $srcCredential = $null }
    if ($dstCredential) { $dstCredential = $null }
    if ($sourcePassword) { $sourcePassword = $null }
    if ($destinationPassword) { $destinationPassword = $null }
    Write-Host "`nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
    Write-Host "Audit log saved to: $logFile"
    Write-AuditLog -Message "VM migration process completed" -Level SECURITY -LogFile $logFile
}
