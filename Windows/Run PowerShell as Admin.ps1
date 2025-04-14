<#
.SYNOPSIS
    Ensures that a PowerShell script is running with administrative privileges and restarts it with elevation if not.

.DESCRIPTION
    This script checks whether the current PowerShell session is running with administrative privileges. If it is not running
    as an Administrator, it will restart itself with elevated privileges by using the Start-Process cmdlet with the "RunAs" verb.
    Once elevated, the script continues executing. This functionality is useful when a script requires administrative rights
    to perform critical tasks.
    
.PARAMETER None
    This script does not require any parameters; it operates on the current script.
    
.EXAMPLE
    PS C:\> .\Elevate-Script.ps1
    The script will check for administrative privileges and, if necessary, relaunch itself with elevated rights.
    
.NOTES
    Author: Your Name or Organization
    Date: 2025-04-14
    Version: 1.0
    Prerequisites: 
      - Run on a Windows system.
      - Must be executed with PowerShell.
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a timestamped log message with a specified severity level.
        
    .PARAMETER Message
        The message text to log.
        
    .PARAMETER Level
        The severity level (e.g., "INFO", "WARNING", "ERROR"). Default is "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

#----------------------------------------------
# 1. Check for Administrative Privileges
#----------------------------------------------
Write-Log -Message "Checking if script is running with administrative privileges..."

# Determine if the current user is in the Administrators group.
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log -Message "Script is not running with administrative privileges. Attempting to restart with elevation..." -Level "WARNING"
    try {
        # Restart the current script with elevated privileges using the "RunAs" verb.
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" `
            -Verb RunAs -ErrorAction Stop
        Write-Log -Message "Elevated process started. Exiting current non-elevated session." -Level "INFO"
    } catch {
        Write-Log -Message "Failed to restart script with elevated privileges: $_" -Level "ERROR"
    }
    exit
} else {
    Write-Log -Message "Running with administrative privileges." -Level "INFO"
}

#----------------------------------------------
# 2. Proceed with the Main Script Logic
#----------------------------------------------
# Your script code goes here. For demonstration, we output a confirmation message.
Write-Log -Message "Script execution continues under administrative privileges." -Level "INFO"

# Example: Display a message to the user.
Write-Host "Running with administrative privileges."
