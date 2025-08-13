<#
.SYNOPSIS
    Exports roles and permissions from a vCenter Server or ESXi host to a CSV file.

.DESCRIPTION
    This script checks for the VMware.PowerCLI module and installs it if it is not already installed.
    It then prompts for the vCenter Server or ESXi host connection details (server, username, and password)
    and connects to the server. The script retrieves all the roles from the server and for each role, collects
    associated permissions. A custom property "RoleName" is added to each permission object. Finally, the
    aggregated roles and permissions are exported to a CSV file whose path is supplied by the user.
    
    At the end, the script disconnects from the server cleanly.

.PARAMETER None
    The script runs interactively, prompting the user for connection details and export file path.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - VMware.PowerCLI module.
      - Appropriate connectivity and permissions to connect to a vCenter Server or ESXi host.
#>

#==============================================
# Global Logging Function
#==============================================
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a log message with a timestamp and severity level.
    
    .PARAMETER Message
        The log message text.
    
    .PARAMETER Level
        The severity level for the message (e.g., INFO, ERROR).
        Default is "INFO".
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
# 1. Check for and Install VMware.PowerCLI Module if Needed
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
# 2. Connect to vCenter Server or ESXi Host
#==============================================
$server = Read-Host "Enter vCenter Server or ESXi host"   # e.g., "vcenter.company.com" or "esxi01.company.com"
$user   = Read-Host "Enter username"                      # e.g., "administrator@vsphere.local"
$password = Read-Host "Enter password" -AsSecureString       # Input is secured

Write-Log -Message "Connecting to $server..."
try {
    Connect-VIServer -Server $server -User $user -Password $password -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to $server." -Level "INFO"
} catch {
    Write-Log -Message "Error connecting to $server: $_" -Level "ERROR"
    exit
}

#==============================================
# 3. Prompt for CSV Export File Path
#==============================================
$csvFilePath = Read-Host "Enter the path for exporting roles and permissions (e.g., C:\Export\Roles_Permissions.csv)"

#==============================================
# 4. Retrieve Roles and Permissions and Export to CSV
#==============================================
Write-Log -Message "Retrieving roles and permissions..."


# Summary variable
$Summary = $false

try {
    $rolesPermissions = @()
    Get-VIRole | ForEach-Object {
        $role = $_
        $permissions = Get-VIPermission -Role $role -ErrorAction SilentlyContinue | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name "RoleName" -Value $role.Name -Force -PassThru
        }
        if ($permissions) {
            $rolesPermissions += $permissions
        }
    }
    $rolesPermissions | Export-Csv -Path $csvFilePath -NoTypeInformation -ErrorAction Stop
    Write-Log -Message "Roles and permissions successfully exported to $csvFilePath." -Level "INFO"
    $Summary = $true
} catch {
    Write-Log -Message "Error exporting roles and permissions: $_" -Level "ERROR"
    $Summary = $false
}

#==============================================
# 5. Disconnect from vCenter Server or ESXi Host
#==============================================

# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
Write-Host "Roles and permissions export: $($Summary ? 'Success' : 'Failed')"
Write-Host "Export file: $csvFilePath"

Write-Log -Message "Disconnecting from $server..."
Disconnect-VIServer -Confirm:$false | Out-Null
Write-Log -Message "Disconnected from $server." -Level "INFO"
