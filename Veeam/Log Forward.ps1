<#
.SYNOPSIS
    Copies recent Veeam backup logs from multiple remote servers and exports event logs to a CSV file.

.DESCRIPTION
    This script performs the following tasks:
      1. Defines a list of remote servers, time range, and paths for backup log and event export.
      2. Ensures that local directories for storing backup logs exist (creates them if necessary).
      3. Iterates over each server to:
           - Copy files from the remote Veeam Backup logs folder if the LastWriteTime falls within a defined time range.
           - Retrieve event logs from the Application log (for the defined time range) and append them to a CSV file.
      4. Logs actions and any errors to the console as well as a separate error log file.

.PREREQUISITES
    - Sufficient permissions to access the remote servers and the required directories.
    - The remote servers must have the Veeam backup logs stored in the expected directory (e.g., "C:\ProgramData\Veeam\Backup").
    - Adjust server names, export paths, and log directories as needed.

.NOTES
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.0
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Logs a message with timestamp and level to the console and optionally a log file.
    
    .PARAMETER Message
        The log message.
    
    .PARAMETER Level
        The log level (e.g., INFO, ERROR). Default is INFO.
    
    .PARAMETER LogFile
        Optional file path to append the log message.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timeStamp [$Level] $Message"
    
    # Write to console
    Write-Host $logMessage
    
    # If a LogFile is provided, append the log message there
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logMessage
    }
}

#==============================================
# Global Variables and Setup
#==============================================
# Define remote servers to process (update with actual server names)
$servers = 'Server1', 'Server2'

# Define the script execution time parameters
$ScriptStart = Get-Date
$PreviousTime = (Get-Date).AddHours(-24)

# Destination path for event log CSV export (update as needed)
$ExportPath = '\\remoteserver\C$\Temp\VeeamLogs\events.csv'

# Define local log directory and error log file path
$localLogDir  = "C:\Backups Logs"
$errorLogPath = Join-Path $localLogDir "ErrorLog.txt"

# Ensure the local log directory exists; create it if missing.
if (-not (Test-Path -LiteralPath $localLogDir)) {
    Write-Host "Creating directory: $localLogDir"
    try {
        New-Item -Type Directory -Path $localLogDir | Out-Null
    }
    catch {
        Write-Host "Failed to create local log directory: $localLogDir. Error: $_"
        exit 1
    }
}

#==============================================
# Process Each Server
#==============================================
foreach ($server in $servers) {
    Write-Log -Message "Processing server: $server" -LogFile $errorLogPath
    try {
        # Define source folder (remote Veeam logs directory) and destination folder (local storage per server)
        $source = "\\$server\C$\ProgramData\Veeam\Backup"
        $destination = Join-Path $localLogDir $server

        # Ensure destination folder for the server exists
        if (-not (Test-Path -LiteralPath $destination)) {
            Write-Log -Message "Creating destination directory for $server: $destination" -LogFile $errorLogPath
            New-Item -Type Directory -Path $destination | Out-Null
        }
        
        # Get all files from the source directory recursively and filter by last write time
        Write-Log -Message "Copying backup log files from $source modified between $PreviousTime and $ScriptStart." -LogFile $errorLogPath
        $filesToCopy = Get-ChildItem -Path $source -Recurse -File | Where-Object {
            $_.LastWriteTime -lt $ScriptStart -and $_.LastWriteTime -gt $PreviousTime
        }
        
        # Copy each file from the remote server to the local destination folder
        foreach ($file in $filesToCopy) {
            $logFileName = $file.Name
            $destinationPath = Join-Path $destination $logFileName
            Write-Log -Message "Copying file: $logFileName to $destinationPath" -LogFile $errorLogPath
            Copy-Item -Path $file.FullName -Destination $destinationPath -ErrorAction Stop
        }
        
        # Retrieve Application event logs for the server within the time range
        Write-Log -Message "Retrieving Application event logs from $server from $PreviousTime to $ScriptStart." -LogFile $errorLogPath
        $eventLogs = Get-EventLog -LogName Application -After $PreviousTime -Before $ScriptStart -ComputerName $server |
                     Select-Object EventID, MachineName, Message
        
        # Export (append) event logs to the CSV file at the specified export path
        $eventLogs | Export-Csv -Path $ExportPath -Append -NoTypeInformation -Force
        
        Write-Log -Message "Logs copied and event logs exported successfully for $server." -LogFile $errorLogPath
    }
    catch {
        $errorMessage = "Error occurred while processing $server: $_"
        Write-Log -Message $errorMessage -Level "ERROR" -LogFile $errorLogPath
    }
}
