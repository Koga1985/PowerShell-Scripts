<#
.SYNOPSIS
    Updates the logon credentials for a specified Windows service and restarts it.

.DESCRIPTION
    This script performs the following actions:
      1. Retrieves the specified service on the local (or remote) computer using CIM.
      2. Uses the Win32_Service Change method to update the service's logon account credentials.
      3. Stops the service to allow the credential changes to take effect.
      4. Starts the service again.
      
    The script is parameterized so you can specify the service name, the new account, and the new password.
    It includes robust error handling and logging for easier troubleshooting.

.PARAMETER ServiceName
    The name of the Windows service whose credentials are to be updated 
    (e.g., "Spooler" for the Print Spooler service).

.PARAMETER Account
    The new logon account in "domain\username" format (or ".\username" for a local account).

.PARAMETER Password
    The new logon password (as plain text). Use caution with plaintext passwords in scripts.
    
.EXAMPLE
    .\Set-ServiceAcctCreds.ps1 -ServiceName "Spooler" -Account "DOMAIN\User" -Password "P@ssw0rd123!"
    
    This example updates the credentials for the "Spooler" service to use the account DOMAIN\User with the specified password.

#
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   August 14, 2025
    Version:        1.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ServiceName,
    
    [Parameter(Mandatory = $true)]
    [string]$Account,
    
    [Parameter(Mandatory = $true)]
    [string]$Password
)

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a timestamped log message with a specified severity level.
        <#
        .SYNOPSIS
            Writes a timestamped log message with a specified severity level.
        .PARAMETER Message
            The log message text.
        .PARAMETER Level
            The severity level (INFO, ERROR, etc.). Default is INFO.
        #>
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [ValidateSet('INFO','ERROR','WARNING')]
            [string]$Level = "INFO"
        )
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "$timestamp [$Level] $Message"
    }

    # Ensure running as admin
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log -Message "Script must be run as Administrator." -Level "ERROR"
        exit 1
    }

    try {
        Write-Log -Message "Retrieving service '$ServiceName'..."
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
        if (-not $service) {
            Write-Log -Message "Service '$ServiceName' not found." -Level "ERROR"
            exit 1
        }
        Write-Log -Message "Updating logon credentials for service '$ServiceName'..."
        $result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{StartName=$Account; StartPassword=$Password} -ErrorAction Stop
        if ($result.ReturnValue -eq 0) {
            Write-Log -Message "Logon credentials updated successfully for service '$ServiceName'." -Level "INFO"
            Write-Log -Message "Restarting service '$ServiceName'..."
            Restart-Service -Name $ServiceName -ErrorAction Stop
            Write-Log -Message "Service '$ServiceName' restarted successfully." -Level "INFO"
        } else {
            Write-Log -Message "Failed to update credentials. ReturnValue: $($result.ReturnValue)" -Level "ERROR"
            exit 1
        }
    } catch {
        Write-Log -Message "Error: $_" -Level "ERROR"
        exit 1
    }
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

Write-Log -Message "Starting service credential update process for service: $ServiceName" -Level "INFO"

#----------------------------------------------
# 1. Retrieve the Service Object Using CIM
#----------------------------------------------
try {
    Write-Log -Message "Retrieving service '$ServiceName'..."
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if (-not $svc) {
        Write-Log -Message "Service '$ServiceName' not found." -Level "ERROR"
        exit
    }
    Write-Log -Message "Service '$ServiceName' retrieved successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving service '$ServiceName': $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 2. Update Service Credentials Using the Change Method
#----------------------------------------------
try {
    Write-Log -Message "Updating logon credentials for service '$ServiceName'..."
    $changeResult = Invoke-CimMethod -InputObject $svc -MethodName Change -Arguments @{
        StartName     = $Account;
        StartPassword = $Password
    } -ErrorAction Stop

    if ($changeResult.ReturnValue -eq 0) {
        Write-Log -Message "Service credentials updated successfully." -Level "INFO"
    } else {
        Write-Log -Message "Failed to update credentials. Return code: $($changeResult.ReturnValue)" -Level "ERROR"
        exit
    }
} catch {
    Write-Log -Message "Error updating credentials for service '$ServiceName': $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 3. Restart the Service to Apply Changes
#----------------------------------------------
try {
    Write-Log -Message "Stopping service '$ServiceName'..."
    $stopResult = Invoke-CimMethod -InputObject $svc -MethodName StopService -ErrorAction Stop
    Write-Log -Message "Service '$ServiceName' stopped successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error stopping service '$ServiceName': $_" -Level "ERROR"
}

try {
    Write-Log -Message "Starting service '$ServiceName'..."
    $startResult = Invoke-CimMethod -InputObject $svc -MethodName StartService -ErrorAction Stop
    if ($startResult.ReturnValue -eq 0) {
        Write-Log -Message "Service '$ServiceName' started successfully." -Level "INFO"
    } else {
        Write-Log -Message "Failed to start service '$ServiceName'. Return code: $($startResult.ReturnValue)" -Level "ERROR"
    }
} catch {
    Write-Log -Message "Error starting service '$ServiceName': $_" -Level "ERROR"
}

Write-Log -Message "Service credential update process completed for '$ServiceName'." -Level "INFO"
