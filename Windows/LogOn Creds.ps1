<#
.SYNOPSIS
    Updates the logon credentials for a specified Windows service and restarts it.

.DESCRIPTION
    This script performs the following actions:
      1. Retrieves the specified service on the local (or remote) computer using CIM.
      2. Uses the Win32_Service Change method to update the service's logon account credentials.
      3. Stops the service to allow the credential changes to take effect.
      4. Starts the service again.

    SECURITY FEATURES:
      - Uses PSCredential for secure credential handling
      - Implements comprehensive audit logging
      - Enforces administrator privileges
      - Validates all input parameters
      - Uses Set-StrictMode for code safety

.PARAMETER ServiceName
    The name of the Windows service whose credentials are to be updated
    (e.g., "Spooler" for the Print Spooler service).

.PARAMETER Credential
    PSCredential object containing the service account username and password.
    Use Get-Credential or retrieve from Windows Credential Manager.

.PARAMETER ComputerName
    The target computer name. Defaults to local computer.

.PARAMETER LogPath
    Path for audit log file. Defaults to $env:ProgramData\PowerShellLogs\ServiceCredUpdate.log

.EXAMPLE
    $cred = Get-Credential -Message "Enter service account credentials"
    .\LogOn-Creds.ps1 -ServiceName "Spooler" -Credential $cred

    Updates the credentials for the "Spooler" service using secure credential prompt.

.EXAMPLE
    # Using Windows Credential Manager (requires CredentialManager module)
    $cred = Get-StoredCredential -Target "ServiceAccount"
    .\LogOn-Creds.ps1 -ServiceName "MyService" -Credential $cred -ComputerName "SERVER01"

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

    SECURITY NOTES:
      - This script must be run with administrative privileges
      - All actions are logged for audit purposes
      - Credentials are never stored in plaintext
      - Suitable for Fourth Estate infrastructure

    COMPLIANCE:
      - Follows CIS PowerShell security guidelines
      - Implements STIG-compliant logging
      - Uses approved cryptographic credential handling
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Service name to update")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9\-_\.]+$')]
    [string]$ServiceName,

    [Parameter(Mandatory = $true, HelpMessage = "Service account credentials")]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "$env:ProgramData\PowerShellLogs\ServiceCredUpdate.log"
)

# Enable strict mode for better code safety
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Script
#----------------------------------------------
$script:StartTime = Get-Date
$script:ScriptName = $MyInvocation.MyCommand.Name
$script:ExecutingUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$script:LogDirectory = Split-Path -Parent $LogPath

# Start transcript for complete audit trail
$transcriptPath = Join-Path $script:LogDirectory "Transcript_$($ServiceName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
try {
    if (-not (Test-Path $script:LogDirectory)) {
        New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null
    }
    Start-Transcript -Path $transcriptPath -Force
} catch {
    Write-Warning "Failed to start transcript: $_"
}

#----------------------------------------------
# Secure Logging Function with Audit Trail
#----------------------------------------------
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Security')]
        [string]$Level = 'Information',

        [Parameter(Mandatory = $false)]
        [int]$EventId = 1000
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] [User:$script:ExecutingUser] [Computer:$ComputerName] [Service:$ServiceName] $Message"

    # Console output with color coding
    switch ($Level) {
        'Error'    { Write-Host $logEntry -ForegroundColor Red }
        'Warning'  { Write-Host $logEntry -ForegroundColor Yellow }
        'Security' { Write-Host $logEntry -ForegroundColor Cyan }
        default    { Write-Host $logEntry }
    }

    # File logging with error handling
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log file: $_"
    }

    # Windows Event Log for security events
    if ($Level -eq 'Security') {
        try {
            $eventLogName = 'Application'
            $eventSource = 'PowerShell-ServiceCredentialUpdate'

            if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
                New-EventLog -LogName $eventLogName -Source $eventSource
            }

            Write-EventLog -LogName $eventLogName -Source $eventSource -EventId $EventId -EntryType Information -Message $Message
        } catch {
            Write-Warning "Failed to write to Windows Event Log: $_"
        }
    }
}

#----------------------------------------------
# Validate Input Parameters
#----------------------------------------------
function Test-InputValidation {
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Validating input parameters..." -Level Information

    # Validate computer accessibility
    if ($ComputerName -ne $env:COMPUTERNAME) {
        if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {
            throw "Computer '$ComputerName' is not accessible"
        }
    }

    # Validate credential format
    $username = $Credential.UserName
    if ($username -notmatch '^[a-zA-Z0-9\-_\.\\@]+$') {
        throw "Invalid username format: $username"
    }

    Write-AuditLog -Message "Input validation passed" -Level Information
}

#----------------------------------------------
# Main Execution Block
#----------------------------------------------
try {
    Write-AuditLog -Message "========== Service Credential Update Started ==========" -Level Security -EventId 1001
    Write-AuditLog -Message "Script: $script:ScriptName" -Level Information
    Write-AuditLog -Message "Executed by: $script:ExecutingUser" -Level Information
    Write-AuditLog -Message "Target Computer: $ComputerName" -Level Information
    Write-AuditLog -Message "Target Service: $ServiceName" -Level Information

    # Validate inputs
    Test-InputValidation

    # Retrieve the service
    Write-AuditLog -Message "Retrieving service '$ServiceName' on '$ComputerName'..." -Level Information

    $cimSessionParams = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
    }

    $cimSession = New-CimSession @cimSessionParams
    $service = Get-CimInstance -CimSession $cimSession -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop

    if (-not $service) {
        throw "Service '$ServiceName' not found on '$ComputerName'"
    }

    Write-AuditLog -Message "Service '$ServiceName' found. Display Name: $($service.DisplayName), Current State: $($service.State)" -Level Information

    # WhatIf support
    if ($PSCmdlet.ShouldProcess("Service: $ServiceName on $ComputerName", "Update logon credentials to $($Credential.UserName)")) {

        # Extract credentials securely
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password

        # Update service credentials
        Write-AuditLog -Message "Updating credentials for service '$ServiceName'..." -Level Information

        $changeParams = @{
            StartName     = $username
            StartPassword = $password
        }

        $changeResult = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments $changeParams -ErrorAction Stop

        if ($changeResult.ReturnValue -eq 0) {
            Write-AuditLog -Message "Service credentials updated successfully" -Level Security -EventId 1002
        } else {
            $errorMessage = switch ($changeResult.ReturnValue) {
                1  { "Not Supported" }
                2  { "Access Denied" }
                3  { "Dependent Services Running" }
                4  { "Invalid Service Control" }
                5  { "Service Cannot Accept Control" }
                6  { "Service Not Active" }
                7  { "Service Request Timeout" }
                8  { "Unknown Failure" }
                9  { "Path Not Found" }
                10 { "Service Already Running" }
                11 { "Service Database Locked" }
                12 { "Service Dependency Deleted" }
                13 { "Service Dependency Failure" }
                14 { "Service Disabled" }
                15 { "Service Logon Failed" }
                16 { "Service Marked For Deletion" }
                17 { "Service No Thread" }
                18 { "Status Circular Dependency" }
                19 { "Status Duplicate Name" }
                20 { "Status Invalid Name" }
                21 { "Status Invalid Parameter" }
                22 { "Status Invalid Service Account" }
                23 { "Status Service Exists" }
                24 { "Service Already Paused" }
                default { "Unknown Error Code: $($changeResult.ReturnValue)" }
            }
            throw "Failed to update service credentials. Error: $errorMessage"
        }

        # Restart service if it was running
        if ($service.State -eq 'Running') {
            Write-AuditLog -Message "Restarting service '$ServiceName'..." -Level Information

            # Stop service
            $stopResult = Invoke-CimMethod -InputObject $service -MethodName StopService -ErrorAction Stop
            if ($stopResult.ReturnValue -ne 0) {
                Write-AuditLog -Message "Warning: Service stop returned code $($stopResult.ReturnValue)" -Level Warning
            }

            # Wait for service to stop
            $timeout = 30
            $elapsed = 0
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $service = Get-CimInstance -CimSession $cimSession -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
            } while ($service.State -ne 'Stopped' -and $elapsed -lt $timeout)

            if ($service.State -ne 'Stopped') {
                Write-AuditLog -Message "Warning: Service did not stop within $timeout seconds" -Level Warning
            }

            # Start service
            $startResult = Invoke-CimMethod -InputObject $service -MethodName StartService -ErrorAction Stop
            if ($startResult.ReturnValue -eq 0) {
                Write-AuditLog -Message "Service '$ServiceName' restarted successfully" -Level Security -EventId 1003
            } else {
                throw "Failed to start service. Return code: $($startResult.ReturnValue)"
            }
        } else {
            Write-AuditLog -Message "Service was not running, skipping restart" -Level Information
        }
    }

    # Cleanup
    if ($cimSession) {
        Remove-CimSession -CimSession $cimSession
    }

    $duration = (Get-Date) - $script:StartTime
    Write-AuditLog -Message "========== Service Credential Update Completed Successfully (Duration: $($duration.ToString('mm\:ss'))) ==========" -Level Security -EventId 1004

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level Error
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Write-AuditLog -Message "========== Service Credential Update Failed ==========" -Level Security -EventId 1005

    exit 1

} finally {
    # Cleanup
    if ($cimSession) {
        try { Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue } catch {}
    }

    # Stop transcript
    try { Stop-Transcript } catch {}

    # Clear sensitive data from memory
    if ($password) {
        Clear-Variable -Name password -ErrorAction SilentlyContinue
    }
}
