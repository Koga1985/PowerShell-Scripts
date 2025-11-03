<#
.SYNOPSIS
    Adds specified VLANs to a Virtual Switch on a vCenter Server or ESXi host using VMware PowerCLI.

.DESCRIPTION
    This script ensures the VMware PowerCLI module is installed and imported, then prompts the user for connection details
    (vCenter Server/ESXi host, credentials) and the target vSwitch name along with VLAN IDs to be added.
    For each VLAN ID provided, the script checks if a Virtual Port Group exists on the vSwitch.
    If not, a new port group is created with the specified VLAN ID.
    The script logs progress and errors, and disconnects from the host when complete.

.PARAMETER (None)
    The script is interactive. Users will be prompted for necessary details.

.PREREQUISITES
    - Administrative privileges.
    - Network connectivity to the vCenter Server or ESXi host.
    - Sufficient permissions to create port groups and modify networking settings.
    - VMware PowerCLI module access.
    - PowerShell 5.1 or higher.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for VLAN IDs and network names
    - WhatIf/Confirm support for destructive operations
    - Automatic session cleanup in finally blocks

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all infrastructure changes
    - Follows principle of least privilege
    - Implements defense-in-depth security controls

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
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
    <#
    .SYNOPSIS
        Writes audit messages to file and Windows Event Log for compliance tracking.

    .PARAMETER Message
        The audit log message.

    .PARAMETER Level
        The severity level (INFO, WARNING, ERROR, SECURITY). Default is INFO.

    .PARAMETER LogFile
        Optional file path to append the log message.

    .PARAMETER VCenter
        vCenter Server name for audit trail.

    .PARAMETER VMName
        Virtual machine or resource name for audit trail.
    #>
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

    # Output to console
    switch ($Level) {
        'ERROR'    { Write-Host $auditMessage -ForegroundColor Red }
        'WARNING'  { Write-Host $auditMessage -ForegroundColor Yellow }
        'SECURITY' { Write-Host $auditMessage -ForegroundColor Cyan }
        default    { Write-Host $auditMessage }
    }

    # Append to file if provided
    if ($LogFile) {
        try {
            Add-Content -Path $LogFile -Value $auditMessage -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }

    # Write to Windows Event Log
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

        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1000 -Message $auditMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Silently continue if Event Log writing fails
    }
}

#==============================================
# Input Validation Functions
#==============================================
function Test-ValidVLANID {
    param([int]$VLANID)

    if ($VLANID -lt 1 -or $VLANID -gt 4094) {
        throw "Invalid VLAN ID: $VLANID. Valid range is 1-4094."
    }
    return $true
}

function Test-ValidNetworkName {
    param([string]$Name)

    # Check for dangerous characters
    if ($Name -match '[;&|`$<>]') {
        throw "Invalid characters detected in network name: $Name"
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Network name cannot be empty or whitespace."
    }

    return $true
}

#==============================================
# Main Script Execution
#==============================================

# Initialize audit log file
$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}
$logFile = Join-Path $logDirectory "vSwitch_VLAN_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-AuditLog -Message "Script execution started" -Level SECURITY -LogFile $logFile

# Variables for cleanup
$viConnection = $null
$credential = $null

try {
    # 1. Ensure VMware.PowerCLI Module is Installed and Imported
    #==============================================
    Write-AuditLog -Message "Checking for VMware.PowerCLI module..." -LogFile $logFile

    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-AuditLog -Message "VMware.PowerCLI module not found. Installing..." -Level WARNING -LogFile $logFile
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
    }

    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-AuditLog -Message "VMware.PowerCLI module imported successfully" -LogFile $logFile

    # Configure PowerCLI for security
    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null

    Write-AuditLog -Message "PowerCLI security configuration applied: Certificate validation enabled, Single server mode" -Level SECURITY -LogFile $logFile

    #==============================================
    # 2. Prompt for Connection Details and Connect
    #==============================================
    $server = Read-Host "Enter vCenter Server or ESXi host"
    Test-ValidNetworkName -Name $server

    $user = Read-Host "Enter username"
    $securePassword = Read-Host "Enter password" -AsSecureString

    # Create PSCredential object
    $credential = New-Object System.Management.Automation.PSCredential($user, $securePassword)

    Write-AuditLog -Message "Attempting secure connection to $server" -VCenter $server -LogFile $logFile

    $viConnection = Connect-VIServer -Server $server -Credential $credential -ErrorAction Stop
    Write-AuditLog -Message "Successfully connected to $server" -Level SECURITY -VCenter $server -LogFile $logFile

    #==============================================
    # 3. Prompt for vSwitch Name and VLAN IDs
    #==============================================
    $vSwitchName = Read-Host "Enter the vSwitch name (e.g., vSwitch0)"
    Test-ValidNetworkName -Name $vSwitchName

    $vlanInput = Read-Host "Enter the VLAN IDs to add (comma-separated, e.g., 100,200,300)"
    $vlanIDs = $vlanInput -split ',' | ForEach-Object {
        $trimmed = $_.Trim()
        try {
            $vlanID = [int]$trimmed
            Test-ValidVLANID -VLANID $vlanID
            $vlanID
        }
        catch {
            Write-AuditLog -Message "Invalid VLAN ID '$trimmed': $_" -Level ERROR -LogFile $logFile
            throw
        }
    }

    Write-AuditLog -Message "Validated VLAN IDs: $($vlanIDs -join ', ')" -Level SECURITY -LogFile $logFile

    #==============================================
    # 4. Retrieve the vSwitch and Add VLANs
    #==============================================
    Write-AuditLog -Message "Retrieving vSwitch: $vSwitchName" -VCenter $server -VMName $vSwitchName -LogFile $logFile
    $vSwitch = Get-VirtualSwitch -Name $vSwitchName -ErrorAction Stop
    Write-AuditLog -Message "Found vSwitch: $vSwitchName" -VCenter $server -VMName $vSwitchName -LogFile $logFile

    # Summary variable
    $Summary = @{}

    foreach ($vlanID in $vlanIDs) {
        $success = $true
        Write-AuditLog -Message "Processing VLAN ID: $vlanID" -VCenter $server -VMName $vSwitchName -LogFile $logFile

        try {
            $portGroups = Get-VirtualPortGroup -VirtualSwitch $vSwitch
            if ($portGroups | Where-Object { $_.VlanId -eq $vlanID }) {
                Write-AuditLog -Message "VLAN $vlanID already exists on $vSwitchName. Skipping..." -VCenter $server -VMName $vSwitchName -LogFile $logFile
            }
            else {
                $pgName = "VLAN-$vlanID"

                # Use ShouldProcess for WhatIf/Confirm support
                if ($PSCmdlet.ShouldProcess("$vSwitchName", "Create port group '$pgName' with VLAN $vlanID")) {
                    Write-AuditLog -Message "Creating port group '$pgName' on $vSwitchName with VLAN $vlanID" -Level SECURITY -VCenter $server -VMName $vSwitchName -LogFile $logFile

                    New-VirtualPortGroup -Name $pgName -VirtualSwitch $vSwitch -VlanId $vlanID -ErrorAction Stop | Out-Null

                    Write-AuditLog -Message "VLAN $vlanID added to $vSwitchName as port group '$pgName'" -Level SECURITY -VCenter $server -VMName $vSwitchName -LogFile $logFile
                }
            }
        }
        catch {
            Write-AuditLog -Message "Failed to add VLAN $vlanID to $vSwitchName. Error: $_" -Level ERROR -VCenter $server -VMName $vSwitchName -LogFile $logFile
            $success = $false
        }

        $Summary[$vlanID] = $success
    }

    #==============================================
    # Summary Output
    #==============================================
    Write-Host "`nSummary:" -ForegroundColor Cyan
    foreach ($vlanID in $Summary.Keys) {
        $status = if ($Summary[$vlanID]) { 'Success' } else { 'Failed' }
        Write-Host "VLAN $vlanID: $status"
    }

    Write-AuditLog -Message "Script execution completed successfully" -Level SECURITY -VCenter $server -LogFile $logFile
}
catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -VCenter $server -LogFile $logFile
    throw
}
finally {
    # Cleanup: Disconnect from vCenter and clear credentials
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

    # Clear credentials from memory
    if ($credential) {
        $credential = $null
    }
    if ($securePassword) {
        $securePassword = $null
    }

    Write-Host "`nAudit log saved to: $logFile" -ForegroundColor Cyan
}
