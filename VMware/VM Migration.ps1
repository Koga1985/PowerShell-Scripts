<#
.SYNOPSIS
    Migrates a specified virtual machine from a source vCenter Server or ESXi host to a destination host or cluster.

.DESCRIPTION
    This script performs the following actions:
      1. Checks if the VMware.PowerCLI module is installed and installs it if not.
      2. Imports the VMware.PowerCLI module.
      3. Prompts the user for source and destination connection details and connects to both.
      4. Prompts the user for the name of the virtual machine to migrate.
      5. Prompts for the destination host or cluster.
      6. Validates that the specified virtual machine exists on the source environment.
      7. Validates that the destination host or cluster exists (supports both VMHost and ClusterComputeResource).
      8. Migrates the virtual machine to the destination using Move-VM.
      9. Disconnects from both the source and destination environments.

.PARAMETER None
    The script is interactive; it prompts for all necessary details.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module (the script installs it if not present).
      - Sufficient permissions to connect to and modify objects on the vCenter Server or ESXi host.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with a timestamp and severity level.
    
    .PARAMETER Message
        The text of the log message.
    
    .PARAMETER Level
        The severity level (e.g., "INFO", "ERROR"). Default is "INFO".
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
# 1. Install or Update VMware.PowerCLI Module
#==============================================
Write-Log -Message "Checking for VMware.PowerCLI module..."
if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
    Write-Log -Message "VMware.PowerCLI module not found. Installing the latest version..." -Level "INFO"
    try {
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -ErrorAction Stop
        Write-Log -Message "VMware.PowerCLI installed successfully." -Level "INFO"
    } catch {
        Write-Log -Message "Error installing VMware.PowerCLI module: $_" -Level "ERROR"
        exit
    }
} else {
    Write-Log -Message "VMware.PowerCLI module is already installed." -Level "INFO"
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
# 2. Connect to Source and Destination vCenter/ESXi Hosts
#==============================================
# Source connection details
$sourceServer = Read-Host "Enter source vCenter Server or ESXi host"       # e.g., "source-vcenter.company.com"
$sourceUser   = Read-Host "Enter source username"                          # e.g., "administrator@source.local"
$sourcePassword = Read-Host "Enter source password" -AsSecureString

Write-Log -Message "Connecting to source server: $sourceServer..."
try {
    Connect-VIServer -Server $sourceServer -User $sourceUser -Password $sourcePassword -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to source server: $sourceServer." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to source server $sourceServer: $_" -Level "ERROR"
    exit
}

# Destination connection details
$destinationServer = Read-Host "Enter destination vCenter Server or ESXi host"   # e.g., "dest-vcenter.company.com"
$destinationUser   = Read-Host "Enter destination username"                      # e.g., "administrator@dest.local"
$destinationPassword = Read-Host "Enter destination password" -AsSecureString

Write-Log -Message "Connecting to destination server: $destinationServer..."
try {
    Connect-VIServer -Server $destinationServer -User $destinationUser -Password $destinationPassword -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to destination server: $destinationServer." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to destination server $destinationServer: $_" -Level "ERROR"
    # Disconnect from source if destination fails
    Disconnect-VIServer -Server $sourceServer -Confirm:$false
    exit
}

#==============================================
# 3. Specify the Virtual Machine and Destination Object
#==============================================
# Prompt for the VM name to migrate (on the source environment)
$vmName = Read-Host "Enter the virtual machine name to migrate"

# Get the virtual machine from the source
Write-Log -Message "Retrieving VM '$vmName' from source server..."
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if ($vm -eq $null) {
    Write-Log -Message "Error: Virtual machine '$vmName' not found on source server." -Level "ERROR"
    Disconnect-VIServer -Server $sourceServer -Confirm:$false
    Disconnect-VIServer -Server $destinationServer -Confirm:$false
    exit
}
Write-Log -Message "Virtual machine '$vmName' found." -Level "INFO"

# Prompt for the destination host or cluster
$destinationTarget = Read-Host "Enter the destination host or cluster"

# Validate if the destination target exists. Try as a VMHost first.
$destination = Get-VMHost -Name $destinationTarget -ErrorAction SilentlyContinue

# If not found as VMHost, try as a cluster.
if (-not $destination) {
    $destination = Get-Cluster -Name $destinationTarget -ErrorAction SilentlyContinue
}

if ($destination -eq $null) {
    Write-Log -Message "Error: Destination target '$destinationTarget' not found." -Level "ERROR"
    Disconnect-VIServer -Server $sourceServer -Confirm:$false
    Disconnect-VIServer -Server $destinationServer -Confirm:$false
    exit
}
Write-Log -Message "Destination target '$destinationTarget' found." -Level "INFO"

#==============================================
# 4. Migrate the Virtual Machine
#==============================================
Write-Log -Message "Migrating virtual machine '$vmName' to '$destinationTarget'..."
try {
    Move-VM -VM $vm -Destination $destination -Confirm:$false -ErrorAction Stop
    Write-Log -Message "Virtual machine '$vmName' migrated successfully to '$destinationTarget'." -Level "INFO"
} catch {
    Write-Log -Message "Error migrating virtual machine '$vmName': $_" -Level "ERROR"
}

#==============================================
# 5. Disconnect from Source and Destination Servers
#==============================================
Write-Log -Message "Disconnecting from source server: $sourceServer..."
try {
    Disconnect-VIServer -Server $sourceServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from source server: $sourceServer." -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from source server: $_" -Level "ERROR"
}

Write-Log -Message "Disconnecting from destination server: $destinationServer..."
try {
    Disconnect-VIServer -Server $destinationServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from destination server: $destinationServer." -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from destination server: $_" -Level "ERROR"
}

Write-Log -Message "VM migration process completed." -Level "INFO"
