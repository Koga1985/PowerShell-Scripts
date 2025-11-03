<#
.SYNOPSIS
    Retrieves and displays snapshot information for all virtual machines in a vCenter Server or ESXi host.

.DESCRIPTION
    This script performs the following steps:
      1. Checks if the VMware.PowerCLI module is installed. If not, it installs the module.
      2. Imports the VMware.PowerCLI module.
      3. Prompts the user to enter vCenter/ESXi connection details (host, username, password) and connects.
      4. Retrieves all virtual machines in the environment.
      5. For each virtual machine, retrieves any snapshots and collects key snapshot data including age.
      6. Finally, disconnects from the vCenter/ESXi host.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Automatic session cleanup in finally blocks
    - Read-only operations to minimize infrastructure impact

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all snapshot inventory operations
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

[CmdletBinding()]
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
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1006 -Message $auditMessage -ErrorAction SilentlyContinue
    } catch { }
}

function Test-ValidServerName { param([string]$Name)
    if ($Name -match '[;&|`$<>]') { throw "Invalid characters detected in server name: $Name" }
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Server name cannot be empty or whitespace." }
    return $true
}

$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDirectory "Snapshot_Hunter_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

    $Summary = @{'VMs Checked' = 0; 'Snapshots Found' = 0; 'Errors' = 0}
    Write-AuditLog -Message "Retrieving virtual machines..." -VCenter $server -LogFile $logFile
    $allVMs = Get-VM
    Write-AuditLog -Message "Found $($allVMs.Count) virtual machines" -VCenter $server -LogFile $logFile

    foreach ($vm in $allVMs) {
        $Summary['VMs Checked']++
        try {
            $snapshots = Get-Snapshot -VM $vm -ErrorAction Stop
            if ($snapshots.Count -eq 0) {
                Write-Verbose "No snapshots found for VM '$($vm.Name)'"
            } else {
                $Summary['Snapshots Found'] += $snapshots.Count
                foreach ($snapshot in $snapshots) {
                    $snapshotAge = (Get-Date) - $snapshot.Created
                    $snapshotInfo = [PSCustomObject]@{
                        VMName = $vm.Name
                        SnapshotName = $snapshot.Name
                        Created = $snapshot.Created
                        AgeInDays = $snapshotAge.Days
                        SizeGB = $snapshot.SizeGB
                        IsCurrent = $snapshot.IsCurrent
                    }
                    $snapshotInfo | Format-Table -AutoSize
                    Write-AuditLog -Message "Snapshot found: $($snapshot.Name) on $($vm.Name) - Age: $($snapshotAge.Days) days" -VCenter $server -VMName $vm.Name -LogFile $logFile
                }
            }
        } catch {
            Write-AuditLog -Message "Error fetching snapshots for VM '$($vm.Name)': $_" -Level ERROR -VCenter $server -VMName $vm.Name -LogFile $logFile
            $Summary['Errors']++
        }
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
    Write-Host "Audit log saved to: $logFile"
    Write-AuditLog -Message "Snapshot collection process completed" -Level SECURITY -LogFile $logFile
}
