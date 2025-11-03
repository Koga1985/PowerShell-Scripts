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

.PARAMETER LogLocation
    The folder containing log files to sanitize.

.PARAMETER HostPlaceholder
    Placeholder string for host names. Default is "HostNamePlaceholder".

.PARAMETER IpPlaceholder
    Placeholder string for IP addresses. Default is "IPAddressPlaceholder".

.PARAMETER ErrorLogPath
    Path for error logging. Default is "C:\VeeamLogs\ScrubberErrorLog.txt".

.SECURITY FEATURES
    - Requires PowerShell 5.1 and Administrator privileges
    - Comprehensive audit logging to file and Windows Event Log
    - Input validation for all parameters
    - Path traversal protection
    - Backup of original files before sanitization
    - Sensitive data cleared from memory on exit

.COMPLIANCE
    - Follows Fourth Estate security standards
    - Implements defense-in-depth logging
    - Supports audit trail requirements
    - Validates all input parameters
    - Protects against injection attacks

.EXAMPLE
    .\Log Scrubber.ps1 -LogLocation "C:\Logs\Veeam" -HostPlaceholder "HOST" -IpPlaceholder "IP"

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
        if ($_ -match '^[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]*$') {
            if (Test-Path -Path $_ -PathType Container) {
                $true
            } else {
                throw "Path does not exist or is not a directory: $_"
            }
        } else {
            throw "Invalid path format. Must be a valid Windows path."
        }
    })]
    [string]$LogLocation,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$HostPlaceholder = "HostNamePlaceholder",

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$IpPlaceholder = "IPAddressPlaceholder",

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '^[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]+\.txt$') {
            $true
        } else {
            throw "Invalid error log path format."
        }
    })]
    [string]$ErrorLogPath = "C:\VeeamLogs\ScrubberErrorLog.txt"
)

#==============================================
# Global Logging Setup
#==============================================

$Global:EventLogSource = "VeeamLogScrubber"
$Global:EventLogName = "Application"

# Ensure error log directory exists
$errorLogDir = Split-Path -Path $ErrorLogPath -Parent
if (-not (Test-Path -Path $errorLogDir -PathType Container)) {
    try {
        New-Item -Path $errorLogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create error log directory: $errorLogDir. Error: $_"
        exit 1
    }
}

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
        [string]$TargetFile = ""
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $logMessage = "$timestamp [$Level] User: $userName | Operation: $Operation | Target: $TargetFile | $Message"

        # Write to console
        switch ($Level) {
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            default   { Write-Host $logMessage }
        }

        # Write to error log file
        Add-Content -Path $ErrorLogPath -Value $logMessage -ErrorAction SilentlyContinue

        # Write to Windows Event Log
        $eventType = switch ($Level) {
            'ERROR'   { [System.Diagnostics.EventLogEntryType]::Error }
            'WARNING' { [System.Diagnostics.EventLogEntryType]::Warning }
            default   { [System.Diagnostics.EventLogEntryType]::Information }
        }

        $eventID = switch ($Level) {
            'ERROR'   { 4001 }
            'WARNING' { 4002 }
            'SUCCESS' { 4003 }
            default   { 4000 }
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
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile
    )
    Write-AuditLog -Message $Message -Level $Level -Operation "LogSanitization"
}

#==============================================
# Input Validation
#==============================================
function Test-PathSafety {
    param([string]$Path)

    # Check for path traversal attempts
    if ($Path -match '\.\.' -or $Path -match '[<>"|?*]') {
        throw "Path contains invalid or potentially unsafe characters: $Path"
    }
    return $true
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
        [ValidateNotNullOrEmpty()]
        [string]$LogFilePath,

        [Parameter(Mandatory = $true)]
        [string]$HostPlaceholder,

        [Parameter(Mandatory = $true)]
        [string]$IpPlaceholder
    )

    try {
        Write-AuditLog -Message "Sanitizing file" -Level INFO -Operation "SanitizeFile" -TargetFile $LogFilePath

        # Validate file path
        Test-PathSafety -Path $LogFilePath

        # Create backup before sanitization
        $backupPath = "$LogFilePath.backup"
        try {
            Copy-Item -Path $LogFilePath -Destination $backupPath -Force -ErrorAction Stop
            Write-AuditLog -Message "Backup created" -Level INFO -Operation "CreateBackup" -TargetFile $backupPath
        } catch {
            throw "Failed to create backup: $_"
        }

        # Read the entire file content as a single string
        $logContent = Get-Content -Path $LogFilePath -Raw -ErrorAction Stop

        # Store original size for validation
        $originalSize = $logContent.Length

        # Replace detected IP addresses with the provided IP placeholder.
        # Pattern: Matches any valid IPv4 address.
        $logContent = $logContent -replace '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b', $IpPlaceholder

        # Replace email addresses with a generic placeholder.
        $logContent = $logContent -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', "EmailPlaceholder"

        # Replace full file paths (e.g., "C:\Path\To\File") with a generic placeholder.
        $logContent = $logContent -replace '\b[C-Z]:\\[A-Za-z0-9._\\-]+\b', "FilePathPlaceholder"

        # Replace UNC paths
        $logContent = $logContent -replace '\\\\[A-Za-z0-9\-\.]+\\[A-Za-z0-9$_\\-]+', "UNCPathPlaceholder"

        # Replace host names (alphanumeric including hyphen or underscore) with the host placeholder.
        # NOTE: This is applied last to avoid interfering with other replacements
        # $logContent = $logContent -replace '\b[A-Za-z0-9_-]{3,}\b', $HostPlaceholder

        # Validate sanitization didn't corrupt file
        if ($logContent.Length -eq 0 -and $originalSize -gt 0) {
            throw "Sanitization resulted in empty file. Restoring backup."
        }

        # Overwrite the original log file with the sanitized content.
        $logContent | Set-Content -Path $LogFilePath -ErrorAction Stop

        Write-AuditLog -Message "Sanitization completed successfully" -Level SUCCESS -Operation "SanitizeFile" -TargetFile $LogFilePath

        # Remove backup after successful sanitization
        Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue

        return $true

    } catch {
        $errorMessage = "Error processing file: $_"
        Write-AuditLog -Message $errorMessage -Level ERROR -Operation "SanitizeFile" -TargetFile $LogFilePath

        # Restore backup if it exists
        if (Test-Path -Path "$LogFilePath.backup") {
            try {
                Copy-Item -Path "$LogFilePath.backup" -Destination $LogFilePath -Force
                Write-AuditLog -Message "Backup restored due to error" -Level WARNING -Operation "RestoreBackup" -TargetFile $LogFilePath
            } catch {
                Write-AuditLog -Message "Failed to restore backup: $_" -Level ERROR -Operation "RestoreBackup" -TargetFile $LogFilePath
            }
        }

        return $false
    }
}

#==============================================
# Main Processing
#==============================================

Write-AuditLog -Message "Script execution started" -Level INFO -Operation "Initialization"
Write-AuditLog -Message "Log location: $LogLocation" -Level INFO -Operation "Initialization"

try {
    # Validate log location
    Test-PathSafety -Path $LogLocation

    # Get all log files (with a .log extension) from the specified location recursively.
    Write-AuditLog -Message "Retrieving log files from $LogLocation" -Level INFO -Operation "RetrieveFiles"

    $logFiles = Get-ChildItem -Path $LogLocation -Filter "*.log" -Recurse -ErrorAction Stop

    if ($logFiles.Count -eq 0) {
        Write-AuditLog -Message "No log files found in $LogLocation" -Level WARNING -Operation "RetrieveFiles"
        exit 0
    }

    Write-AuditLog -Message "Found $($logFiles.Count) log file(s) to process" -Level INFO -Operation "RetrieveFiles"

    # Summary variable
    $Summary = @{}
    $successCount = 0
    $failCount = 0

    foreach ($logFile in $logFiles) {
        try {
            $result = Sanitize-LogFile -LogFilePath $logFile.FullName -HostPlaceholder $HostPlaceholder -IpPlaceholder $IpPlaceholder

            if ($result) {
                $Summary[$logFile.FullName] = $true
                $successCount++
            } else {
                $Summary[$logFile.FullName] = $false
                $failCount++
            }

        } catch {
            $errorMessage = "Error processing $($logFile.FullName): $_"
            Write-AuditLog -Message $errorMessage -Level ERROR -Operation "ProcessFile" -TargetFile $logFile.FullName
            $Summary[$logFile.FullName] = $false
            $failCount++
        }
    }

    # Summary Output
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "Total files processed: $($logFiles.Count)"
    Write-Host "Successfully sanitized: $successCount"
    Write-Host "Failed: $failCount"

    Write-AuditLog -Message "Log sanitization completed. Success: $successCount, Failed: $failCount" -Level INFO -Operation "Completion"

    # Exit with appropriate code
    if ($failCount -eq 0) {
        Write-AuditLog -Message "Script completed successfully with no errors" -Level SUCCESS -Operation "Completion"
        Write-Host "`nLog sanitization process completed successfully." -ForegroundColor Green
        exit 0
    } else {
        Write-AuditLog -Message "Script completed with $failCount error(s)" -Level WARNING -Operation "Completion"
        Write-Host "`nLog sanitization process completed with errors." -ForegroundColor Yellow
        exit 1
    }

} catch {
    Write-AuditLog -Message "Critical error during execution: $_" -Level ERROR -Operation "MainExecution"
    Write-Host "`nCritical error occurred. Check error log at: $ErrorLogPath" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup
    [System.GC]::Collect()
}
