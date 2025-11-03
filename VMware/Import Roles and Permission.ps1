<#
.SYNOPSIS
    Imports roles and permissions from a CSV file and applies them to a vCenter Server or ESXi host.

.DESCRIPTION
    This script performs the following tasks:
      1. Checks if the VMware.PowerCLI module is installed; if not, installs it.
      2. Imports the PowerCLI module.
      3. Prompts for vCenter/ESXi host connection details (server, username, and password) and connects to the host.
      4. Prompts for the path to a CSV file which contains roles and permissions information.
      5. Validates that the CSV file exists and then reads its contents.
      6. Iterates through each CSV entry and applies the specified permission using New-VIPermission.
      7. Disconnects from the vCenter/ESXi host.

.PARAMETER None
    This script is interactive and prompts for all required inputs.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for file paths and server names
    - WhatIf/Confirm support for permission changes
    - Automatic session cleanup in finally blocks
    - Validates role and entity existence before applying permissions

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all permission modifications
    - Follows principle of least privilege
    - Implements defense-in-depth security controls
    - Validates all inputs before applying changes

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module.
      - Valid credentials and permissions to access and modify permissions on the vCenter/ESXi host.
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
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1003 -Message $auditMessage -ErrorAction SilentlyContinue
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
    if (-not (Test-Path -Path $Path)) { throw "File does not exist: $Path" }
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
$logFile = Join-Path $logDirectory "Import_Roles_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-AuditLog -Message "Script execution started" -Level SECURITY -LogFile $logFile

$viConnection = $null
$credential = $null

try {
    #==============================================
    # 1. Ensure VMware.PowerCLI Module is Installed and Imported
    #==============================================
    Write-AuditLog -Message "Checking for VMware.PowerCLI module..." -LogFile $logFile

    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-AuditLog -Message "VMware.PowerCLI module not found. Installing..." -Level WARNING -LogFile $logFile
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
        Write-AuditLog -Message "VMware.PowerCLI module installed successfully" -LogFile $logFile
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
    # 3. Specify and Validate the CSV File Path
    #==============================================
    $csvFilePath = Read-Host "Enter the path to the CSV file (e.g., C:\Path\To\Import\Roles_Permissions.csv)"
    Test-ValidFilePath -Path $csvFilePath

    Write-AuditLog -Message "CSV file path validated: $csvFilePath" -Level SECURITY -VCenter $server -LogFile $logFile

    #==============================================
    # 4. Read Roles and Permissions from the CSV File
    #==============================================
    Write-AuditLog -Message "Reading CSV file from $csvFilePath..." -VCenter $server -LogFile $logFile
    $rolesPermissions = Import-Csv -Path $csvFilePath -ErrorAction Stop
    Write-AuditLog -Message "CSV file loaded successfully ($($rolesPermissions.Count) entries)" -VCenter $server -LogFile $logFile

    #==============================================
    # 5. Iterate Through Each CSV Entry and Apply Permissions
    #==============================================
    Write-AuditLog -Message "Applying roles and permissions from CSV..." -VCenter $server -LogFile $logFile

    $Summary = @{}
    $successCount = 0
    $failCount = 0

    foreach ($entry in $rolesPermissions) {
        $success = $true
        $principal = $entry.Principal

        try {
            # Validate role exists
            $role = Get-VIRole -Name $entry.RoleName -ErrorAction Stop
            Write-AuditLog -Message "Role '$($entry.RoleName)' validated" -VCenter $server -LogFile $logFile

            # Validate entity exists
            $entity = Get-View -Id $entry.Entity -ErrorAction Stop
            Write-AuditLog -Message "Entity '$($entry.Entity)' validated" -VCenter $server -LogFile $logFile

            if ($PSCmdlet.ShouldProcess("$principal on $($entry.Entity)", "Apply permission with role $($entry.RoleName)")) {
                New-VIPermission -Role $role -Principal $principal -Entity $entity -Propagate $entry.Propagate -ErrorAction Stop | Out-Null
                Write-AuditLog -Message "Permission for '$principal' applied on '$($entry.Entity)' with role '$($entry.RoleName)'" -Level SECURITY -VCenter $server -VMName $principal -LogFile $logFile
                $successCount++
            }
        }
        catch {
            Write-AuditLog -Message "Error applying permission for '$principal' on '$($entry.Entity)': $_" -Level ERROR -VCenter $server -VMName $principal -LogFile $logFile
            $success = $false
            $failCount++
        }

        $Summary[$principal] = $success
    }

    Write-AuditLog -Message "Roles and permissions imported: $successCount succeeded, $failCount failed" -Level SECURITY -VCenter $server -LogFile $logFile
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
    Write-Host "Total permissions applied: $successCount"
    Write-Host "Total failures: $failCount"
    if ($csvFilePath) { Write-Host "Import file: $csvFilePath" }
    Write-Host "Audit log saved to: $logFile"

    Write-AuditLog -Message "Script execution completed" -Level SECURITY -LogFile $logFile
}
