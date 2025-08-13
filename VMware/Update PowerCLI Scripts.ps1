<#
.SYNOPSIS
    Installs or updates the VMware.PowerCLI module and then updates existing PowerShell scripts in a specified directory.
    
.DESCRIPTION
    This script does the following:
      1. Defines a function, Install-Or-Update-PowerCLI, which checks if the VMware.PowerCLI module is installed:
         - If not installed, it installs the latest version.
         - If installed, it updates the module to the latest version.
      2. Ensures that the VMware.PowerCLI module is installed or updated.
      3. Checks if the specified directory (containing PowerShell scripts) exists.
      4. If the directory exists:
         - Retrieves all *.ps1 files within that directory.
         - For each script, reads its content in a single string (to preserve formatting).
         - Replaces the plain "Import-Module VMware.PowerCLI" line with "Import-Module VMware.PowerCLI -Force".
         - Writes the updated content back to the original file.
      5. Provides feedback for each script processed and prints a final completion message.
      
.PARAMETER None
    This script does not require any command-line parameters. All configuration is performed via variables.
    
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - Necessary permissions to install modules and update files in the script directory.
#>


#----------------------------------------------
# Logging Function
#----------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# Admin Rights and PowerShell Version Check
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
# Function: Install-Or-Update-PowerCLI
#----------------------------------------------
function Install-Or-Update-PowerCLI {
    $installedModule = Get-Module -ListAvailable VMware.PowerCLI
    if (-not $installedModule) {
        Write-Log -Message "PowerCLI module not found. Installing the latest version..."
        try {
            Install-Module -Name VMware.PowerCLI -Force -AllowClobber -ErrorAction Stop
            Write-Log -Message "VMware.PowerCLI installed successfully." -Level "INFO"
        } catch {
            Write-Log -Message "Error installing VMware.PowerCLI: $_" -Level "ERROR"
            exit
        }
    } else {
        Write-Log -Message "PowerCLI module is already installed. Updating to the latest version..."
        try {
            Update-Module -Name VMware.PowerCLI -ErrorAction Stop
            Write-Log -Message "VMware.PowerCLI updated successfully." -Level "INFO"
        } catch {
            Write-Log -Message "Error updating VMware.PowerCLI: $_" -Level "ERROR"
            exit
        }
    }
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------


# 1. Ensure VMware.PowerCLI is installed or updated.
Install-Or-Update-PowerCLI

# 2. Import the PowerCLI module.
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Log -Message "VMware.PowerCLI module imported successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error importing VMware.PowerCLI: $_" -Level "ERROR"
    exit
}

# 3. Prompt for the directory containing PowerShell scripts to be updated if not set.
$scriptDirectory = "C:\Path\To\Your\Scripts"  # TODO: Update this path to your scripts folder
if ($scriptDirectory -eq "C:\Path\To\Your\Scripts") {
    $scriptDirectory = Read-Host "Enter the path to your PowerShell scripts directory"
}

# 4. Validate if the script directory exists.
$Summary = @{'Scripts Processed'=0; 'Scripts Updated'=0; 'Scripts Failed'=0}
if (Test-Path -Path $scriptDirectory) {
    $scripts = Get-ChildItem -Path $scriptDirectory -Filter *.ps1
    if ($scripts.Count -eq 0) {
        Write-Log -Message "No PowerShell scripts found in the specified directory: $scriptDirectory." -Level "INFO"
    } else {
        foreach ($script in $scripts) {
            $Summary['Scripts Processed']++
            Write-Log -Message "Processing script: $($script.Name)"
            try {
                $scriptContent = Get-Content -Path $script.FullName -Raw
                $updatedContent = $scriptContent -replace 'Import-Module\s+VMware\.PowerCLI', 'Import-Module VMware.PowerCLI -Force'
                $updatedContent | Set-Content -Path $script.FullName -ErrorAction Stop
                Write-Log -Message "Updated script: $($script.Name)" -Level "INFO"
                $Summary['Scripts Updated']++
            } catch {
                Write-Log -Message "Failed to update script $($script.Name): $_" -Level "ERROR"
                $Summary['Scripts Failed']++
            }
        }
    }
} else {
    Write-Log -Message "The specified directory '$scriptDirectory' does not exist." -Level "ERROR"
}

# 5. Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
foreach ($key in $Summary.Keys) {
    Write-Host "$key: $Summary[$key]"
}
Write-Log -Message "PowerCLI scripts update process completed." -Level "INFO"
