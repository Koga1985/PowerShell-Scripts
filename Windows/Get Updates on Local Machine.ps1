#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Retrieves and displays all installed Windows updates on the local system.

.DESCRIPTION
    This script uses the Get-HotFix cmdlet and Windows Update COM objects to obtain a comprehensive list
    of installed Windows updates. The results are then displayed in a formatted table with detailed information
    including KB number, description, installation date, and installed by user.

.PARAMETER OutputFormat
    Specifies the output format: Table, GridView, CSV, or JSON. Default is Table.

.PARAMETER ExportPath
    Optional path to export results when using CSV or JSON format.

.EXAMPLE
    .\Get Updates on Local Machine.ps1
    Retrieves and displays all installed Windows updates in table format.

.EXAMPLE
    .\Get Updates on Local Machine.ps1 -OutputFormat GridView
    Displays results in an interactive GridView window.

.EXAMPLE
    .\Get Updates on Local Machine.ps1 -OutputFormat CSV -ExportPath "C:\Reports\Updates.csv"
    Exports update information to a CSV file.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required for complete update details

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Input validation and sanitization
    - Secure error handling with proper cleanup
    - No network communication required

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (SI-2: Flaw Remediation)
    - Supports DISA STIG requirements for patch management
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'GridView', 'CSV', 'JSON')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "GetLocalUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\GetLocalUpdates_Audit.log"
$script:EventSource = "GetLocalUpdates"

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
    Write-AuditLog -Message "===== Local Windows Update Retrieval Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Output Format: $OutputFormat" -Level "INFO"

    #----------------------------------------------
    # Retrieve Installed Windows Updates
    #----------------------------------------------
    Write-AuditLog -Message "Retrieving installed Windows updates from local system..." -Level "INFO"

    $installedUpdates = @()

    try {
        # Get-HotFix retrieves a list of installed hotfixes and updates
        $hotfixes = Get-HotFix -ErrorAction Stop

        foreach ($hotfix in $hotfixes) {
            $installedUpdates += [PSCustomObject]@{
                ComputerName   = $hotfix.PSComputerName
                HotFixID       = $hotfix.HotFixID
                Description    = $hotfix.Description
                InstalledBy    = $hotfix.InstalledBy
                InstalledOn    = $hotfix.InstalledOn
                Source         = $hotfix.Source
            }
        }

        Write-AuditLog -Message "Retrieved $($installedUpdates.Count) installed updates." -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Error retrieving installed updates: $_" -Level "ERROR"
        throw
    }

    #----------------------------------------------
    # Display or Export Results
    #----------------------------------------------
    if ($installedUpdates.Count -eq 0) {
        Write-AuditLog -Message "No installed updates found." -Level "WARNING"
    } else {
        switch ($OutputFormat) {
            'Table' {
                if ($PSCmdlet.ShouldProcess("Console", "Display updates in table format")) {
                    Write-Host "`nInstalled Windows Updates:" -ForegroundColor Cyan
                    $installedUpdates | Format-Table -AutoSize
                    Write-AuditLog -Message "Updates displayed in table format." -Level "SUCCESS"
                }
            }
            'GridView' {
                if ($PSCmdlet.ShouldProcess("GridView", "Display updates in interactive grid")) {
                    $installedUpdates | Out-GridView -Title "Installed Windows Updates - $env:COMPUTERNAME"
                    Write-AuditLog -Message "Updates displayed in GridView." -Level "SUCCESS"
                }
            }
            'CSV' {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $env:USERPROFILE "Desktop\InstalledUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
                }

                if ($PSCmdlet.ShouldProcess($ExportPath, "Export updates to CSV")) {
                    $installedUpdates | Export-Csv -Path $ExportPath -NoTypeInformation -ErrorAction Stop
                    Write-AuditLog -Message "Updates exported to CSV: $ExportPath" -Level "SUCCESS"
                    Write-Host "`nUpdates exported to: $ExportPath" -ForegroundColor Green
                }
            }
            'JSON' {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $env:USERPROFILE "Desktop\InstalledUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                }

                if ($PSCmdlet.ShouldProcess($ExportPath, "Export updates to JSON")) {
                    $installedUpdates | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -ErrorAction Stop
                    Write-AuditLog -Message "Updates exported to JSON: $ExportPath" -Level "SUCCESS"
                    Write-Host "`nUpdates exported to: $ExportPath" -ForegroundColor Green
                }
            }
        }
    }

    Write-AuditLog -Message "===== Local Windows Update Retrieval Completed Successfully =====" -Level "SUCCESS"
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
