<#
.SYNOPSIS
    Removes all snapshots from a specified virtual machine on a vCenter Server or ESXi host.

.DESCRIPTION
    This script performs the following steps:
      1. Ensures that the VMware.PowerCLI module is installed; if not, it installs it.
      2. Imports the VMware.PowerCLI module.
      3. Prompts the user for connection details (vCenter/ESXi host, username, and password) and connects.
      4. Prompts for the target virtual machine name.
      5. Retrieves the virtual machine object and all its associated snapshots.
      6. If snapshots exist, it iterates over them and removes each one without confirmation.
      7. Disconnects from the vCenter/ESXi host.
#
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   August 14, 2025
    Version:        1.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a log message with a timestamp and severity level.
    
    .PARAMETER Message
        The text to be logged.
    
    .PARAMETER Level
        The severity of the message (e.g., "INFO" or "ERROR"). Default is "INFO".
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
# 1. Install VMware.PowerCLI Module if Not Installed
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
        Write-Log -Message "Error installing VMware.PowerCLI module: $_" -Level "ERROR"
        exit
    }
} else {
    Write-Log -Message "VMware.PowerCLI module already installed." -Level "INFO"
}

#==============================================
# 2. Import the VMware.PowerCLI Module
#==============================================
Write-Log -Message "Importing VMware.PowerCLI module..."
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Log -Message "VMware.PowerCLI module imported successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error importing VMware.PowerCLI module: $_" -Level "ERROR"
    exit
}

#==============================================
# 3. Connect to vCenter Server or ESXi Host
#==============================================
# Prompt for connection details
$server = Read-Host "Enter vCenter Server or ESXi host"      # e.g., "vcenter.example.com" or "esxi01.example.com"
$user   = Read-Host "Enter username"                         # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString          # Securely capture the password

Write-Log -Message "Connecting to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    exit
}

#==============================================
# 4. Specify the Virtual Machine Name and Retrieve the VM
#==============================================
# Prompt for the virtual machine name
$vmName = Read-Host "Enter the virtual machine name"

# Retrieve the VM object; use SilentlyContinue to handle if not found
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Log -Message "Error: Virtual machine '$vmName' not found." -Level "ERROR"
    Disconnect-VIServer -Confirm:$false
    exit
}
Write-Log -Message "Virtual machine '$vmName' found." -Level "INFO"

#==============================================
# 5. Get and Remove All Snapshots for the Virtual Machine
#==============================================

# Summary variable
$Summary = @{}

# Retrieve all snapshots associated with the VM
$snapshots = Get-Snapshot -VM $vm
if ($snapshots.Count -eq 0) {
    Write-Log -Message "No snapshots found for virtual machine '$vmName'." -Level "INFO"
    $Summary['Snapshots Removed'] = 'None Found'
} else {
    Write-Log -Message "Found $($snapshots.Count) snapshot(s) for VM '$vmName'. Removing snapshots..." -Level "INFO"
    $removed = 0
    $failed = 0
    foreach ($snapshot in $snapshots) {
        try {
            Write-Log -Message "Removing snapshot '$($snapshot.Name)' from VM '$vmName'..." -Level "INFO"
            Remove-Snapshot -Snapshot $snapshot -Confirm:$false -ErrorAction Stop
            Write-Log -Message "Snapshot '$($snapshot.Name)' removed successfully." -Level "INFO"
            $removed++
        } catch {
            Write-Log -Message "Error removing snapshot '$($snapshot.Name)': $_" -Level "ERROR"
            $failed++
        }
    }
    $Summary['Snapshots Removed'] = $removed
    $Summary['Snapshots Failed'] = $failed
}

#==============================================
# 6. Disconnect from vCenter Server or ESXi Host
#==============================================

# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
foreach ($key in $Summary.Keys) {
    Write-Host "$key: $Summary[$key]"
}
Write-Host "Target VM: $vmName"

Write-Log -Message "Disconnecting from $server..."
try {
    Disconnect-VIServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from $server." -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from $server: $_" -Level "ERROR"
}

Write-Log -Message "Snapshot removal process completed." -Level "INFO"
