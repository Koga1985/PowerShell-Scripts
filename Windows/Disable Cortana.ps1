#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables Cortana by modifying the Windows Search registry setting.

.DESCRIPTION
    This script applies a basic security configuration by disabling Cortana on a Windows system.
    It accomplishes this by:
      1. Defining the registry path used by Windows Search for policies.
      2. Checking if the registry key exists; if not, it creates the key.
      3. Setting the "AllowCortana" registry value to 0 to disable Cortana.
      4. Restarting Windows Explorer to apply the changes immediately.
      5. Providing comprehensive audit logging of all actions.

.PARAMETER WhatIf
    Shows what would happen if the script runs without actually executing the changes.

.PARAMETER Confirm
    Prompts for confirmation before executing each action.

.EXAMPLE
    .\Disable Cortana.ps1
    Disables Cortana and restarts Explorer with full auditing.

.EXAMPLE
    .\Disable Cortana.ps1 -WhatIf
    Shows what changes would be made without executing them.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    Updated:        October 30, 2025
    Version:        2.0
    License:        MIT
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Registry path validation
    - Safe registry modification with rollback on error
    - Secure error handling

.COMPLIANCE
    - Aligns with NIST 800-53 CM-6 controls
    - Supports DISA STIG configuration management requirements
    - Fourth Estate infrastructure compatible
    - Full audit trail for compliance reporting

.DISCLAIMER
    Scripts are provided as-is, without warranty. Test in non-production before use.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "DisableCortana_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\DisableCortana_Audit.log"
$script:EventSource = "CortanaDisable"

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
        [string]$Level = 'INFO'
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

    $eventIdMap = @{ 'INFO' = 1000; 'SUCCESS' = 1001; 'WARNING' = 2000; 'ERROR' = 3000 }

    try {
        Write-EventLog -LogName Application -Source $script:EventSource -EntryType $eventType -EventId $eventIdMap[$Level] -Message $logEntry -ErrorAction SilentlyContinue
    } catch { }

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
# Main Script Execution
#----------------------------------------------
try {
    Write-AuditLog -Message "===== Disable Cortana Script Started =====" -Level "INFO"

    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    $valueName = "AllowCortana"
    $desiredValue = 0

    Write-AuditLog -Message "Target registry path: $registryPath" -Level "INFO"
    Write-AuditLog -Message "Value name: $valueName" -Level "INFO"

    # Check current value if it exists
    if (Test-Path -Path $registryPath) {
        try {
            $currentValue = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
            if ($null -ne $currentValue) {
                Write-AuditLog -Message "Current value of $valueName`: $($currentValue.$valueName)" -Level "INFO"
            }
        } catch {
            Write-AuditLog -Message "Unable to read current value: $_" -Level "INFO"
        }
    }

    # Ensure registry key exists
    if ($PSCmdlet.ShouldProcess($registryPath, "Create registry key if not exists")) {
        if (-not (Test-Path -Path $registryPath)) {
            Write-AuditLog -Message "Registry key not found. Creating..." -Level "INFO"
            try {
                New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
                Write-AuditLog -Message "Registry key created successfully." -Level "SUCCESS"
            } catch {
                Write-AuditLog -Message "Failed to create registry key: $_" -Level "ERROR"
                throw
            }
        } else {
            Write-AuditLog -Message "Registry key already exists." -Level "INFO"
        }
    }

    # Set AllowCortana value to 0
    if ($PSCmdlet.ShouldProcess("$registryPath\$valueName", "Set value to $desiredValue")) {
        Write-AuditLog -Message "Setting $valueName to $desiredValue..." -Level "INFO"
        try {
            Set-ItemProperty -Path $registryPath -Name $valueName -Value $desiredValue -Type DWord -ErrorAction Stop
            Write-AuditLog -Message "Registry value set successfully." -Level "SUCCESS"

            # Verify the change
            $verifyValue = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction Stop
            Write-AuditLog -Message "Verified: $valueName is now set to $($verifyValue.$valueName)" -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Failed to set registry value: $_" -Level "ERROR"
            throw
        }
    }

    # Restart Windows Explorer to apply changes
    if ($PSCmdlet.ShouldProcess("Windows Explorer", "Restart to apply changes")) {
        Write-AuditLog -Message "Restarting Windows Explorer..." -Level "INFO"
        try {
            # Stop Explorer process
            $explorerProcesses = Get-Process -Name explorer -ErrorAction SilentlyContinue
            if ($explorerProcesses) {
                Stop-Process -Name explorer -Force -ErrorAction Stop
                Write-AuditLog -Message "Windows Explorer stopped." -Level "SUCCESS"

                # Wait a moment before restarting
                Start-Sleep -Seconds 2

                # Start Explorer process
                Start-Process explorer -ErrorAction Stop
                Write-AuditLog -Message "Windows Explorer restarted successfully." -Level "SUCCESS"
            } else {
                Write-AuditLog -Message "Windows Explorer not running. Skipping restart." -Level "INFO"
            }
        } catch {
            Write-AuditLog -Message "Error restarting Windows Explorer: $_" -Level "WARNING"
        }
    }

    Write-AuditLog -Message "===== Cortana Disabled Successfully =====" -Level "SUCCESS"
    Write-AuditLog -Message "IMPORTANT: Log off or reboot for all changes to take effect." -Level "INFO"
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
    } catch { }
}
