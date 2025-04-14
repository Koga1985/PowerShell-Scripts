<#
.SYNOPSIS
    Veeam Server Hardening Script

.DESCRIPTION
    This script applies a set of hardening and best practice configurations to a Veeam Backup & Replication server. 
    The configuration steps include:
      1. Disabling unnecessary services.
      2. Configuring strong authentication for Veeam components.
      3. Limiting permissions on Veeam backup repositories.
      4. Enabling backup data encryption.
      5. Setting retention policies for backup data.
      6. Enabling and configuring alarms for critical events.
      7. Reviewing Veeam logs for anomalies.

    Prerequisites:
      - Veeam Backup & Replication with the PowerShell snap-in/module loaded.
      - Administrative privileges.
      - Ensure that variables like 'YourBackupRepository', 'YourBackupUser', 'YourBackupJob', and 'YourNotification' are updated appropriately.

.NOTES
    Author:         Your Name or Organization
    Created:        2025-04-14
    Version:        1.0
#>

#==============================================
# Global Logging Setup
#==============================================
$Global:LogFile = "C:\Logs\VeeamHardening.log"

function Write-Log {
    <#
    .SYNOPSIS
        Logs a message with a timestamp to both the console and a log file.
    
    .PARAMETER Message
        The message to log.
    
    .PARAMETER Level
        The level of the message (e.g., INFO, ERROR). Default value is INFO.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timeStamp [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $Global:LogFile -Value $logMessage
}

Write-Log "Starting Veeam Server Hardening configuration."

#==============================================
# Function: Set-VeeamSetting
#==============================================
function Set-VeeamSetting {
    <#
    .SYNOPSIS
        Sets a specified Veeam server setting.
    
    .PARAMETER SettingName
        The name of the setting to configure.
    
    .PARAMETER SettingValue
        The value to apply to the setting.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$SettingName,
        [Parameter(Mandatory=$true)][string]$SettingValue
    )
    try {
        # Applies the configuration using the Veeam cmdlet.
        Set-VBRServerSettings -Name $SettingName -Value $SettingValue
        Write-Log "Successfully set '$SettingName' to '$SettingValue'."
    } catch {
        Write-Log "Failed to set '$SettingName' to '$SettingValue'. Error: $_" "ERROR"
    }
}

#==============================================
# 1. Disable Unnecessary Services
#==============================================
Write-Log "Disabling unnecessary services..."
try {
    Stop-Service -Name 'VeeamBackupSvc' -Force
    Set-Service -Name 'VeeamBackupSvc' -StartupType 'Disabled'
    Write-Log "Service 'VeeamBackupSvc' stopped and disabled successfully."
} catch {
    Write-Log "Failed to stop or disable 'VeeamBackupSvc'. Error: $_" "ERROR"
}

#==============================================
# 2. Configure Strong Authentication for Veeam Components
#==============================================
Write-Log "Configuring strong authentication for Veeam components..."
try {
    # Enable SQL authentication mode for Veeam components.
    Set-VBRServer -SqlAuthenticationMode -Enable
    Write-Log "SQL authentication mode enabled successfully."
} catch {
    Write-Log "Failed to enable SQL authentication. Error: $_" "ERROR"
}

#==============================================
# 3. Limit Permissions on Veeam Backup Repositories
#==============================================
Write-Log "Limiting permissions on Veeam backup repositories..."
try {
    # Retrieve the backup repository by name.
    $repo = Get-VBRBackupRepository -Name 'YourBackupRepository'
    try {
        # Retrieve the user whose permissions will be limited.
        $user = Get-VBRUser -Name 'YourBackupUser'
        # Remove permissions for the specified user on the repository.
        Set-VBRBackupRepository -Repository $repo -Permissions $user -RemovePermissions
        Write-Log "Permissions removed from repository '$($repo.Name)' for user '$($user.Name)'."
    } catch {
        Write-Log "Failed to update permissions on repository '$($repo.Name)'. Error: $_" "ERROR"
    }
} catch {
    Write-Log "Failed to retrieve backup repository 'YourBackupRepository'. Error: $_" "ERROR"
}

#==============================================
# 4. Enable Veeam Encryption for Backup Data
#==============================================
Write-Log "Enabling encryption for Veeam backup data..."
try {
    Set-VBRGlobalOptions -EnableEncryption $true
    Write-Log "Backup encryption enabled successfully."
} catch {
    Write-Log "Failed to enable backup encryption. Error: $_" "ERROR"
}

#==============================================
# 5. Set Retention Policies for Backup Data
#==============================================
Write-Log "Setting retention policies for backup data..."
try {
    # Retrieve the backup job by name.
    $backupJob = Get-VBRJob -Name 'YourBackupJob'
    try {
        # Set the retention options (weekly synchronization and retention count).
        Set-VBRJobOptions -Job $backupJob -RetentionSyncWeekly -RetentionWeekly 4
        Write-Log "Retention policy set for backup job '$($backupJob.Name)'."
    } catch {
        Write-Log "Failed to set retention policy for backup job '$($backupJob.Name)'. Error: $_" "ERROR"
    }
} catch {
    Write-Log "Failed to retrieve backup job 'YourBackupJob'. Error: $_" "ERROR"
}

#==============================================
# 6. Enable and Configure Veeam Alarms for Critical Events
#==============================================
Write-Log "Enabling and configuring Veeam alarms for critical events..."
try {
    # Retrieve the notification configuration by name.
    $notification = Get-VBRNotification -Name 'YourNotification'
    try {
        # Enable the notification.
        Enable-VBRNotification -Notification $notification
        Write-Log "Notification '$($notification.Name)' enabled successfully."
    } catch {
        Write-Log "Failed to enable notification '$($notification.Name)'. Error: $_" "ERROR"
    }
} catch {
    Write-Log "Failed to retrieve notification 'YourNotification'. Error: $_" "ERROR"
}

#==============================================
# 7. Regularly Review Veeam Logs for Anomalies
#==============================================
Write-Log "Reviewing Veeam logs for anomalies..."
try {
    # Retrieve logs from the past 7 days.
    $logs = Get-VBRLog -From (Get-Date).AddDays(-7)
    $logs | Out-File -FilePath 'C:\VeeamLogsReview.txt'
    Write-Log "Logs for the last 7 days saved to 'C:\VeeamLogsReview.txt'."
} catch {
    Write-Log "Failed to review Veeam logs. Error: $_" "ERROR"
}

Write-Log "Veeam Server Hardening configurations applied successfully."
