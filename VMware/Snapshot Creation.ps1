<#
.SYNOPSIS
    Connects to a vCenter Server or ESXi host and creates a snapshot of a specified virtual machine.

.DESCRIPTION
    This script ensures the VMware PowerCLI module is installed and imported. It then prompts the user for
    connection details (vCenter/ESXi host, username, and password) and connects to the specified server. The user
    is then prompted for the target virtual machine name. The script validates that the virtual machine exists
    and, if found, creates a snapshot with a timestamped name. Finally, it disconnects from the server.

.PARAMETER None
    The script is interactive. User input is required at runtime for host connection and VM selection.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for VM names
    - WhatIf/Confirm support for snapshot operations
    - Automatic session cleanup in finally blocks

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all snapshot creations
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

[CmdletBinding(SupportsShouldProcess = $true)]
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
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1005 -Message $auditMessage -ErrorAction SilentlyContinue
    } catch { }
}

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

$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDirectory "Snapshot_Creation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
    Write-AuditLog -Message "Searching for virtual machine '$vmName'..." -VCenter $server -VMName $vmName -LogFile $logFile
    $vm = Get-VM -Name $vmName -ErrorAction Stop
    Write-AuditLog -Message "Virtual machine '$vmName' found" -VCenter $server -VMName $vmName -LogFile $logFile

    $snapshotName = "Snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if ($PSCmdlet.ShouldProcess("$vmName", "Create snapshot '$snapshotName'")) {
        Write-AuditLog -Message "Creating snapshot '$snapshotName' for virtual machine '$vmName'" -Level SECURITY -VCenter $server -VMName $vmName -LogFile $logFile
        New-Snapshot -VM $vm -Name $snapshotName -Description "Snapshot created via PowerCLI by $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ErrorAction Stop | Out-Null
        Write-AuditLog -Message "Snapshot '$snapshotName' created successfully for VM '$vmName'" -Level SECURITY -VCenter $server -VMName $vmName -LogFile $logFile
        $Summary = @{ 'Snapshot' = $snapshotName; 'Snapshot Status' = 'Created' }
    }
} catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -VCenter $server -LogFile $logFile
    if ($vmName) { $Summary = @{ 'Snapshot' = 'N/A'; 'Snapshot Status' = 'Failed'; 'Error' = $_ } }
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
    if ($Summary) { foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" } }
    Write-Host "Audit log saved to: $logFile"
    Write-AuditLog -Message "Script execution completed" -Level SECURITY -LogFile $logFile
}
