<#
.SYNOPSIS
    Performs a health check on a vCenter Server or ESXi host and exports results to a CSV file.

.DESCRIPTION
    This script:
      1. Checks whether VMware.PowerCLI is installed; if not, it installs the module.
      2. Imports the PowerCLI module.
      3. Prompts the user for vCenter/ESXi connection details and connects to the server.
      4. Prompts for an output path to export health check results.
      5. Performs several health checks:
            - Host status (name, connection state, power state)
            - Datastore usage (name, total capacity, free space, used space)
            - Virtual machine configurations (name, power state, CPUs, memory, hard disks, network adapters)
            - Snapshot details (associated VM, snapshot name, creation time, size)
            - Orphaned VMs (VMs with inaccessible connection state)
      6. Exports the collected results to a CSV file.
      7. Disconnects from the vCenter/ESXi host.

.NOTES
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.1
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module (the script will install it if missing).
      - Appropriate permissions to access and query the vCenter Server or ESXi host.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a log message with a timestamp and a severity level.
    
    .PARAMETER Message
        The log message text.
    
    .PARAMETER Level
        Severity level (e.g., INFO, ERROR). Default is "INFO".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#==============================================
# 1. Ensure VMware.PowerCLI is Installed and Imported
#==============================================
Write-Log -Message "Checking for VMware.PowerCLI module..."
if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
    Write-Log -Message "PowerCLI module not found. Installing..." -Level "INFO"
    try {
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -ErrorAction Stop
        Write-Log -Message "VMware.PowerCLI installed successfully." -Level "INFO"
    } catch {
        Write-Log -Message "Error installing VMware.PowerCLI: $_" -Level "ERROR"
        exit
    }
} else {
    Write-Log -Message "VMware.PowerCLI module already installed." -Level "INFO"
}

# Import the PowerCLI module
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
# Prompt the user for connection details (server, username, and password)
$server = Read-Host "Enter vCenter Server or ESXi host"      # e.g., "vcenter.company.com" or "esxi01.company.com"
$user   = Read-Host "Enter username"                         # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString          # Password input is masked for security

Write-Log -Message "Attempting connection to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    exit
}

#==============================================
# 3. Define the Output CSV Path for Health Check Results
#==============================================
$csvFilePath = Read-Host "Enter the path for exporting health check results (e.g., C:\HealthCheckResults.csv)"
if (-not $csvFilePath) {
    Write-Log -Message "No CSV file path provided. Exiting." -Level "ERROR"
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 4. Collect Health Check Data
#==============================================
# Initialize an empty array to store all the health check results.
$healthCheckResults = @()

# Check host status: Retrieves each host's name, connection state, and power state.
Write-Log -Message "Checking host status..."
try {
    $hostStatus = Get-VMHost | Select-Object Name, ConnectionState, PowerState
    $healthCheckResults += $hostStatus
    Write-Log -Message "Host status data collected." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving host status: $_" -Level "ERROR"
}

# Check datastore usage: Retrieves datastore name and capacity information.
Write-Log -Message "Checking datastore usage..."
try {
    $datastoreUsage = Get-Datastore | Select-Object Name, CapacityGB, FreeSpaceGB, UsedSpaceGB
    $healthCheckResults += $datastoreUsage
    Write-Log -Message "Datastore usage data collected." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving datastore usage: $_" -Level "ERROR"
}

# Check VM configurations: Retrieves VMs' name, power state, CPU, memory, and attached devices.
Write-Log -Message "Checking VM configurations..."
try {
    $vmConfigs = Get-VM | Select-Object Name, PowerState, NumCpu, MemoryGB, HardDisks, NetworkAdapters
    $healthCheckResults += $vmConfigs
    Write-Log -Message "VM configuration data collected." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving VM configurations: $_" -Level "ERROR"
}

# Check for snapshots: Retrieves snapshot details for all VMs.
Write-Log -Message "Checking for snapshots..."
try {
    $snapshots = Get-VM | Get-Snapshot | Select-Object VM, Name, Created, SizeGB
    $healthCheckResults += $snapshots
    Write-Log -Message "Snapshot data collected." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving snapshots: $_" -Level "ERROR"
}

# Check for orphaned VMs: Finds VMs that are marked as inaccessible.
Write-Log -Message "Checking for orphaned VMs..."
try {
    $orphanedVMs = Get-VM -Name '*' -ErrorAction SilentlyContinue | Where-Object {
        $_.ExtensionData.Runtime.ConnectionState -eq 'inaccessible'
    }
    $healthCheckResults += $orphanedVMs
    Write-Log -Message "Orphaned VM data collected." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving orphaned VMs: $_" -Level "ERROR"
}

#==============================================
# 5. Export Health Check Results to CSV
#==============================================
Write-Log -Message "Exporting health check results to CSV file: $csvFilePath..."
try {
    $healthCheckResults | Export-Csv -Path $csvFilePath -NoTypeInformation -ErrorAction Stop
    Write-Log -Message "Health check results successfully exported to $csvFilePath." -Level "INFO"
} catch {
    Write-Log -Message "Error exporting health check results: $_" -Level "ERROR"
}

#==============================================
# 6. Disconnect from vCenter Server or ESXi Host
#==============================================
Write-Log -Message "Disconnecting from $server..."
try {
    Disconnect-VIServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from $server." -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from $server: $_" -Level "ERROR"
}

Write-Log -Message "Health check process completed." -Level "INFO"
