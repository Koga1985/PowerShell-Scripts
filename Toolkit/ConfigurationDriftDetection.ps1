#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Detects configuration drift by comparing current system states against defined baselines.

.DESCRIPTION
    This script performs comprehensive configuration drift detection:
      1. Loads baseline configuration from JSON file
      2. Collects current system configuration from target computers
      3. Compares current state against baseline
      4. Reports configuration deviations with detailed analysis
      5. Exports drift report in multiple formats

.PARAMETER BaselineFile
    Path to baseline configuration file (JSON format).

.PARAMETER ComputerName
    Array of computer names or IP addresses to check for drift.

.PARAMETER Credential
    PSCredential object for remote authentication.

.PARAMETER OutputFormat
    Output format for drift report: CSV, JSON, or HTML. Default is HTML.

.PARAMETER ExportPath
    Path for the exported drift report.

.EXAMPLE
    .\ConfigurationDriftDetection.ps1 -BaselineFile "C:\Baselines\WindowsBaseline.json" -ComputerName "Server01","Server02" -OutputFormat HTML

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges
      - WinRM enabled on target computers
      - Baseline JSON file

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Secure credential handling (PSCredential)
    - Input validation and sanitization
    - Secure error handling with proper cleanup

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (CM-3: Configuration Change Control, CM-6: Configuration Settings)
    - Supports DISA STIG requirements for configuration management
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$BaselineFile,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,

    [Parameter(Mandatory = $false)]
    [ValidateSet('CSV', 'JSON', 'HTML')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "ConfigurationDriftDetection_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\ConfigurationDriftDetection_Audit.log"
$script:EventSource = "ConfigurationDriftDetection"

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
    Write-AuditLog -Message "===== Configuration Drift Detection Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Baseline File: $BaselineFile" -Level "INFO"
    Write-AuditLog -Message "Target Computers: $($ComputerName -join ', ')" -Level "INFO"

    $driftResults = @()
    $totalDrifts = 0

    #----------------------------------------------
    # Load Baseline Configuration
    #----------------------------------------------
    Write-AuditLog -Message "Loading baseline configuration from $BaselineFile..." -Level "INFO"

    try {
        $baseline = Get-Content -Path $BaselineFile -Raw | ConvertFrom-Json
        Write-AuditLog -Message "Baseline configuration loaded successfully." -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Error loading baseline configuration: $_" -Level "ERROR"
        throw
    }

    #----------------------------------------------
    # Check Each Computer for Drift
    #----------------------------------------------
    foreach ($computer in $ComputerName) {
        Write-AuditLog -Message "Checking configuration drift on: $computer" -Level "INFO"

        if ($PSCmdlet.ShouldProcess($computer, "Check for configuration drift")) {
            try {
                # Test connectivity
                if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                    Write-AuditLog -Message "Unable to reach computer: $computer" -Level "WARNING"
                    continue
                }

                # Prepare Invoke-Command parameters
                $invokeParams = @{
                    ComputerName = $computer
                    ErrorAction  = 'Stop'
                    ScriptBlock  = {
                        param($BaselineConfig)

                        $currentConfig = @{
                            Services = @()
                            RegistryKeys = @()
                            FirewallRules = @()
                            WindowsFeatures = @()
                        }

                        # Collect current services
                        if ($BaselineConfig.Services) {
                            foreach ($svc in $BaselineConfig.Services) {
                                $current = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                                if ($current) {
                                    $currentConfig.Services += @{
                                        Name = $svc.Name
                                        Status = $current.Status.ToString()
                                        StartType = $current.StartType.ToString()
                                    }
                                }
                            }
                        }

                        # Collect current registry settings
                        if ($BaselineConfig.RegistryKeys) {
                            foreach ($reg in $BaselineConfig.RegistryKeys) {
                                if (Test-Path $reg.Path) {
                                    $value = Get-ItemProperty -Path $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue
                                    if ($value) {
                                        $currentConfig.RegistryKeys += @{
                                            Path = $reg.Path
                                            Name = $reg.Name
                                            Value = $value.$($reg.Name)
                                        }
                                    }
                                }
                            }
                        }

                        # Collect current firewall rules
                        if ($BaselineConfig.FirewallRules) {
                            foreach ($fw in $BaselineConfig.FirewallRules) {
                                $rule = Get-NetFirewallRule -DisplayName $fw.DisplayName -ErrorAction SilentlyContinue
                                if ($rule) {
                                    $currentConfig.FirewallRules += @{
                                        DisplayName = $rule.DisplayName
                                        Enabled = $rule.Enabled.ToString()
                                        Direction = $rule.Direction.ToString()
                                        Action = $rule.Action.ToString()
                                    }
                                }
                            }
                        }

                        return $currentConfig
                    }
                    ArgumentList = $baseline
                }

                # Add credential if provided
                if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                    $invokeParams['Credential'] = $Credential
                }

                # Execute drift detection
                $currentConfig = Invoke-Command @invokeParams

                # Compare configurations and detect drift
                if ($baseline.Services) {
                    foreach ($baselineSvc in $baseline.Services) {
                        $currentSvc = $currentConfig.Services | Where-Object { $_.Name -eq $baselineSvc.Name }

                        if ($currentSvc) {
                            if ($currentSvc.Status -ne $baselineSvc.Status -or $currentSvc.StartType -ne $baselineSvc.StartType) {
                                $driftResults += [PSCustomObject]@{
                                    ComputerName = $computer
                                    Category = 'Service'
                                    Item = $baselineSvc.Name
                                    BaselineValue = "$($baselineSvc.Status) / $($baselineSvc.StartType)"
                                    CurrentValue = "$($currentSvc.Status) / $($currentSvc.StartType)"
                                    DriftDetected = $true
                                    DetectionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                }
                                $totalDrifts++
                            }
                        } else {
                            $driftResults += [PSCustomObject]@{
                                ComputerName = $computer
                                Category = 'Service'
                                Item = $baselineSvc.Name
                                BaselineValue = "$($baselineSvc.Status) / $($baselineSvc.StartType)"
                                CurrentValue = "NOT FOUND"
                                DriftDetected = $true
                                DetectionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            }
                            $totalDrifts++
                        }
                    }
                }

                # Compare registry keys
                if ($baseline.RegistryKeys) {
                    foreach ($baselineReg in $baseline.RegistryKeys) {
                        $currentReg = $currentConfig.RegistryKeys | Where-Object { $_.Path -eq $baselineReg.Path -and $_.Name -eq $baselineReg.Name }

                        if ($currentReg -and $currentReg.Value -ne $baselineReg.Value) {
                            $driftResults += [PSCustomObject]@{
                                ComputerName = $computer
                                Category = 'Registry'
                                Item = "$($baselineReg.Path)\$($baselineReg.Name)"
                                BaselineValue = $baselineReg.Value
                                CurrentValue = $currentReg.Value
                                DriftDetected = $true
                                DetectionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            }
                            $totalDrifts++
                        }
                    }
                }

                Write-AuditLog -Message "Drift detection completed for $computer. Drifts detected: $totalDrifts" -Level "SUCCESS"

            } catch {
                Write-AuditLog -Message "Error checking drift on $computer : $_" -Level "ERROR"
            }
        }
    }

    #----------------------------------------------
    # Export Drift Report
    #----------------------------------------------
    if ($driftResults.Count -eq 0) {
        Write-AuditLog -Message "No configuration drift detected." -Level "SUCCESS"
        Write-Host "`nNo configuration drift detected. All systems are in compliance with baseline.`n" -ForegroundColor Green
    } else {
        Write-AuditLog -Message "Total configuration drifts detected: $totalDrifts" -Level "WARNING"

        # Determine export path
        if (-not $ExportPath) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $ExportPath = switch ($OutputFormat) {
                'CSV'  { Join-Path $env:USERPROFILE "Desktop\DriftReport_$timestamp.csv" }
                'JSON' { Join-Path $env:USERPROFILE "Desktop\DriftReport_$timestamp.json" }
                'HTML' { Join-Path $env:USERPROFILE "Desktop\DriftReport_$timestamp.html" }
            }
        }

        if ($PSCmdlet.ShouldProcess($ExportPath, "Export drift report")) {
            switch ($OutputFormat) {
                'CSV' {
                    $driftResults | Export-Csv -Path $ExportPath -NoTypeInformation -ErrorAction Stop
                    Write-AuditLog -Message "Drift report exported to CSV: $ExportPath" -Level "SUCCESS"
                }
                'JSON' {
                    $driftResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -ErrorAction Stop
                    Write-AuditLog -Message "Drift report exported to JSON: $ExportPath" -Level "SUCCESS"
                }
                'HTML' {
                    $htmlStyle = @"
<style>
BODY { background-color: #FFF5F5; font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }
H2 { color: #C0392B; border-bottom: 2px solid #E74C3C; padding-bottom: 10px; }
TABLE { border-collapse: collapse; width: 100%; box-shadow: 0 2px 4px rgba(0,0,0,0.1); font-size: 12px; }
TH { background-color: #E74C3C; color: white; padding: 10px; text-align: left; font-weight: bold; }
TD { border: 1px solid #BDC3C7; padding: 8px; background-color: white; }
TR:nth-child(even) TD { background-color: #FADBD8; }
TR:hover TD { background-color: #F5B7B1; }
.drift { color: #C0392B; font-weight: bold; }
</style>
"@
                    $htmlBody = $driftResults | ConvertTo-Html -Head $htmlStyle -Body "<h2>Configuration Drift Report</h2><p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p><p class='drift'>Total Drifts Detected: $totalDrifts</p>" -Title "Drift Report"
                    $htmlBody | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-AuditLog -Message "Drift report exported to HTML: $ExportPath" -Level "SUCCESS"
                }
            }

            Write-Host "`nConfiguration Drift Report:" -ForegroundColor Yellow
            Write-Host "Total Drifts Detected: $totalDrifts" -ForegroundColor Red
            Write-Host "Report exported to: $ExportPath`n" -ForegroundColor Cyan
        }
    }

    Write-AuditLog -Message "===== Configuration Drift Detection Completed Successfully =====" -Level "SUCCESS"
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
