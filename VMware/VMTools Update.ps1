<#
.SYNOPSIS
    Checks the status of VMware Tools on all virtual machines in a vCenter Server or ESXi host and updates them if necessary.
    
.DESCRIPTION
    This script performs the following tasks:
      1. Ensures the VMware.PowerCLI module is installed; if not, installs it.
      2. Imports the VMware.PowerCLI module.
      3. Prompts the user for connection details (vCenter/ESXi host, username, and password) and connects.
      4. Retrieves all VMs in the environment.
      5. For each virtual machine, it checks the status of VMware Tools:
           - If Tools are not installed or not running, it triggers an update without rebooting.
           - Otherwise, it logs that the Tools are up-to-date.
      6. Disconnects from the vCenter/ESXi host.
      
.NOTES
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.1
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module (the script installs it if missing).
      - Sufficient permissions to connect to the vCenter/ESXi host and to manage virtual machines.
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
# 1. Ensure VMware.PowerCLI Module is Installed and Imported
#==============================================
Write-Log -Message "Checking for VMware.PowerCLI module..."
if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
    Write-Log -Message "VMware.PowerCLI module not found. Installing the latest version..." -Level "INFO"
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

# Import the VMware.PowerCLI module
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
$user = Read-Host "Enter username"                              # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString           # Securely capture the password

Write-Log -Message "Connecting to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    exit
}

#==============================================
# 3. Retrieve All Virtual Machines
#==============================================
Write-Log -Message "Retrieving all virtual machines..."
try {
    $vms = Get-VM -ErrorAction Stop
    Write-Log -Message "Retrieved $($vms.Count) virtual machines." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving virtual machines: $_" -Level "ERROR"
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 4. Check VMware Tools Status and Update if Necessary
#==============================================
foreach ($vm in $vms) {
    Write-Log -Message "Checking VMware Tools for VM: $($vm.Name)..." -Level "INFO"
    
    try {
        # Retrieve the VMware Tools status for the VM.
        $toolsStatus = $vm | Get-VMTools | Select-Object -ExpandProperty ToolsVersionStatus
    } catch {
        Write-Log -Message "Error fetching VMware Tools status for VM '$($vm.Name)': $_" -Level "ERROR"
        continue
    }
    
    # If tools are not installed or not running, update them.
    if ($toolsStatus -eq "toolsNotInstalled" -or $toolsStatus -eq "toolsNotRunning") {
        Write-Log -Message "VMware Tools not installed or not running for VM '$($vm.Name)'. Initiating update..." -Level "INFO"
        
        try {
            # Update VMware Tools without rebooting the VM.
            Update-Tools -VM $vm -NoReboot -ErrorAction Stop
            Write-Log -Message "VMware Tools updated successfully for VM '$($vm.Name)'." -Level "INFO"
        } catch {
            Write-Log -Message "Error updating VMware Tools for VM '$($vm.Name)': $_" -Level "ERROR"
        }
    } else {
        Write-Log -Message "VMware Tools already up-to-date for VM '$($vm.Name)'." -Level "INFO"
    }
    
    Write-Log -Message "--------------------------------------------" -Level "INFO"
}

#==============================================
# 5. Disconnect from vCenter Server or ESXi Host
#==============================================
Write-Log -Message "Disconnecting from $server..."
try {
    Disconnect-VIServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from $server." -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from $server: $_" -Level "ERROR"
}

Write-Log -Message "VMware Tools update process completed." -Level "INFO"
