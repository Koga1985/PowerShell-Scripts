<#
.SYNOPSIS
    Auto Deploy Home Lab Script for VMware environments (NIST/STIG-aligned).

.DESCRIPTION
    Automates deployment of a home lab on VMware vSphere/ESXi. Functions for creating virtual networks, VMs, and configuring Windows Server installation via ISO.
    All actions use robust error handling, input validation, and logging. Run with least privilege and review for compliance.

.PARAMETER VMHost
    The name or IP of the VMware ESXi host or vCenter Server.
.PARAMETER VMFolder
    The folder or location within vCenter where the virtual machines will be deployed.
.PARAMETER Datastore
    The datastore name where the VM files will be stored.
.PARAMETER ISOPath
    Local or network path to the Windows Server installation ISO file.
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   2025-08-20
    Version:        1.1
    Compliance:     NIST SP 800-53, STIG PowerShell Security Requirements
    Security:       Input validation, logging, no hardcoded credentials, least privilege
    Disclaimer:     Scripts are provided as-is. Review for your environment and compliance needs.
    Ensure VMware PowerCLI is installed and connected to your vSphere environment before running. Adjust commands for your environment.
#>


# Logging: Define a global log file path where all events and error messages will be recorded.
$Global:LogFile = "C:\Logs\HomeLabDeploy.log"

# Check for VMware PowerCLI module
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Host "ERROR: VMware PowerCLI module is not installed." -ForegroundColor Red
    exit 1
}

# Check for connection to vCenter/ESXi
if (-not (Get-VMHost -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Not connected to a vCenter or ESXi host. Run 'Connect-VIServer' first." -ForegroundColor Red
    exit 1
}

# Function to log messages
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timeStamp [$Level] $Message"
    # Output to console
    Write-Host $logMessage
    # Append to the log file
    Add-Content -Path $Global:LogFile -Value $logMessage
}


# VARIABLES
$VMHost    = "YourVMHost"           # Replace with your VMware ESXi host or vCenter Server address.
$VMFolder  = "HomeLab"              # Folder (or datacenter/cluster) where VMs will be created.
$Datastore = "YourDatastore"        # Replace with the name of your datastore.
$ISOPath   = "C:\Path\To\WindowsServerISO.iso"   # Full path to the Windows Server ISO file.

# Validate required variables
foreach ($var in @('VMHost','VMFolder','Datastore','ISOPath')) {
    if (-not (Get-Variable $var -ValueOnly)) {
        Write-Host "ERROR: Variable $var is not set." -ForegroundColor Red
        exit 1
    }
}

<#
Reusable function to create multiple VMs from a hashtable array
#>
function New-VirtualMachines {
    param(
        [Parameter(Mandatory)]
        [array]$VMList
    )
    foreach ($vm in $VMList) {
        New-VirtualMachine -Name $vm.Name -MemoryGB $vm.MemoryGB -CPUs $vm.CPUs -DiskGB $vm.DiskGB
    }
}

# Function: Create a new virtual machine.
function New-VirtualMachine {
    <#
    .SYNOPSIS
        Creates a new virtual machine with specified resources.

    .PARAMETER Name
        The name to assign to the new virtual machine.
    .PARAMETER MemoryGB
        The size of the virtual machine's memory in GB.
    .PARAMETER CPUs
        The number of virtual CPUs to allocate.
    .PARAMETER DiskGB
        The size of the virtual machine's disk in GB.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$MemoryGB,
        [Parameter(Mandatory=$true)][int]$CPUs,
        [Parameter(Mandatory=$true)][int]$DiskGB
    )

    Write-Log "Starting creation of VM '$Name' with $MemoryGB GB memory, $CPUs CPU(s), and $DiskGB GB disk."

    try {
        # The New-VM cmdlet is part of VMware PowerCLI. Adjust the parameters as needed.
        New-VM -Name $Name `
               -MemoryGB $MemoryGB `
               -NumCpu $CPUs `
               -DiskGB $DiskGB `
               -VMHost $VMHost `
               -Datastore $Datastore `
               -Location $VMFolder

        Write-Log "Virtual machine '$Name' created successfully."
    }
    catch {
        Write-Log "Error while creating virtual machine '$Name'. Error details: $_" "ERROR"
    }
}

<#
Reusable function to create multiple networks from a hashtable array
#>
function New-VirtualNetworks {
    param(
        [Parameter(Mandatory)]
        [array]$NetList
    )
    foreach ($net in $NetList) {
        New-VirtualNetwork -Name $net.Name -Subnet $net.Subnet -Gateway $net.Gateway
    }
}

# Function: Create a new virtual network.
function New-VirtualNetwork {
    <#
    .SYNOPSIS
        Creates and configures a new virtual network (virtual switch and network adapter).

    .PARAMETER Name
        The name of the virtual network.
    .PARAMETER Subnet
        The IP subnet (in CIDR notation) for the network.
    .PARAMETER Gateway
        The default gateway IP address for the network.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Subnet,
        [Parameter(Mandatory=$true)][string]$Gateway
    )

    Write-Log "Starting creation of virtual network '$Name' with subnet $Subnet and gateway $Gateway."

    try {
        # Create a virtual switch. Adjust this command if your environment uses different cmdlets.
        New-VirtualSwitch -Name $Name -VMHost $VMHost
        Write-Log "Virtual switch '$Name' created successfully."

        # Create a network adapter on the host for the virtual switch.
        New-VMHostNetworkAdapter -VMHost $VMHost -VirtualSwitch $Name
        Write-Log "Network adapter on virtual switch '$Name' created successfully."

        # Retrieve the virtual network object for further configuration.
        $network = Get-VirtualNetwork -Name $Name

        # Set the network configuration including subnet and gateway.
        Set-VMHostNetwork -VMHostNetwork $network -Subnet $Subnet -Gateway $Gateway
        Write-Log "Virtual network '$Name' configured with subnet $Subnet and gateway $Gateway."

    }
    catch {
        Write-Log "Error while creating virtual network '$Name'. Error details: $_" "ERROR"
    }
}

# Function: Install and configure a Windows Server VM
function Install-WindowsServer {
    <#
    .SYNOPSIS
        Configures a VM to boot from a Windows Server installation ISO.

    .PARAMETER VMName
        The name of the target virtual machine.
    .PARAMETER ISOPath
        The path to the Windows Server installation ISO.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$VMName,
        [Parameter(Mandatory=$true)][string]$ISOPath
    )

    Write-Log "Configuring VM '$VMName' to use the ISO $ISOPath for installation."

    try {
        # Retrieve the virtual machine object
        $VM = Get-VM -Name $VMName
        if (-not $VM) {
            Write-Log "VM '$VMName' not found." "ERROR"
            return
        }

        # Set the VM's CD drive to connect at power on and attach to the ISO.
        # First, enable the CD drive connection properties for booting.
        Set-VM -VM $VM -CD -StartConnected $true -Connected $true

        # Get the CD/DVD drive object and configure it with the ISO file.
        $CDDrive = Get-CDDrive -VM $VM
        if (-not $CDDrive) {
            Write-Log "No CD drive found on VM '$VMName'." "ERROR"
            return
        }

        $CDDrive | Set-CDDrive -IsoPath $ISOPath -StartConnected $true -Connected $true
        Write-Log "Windows Server ISO attached to VM '$VMName' successfully."
    }
    catch {
        Write-Log "Error while configuring ISO for VM '$VMName'. Error details: $_" "ERROR"
    }
}


# ----------------------- SCRIPT EXECUTION STARTS HERE -----------------------

Write-Log "Starting Home Lab Auto Deploy Script execution."

# Define networks and VMs as arrays of hashtables for easy expansion
$Networks = @(
    @{ Name = "ManagementNetwork"; Subnet = "192.168.1.0/24"; Gateway = "192.168.1.1" },
    @{ Name = "InternalNetwork";   Subnet = "192.168.2.0/24"; Gateway = "192.168.2.1" }
)
$VMs = @(
    @{ Name = "DC1";        MemoryGB = 4; CPUs = 2; DiskGB = 40 },
    @{ Name = "WebServer1"; MemoryGB = 2; CPUs = 1; DiskGB = 20 },
    @{ Name = "SQLServer1"; MemoryGB = 4; CPUs = 2; DiskGB = 40 }
)

Write-Log "Creating virtual networks..."
New-VirtualNetworks -NetList $Networks

Write-Log "Creating virtual machines..."
New-VirtualMachines -VMList $VMs

Write-Log "Configuring Windows Server installation on VMs..."
foreach ($vm in $VMs) {
    Install-WindowsServer -VMName $vm.Name -ISOPath $ISOPath
}

# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
Write-Host "Networks deployed: $($Networks | ForEach-Object { $_.Name } | Out-String)"
Write-Host "VMs deployed: $($VMs | ForEach-Object { $_.Name } | Out-String)"
Write-Log "Home Lab Auto Deploy Script completed."
