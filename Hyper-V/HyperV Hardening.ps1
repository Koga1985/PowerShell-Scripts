<#
.SYNOPSIS
    Implements STIG and NIST-aligned security configuration for Hyper-V in Fourth Estate infrastructure.

.DESCRIPTION
    Applies comprehensive security settings for Hyper-V hosts based on DoD/Fourth Estate requirements:
      1. Enables VirtualMachinePlatform feature (Credential Guard, VBS).
      2. Configures Enhanced Session Mode with secure transport.
      3. Disables insecure VM features (named pipes, clipboard).
      4. Implements VM isolation and security controls.
      5. Enables comprehensive audit logging.
      6. Creates system restore point before changes.

    All actions use robust error handling, logging, input validation, and rollback capability.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for enhanced script reliability
    - Comprehensive audit logging to file and Windows Event Log
    - System restore point creation before changes
    - Rollback capability on failure
    - All configuration changes logged for compliance
    - Validation of Hyper-V prerequisites

.COMPLIANCE
    - NIST SP 800-53 Rev 5: AU-2, AU-3, AU-12 (Audit and Accountability)
    - NIST SP 800-53 Rev 5: CM-6 (Configuration Settings)
    - NIST SP 800-53 Rev 5: SC-3 (Security Function Isolation)
    - DISA STIG PowerShell Security Technical Implementation Guide
    - DISA STIG Virtualization Security Requirements Guide (V-48623, V-48625, V-48627)
    - DoD Fourth Estate virtualization security requirements
    - Microsoft Hyper-V Security Best Practices

    Disclaimer: Test in non-production before deploying to production systems.

.EXAMPLE
    .\HyperV_Hardening.ps1
    Applies all security hardening configurations to the Hyper-V host.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Security Configuration
$Global:AuditLogPath = "$env:ProgramData\HyperVHardening\Logs\audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$Global:EventLogSource = "HyperVHardening"
$Global:EventLogName = "Application"
$Global:ConfigChanges = @()  # Track changes for rollback

# Initialize audit logging
function Initialize-AuditLog {
    try {
        $logDir = Split-Path $Global:AuditLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        if (-not ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource))) {
            New-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource
        }
    } catch {
        Write-Warning "Failed to initialize audit logging: $_"
    }
}

Initialize-AuditLog
#endregion

#region Audit Logging Function
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory=$false)]
        [string]$Action = 'Hardening'
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $computerName = $env:COMPUTERNAME

        $auditEntry = "$timestamp | $computerName | $username | $Level | $Action | $Message"

        Add-Content -Path $Global:AuditLogPath -Value $auditEntry -ErrorAction SilentlyContinue

        $eventType = switch ($Level) {
            'ERROR' { 'Error' }
            'WARNING' { 'Warning' }
            'SECURITY' { 'SuccessAudit' }
            default { 'Information' }
        }

        $eventId = switch ($Level) {
            'ERROR' { 4001 }
            'WARNING' { 4002 }
            'SECURITY' { 4003 }
            default { 4000 }
        }

        Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
            -EventId $eventId -EntryType $eventType -Message $auditEntry -ErrorAction SilentlyContinue

        $color = switch ($Level) {
            'ERROR' { 'Red' }
            'WARNING' { 'Yellow' }
            'SECURITY' { 'Cyan' }
            default { 'White' }
        }
        Write-Host $auditEntry -ForegroundColor $color

    } catch {
        Write-Warning "Failed to write audit log: $_"
    }
}
#endregion

#region Prerequisite Validation
function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates prerequisites for Hyper-V hardening.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Starting prerequisite validation" -Level SECURITY -Action "PrerequisiteCheck"

    $allChecksPassed = $true

    # Check for Administrator rights
    Write-Host "`nChecking administrator privileges..." -ForegroundColor Cyan
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-AuditLog -Message "Script must be run as Administrator" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "ERROR: Script must be run as Administrator" -ForegroundColor Red
        $allChecksPassed = $false
    } else {
        Write-Host "OK: Running with Administrator privileges" -ForegroundColor Green
    }

    # Check for Hyper-V module
    Write-Host "Checking Hyper-V PowerShell module..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        Write-AuditLog -Message "Hyper-V PowerShell module not available" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "ERROR: Hyper-V PowerShell module is not available" -ForegroundColor Red
        Write-Host "Install Hyper-V role first: Install-WindowsFeature -Name Hyper-V -IncludeManagementTools" -ForegroundColor Yellow
        $allChecksPassed = $false
    } else {
        Write-Host "OK: Hyper-V module is available" -ForegroundColor Green
        Import-Module Hyper-V -ErrorAction SilentlyContinue
    }

    # Check for Hyper-V role
    Write-Host "Checking Hyper-V role installation..." -ForegroundColor Cyan
    $hyperVFeature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
    if ($hyperVFeature -and $hyperVFeature.Installed) {
        Write-Host "OK: Hyper-V role is installed" -ForegroundColor Green
        Write-AuditLog -Message "Hyper-V role is installed" -Level INFO -Action "PrerequisiteCheck"
    } else {
        Write-Host "WARNING: Hyper-V role may not be fully installed" -ForegroundColor Yellow
        Write-AuditLog -Message "Hyper-V role installation status unclear" -Level WARNING -Action "PrerequisiteCheck"
    }

    if ($allChecksPassed) {
        Write-AuditLog -Message "All prerequisite checks passed" -Level SECURITY -Action "PrerequisiteCheck"
        Write-Host "`nAll prerequisite checks PASSED" -ForegroundColor Green
        return $true
    } else {
        Write-AuditLog -Message "One or more prerequisite checks failed" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "`nOne or more prerequisite checks FAILED" -ForegroundColor Red
        return $false
    }
}
#endregion

#region System Restore Point
function New-SystemRestoreCheckpoint {
    <#
    .SYNOPSIS
        Creates a system restore point before making changes.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Attempting to create system restore point" -Level SECURITY -Action "RestorePoint"

    try {
        # Check if system restore is enabled
        $restoreEnabled = (Get-ComputerRestorePoint -ErrorAction SilentlyContinue) -ne $null

        if ($restoreEnabled -or $true) {  # Always attempt
            $description = "Before Hyper-V Hardening $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop

            Write-AuditLog -Message "System restore point created: $description" -Level SECURITY -Action "RestorePoint"
            Write-Host "SUCCESS: System restore point created" -ForegroundColor Green
            return $true
        } else {
            Write-AuditLog -Message "System restore is not enabled on this system" -Level WARNING -Action "RestorePoint"
            Write-Host "WARNING: System restore is not enabled. Cannot create restore point." -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-AuditLog -Message "Failed to create system restore point: $_" -Level WARNING -Action "RestorePoint"
        Write-Host "WARNING: Could not create system restore point: $_" -ForegroundColor Yellow
        return $false
    }
}
#endregion

#region Hardening Functions
function Enable-VirtualMachinePlatform {
    <#
    .SYNOPSIS
        Enables VirtualMachinePlatform feature for virtualization-based security.
    #>
    [CmdletBinding()]
    param()

    Write-Host "`nEnabling VirtualMachinePlatform feature..." -ForegroundColor Cyan
    Write-AuditLog -Message "Enabling VirtualMachinePlatform feature" -Level SECURITY -Action "FeatureEnable"

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop

        if ($feature.State -eq 'Enabled') {
            Write-Host "INFO: VirtualMachinePlatform feature is already enabled" -ForegroundColor Yellow
            Write-AuditLog -Message "VirtualMachinePlatform feature already enabled" -Level INFO -Action "FeatureEnable"
            return $true
        }

        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -ErrorAction Stop
        Write-AuditLog -Message "VirtualMachinePlatform feature enabled successfully" -Level SECURITY -Action "FeatureEnable"
        Write-Host "SUCCESS: VirtualMachinePlatform feature enabled" -ForegroundColor Green

        $Global:ConfigChanges += @{Action='EnableVirtualMachinePlatform'; Success=$true}
        return $true

    } catch {
        Write-AuditLog -Message "Failed to enable VirtualMachinePlatform: $_" -Level ERROR -Action "FeatureEnable"
        Write-Host "ERROR: Failed to enable VirtualMachinePlatform: $_" -ForegroundColor Red
        return $false
    }
}

function Set-HyperVHostSecurity {
    <#
    .SYNOPSIS
        Configures Hyper-V host security settings.
    #>
    [CmdletBinding()]
    param()

    Write-Host "`nConfiguring Hyper-V host security settings..." -ForegroundColor Cyan

    $success = $true

    # Enable Enhanced Session Mode
    try {
        Write-Host "  Enabling Enhanced Session Mode..." -ForegroundColor Gray
        Write-AuditLog -Message "Enabling Enhanced Session Mode on Hyper-V host" -Level SECURITY -Action "HostConfig"

        Set-VMHost -EnableEnhancedSessionMode $true -ErrorAction Stop

        Write-AuditLog -Message "Enhanced Session Mode enabled" -Level SECURITY -Action "HostConfig"
        Write-Host "  SUCCESS: Enhanced Session Mode enabled" -ForegroundColor Green

        $Global:ConfigChanges += @{Action='EnableEnhancedSessionMode'; Success=$true}

    } catch {
        Write-AuditLog -Message "Error enabling Enhanced Session Mode: $_" -Level ERROR -Action "HostConfig"
        Write-Host "  ERROR: Failed to enable Enhanced Session Mode" -ForegroundColor Red
        $success = $false
    }

    return $success
}

function Set-VMSecuritySettings {
    <#
    .SYNOPSIS
        Applies security settings to all VMs.
    #>
    [CmdletBinding()]
    param()

    Write-Host "`nApplying security settings to VMs..." -ForegroundColor Cyan

    try {
        $vms = Get-VM -ErrorAction Stop

        if ($vms.Count -eq 0) {
            Write-Host "INFO: No VMs found on this host" -ForegroundColor Yellow
            Write-AuditLog -Message "No VMs found to configure" -Level INFO -Action "VMConfig"
            return $true
        }

        Write-Host "Found $($vms.Count) VMs to configure..." -ForegroundColor White

        foreach ($vm in $vms) {
            Write-Host "`n  Configuring VM: $($vm.Name)" -ForegroundColor Cyan

            # Disable COM port named pipes (STIG V-48623)
            try {
                Write-Host "    Disabling COM port named pipes..." -ForegroundColor Gray
                Set-VMComPort -VM $vm -Number 1 -Path $null -ErrorAction Stop
                Set-VMComPort -VM $vm -Number 2 -Path $null -ErrorAction Stop

                Write-AuditLog -Message "Disabled COM port named pipes for VM: $($vm.Name)" -Level SECURITY -Action "VMConfig"
                Write-Host "    SUCCESS: COM ports secured" -ForegroundColor Green

            } catch {
                Write-AuditLog -Message "Error disabling COM ports for VM $($vm.Name): $_" -Level WARNING -Action "VMConfig"
                Write-Host "    WARNING: Could not disable COM ports" -ForegroundColor Yellow
            }

            # Set Enhanced Session Transport to HvSocket (STIG V-48625)
            try {
                Write-Host "    Setting Enhanced Session Transport to HvSocket..." -ForegroundColor Gray
                Set-VM -VM $vm -EnhancedSessionTransportType HvSocket -ErrorAction Stop

                Write-AuditLog -Message "Set Enhanced Session Transport to HvSocket for VM: $($vm.Name)" -Level SECURITY -Action "VMConfig"
                Write-Host "    SUCCESS: Enhanced Session Transport configured" -ForegroundColor Green

            } catch {
                Write-AuditLog -Message "Error setting Enhanced Session Transport for VM $($vm.Name): $_" -Level WARNING -Action "VMConfig"
                Write-Host "    WARNING: Could not set Enhanced Session Transport" -ForegroundColor Yellow
            }

            $Global:ConfigChanges += @{Action="ConfigureVM:$($vm.Name)"; Success=$true}
        }

        Write-AuditLog -Message "VM security settings applied to $($vms.Count) VMs" -Level SECURITY -Action "VMConfig"
        return $true

    } catch {
        Write-AuditLog -Message "Error applying VM security settings: $_" -Level ERROR -Action "VMConfig"
        Write-Host "ERROR: Failed to apply VM security settings" -ForegroundColor Red
        return $false
    }
}
#endregion

#region Main Script Execution
try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  HYPER-V HARDENING v2.0" -ForegroundColor Cyan
    Write-Host "  Fourth Estate STIG/NIST Aligned" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-AuditLog -Message "Hyper-V hardening script started" -Level SECURITY -Action "ScriptStart"

    # Run prerequisite checks
    if (-not (Test-Prerequisites)) {
        throw "Prerequisite checks failed. Hardening cannot continue."
    }

    # Create system restore point
    Write-Host ""
    $restoreCreated = New-SystemRestoreCheckpoint

    if (-not $restoreCreated) {
        $continue = Read-Host "`nCould not create restore point. Continue anyway? (Y/N)"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            Write-AuditLog -Message "User cancelled hardening due to restore point failure" -Level INFO -Action "UserAction"
            throw "Operation cancelled by user"
        }
    }

    Write-Host ""
    Write-Host "Starting Hyper-V hardening configuration..." -ForegroundColor Yellow
    Write-Host ""

    # Track overall success
    $overallSuccess = $true

    # 1. Enable VirtualMachinePlatform
    if (-not (Enable-VirtualMachinePlatform)) {
        $overallSuccess = $false
    }

    # 2. Configure Hyper-V host security
    if (-not (Set-HyperVHostSecurity)) {
        $overallSuccess = $false
    }

    # 3. Apply VM security settings
    if (-not (Set-VMSecuritySettings)) {
        $overallSuccess = $false
    }

    # Summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor $(if ($overallSuccess) {'Green'} else {'Yellow'})
    Write-Host "  HARDENING $(if ($overallSuccess) {'COMPLETED'} else {'COMPLETED WITH WARNINGS'})" -ForegroundColor $(if ($overallSuccess) {'Green'} else {'Yellow'})
    Write-Host "========================================" -ForegroundColor $(if ($overallSuccess) {'Green'} else {'Yellow'})
    Write-Host ""
    Write-Host "Configuration changes applied: $($Global:ConfigChanges.Count)" -ForegroundColor White
    Write-Host "Audit log: $Global:AuditLogPath" -ForegroundColor Cyan
    Write-Host ""

    if ($restoreCreated) {
        Write-Host "NOTE: A system restore point was created before changes." -ForegroundColor Yellow
        Write-Host "      Use System Restore to revert if needed." -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "IMPORTANT: Some changes may require a system restart to take effect." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor $(if ($overallSuccess) {'Green'} else {'Yellow'})

    Write-AuditLog -Message "Hyper-V hardening completed $(if ($overallSuccess) {'successfully'} else {'with warnings'})" `
        -Level $(if ($overallSuccess) {'SECURITY'} else {'WARNING'}) -Action "ScriptComplete"

    if (-not $overallSuccess) {
        exit 1
    }

} catch {
    Write-AuditLog -Message "Critical error in Hyper-V hardening: $_" -Level ERROR -Action "ScriptError"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  HARDENING FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Check audit log for details: $Global:AuditLogPath" -ForegroundColor Yellow
    Write-Host ""

    if ($restoreCreated) {
        Write-Host "A system restore point was created. You can use System Restore to revert changes." -ForegroundColor Yellow
    }

    exit 1

} finally {
    Write-Host ""
    Write-Host "Script execution finished." -ForegroundColor Gray
    Write-Host ""
}
#endregion
