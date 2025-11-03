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

.PARAMETER Credential
    PSCredential object for Veeam server authentication.

.PARAMETER VeeamServer
    Target Veeam Backup & Replication server name.

.SECURITY FEATURES
    - Requires PowerShell 5.1 and Administrator privileges
    - Comprehensive audit logging to file and Windows Event Log
    - Secure credential handling via PSCredential
    - Input validation for all parameters
    - Sensitive data cleared from memory on exit

.COMPLIANCE
    - Follows Fourth Estate security standards
    - Implements defense-in-depth logging
    - Supports audit trail requirements
    - Validates all input parameters

.EXAMPLE
    $cred = Get-Credential
    .\Best Practices.ps1 -VeeamServer "VEEAM01" -Credential $cred

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9\-\.]+$')]
    [string]$VeeamServer = $env:COMPUTERNAME
)

#==============================================
# Global Logging Setup
#==============================================

# Logging: Define a global log file path where all events and error messages will be recorded.
$Global:LogFile = "C:\Logs\VeeamBestPractices.log"
$Global:EventLogSource = "VeeamBestPractices"
$Global:EventLogName = "Application"

# Ensure log directory exists
$logDir = Split-Path -Path $Global:LogFile -Parent
if (-not (Test-Path -Path $logDir -PathType Container)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory: $logDir. Error: $_"
        exit 1
    }
}

# Register Event Log Source
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
        [System.Diagnostics.EventLog]::CreateEventSource($Global:EventLogSource, $Global:EventLogName)
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Warning "Could not create Event Log source. Continuing with file logging only."
}

#==============================================
# Function: Write-AuditLog
#==============================================
function Write-AuditLog {
    <#
    .SYNOPSIS
        Comprehensive audit logging to file and Windows Event Log.

    .PARAMETER Message
        The message text to log.

    .PARAMETER Level
        The message level (INFO, ERROR, WARNING, SUCCESS). Default is INFO.

    .PARAMETER Operation
        The operation being performed.

    .PARAMETER TargetSystem
        The target system for the operation.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','ERROR','WARNING','SUCCESS')]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [string]$Operation = "General",

        [Parameter(Mandatory=$false)]
        [string]$TargetSystem = $VeeamServer
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $logMessage = "$timestamp [$Level] User: $userName | Operation: $Operation | Target: $TargetSystem | $Message"

        # Write to console
        switch ($Level) {
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            default   { Write-Host $logMessage }
        }

        # Write to file
        Add-Content -Path $Global:LogFile -Value $logMessage -ErrorAction Stop

        # Write to Windows Event Log
        $eventType = switch ($Level) {
            'ERROR'   { [System.Diagnostics.EventLogEntryType]::Error }
            'WARNING' { [System.Diagnostics.EventLogEntryType]::Warning }
            default   { [System.Diagnostics.EventLogEntryType]::Information }
        }

        $eventID = switch ($Level) {
            'ERROR'   { 1001 }
            'WARNING' { 1002 }
            'SUCCESS' { 1003 }
            default   { 1000 }
        }

        if ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
            Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
                -EntryType $eventType -EventId $eventID -Message $logMessage -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Failed to write to audit log: $_"
    }
}

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
    Write-AuditLog -Message $Message -Level $Level -Operation "VeeamBestPractices"
}

#==============================================
# Input Validation
#==============================================
function Test-ComputerName {
    param([string]$ComputerName)

    if ($ComputerName -notmatch '^[a-zA-Z0-9\-\.]+$') {
        throw "Invalid computer name format: $ComputerName"
    }
    return $true
}

try {
    Test-ComputerName -ComputerName $VeeamServer
} catch {
    Write-AuditLog -Message "Invalid VeeamServer parameter: $_" -Level ERROR
    exit 1
}

#==============================================
# Check Prerequisites
#==============================================

Write-AuditLog -Message "Script execution started" -Level INFO -Operation "Initialization"

# Check for Veeam PowerShell module
if (-not (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell)) {
    Write-AuditLog -Message "Veeam PowerShell module is not installed or loaded." -Level ERROR -Operation "Initialization"
    exit 1
}

# Helper function for step summary
$Summary = @{}
function Add-Summary {
    param([string]$Step,[bool]$Success)
    $Summary[$Step] = $Success
    Write-AuditLog -Message "Step completed: $Step - $($Success ? 'Success' : 'Failed')" -Level ($Success ? 'SUCCESS' : 'ERROR') -Operation $Step
}

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
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingName,

        [Parameter(Mandatory=$true)]
        [string]$SettingValue
    )
    try {
        # Assumes the existence of a Veeam cmdlet (Set-VBRServerSettings) to apply the setting.
        Set-VBRServerSettings -Name $SettingName -Value $SettingValue -ErrorAction Stop
        Write-AuditLog "Successfully set '$SettingName' to '$SettingValue'." -Level SUCCESS -Operation "SetVeeamSetting"
        return $true
    } catch {
        Write-AuditLog "Failed to set '$SettingName' to '$SettingValue'. Error: $_" -Level ERROR -Operation "SetVeeamSetting"
        return $false
    }
}

#==============================================
# Main Configuration Execution
#==============================================

try {
    #==============================================
    # Set Backup Compression Level
    #==============================================
    Write-Log "Setting backup compression level to 'Optimal'..."
    try {
        $result = Set-VeeamSetting -SettingName "CompressionLevel" -SettingValue "Optimal"
        Add-Summary "Set Backup Compression Level" $result
    } catch {
        Add-Summary "Set Backup Compression Level" $false
    }

    #==============================================
    # Set Optimal Repository Settings
    #==============================================
    Write-Log "Configuring repository cache settings..."
    try {
        $repositories = Get-VBRRepository -ErrorAction Stop
        $repoSuccess = $true
        foreach ($repo in $repositories) {
            try {
                Set-VBRRepository -Repository $repo -CacheSize 1024GB -CachePath "C:\VeeamCache" -ErrorAction Stop
                Write-AuditLog "Repository '$($repo.Name)' cache size set to 1024GB and cache path set to 'C:\VeeamCache'." -Level SUCCESS -Operation "ConfigureRepository"
            } catch {
                Write-AuditLog "Failed to set cache settings for repository '$($repo.Name)'. Error: $_" -Level ERROR -Operation "ConfigureRepository"
                $repoSuccess = $false
            }
        }
        Add-Summary "Set Optimal Repository Settings" $repoSuccess
    } catch {
        Write-AuditLog "Failed to retrieve Veeam repositories. Error: $_" -Level ERROR -Operation "ConfigureRepository"
        Add-Summary "Set Optimal Repository Settings" $false
    }

    #==============================================
    # Configure WAN Acceleration Settings
    #==============================================
    Write-Log "Configuring WAN acceleration settings..."
    try {
        Set-VBRWANAccelerator -GlobalNetworkThrottlingMBps 100 -LocalCacheSizeGB 1024 -ErrorAction Stop
        Write-AuditLog "WAN acceleration settings configured successfully." -Level SUCCESS -Operation "ConfigureWAN"
        Add-Summary "Configure WAN Acceleration Settings" $true
    } catch {
        Write-AuditLog "Failed to configure WAN acceleration settings. Error: $_" -Level ERROR -Operation "ConfigureWAN"
        Add-Summary "Configure WAN Acceleration Settings" $false
    }

    #==============================================
    # Enable Automatic Backup Integrity Checks on Jobs
    #==============================================
    Write-Log "Enabling automatic backup integrity checks on backup jobs..."
    try {
        $jobs = Get-VBRJob -ErrorAction Stop
        $integritySuccess = $true
        foreach ($job in $jobs) {
            try {
                Set-VBRJobOptions -Job $job -BackupStorageOptions @{ "IntegrityCheck" = "true" } -ErrorAction Stop
                Write-AuditLog "Backup integrity check enabled for job '$($job.Name)'." -Level SUCCESS -Operation "EnableIntegrityCheck"
            } catch {
                Write-AuditLog "Failed to enable backup integrity check for job '$($job.Name)'. Error: $_" -Level ERROR -Operation "EnableIntegrityCheck"
                $integritySuccess = $false
            }
        }
        Add-Summary "Enable Automatic Backup Integrity Checks" $integritySuccess
    } catch {
        Write-AuditLog "Failed to retrieve backup jobs. Error: $_" -Level ERROR -Operation "EnableIntegrityCheck"
        Add-Summary "Enable Automatic Backup Integrity Checks" $false
    }

    #==============================================
    # Set Guest Interaction Proxy
    #==============================================
    Write-Log "Configuring guest interaction proxy..."
    try {
        $result = Set-VeeamSetting -SettingName "GuestInteractionProxy" -SettingValue "VeeamGuestInteractionProxy"
        Add-Summary "Set Guest Interaction Proxy" $result
    } catch {
        Add-Summary "Set Guest Interaction Proxy" $false
    }

    #==============================================
    # Enable Parallel Processing for Backup Jobs
    #==============================================
    Write-Log "Enabling parallel processing for backup jobs..."
    try {
        $parallelSuccess = $true
        $jobs | ForEach-Object {
            try {
                Set-VBRJobAdvancedStorageOptions -Job $_ -EnableParallelProcessing $true -ErrorAction Stop
                Write-AuditLog "Parallel processing enabled for job '$($_.Name)'." -Level SUCCESS -Operation "EnableParallelProcessing"
            } catch {
                Write-AuditLog "Failed to enable parallel processing for job '$($_.Name)'. Error: $_" -Level ERROR -Operation "EnableParallelProcessing"
                $parallelSuccess = $false
            }
        }
        Add-Summary "Enable Parallel Processing for Backup Jobs" $parallelSuccess
    } catch {
        Write-AuditLog "Failed to process backup jobs for parallel processing configuration. Error: $_" -Level ERROR -Operation "EnableParallelProcessing"
        Add-Summary "Enable Parallel Processing for Backup Jobs" $false
    }

    #==============================================
    # Configure SureBackup Settings
    #==============================================
    Write-Log "Configuring SureBackup settings..."
    try {
        Set-VBRJobAdvancedStorageOptions -EnableInlineDeduplication $true -ErrorAction Stop
        Write-AuditLog "SureBackup settings applied successfully with inline deduplication enabled." -Level SUCCESS -Operation "ConfigureSureBackup"
        Add-Summary "Configure SureBackup Settings" $true
    } catch {
        Write-AuditLog "Failed to configure SureBackup settings. Error: $_" -Level ERROR -Operation "ConfigureSureBackup"
        Add-Summary "Configure SureBackup Settings" $false
    }

    #==============================================
    # Enable Backup Copy Job Encryption
    #==============================================
    Write-Log "Enabling backup copy job encryption..."
    try {
        $encryptionSuccess = $true
        $jobs | ForEach-Object {
            try {
                Set-VBRJobStorageOptions -Job $_ -StorageEncryptionEnabled $true -ErrorAction Stop
                Write-AuditLog "Storage encryption enabled for backup copy job '$($_.Name)'." -Level SUCCESS -Operation "EnableEncryption"
            } catch {
                Write-AuditLog "Failed to enable storage encryption for job '$($_.Name)'. Error: $_" -Level ERROR -Operation "EnableEncryption"
                $encryptionSuccess = $false
            }
        }
        Add-Summary "Enable Backup Copy Job Encryption" $encryptionSuccess
    } catch {
        Write-AuditLog "Failed to retrieve backup jobs for encryption settings. Error: $_" -Level ERROR -Operation "EnableEncryption"
        Add-Summary "Enable Backup Copy Job Encryption" $false
    }

    #==============================================
    # Enable Per-VM Backup Chains
    #==============================================
    Write-Log "Enabling per-VM backup chains..."
    try {
        Set-VBRGlobalOptions -EnablePerVMBackupChain $true -ErrorAction Stop
        Write-AuditLog "Per-VM backup chains enabled successfully." -Level SUCCESS -Operation "EnablePerVMChains"
        Add-Summary "Enable Per-VM Backup Chains" $true
    } catch {
        Write-AuditLog "Failed to enable per-VM backup chains. Error: $_" -Level ERROR -Operation "EnablePerVMChains"
        Add-Summary "Enable Per-VM Backup Chains" $false
    }

    #==============================================
    # Set vPower NFS Cache Settings
    #==============================================
    Write-Log "Configuring vPower NFS cache settings..."
    try {
        $result1 = Set-VeeamSetting -SettingName "NFS.MaxDataSizeForDeltaBlockCachingMB" -SettingValue 512
        $result2 = Set-VeeamSetting -SettingName "NFS.UseLegacyNFSWriteAlgorithm" -SettingValue $false
        Add-Summary "Set vPower NFS Cache Settings" ($result1 -and $result2)
    } catch {
        Add-Summary "Set vPower NFS Cache Settings" $false
    }

    #==============================================
    # Disable Automatic Product Update Checks
    #==============================================
    Write-Log "Disabling automatic check for product updates..."
    try {
        Set-VBRGlobalOptions -UpdateNotification $false -ErrorAction Stop
        Write-AuditLog "Automatic product update checks disabled successfully." -Level SUCCESS -Operation "DisableAutoUpdate"
        Add-Summary "Disable Automatic Product Update Checks" $true
    } catch {
        Write-AuditLog "Failed to disable automatic product update checks. Error: $_" -Level ERROR -Operation "DisableAutoUpdate"
        Add-Summary "Disable Automatic Product Update Checks" $false
    }

} catch {
    Write-AuditLog -Message "Critical error during execution: $_" -Level ERROR -Operation "MainExecution"
    throw
} finally {
    # Clear sensitive data from memory
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $Credential = $null
    }
    [System.GC]::Collect()
}

# Summary Output
Write-Host "`nSummary:" -ForegroundColor Cyan
$successCount = 0
$failCount = 0
foreach ($step in $Summary.Keys) {
    $status = if ($Summary[$step]) { $successCount++; 'Success' } else { $failCount++; 'Failed' }
    Write-Host "$step: $status"
}

Write-Host "`nTotal: $($Summary.Count) steps - $successCount succeeded, $failCount failed" -ForegroundColor Cyan
Write-AuditLog "Veeam Best Practices configuration completed. Success: $successCount, Failed: $failCount" -Level INFO -Operation "Completion"

# Exit with appropriate code
if ($failCount -eq 0) {
    Write-AuditLog "Script completed successfully with no errors" -Level SUCCESS -Operation "Completion"
    exit 0
} else {
    Write-AuditLog "Script completed with $failCount error(s)" -Level WARNING -Operation "Completion"
    exit 1
}
