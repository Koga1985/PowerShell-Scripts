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
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.0
    Prerequisites:
      - PowerShell 5.1 or later.
      - Necessary permissions to install modules and update files in the script directory.
#>

#----------------------------------------------
# Function: Install-Or-Update-PowerCLI
#----------------------------------------------
function Install-Or-Update-PowerCLI {
    <#
    .SYNOPSIS
        Ensures the VMware.PowerCLI module is installed and updated to the latest version.
    
    .DESCRIPTION
        This function checks if the VMware.PowerCLI module is available.
        - If it is not found, it installs the latest version.
        - If found, it updates the module.
    #>
    # Retrieve module information if available.
    $installedModule = Get-Module -ListAvailable VMware.PowerCLI

    if (-not $installedModule) {
        Write-Host "PowerCLI module not found. Installing the latest version..."
        try {
            Install-Module -Name VMware.PowerCLI -Force -AllowClobber -ErrorAction Stop
            Write-Host "VMware.PowerCLI installed successfully."
        } catch {
            Write-Host "Error installing VMware.PowerCLI: $_"
            exit
        }
    } else {
        Write-Host "PowerCLI module is already installed. Updating to the latest version..."
        try {
            Update-Module -Name VMware.PowerCLI -ErrorAction Stop
            Write-Host "VMware.PowerCLI updated successfully."
        } catch {
            Write-Host "Error updating VMware.PowerCLI: $_"
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
    Write-Host "VMware.PowerCLI module imported successfully."
} catch {
    Write-Host "Error importing VMware.PowerCLI: $_"
    exit
}

# 3. Set the directory containing PowerShell scripts to be updated.
$scriptDirectory = "C:\Path\To\Your\Scripts"  # TODO: Update this path to your scripts folder

# 4. Validate if the script directory exists.
if (Test-Path -Path $scriptDirectory) {
    # Retrieve all .ps1 files in the specified directory.
    $scripts = Get-ChildItem -Path $scriptDirectory -Filter *.ps1
    
    # If no scripts are found, output a message.
    if ($scripts.Count -eq 0) {
        Write-Host "No PowerShell scripts found in the specified directory: $scriptDirectory."
    } else {
        # Process each script.
        foreach ($script in $scripts) {
            Write-Host "Processing script: $($script.Name)"
            try {
                # Read the entire content of the script file.
                $scriptContent = Get-Content -Path $script.FullName -Raw
                
                # Update PowerCLI related import line to force-load the module.
                # The -replace operator uses a regular expression pattern.
                $updatedContent = $scriptContent -replace 'Import-Module\s+VMware\.PowerCLI', 'Import-Module VMware.PowerCLI -Force'
                
                # Write the updated content back to the original file.
                $updatedContent | Set-Content -Path $script.FullName -ErrorAction Stop
                
                Write-Host "Updated script: $($script.Name)"
            } catch {
                Write-Host "Failed to update script $($script.Name): $_"
            }
        }
    }
} else {
    Write-Host "The specified directory '$scriptDirectory' does not exist."
}

Write-Host "PowerCLI scripts update process completed."
