<#
.SYNOPSIS
    Sanitize log files by replacing sensitive data (IP addresses, host names, email addresses, file paths) with generic placeholders.

.DESCRIPTION
    This script:
      1. Verifies that the target log folder exists.
      2. Retrieves all ".log" files from the specified location (including subdirectories).
      3. Loops through each log file to sanitize sensitive information:
            - Replaces any detected IP addresses with a placeholder.
            - Replaces detected host names with a placeholder.
            - Replaces email addresses with "EmailPlaceholder".
            - Replaces full file paths with "FilePathPlaceholder".
      4. Writes any errors or progress messages to both the console and a dedicated error log file.

.PARAMETER None
    This script does not take command-line parameters, but you can modify variables such as:
      - $location: the folder containing log files.
      - $errorLogFile: the path of the error log to record issues.
      - Placeholder strings for sensitive data replacement.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites: Ensure that the log folder specified in $location exists or update the variable accordingly.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Logs messages with a timestamp and level to the console and optionally to a file.
    
    .PARAMETER Message
        The text of the message to log.
    .PARAMETER Level
        The log level (e.g., INFO, ERROR). Default is INFO.
    .PARAMETER LogFile
        (Optional) A file path where the message should be appended.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Level = "INFO",

        [string]$LogFile
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "$timeStamp [$Level] $Message"

    # Output to the console
    Write-Host $formattedMessage

    # If a LogFile is provided, append the message to that file
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $formattedMessage
    }
}

#==============================================
# Function: Sanitize-LogFile
#==============================================
function Sanitize-LogFile {
    <#
    .SYNOPSIS
        Reads a log file, replaces sensitive data with placeholders, and overwrites the file.
    
    .PARAMETER LogFilePath
        The full path to the log file to sanitize.
    
    .PARAMETER HostPlaceholder
        The placeholder string used for host names.
    
    .PARAMETER IpPlaceholder
        The placeholder string used for IP addresses.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath,

        [Parameter(Mandatory = $true)]
        [string]$HostPlaceholder,

        [Parameter(Mandatory = $true)]
        [string]$IpPlaceholder
    )

    try {
        Write-Log -Message "Sanitizing file: $LogFilePath..." -Level "INFO"
        
        # Read the entire file content as a single string
        $logContent = Get-Content -Path $LogFilePath -Raw

        # Replace detected IP addresses with the provided IP placeholder.
        # Pattern: Matches any valid IPv4 address.
        $logContent = $logContent -replace '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b', $IpPlaceholder
        
        # Replace host names (alphanumeric including hyphen or underscore) with the host placeholder.
        # NOTE: This regex is intentionally generic and might need tuning based on your actual log content.
        $logContent = $logContent -replace '\b[A-Za-z0-9_-]+\b', $HostPlaceholder

        # Replace email addresses with a generic placeholder.
        $logContent = $logContent -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', "EmailPlaceholder"

        # Replace full file paths (e.g., "C:\Path\To\File") with a generic placeholder.
        $logContent = $logContent -replace '\b[C-Z]:\\[A-Za-z0-9._\\-]+\b', "FilePathPlaceholder"

        # Overwrite the original log file with the sanitized content.
        $logContent | Set-Content -Path $LogFilePath

        Write-Log -Message "Sanitization completed for $LogFilePath" -Level "INFO"
    }
    catch {
        $errorMessage = "Error processing file $LogFilePath: $_"
        Write-Log -Message $errorMessage -Level "ERROR"
        # Append the error message to the global error log file.
        Add-Content -Path $errorLogFile -Value "$(Get-Date) - $errorMessage"
    }
}

#==============================================
# Global Variables and Setup
#==============================================
# Define the log location (update as needed)
$location = "YourLogLocationPath"

# Verify that the log folder exists; if not, exit with an error.
if (!(Test-Path -Path $location -PathType Container)) {
    Write-Host "Log folder does not exist: $location" -ForegroundColor Red
    exit
}

# Define placeholders for sensitive data.
$hostNamePlaceholder = "HostNamePlaceholder"
$ipAddressPlaceholder = "IPAddressPlaceholder"

# Define the error log file path (used by both the main script and functions).
$errorLogFile = "C:\VeeamLogs\ScrubberErrorLog.txt"

#==============================================
# Main Processing
#==============================================
# Get all log files (with a .log extension) from the specified location recursively.
$logFiles = Get-ChildItem -Path $location -Filter "*.log" -Recurse

# Loop through each discovered log file and sanitize its contents.
foreach ($logFile in $logFiles) {
    try {
        # Call the function to sanitize the log file.
        Sanitize-LogFile -LogFilePath $logFile.FullName -HostPlaceholder $hostNamePlaceholder -IpPlaceholder $ipAddressPlaceholder
    }
    catch {
        $errorMessage = "$(Get-Date) - Error processing $($logFile.FullName): $_"
        Write-Log -Message $errorMessage -Level "ERROR"
        Add-Content -Path $errorLogFile -Value $errorMessage
    }
}

Write-Host "Log sanitization process completed." -ForegroundColor Green
