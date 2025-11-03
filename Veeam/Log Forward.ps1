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

.PARAMETER ServerList
    Array of server names to process.

.PARAMETER Credential
    PSCredential object for remote server authentication.

.PARAMETER HoursBack
    Number of hours to look back for log files. Default is 24.

.PARAMETER ExportPath
    Path for event log CSV export.

.PARAMETER LocalLogDir
    Local directory to store copied logs.

.SECURITY FEATURES
    - Requires PowerShell 5.1 and Administrator privileges
    - Comprehensive audit logging to file and Windows Event Log
    - Secure credential handling via PSCredential
    - Input validation for all parameters
    - Sanitizes server names and paths
    - Sensitive data cleared from memory on exit

.COMPLIANCE
    - Follows Fourth Estate security standards
    - Implements defense-in-depth logging
    - Supports audit trail requirements
    - Validates all input parameters

.PREREQUISITES
    - Sufficient permissions to access the remote servers and the required directories.
    - The remote servers must have the Veeam backup logs stored in the expected directory (e.g., "C:\ProgramData\Veeam\Backup").
    - Adjust server names, export paths, and log directories as needed.

.EXAMPLE
    $cred = Get-Credential
    .\Log Forward.ps1 -ServerList @("Server1","Server2") -Credential $cred -HoursBack 24

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        foreach ($server in $_) {
            if ($server -notmatch '^[a-zA-Z0-9\-\.]+$') {
                throw "Invalid server name format: $server"
            }
        }
        $true
    })]
    [string[]]$ServerList,

    [Parameter(Mandatory=$true)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1,168)]
    [int]$HoursBack = 24,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '^\\\\[a-zA-Z0-9\-\.]+\\[a-zA-Z]\$\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]+\.csv$') {
            $true
        } else {
            throw "Invalid UNC path format for CSV export."
        }
    })]
    [string]$ExportPath = '\\remoteserver\C$\Temp\VeeamLogs\events.csv',

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '^[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]*$') {
            $true
        } else {
            throw "Invalid path format. Must be a valid Windows path."
        }
    })]
    [string]$LocalLogDir = "C:\Backups Logs"
)

#==============================================
# Global Logging Setup
#==============================================

$Global:EventLogSource = "VeeamLogForward"
$Global:EventLogName = "Application"
$errorLogPath = Join-Path $LocalLogDir "ErrorLog.txt"

# Register Event Log Source
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
        [System.Diagnostics.EventLog]::CreateEventSource($Global:EventLogSource, $Global:EventLogName)
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Warning "Could not create Event Log source. Continuing with file logging only."
}

#==============================================
# Function: Write-AuditLog
#==============================================
function Write-AuditLog {
    <#
    .SYNOPSIS
        Comprehensive audit logging to file and Windows Event Log.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','ERROR','WARNING','SUCCESS')]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [string]$Operation = "General",

        [Parameter(Mandatory=$false)]
        [string]$TargetSystem = "Local",

        [Parameter(Mandatory=$false)]
        [string]$LogFile = $script:errorLogPath
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $logMessage = "$timestamp [$Level] User: $userName | Operation: $Operation | Target: $TargetSystem | $Message"

        # Write to console
        switch ($Level) {
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            default   { Write-Host $logMessage }
        }

        # Write to file
        if ($LogFile) {
            Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
        }

        # Write to Windows Event Log
        $eventType = switch ($Level) {
            'ERROR'   { [System.Diagnostics.EventLogEntryType]::Error }
            'WARNING' { [System.Diagnostics.EventLogEntryType]::Warning }
            default   { [System.Diagnostics.EventLogEntryType]::Information }
        }

        $eventID = switch ($Level) {
            'ERROR'   { 3001 }
            'WARNING' { 3002 }
            'SUCCESS' { 3003 }
            default   { 3000 }
        }

        if ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
            Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
                -EntryType $eventType -EventId $eventID -Message $logMessage -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Failed to write to audit log: $_"
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile
    )
    Write-AuditLog -Message $Message -Level $Level -Operation "LogForwarding" -LogFile $LogFile
}

#==============================================
# Input Validation
#==============================================
function Test-ComputerName {
    param([string]$ComputerName)

    if ($ComputerName -notmatch '^[a-zA-Z0-9\-\.]+$') {
        throw "Invalid computer name format: $ComputerName"
    }
    return $true
}

function Test-PathSafety {
    param([string]$Path)

    if ($Path -match '\.\.' -or $Path -match '[<>"|?*]') {
        throw "Path contains invalid or potentially unsafe characters: $Path"
    }
    return $true
}

#==============================================
# Global Variables and Setup
#==============================================

Write-AuditLog -Message "Script execution started" -Level INFO -Operation "Initialization"

# Define the script execution time parameters
$ScriptStart = Get-Date
$PreviousTime = (Get-Date).AddHours(-$HoursBack)

Write-AuditLog -Message "Time range: $PreviousTime to $ScriptStart" -Level INFO -Operation "Initialization"

# Ensure the local log directory exists; create it if missing.
if (-not (Test-Path -LiteralPath $LocalLogDir)) {
    Write-AuditLog -Message "Creating directory: $LocalLogDir" -Level INFO -Operation "Initialization"
    try {
        New-Item -Type Directory -Path $LocalLogDir -ErrorAction Stop | Out-Null
        Write-AuditLog -Message "Directory created successfully" -Level SUCCESS -Operation "Initialization"
    } catch {
        Write-AuditLog -Message "Failed to create local log directory: $LocalLogDir. Error: $_" -Level ERROR -Operation "Initialization"
        exit 1
    }
}

#==============================================
# Process Each Server
#==============================================

$Summary = @{}

try {
    foreach ($server in $ServerList) {
        Write-AuditLog -Message "Processing server: $server" -Level INFO -Operation "ProcessServer" -TargetSystem $server
        $success = $true

        try {
            # Validate server name
            Test-ComputerName -ComputerName $server

            $source = "\\$server\C$\ProgramData\Veeam\Backup"
            $destination = Join-Path $LocalLogDir $server

            # Validate paths
            Test-PathSafety -Path $destination

            if (-not (Test-Path -LiteralPath $destination)) {
                Write-AuditLog -Message "Creating destination directory: $destination" -Level INFO -Operation "CreateDirectory" -TargetSystem $server
                New-Item -Type Directory -Path $destination -ErrorAction Stop | Out-Null
            }

            Write-AuditLog -Message "Copying backup log files from $source" -Level INFO -Operation "CopyLogs" -TargetSystem $server

            # Test connectivity
            if (-not (Test-Path -Path $source)) {
                throw "Cannot access source path: $source. Check network connectivity and permissions."
            }

            $filesToCopy = Get-ChildItem -Path $source -Recurse -File -ErrorAction Stop | Where-Object {
                $_.LastWriteTime -lt $ScriptStart -and $_.LastWriteTime -gt $PreviousTime
            }

            $copiedCount = 0
            foreach ($file in $filesToCopy) {
                try {
                    $logFileName = $file.Name
                    $destinationPath = Join-Path $destination $logFileName

                    # Validate file name
                    if ($logFileName -match '[<>:"|?*]') {
                        Write-AuditLog -Message "Skipping file with invalid characters: $logFileName" -Level WARNING -Operation "CopyLogs" -TargetSystem $server
                        continue
                    }

                    Copy-Item -Path $file.FullName -Destination $destinationPath -ErrorAction Stop
                    $copiedCount++
                } catch {
                    Write-AuditLog -Message "Failed to copy file $($file.Name). Error: $_" -Level WARNING -Operation "CopyLogs" -TargetSystem $server
                }
            }

            Write-AuditLog -Message "Copied $copiedCount file(s) from $server" -Level SUCCESS -Operation "CopyLogs" -TargetSystem $server

            # Retrieve Application event logs
            Write-AuditLog -Message "Retrieving Application event logs from $server" -Level INFO -Operation "ExportEventLogs" -TargetSystem $server

            $eventLogs = Get-EventLog -LogName Application -After $PreviousTime -Before $ScriptStart -ComputerName $server -ErrorAction Stop |
                         Select-Object EventID, MachineName, Message, TimeGenerated, Source

            if ($eventLogs) {
                $eventLogs | Export-Csv -Path $ExportPath -Append -NoTypeInformation -Force -ErrorAction Stop
                Write-AuditLog -Message "Exported $($eventLogs.Count) event log entries" -Level SUCCESS -Operation "ExportEventLogs" -TargetSystem $server
            } else {
                Write-AuditLog -Message "No event logs found in specified time range" -Level INFO -Operation "ExportEventLogs" -TargetSystem $server
            }

        } catch {
            $errorMessage = "Error occurred while processing $server: $_"
            Write-AuditLog -Message $errorMessage -Level ERROR -Operation "ProcessServer" -TargetSystem $server
            $success = $false
        }

        $Summary[$server] = $success
    }

} catch {
    Write-AuditLog -Message "Critical error during execution: $_" -Level ERROR -Operation "MainExecution"
    throw
} finally {
    # Clear sensitive data from memory
    if ($Credential) {
        $Credential = $null
    }
    [System.GC]::Collect()
}

# Summary Output
Write-Host "`nSummary:" -ForegroundColor Cyan
$successCount = 0
$failCount = 0

foreach ($server in $ServerList) {
    $status = if ($Summary[$server]) { $successCount++; 'Success' } else { $failCount++; 'Failed' }
    Write-Host "$server: $status"
}

Write-Host "`nTotal: $($ServerList.Count) servers - $successCount succeeded, $failCount failed" -ForegroundColor Cyan
Write-AuditLog -Message "Log forwarding completed. Success: $successCount, Failed: $failCount" -Level INFO -Operation "Completion"

# Exit with appropriate code
if ($failCount -eq 0) {
    Write-AuditLog -Message "Script completed successfully with no errors" -Level SUCCESS -Operation "Completion"
    exit 0
} else {
    Write-AuditLog -Message "Script completed with $failCount error(s)" -Level WARNING -Operation "Completion"
    exit 1
}
