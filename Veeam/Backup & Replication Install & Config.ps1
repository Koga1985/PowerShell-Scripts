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

Write-Log "Veeam Backup and Replication Deployment started."

#==============================================
# Create Installation Directory
#==============================================
if (-not (Test-Path -Path $installationPath)) {
    Write-Log "Creating installation directory at $installationPath..."
    try {
        New-Item -Path $installationPath -ItemType Directory -Force | Out-Null
        Write-Log "Installation directory created successfully."
    } catch {
        Write-Log "Failed to create installation directory. Error: $_" "ERROR"
        exit 1
    }
} else {
    Write-Log "Installation directory already exists at $installationPath."
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
    } catch {
        Write-Log "Failed to download the Veeam installer. Error: $_" "ERROR"
        exit 1
    }
} else {
    Write-Log "Veeam installer ISO already exists at $isoFile."
}

#==============================================
# Mount and Format the Installer ISO
#==============================================
Write-Log "Mounting the installer ISO..."
try {
    $mountedDisk = Mount-DiskImage -ImagePath $isoFile -PassThru
    if ($mountedDisk) {
        # Retrieve the volume from the mounted disk image.
        $volume = $mountedDisk | Get-Partition | Get-Volume
        if ($volume) {
            Write-Log "ISO mounted successfully. Formatting the mounted volume..."
            try {
                # Format the volume as NTFS with a label "VeeamInstaller" without prompting for confirmation.
                $volume | Format-Volume -FileSystem NTFS -NewFileSystemLabel "VeeamInstaller" -Confirm:$false
                Write-Log "Mounted volume formatted successfully."
            } catch {
                Write-Log "Failed to format the mounted volume. Error: $_" "ERROR"
                exit 1
            }
        } else {
            Write-Log "Failed to retrieve volume after mounting the ISO." "ERROR"
            exit 1
        }
    } else {
        Write-Log "Failed to mount the installer ISO." "ERROR"
        exit 1
    }
} catch {
    Write-Log "Exception occurred while mounting the installer ISO. Error: $_" "ERROR"
    exit 1
}

#==============================================
# Install Veeam Backup & Replication
#==============================================
Write-Log "Starting Veeam Backup and Replication installation..."
try {
    # Construct the installer executable path.
    # NOTE: Adjust the installer path if the files on the mounted ISO are structured differently.
    $installerPath = Join-Path -Path $installationPath -ChildPath "veeam_installer\setup.exe"
    Start-Process -Wait -FilePath $installerPath -ArgumentList "/S /v/qn"
    Write-Log "Veeam Backup and Replication installed successfully."
} catch {
    Write-Log "Failed to install Veeam Backup and Replication. Error: $_" "ERROR"
    exit 1
}

#==============================================
# Dismount the Installer ISO
#==============================================
Write-Log "Dismounting the installer ISO..."
try {
    Dismount-DiskImage -ImagePath $isoFile
    Write-Log "ISO dismounted successfully."
} catch {
    Write-Log "Failed to dismount the installer ISO. Error: $_" "ERROR"
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
} catch {
    Write-Log "Failed to initialize the Veeam Management Database. Error: $_" "ERROR"
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
} catch {
    Write-Log "Failed to import Veeam license. Error: $_" "ERROR"
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

foreach ($service in $services) {
    try {
        Start-Service -Name $service -ErrorAction Stop
        Write-Log "$service started successfully."
    } catch {
        Write-Log "Failed to start service '$service'. Error: $_" "ERROR"
        exit 1
    }
}

Write-Log "Veeam Backup and Replication deployment completed successfully."
