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
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
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

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with a timestamp and specified severity level.
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

try {
    Write-Log -Message "Retrieving services running under '$serviceUsername' on '$computerName'..."
    $services = Get-CimInstance -ComputerName $computerName -ClassName Win32_Service | Where-Object { $_.StartName -eq $serviceUsername }
    if (-not $services) {
        Write-Log -Message "No services found running under '$serviceUsername' on '$computerName'." -Level "WARNING"
        return
    }
    foreach ($svc in $services) {
        Write-Log -Message "Updating credentials for service '$($svc.Name)'..."
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($servicePassword))
        $result = Invoke-CimMethod -InputObject $svc -MethodName Change -Arguments @{StartName=$serviceUsername; StartPassword=$plainPassword} -ErrorAction Stop
        if ($result.ReturnValue -eq 0) {
            Write-Log -Message "Credentials updated for service '$($svc.Name)'. Restarting service..." -Level "INFO"
            Restart-Service -ComputerName $computerName -Name $svc.Name -ErrorAction Stop
            Write-Log -Message "Service '$($svc.Name)' restarted successfully." -Level "INFO"
        } else {
            Write-Log -Message "Failed to update credentials for service '$($svc.Name)'. ReturnValue: $($result.ReturnValue)" -Level "ERROR"
        }
    }
} catch {
    Write-Log -Message "Error: $_" -Level "ERROR"
}
