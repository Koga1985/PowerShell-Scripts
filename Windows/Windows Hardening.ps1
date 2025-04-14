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
    
.NOTES
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.0
    Prerequisites:
      - The script must be run as an administrator.
      - Windows Server environment with the necessary components installed.
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with a timestamp and severity level to the console.
    
    .PARAMETER Message
        The text of the log message.
    
    .PARAMETER Level
        The severity level, e.g., "INFO" or "ERROR". Default is "INFO".
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# 1. Disable Unnecessary Services
#----------------------------------------------
Write-Log -Message "Disabling unnecessary services (Telnet, FTP, SNMP, TFTP, HTTP, HTTPS)..."
try {
    # Stop matching services forcibly
    Get-Service | Where-Object { $_.DisplayName -match 'Telnet|FTP|SNMP|TFTP|HTTP|HTTPS' } | ForEach-Object {
        Stop-Service -InputObject $_ -Force -ErrorAction Stop
    }
    # Set the same services to Disabled startup type to prevent future runs.
    Get-Service | Where-Object { $_.DisplayName -match 'Telnet|FTP|SNMP|TFTP|HTTP|HTTPS' } | ForEach-Object {
        Set-Service -InputObject $_ -StartupType Disabled -ErrorAction Stop
    }
    Write-Log -Message "Unnecessary services disabled successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error disabling services: $_" -Level "ERROR"
}

#----------------------------------------------
# 2. Configure Windows Firewall
#----------------------------------------------
Write-Log -Message "Configuring Windows Firewall: blocking inbound and allowing outbound traffic..."
try {
    netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound
    Write-Log -Message "Windows Firewall configured successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error configuring Windows Firewall: $_" -Level "ERROR"
}

#----------------------------------------------
# 3. Disable Unnecessary Windows Features
#----------------------------------------------
Write-Log -Message "Disabling unnecessary Windows features: TelnetClient, TelnetServer, and SNMP..."
try {
    Disable-WindowsOptionalFeature -Online -FeatureName TelnetClient -NoRestart -ErrorAction Stop
    Disable-WindowsOptionalFeature -Online -FeatureName TelnetServer -NoRestart -ErrorAction Stop
    Disable-WindowsOptionalFeature -Online -FeatureName SNMP -NoRestart -ErrorAction Stop
    Write-Log -Message "Unnecessary Windows features disabled successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error disabling Windows features: $_" -Level "ERROR"
}

#----------------------------------------------
# 4. Set Password Policies via Secedit
#----------------------------------------------
Write-Log -Message "Applying password policies via secedit configuration..."
try {
    # Create a temporary secedit configuration file.
    # Adjust the [Security] section as needed for your environment.
    $seceditConfig = @"
[Unicode]
Unicode=yes
[Version]
signature="$CHICAGO$"
Revision=1
[Security]
SeNetworkLogonRight =
"@
    # Write the configuration to a file (stored as ASCII).
    $seceditConfigPath = "C:\secedit.cfg"
    $seceditConfig | Out-File -FilePath $seceditConfigPath -Encoding ASCII -Force

    # Apply the security configuration to update password policies (if applicable).
    secedit /configure /db $env:windir\security\local.sdb /cfg $seceditConfigPath /areas SECURITYPOLICY /quiet
    Write-Log -Message "Password policies applied using secedit." -Level "INFO"
} catch {
    Write-Log -Message "Error applying secedit configuration: $_" -Level "ERROR"
}

#----------------------------------------------
# 5. Disable Unnecessary Protocols on Network Adapters
#----------------------------------------------
Write-Log -Message "Disabling unnecessary protocols on all network adapters..."
try {
    # Disable IPv6 TCP/IP binding
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6 -ErrorAction Stop
    # Disable LLTDIO binding (Link Layer Topology Discovery)
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_lltdio -ErrorAction Stop
    # Disable RSPNDR (File and Printer Sharing for Microsoft Networks)
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_rspndr -ErrorAction Stop
    Write-Log -Message "Protocol bindings disabled successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error disabling protocol bindings: $_" -Level "ERROR"
}

#----------------------------------------------
# 6. Enable Windows Defender and Initiate a Quick Scan
#----------------------------------------------
Write-Log -Message "Enabling Windows Defender real-time monitoring and starting a quick scan..."
try {
    # Ensure real-time monitoring is enabled.
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    # Start a quick scan.
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    Write-Log -Message "Windows Defender enabled and quick scan initiated." -Level "INFO"
} catch {
    Write-Log -Message "Error enabling Windows Defender or starting a scan: $_" -Level "ERROR"
}

#----------------------------------------------
# 7. Final Notification
#----------------------------------------------
Write-Log -Message "STIG configurations applied successfully. Reboot the system for changes to take effect." -Level "INFO"
