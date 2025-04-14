<#
.SYNOPSIS
    Retrieves and displays snapshot information for all virtual machines in a vCenter Server or ESXi host.

.DESCRIPTION
    This script performs the following steps:
      1. Checks if the VMware.PowerCLI module is installed. If not, it installs the module.
      2. Imports the VMware.PowerCLI module.
      3. Prompts the user to enter vCenter/ESXi connection details (host, username, password) and connects.
      4. Retrieves all virtual machines in the environment.
      5. For each virtual machine, it attempts to retrieve any snapshots.
         - For each snapshot, the script calculates the age (in days) and collects key snapshot data,
           including whether the snapshot is current, orphaned, and the user who created it (if available).
         - Snapshot information is output in a table format.
      6. Finally, the script disconnects from the vCenter/ESXi host.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - PowerShell 5.1+.
      - VMware.PowerCLI module (if not present, the script will install it).
      - Appropriate permissions to connect to and query the vCenter Server/ESXi host.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a log message with a timestamp and a specified severity level.
    
    .PARAMETER Message
        The message text to log.
    
    .PARAMETER Level
        The severity level of the message (e.g., "INFO" or "ERROR"). Default is "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#==============================================
# 1. Ensure VMware.PowerCLI Module is Installed and Imported
#==============================================
Write-Log -Message "Checking for VMware.PowerCLI module..."
if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
    Write-Log -Message "VMware.PowerCLI module not found. Installing..." -Level "INFO"
    try {
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -ErrorAction Stop
        Write-Log -Message "VMware.PowerCLI module installed successfully." -Level "INFO"
    } catch {
        Write-Log -Message "Error installing VMware.PowerCLI module: $_" -Level "ERROR"
        exit
    }
} else {
    Write-Log -Message "VMware.PowerCLI module already installed." -Level "INFO"
}

Write-Log -Message "Importing VMware.PowerCLI module..."
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Log -Message "VMware.PowerCLI module imported successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error importing VMware.PowerCLI module: $_" -Level "ERROR"
    exit
}

#==============================================
# 2. Connect to vCenter Server or ESXi Host
#==============================================
# Prompt for connection details
$server = Read-Host "Enter vCenter Server or ESXi host"        # e.g., "vcenter.example.com" or "esxi01.example.com"
$user   = Read-Host "Enter username"                           # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString            # The password is captured securely

Write-Log -Message "Connecting to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    exit
}

#==============================================
# 3. Get All Virtual Machines and Their Snapshots
#==============================================
Write-Log -Message "Retrieving virtual machines..."
$allVMs = Get-VM

foreach ($vm in $allVMs) {
    Write-Log -Message "Checking snapshots for VM: $($vm.Name)..." -Level "INFO"
    
    # Attempt to fetch snapshots for the current VM
    try {
        $snapshots = Get-Snapshot -VM $vm -ErrorAction Stop
    } catch {
        Write-Log -Message "Error fetching snapshots for VM '$($vm.Name)': $_" -Level "ERROR"
        continue
    }
    
    if ($snapshots.Count -eq 0) {
        Write-Log -Message "No snapshots found for VM '$($vm.Name)'." -Level "INFO"
    } else {
        foreach ($snapshot in $snapshots) {
            # Calculate how many days ago the snapshot was created
            $snapshotAge = (Get-Date) - $snapshot.Created
            
            # Collect snapshot information into a custom object
            $snapshotInfo = [PSCustomObject]@{
                VMName        = $vm.Name
                SnapshotName  = $snapshot.Name
                Created       = $snapshot.Created
                Age           = $snapshotAge.Days
                IsOrphaned    = if ($snapshot.VM) { $false } else { $true }
                IsCurrent     = $snapshot.IsCurrent
                CreatedBy     = if ($snapshot.Description) { $snapshot.Description -replace ".*\((.*)\)", '$1' } else { "N/A" }
            }

            # Output the snapshot information in a formatted table
            $snapshotInfo | Format-Table -AutoSize
        }
    }
    
    Write-Log -Message "--------------------------------------------" -Level "INFO"
}

#==============================================
# 4. Disconnect from vCenter Server or ESXi Host
#==============================================
Write-Log -Message "Disconnecting from $server..."
try {
    Disconnect-VIServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from $server." -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from $server: $_" -Level "ERROR"
}

Write-Log -Message "Snapshot collection process completed." -Level "INFO"
