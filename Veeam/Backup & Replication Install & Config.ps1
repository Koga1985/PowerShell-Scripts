<#
.SYNOPSIS
    Automated Deployment Script for Veeam Backup & Replication.

.DESCRIPTION
    This script automates the deployment of Veeam Backup & Replication by performing the following tasks:
      - Creating a target installation directory.
      - Downloading the Veeam installer ISO if it does not exist.
      - Mounting the ISO and formatting the mounted volume.
      - Installing Veeam Backup & Replication silently.
      - Dismounting the ISO.
      - Configuring the Veeam Management Database using the specified service account credentials.
      - Importing a Veeam license.
      - Starting necessary Veeam services.

    Prerequisites:
      - PowerShell running with administrative privileges.
      - Internet connectivity to download the installer.
      - The Veeam installer URL, license file location, and service account credentials must be updated to match your environment.

.NOTES
    Tested on Windows PowerShell 5.1. Modify paths and parameters as needed.
#>

#==============================================
# Configuration Variables
#==============================================
$veeamInstallerUrl      = "https://download.veeam.com/veeambackup&replication_11.0.0.837_x64.iso"  # URL to download the Veeam installer ISO.
$installationPath       = "C:\Veeam"                           # Directory where the installer and files will be stored.
$licenseFile            = "C:\Path\to\your\license_file.lic"   # Path to your Veeam license file.
$serviceAccountUsername = "VeeamServiceAccount"                # Service account username for Veeam.
$serviceAccountPassword = "YourPassword"                       # Service account password.


# Global log file for recording operations and errors.
$Global:LogFile = "C:\Logs\VeeamDeploy.log"

# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script must be run as Administrator." -ForegroundColor Red
    exit 1
}

# Check for PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.0 or higher is required." -ForegroundColor Red
    exit 1
}

# Validate required variables
foreach ($var in @('veeamInstallerUrl','installationPath','licenseFile','serviceAccountUsername','serviceAccountPassword')) {
    if (-not (Get-Variable $var -ValueOnly -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Variable $var is not set. Please update the script with correct values." -ForegroundColor Red
        exit 1
    }
}

#==============================================
# Function: Write-Log
#==============================================
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timeStamp [$Level] $Message"
    # Output to console
    Write-Host $logMessage
    # Append the message to the log file
    Add-Content -Path $Global:LogFile -Value $logMessage
}


# Helper function for step summary
$Summary = @{}
function Add-Summary {
    param([string]$Step,[bool]$Success)
    $Summary[$Step] = $Success
}

Write-Log "Veeam Backup and Replication Deployment started."

#==============================================
# Create Installation Directory
#==============================================
if (-not (Test-Path -Path $installationPath)) {
    Write-Log "Creating installation directory at $installationPath..."
    try {
        New-Item -Path $installationPath -ItemType Directory -Force | Out-Null
        Write-Log "Installation directory created successfully."
        Add-Summary "Create Installation Directory" $true
    } catch {
        Write-Log "Failed to create installation directory. Error: $_" "ERROR"
        Add-Summary "Create Installation Directory" $false
        exit 1
    }
} else {
    Write-Log "Installation directory already exists at $installationPath."
    Add-Summary "Create Installation Directory" $true
}

#==============================================
# Download Veeam Installer ISO
#==============================================
$isoFile = Join-Path -Path $installationPath -ChildPath "veeam_installer.iso"
if (-not (Test-Path -Path $isoFile)) {
    Write-Log "Downloading Veeam installer from $veeamInstallerUrl..."
    try {
        Invoke-WebRequest -Uri $veeamInstallerUrl -OutFile $isoFile
        Write-Log "Veeam installer downloaded successfully."
        Add-Summary "Download Veeam Installer ISO" $true
    } catch {
        Write-Log "Failed to download the Veeam installer. Error: $_" "ERROR"
        Add-Summary "Download Veeam Installer ISO" $false
        exit 1
    }
} else {
    Write-Log "Veeam installer ISO already exists at $isoFile."
    Add-Summary "Download Veeam Installer ISO" $true
}

#==============================================
# Mount and Format the Installer ISO
#==============================================
Write-Log "Mounting the installer ISO..."
try {
    $mountedDisk = Mount-DiskImage -ImagePath $isoFile -PassThru
    if ($mountedDisk) {
        $volume = $mountedDisk | Get-Partition | Get-Volume
        if ($volume) {
            Write-Log "ISO mounted successfully. Formatting the mounted volume..."
            try {
                $volume | Format-Volume -FileSystem NTFS -NewFileSystemLabel "VeeamInstaller" -Confirm:$false
                Write-Log "Mounted volume formatted successfully."
                Add-Summary "Mount and Format Installer ISO" $true
            } catch {
                Write-Log "Failed to format the mounted volume. Error: $_" "ERROR"
                Add-Summary "Mount and Format Installer ISO" $false
                exit 1
            }
        } else {
            Write-Log "Failed to retrieve volume after mounting the ISO." "ERROR"
            Add-Summary "Mount and Format Installer ISO" $false
            exit 1
        }
    } else {
        Write-Log "Failed to mount the installer ISO." "ERROR"
        Add-Summary "Mount and Format Installer ISO" $false
        exit 1
    }
} catch {
    Write-Log "Exception occurred while mounting the installer ISO. Error: $_" "ERROR"
    Add-Summary "Mount and Format Installer ISO" $false
    exit 1
}

#==============================================
# Install Veeam Backup & Replication
#==============================================
Write-Log "Starting Veeam Backup and Replication installation..."
try {
    $installerPath = Join-Path -Path $installationPath -ChildPath "veeam_installer\setup.exe"
    Start-Process -Wait -FilePath $installerPath -ArgumentList "/S /v/qn"
    Write-Log "Veeam Backup and Replication installed successfully."
    Add-Summary "Install Veeam Backup & Replication" $true
} catch {
    Write-Log "Failed to install Veeam Backup and Replication. Error: $_" "ERROR"
    Add-Summary "Install Veeam Backup & Replication" $false
    exit 1
}

#==============================================
# Dismount the Installer ISO
#==============================================
Write-Log "Dismounting the installer ISO..."
try {
    Dismount-DiskImage -ImagePath $isoFile
    Write-Log "ISO dismounted successfully."
    Add-Summary "Dismount Installer ISO" $true
} catch {
    Write-Log "Failed to dismount the installer ISO. Error: $_" "ERROR"
    Add-Summary "Dismount Installer ISO" $false
    exit 1
}

#==============================================
# Configure Veeam Management Database
#==============================================
Write-Log "Configuring Veeam Backup and Replication (Management Database initialization)..."
try {
    $initScript = Join-Path -Path $installationPath -ChildPath "Veeam\Backup and Replication\Console\Initialize-VeeamManagementDatabase.ps1"
    & $initScript -ServiceAccount $serviceAccountUsername -ServiceAccountPassword $serviceAccountPassword
    Write-Log "Veeam Management Database initialized successfully."
    Add-Summary "Configure Veeam Management Database" $true
} catch {
    Write-Log "Failed to initialize the Veeam Management Database. Error: $_" "ERROR"
    Add-Summary "Configure Veeam Management Database" $false
    exit 1
}

#==============================================
# Import Veeam License
#==============================================
Write-Log "Importing Veeam license..."
try {
    $licenseScript = Join-Path -Path $installationPath -ChildPath "Veeam\Backup and Replication\Console\Install-VeeamLicense.ps1"
    & $licenseScript -LicenseFile $licenseFile
    Write-Log "Veeam license imported successfully."
    Add-Summary "Import Veeam License" $true
} catch {
    Write-Log "Failed to import Veeam license. Error: $_" "ERROR"
    Add-Summary "Import Veeam License" $false
    exit 1
}

#==============================================
# Start Veeam Services
#==============================================
Write-Log "Starting Veeam services..."
$services = @(
    "VeeamEndpointBackupSvc",
    "VeeamBackupSvc",
    "VeeamBrokerSvc",
    "VeeamDeploySvc",
    "VeeamCatalogSvc"
)
$allServicesStarted = $true
foreach ($service in $services) {
    try {
        Start-Service -Name $service -ErrorAction Stop
        Write-Log "$service started successfully."
    } catch {
        Write-Log "Failed to start service '$service'. Error: $_" "ERROR"
        $allServicesStarted = $false
    }
}
Add-Summary "Start Veeam Services" $allServicesStarted


# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
foreach ($step in $Summary.Keys) {
    Write-Host "$step: $($Summary[$step] ? 'Success' : 'Failed')"
}
Write-Log "Veeam Backup and Replication deployment completed successfully."
