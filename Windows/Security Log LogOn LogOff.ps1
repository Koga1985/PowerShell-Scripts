#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Retrieves logon and logoff events from a specified computer's Security event log.

.DESCRIPTION
    This script performs comprehensive logon activity analysis by:
      1. Querying Security event log for logon (4624), logoff (4647), and failed logon (4625) events
      2. Filtering events by date range and success/failure status
      3. Parsing event data including user, IP address, and logon type
      4. Outputting results in multiple formats: Table, GridView, HTML, or JSON

.PARAMETER ComputerName
    Target computer name or IP. Defaults to local computer if not specified.

.PARAMETER StartDate
    Start date for log analysis. Defaults to 30 days ago.

.PARAMETER EndDate
    End date for log analysis. Defaults to current date/time.

.PARAMETER FailedOnly
    If specified, only failed logon attempts are returned.

.PARAMETER OutputFormat
    Output format: Table, GridView, HTML, or JSON. Default is Table.

.PARAMETER ExportPath
    Optional path for exported HTML or JSON output.

.EXAMPLE
    .\Security Log LogOn LogOff.ps1
    Retrieves all logon/logoff events from local computer for the last 30 days.

.EXAMPLE
    .\Security Log LogOn LogOff.ps1 -ComputerName "Server01" -FailedOnly -OutputFormat HTML -ExportPath "C:\Reports\FailedLogins.html"
    Exports failed login attempts from Server01 to an HTML report.

.EXAMPLE
    .\Security Log LogOn LogOff.ps1 -StartDate "01/01/2025" -EndDate "01/31/2025" -OutputFormat GridView
    Displays January 2025 logon activity in an interactive grid.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - Access to Security event log on target computer

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Input validation and sanitization
    - Secure error handling with proper cleanup
    - Read-only security log access (no modifications)

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (AU-2, AU-3, AU-6: Audit Events, Content, Review)
    - Supports DISA STIG requirements for security log monitoring
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [datetime]$StartDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [datetime]$EndDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [switch]$FailedOnly,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'GridView', 'HTML', 'JSON')]
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
$transcriptPath = Join-Path $env:TEMP "SecurityLogAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\SecurityLogAnalysis_Audit.log"
$script:EventSource = "SecurityLogAnalysis"

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
    Write-AuditLog -Message "===== Security Log Analysis Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Target Computer: $ComputerName" -Level "INFO"
    Write-AuditLog -Message "Date Range: $StartDate to $EndDate" -Level "INFO"
    Write-AuditLog -Message "Failed Only: $FailedOnly" -Level "INFO"
    Write-AuditLog -Message "Output Format: $OutputFormat" -Level "INFO"

    #----------------------------------------------
    # Validate Date Range
    #----------------------------------------------
    if ($StartDate -gt $EndDate) {
        throw "Start date cannot be after end date."
    }

    #----------------------------------------------
    # Create DataTable for Results
    #----------------------------------------------
    Write-AuditLog -Message "Creating data structure for logon/logoff events..." -Level "INFO"

    $logonActivityTable = New-Object System.Collections.ArrayList

    #----------------------------------------------
    # Query Security Event Log
    #----------------------------------------------
    Write-AuditLog -Message "Querying Security event log on $ComputerName from $StartDate to $EndDate..." -Level "INFO"

    try {
        # Use Get-WinEvent for better performance and compatibility
        $filterHashTable = @{
            LogName   = 'Security'
            StartTime = $StartDate
            EndTime   = $EndDate
        }

        if ($ComputerName -ne $env:COMPUTERNAME) {
            $filterHashTable['ComputerName'] = $ComputerName
        }

        # Get relevant event IDs: 4624 (Logon), 4625 (Failed Logon), 4647 (Logoff)
        if ($FailedOnly) {
            $filterHashTable['ID'] = 4625
        } else {
            $filterHashTable['ID'] = 4624, 4625, 4647
        }

        $events = Get-WinEvent -FilterHashtable $filterHashTable -ErrorAction Stop

        Write-AuditLog -Message "Retrieved $($events.Count) events from Security log." -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Error retrieving event log data: $_" -Level "ERROR"
        throw
    }

    #----------------------------------------------
    # Process Events
    #----------------------------------------------
    Write-AuditLog -Message "Processing events..." -Level "INFO"

    foreach ($event in $events) {
        try {
            $eventXML = [xml]$event.ToXml()
            $eventData = $eventXML.Event.EventData.Data

            switch ($event.Id) {
                4624 {
                    # Successful Logon
                    $logonType = $eventData | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'
                    $targetUserName = $eventData | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'
                    $ipAddress = $eventData | Where-Object { $_.Name -eq 'IpAddress' } | Select-Object -ExpandProperty '#text'

                    # Only process interactive logons (Type 2, 10, 11)
                    if ($logonType -in @('2', '10', '11')) {
                        $logonTypeDescription = switch ($logonType) {
                            '2'  { 'Interactive' }
                            '10' { 'RemoteInteractive' }
                            '11' { 'CachedInteractive' }
                        }

                        [void]$logonActivityTable.Add([PSCustomObject]@{
                            TimeGenerated = $event.TimeCreated
                            EventType     = 'Logon'
                            Status        = 'Success'
                            LogonType     = $logonTypeDescription
                            User          = $targetUserName
                            IPAddress     = if ($ipAddress -and $ipAddress -ne '-') { $ipAddress } else { 'Local' }
                            ComputerName  = $ComputerName
                        })
                    }
                }
                4625 {
                    # Failed Logon
                    $logonType = $eventData | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'
                    $targetUserName = $eventData | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'
                    $ipAddress = $eventData | Where-Object { $_.Name -eq 'IpAddress' } | Select-Object -ExpandProperty '#text'
                    $failureReason = $eventData | Where-Object { $_.Name -eq 'SubStatus' } | Select-Object -ExpandProperty '#text'

                    $logonTypeDescription = switch ($logonType) {
                        '2'  { 'Interactive' }
                        '10' { 'RemoteInteractive' }
                        '11' { 'CachedInteractive' }
                        default { "Type $logonType" }
                    }

                    [void]$logonActivityTable.Add([PSCustomObject]@{
                        TimeGenerated = $event.TimeCreated
                        EventType     = 'Logon'
                        Status        = 'Failure'
                        LogonType     = $logonTypeDescription
                        User          = $targetUserName
                        IPAddress     = if ($ipAddress -and $ipAddress -ne '-') { $ipAddress } else { 'Local' }
                        ComputerName  = $ComputerName
                    })
                }
                4647 {
                    # User Initiated Logoff
                    $targetUserName = $eventData | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'

                    [void]$logonActivityTable.Add([PSCustomObject]@{
                        TimeGenerated = $event.TimeCreated
                        EventType     = 'Logoff'
                        Status        = 'Success'
                        LogonType     = 'N/A'
                        User          = $targetUserName
                        IPAddress     = 'N/A'
                        ComputerName  = $ComputerName
                    })
                }
            }
        } catch {
            Write-AuditLog -Message "Error processing event ID $($event.Id): $_" -Level "WARNING"
        }
    }

    Write-AuditLog -Message "Processed $($logonActivityTable.Count) logon/logoff events." -Level "SUCCESS"

    #----------------------------------------------
    # Output Results
    #----------------------------------------------
    if ($logonActivityTable.Count -eq 0) {
        Write-AuditLog -Message "No matching events found." -Level "WARNING"
    } else {
        switch ($OutputFormat) {
            'Table' {
                if ($PSCmdlet.ShouldProcess("Console", "Display events in table format")) {
                    Write-Host "`nLogon Activity Report:" -ForegroundColor Cyan
                    $logonActivityTable | Sort-Object TimeGenerated -Descending | Format-Table -AutoSize
                    Write-AuditLog -Message "Events displayed in table format." -Level "SUCCESS"
                }
            }
            'GridView' {
                if ($PSCmdlet.ShouldProcess("GridView", "Display events in interactive grid")) {
                    $logonActivityTable | Sort-Object TimeGenerated -Descending | Out-GridView -Title "Logon Activity Report - $ComputerName"
                    Write-AuditLog -Message "Events displayed in GridView." -Level "SUCCESS"
                }
            }
            'HTML' {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $env:USERPROFILE "Desktop\LogonActivity_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
                }

                if ($PSCmdlet.ShouldProcess($ExportPath, "Export events to HTML")) {
                    $htmlStyle = @"
<style>
BODY { background-color: #F5F5F5; font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }
H2 { color: #2E4053; border-bottom: 2px solid #3498DB; padding-bottom: 10px; }
TABLE { border-collapse: collapse; width: 100%; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
TH { background-color: #3498DB; color: white; padding: 12px; text-align: left; font-weight: bold; }
TD { border: 1px solid #BDC3C7; padding: 10px; background-color: white; }
TR:nth-child(even) TD { background-color: #ECF0F1; }
TR:hover TD { background-color: #D5DBDB; }
.success { color: #27AE60; font-weight: bold; }
.failure { color: #E74C3C; font-weight: bold; }
</style>
"@
                    $htmlBody = $logonActivityTable | Sort-Object TimeGenerated -Descending |
                        ConvertTo-Html -Head $htmlStyle -Body "<h2>Logon Activity Report - $ComputerName</h2><p>Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>" -Title "Logon Activity"

                    $htmlBody | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-AuditLog -Message "HTML report generated: $ExportPath" -Level "SUCCESS"
                    Write-Host "`nReport exported to: $ExportPath" -ForegroundColor Green
                }
            }
            'JSON' {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $env:USERPROFILE "Desktop\LogonActivity_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                }

                if ($PSCmdlet.ShouldProcess($ExportPath, "Export events to JSON")) {
                    $logonActivityTable | Sort-Object TimeGenerated -Descending | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -ErrorAction Stop
                    Write-AuditLog -Message "JSON report generated: $ExportPath" -Level "SUCCESS"
                    Write-Host "`nReport exported to: $ExportPath" -ForegroundColor Green
                }
            }
        }
    }

    Write-AuditLog -Message "===== Security Log Analysis Completed Successfully =====" -Level "SUCCESS"
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
