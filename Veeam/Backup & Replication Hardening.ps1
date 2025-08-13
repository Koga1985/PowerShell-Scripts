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
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
#>

#==============================================
# Global Logging Setup
#==============================================

# Logging: Define a global log file path where all events and error messages will be recorded.
$Global:LogFile = "C:\Logs\VeeamHardening.log"

# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script must be run as Administrator." -ForegroundColor Red
    exit 1
}

# Check for Veeam PowerShell module
if (-not (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell)) {
    Write-Host "ERROR: Veeam PowerShell module is not installed or loaded." -ForegroundColor Red
    exit 1
}

# Validate required variables
foreach ($var in @('YourBackupRepository','YourBackupUser','YourBackupJob','YourNotification')) {
    if (-not (Get-Variable $var -ValueOnly -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Variable $var is not set. Please update the script with correct values." -ForegroundColor Red
        exit 1
    }
}

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

# Helper function for step summary
$Summary = @{}
function Add-Summary {
    param([string]$Step,[bool]$Success)
    $Summary[$Step] = $Success
}

# 1. Disable Unnecessary Services
#==============================================
Write-Log "Disabling unnecessary services..."
try {
    Stop-Service -Name 'VeeamBackupSvc' -Force
    Set-Service -Name 'VeeamBackupSvc' -StartupType 'Disabled'
    Write-Log "Service 'VeeamBackupSvc' stopped and disabled successfully."
    Add-Summary "Disable Unnecessary Services" $true
} catch {
    Write-Log "Failed to stop or disable 'VeeamBackupSvc'. Error: $_" "ERROR"
    Add-Summary "Disable Unnecessary Services" $false
}

#==============================================
# 2. Configure Strong Authentication for Veeam Components
#==============================================
Write-Log "Configuring strong authentication for Veeam components..."
try {
    Set-VBRServer -SqlAuthenticationMode -Enable
    Write-Log "SQL authentication mode enabled successfully."
    Add-Summary "Configure Strong Authentication" $true
} catch {
    Write-Log "Failed to enable SQL authentication. Error: $_" "ERROR"
    Add-Summary "Configure Strong Authentication" $false
}

#==============================================
# 3. Limit Permissions on Veeam Backup Repositories
#==============================================
Write-Log "Limiting permissions on Veeam backup repositories..."
try {
    $repo = Get-VBRBackupRepository -Name $YourBackupRepository
    try {
        $user = Get-VBRUser -Name $YourBackupUser
        Set-VBRBackupRepository -Repository $repo -Permissions $user -RemovePermissions
        Write-Log "Permissions removed from repository '$($repo.Name)' for user '$($user.Name)'."
        Add-Summary "Limit Permissions on Backup Repositories" $true
    } catch {
        Write-Log "Failed to update permissions on repository '$($repo.Name)'. Error: $_" "ERROR"
        Add-Summary "Limit Permissions on Backup Repositories" $false
    }
} catch {
    Write-Log "Failed to retrieve backup repository '$YourBackupRepository'. Error: $_" "ERROR"
    Add-Summary "Limit Permissions on Backup Repositories" $false
}

#==============================================
# 4. Enable Veeam Encryption for Backup Data
#==============================================
Write-Log "Enabling encryption for Veeam backup data..."
try {
    Set-VBRGlobalOptions -EnableEncryption $true
    Write-Log "Backup encryption enabled successfully."
    Add-Summary "Enable Backup Data Encryption" $true
} catch {
    Write-Log "Failed to enable backup encryption. Error: $_" "ERROR"
    Add-Summary "Enable Backup Data Encryption" $false
}

#==============================================
# 5. Set Retention Policies for Backup Data
#==============================================
Write-Log "Setting retention policies for backup data..."
try {
    $backupJob = Get-VBRJob -Name $YourBackupJob
    try {
        Set-VBRJobOptions -Job $backupJob -RetentionSyncWeekly -RetentionWeekly 4
        Write-Log "Retention policy set for backup job '$($backupJob.Name)'."
        Add-Summary "Set Retention Policies" $true
    } catch {
        Write-Log "Failed to set retention policy for backup job '$($backupJob.Name)'. Error: $_" "ERROR"
        Add-Summary "Set Retention Policies" $false
    }
} catch {
    Write-Log "Failed to retrieve backup job '$YourBackupJob'. Error: $_" "ERROR"
    Add-Summary "Set Retention Policies" $false
}

#==============================================
# 6. Enable and Configure Veeam Alarms for Critical Events
#==============================================
Write-Log "Enabling and configuring Veeam alarms for critical events..."
try {
    $notification = Get-VBRNotification -Name $YourNotification
    try {
        Enable-VBRNotification -Notification $notification
        Write-Log "Notification '$($notification.Name)' enabled successfully."
        Add-Summary "Enable and Configure Alarms" $true
    } catch {
        Write-Log "Failed to enable notification '$($notification.Name)'. Error: $_" "ERROR"
        Add-Summary "Enable and Configure Alarms" $false
    }
} catch {
    Write-Log "Failed to retrieve notification '$YourNotification'. Error: $_" "ERROR"
    Add-Summary "Enable and Configure Alarms" $false
}

#==============================================
# 7. Regularly Review Veeam Logs for Anomalies
#==============================================
Write-Log "Reviewing Veeam logs for anomalies..."
try {
    $logs = Get-VBRLog -From (Get-Date).AddDays(-7)
    $logs | Out-File -FilePath 'C:\VeeamLogsReview.txt'
    Write-Log "Logs for the last 7 days saved to 'C:\VeeamLogsReview.txt'."
    Add-Summary "Review Veeam Logs" $true
} catch {
    Write-Log "Failed to review Veeam logs. Error: $_" "ERROR"
    Add-Summary "Review Veeam Logs" $false
}


# Summary Output
Write-Host "\nSummary:" -ForegroundColor Cyan
foreach ($step in $Summary.Keys) {
    Write-Host "$step: $($Summary[$step] ? 'Success' : 'Failed')"
}
Write-Log "Veeam Server Hardening configurations applied successfully."
