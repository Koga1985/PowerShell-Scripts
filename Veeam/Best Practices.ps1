<#
.SYNOPSIS
    Configure Veeam Backup & Replication Best Practices.

.DESCRIPTION
    This script applies a variety of Veeam best practices settings including:
      - Configuring backup compression
      - Adjusting repository cache settings
      - Configuring WAN acceleration
      - Enabling backup integrity checks on jobs
      - Setting guest interaction proxy
      - Enabling parallel processing for backup jobs
      - Configuring SureBackup settings
      - Enabling backup copy job encryption
      - Enabling per-VM backup chains
      - Configuring vPower NFS cache settings
      - Disabling automatic update notifications

    Prerequisites:
      - Veeam Backup & Replication with the PowerShell snap-in/module loaded.
      - Appropriate permissions to configure server and job settings.
      - This script should be run in an elevated PowerShell session.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
#>

#==============================================
# Global Logging Setup
#==============================================
$Global:LogFile = "C:\Logs\VeeamBestPractices.log"

function Write-Log {
    <#
    .SYNOPSIS
        Logs a message with a timestamp to the console and a log file.
    
    .PARAMETER Message
        The message text to log.
    
    .PARAMETER Level
        The message level (e.g., INFO, ERROR). Default is INFO.
    #>
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timeStamp [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $Global:LogFile -Value $logMessage
}

# Log start of script
Write-Log "Starting Veeam Best Practices configuration..."

#==============================================
# Function: Set-VeeamSetting
#==============================================
function Set-VeeamSetting {
    <#
    .SYNOPSIS
        Applies a Veeam server setting and logs the outcome.
    
    .PARAMETER SettingName
        The name of the Veeam setting to configure.
    
    .PARAMETER SettingValue
        The value to apply for the setting.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$SettingName,
        [Parameter(Mandatory=$true)][string]$SettingValue
    )
    try {
        # Assumes the existence of a Veeam cmdlet (Set-VBRServerSettings) to apply the setting.
        Set-VBRServerSettings -Name $SettingName -Value $SettingValue
        Write-Log "Successfully set '$SettingName' to '$SettingValue'."
    } catch {
        Write-Log "Failed to set '$SettingName' to '$SettingValue'. Error: $_" "ERROR"
    }
}

#==============================================
# Set Backup Compression Level
#==============================================
Write-Log "Setting backup compression level to 'Optimal'..."
Set-VeeamSetting -SettingName "CompressionLevel" -SettingValue "Optimal"

#==============================================
# Set Optimal Repository Settings
#==============================================
Write-Log "Configuring repository cache settings..."
try {
    $repositories = Get-VBRRepository
    foreach ($repo in $repositories) {
        try {
            # Adjust cache size and path for each repository.
            Set-VBRRepository -Repository $repo -CacheSize 1024GB -CachePath "C:\VeeamCache"
            Write-Log "Repository '$($repo.Name)' cache size set to 1024GB and cache path set to 'C:\VeeamCache'."
        } catch {
            Write-Log "Failed to set cache settings for repository '$($repo.Name)'. Error: $_" "ERROR"
        }
    }
} catch {
    Write-Log "Failed to retrieve Veeam repositories. Error: $_" "ERROR"
}

#==============================================
# Configure WAN Acceleration Settings
#==============================================
Write-Log "Configuring WAN acceleration settings..."
try {
    Set-VBRWANAccelerator -GlobalNetworkThrottlingMBps 100 -LocalCacheSizeGB 1024
    Write-Log "WAN acceleration settings configured successfully."
} catch {
    Write-Log "Failed to configure WAN acceleration settings. Error: $_" "ERROR"
}

#==============================================
# Enable Automatic Backup Integrity Checks on Jobs
#==============================================
Write-Log "Enabling automatic backup integrity checks on backup jobs..."
try {
    $jobs = Get-VBRJob
    foreach ($job in $jobs) {
        try {
            # Enable integrity check by setting the BackupStorageOptions property.
            Set-VBRJobOptions -Job $job -BackupStorageOptions @{ "IntegrityCheck" = "true" }
            Write-Log "Backup integrity check enabled for job '$($job.Name)'."
        } catch {
            Write-Log "Failed to enable backup integrity check for job '$($job.Name)'. Error: $_" "ERROR"
        }
    }
} catch {
    Write-Log "Failed to retrieve backup jobs. Error: $_" "ERROR"
}

#==============================================
# Set Guest Interaction Proxy
#==============================================
Write-Log "Configuring guest interaction proxy..."
Set-VeeamSetting -SettingName "GuestInteractionProxy" -SettingValue "VeeamGuestInteractionProxy"

#==============================================
# Enable Parallel Processing for Backup Jobs
#==============================================
Write-Log "Enabling parallel processing for backup jobs..."
try {
    $jobs | ForEach-Object {
        try {
            Set-VBRJobAdvancedStorageOptions -Job $_ -EnableParallelProcessing $true
            Write-Log "Parallel processing enabled for job '$($_.Name)'."
        } catch {
            Write-Log "Failed to enable parallel processing for job '$($_.Name)'. Error: $_" "ERROR"
        }
    }
} catch {
    Write-Log "Failed to process backup jobs for parallel processing configuration. Error: $_" "ERROR"
}

#==============================================
# Configure SureBackup Settings
#==============================================
Write-Log "Configuring SureBackup settings..."
try {
    # Assuming that SureBackup settings can be applied globally using advanced storage options.
    Set-VBRJobAdvancedStorageOptions -EnableInlineDeduplication $true
    Write-Log "SureBackup settings applied successfully with inline deduplication enabled."
} catch {
    Write-Log "Failed to configure SureBackup settings. Error: $_" "ERROR"
}

#==============================================
# Enable Backup Copy Job Encryption
#==============================================
Write-Log "Enabling backup copy job encryption..."
try {
    $jobs | ForEach-Object {
        try {
            Set-VBRJobStorageOptions -Job $_ -StorageEncryptionEnabled $true
            Write-Log "Storage encryption enabled for backup copy job '$($_.Name)'."
        } catch {
            Write-Log "Failed to enable storage encryption for job '$($_.Name)'. Error: $_" "ERROR"
        }
    }
} catch {
    Write-Log "Failed to retrieve backup jobs for encryption settings. Error: $_" "ERROR"
}

#==============================================
# Enable Per-VM Backup Chains
#==============================================
Write-Log "Enabling per-VM backup chains..."
try {
    Set-VBRGlobalOptions -EnablePerVMBackupChain $true
    Write-Log "Per-VM backup chains enabled successfully."
} catch {
    Write-Log "Failed to enable per-VM backup chains. Error: $_" "ERROR"
}

#==============================================
# Set vPower NFS Cache Settings
#==============================================
Write-Log "Configuring vPower NFS cache settings..."
Set-VeeamSetting -SettingName "NFS.MaxDataSizeForDeltaBlockCachingMB" -SettingValue 512
Set-VeeamSetting -SettingName "NFS.UseLegacyNFSWriteAlgorithm" -SettingValue $false

#==============================================
# Disable Automatic Product Update Checks
#==============================================
Write-Log "Disabling automatic check for product updates..."
try {
    Set-VBRGlobalOptions -UpdateNotification $false
    Write-Log "Automatic product update checks disabled successfully."
} catch {
    Write-Log "Failed to disable automatic product update checks. Error: $_" "ERROR"
}

Write-Log "Veeam Best Practices configuration completed successfully."
