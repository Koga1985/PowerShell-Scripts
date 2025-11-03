<#
.SYNOPSIS
    Performs a health check on a vCenter Server or ESXi host and exports results to a CSV file.

.DESCRIPTION
    This script:
      1. Checks whether VMware.PowerCLI is installed; if not, it installs the module.
      2. Imports the PowerCLI module.
      3. Prompts the user for vCenter/ESXi connection details and connects to the server.
      4. Prompts for an output path to export health check results.
      5. Performs several health checks:
            - Host status (name, connection state, power state)
            - Datastore usage (name, total capacity, free space, used space)
            - Virtual machine configurations (name, power state, CPUs, memory, hard disks, network adapters)
            - Snapshot details (associated VM, snapshot name, creation time, size)
            - Orphaned VMs (VMs with inaccessible connection state)
      6. Exports the collected results to a CSV file.
      7. Disconnects from the vCenter/ESXi host.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for file paths and server names
    - WhatIf/Confirm support for data export operations
    - Automatic session cleanup in finally blocks
    - Validates CSV export path before writing

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all health check operations
    - Follows principle of least privilege
    - Implements defense-in-depth security controls
    - Read-only operations to minimize infrastructure impact

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

#==============================================
# Global Audit Logging Function
#==============================================
function Write-AuditLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO',
        [string]$LogFile,
        [string]$VCenter,
        [string]$VMName
    )

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

    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $auditMessage -ErrorAction Stop }
        catch { Write-Warning "Failed to write to log file: $_" }
    }

    try {
        $eventSource = 'VMware-PowerCLI-Security'
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
            New-EventLog -LogName Application -Source $eventSource -ErrorAction SilentlyContinue
        }
        $eventType = switch ($Level) {
            'ERROR'    { 'Error' }
            'WARNING'  { 'Warning' }
            'SECURITY' { 'SuccessAudit' }
            default    { 'Information' }
        }
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1002 -Message $auditMessage -ErrorAction SilentlyContinue
    }
    catch { }
}

#==============================================
# Input Validation Functions
#==============================================
function Test-ValidServerName {
    param([string]$Name)
    if ($Name -match '[;&|`$<>]') { throw "Invalid characters detected in server name: $Name" }
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Server name cannot be empty or whitespace." }
    return $true
}

function Test-ValidFilePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "File path cannot be empty or whitespace." }
    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) { throw "Directory does not exist: $directory" }
    if ($Path -notmatch '\.csv$') { throw "File must have .csv extension" }
    return $true
}

#==============================================
# Main Script Execution
#==============================================

$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}
$logFile = Join-Path $logDirectory "HealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-AuditLog -Message "Health check script execution started" -Level SECURITY -LogFile $logFile

$viConnection = $null
$credential = $null

try {
    #==============================================
    # 1. Ensure VMware.PowerCLI is Installed and Imported
    #==============================================
    Write-AuditLog -Message "Checking for VMware.PowerCLI module..." -LogFile $logFile

    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-AuditLog -Message "PowerCLI module not found. Installing..." -Level WARNING -LogFile $logFile
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
        Write-AuditLog -Message "VMware.PowerCLI installed successfully" -LogFile $logFile
    }
    else {
        Write-AuditLog -Message "VMware.PowerCLI module already installed" -LogFile $logFile
    }

    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-AuditLog -Message "VMware.PowerCLI module imported successfully" -LogFile $logFile

    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null

    Write-AuditLog -Message "PowerCLI security configuration applied" -Level SECURITY -LogFile $logFile

    #==============================================
    # 2. Connect to vCenter Server or ESXi Host
    #==============================================
    $server = Read-Host "Enter vCenter Server or ESXi host"
    Test-ValidServerName -Name $server

    $user = Read-Host "Enter username"
    $securePassword = Read-Host "Enter password" -AsSecureString
    $credential = New-Object System.Management.Automation.PSCredential($user, $securePassword)

    Write-AuditLog -Message "Attempting secure connection to $server" -VCenter $server -LogFile $logFile

    $viConnection = Connect-VIServer -Server $server -Credential $credential -ErrorAction Stop
    Write-AuditLog -Message "Successfully connected to $server" -Level SECURITY -VCenter $server -LogFile $logFile

    #==============================================
    # 3. Define the Output CSV Path for Health Check Results
    #==============================================
    $csvFilePath = Read-Host "Enter the path for exporting health check results (e.g., C:\HealthCheckResults.csv)"
    if ([string]::IsNullOrWhiteSpace($csvFilePath)) {
        Write-AuditLog -Message "No CSV file path provided. Exiting." -Level ERROR -VCenter $server -LogFile $logFile
        throw "CSV file path is required"
    }
    Test-ValidFilePath -Path $csvFilePath
    Write-AuditLog -Message "Export path validated: $csvFilePath" -Level SECURITY -VCenter $server -LogFile $logFile

    #==============================================
    # 4. Collect Health Check Data
    #==============================================
    $Summary = @{}
    $healthCheckResults = @()

    if ($PSCmdlet.ShouldProcess($server, "Perform health check")) {
        # Check host status
        Write-AuditLog -Message "Checking host status..." -VCenter $server -LogFile $logFile
        try {
            $hostStatus = Get-VMHost | Select-Object Name, ConnectionState, PowerState
            $healthCheckResults += $hostStatus
            Write-AuditLog -Message "Host status data collected ($($hostStatus.Count) hosts)" -VCenter $server -LogFile $logFile
            $Summary['Host Status'] = $true
        }
        catch {
            Write-AuditLog -Message "Error retrieving host status: $_" -Level ERROR -VCenter $server -LogFile $logFile
            $Summary['Host Status'] = $false
        }

        # Check datastore usage
        Write-AuditLog -Message "Checking datastore usage..." -VCenter $server -LogFile $logFile
        try {
            $datastoreUsage = Get-Datastore | Select-Object Name, CapacityGB, FreeSpaceGB,
            @{N = 'UsedSpaceGB'; E = { [math]::Round($_.CapacityGB - $_.FreeSpaceGB, 2) } }
            $healthCheckResults += $datastoreUsage
            Write-AuditLog -Message "Datastore usage data collected ($($datastoreUsage.Count) datastores)" -VCenter $server -LogFile $logFile
            $Summary['Datastore Usage'] = $true
        }
        catch {
            Write-AuditLog -Message "Error retrieving datastore usage: $_" -Level ERROR -VCenter $server -LogFile $logFile
            $Summary['Datastore Usage'] = $false
        }

        # Check VM configurations
        Write-AuditLog -Message "Checking VM configurations..." -VCenter $server -LogFile $logFile
        try {
            $vmConfigs = Get-VM | Select-Object Name, PowerState, NumCpu, MemoryGB,
            @{N = 'HardDisks'; E = { ($_ | Get-HardDisk).Count } },
            @{N = 'NetworkAdapters'; E = { ($_ | Get-NetworkAdapter).Count } }
            $healthCheckResults += $vmConfigs
            Write-AuditLog -Message "VM configuration data collected ($($vmConfigs.Count) VMs)" -VCenter $server -LogFile $logFile
            $Summary['VM Configurations'] = $true
        }
        catch {
            Write-AuditLog -Message "Error retrieving VM configurations: $_" -Level ERROR -VCenter $server -LogFile $logFile
            $Summary['VM Configurations'] = $false
        }

        # Check for snapshots
        Write-AuditLog -Message "Checking for snapshots..." -VCenter $server -LogFile $logFile
        try {
            $snapshots = Get-VM | Get-Snapshot | Select-Object VM, Name, Created, SizeGB
            if ($snapshots) {
                $healthCheckResults += $snapshots
                Write-AuditLog -Message "Snapshot data collected ($($snapshots.Count) snapshots found)" -Level WARNING -VCenter $server -LogFile $logFile
            }
            else {
                Write-AuditLog -Message "No snapshots found" -VCenter $server -LogFile $logFile
            }
            $Summary['Snapshots'] = $true
        }
        catch {
            Write-AuditLog -Message "Error retrieving snapshots: $_" -Level ERROR -VCenter $server -LogFile $logFile
            $Summary['Snapshots'] = $false
        }

        # Check for orphaned VMs
        Write-AuditLog -Message "Checking for orphaned VMs..." -VCenter $server -LogFile $logFile
        try {
            $orphanedVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object {
                $_.ExtensionData.Runtime.ConnectionState -eq 'inaccessible'
            }
            if ($orphanedVMs) {
                $healthCheckResults += $orphanedVMs | Select-Object Name, PowerState
                Write-AuditLog -Message "Orphaned VM data collected ($($orphanedVMs.Count) orphaned VMs found)" -Level WARNING -VCenter $server -LogFile $logFile
            }
            else {
                Write-AuditLog -Message "No orphaned VMs found" -VCenter $server -LogFile $logFile
            }
            $Summary['Orphaned VMs'] = $true
        }
        catch {
            Write-AuditLog -Message "Error retrieving orphaned VMs: $_" -Level ERROR -VCenter $server -LogFile $logFile
            $Summary['Orphaned VMs'] = $false
        }
    }

    #==============================================
    # 5. Export Health Check Results to CSV
    #==============================================
    if ($PSCmdlet.ShouldProcess($csvFilePath, "Export health check results")) {
        Write-AuditLog -Message "Exporting health check results to CSV file: $csvFilePath..." -VCenter $server -LogFile $logFile
        try {
            $healthCheckResults | Export-Csv -Path $csvFilePath -NoTypeInformation -ErrorAction Stop
            Write-AuditLog -Message "Health check results successfully exported to $csvFilePath ($($healthCheckResults.Count) records)" -Level SECURITY -VCenter $server -LogFile $logFile
            $Summary['Export to CSV'] = $true
        }
        catch {
            Write-AuditLog -Message "Error exporting health check results: $_" -Level ERROR -VCenter $server -LogFile $logFile
            $Summary['Export to CSV'] = $false
            throw
        }
    }
}
catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -VCenter $server -LogFile $logFile
    throw
}
finally {
    #==============================================
    # 6. Disconnect from vCenter Server or ESXi Host
    #==============================================
    if ($viConnection) {
        try {
            Write-AuditLog -Message "Disconnecting from $server" -VCenter $server -LogFile $logFile
            Disconnect-VIServer -Server $server -Confirm:$false -ErrorAction SilentlyContinue
            Write-AuditLog -Message "Disconnected from $server" -Level SECURITY -VCenter $server -LogFile $logFile
        }
        catch {
            Write-AuditLog -Message "Error during disconnect: $_" -Level WARNING -LogFile $logFile
        }
    }

    if ($credential) { $credential = $null }
    if ($securePassword) { $securePassword = $null }

    Write-Host "`nSummary:" -ForegroundColor Cyan
    foreach ($step in $Summary.Keys) {
        $status = if ($Summary[$step]) { 'Success' } else { 'Failed' }
        Write-Host "$step: $status"
    }
    if ($csvFilePath) { Write-Host "Export file: $csvFilePath" }
    Write-Host "Audit log saved to: $logFile"

    Write-AuditLog -Message "Health check process completed" -Level SECURITY -LogFile $logFile
}
