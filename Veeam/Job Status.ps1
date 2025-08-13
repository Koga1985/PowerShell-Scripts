<#
.SYNOPSIS
    Retrieves Veeam backup sessions from the last 10 days and writes job results to a timestamped log file.

.DESCRIPTION
    This script performs the following actions:
      1. Defines the destination folder for log files.
      2. Ensures the log folder exists (creating it if it doesn't).
      3. Generates a timestamp and constructs a log file path.
      4. Retrieves Veeam backup sessions from the past 10 days.
      5. Formats the output (job name, type, creation time, result, and backup size) and writes it to a log file.
      6. Displays appropriate messages on the console regarding the success or failure of each operation.

.PREREQUISITES
    - Veeam Backup & Replication PowerShell module must be installed and imported.
    - The account running this script must have permissions to query backup session data.
    - Adjust the $destination variable if you require a different log file location.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to both the console and a specified log file.
    
    .PARAMETER Message
        The text message to output.
    
    .PARAMETER LogPath
        The file path where the log message should be appended.
    
    .PARAMETER Level
        The log level (INFO, ERROR, etc.). Default is "INFO".
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$true)][string]$LogPath,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "$timeStamp [$Level] $Message"
    
    # Write message to the console
    Write-Host $formattedMessage
    
    # Append the message to the log file
    Add-Content -Path $LogPath -Value $formattedMessage
}

#==============================================
# Main Script Variables and Setup
#==============================================


# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script must be run as Administrator." -ForegroundColor Red
    exit 1
}

# Check for Veeam PowerShell module
if (-not (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell)) {
    Write-Host "ERROR: Veeam PowerShell module is not installed or loaded." -ForegroundColor Red
    exit 1
}

# Define the destination folder for log files
$destination = "C:\Log Files"

# Ensure the destination folder exists; if not, create it.
if (-not (Test-Path -Path $destination)) {
    Write-Host "Creating directory: $destination"
    try {
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
    } catch {
        Write-Host "Error creating directory: $destination. Error: $_"
        exit 1
    }
}

# Generate a timestamp string for the log file name
$timestamp = Get-Date -Format 'MMddyyyy-HHmmss'

# Construct the log file path using the destination folder and timestamped file name
$logFilePath = Join-Path $destination "Veeam Job Results_$timestamp.log"

# Write an initial log message to the file
"Log File Created: $logFilePath" | Out-File -FilePath $logFilePath

#==============================================
# Retrieve and Log Veeam Backup Sessions
#==============================================

# Summary variable
$Summary = $false

try {
    $sessions = Get-VBRBackupSession | Where-Object { $_.CreationTime -ge (Get-Date).AddDays(-10) }
    if ($sessions) {
        $formattedSessions = $sessions |
            Select-Object JobName, JobType, CreationTime, Result, @{
                Name = "BackupSize"
                Expression = { $_.BackupStats.BackupSize }
            } |
            Sort-Object CreationTime |
            Format-Table | Out-String
        $formattedSessions | Out-File -FilePath $logFilePath -Append
        Write-Log -Message "Job status written to: $logFilePath" -LogPath $logFilePath -Level "INFO"
        $Summary = $true
    } else {
        Write-Log -Message "No backup sessions found within the last 10 days." -LogPath $logFilePath -Level "INFO"
        $Summary = $true
    }
} catch {
    Write-Log -Message "An error occurred while retrieving backup session data. Error: $_" -LogPath $logFilePath -Level "ERROR"
    $Summary = $false
}

# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
Write-Host "Job status log: $logFilePath"
Write-Host "Script completed: $($Summary ? 'Success' : 'Failed')"
