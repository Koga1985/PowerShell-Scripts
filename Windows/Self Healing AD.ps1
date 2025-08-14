<#
.SYNOPSIS
    Checks and attempts to repair basic Active Directory issues related to domain controller connectivity and replication.
    
.DESCRIPTION
    The Repair-AD function performs the following actions:
      1. Retrieves all domain controllers in the domain.
      2. Checks connectivity (via Test-Connection) for each domain controller.
      3. If one or more domain controllers are reachable, it checks Active Directory replication status:
            - If any replication partner metadata shows a LastReplicationSuccess older than one day, it initiates replication
              using repadmin.
      4. If no domain controllers are reachable, it verifies DNS resolution for one of the domain controllers.
            - If DNS resolution fails, it attempts to renew the IP configuration.
    
    **Note:** You may need to rerun the script after network changes to see updated results.
    
.EXAMPLE
    PS C:\> .\Repair-AD.ps1
    The script will output status messages about the connectivity, replication health, and any remedial actions.
    
#
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   August 14, 2025
    Version:        1.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

function Repair-AD {
    <#
    .SYNOPSIS
        Checks Active Directory connectivity and replication, and attempts remedial actions if issues are found.
        
    .DESCRIPTION
        The function retrieves all domain controllers from Active Directory. It pings each one to see which are reachable.
        If any domain controllers are reachable, it then checks the replication metadata.
        If replication failures (i.e. LastReplicationSuccess older than one day) are detected, it initiates forced replication using repadmin.
        If no domain controllers are reachable, the function checks DNS resolution for one of the domain controllers.
        If DNS resolution fails, it attempts to renew the IP configuration.
    #>
    try {
        Write-Host "Retrieving list of domain controllers..."
        $domainControllers = Get-ADDomainController -Filter * -ErrorAction Stop
    } catch {
        Write-Host "Error retrieving domain controllers: $_" -ForegroundColor Red
        return
    }
    
    Write-Host "Checking connectivity to domain controllers..."
    $reachableDCs = @()
    foreach ($dc in $domainControllers) {
        try {
            $pingResult = Test-Connection -ComputerName $dc.HostName -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($pingResult) {
                Write-Host "Domain controller '$($dc.HostName)' is reachable." -ForegroundColor Green
                $reachableDCs += $dc
            } else {
                Write-Host "Domain controller '$($dc.HostName)' is not reachable." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Error pinging '$($dc.HostName)': $_" -ForegroundColor Red
        }
    }
    
    # If at least one domain controller is reachable, check replication health.
    if ($reachableDCs.Count -gt 0) {
        Write-Host "Domain controllers are reachable. Checking AD replication health..."
        try {
            $replicationMetadata = Get-ADReplicationPartnerMetadata -Target * -ErrorAction Stop
            # Identify partners with a replication success older than 1 day.
            $replicationIssues = $replicationMetadata | Where-Object { $_.LastReplicationSuccess -lt (Get-Date).AddDays(-1) }
            if ($replicationIssues) {
                Write-Host "Replication issues detected. Initiating replication repair..."
                foreach ($meta in $replicationMetadata) {
                    Write-Host "Attempting replication from $($meta.Partner) to $($meta.Server)..."
                    # Force replication using repadmin (suppressing output)
                    repadmin /replicate $meta.Server $meta.Partner | Out-Null
                }
                Write-Host "Replication repair initiated."
            } else {
                Write-Host "Active Directory replication appears healthy." -ForegroundColor Green
            }
        } catch {
            Write-Host "Error checking replication health: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "None of the domain controllers are reachable. Checking DNS resolution..."
        try {
            # Use the hostname of the first domain controller to test DNS resolution.
            $dcHostName = $domainControllers[0].HostName
            $dnsRecord = Resolve-DnsName -Name $dcHostName -ErrorAction SilentlyContinue
            if ($dnsRecord) {
                Write-Host "DNS resolution is successful for $dcHostName, but domain controllers remain unreachable." -ForegroundColor Yellow
                Write-Host "Investigate network connectivity issues."
            } else {
                Write-Host "DNS resolution failed for $dcHostName." -ForegroundColor Red
                Write-Host "Attempting to renew IP configuration..."
                ipconfig /renew | Out-Null
                Write-Host "IP configuration renew initiated. Please re-run the script after network changes take effect."
            }
        } catch {
            Write-Host "Error during DNS resolution check: $_" -ForegroundColor Red
        }
    }
}

# Run the Active Directory repair function
Repair-AD
