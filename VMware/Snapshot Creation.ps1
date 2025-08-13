<#
.SYNOPSIS
    Connects to a vCenter Server or ESXi host and creates a snapshot of a specified virtual machine.

.DESCRIPTION
    This script ensures the VMware PowerCLI module is installed and imported. It then prompts the user for
    connection details (vCenter/ESXi host, username, and password) and connects to the specified server. The user 
    is then prompted for the target virtual machine name. The script validates that the virtual machine exists
    and, if found, creates a snapshot with a timestamped name. Finally, it disconnects from the server.
    
    Enhancements include:
      - A logging function for standardized messaging.
      - Robust try/catch error handling.
      - User prompts to avoid hardcoding sensitive or environment-specific information.

.PARAMETER None
    The script is interactive. User input is required at runtime for host connection and VM selection.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - Administrative privileges and necessary permissions to manage vCenter/ESXi.
      - Internet connectivity for module installation, if required.
#>


#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#==============================================
# 0. Admin Rights and PowerShell Version Check
#==============================================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script must be run as Administrator." -ForegroundColor Red
    exit
}
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.0 or higher is required." -ForegroundColor Red
    exit
}

#==============================================
# 1. Ensure VMware PowerCLI Module is Installed and Imported
#==============================================

Write-Log -Message "Checking for VMware.PowerCLI module..."
if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
    Write-Log -Message "VMware.PowerCLI module not found. Installing..." -Level "INFO"
    try {
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -ErrorAction Stop
        Write-Log -Message "VMware.PowerCLI installed successfully." -Level "INFO"
    } catch {
        Write-Log -Message "Failed to install VMware.PowerCLI module. Error: $_" -Level "ERROR"
        exit
    }
} else {
    Write-Log -Message "VMware.PowerCLI module is already installed." -Level "INFO"
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
# 2. Connect to vCenter Server / ESXi Host
#==============================================

# Prompt the user for connection details:
$server   = Read-Host "Enter vCenter Server or ESXi host"   # e.g., "vcenter.company.com" or "esxi01.company.com"
$user     = Read-Host "Enter username"                      # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString      # Input is masked for security

Write-Log -Message "Attempting connection to $server..."
$Summary = @{}
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
    $Summary['Connection'] = "Success"
} catch {
    Write-Log -Message "Error connecting to $server. Check your credentials or network. Error: $_" -Level "ERROR"
    $Summary['Connection'] = "Failed"
    $Summary['Error'] = $_
    Write-Host "\nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
    exit
}

#==============================================
# 3. Validate Virtual Machine and Create Snapshot
#==============================================

# Prompt for the virtual machine name:
$vmName = Read-Host "Enter the virtual machine name"   # Do not hardcode the VM name

# Validate that the virtual machine exists in the inventory:
Write-Log -Message "Searching for virtual machine '$vmName'..."
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if ($vm -eq $null) {
    Write-Log -Message "Virtual machine '$vmName' not found. Please check the name and try again." -Level "ERROR"
    $Summary['VM Found'] = "No"
    $Summary['VM Name'] = $vmName
    Disconnect-VIServer -Confirm:$false
    Write-Host "\nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
    exit
} else {
    $Summary['VM Found'] = "Yes"
    $Summary['VM Name'] = $vmName
}

# Create a snapshot with a unique name (using the current date/time):
$snapshotName = "Snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Log -Message "Creating snapshot '$snapshotName' for virtual machine '$vmName'..."
try {
    New-Snapshot -VM $vm -Name $snapshotName -Description "Snapshot created via PowerCLI" -ErrorAction Stop
    Write-Log -Message "Snapshot '$snapshotName' created successfully for VM '$vmName'." -Level "INFO"
    $Summary['Snapshot'] = $snapshotName
    $Summary['Snapshot Status'] = "Created"
} catch {
    Write-Log -Message "Error creating snapshot: $_" -Level "ERROR"
    $Summary['Snapshot'] = $snapshotName
    $Summary['Snapshot Status'] = "Failed"
    $Summary['Error'] = $_
}

#==============================================
# 4. Disconnect from vCenter Server / ESXi Host
#==============================================

Write-Log -Message "Disconnecting from $server..."
try {
    Disconnect-VIServer -Confirm:$false -ErrorAction Stop
    Write-Log -Message "Disconnected from $server." -Level "INFO"
    $Summary['Disconnected'] = "Yes"
} catch {
    Write-Log -Message "Error disconnecting from $server: $_" -Level "ERROR"
    $Summary['Disconnected'] = "Error"
}

#==============================================
# 5. Summary Output
#==============================================
Write-Host "\nSummary:" -ForegroundColor Cyan
foreach ($key in $Summary.Keys) {
    Write-Host "$key: $Summary[$key]"
}
