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
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.0
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
        # Retrieve the service from the remote computer using CIM. 
        # Win32_Service provides the Change method, which we use to update credentials.
        Write-Host "Retrieving service '$strServiceName' on computer '$strCompName'..."
        $service = Get-CimInstance -ComputerName $strCompName -ClassName Win32_Service -Filter "Name='$strServiceName'" -ErrorAction Stop

        if (-not $service) {
            Write-Host "Service '$strServiceName' not found on computer '$strCompName'." -ForegroundColor Red
            return
        }
        
        # Update the service logon credentials by invoking the Change method.
        # Only pass parameters that need to be changed; here, we update StartName and StartPassword.
        Write-Host "Updating service credentials for '$strServiceName'..."
        $changeResult = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{
            StartName = $newAcct;
            StartPassword = $newPass
        }
        
        # Check the return code. A value of 0 indicates success.
        if ($changeResult.ReturnValue -eq 0) {
            Write-Host "Service credentials for '$strServiceName' updated successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to update credentials for '$strServiceName'. Return code: $($changeResult.ReturnValue)" -ForegroundColor Red
            return
        }
        
        # Restart the service to apply new credentials.
        Write-Host "Stopping service '$strServiceName'..."
        $stopResult = Invoke-CimMethod -InputObject $service -MethodName StopService
        Start-Sleep -Seconds 5  # Allow some time for the service to fully stop
        Write-Host "Starting service '$strServiceName'..."
        $startResult = Invoke-CimMethod -InputObject $service -MethodName StartService
        
        if ($startResult.ReturnValue -eq 0) {
            Write-Host "Service '$strServiceName' restarted successfully." -ForegroundColor Green
        } else {
            Write-Host "Service '$strServiceName' failed to restart. Return code: $($startResult.ReturnValue)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        # Add additional error handling or logging as needed.
    }
}

# Example usage:
Set-ServiceAcctCreds -strCompName "RemoteComputer" -strServiceName "Spooler" -newAcct "DOMAIN\NewUser" -newPass "NewPassword123!"
