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
#
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   August 14, 2025
    Version:        1.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>


#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# 0. Admin Rights and PowerShell Version Check
#----------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script must be run as Administrator." -ForegroundColor Red
    exit
}
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.0 or higher is required." -ForegroundColor Red
    exit
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

# Summary variable
$Summary = @{'VMs Processed'=0; 'VMs Tagged'=0; 'VMs Failed'=0}

$server = Read-Host "Enter vCenter Server or ESXi host"        # e.g., "vcenter.example.com" or "esxi01.example.com"
$user   = Read-Host "Enter username"                           # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString         # Password is captured securely

Write-Log -Message "Connecting to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
    $Summary['Connection'] = "Success"
} catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    $Summary['Connection'] = "Failed"
    Write-Host "\nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
    exit
}

#----------------------------------------------
# 3. Retrieve All Virtual Machines
#----------------------------------------------

Write-Log -Message "Retrieving all virtual machines..."
try {
    $vms = Get-VM -ErrorAction Stop
    Write-Log -Message "Retrieved $($vms.Count) VMs." -Level "INFO"
    $Summary['VMs Processed'] = $vms.Count
} catch {
    Write-Log -Message "Error retrieving virtual machines: $_" -Level "ERROR"
    $Summary['VMs Processed'] = 0
    Disconnect-VIServer -Confirm:$false
    Write-Host "\nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
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
        $Summary['VMs Tagged']++
    } catch {
        Write-Log -Message "Error tagging VM '$($vm.Name)': $_" -Level "ERROR"
        $Summary['VMs Failed']++
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
    $Summary['Disconnected'] = "Yes"
} catch {
    Write-Log -Message "Error disconnecting from vCenter Server: $_" -Level "ERROR"
    $Summary['Disconnected'] = "Error"
}

#----------------------------------------------
# 8. Summary Output
#----------------------------------------------
Write-Log -Message "Script execution completed." -Level "INFO"
Write-Host "\nSummary:" -ForegroundColor Cyan
foreach ($key in $Summary.Keys) {
    Write-Host "$key: $Summary[$key]"
}
