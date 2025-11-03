<#
.SYNOPSIS
    ITToolkit: Secure PowerShell toolkit for IT operations in Fourth Estate infrastructure.

.DESCRIPTION
    Advanced functions for system health, service management, log queries, connectivity, and more.
    All functions use robust error handling, input validation, comprehensive audit logging, and
    follow DoD/Fourth Estate security standards. Dot-source to import functions or use interactive menu.

.EXAMPLE
    # Import the toolkit into your session:
    . "C:\Scripts\ITToolkit.ps1"

    # Run a function:
    Get-SystemUptime

    # Or launch interactive menu:
    Show-ITToolkit

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for enhanced script reliability
    - Comprehensive input validation and sanitization
    - Audit logging to file and Windows Event Log
    - No hardcoded credentials or sensitive data
    - Path traversal prevention
    - Sanitized user inputs to prevent injection attacks

.COMPLIANCE
    - NIST SP 800-53 Rev 5: AU-2, AU-3, AU-12 (Audit and Accountability)
    - NIST SP 800-53 Rev 5: SI-10 (Input Validation)
    - DISA STIG PowerShell Security Technical Implementation Guide
    - DoD Fourth Estate security requirements
    - FedRAMP security controls

    Disclaimer: Scripts are provided as-is. Review and test for your environment and compliance needs.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Security Configuration
$Global:AuditLogPath = "$env:ProgramData\ITToolkit\Logs\audit.log"
$Global:EventLogSource = "ITToolkit"
$Global:EventLogName = "Application"

# Initialize audit logging
function Initialize-AuditLog {
    try {
        $logDir = Split-Path $Global:AuditLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        # Register event source if not exists
        if (-not ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource))) {
            New-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource
        }
    } catch {
        Write-Warning "Failed to initialize audit logging: $_"
    }
}

Initialize-AuditLog
#endregion

#region Security Functions
function Write-AuditLog {
    <#
    .SYNOPSIS
        Writes comprehensive audit logs to file and Windows Event Log.
    .PARAMETER Message
        The audit message to log.
    .PARAMETER Level
        Log level: INFO, WARNING, ERROR, SECURITY. Default is INFO.
    .PARAMETER Action
        The action being performed (e.g., "SystemQuery", "ServiceRestart").
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory=$false)]
        [string]$Action = 'General'
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $computerName = $env:COMPUTERNAME

        $auditEntry = "$timestamp | $computerName | $username | $Level | $Action | $Message"

        # Write to file
        Add-Content -Path $Global:AuditLogPath -Value $auditEntry -ErrorAction SilentlyContinue

        # Write to Windows Event Log
        $eventType = switch ($Level) {
            'ERROR' { 'Error' }
            'WARNING' { 'Warning' }
            'SECURITY' { 'SuccessAudit' }
            default { 'Information' }
        }

        $eventId = switch ($Level) {
            'ERROR' { 1001 }
            'WARNING' { 1002 }
            'SECURITY' { 1003 }
            default { 1000 }
        }

        Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
            -EventId $eventId -EntryType $eventType -Message $auditEntry -ErrorAction SilentlyContinue

        # Also output to console with color
        $color = switch ($Level) {
            'ERROR' { 'Red' }
            'WARNING' { 'Yellow' }
            'SECURITY' { 'Cyan' }
            default { 'White' }
        }
        Write-Host $auditEntry -ForegroundColor $color

    } catch {
        Write-Warning "Failed to write audit log: $_"
    }
}

function Test-ValidPath {
    <#
    .SYNOPSIS
        Validates and sanitizes file paths to prevent path traversal attacks.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # Check for dangerous patterns
    $dangerousPatterns = @('..', '~', '$', '`', ';', '|', '&', '<', '>', '"', "'")
    foreach ($pattern in $dangerousPatterns) {
        if ($Path -match [regex]::Escape($pattern)) {
            Write-AuditLog -Message "Dangerous pattern detected in path: $Path" -Level ERROR -Action "InputValidation"
            return $false
        }
    }

    # Verify path is rooted and doesn't contain relative references
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        Write-AuditLog -Message "Non-rooted path rejected: $Path" -Level ERROR -Action "InputValidation"
        return $false
    }

    return $true
}

function Test-ValidHostname {
    <#
    .SYNOPSIS
        Validates hostname to prevent injection attacks.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Hostname
    )

    # RFC 1123 compliant hostname validation
    $hostnameRegex = '^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?)*$|^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$'

    if ($Hostname -notmatch $hostnameRegex) {
        Write-AuditLog -Message "Invalid hostname format: $Hostname" -Level ERROR -Action "InputValidation"
        return $false
    }

    return $true
}
#endregion

#region Core Functions
function Get-SystemUptime {
    <#
    .SYNOPSIS
        Displays the time since last system boot.
    .DESCRIPTION
        Queries CIM for operating system boot time and calculates uptime.
        Logs all actions to audit log for compliance tracking.
    #>
    [CmdletBinding()]
    param ()

    Write-AuditLog -Message "Querying system uptime" -Level INFO -Action "SystemQuery"

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $uptime = (Get-Date) - $os.LastBootUpTime

        Write-Host "`nSystem Uptime:" -ForegroundColor Cyan
        Write-Host "  Days:    $($uptime.Days)"
        Write-Host "  Hours:   $($uptime.Hours)"
        Write-Host "  Minutes: $($uptime.Minutes)"
        Write-Host "  Last Boot: $($os.LastBootUpTime)"

        Write-AuditLog -Message "System uptime retrieved successfully: $($uptime.Days)d $($uptime.Hours)h" -Level INFO -Action "SystemQuery"

    } catch {
        Write-AuditLog -Message "Error retrieving system uptime: $_" -Level ERROR -Action "SystemQuery"
        throw
    }
}

function Get-RunningServices {
    <#
    .SYNOPSIS
        Lists all currently running Windows services with security context.
    #>
    [CmdletBinding()]
    param ()

    Write-AuditLog -Message "Querying running services" -Level INFO -Action "ServiceQuery"

    try {
        $services = Get-Service | Where-Object Status -eq 'Running' |
            Sort-Object DisplayName

        $services | Format-Table -AutoSize Name, DisplayName, Status, StartType

        Write-AuditLog -Message "Retrieved $($services.Count) running services" -Level INFO -Action "ServiceQuery"

    } catch {
        Write-AuditLog -Message "Error retrieving running services: $_" -Level ERROR -Action "ServiceQuery"
        throw
    }
}

function Get-DiskUsage {
    <#
    .SYNOPSIS
        Shows size, free space, and percentage free for each local drive with threshold warnings.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,99)]
        [int]$WarningThreshold = 20
    )

    Write-AuditLog -Message "Querying disk usage" -Level INFO -Action "DiskQuery"

    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop |
            Select-Object DeviceID,
                @{Name='Size(GB)';Expression={[math]::Round($_.Size/1GB,2)}},
                @{Name='Free(GB)';Expression={[math]::Round($_.FreeSpace/1GB,2)}},
                @{Name='Free(%)';Expression={[math]::Round(($_.FreeSpace/$_.Size)*100,2)}}

        foreach ($disk in $disks) {
            $color = if ($disk.'Free(%)' -lt $WarningThreshold) { 'Red' }
                     elseif ($disk.'Free(%)' -lt 30) { 'Yellow' }
                     else { 'Green' }

            Write-Host "`nDrive: $($disk.DeviceID)" -ForegroundColor $color
            Write-Host "  Size: $($disk.'Size(GB)') GB"
            Write-Host "  Free: $($disk.'Free(GB)') GB ($($disk.'Free(%)')%)"

            if ($disk.'Free(%)' -lt $WarningThreshold) {
                Write-AuditLog -Message "Low disk space warning on $($disk.DeviceID): $($disk.'Free(%)')% free" `
                    -Level WARNING -Action "DiskQuery"
            }
        }

        Write-AuditLog -Message "Disk usage retrieved successfully" -Level INFO -Action "DiskQuery"

    } catch {
        Write-AuditLog -Message "Error retrieving disk usage: $_" -Level ERROR -Action "DiskQuery"
        throw
    }
}

function Get-TopCPUProcesses {
    <#
    .SYNOPSIS
        Retrieves the top processes by CPU usage with resource monitoring.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,50)]
        [int]$Count = 5
    )

    Write-AuditLog -Message "Querying top $Count CPU processes" -Level INFO -Action "ProcessQuery"

    try {
        $processes = Get-Process |
            Sort-Object CPU -Descending |
            Select-Object -First $Count Name, CPU,
                @{Name='Memory(MB)';Expression={[math]::Round($_.WorkingSet64/1MB,2)}},
                Id

        $processes | Format-Table -AutoSize

        Write-AuditLog -Message "Retrieved top $Count CPU processes" -Level INFO -Action "ProcessQuery"

    } catch {
        Write-AuditLog -Message "Error retrieving top CPU processes: $_" -Level ERROR -Action "ProcessQuery"
        throw
    }
}

function Get-ListeningPorts {
    <#
    .SYNOPSIS
        Lists all TCP ports in Listen state with process details for security auditing.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Querying listening TCP ports" -Level SECURITY -Action "NetworkQuery"

    try {
        $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Select-Object LocalAddress, LocalPort, OwningProcess,
                @{Name='ProcessName';Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} |
            Sort-Object LocalPort

        $connections | Format-Table -AutoSize

        Write-AuditLog -Message "Retrieved $($connections.Count) listening ports" -Level SECURITY -Action "NetworkQuery"

    } catch {
        Write-AuditLog -Message "Error retrieving listening ports: $_" -Level ERROR -Action "NetworkQuery"
        throw
    }
}

function Test-MultiPing {
    <#
    .SYNOPSIS
        Tests ICMP connectivity for multiple hosts with validation.
    .PARAMETER Hosts
        Array of validated hostnames or IP addresses to ping.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Hosts
    )

    Write-AuditLog -Message "Testing connectivity to $($Hosts.Count) hosts" -Level INFO -Action "NetworkTest"

    foreach ($hostItem in $Hosts) {
        $hostName = $hostItem.Trim()

        # Validate hostname
        if (-not (Test-ValidHostname -Hostname $hostName)) {
            Write-Host "Invalid hostname: $hostName" -ForegroundColor Red
            continue
        }

        try {
            $result = Test-Connection -ComputerName $hostName -Count 2 -ErrorAction Stop
            Write-Host "SUCCESS: $hostName is reachable (RTT: $($result[0].ResponseTime)ms)" -ForegroundColor Green
            Write-AuditLog -Message "Ping to $hostName succeeded" -Level INFO -Action "NetworkTest"

        } catch {
            Write-Host "FAILED: $hostName is unreachable" -ForegroundColor Red
            Write-AuditLog -Message "Ping to $hostName failed: $_" -Level WARNING -Action "NetworkTest"
        }
    }
}

function Show-LatestAppEvents {
    <#
    .SYNOPSIS
        Displays the latest entries in the Application event log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,1000)]
        [int]$Newest = 20
    )

    Write-AuditLog -Message "Querying $Newest latest application events" -Level INFO -Action "EventQuery"

    try {
        Get-WinEvent -LogName Application -MaxEvents $Newest -ErrorAction Stop |
            Select-Object TimeCreated, Id, LevelDisplayName, Message |
            Format-Table -AutoSize -Wrap

        Write-AuditLog -Message "Retrieved $Newest application events" -Level INFO -Action "EventQuery"

    } catch {
        Write-AuditLog -Message "Error retrieving application events: $_" -Level ERROR -Action "EventQuery"
        throw
    }
}

function Export-SystemLog {
    <#
    .SYNOPSIS
        Exports System event log to CSV with path validation.
    .PARAMETER Path
        Validated path to save the exported CSV file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Write-AuditLog -Message "Exporting system log to $Path" -Level SECURITY -Action "LogExport"

    if (-not (Test-ValidPath -Path $Path)) {
        throw "Invalid or insecure path specified"
    }

    try {
        $exportDir = Split-Path $Path -Parent
        if (-not (Test-Path $exportDir)) {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
        }

        Get-WinEvent -LogName System -MaxEvents 5000 -ErrorAction Stop |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Export-Csv -Path $Path -NoTypeInformation -ErrorAction Stop

        Write-Host "System log exported to $Path" -ForegroundColor Green
        Write-AuditLog -Message "System log exported successfully to $Path" -Level SECURITY -Action "LogExport"

    } catch {
        Write-AuditLog -Message "Error exporting system log: $_" -Level ERROR -Action "LogExport"
        throw
    }
}

function Restart-PrintSpooler {
    <#
    .SYNOPSIS
        Restarts the Print Spooler service with proper error handling.
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param()

    Write-AuditLog -Message "Attempting to restart Print Spooler service" -Level SECURITY -Action "ServiceRestart"

    if ($PSCmdlet.ShouldProcess("Print Spooler", "Restart Service")) {
        try {
            $service = Get-Service -Name Spooler -ErrorAction Stop

            if ($service.Status -eq 'Running') {
                Restart-Service -Name Spooler -Force -ErrorAction Stop
            } else {
                Start-Service -Name Spooler -ErrorAction Stop
            }

            Write-Host "Print Spooler restarted successfully." -ForegroundColor Green
            Write-AuditLog -Message "Print Spooler restarted successfully" -Level SECURITY -Action "ServiceRestart"

        } catch {
            Write-AuditLog -Message "Error restarting Print Spooler: $_" -Level ERROR -Action "ServiceRestart"
            throw
        }
    }
}

function Get-InstalledUpdates {
    <#
    .SYNOPSIS
        Lists installed Windows updates for patch compliance verification.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Querying installed updates" -Level INFO -Action "UpdateQuery"

    try {
        $updates = Get-HotFix | Sort-Object InstalledOn -Descending

        $updates | Format-Table -AutoSize InstalledOn, Description, HotFixID, InstalledBy

        Write-AuditLog -Message "Retrieved $($updates.Count) installed updates" -Level INFO -Action "UpdateQuery"

    } catch {
        Write-AuditLog -Message "Error retrieving installed updates: $_" -Level ERROR -Action "UpdateQuery"
        throw
    }
}

function Resolve-DNSNameInfo {
    <#
    .SYNOPSIS
        Resolves a DNS name with validation and shows query results.
    .PARAMETER Name
        The validated hostname or FQDN to resolve.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    Write-AuditLog -Message "Resolving DNS name: $Name" -Level INFO -Action "DNSQuery"

    if (-not (Test-ValidHostname -Hostname $Name)) {
        throw "Invalid hostname format"
    }

    try {
        $results = Resolve-DnsName -Name $Name -ErrorAction Stop

        $results | Select-Object Name, Type, IPAddress, NameHost |
            Format-Table -AutoSize

        Write-AuditLog -Message "DNS name $Name resolved successfully" -Level INFO -Action "DNSQuery"

    } catch {
        Write-AuditLog -Message "Error resolving DNS name $Name : $_" -Level ERROR -Action "DNSQuery"
        throw
    }
}

function Find-DormantAccounts {
    <#
    .SYNOPSIS
        Finds AD user accounts inactive for a specified timespan.
    .PARAMETER DaysInactive
        Number of days since last logon to consider inactive.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateRange(1,3650)]
        [int]$DaysInactive
    )

    Write-AuditLog -Message "Searching for dormant AD accounts ($DaysInactive days)" -Level SECURITY -Action "ADQuery"

    try {
        # Check if AD module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            throw "ActiveDirectory module not available"
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        $accounts = Search-ADAccount -UsersOnly -AccountInactive -TimeSpan (New-TimeSpan -Days $DaysInactive) -ErrorAction Stop |
            Select-Object Name, SamAccountName, LastLogonDate, Enabled

        $accounts | Format-Table -AutoSize

        Write-AuditLog -Message "Found $($accounts.Count) dormant AD accounts" -Level SECURITY -Action "ADQuery"

    } catch {
        Write-AuditLog -Message "Error finding dormant accounts: $_" -Level ERROR -Action "ADQuery"
        throw
    }
}

function Show-ITToolkit {
    <#
    .SYNOPSIS
        Displays an interactive menu to run toolkit functions with audit logging.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "IT Toolkit menu launched" -Level INFO -Action "MenuLaunch"

    $menu = @(
        @{Name='System Uptime'; Action='Get-SystemUptime'},
        @{Name='Running Services'; Action='Get-RunningServices'},
        @{Name='Disk Usage'; Action='Get-DiskUsage'},
        @{Name='Top CPU Processes'; Action='Get-TopCPUProcesses'},
        @{Name='Listening TCP Ports'; Action='Get-ListeningPorts'},
        @{Name='Ping Multiple Hosts'; Action={
            $hostsInput = Read-Host 'Enter hostnames/IPs (comma-separated)'
            if ($hostsInput) {
                Test-MultiPing -Hosts ($hostsInput -split ',' | ForEach-Object { $_.Trim() })
            } else {
                Write-Host 'No hosts entered.' -ForegroundColor Yellow
            }
        }},
        @{Name='Latest Application Events'; Action='Show-LatestAppEvents'},
        @{Name='Export System Log'; Action={
            $path = Read-Host 'Export Path (e.g., C:\Logs\SystemLog.csv)'
            if ($path) {
                Export-SystemLog -Path $path
            } else {
                Write-Host 'No path entered.' -ForegroundColor Yellow
            }
        }},
        @{Name='Restart Print Spooler'; Action='Restart-PrintSpooler'},
        @{Name='Installed Updates'; Action='Get-InstalledUpdates'},
        @{Name='Resolve DNS Name'; Action={
            $name = Read-Host 'Hostname or FQDN'
            if ($name) {
                Resolve-DNSNameInfo -Name $name
            } else {
                Write-Host 'No name entered.' -ForegroundColor Yellow
            }
        }},
        @{Name='Find Dormant AD Accounts'; Action={
            $days = Read-Host 'Days Inactive'
            if ($days -as [int] -gt 0) {
                Find-DormantAccounts -DaysInactive $days
            } else {
                Write-Host 'Invalid days entered.' -ForegroundColor Yellow
            }
        }}
    )

    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "    IT Toolkit v2.0 - Secure Edition" -ForegroundColor Cyan
        Write-Host "  Fourth Estate Infrastructure Ready" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        for ($i=0; $i -lt $menu.Count; $i++) {
            Write-Host "[$($i+1)] $($menu[$i].Name)"
        }
        Write-Host "[0] Exit"
        Write-Host ""

        $choice = Read-Host 'Select an option'

        if ($choice -match '^\d+$' -and [int]$choice -gt 0 -and [int]$choice -le $menu.Count) {
            Write-Host ""
            Write-Host "Executing: $($menu[$choice-1].Name)" -ForegroundColor Yellow
            Write-Host "----------------------------------------"

            try {
                & $menu[$choice-1].Action
            } catch {
                Write-Host "Error executing function: $_" -ForegroundColor Red
            }

            Write-Host ""
            Write-Host "Press Enter to continue..." -ForegroundColor Gray
            Read-Host | Out-Null

        } elseif ($choice -ne '0') {
            Write-Host "Invalid selection. Please enter 0-$($menu.Count)." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }

    } until ($choice -eq '0')

    Write-AuditLog -Message "IT Toolkit menu closed" -Level INFO -Action "MenuClose"
}
#endregion

# If script is executed directly (not dot-sourced), launch the menu
if ($MyInvocation.InvocationName -ne '.') {
    Show-ITToolkit
}
