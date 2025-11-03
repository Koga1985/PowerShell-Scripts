#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies a set of basic Security Technical Implementation Guide (STIG) configurations on a Windows Server.

.DESCRIPTION
    This script implements fundamental hardening recommendations by:
      1. Disabling unnecessary services (Telnet, FTP, SNMP, TFTP, HTTP, HTTPS) to reduce the attack surface.
      2. Configuring the Windows Firewall to block all inbound traffic and allow outbound traffic.
      3. Disabling unneeded Windows features (such as Telnet Client/Server and SNMP).
      4. Enforcing certain password policies via a security configuration file.
      5. Disabling unnecessary network protocols on all network adapters.
      6. Enabling and running a quick scan with Windows Defender.

    Before running the script, please verify that the services and features being disabled are not needed in your environment.

.PARAMETER WhatIf
    Shows what would happen if the script runs without actually executing the changes.

.PARAMETER Confirm
    Prompts for confirmation before executing each hardening action.

.EXAMPLE
    .\Windows Hardening.ps1
    Applies all hardening configurations with full audit logging.

.EXAMPLE
    .\Windows Hardening.ps1 -WhatIf
    Shows what changes would be made without executing them.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - Windows Server environment with the necessary components installed

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Input validation and sanitization
    - Secure error handling with proper cleanup
    - Modern CIM cmdlets instead of legacy WMI

.COMPLIANCE
    - Aligns with NIST 800-53 controls
    - Supports DISA STIG requirements
    - Fourth Estate infrastructure compatible
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "WindowsHardening_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\WindowsHardening_Audit.log"
$script:EventSource = "WindowsHardening"

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
    <#
    .SYNOPSIS
        Writes comprehensive audit logs to file and Windows Event Log.

    .PARAMETER Message
        The audit message to log.

    .PARAMETER Level
        The severity level: INFO, WARNING, ERROR, SUCCESS. Default is INFO.

    .PARAMETER EventId
        Optional Event ID for Windows Event Log. Defaults based on level.
    #>
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
# Input Validation Function
#----------------------------------------------
function Test-SecurePath {
    <#
    .SYNOPSIS
        Validates and sanitizes file paths.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Check for dangerous patterns
    $dangerousPatterns = @('\.\.', '\$', '`', ';', '&', '|', '<', '>')
    foreach ($pattern in $dangerousPatterns) {
        if ($Path -match [regex]::Escape($pattern)) {
            throw "Path contains potentially dangerous characters: $pattern"
        }
    }

    return $true
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
try {
    Write-AuditLog -Message "===== Windows Hardening Script Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Execution Policy: $(Get-ExecutionPolicy)" -Level "INFO"

    #----------------------------------------------
    # 1. Disable Unnecessary Services
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess("System Services", "Disable unnecessary services (Telnet, FTP, SNMP, TFTP, HTTP, HTTPS)")) {
        Write-AuditLog -Message "Disabling unnecessary services..." -Level "INFO"

        try {
            $servicesToDisable = Get-Service | Where-Object { $_.DisplayName -match 'Telnet|FTP|SNMP|TFTP|HTTP|HTTPS' }

            if ($servicesToDisable) {
                foreach ($service in $servicesToDisable) {
                    try {
                        Write-AuditLog -Message "Stopping service: $($service.Name)" -Level "INFO"
                        Stop-Service -InputObject $service -Force -ErrorAction Stop

                        Write-AuditLog -Message "Disabling service: $($service.Name)" -Level "INFO"
                        Set-Service -InputObject $service -StartupType Disabled -ErrorAction Stop

                        Write-AuditLog -Message "Service disabled successfully: $($service.Name)" -Level "SUCCESS"
                    } catch {
                        Write-AuditLog -Message "Failed to disable service $($service.Name): $_" -Level "WARNING"
                    }
                }
            } else {
                Write-AuditLog -Message "No unnecessary services found to disable." -Level "INFO"
            }
        } catch {
            Write-AuditLog -Message "Error during service enumeration: $_" -Level "ERROR"
        }
    }

    #----------------------------------------------
    # 2. Configure Windows Firewall
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess("Windows Firewall", "Configure to block inbound and allow outbound traffic")) {
        Write-AuditLog -Message "Configuring Windows Firewall..." -Level "INFO"

        try {
            $firewallProfiles = @('DomainProfile', 'PublicProfile', 'PrivateProfile')

            foreach ($profile in $firewallProfiles) {
                $params = @{
                    Profile              = $profile
                    DefaultInboundAction = 'Block'
                    DefaultOutboundAction = 'Allow'
                    Enabled              = 'True'
                }

                Set-NetFirewallProfile @params -ErrorAction Stop
                Write-AuditLog -Message "Firewall configured for profile: $profile" -Level "SUCCESS"
            }
        } catch {
            Write-AuditLog -Message "Error configuring Windows Firewall: $_" -Level "ERROR"
        }
    }

    #----------------------------------------------
    # 3. Disable Unnecessary Windows Features
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess("Windows Features", "Disable TelnetClient, TelnetServer, and SNMP")) {
        Write-AuditLog -Message "Disabling unnecessary Windows features..." -Level "INFO"

        $featuresToDisable = @('TelnetClient', 'TelnetServer', 'SNMP')

        foreach ($feature in $featuresToDisable) {
            try {
                $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue

                if ($featureState -and $featureState.State -eq 'Enabled') {
                    Write-AuditLog -Message "Disabling feature: $feature" -Level "INFO"
                    Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop | Out-Null
                    Write-AuditLog -Message "Feature disabled: $feature" -Level "SUCCESS"
                } else {
                    Write-AuditLog -Message "Feature already disabled or not found: $feature" -Level "INFO"
                }
            } catch {
                Write-AuditLog -Message "Error disabling feature $feature`: $_" -Level "WARNING"
            }
        }
    }

    #----------------------------------------------
    # 4. Set Password Policies via Secedit
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess("Security Policies", "Apply password policies via secedit")) {
        Write-AuditLog -Message "Applying password policies via secedit..." -Level "INFO"

        try {
            $seceditConfig = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordAge = 1
MaximumPasswordAge = 60
MinimumPasswordLength = 14
PasswordComplexity = 1
PasswordHistorySize = 24
[Event Audit]
AuditLogonEvents = 3
AuditAccountLogon = 3
AuditSystemEvents = 3
"@

            $seceditConfigPath = Join-Path $env:TEMP "secedit_$(Get-Date -Format 'yyyyMMddHHmmss').cfg"
            Test-SecurePath -Path $seceditConfigPath

            $seceditConfig | Out-File -FilePath $seceditConfigPath -Encoding ASCII -Force
            Write-AuditLog -Message "Secedit configuration file created: $seceditConfigPath" -Level "INFO"

            $seceditArgs = "/configure /db $env:windir\security\local.sdb /cfg `"$seceditConfigPath`" /areas SECURITYPOLICY /quiet"
            $process = Start-Process -FilePath "secedit.exe" -ArgumentList $seceditArgs -Wait -NoNewWindow -PassThru

            if ($process.ExitCode -eq 0) {
                Write-AuditLog -Message "Password policies applied successfully via secedit." -Level "SUCCESS"
            } else {
                Write-AuditLog -Message "Secedit returned exit code: $($process.ExitCode)" -Level "WARNING"
            }

            # Clean up configuration file
            Remove-Item -Path $seceditConfigPath -Force -ErrorAction SilentlyContinue
        } catch {
            Write-AuditLog -Message "Error applying secedit configuration: $_" -Level "ERROR"
        }
    }

    #----------------------------------------------
    # 5. Disable Unnecessary Protocols on Network Adapters
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess("Network Adapters", "Disable unnecessary protocols")) {
        Write-AuditLog -Message "Disabling unnecessary protocols on network adapters..." -Level "INFO"

        try {
            $bindingsToDisable = @(
                @{ Name = 'IPv6'; ComponentID = 'ms_tcpip6' },
                @{ Name = 'LLTDIO'; ComponentID = 'ms_lltdio' },
                @{ Name = 'RSPNDR'; ComponentID = 'ms_rspndr' }
            )

            foreach ($binding in $bindingsToDisable) {
                try {
                    $params = @{
                        Name         = '*'
                        ComponentID  = $binding.ComponentID
                        ErrorAction  = 'Stop'
                    }

                    Disable-NetAdapterBinding @params
                    Write-AuditLog -Message "Disabled $($binding.Name) binding on all adapters." -Level "SUCCESS"
                } catch {
                    Write-AuditLog -Message "Error disabling $($binding.Name) binding: $_" -Level "WARNING"
                }
            }
        } catch {
            Write-AuditLog -Message "Error configuring network adapter bindings: $_" -Level "ERROR"
        }
    }

    #----------------------------------------------
    # 6. Enable Windows Defender and Initiate a Quick Scan
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess("Windows Defender", "Enable real-time monitoring and start quick scan")) {
        Write-AuditLog -Message "Enabling Windows Defender and starting quick scan..." -Level "INFO"

        try {
            # Enable real-time monitoring
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
            Write-AuditLog -Message "Windows Defender real-time monitoring enabled." -Level "SUCCESS"

            # Update signatures
            Write-AuditLog -Message "Updating Windows Defender signatures..." -Level "INFO"
            Update-MpSignature -ErrorAction Stop
            Write-AuditLog -Message "Windows Defender signatures updated." -Level "SUCCESS"

            # Start quick scan
            Write-AuditLog -Message "Starting Windows Defender quick scan..." -Level "INFO"
            Start-MpScan -ScanType QuickScan -ErrorAction Stop
            Write-AuditLog -Message "Windows Defender quick scan completed." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Error with Windows Defender operations: $_" -Level "ERROR"
        }
    }

    #----------------------------------------------
    # Final Notification
    #----------------------------------------------
    Write-AuditLog -Message "===== Windows Hardening Script Completed Successfully =====" -Level "SUCCESS"
    Write-AuditLog -Message "IMPORTANT: Reboot the system for all changes to take effect." -Level "INFO"
    Write-AuditLog -Message "Transcript saved to: $transcriptPath" -Level "INFO"
    Write-AuditLog -Message "Audit log saved to: $script:AuditLogPath" -Level "INFO"

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR in Windows Hardening Script: $_" -Level "ERROR"
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
} finally {
    # Stop transcript
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if transcript stop fails
    }

    # Clear any sensitive data from memory
    if (Test-Path variable:seceditConfig) {
        Remove-Variable -Name seceditConfig -Force -ErrorAction SilentlyContinue
    }
}
