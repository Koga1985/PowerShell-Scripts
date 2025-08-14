<#
.SYNOPSIS
    Updates the logon credentials for a specified service on a remote computer and restarts the service.
    
.DESCRIPTION
    This function, Set-ServiceAcctCreds, does the following:
      1. Connects to a remote computer using CIM and retrieves the specified service.
      2. Updates the service's logon account and password by invoking the Change method of the Win32_Service class.
      3. Stops and then starts the service to apply the new credentials.
      
    NOTE: The Win32_Service Change method returns a numeric code:
          0 indicates success; non-zero values indicate error.
          Ensure you run this script with appropriate administrative privileges.
          
.PARAMETER strCompName
    The name (or IP address) of the remote computer.
    
.PARAMETER strServiceName
    The name of the service for which credentials should be updated.
    
.PARAMETER newAcct
    The new logon account (in format DOMAIN\User or .\User for local accounts).
    
.PARAMETER newPass
    The new logon password (passed as plain text; consider securing it appropriately).
    
.EXAMPLE
    Set-ServiceAcctCreds -strCompName "RemoteComputer" -strServiceName "Spooler" -newAcct "DOMAIN\NewUser" -newPass "NewPassword123!"
    
    This example updates the credentials for the "Spooler" service on the computer "RemoteComputer" to use DOMAIN\NewUser.
    
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
#>

Function Set-ServiceAcctCreds {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$strCompName,
        [Parameter(Mandatory = $true)]
        [string]$strServiceName,
        [Parameter(Mandatory = $true)]
        [string]$newAcct,
        [Parameter(Mandatory = $true)]
        [string]$newPass
    )
    try {
        Write-Host "Retrieving service '$strServiceName' on computer '$strCompName'..."
        $service = Get-CimInstance -ComputerName $strCompName -ClassName Win32_Service -Filter "Name='$strServiceName'" -ErrorAction Stop
        if (-not $service) {
            Write-Host "Service '$strServiceName' not found on '$strCompName'." -ForegroundColor Red
            return
        }
        Write-Host "Updating logon credentials for service '$strServiceName'..."
        $result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{StartName=$newAcct; StartPassword=$newPass} -ErrorAction Stop
        if ($result.ReturnValue -eq 0) {
            Write-Host "Logon credentials updated successfully for service '$strServiceName'." -ForegroundColor Green
            Write-Host "Restarting service '$strServiceName'..."
            Restart-Service -ComputerName $strCompName -Name $strServiceName -ErrorAction Stop
            Write-Host "Service '$strServiceName' restarted successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to update credentials. ReturnValue: $($result.ReturnValue)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

# Example usage:
Set-ServiceAcctCreds -strCompName "RemoteComputer" -strServiceName "Spooler" -newAcct "DOMAIN\NewUser" -newPass "NewPassword123!"
