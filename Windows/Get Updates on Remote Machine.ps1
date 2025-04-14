<#
.SYNOPSIS
    Retrieves and displays installed Windows updates from a remote computer.

.DESCRIPTION
    This script prompts the user for the name or IP address of a remote computer, retrieves the list
    of installed Windows updates (hotfixes) using the Get-HotFix cmdlet, and then outputs the results 
    in a formatted table.

.PARAMETER None
    This script runs interactively and does not take any command-line parameters.

.EXAMPLE
    PS C:\> .\Get-RemoteHotFixes.ps1
    Enter the name or IP address of the remote computer: RemotePC01
    Installed Windows Updates on RemotePC01:
    (Displays the formatted table of installed updates)

.NOTES
    Author: Your Name or Organization
    Date: 2025-04-14
    Version: 1.0
    Prerequisites:
      - Run the script with appropriate permissions (typically Administrator).
      - The remote computer must be accessible and allow remote WMI queries.
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with a timestamp and a specific severity level.
    
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

#----------------------------------------------
# 1. Prompt for the Remote Computer Name or IP
#----------------------------------------------
$remoteComputer = Read-Host "Enter the name or IP address of the remote computer"
Write-Log -Message "Remote computer entered: $remoteComputer"

#----------------------------------------------
# 2. Retrieve Installed Windows Updates from the Remote Computer
#----------------------------------------------
Write-Log -Message "Attempting to retrieve installed Windows updates from $remoteComputer..."
try {
    # Get-HotFix retrieves installed updates; 
    # -ComputerName parameter allows querying a remote system.
    $installedUpdatesRemote = Get-HotFix -ComputerName $remoteComputer -ErrorAction Stop
    Write-Log -Message "Successfully retrieved $($installedUpdatesRemote.Count) updates from $remoteComputer." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving updates from $remoteComputer: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 3. Display the List of Installed Updates
#----------------------------------------------
Write-Host "Installed Windows Updates on $remoteComputer:"
$installedUpdatesRemote | Format-Table -AutoSize

Write-Log -Message "Displayed installed updates for $remoteComputer." -Level "INFO"
