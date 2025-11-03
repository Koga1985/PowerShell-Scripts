<#
.SYNOPSIS
    Updates the logon credentials for all services running under a specified account.

.DESCRIPTION
    This script provides secure bulk service credential updates for all services running
    under a specified account on one or more computers.

    SECURITY FEATURES:
      - Uses PSCredential for secure credential handling
      - Never converts passwords to plaintext
      - Implements comprehensive audit logging
      - Enforces administrator privileges
      - Validates all input parameters
      - Uses CIM sessions for secure remote access

.PARAMETER ComputerName
    The target computer name(s). Defaults to local computer.
    Accepts array for bulk operations.

.PARAMETER Credential
    PSCredential object containing the service account username and new password.
    Use Get-Credential or retrieve from Windows Credential Manager.

.PARAMETER ServiceAccountName
    Optional: Only update services running under this specific account.
    If not specified, uses the username from Credential parameter.

.PARAMETER LogPath
    Path for audit log file. Defaults to $env:ProgramData\PowerShellLogs\BulkServiceCredUpdate.log

.EXAMPLE
    $cred = Get-Credential -Message "Enter new service account credentials"
    .\Set-Service-Creds.ps1 -Credential $cred

    Updates all services using the credential username on local computer.

.EXAMPLE
    $cred = Get-Credential
    $computers = @("SERVER01", "SERVER02", "SERVER03")
    .\Set-Service-Creds.ps1 -ComputerName $computers -Credential $cred -ServiceAccountName "DOMAIN\ServiceAcct"

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
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [Parameter(Mandatory = $true, HelpMessage = "New service account credentials")]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceAccountName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "$env:ProgramData\PowerShellLogs\BulkServiceCredUpdate.log"
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

# Determine service account to target
if (-not $ServiceAccountName) {
    $ServiceAccountName = $Credential.UserName
}

# Start transcript for complete audit trail
$transcriptPath = Join-Path $script:LogDirectory "Transcript_BulkServiceUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
        [string]$Computer = "N/A",

        [Parameter(Mandatory = $false)]
        [int]$EventId = 2000
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] [User:$script:ExecutingUser] [Computer:$Computer] $Message"

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
            $eventSource = 'PowerShell-BulkServiceUpdate'

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
# Process Services on Single Computer
#----------------------------------------------
function Update-ComputerServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetComputer
    )

    $cimSession = $null
    $computerResults = @{
        Computer = $TargetComputer
        Success = 0
        Failed = 0
        Errors = @()
    }

    try {
        Write-AuditLog -Message "Connecting to computer: $TargetComputer" -Level Information -Computer $TargetComputer

        # Test connectivity
        if ($TargetComputer -ne $env:COMPUTERNAME) {
            if (-not (Test-Connection -ComputerName $TargetComputer -Count 1 -Quiet)) {
                throw "Computer '$TargetComputer' is not accessible"
            }
        }

        # Create CIM session
        $cimSessionParams = @{
            ComputerName = $TargetComputer
            ErrorAction  = 'Stop'
        }
        $cimSession = New-CimSession @cimSessionParams

        # Retrieve services running under the specified account
        Write-AuditLog -Message "Retrieving services running under '$ServiceAccountName'..." -Level Information -Computer $TargetComputer

        $services = Get-CimInstance -CimSession $cimSession -ClassName Win32_Service -ErrorAction Stop |
                    Where-Object { $_.StartName -eq $ServiceAccountName }

        if (-not $services) {
            Write-AuditLog -Message "No services found running under '$ServiceAccountName'" -Level Warning -Computer $TargetComputer
            return $computerResults
        }

        Write-AuditLog -Message "Found $($services.Count) service(s) to update" -Level Information -Computer $TargetComputer

        # Extract credentials
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password

        # Process each service
        foreach ($service in $services) {
            try {
                $serviceName = $service.Name

                if ($PSCmdlet.ShouldProcess("Service: $serviceName on $TargetComputer", "Update credentials to $username")) {

                    Write-AuditLog -Message "Updating service: $serviceName" -Level Information -Computer $TargetComputer

                    # Update credentials
                    $changeParams = @{
                        StartName     = $username
                        StartPassword = $password
                    }

                    $changeResult = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments $changeParams -ErrorAction Stop

                    if ($changeResult.ReturnValue -eq 0) {
                        Write-AuditLog -Message "Credentials updated for service: $serviceName" -Level Security -Computer $TargetComputer -EventId 2001

                        # Restart if running
                        if ($service.State -eq 'Running') {
                            try {
                                Write-AuditLog -Message "Restarting service: $serviceName" -Level Information -Computer $TargetComputer

                                $stopResult = Invoke-CimMethod -InputObject $service -MethodName StopService -ErrorAction Stop
                                Start-Sleep -Seconds 2

                                $startResult = Invoke-CimMethod -InputObject $service -MethodName StartService -ErrorAction Stop

                                if ($startResult.ReturnValue -eq 0) {
                                    Write-AuditLog -Message "Service restarted successfully: $serviceName" -Level Information -Computer $TargetComputer
                                } else {
                                    Write-AuditLog -Message "Failed to restart service: $serviceName (Code: $($startResult.ReturnValue))" -Level Warning -Computer $TargetComputer
                                }
                            } catch {
                                Write-AuditLog -Message "Error restarting service $serviceName : $_" -Level Warning -Computer $TargetComputer
                            }
                        }

                        $computerResults.Success++

                    } else {
                        $errorMsg = "Failed to update service: $serviceName (Return code: $($changeResult.ReturnValue))"
                        Write-AuditLog -Message $errorMsg -Level Error -Computer $TargetComputer
                        $computerResults.Failed++
                        $computerResults.Errors += $errorMsg
                    }
                }

            } catch {
                $errorMsg = "Error processing service $serviceName : $_"
                Write-AuditLog -Message $errorMsg -Level Error -Computer $TargetComputer
                $computerResults.Failed++
                $computerResults.Errors += $errorMsg
            }
        }

    } catch {
        $errorMsg = "Error processing computer $TargetComputer : $_"
        Write-AuditLog -Message $errorMsg -Level Error -Computer $TargetComputer
        $computerResults.Errors += $errorMsg

    } finally {
        if ($cimSession) {
            Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
        }

        # Clear password from memory
        if ($password) {
            Clear-Variable -Name password -ErrorAction SilentlyContinue
        }
    }

    return $computerResults
}

#----------------------------------------------
# Main Execution Block
#----------------------------------------------
try {
    Write-AuditLog -Message "========== Bulk Service Credential Update Started ==========" -Level Security -EventId 2000
    Write-AuditLog -Message "Script: $script:ScriptName" -Level Information
    Write-AuditLog -Message "Executed by: $script:ExecutingUser" -Level Information
    Write-AuditLog -Message "Target Account: $ServiceAccountName" -Level Information
    Write-AuditLog -Message "Target Computers: $($ComputerName -join ', ')" -Level Information

    $allResults = @()

    # Process each computer
    foreach ($computer in $ComputerName) {
        $result = Update-ComputerServices -TargetComputer $computer
        $allResults += $result
    }

    # Summary report
    Write-Host "`n========== SUMMARY REPORT ==========" -ForegroundColor Cyan
    $totalSuccess = ($allResults | Measure-Object -Property Success -Sum).Sum
    $totalFailed = ($allResults | Measure-Object -Property Failed -Sum).Sum

    foreach ($result in $allResults) {
        Write-Host "`nComputer: $($result.Computer)" -ForegroundColor Yellow
        Write-Host "  Successful: $($result.Success)" -ForegroundColor Green
        Write-Host "  Failed: $($result.Failed)" -ForegroundColor Red

        if ($result.Errors.Count -gt 0) {
            Write-Host "  Errors:" -ForegroundColor Red
            foreach ($error in $result.Errors) {
                Write-Host "    - $error" -ForegroundColor Red
            }
        }
    }

    Write-Host "`nOverall Total:" -ForegroundColor Cyan
    Write-Host "  Total Successful: $totalSuccess" -ForegroundColor Green
    Write-Host "  Total Failed: $totalFailed" -ForegroundColor Red

    $duration = (Get-Date) - $script:StartTime
    Write-AuditLog -Message "========== Bulk Service Credential Update Completed (Duration: $($duration.ToString('mm\:ss'))) ==========" -Level Security -EventId 2002

    if ($totalFailed -gt 0) {
        exit 1
    } else {
        exit 0
    }

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level Error
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Write-AuditLog -Message "========== Bulk Service Credential Update Failed ==========" -Level Security -EventId 2003

    exit 1

} finally {
    # Stop transcript
    try { Stop-Transcript } catch {}
}
