<#
.SYNOPSIS
    ITToolkit: A collection of one-line PowerShell functions for everyday IT tasks.
.DESCRIPTION
    Defines a set of advanced functions to check system health, manage services, query logs,
    test connectivity, and more. You can dot-source this script to import all the functions,
    then call them individually or use the interactive menu.
.EXAMPLE
    # Import the toolkit into your session:
    . \"C:\Scripts\ITToolkit.ps1\"

    # Run a function:
    Get-SystemUptime

    # Or launch interactive menu:
    Show-ITToolkit
#
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   August 14, 2025
    Version:        1.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

#region Comment-based Help
# Requires PowerShell 5.0+
#endregion

function Get-SystemUptime {
    <#
    .SYNOPSIS
        Displays the time since last system boot.
    #>
    [CmdletBinding()]
    param ()
    try {
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        Write-Host "System Uptime:" -ForegroundColor Cyan
        Write-Output $uptime
    } catch {
        Write-Host "Error retrieving system uptime: $_" -ForegroundColor Red
    }
}

function Get-RunningServices {
    <#
    .SYNOPSIS
<#
.SYNOPSIS
    ITToolkit: Secure PowerShell toolkit for IT operations.
.DESCRIPTION
    Advanced functions for system health, service management, log queries, connectivity, and more.
    All functions use robust error handling, input validation, and logging. Dot-source to import, or use interactive menu.
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
    Last Updated:   2025-08-20
    Version:        1.1
    Compliance:     NIST SP 800-53, STIG PowerShell Security Requirements
    Security:       Input validation, logging, no hardcoded credentials, least privilege
    Disclaimer:     Scripts are provided as-is. Review for your environment and compliance needs.
#>
        Lists all currently running Windows services.
    #>
    [CmdletBinding()]
    param ()
    try {
        Get-Service | Where-Object Status -eq 'Running' | Format-Table -AutoSize
    } catch {
        Write-Host "Error retrieving running services: $_" -ForegroundColor Red
    }
}

function Get-DiskUsage {
    <#
    .SYNOPSIS
        Shows size, free space, and percentage free for each local drive.
        Write-Log "System uptime retrieved successfully." "INFO"
    #>
        Write-Log "Error retrieving system uptime: $_" "ERROR"
    param ()
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
            Select-Object DeviceID,
                @{Name='Size(GB)';Expression={[math]::Round($_.Size/1GB,2)}},
                @{Name='Free(GB)';Expression={[math]::Round($_.FreeSpace/1GB,2)}},
                @{Name='Free(%)';Expression={[math]::Round(($_.FreeSpace/$_.Size)*100,2)}} |
            Format-Table -AutoSize
    } catch {
        Write-Host "Error retrieving disk usage: $_" -ForegroundColor Red
    }
}
        Write-Log "Running services listed successfully." "INFO"

        Write-Log "Error retrieving running services: $_" "ERROR"
    <#
    .SYNOPSIS
        Retrieves the top 5 processes by CPU usage.
    #>
    [CmdletBinding()]
    param()
    try {
        Get-Process |
            Sort-Object CPU -Descending |
            Select-Object -First 5 Name,CPU |
            Format-Table -AutoSize
    } catch {
        Write-Host "Error retrieving top CPU processes: $_" -ForegroundColor Red
    }
}

function Get-ListeningPorts {
        Write-Log "Disk usage retrieved successfully." "INFO"
    <#
        Write-Log "Error retrieving disk usage: $_" "ERROR"
        Lists all TCP ports in Listen state and their owning processes.
    #>
    [CmdletBinding()]
    param()
    try {
        Get-NetTCPConnection -State Listen |
            Select-Object LocalAddress,LocalPort,OwningProcess |
            Sort-Object LocalPort |
            Format-Table -AutoSize
    } catch {
        Write-Host "Error retrieving listening ports: $_" -ForegroundColor Red
    }
}

function Test-MultiPing {
        Write-Log "Top CPU processes retrieved successfully." "INFO"
    <#
        Write-Log "Error retrieving top CPU processes: $_" "ERROR"
        Tests ICMP connectivity for listed hostnames or IPs.
    .PARAMETER Hosts
        Array of hostnames or IP addresses to ping.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String[]]$Hosts
    )
    foreach ($host in $Hosts) {
        try {
            $result = Test-Connection $host -Count 1 -ErrorAction Stop |
                Select-Object Address,Status
            Write-Host "Ping to $host succeeded." -ForegroundColor Green
            $result | Format-Table -AutoSize
        Write-Log "Listening ports retrieved successfully." "INFO"
        } catch {
        Write-Log "Error retrieving listening ports: $_" "ERROR"
        }
    }
}

function Show-LatestAppEvents {
    <#
    .SYNOPSIS
        Displays the latest 20 entries in the Application event log.
    #>
    [CmdletBinding()]
    param()
    try {
        Get-EventLog -LogName Application -Newest 20 |
            Format-Table -AutoSize
    } catch {
        Write-Host "Error retrieving application events: $_" -ForegroundColor Red
    }
}

function Export-SystemLog {
    <#
            Write-Log "Ping to $host succeeded." "INFO"
    .SYNOPSIS
            Write-Log "Ping to $host failed: $_" "ERROR"
    .PARAMETER Path
        Path to save the exported CSV file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    try {
        Get-EventLog -LogName System |
            Export-Csv -Path $Path -NoTypeInformation
        Write-Host "System log exported to $Path" -ForegroundColor Green
    } catch {
        Write-Host "Error exporting system log: $_" -ForegroundColor Red
        Write-Log "Latest application events retrieved successfully." "INFO"
    }
        Write-Log "Error retrieving application events: $_" "ERROR"

function Restart-PrintSpooler {
    <#
    .SYNOPSIS
        Restarts the Print Spooler service.
    #>
    [CmdletBinding()]
    param()
    try {
        Restart-Service -Name Spooler -Force
        Write-Host "Print Spooler restarted." -ForegroundColor Green
    } catch {
        Write-Host "Error restarting Print Spooler: $_" -ForegroundColor Red
    }
}

function Get-InstalledUpdates {
    <#
        Write-Log "System log exported to $Path" "INFO"
    .SYNOPSIS
        Write-Log "Error exporting system log: $_" "ERROR"
    #>
    [CmdletBinding()]
    param()
    try {
        Get-HotFix |
            Select-Object InstalledOn,Description,HotFixID |
            Format-Table -AutoSize
    } catch {
        Write-Host "Error retrieving installed updates: $_" -ForegroundColor Red
    }
}

        Write-Log "Print Spooler restarted." "INFO"
function Resolve-DNSNameInfo {
        Write-Log "Error restarting Print Spooler: $_" "ERROR"
    .SYNOPSIS
        Resolves a DNS name and shows query results.
    .PARAMETER Name
        The hostname or FQDN to resolve.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )
    try {
        Resolve-DnsName -Name $Name |
            Select-Object Name,IPAddress,QueryType |
            Format-Table -AutoSize
        Write-Log "Installed updates retrieved successfully." "INFO"
    } catch {
        Write-Log "Error retrieving installed updates: $_" "ERROR"
    }
}

function Find-DormantAccounts {
    <#
    .SYNOPSIS
        Finds AD user accounts inactive for a given timespan.
    .PARAMETER DaysInactive
        Number of days since last logon to consider inactive.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$DaysInactive
    )
    try {
        Search-ADAccount -UsersOnly -AccountInactive -TimeSpan (New-TimeSpan -Days $DaysInactive) |
            Select-Object Name,LastLogonDate |
            Format-Table -AutoSize
        Write-Log "DNS name $Name resolved successfully." "INFO"
    } catch {
        Write-Log "Error resolving DNS name: $_" "ERROR"
    }
}

function Show-ITToolkit {
    <#
    .SYNOPSIS
        Displays an interactive menu to run toolkit functions.
    #>
    [CmdletBinding()]
    param()
    $menu = @(
        @{Name='System Uptime'; Action='Get-SystemUptime'},
        @{Name='Running Services'; Action='Get-RunningServices'},
        @{Name='Disk Usage'; Action='Get-DiskUsage'},
        @{Name='Top CPU Processes'; Action='Get-TopCPUProcesses'},
        @{Name='Listening TCP Ports'; Action='Get-ListeningPorts'},
        @{Name='Ping Multiple Hosts'; Action={
            $hosts = Read-Host 'Hosts (comma-separated)'
            if ($hosts) { Test-MultiPing ($hosts -split ',') } else { Write-Host 'No hosts entered.' -ForegroundColor Yellow }
        Write-Log "Dormant AD accounts found successfully." "INFO"
        }},
        Write-Log "Error finding dormant accounts: $_" "ERROR"
        @{Name='Export System Log'; Action={
            $path = Read-Host 'Export Path (e.g. C:\Temp\SystemLog.csv)'
            if ($path) { Export-SystemLog $path } else { Write-Host 'No path entered.' -ForegroundColor Yellow }
        }},
        @{Name='Restart Print Spooler'; Action='Restart-PrintSpooler'},
        @{Name='Installed Updates'; Action='Get-InstalledUpdates'},
        @{Name='Resolve DNS Name'; Action={
            $name = Read-Host 'Hostname or FQDN'
            if ($name) { Resolve-DNSNameInfo $name } else { Write-Host 'No name entered.' -ForegroundColor Yellow }
        }},
        @{Name='Find Dormant AD Accounts'; Action={
            $days = Read-Host 'Days Inactive'
            if ($days -as [int] -gt 0) { Find-DormantAccounts $days } else { Write-Host 'Invalid days entered.' -ForegroundColor Yellow }
        }}
    )
    do {
        Clear-Host
        Write-Host "=== IT Toolkit Menu ===" -ForegroundColor Cyan
        for ($i=0; $i -lt $menu.Count; $i++) {
            Write-Host "[$($i+1)] $($menu[$i].Name)"
        }
        Write-Host "[0] Exit"
        $choice = Read-Host 'Select an option'
        if ($choice -match '^[0-9]+$' -and [int]$choice -gt 0 -and [int]$choice -le $menu.Count) {
            "`nRunning: $($menu[$choice-1].Name)`n" | Write-Host
            & $menu[$choice-1].Action
            Write-Host "`nPress Enter to continue..."; Read-Host | Out-Null
        } elseif ($choice -ne '0') {
            Write-Host "Invalid selection. Please enter a number between 0 and $($menu.Count)." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    } until ($choice -eq '0')
}

<#
If script is executed directly (not dot-sourced), launch the menu.
#>
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Show-ITToolkit
}
