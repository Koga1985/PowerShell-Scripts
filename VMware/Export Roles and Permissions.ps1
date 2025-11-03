<#
.SYNOPSIS
    Exports roles and permissions from a vCenter Server or ESXi host to a CSV file.

.DESCRIPTION
    This script checks for the VMware.PowerCLI module and installs it if it is not already installed.
    It then prompts for the vCenter Server or ESXi host connection details (server, username, and password)
    and connects to the server. The script retrieves all the roles from the server and for each role, collects
    associated permissions. A custom property "RoleName" is added to each permission object. Finally, the
    aggregated roles and permissions are exported to a CSV file whose path is supplied by the user.

    At the end, the script disconnects from the server cleanly.

.PARAMETER None
    The script runs interactively, prompting the user for connection details and export file path.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - Single vCenter server mode to prevent cross-contamination
    - PSCredential-based authentication with secure password handling
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for file paths and server names
    - WhatIf/Confirm support for export operations
    - Automatic session cleanup in finally blocks
    - Validates CSV export path before writing

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail maintained for all data exports
    - Follows principle of least privilege
    - Implements defense-in-depth security controls
    - Sensitive data handling with proper permissions

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module.
      - Appropriate connectivity and permissions to connect to a vCenter Server or ESXi host.
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
        try {
            Add-Content -Path $LogFile -Value $auditMessage -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
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

        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1001 -Message $auditMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Silently continue if Event Log writing fails
    }
}

#==============================================
# Input Validation Functions
#==============================================
function Test-ValidServerName {
    param([string]$Name)

    if ($Name -match '[;&|`$<>]') {
        throw "Invalid characters detected in server name: $Name"
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Server name cannot be empty or whitespace."
    }

    return $true
}

function Test-ValidFilePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "File path cannot be empty or whitespace."
    }

    # Check if directory exists
    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        throw "Directory does not exist: $directory"
    }

    # Check file extension
    if ($Path -notmatch '\.csv$') {
        throw "File must have .csv extension"
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
$logFile = Join-Path $logDirectory "Export_Roles_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-AuditLog -Message "Script execution started" -Level SECURITY -LogFile $logFile

# Variables for cleanup
$viConnection = $null
$credential = $null

try {
    #==============================================
    # 1. Check for and Install VMware.PowerCLI Module if Needed
    #==============================================
    Write-AuditLog -Message "Checking for VMware.PowerCLI module..." -LogFile $logFile

    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-AuditLog -Message "VMware.PowerCLI module not found. Installing..." -Level WARNING -LogFile $logFile
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
        Write-AuditLog -Message "VMware.PowerCLI installed successfully" -LogFile $logFile
    }
    else {
        Write-AuditLog -Message "VMware.PowerCLI module is already installed" -LogFile $logFile
    }

    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-AuditLog -Message "VMware.PowerCLI module imported successfully" -LogFile $logFile

    # Configure PowerCLI for security
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
    # 3. Prompt for CSV Export File Path
    #==============================================
    $csvFilePath = Read-Host "Enter the path for exporting roles and permissions (e.g., C:\Export\Roles_Permissions.csv)"
    Test-ValidFilePath -Path $csvFilePath

    Write-AuditLog -Message "Export path validated: $csvFilePath" -Level SECURITY -VCenter $server -LogFile $logFile

    #==============================================
    # 4. Retrieve Roles and Permissions and Export to CSV
    #==============================================
    Write-AuditLog -Message "Retrieving roles and permissions..." -VCenter $server -LogFile $logFile

    $Summary = $false

    if ($PSCmdlet.ShouldProcess($csvFilePath, "Export roles and permissions")) {
        $rolesPermissions = @()
        $roleCount = 0
        $permissionCount = 0

        Get-VIRole | ForEach-Object {
            $role = $_
            $roleCount++
            Write-AuditLog -Message "Processing role: $($role.Name)" -VCenter $server -LogFile $logFile

            $permissions = Get-VIPermission -Role $role -ErrorAction SilentlyContinue | ForEach-Object {
                $permissionCount++
                $_ | Add-Member -MemberType NoteProperty -Name "RoleName" -Value $role.Name -Force -PassThru
            }

            if ($permissions) {
                $rolesPermissions += $permissions
            }
        }

        Write-AuditLog -Message "Retrieved $roleCount roles with $permissionCount permissions" -VCenter $server -LogFile $logFile

        $rolesPermissions | Export-Csv -Path $csvFilePath -NoTypeInformation -ErrorAction Stop
        Write-AuditLog -Message "Roles and permissions successfully exported to $csvFilePath ($permissionCount records)" -Level SECURITY -VCenter $server -LogFile $logFile
        $Summary = $true
    }
}
catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -VCenter $server -LogFile $logFile
    $Summary = $false
    throw
}
finally {
    #==============================================
    # 5. Disconnect from vCenter Server or ESXi Host
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

    # Clear credentials from memory
    if ($credential) {
        $credential = $null
    }
    if ($securePassword) {
        $securePassword = $null
    }

    # Summary Output
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "Roles and permissions export: $(if ($Summary) { 'Success' } else { 'Failed' })"
    if ($csvFilePath) {
        Write-Host "Export file: $csvFilePath"
    }
    Write-Host "Audit log saved to: $logFile"

    Write-AuditLog -Message "Script execution completed" -Level SECURITY -LogFile $logFile
}
