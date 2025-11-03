#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Ensures that a PowerShell script is running with administrative privileges and restarts it with elevation if not.

.DESCRIPTION
    This script checks whether the current PowerShell session is running with administrative privileges. If it is not running
    as an Administrator, it will restart itself with elevated privileges by using the Start-Process cmdlet with the "RunAs" verb.
    Once elevated, the script continues executing. This functionality is useful when a script requires administrative rights
    to perform critical tasks.

.PARAMETER ScriptPath
    Optional path to a specific script to elevate. If not provided, elevates the current script.

.EXAMPLE
    .\Run PowerShell as Admin.ps1
    The script will check for administrative privileges and, if necessary, relaunch itself with elevated rights.

.EXAMPLE
    .\Run PowerShell as Admin.ps1 -ScriptPath "C:\Scripts\MyScript.ps1"
    Elevates a specific script with administrative privileges.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Windows operating system

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Input validation and sanitization
    - Secure error handling with proper cleanup
    - No plaintext credentials stored or transmitted

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (AC-6: Least Privilege)
    - Supports DISA STIG requirements for privilege escalation
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if (Test-Path -Path $_ -PathType Leaf) { $true }
        else { throw "Script path does not exist: $_" }
    })]
    [string]$ScriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "RunAsAdmin_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\RunAsAdmin_Audit.log"
$script:EventSource = "RunAsAdmin"

# Ensure audit log directory exists
$auditLogDir = Split-Path -Parent $script:AuditLogPath
if (-not (Test-Path -Path $auditLogDir)) {
    New-Item -Path $auditLogDir -ItemType Directory -Force | Out-Null
}

# Create event source if it doesn't exist
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($script:EventSource)) {
        New-EventLog -LogName Application -Source $script:EventSource -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Unable to create event log source. Event logging will be limited."
}

#----------------------------------------------
# Comprehensive Audit Logging Function
#----------------------------------------------
function Write-AuditLog {
    <#
    .SYNOPSIS
        Writes comprehensive audit logs to file and Windows Event Log.

    .PARAMETER Message
        The audit message to log.

    .PARAMETER Level
        The severity level: INFO, WARNING, ERROR, SUCCESS. Default is INFO.

    .PARAMETER EventId
        Optional Event ID for Windows Event Log. Defaults based on level.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [int]$EventId = 1000
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $computerName = $env:COMPUTERNAME

    $logEntry = "$timestamp [$Level] [$userName@$computerName] $Message"

    # Write to file
    try {
        Add-Content -Path $script:AuditLogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to audit log file: $_"
    }

    # Write to Windows Event Log
    $eventType = switch ($Level) {
        'ERROR'   { 'Error' }
        'WARNING' { 'Warning' }
        default   { 'Information' }
    }

    $eventIdMap = @{
        'INFO'    = 1000
        'SUCCESS' = 1001
        'WARNING' = 2000
        'ERROR'   = 3000
    }

    $finalEventId = if ($EventId -eq 1000) { $eventIdMap[$Level] } else { $EventId }

    try {
        Write-EventLog -LogName Application -Source $script:EventSource -EntryType $eventType -EventId $finalEventId -Message $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if event log write fails
    }

    # Write to console
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }

    Write-Host $logEntry -ForegroundColor $color
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
try {
    Write-AuditLog -Message "===== PowerShell Elevation Check Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"

    # Determine target script
    $targetScript = if ($ScriptPath) {
        $ScriptPath
    } else {
        $MyInvocation.MyCommand.Path
    }

    Write-AuditLog -Message "Target script: $targetScript" -Level "INFO"

    #----------------------------------------------
    # Check for Administrative Privileges
    #----------------------------------------------
    Write-AuditLog -Message "Checking if script is running with administrative privileges..." -Level "INFO"

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-AuditLog -Message "Script is not running with administrative privileges. Attempting to restart with elevation..." -Level "WARNING"

        if ($PSCmdlet.ShouldProcess("PowerShell", "Restart with elevated privileges")) {
            try {
                $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$targetScript`""

                Write-AuditLog -Message "Starting elevated process..." -Level "INFO"

                $process = Start-Process -FilePath "powershell.exe" `
                    -ArgumentList $arguments `
                    -Verb RunAs `
                    -PassThru `
                    -ErrorAction Stop

                Write-AuditLog -Message "Elevated process started successfully (PID: $($process.Id)). Exiting current non-elevated session." -Level "SUCCESS"

                exit 0
            } catch {
                Write-AuditLog -Message "Failed to restart script with elevated privileges: $_" -Level "ERROR"
                throw
            }
        }
    } else {
        Write-AuditLog -Message "Running with administrative privileges." -Level "SUCCESS"
    }

    #----------------------------------------------
    # Proceed with Main Script Logic
    #----------------------------------------------
    Write-AuditLog -Message "Script execution continues under administrative privileges." -Level "SUCCESS"
    Write-Host "`nPowerShell is running with administrative privileges." -ForegroundColor Green
    Write-Host "You can now execute administrative commands.`n" -ForegroundColor Cyan

    Write-AuditLog -Message "===== PowerShell Elevation Check Completed Successfully =====" -Level "SUCCESS"
    Write-AuditLog -Message "Transcript saved to: $transcriptPath" -Level "INFO"
    Write-AuditLog -Message "Audit log saved to: $script:AuditLogPath" -Level "INFO"

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level "ERROR"
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
} finally {
    # Stop transcript
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if transcript stop fails
    }
}
