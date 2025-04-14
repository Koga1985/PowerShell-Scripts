<#
.SYNOPSIS
    Adds specified VLANs to a Virtual Switch on a vCenter Server or ESXi host using VMware PowerCLI.

.DESCRIPTION
    This script ensures the VMware PowerCLI module is installed and imported, then prompts the user for connection details
    (vCenter Server/ESXi host, credentials) and the target vSwitch name along with VLAN IDs to be added.
    For each VLAN ID provided, the script checks if a Virtual Port Group exists on the vSwitch.
    If not, a new port group is created with the specified VLAN ID.
    The script logs progress and errors, and disconnects from the host when complete.

.PARAMETER (None)
    The script is interactive. Users will be prompted for necessary details.

.PREREQUISITES
    - Administrative privileges.
    - Network connectivity to the vCenter Server or ESXi host.
    - Sufficient permissions to create port groups and modify networking settings.
    - VMware PowerCLI module access.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Writes a message with a timestamp and specified severity level to the console and optionally to a file.
    
    .PARAMETER Message
        The log message.
    
    .PARAMETER Level
        The severity level (INFO, ERROR, etc.). Default is INFO.
    
    .PARAMETER LogFile
        Optional file path to append the log message.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$Level = "INFO",
        
        [string]$LogFile
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "$timeStamp [$Level] $Message"
    
    # Output to the console
    Write-Host $formattedMessage
    
    # Append to the log file if provided
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $formattedMessage
    }
}

#==============================================
# 1. Ensure VMware.PowerCLI Module is Installed and Imported
#==============================================
Write-Log -Message "Checking for VMware.PowerCLI module..."
try {
    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-Log -Message "VMware.PowerCLI module not found. Installing..." -Level "INFO"
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber
    }
    Write-Log -Message "Importing VMware.PowerCLI module..."
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Log -Message "VMware.PowerCLI module imported successfully." -Level "INFO"
} 
catch {
    Write-Log -Message "Error installing or importing VMware.PowerCLI module: $_" -Level "ERROR"
    exit
}

#==============================================
# 2. Prompt for Connection Details and Connect
#==============================================
# Prompt the user for vCenter or ESXi connection details
$server   = Read-Host "Enter vCenter Server or ESXi host"
$user     = Read-Host "Enter username"
$password = Read-Host "Enter password" -AsSecureString

# Attempt to connect to the specified server
Write-Log -Message "Attempting connection to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Connected to $server successfully." -Level "INFO"
} 
catch {
    Write-Log -Message "Failed to connect to $server. Check your credentials or network. Error: $_" -Level "ERROR"
    exit
}

#==============================================
# 3. Prompt for vSwitch Name and VLAN IDs
#==============================================
# Ask user for the vSwitch name
$vSwitchName = Read-Host "Enter the vSwitch name (e.g., vSwitch0)"

# Ask for VLAN IDs as a comma-separated list and convert them to integers
$vlanIDs = (Read-Host "Enter the VLAN IDs to add (comma-separated, e.g., 100,200,300)") -split ',' |
    ForEach-Object { 
        $_.Trim() | ForEach-Object { [int]$_ } 
    }

#==============================================
# 4. Retrieve the vSwitch and Add VLANs
#==============================================
try {
    Write-Log -Message "Retrieving vSwitch: $vSwitchName..."
    $vSwitch = Get-VirtualSwitch -Name $vSwitchName -ErrorAction Stop
    Write-Log -Message "Found vSwitch: $vSwitchName." -Level "INFO"
} 
catch {
    Write-Log -Message "vSwitch '$vSwitchName' not found. Verify the name and try again. Error: $_" -Level "ERROR"
    Disconnect-VIServer -Confirm:$false
    exit
}

# Loop through each VLAN ID, check for existing port group, and create one if needed
foreach ($vlanID in $vlanIDs) {
    Write-Log -Message "Processing VLAN ID: $vlanID..."
    try {
        # Retrieve all port groups associated with the vSwitch
        $portGroups = Get-VirtualPortGroup -VirtualSwitch $vSwitch
        
        # Check if the current VLAN ID is already in use in a port group
        if ($portGroups | Where-Object { $_.VlanId -eq $vlanID }) {
            Write-Log -Message "VLAN $vlanID already exists on $vSwitchName. Skipping..." -Level "INFO"
        } 
        else {
            # Define a new port group name, e.g., VLAN-100
            $pgName = "VLAN-$vlanID"
            Write-Log -Message "Creating port group '$pgName' on $vSwitchName with VLAN $vlanID..."
            New-VirtualPortGroup -Name $pgName -VirtualSwitch $vSwitch -VlanId $vlanID -ErrorAction Stop
            Write-Log -Message "VLAN $vlanID added to $vSwitchName as port group '$pgName'." -Level "INFO"
        }
    }
    catch {
        Write-Log -Message "Failed to add VLAN $vlanID to $vSwitchName. Error: $_" -Level "ERROR"
    }
}

#==============================================
# 5. Disconnect from vCenter Server / ESXi Host
#==============================================
Write-Log -Message "Disconnecting from $server..."
try {
    Disconnect-VIServer -Confirm:$false
    Write-Log -Message "Disconnected from $server." -Level "INFO"
} 
catch {
    Write-Log -Message "Error disconnecting from $server: $_" -Level "ERROR"
}
