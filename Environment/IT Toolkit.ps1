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
    $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    Write-Output $uptime
}

function Get-RunningServices {
    <#
    .SYNOPSIS
        Lists all currently running Windows services.
    #>
    [CmdletBinding()]
    param ()
    Get-Service | Where-Object Status -eq 'Running'
}

function Get-DiskUsage {
    <#
    .SYNOPSIS
        Shows size, free space, and percentage free for each local drive.
    #>
    [CmdletBinding()]
    param ()
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID,
            @{Name='Size(GB)';Expression={[math]::Round($_.Size/1GB,2)}},
            @{Name='Free(GB)';Expression={[math]::Round($_.FreeSpace/1GB,2)}},
            @{Name='Free(%)';Expression={[math]::Round(($_.FreeSpace/$_.Size)*100,2)}}
}

function Get-TopCPUProcesses {
    <#
    .SYNOPSIS
        Retrieves the top 5 processes by CPU usage.
    #>
    [CmdletBinding()]
    param()
    Get-Process |
        Sort-Object CPU -Descending |
        Select-Object -First 5 Name,CPU
}

function Get-ListeningPorts {
    <#
    .SYNOPSIS
        Lists all TCP ports in Listen state and their owning processes.
    #>
    [CmdletBinding()]
    param()
    Get-NetTCPConnection -State Listen |
        Select-Object LocalAddress,LocalPort,OwningProcess |
        Sort-Object LocalPort
}

function Test-MultiPing {
    <#
    .SYNOPSIS
        Tests ICMP connectivity for listed hostnames or IPs.
    .PARAMETER Hosts
        Array of hostnames or IP addresses to ping.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String[]]$Hosts
    )
    $Hosts | ForEach-Object {
        Test-Connection $_ -Count 1 |
            Select-Object Address,Status
    }
}

function Show-LatestAppEvents {
    <#
    .SYNOPSIS
        Displays the latest 20 entries in the Application event log.
    #>
    [CmdletBinding()]
    param()
    Get-EventLog -LogName Application -Newest 20
}

function Export-SystemLog {
    <#
    .SYNOPSIS
        Exports the entire System event log to CSV.
    .PARAMETER Path
        Path to save the exported CSV file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    Get-EventLog -LogName System |
        Export-Csv -Path $Path -NoTypeInformation
    Write-Output "System log exported to $Path"
}

function Restart-PrintSpooler {
    <#
    .SYNOPSIS
        Restarts the Print Spooler service.
    #>
    [CmdletBinding()]
    param()
    Restart-Service -Name Spooler -Force
    Write-Output "Print Spooler restarted."
}

function Get-InstalledUpdates {
    <#
    .SYNOPSIS
        Lists all installed Windows updates (hotfixes).
    #>
    [CmdletBinding()]
    param()
    Get-HotFix |
        Select-Object InstalledOn,Description,HotFixID
}

function Resolve-DNSNameInfo {
    <#
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
    Resolve-DnsName -Name $Name |
        Select-Object Name,IPAddress,QueryType
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
    Search-ADAccount -UsersOnly -AccountInactive -TimeSpan (New-TimeSpan -Days $DaysInactive) |
        Select-Object Name,LastLogonDate
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
        @{Name='Ping Multiple Hosts'; Action={ Read-Host 'Hosts (comma-separated)' | Split-Path -Delimiter ',' | Test-MultiPing }},
        @{Name='Latest App Events'; Action='Show-LatestAppEvents'},
        @{Name='Export System Log'; Action={ Export-SystemLog (Read-Host 'Export Path (e.g. C:\Temp\SystemLog.csv)') }},
        @{Name='Restart Print Spooler'; Action='Restart-PrintSpooler'},
        @{Name='Installed Updates'; Action='Get-InstalledUpdates'},
        @{Name='Resolve DNS Name'; Action={ Resolve-DNSNameInfo (Read-Host 'Hostname or FQDN') }},
        @{Name='Find Dormant AD Accounts'; Action={ Find-DormantAccounts (Read-Host 'Days Inactive') }}
    )
    do {
        Clear-Host
        Write-Host "=== IT Toolkit Menu ===" -ForegroundColor Cyan
        for ($i=0; $i -lt $menu.Count; $i++) {
            Write-Host "[$($i+1)] $($menu[$i].Name)"
        }
        Write-Host "[0] Exit"
        $choice = Read-Host 'Select an option'
        if ($choice -as [int] -gt 0 -and $choice -le $menu.Count) {
            "`nRunning: $($menu[$choice-1].Name)`n" | Write-Host
            & $menu[$choice-1].Action
            Write-Host "`nPress Enter to continue..."; Read-Host | Out-Null
        }
    } until ($choice -eq '0')
}

<#
If script is executed directly (not dot-sourced), launch the menu.
#>
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Show-ITToolkit
}
