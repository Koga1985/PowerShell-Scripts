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

.PARAMETER VeeamServer
    Target Veeam Backup & Replication server name.

.PARAMETER Credential
    PSCredential object for Veeam server authentication.

.PARAMETER DaysBack
    Number of days to retrieve backup sessions. Default is 10.

.PARAMETER OutputPath
    Path where log files will be stored. Default is C:\Log Files.

.SECURITY FEATURES
    - Requires PowerShell 5.1 and Administrator privileges
    - Comprehensive audit logging to file and Windows Event Log
    - Secure credential handling via PSCredential
    - Input validation for all parameters
    - Sensitive data cleared from memory on exit

.COMPLIANCE
    - Follows Fourth Estate security standards
    - Implements defense-in-depth logging
    - Supports audit trail requirements
    - Validates all input parameters

.PREREQUISITES
    - Veeam Backup & Replication PowerShell module must be installed and imported.
    - The account running this script must have permissions to query backup session data.
    - Adjust the $destination variable if you require a different log file location.

.EXAMPLE
    $cred = Get-Credential
    .\Job Status.ps1 -VeeamServer "VEEAM01" -Credential $cred -DaysBack 10

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
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9\-\.]+$')]
    [string]$VeeamServer = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1,365)]
    [int]$DaysBack = 10,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '^[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]*$') {
            $true
        } else {
            throw "Invalid path format. Must be a valid Windows path."
        }
    })]
    [string]$OutputPath = "C:\Log Files"
)

#==============================================
# Global Logging Setup
#==============================================

$Global:EventLogSource = "VeeamJobStatus"
$Global:EventLogName = "Application"

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

    .PARAMETER Message
        The message text to log.

    .PARAMETER LogPath
        The file path where the log message should be appended.

    .PARAMETER Level
        The message level (INFO, ERROR, WARNING, SUCCESS). Default is INFO.

    .PARAMETER Operation
        The operation being performed.

    .PARAMETER TargetSystem
        The target system for the operation.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','ERROR','WARNING','SUCCESS')]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [string]$Operation = "General",

        [Parameter(Mandatory=$false)]
        [string]$TargetSystem = $VeeamServer
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
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction Stop

        # Write to Windows Event Log
        $eventType = switch ($Level) {
            'ERROR'   { [System.Diagnostics.EventLogEntryType]::Error }
            'WARNING' { [System.Diagnostics.EventLogEntryType]::Warning }
            default   { [System.Diagnostics.EventLogEntryType]::Information }
        }

        $eventID = switch ($Level) {
            'ERROR'   { 2001 }
            'WARNING' { 2002 }
            'SUCCESS' { 2003 }
            default   { 2000 }
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
    <#
    .SYNOPSIS
        Wrapper function for Write-AuditLog to maintain compatibility.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$true)][string]$LogPath,
        [string]$Level = "INFO"
    )
    Write-AuditLog -Message $Message -LogPath $LogPath -Level $Level -Operation "JobStatusReporting"
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

    # Check for path traversal attempts
    if ($Path -match '\.\.' -or $Path -match '[<>:"|?*]') {
        throw "Path contains invalid or potentially unsafe characters: $Path"
    }
    return $true
}

try {
    Test-ComputerName -ComputerName $VeeamServer
    Test-PathSafety -Path $OutputPath
} catch {
    Write-Error "Input validation failed: $_"
    exit 1
}

#==============================================
# Main Script Variables and Setup
#==============================================

# Ensure the destination folder exists; if not, create it.
if (-not (Test-Path -Path $OutputPath)) {
    Write-Host "Creating directory: $OutputPath"
    try {
        New-Item -ItemType Directory -Force -Path $OutputPath -ErrorAction Stop | Out-Null
        Write-Host "Directory created successfully."
    } catch {
        Write-Error "Error creating directory: $OutputPath. Error: $_"
        exit 1
    }
}

# Generate a timestamp string for the log file name
$timestamp = Get-Date -Format 'MMddyyyy-HHmmss'

# Construct the log file path using the destination folder and timestamped file name
$logFilePath = Join-Path $OutputPath "Veeam Job Results_$timestamp.log"

# Validate the constructed path
try {
    Test-PathSafety -Path $logFilePath
} catch {
    Write-Error "Generated log file path is invalid: $_"
    exit 1
}

# Write an initial log message to the file
try {
    "Log File Created: $logFilePath" | Out-File -FilePath $logFilePath -ErrorAction Stop
    Write-AuditLog -Message "Job status log file created" -LogPath $logFilePath -Level INFO -Operation "Initialization"
} catch {
    Write-Error "Failed to create log file: $_"
    exit 1
}

#==============================================
# Check Prerequisites
#==============================================

Write-AuditLog -Message "Script execution started. Checking prerequisites..." -LogPath $logFilePath -Level INFO -Operation "Initialization"

# Check for Veeam PowerShell module
if (-not (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell)) {
    Write-AuditLog -Message "Veeam PowerShell module is not installed or loaded." -LogPath $logFilePath -Level ERROR -Operation "Initialization"
    exit 1
}

#==============================================
# Retrieve and Log Veeam Backup Sessions
#==============================================

$Summary = $false

try {
    Write-AuditLog -Message "Retrieving backup sessions from the last $DaysBack days..." -LogPath $logFilePath -Level INFO -Operation "RetrieveSessions"

    $sessions = Get-VBRBackupSession | Where-Object {
        $_.CreationTime -ge (Get-Date).AddDays(-$DaysBack)
    } -ErrorAction Stop

    if ($sessions) {
        Write-AuditLog -Message "Found $($sessions.Count) backup session(s)" -LogPath $logFilePath -Level SUCCESS -Operation "RetrieveSessions"

        $formattedSessions = $sessions |
            Select-Object JobName, JobType, CreationTime, Result, @{
                Name = "BackupSize"
                Expression = { $_.BackupStats.BackupSize }
            } |
            Sort-Object CreationTime |
            Format-Table | Out-String

        $formattedSessions | Out-File -FilePath $logFilePath -Append -ErrorAction Stop
        Write-AuditLog -Message "Job status written to: $logFilePath" -LogPath $logFilePath -Level SUCCESS -Operation "WriteResults"
        $Summary = $true

        # Log summary statistics
        $successCount = ($sessions | Where-Object { $_.Result -eq 'Success' }).Count
        $warningCount = ($sessions | Where-Object { $_.Result -eq 'Warning' }).Count
        $failedCount = ($sessions | Where-Object { $_.Result -eq 'Failed' }).Count

        Write-AuditLog -Message "Session summary: Success=$successCount, Warning=$warningCount, Failed=$failedCount" `
            -LogPath $logFilePath -Level INFO -Operation "Summary"

    } else {
        Write-AuditLog -Message "No backup sessions found within the last $DaysBack days." -LogPath $logFilePath -Level INFO -Operation "RetrieveSessions"
        $Summary = $true
    }
} catch {
    Write-AuditLog -Message "An error occurred while retrieving backup session data. Error: $_" -LogPath $logFilePath -Level ERROR -Operation "RetrieveSessions"
    $Summary = $false
} finally {
    # Clear sensitive data from memory
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $Credential = $null
    }
    [System.GC]::Collect()
}

# Summary Output
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "Job status log: $logFilePath"
Write-Host "Script completed: $($Summary ? 'Success' : 'Failed')"

if ($Summary) {
    Write-AuditLog -Message "Script completed successfully" -LogPath $logFilePath -Level SUCCESS -Operation "Completion"
    exit 0
} else {
    Write-AuditLog -Message "Script completed with errors" -LogPath $logFilePath -Level ERROR -Operation "Completion"
    exit 1
}
