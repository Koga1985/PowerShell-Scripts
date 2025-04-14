<# 
.SYNOPSIS
    Auto Deploy Home Lab Script for VMware environments.

.DESCRIPTION
    This script automates the deployment of a home lab environment on a VMware vSphere or ESXi host.
    It includes functions to create virtual networks and virtual machines, and to configure Windows Server 
    installation using an ISO file attached to the VM’s CD drive.

    Enhancements:
    - Added detailed inline comments for clarity.
    - Introduced logging functions to write events and errors to a log file.
    - Improved error handling within each function.
    - Uses Write-Verbose for additional runtime information; run the script with -Verbose flag for detailed output.

.PARAMETER VMHost
    The name or IP of the VMware ESXi host or vCenter Server.

.PARAMETER VMFolder
    The folder or location within vCenter where the virtual machines will be deployed.

.PARAMETER Datastore
    The datastore name where the VM files will be stored.

.PARAMETER ISOPath
    Local or network path to the Windows Server installation ISO file.

.NOTES
    Ensure that VMware PowerCLI is installed and connected to your vSphere environment before running this script.
    Adjust the commands if your environment uses different cmdlet names or modules.
#>

# Logging: Define a global log file path where all events and error messages will be recorded.
$Global:LogFile = "C:\Logs\HomeLabDeploy.log"

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

# Log the start of the deployment process.
Write-Log "Starting Home Lab Auto Deploy Script execution."

# Create virtual networks.
Write-Log "Creating virtual networks..."
New-VirtualNetwork -Name "ManagementNetwork" -Subnet "192.168.1.0/24" -Gateway "192.168.1.1"
New-VirtualNetwork -Name "InternalNetwork" -Subnet "192.168.2.0/24" -Gateway "192.168.2.1"

# Create virtual machines.
Write-Log "Creating virtual machines..."
New-VirtualMachine -Name "DC1"         -MemoryGB 4 -CPUs 2 -DiskGB 40
New-VirtualMachine -Name "WebServer1"    -MemoryGB 2 -CPUs 1 -DiskGB 20
New-VirtualMachine -Name "SQLServer1"    -MemoryGB 4 -CPUs 2 -DiskGB 40

# Configure Windows Server installations on VMs.
Write-Log "Configuring Windows Server installation on VMs..."
Install-WindowsServer -VMName "DC1"       -ISOPath $ISOPath
Install-WindowsServer -VMName "WebServer1"  -ISOPath $ISOPath
Install-WindowsServer -VMName "SQLServer1"  -ISOPath $ISOPath

# End of script processing.
Write-Log "Home Lab Auto Deploy Script completed."
