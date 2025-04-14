<#
.SYNOPSIS
    Applies a specific tag to all virtual machines in a vCenter Server or ESXi host.

.DESCRIPTION
    This script does the following:
      1. Checks if the VMware.PowerCLI module is installed (installs it if not) and imports it.
      2. Prompts the user for connection details (vCenter Server/ESXi host, username, and password) and connects.
      3. Retrieves all VMs from the connected environment.
      4. Prompts the user for tag details:
         - Tag name to be applied.
         - Tag category name.
         - Tag description.
      5. Checks if the specified tag exists; if not, verifies (or creates) the tag category and creates the tag.
      6. Iterates over all VMs and assigns the tag.
      7. Disconnects from the vCenter Server/ESXi host.

.NOTES
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module.
      - Appropriate permissions to connect to and modify tags on the vCenter Server/ESXi host.
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a timestamped log message with a specified severity level.
    
    .PARAMETER Message
        The log message text.
    
    .PARAMETER Level
        The log level (e.g., "INFO", "ERROR"). Default is "INFO".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# 1. Ensure VMware.PowerCLI Module is Installed and Imported
#----------------------------------------------
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

#----------------------------------------------
# 2. Connect to vCenter Server or ESXi Host
#----------------------------------------------
# Prompt the user for source connection details
$server = Read-Host "Enter vCenter Server or ESXi host"        # e.g., "vcenter.example.com" or "esxi01.example.com"
$user   = Read-Host "Enter username"                           # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString            # Password is captured securely

Write-Log -Message "Connecting to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 3. Retrieve All Virtual Machines
#----------------------------------------------
Write-Log -Message "Retrieving all virtual machines..."
try {
    $vms = Get-VM -ErrorAction Stop
    Write-Log -Message "Retrieved $($vms.Count) VMs." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving virtual machines: $_" -Level "ERROR"
    Disconnect-VIServer -Confirm:$false
    exit
}

#----------------------------------------------
# 4. Prompt for Tag Information
#----------------------------------------------
$tagName = Read-Host "Enter the tag name you want to apply"
$tagCategoryName = Read-Host "Enter the tag category name"
$tagDescription = Read-Host "Enter the tag description"

#----------------------------------------------
# 5. Check if the Tag and Tag Category Exist (Create if Not)
#----------------------------------------------
try {
    # Try to get the tag by name; if not available, it will return $null
    $tag = Get-Tag -Name $tagName -ErrorAction SilentlyContinue
} catch {
    Write-Log -Message "Error checking existence of tag '$tagName': $_" -Level "ERROR"
}

if (-not $tag) {
    Write-Log -Message "Tag '$tagName' not found. Creating tag..."
    try {
        # Check if the tag category exists; if not, create the tag category
        $tagCategoryObject = Get-TagCategory -Name $tagCategoryName -ErrorAction SilentlyContinue
        if (-not $tagCategoryObject) {
            Write-Log -Message "Tag category '$tagCategoryName' not found. Creating tag category..."
            $tagCategoryObject = New-TagCategory -Name $tagCategoryName -Description $tagDescription -Cardinality Single -ErrorAction Stop
            Write-Log -Message "Tag category '$tagCategoryName' created successfully." -Level "INFO"
        }
        
        # Create the tag within the found or newly created category
        $tag = New-Tag -Name $tagName -Category $tagCategoryObject -Description $tagDescription -ErrorAction Stop
        Write-Log -Message "Tag '$tagName' created successfully." -Level "INFO"
    } catch {
        Write-Log -Message "Error creating tag '$tagName': $_" -Level "ERROR"
        Disconnect-VIServer -Confirm:$false
        exit
    }
} else {
    Write-Log -Message "Tag '$tagName' already exists. Proceeding with assignment." -Level "INFO"
}

#----------------------------------------------
# 6. Apply the Tag to Each Virtual Machine
#----------------------------------------------
foreach ($vm in $vms) {
    Write-Log -Message "Tagging VM '$($vm.Name)' with tag '$tagName' under category '$tagCategoryName'..."
    try {
        New-VIPermission -Tag $tag -Entity $vm -ErrorAction Stop
        Write-Log -Message "Successfully tagged VM '$($vm.Name)'." -Level "INFO"
    } catch {
        Write-Log -Message "Error tagging VM '$($vm.Name)': $_" -Level "ERROR"
    }
}

Write-Log -Message "Tagging process completed." -Level "INFO"

#----------------------------------------------
# 7. Disconnect from vCenter Server or ESXi Host
#----------------------------------------------
Write-Log -Message "Disconnecting from vCenter Server..."
try {
    Disconnect-VIServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from vCenter Server." -Level "INFO"
} catch {
    Write-Log -Message "Error disconnecting from vCenter Server: $_" -Level "ERROR"
}

Write-Log -Message "Script execution completed." -Level "INFO"
