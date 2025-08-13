<#
.SYNOPSIS
    Deploys a new ESXi installation virtual machine on an ESXi host using PowerCLI.

.DESCRIPTION
    This script performs the following actions:
      1. Checks for the VMware.PowerCLI module and installs it if it’s not available.
      2. Prompts the user for ESXi host connection details and configuration parameters
         (such as datastore, network, and the installer ISO location).
      3. Connects to the specified ESXi host.
      4. Creates a new virtual machine using the first available resource pool from the cluster.
      5. Attaches the specified ESXi Installer ISO to the VM’s CD drive.
      6. Configures the network adapter of the VM.
      7. Powers on the VM and waits for a predetermined period (for the installation to complete).
      8. Powers off the VM after installation.
      9. Disconnects from the ESXi host.
      
    This automated approach helps streamline ESXi deployments using PowerCLI.

.PARAMETER None
    The script is interactive and will prompt for all necessary input parameters.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module (if not installed, the script will install it).
      - Sufficient privileges to access and manage the target ESXi host.
      - Correct connectivity and credentials for the ESXi host.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Logs messages with a timestamp and a specified severity level.
        
    .PARAMETER Message
        The log message text.
        
    .PARAMETER Level
        Severity level of the log message (e.g., INFO, ERROR).
        The default level is "INFO".
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#==============================================
# 1. Ensure VMware.PowerCLI Module is Installed and Imported
#==============================================

# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script must be run as Administrator." -ForegroundColor Red
    exit
}

# Check for PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.0 or higher is required." -ForegroundColor Red
    exit
}

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
# 2. Define Variables and Prompt for User Input
#==============================================
# Prompt for ESXi host connection details and configuration settings
$esxiHost        = Read-Host "Enter ESXi Host IP"          # e.g., "192.168.1.10"
$esxiUsername    = Read-Host "Enter ESXi Username"         # e.g., "root"
$esxiPassword    = Read-Host "Enter ESXi Password" -AsSecureString
$esxiDatastore   = Read-Host "Enter Datastore Name"        # e.g., "datastore1"
$esxiNetwork     = Read-Host "Enter Network Name"          # e.g., "VM Network"
$esxiInstallerISO= Read-Host "Enter path to ESXi Installer ISO"  # e.g., "C:\ISOs\ESXiInstaller.iso"

#==============================================
# 3. Connect to the ESXi Host
#==============================================
Write-Log -Message "Connecting to ESXi host: $esxiHost..."
try {
    Connect-VIServer -Server $esxiHost -User $esxiUsername -Password $esxiPassword -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to ESXi host: $esxiHost" -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to ESXi host: $_" -Level "ERROR"
    exit
}

#==============================================
# 4. Create a New Virtual Machine Configuration
#==============================================

# Summary variable
$Summary = @{}

Write-Log -Message "Creating new virtual machine 'ESXi-Deploy-VM'..."
try {
    $vmConfig = New-VM -Name "ESXi-Deploy-VM" -ResourcePool (Get-Cluster).ResourcePool -Datastore $esxiDatastore -ErrorAction Stop
    Write-Log -Message "Virtual machine 'ESXi-Deploy-VM' created successfully." -Level "INFO"
    $Summary['Create VM'] = $true
} catch {
    Write-Log -Message "Error creating virtual machine: $_" -Level "ERROR"
    $Summary['Create VM'] = $false
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 5. Attach the ESXi Installer ISO to the Virtual Machine
#==============================================
Write-Log -Message "Attaching ISO '$esxiInstallerISO' to VM 'ESXi-Deploy-VM'..."
try {
    $cdDrive = Get-CDDrive -VM $vmConfig -ErrorAction Stop
    Set-CDDrive -CD $cdDrive -ISOPath $esxiInstallerISO -StartConnected $true -Confirm:$false -ErrorAction Stop
    Write-Log -Message "ISO attached successfully." -Level "INFO"
    $Summary['Attach ISO'] = $true
} catch {
    Write-Log -Message "Error attaching ISO: $_" -Level "ERROR"
    $Summary['Attach ISO'] = $false
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 6. Configure the Network Adapter
#==============================================
Write-Log -Message "Configuring network adapter for VM 'ESXi-Deploy-VM'..."
try {
    $networkAdapter = Get-NetworkAdapter -VM $vmConfig -ErrorAction Stop
    Set-NetworkAdapter -NetworkAdapter $networkAdapter -NetworkName $esxiNetwork -Confirm:$false -ErrorAction Stop
    Write-Log -Message "Network adapter configured successfully." -Level "INFO"
    $Summary['Configure Network Adapter'] = $true
} catch {
    Write-Log -Message "Error configuring network adapter: $_" -Level "ERROR"
    $Summary['Configure Network Adapter'] = $false
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 7. Power on the Virtual Machine
#==============================================
Write-Log -Message "Powering on VM 'ESXi-Deploy-VM'..."
try {
    Start-VM -VM $vmConfig -ErrorAction Stop | Out-Null
    Write-Log -Message "VM started. Waiting for ESXi installation to complete..." -Level "INFO"
    $Summary['Power On VM'] = $true
} catch {
    Write-Log -Message "Error starting VM: $_" -Level "ERROR"
    $Summary['Power On VM'] = $false
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 8. Wait for ESXi Installation to Complete
#==============================================
# Pause execution to allow the ESXi installation to finish.
$waitTime = 300  # Wait time in seconds; adjust as needed
Write-Log -Message "Waiting for $waitTime seconds for ESXi installation to complete..."
Start-Sleep -Seconds $waitTime

#==============================================
# 9. Power Off the Virtual Machine After Installation
#==============================================
Write-Log -Message "Powering off VM 'ESXi-Deploy-VM' after installation..."
try {
    Stop-VM -VM $vmConfig -Confirm:$false -ErrorAction Stop | Out-Null
    Write-Log -Message "VM powered off successfully." -Level "INFO"
    $Summary['Power Off VM'] = $true
} catch {
    Write-Log -Message "Error stopping VM: $_" -Level "ERROR"
    $Summary['Power Off VM'] = $false
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 10. Disconnect from the ESXi Host
#==============================================

# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
foreach ($step in $Summary.Keys) {
    Write-Host "$step: $($Summary[$step] ? 'Success' : 'Failed')"
}

Write-Log -Message "Disconnecting from ESXi host: $esxiHost..."
try {
    Disconnect-VIServer -Confirm:$false -ErrorAction Stop
    Write-Log -Message "Disconnected from ESXi host: $esxiHost" -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from ESXi host: $_" -Level "ERROR"
}

Write-Log -Message "ESXi deployment completed successfully." -Level "INFO"
