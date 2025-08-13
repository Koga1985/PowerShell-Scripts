<#
.SYNOPSIS
    Imports roles and permissions from a CSV file and applies them to a vCenter Server or ESXi host.
    
.DESCRIPTION
    This script performs the following tasks:
      1. Checks if the VMware.PowerCLI module is installed; if not, installs it.
      2. Imports the PowerCLI module.
      3. Prompts for vCenter/ESXi host connection details (server, username, and password) and connects to the host.
      4. Prompts for the path to a CSV file which contains roles and permissions information.
      5. Validates that the CSV file exists and then reads its contents.
      6. Iterates through each CSV entry:
           - Checks if the specified role exists.
           - Checks if the target entity (the managed object's ID) exists.
           - Applies the specified permission using New-VIPermission.
      7. Exports any errors to the console.
      8. Disconnects from the vCenter/ESXi host.
      
.PARAMETER None
    This script is interactive and prompts the user for all required inputs.
    
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites: 
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module (this script installs it if missing).
      - Valid credentials and permissions to access and modify permissions on the vCenter/ESXi host.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Writes log messages with timestamps and a severity level.
    
    .PARAMETER Message
        The log message text.
    
    .PARAMETER Level
        The severity level, e.g., "INFO" or "ERROR". Default value is "INFO".
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
        Write-Log -Message "VMware.PowerCLI module installed successfully." -Level "INFO"
    }
    catch {
        Write-Log -Message "Error installing VMware.PowerCLI module: $_" -Level "ERROR"
        exit
    }
} else {
    Write-Log -Message "VMware.PowerCLI module already installed." -Level "INFO"
}

Write-Log -Message "Importing VMware.PowerCLI module..."
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Log -Message "VMware.PowerCLI module imported successfully." -Level "INFO"
}
catch {
    Write-Log -Message "Error importing VMware.PowerCLI module: $_" -Level "ERROR"
    exit
}

#==============================================
# 2. Connect to vCenter Server or ESXi Host
#==============================================
# Prompt user for connection details
$server = Read-Host "Enter vCenter Server or ESXi host"      # e.g., "vcenter.company.com" or "esxi01.company.com"
$user   = Read-Host "Enter username"                         # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString          # Securely capture the password

Write-Log -Message "Connecting to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
}
catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    exit
}

#==============================================
# 3. Specify and Validate the CSV File Path
#==============================================
$csvFilePath = Read-Host "Enter the path to the CSV file (e.g., C:\Path\To\Import\Roles_Permissions.csv)"
if (-not (Test-Path -Path $csvFilePath)) {
    Write-Log -Message "Error: The CSV file does not exist at $csvFilePath." -Level "ERROR"
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 4. Read Roles and Permissions from the CSV File
#==============================================
Write-Log -Message "Reading CSV file from $csvFilePath..."
try {
    $rolesPermissions = Import-Csv -Path $csvFilePath -ErrorAction Stop
    Write-Log -Message "CSV file loaded successfully." -Level "INFO"
}
catch {
    Write-Log -Message "Error reading CSV file: $_" -Level "ERROR"
    Disconnect-VIServer -Confirm:$false
    exit
}

#==============================================
# 5. Iterate Through Each CSV Entry and Apply Permissions
#==============================================
Write-Log -Message "Applying roles and permissions from CSV..."

# Summary variable
$Summary = @{}

$successCount = 0
$failCount = 0
foreach ($entry in $rolesPermissions) {
    $success = $true
    $role = Get-VIRole -Name $entry.RoleName -ErrorAction SilentlyContinue
    if (-not $role) {
        Write-Log -Message "Role '$($entry.RoleName)' not found. Skipping entry." -Level "ERROR"
        $success = $false
        $failCount++
        continue
    }
    $entity = Get-View -Id $entry.Entity -ErrorAction SilentlyContinue
    if (-not $entity) {
        Write-Log -Message "Entity '$($entry.Entity)' not found. Skipping entry." -Level "ERROR"
        $success = $false
        $failCount++
        continue
    }
    try {
        New-VIPermission -Role $role -Principal $entry.Principal -Entity $entity -Propagate $entry.Propagate -ErrorAction Stop
        Write-Log -Message "Permission for '$($entry.Principal)' applied on '$($entry.Entity)'." -Level "INFO"
        $successCount++
    } catch {
        Write-Log -Message "Error applying permission for '$($entry.Principal)' on '$($entry.Entity)': $_" -Level "ERROR"
        $success = $false
        $failCount++
    }
    $Summary[$entry.Principal] = $success
}

Write-Log -Message "Roles and permissions imported successfully from $csvFilePath." -Level "INFO"

#==============================================
# 6. Disconnect from vCenter Server or ESXi Host
#==============================================

# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
Write-Host "Total permissions applied: $successCount"
Write-Host "Total failures: $failCount"
Write-Host "Import file: $csvFilePath"

Write-Log -Message "Disconnecting from $server..."
try {
    Disconnect-VIServer -Confirm:$false | Out-Null
    Write-Log -Message "Disconnected from $server." -Level "INFO"
}
catch {
    Write-Log -Message "Error disconnecting from $server: $_" -Level "ERROR"
}

Write-Log -Message "Script execution completed." -Level "INFO"
