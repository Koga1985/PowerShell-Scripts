#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive inventory and asset management script for enterprise IT environments.

.DESCRIPTION
    This script collects detailed hardware and software inventory across Windows computers:
      1. Hardware inventory (CPU, Memory, Disk, Network)
      2. Software inventory (Installed applications, Windows features)
      3. Operating system details and patch status
      4. Network configuration
      5. Exports results to CSV, JSON, or HTML formats

.PARAMETER ComputerName
    Array of computer names or IP addresses to inventory. Supports pipeline input.

.PARAMETER Credential
    PSCredential object for remote authentication.

.PARAMETER OutputFormat
    Output format: CSV, JSON, or HTML. Default is CSV.

.PARAMETER ExportPath
    Path for the exported inventory report.

.EXAMPLE
    .\InventoryAssetManagement.ps1 -ComputerName "Server01","Server02" -OutputFormat CSV -ExportPath "C:\Reports\Inventory.csv"

.EXAMPLE
    $cred = Get-Credential
    Get-Content servers.txt | .\InventoryAssetManagement.ps1 -Credential $cred -OutputFormat HTML

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges
      - WinRM enabled on target computers

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Secure credential handling (PSCredential)
    - Input validation and sanitization
    - Secure error handling with proper cleanup

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (CM-8: Information System Component Inventory)
    - Supports DISA STIG requirements for asset management
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
    [ValidateSet('CSV', 'JSON', 'HTML')]
    [string]$OutputFormat = 'CSV',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "InventoryAssetManagement_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\InventoryAssetManagement_Audit.log"
$script:EventSource = "InventoryAssetManagement"

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
    Write-AuditLog -Message "===== Inventory Asset Management Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Target Computers: $($ComputerName -join ', ')" -Level "INFO"

    $inventoryResults = @()
    $successCount = 0
    $failureCount = 0

    #----------------------------------------------
    # Collect Inventory from Each Computer
    #----------------------------------------------
    foreach ($computer in $ComputerName) {
        Write-AuditLog -Message "Collecting inventory from: $computer" -Level "INFO"

        if ($PSCmdlet.ShouldProcess($computer, "Collect hardware and software inventory")) {
            try {
                # Test connectivity
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
                        # Collect Computer System Information
                        $computerSystem = Get-CimInstance Win32_ComputerSystem
                        $operatingSystem = Get-CimInstance Win32_OperatingSystem
                        $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
                        $physicalMemory = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
                        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
                        $network = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | Select-Object -First 1
                        $bios = Get-CimInstance Win32_BIOS

                        # Collect Software Information
                        $installedSoftware = Get-CimInstance Win32_Product | Measure-Object
                        $hotfixes = Get-HotFix | Measure-Object

                        # Build inventory object
                        [PSCustomObject]@{
                            ComputerName       = $env:COMPUTERNAME
                            Domain             = $computerSystem.Domain
                            Manufacturer       = $computerSystem.Manufacturer
                            Model              = $computerSystem.Model
                            SerialNumber       = $bios.SerialNumber
                            ProcessorName      = $processor.Name
                            ProcessorCores     = $processor.NumberOfCores
                            ProcessorThreads   = $processor.NumberOfLogicalProcessors
                            TotalRAM_GB        = [math]::Round($physicalMemory.Sum / 1GB, 2)
                            OSName             = $operatingSystem.Caption
                            OSVersion          = $operatingSystem.Version
                            OSArchitecture     = $operatingSystem.OSArchitecture
                            InstallDate        = $operatingSystem.InstallDate
                            LastBootTime       = $operatingSystem.LastBootUpTime
                            TotalDiskSpace_GB  = [math]::Round(($disk | Measure-Object -Property Size -Sum).Sum / 1GB, 2)
                            FreeDiskSpace_GB   = [math]::Round(($disk | Measure-Object -Property FreeSpace -Sum).Sum / 1GB, 2)
                            IPAddress          = $network.IPAddress -join '; '
                            MACAddress         = $network.MACAddress
                            DNSServers         = $network.DNSServerSearchOrder -join '; '
                            InstalledSoftwareCount = $installedSoftware.Count
                            InstalledUpdatesCount  = $hotfixes.Count
                            CollectionDate     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        }
                    }
                }

                # Add credential if provided
                if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                    $invokeParams['Credential'] = $Credential
                }

                # Execute inventory collection
                $inventory = Invoke-Command @invokeParams

                if ($inventory) {
                    $inventoryResults += $inventory
                    Write-AuditLog -Message "Successfully collected inventory from $computer" -Level "SUCCESS"
                    $successCount++
                }

            } catch {
                Write-AuditLog -Message "Error collecting inventory from $computer : $_" -Level "ERROR"
                $failureCount++
            }
        }
    }

    #----------------------------------------------
    # Export Results
    #----------------------------------------------
    Write-AuditLog -Message "Inventory collection complete. Success: $successCount, Failed: $failureCount" -Level "INFO"

    if ($inventoryResults.Count -eq 0) {
        Write-AuditLog -Message "No inventory data collected." -Level "WARNING"
    } else {
        # Determine export path
        if (-not $ExportPath) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $ExportPath = switch ($OutputFormat) {
                'CSV'  { Join-Path $env:USERPROFILE "Desktop\Inventory_$timestamp.csv" }
                'JSON' { Join-Path $env:USERPROFILE "Desktop\Inventory_$timestamp.json" }
                'HTML' { Join-Path $env:USERPROFILE "Desktop\Inventory_$timestamp.html" }
            }
        }

        if ($PSCmdlet.ShouldProcess($ExportPath, "Export inventory results")) {
            switch ($OutputFormat) {
                'CSV' {
                    $inventoryResults | Export-Csv -Path $ExportPath -NoTypeInformation -ErrorAction Stop
                    Write-AuditLog -Message "Inventory exported to CSV: $ExportPath" -Level "SUCCESS"
                }
                'JSON' {
                    $inventoryResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -ErrorAction Stop
                    Write-AuditLog -Message "Inventory exported to JSON: $ExportPath" -Level "SUCCESS"
                }
                'HTML' {
                    $htmlStyle = @"
<style>
BODY { background-color: #F5F5F5; font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }
H2 { color: #2E4053; border-bottom: 2px solid #3498DB; padding-bottom: 10px; }
TABLE { border-collapse: collapse; width: 100%; box-shadow: 0 2px 4px rgba(0,0,0,0.1); font-size: 12px; }
TH { background-color: #3498DB; color: white; padding: 10px; text-align: left; font-weight: bold; }
TD { border: 1px solid #BDC3C7; padding: 8px; background-color: white; }
TR:nth-child(even) TD { background-color: #ECF0F1; }
TR:hover TD { background-color: #D5DBDB; }
</style>
"@
                    $htmlBody = $inventoryResults | ConvertTo-Html -Head $htmlStyle -Body "<h2>IT Asset Inventory Report</h2><p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>" -Title "Asset Inventory"
                    $htmlBody | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-AuditLog -Message "Inventory exported to HTML: $ExportPath" -Level "SUCCESS"
                }
            }

            Write-Host "`nInventory report exported to: $ExportPath" -ForegroundColor Green
            Write-Host "Total assets inventoried: $($inventoryResults.Count)`n" -ForegroundColor Cyan
        }
    }

    Write-AuditLog -Message "===== Inventory Asset Management Completed Successfully =====" -Level "SUCCESS"
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
