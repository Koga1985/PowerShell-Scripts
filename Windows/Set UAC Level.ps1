#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reads and configures User Account Control (UAC) settings via registry modifications.

.DESCRIPTION
    This script provides functions to get and set UAC levels on Windows systems:
      - Get-UACLevel: Reads current UAC settings and returns descriptive level
      - Set-UACLevel: Configures UAC by modifying registry keys

    UAC Levels:
      0 = Never Notify
      1 = Notify me only when apps try to make changes (do not dim desktop)
      2 = Notify me only when apps try to make changes (default)
      3 = Always Notify

.PARAMETER Level
    Numeric UAC level (0, 1, 2, or 3) corresponding to the desired UAC behavior.

.PARAMETER GetCurrentLevel
    Switch to retrieve and display current UAC level without making changes.

.EXAMPLE
    .\Set UAC Level.ps1 -GetCurrentLevel
    Displays the current UAC configuration.

.EXAMPLE
    .\Set UAC Level.ps1 -Level 2
    Sets UAC to the default level (Notify me only when apps try to make changes).

.EXAMPLE
    .\Set UAC Level.ps1 -Level 3 -WhatIf
    Shows what would happen if UAC is set to "Always Notify" without making changes.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    Updated:        October 30, 2025
    Version:        2.0
    License:        MIT
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - System restart may be required for changes to take effect

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Input validation (ValidateSet for UAC levels)
    - Secure error handling with proper cleanup
    - SupportsShouldProcess for safe operations

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (AC-6: Least Privilege)
    - Supports DISA STIG requirements for privilege escalation controls
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Set')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Set')]
    [ValidateSet(0, 1, 2, 3)]
    [int]$Level,

    [Parameter(Mandatory = $false, ParameterSetName = 'Get')]
    [switch]$GetCurrentLevel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "SetUACLevel_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\SetUACLevel_Audit.log"
$script:EventSource = "SetUACLevel"

# Ensure audit log directory exists
$auditLogDir = Split-Path -Parent $script:AuditLogPath
if (-not (Test-Path -Path $auditLogDir)) {
    New-Item -Path $auditLogDir -ItemType Directory -Force | Out-Null
}

# Create event source if it doesn't exist
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($script:EventSource)) {
        New-EventLog -LogName Application -Source $script:EventSource -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Unable to create event log source. Event logging will be limited."
}

#----------------------------------------------
# Global Variables for Registry Paths
#----------------------------------------------
$script:UACRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$script:ConsentPromptBehaviorAdmin = "ConsentPromptBehaviorAdmin"
$script:PromptOnSecureDesktop = "PromptOnSecureDesktop"

#----------------------------------------------
# Comprehensive Audit Logging Function
#----------------------------------------------
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [int]$EventId = 1000
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $computerName = $env:COMPUTERNAME

    $logEntry = "$timestamp [$Level] [$userName@$computerName] $Message"

    # Write to file
    try {
        Add-Content -Path $script:AuditLogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to audit log file: $_"
    }

    # Write to Windows Event Log
    $eventType = switch ($Level) {
        'ERROR'   { 'Error' }
        'WARNING' { 'Warning' }
        default   { 'Information' }
    }

    $eventIdMap = @{
        'INFO'    = 1000
        'SUCCESS' = 1001
        'WARNING' = 2000
        'ERROR'   = 3000
    }

    $finalEventId = if ($EventId -eq 1000) { $eventIdMap[$Level] } else { $EventId }

    try {
        Write-EventLog -LogName Application -Source $script:EventSource -EntryType $eventType -EventId $finalEventId -Message $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if event log write fails
    }

    # Write to console
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }

    Write-Host $logEntry -ForegroundColor $color
}

#----------------------------------------------
# Function: Get-RegistryValue
#----------------------------------------------
function Get-RegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    try {
        if (Test-Path -Path $Path) {
            $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop | Select-Object -ExpandProperty $Name
            Write-AuditLog -Message "Retrieved registry value '$Name' = $value from '$Path'" -Level "INFO"
            return $value
        } else {
            Write-AuditLog -Message "Registry path does not exist: $Path" -Level "WARNING"
            return $null
        }
    } catch {
        Write-AuditLog -Message "Error reading registry value '$Name' from '$Path': $_" -Level "ERROR"
        return $null
    }
}

#----------------------------------------------
# Function: Set-RegistryValue
#----------------------------------------------
function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$Value
    )

    try {
        # Ensure registry path exists
        if (-not (Test-Path -Path $Path)) {
            Write-AuditLog -Message "Registry path '$Path' not found. Creating it." -Level "INFO"
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set registry value to $Value")) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force -ErrorAction Stop
            Write-AuditLog -Message "Successfully set '$Name' to $Value in '$Path'" -Level "SUCCESS"
            return $true
        }
        return $false
    } catch {
        Write-AuditLog -Message "Error setting registry value '$Name' in '$Path': $_" -Level "ERROR"
        throw
    }
}

#----------------------------------------------
# Function: Get-UACLevel
#----------------------------------------------
function Get-UACLevel {
    <#
    .SYNOPSIS
        Retrieves the current UAC configuration and returns a descriptive string.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Retrieving current UAC level..." -Level "INFO"

    $consentValue = Get-RegistryValue -Path $script:UACRegistryPath -Name $script:ConsentPromptBehaviorAdmin
    $desktopValue = Get-RegistryValue -Path $script:UACRegistryPath -Name $script:PromptOnSecureDesktop

    $uacLevel = if (($consentValue -eq 0) -and ($desktopValue -eq 0)) {
        "0 - Never Notify"
    } elseif (($consentValue -eq 5) -and ($desktopValue -eq 0)) {
        "1 - Notify me only when apps try to make changes (do not dim desktop)"
    } elseif (($consentValue -eq 5) -and ($desktopValue -eq 1)) {
        "2 - Notify me only when apps try to make changes (default)"
    } elseif (($consentValue -eq 2) -and ($desktopValue -eq 1)) {
        "3 - Always Notify"
    } else {
        "Unknown (ConsentPromptBehaviorAdmin=$consentValue, PromptOnSecureDesktop=$desktopValue)"
    }

    Write-AuditLog -Message "Current UAC Level: $uacLevel" -Level "INFO"
    return $uacLevel
}

#----------------------------------------------
# Function: Set-UACLevelInternal
#----------------------------------------------
function Set-UACLevelInternal {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(0, 1, 2, 3)]
        [int]$Level
    )

    Write-AuditLog -Message "Setting UAC level to $Level..." -Level "INFO"

    # Determine registry values based on UAC level
    $consentValue = switch ($Level) {
        0 { 0 }
        1 { 5 }
        2 { 5 }
        3 { 2 }
    }

    $desktopValue = switch ($Level) {
        0 { 0 }
        1 { 0 }
        2 { 1 }
        3 { 1 }
    }

    $levelDescription = switch ($Level) {
        0 { "Never Notify" }
        1 { "Notify me only when apps try to make changes (do not dim desktop)" }
        2 { "Notify me only when apps try to make changes (default)" }
        3 { "Always Notify" }
    }

    Write-AuditLog -Message "Target UAC Level: $levelDescription" -Level "INFO"
    Write-AuditLog -Message "Registry values: ConsentPromptBehaviorAdmin=$consentValue, PromptOnSecureDesktop=$desktopValue" -Level "INFO"

    if ($PSCmdlet.ShouldProcess("UAC Configuration", "Set level to $Level ($levelDescription)")) {
        # Set registry values
        Set-RegistryValue -Path $script:UACRegistryPath -Name $script:ConsentPromptBehaviorAdmin -Value $consentValue
        Set-RegistryValue -Path $script:UACRegistryPath -Name $script:PromptOnSecureDesktop -Value $desktopValue

        Write-AuditLog -Message "UAC level successfully set to $Level ($levelDescription)" -Level "SUCCESS"
        Write-Host "`nUAC configuration updated successfully." -ForegroundColor Green
        Write-Host "IMPORTANT: A system restart may be required for changes to take effect.`n" -ForegroundColor Yellow

        return $true
    }

    return $false
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
try {
    Write-AuditLog -Message "===== UAC Configuration Script Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Operating System: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)" -Level "INFO"

    if ($GetCurrentLevel) {
        #----------------------------------------------
        # Get Current UAC Level
        #----------------------------------------------
        $currentLevel = Get-UACLevel
        Write-Host "`nCurrent UAC Level: $currentLevel`n" -ForegroundColor Cyan
    } else {
        #----------------------------------------------
        # Set UAC Level
        #----------------------------------------------
        # Display current level before change
        Write-Host "`nCurrent UAC Configuration:" -ForegroundColor Cyan
        $currentLevel = Get-UACLevel
        Write-Host $currentLevel -ForegroundColor White

        # Set new level
        Write-Host "`nApplying new UAC configuration..." -ForegroundColor Cyan
        $result = Set-UACLevelInternal -Level $Level

        if ($result) {
            # Display new level after change
            Write-Host "`nNew UAC Configuration:" -ForegroundColor Cyan
            $newLevel = Get-UACLevel
            Write-Host $newLevel -ForegroundColor Green
        }
    }

    Write-AuditLog -Message "===== UAC Configuration Script Completed Successfully =====" -Level "SUCCESS"
    Write-AuditLog -Message "Transcript saved to: $transcriptPath" -Level "INFO"
    Write-AuditLog -Message "Audit log saved to: $script:AuditLogPath" -Level "INFO"

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level "ERROR"
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
} finally {
    # Stop transcript
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if transcript stop fails
    }
}
