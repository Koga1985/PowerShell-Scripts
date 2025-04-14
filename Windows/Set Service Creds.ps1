<#
.SYNOPSIS
    Updates the logon credentials for services running under a specified account on a remote computer and restarts them.

.DESCRIPTION
    This script updates the service logon credentials on a remote computer for all services that run under a specified account.
    It:
      1. Accepts parameters for the remote computer name (defaults to the local computer), the target service account (defaults
         to the current domain\user), and the new password (as a secure string).
      2. Uses Invoke-Command to run a script block on the target computer.
      3. Retrieves all services (via Get-CimInstance) that run under the specified account.
      4. Updates each service's logon credentials by calling the Win32_Service Change method (via Invoke-CimMethod).
      5. If the service is running, it is stopped and restarted to apply the change.
      
.PARAMETER computerName
    The target computer name or IP address. Defaults to the local computer if not provided.

.PARAMETER serviceUsername
    The account under which the service(s) are running, in the format domain\username. Defaults to the current domain\user.

.PARAMETER servicePassword
    The new password for the service logon account. Must be provided as a secure string.

.EXAMPLE
    PS C:\> .\Set-ServiceAcctCreds.ps1 -computerName "RemoteServer01" -serviceUsername "DOMAIN\User" -servicePassword (ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force)
    This example updates the services running under DOMAIN\User on RemoteServer01 with the new password, then restarts the services.

.NOTES
    Author: Your Name or Organization
    Date: 2025-04-14
    Version: 1.1
    Prerequisites:
      - Must be run with administrative privileges.
      - Remote PowerShell must be enabled if targeting a remote system.
#>

param (
    [alias('computer', 'c')]
    [string]$computerName = $env:COMPUTERNAME,
    
    [alias('username', 'u')]
    [string]$serviceUsername = "$env:USERDOMAIN\$env:USERNAME",
    
    [alias('password', 'p')]
    [Parameter(Mandatory = $true)]
    [securestring]$servicePassword
)

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with a timestamp and specified severity level.
        
    .PARAMETER Message
        The log message text.
        
    .PARAMETER Level
        The severity level (e.g., "INFO", "ERROR"). Defaults to "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

Write-Log -Message "Starting service credential update process on '$computerName' for account '$serviceUsername'." -Level "INFO"

#----------------------------------------------
# Invoke-Command to Update Service Credentials on the Target Computer
#----------------------------------------------
Invoke-Command -ComputerName $computerName -Credential "$env:USERDOMAIN\$env:USERNAME" -ScriptBlock {
    param (
        [string]$computerName,
        [string]$serviceUsername,
        [securestring]$servicePassword
    )

    Write-Host "Retrieving services running under account '$serviceUsername' on $computerName..."
    try {
        # Retrieve the services with a filter based on the StartName property matching the specified serviceUsername.
        $services = Get-CimInstance -ClassName Win32_Service -Filter "StartName='$serviceUsername'" -ErrorAction Stop
    } catch {
        Write-Host "Error retrieving services: $_" -ForegroundColor Red
        return
    }
    
    foreach ($svc in $services) {
        Write-Host ("Updating credentials for service: {0} (running as: {1}) on host: {2}." -f $svc.Name, $serviceUsername, $computerName)
        
        try {
            # Update the service logon credentials using the Change() method.
            # Only the StartName and StartPassword parameters are being updated; other parameters remain unchanged (passed as $null).
            $changeResult = Invoke-CimMethod -InputObject $svc -MethodName Change -Arguments @{
                StartName     = $serviceUsername;
                StartPassword = $servicePassword
            } -ErrorAction Stop
            
            if ($changeResult.ReturnValue -eq 0) {
                Write-Host "Service credential change accepted."
                # If the service is running, stop and restart it to apply the new credentials.
                if ($svc.State -eq "Running") {
                    Write-Host ("Restarting service {0} to apply credential changes." -f $svc.Name)
                    
                    # Stop the service
                    $stopResult = Invoke-CimMethod -InputObject $svc -MethodName StopService -ErrorAction Stop
                    if ($stopResult.ReturnValue -eq 0) {
                        Write-Host -NoNewline "Service stopped. Waiting for the service to stop "
                        # Poll until the service state becomes 'Stopped'
                        do {
                            Start-Sleep -Seconds 2
                            $currentSvcState = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'").State
                            Write-Host -NoNewline "."
                        } while ($currentSvcState -ne "Stopped")
                        Write-Host "Stopped."
                        
                        # Start the service
                        $startResult = Invoke-CimMethod -InputObject $svc -MethodName StartService -ErrorAction Stop
                        if ($startResult.ReturnValue -eq 0) {
                            Write-Host "Service started successfully."
                        } else {
                            Write-Host ("Failed to start service. Return code: {0}" -f $startResult.ReturnValue) -ForegroundColor Red
                        }
                    } else {
                        Write-Host ("Failed to stop service. Return code: {0}" -f $stopResult.ReturnValue) -ForegroundColor Red
                    }
                }
            } else {
                Write-Host ("Failed to change service credentials. Change() returned code: {0}" -f $changeResult.ReturnValue) -ForegroundColor Red
            }
        } catch {
            Write-Host "Error updating credentials for service '$($svc.Name)': $_" -ForegroundColor Red
        }
    }
} -ArgumentList $computerName, $serviceUsername, $servicePassword

Write-Log -Message "Service credential update process completed on '$computerName'." -Level "INFO"
