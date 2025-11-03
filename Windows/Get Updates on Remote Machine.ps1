#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Retrieves and displays installed Windows updates from one or more remote computers.

.DESCRIPTION
    This script queries remote computers for installed Windows updates using secure WinRM/PowerShell remoting.
    It supports multiple output formats and can process multiple computers simultaneously with error handling
    for individual computer failures.

.PARAMETER ComputerName
    One or more computer names or IP addresses to query. Supports pipeline input.

.PARAMETER Credential
    PSCredential object for authentication. If not provided, current user credentials are used.

.PARAMETER OutputFormat
    Specifies the output format: Table, GridView, CSV, or JSON. Default is Table.

.PARAMETER ExportPath
    Optional path to export results when using CSV or JSON format.

.EXAMPLE
    .\Get Updates on Remote Machine.ps1 -ComputerName "Server01"
    Retrieves updates from Server01 using current credentials.

.EXAMPLE
    $cred = Get-Credential
    .\Get Updates on Remote Machine.ps1 -ComputerName "Server01","Server02" -Credential $cred -OutputFormat GridView
    Queries multiple servers with provided credentials and displays in GridView.

.EXAMPLE
    .\Get Updates on Remote Machine.ps1 -ComputerName "Server01" -OutputFormat CSV -ExportPath "C:\Reports\Updates.csv"
    Exports results to CSV file.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - WinRM/PowerShell remoting enabled on target computers
      - Network connectivity to target computers

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Secure credential handling (PSCredential)
    - Input validation and sanitization
    - Secure error handling with proper cleanup
    - Encrypted remoting via WinRM

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (SI-2: Flaw Remediation, AC-17: Remote Access)
    - Supports DISA STIG requirements for patch management and secure remote access
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,

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
$transcriptPath = Join-Path $env:TEMP "GetRemoteUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\GetRemoteUpdates_Audit.log"
$script:EventSource = "GetRemoteUpdates"

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
    Write-AuditLog -Message "===== Remote Windows Update Retrieval Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Target Computers: $($ComputerName -join ', ')" -Level "INFO"
    Write-AuditLog -Message "Output Format: $OutputFormat" -Level "INFO"

    $allResults = @()
    $successCount = 0
    $failureCount = 0

    #----------------------------------------------
    # Process Each Remote Computer
    #----------------------------------------------
    foreach ($computer in $ComputerName) {
        Write-AuditLog -Message "Processing computer: $computer" -Level "INFO"

        if ($PSCmdlet.ShouldProcess($computer, "Retrieve installed Windows updates")) {
            try {
                # Test connectivity first
                if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                    Write-AuditLog -Message "Unable to reach computer: $computer" -Level "WARNING"
                    $failureCount++
                    continue
                }

                # Prepare Invoke-Command parameters
                $invokeParams = @{
                    ComputerName = $computer
                    ErrorAction  = 'Stop'
                    ScriptBlock  = {
                        Get-HotFix | Select-Object -Property `
                            @{Name='ComputerName';Expression={$env:COMPUTERNAME}},
                            HotFixID,
                            Description,
                            InstalledBy,
                            InstalledOn
                    }
                }

                # Add credential if provided
                if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                    $invokeParams['Credential'] = $Credential
                    Write-AuditLog -Message "Using provided credentials for $computer" -Level "INFO"
                }

                # Execute remote query
                $updates = Invoke-Command @invokeParams

                if ($updates) {
                    $allResults += $updates
                    Write-AuditLog -Message "Successfully retrieved $($updates.Count) updates from $computer" -Level "SUCCESS"
                    $successCount++
                } else {
                    Write-AuditLog -Message "No updates found on $computer" -Level "WARNING"
                    $successCount++
                }

            } catch {
                Write-AuditLog -Message "Error querying $computer : $_" -Level "ERROR"
                $failureCount++
            }
        }
    }

    #----------------------------------------------
    # Display Results Summary
    #----------------------------------------------
    Write-AuditLog -Message "Query Summary: $successCount successful, $failureCount failed" -Level "INFO"
    Write-AuditLog -Message "Total updates retrieved: $($allResults.Count)" -Level "INFO"

    #----------------------------------------------
    # Display or Export Results
    #----------------------------------------------
    if ($allResults.Count -eq 0) {
        Write-AuditLog -Message "No updates retrieved from any computer." -Level "WARNING"
    } else {
        switch ($OutputFormat) {
            'Table' {
                if ($PSCmdlet.ShouldProcess("Console", "Display updates in table format")) {
                    Write-Host "`nInstalled Windows Updates:" -ForegroundColor Cyan
                    $allResults | Format-Table -AutoSize
                    Write-AuditLog -Message "Updates displayed in table format." -Level "SUCCESS"
                }
            }
            'GridView' {
                if ($PSCmdlet.ShouldProcess("GridView", "Display updates in interactive grid")) {
                    $allResults | Out-GridView -Title "Installed Windows Updates - Remote Computers"
                    Write-AuditLog -Message "Updates displayed in GridView." -Level "SUCCESS"
                }
            }
            'CSV' {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $env:USERPROFILE "Desktop\RemoteUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
                }

                if ($PSCmdlet.ShouldProcess($ExportPath, "Export updates to CSV")) {
                    $allResults | Export-Csv -Path $ExportPath -NoTypeInformation -ErrorAction Stop
                    Write-AuditLog -Message "Updates exported to CSV: $ExportPath" -Level "SUCCESS"
                    Write-Host "`nUpdates exported to: $ExportPath" -ForegroundColor Green
                }
            }
            'JSON' {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $env:USERPROFILE "Desktop\RemoteUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                }

                if ($PSCmdlet.ShouldProcess($ExportPath, "Export updates to JSON")) {
                    $allResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -ErrorAction Stop
                    Write-AuditLog -Message "Updates exported to JSON: $ExportPath" -Level "SUCCESS"
                    Write-Host "`nUpdates exported to: $ExportPath" -ForegroundColor Green
                }
            }
        }
    }

    Write-AuditLog -Message "===== Remote Windows Update Retrieval Completed Successfully =====" -Level "SUCCESS"
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

    # Clear sensitive data
    if (Test-Path variable:Credential) {
        Remove-Variable -Name Credential -Force -ErrorAction SilentlyContinue
    }
}
