<#
.SYNOPSIS
    Retrieves and displays all installed Windows updates on the system.

.DESCRIPTION
    This script uses the Get-HotFix cmdlet to obtain a list of installed Windows updates.
    The results are then displayed in a formatted table. The script includes logging functionality
    to provide feedback and error handling to ensure reliability.

.PARAMETER None
    This script does not require any parameters.

.EXAMPLE
    PS C:\> .\Get-InstalledUpdates.ps1
    This command will retrieve and display all installed Windows updates in a table.

.NOTES
    Author: Your Name
    Date: 2025-04-14
    Version: 1.0
    Prerequisites: Must be run as Administrator for full access to installed update details.
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a log message with a timestamp and specified severity level.
    
    .PARAMETER Message
        The text of the log message.
    
    .PARAMETER Level
        The severity level (e.g., "INFO", "ERROR"). Default is "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

Write-Log -Message "Starting retrieval of installed Windows updates..."

#----------------------------------------------
# 1. Retrieve Installed Windows Updates
#----------------------------------------------
try {
    # Get-HotFix retrieves a list of installed hotfixes and updates
    $installedUpdates = Get-HotFix -ErrorAction Stop
    Write-Log -Message "Retrieved $($installedUpdates.Count) installed updates." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving installed updates: $_" -Level "ERROR"
    exit 1
}

#----------------------------------------------
# 2. Display Installed Windows Updates
#----------------------------------------------
Write-Host "Installed Windows Updates:"
$installedUpdates | Format-Table -AutoSize

Write-Log -Message "Installed updates displayed successfully." -Level "INFO"
