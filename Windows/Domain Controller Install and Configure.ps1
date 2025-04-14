<#
.SYNOPSIS
    Installs and configures a Domain Controller with basic settings and DNS configuration.

.DESCRIPTION
    This script installs the Active Directory Domain Services (AD DS) role, promotes the server to a Domain Controller by creating a new AD forest,
    and configures initial DNS settings. It also demonstrates a simple parameterization approach for easy customization.
    
    **Important Note:**  
    The DC promotion step will force a reboot of the system. Any configuration steps after the DC promotion will only execute if the server is still online,
    so typically the DNS configuration and any additional settings should be re-run after reboot or be part of a separate post-promotion script.
    
.PARAMETER domainName
    The fully qualified domain name for the new Active Directory forest (e.g., "yourdomain.local").

.PARAMETER domainAdminPassword
    The strong password for the Domain Admin account (used for the Safe Mode Administrator).

.PARAMETER dnsIpAddress
    The DNS server IP address to assign to the network adapter (for example, the server's own IP).

.EXAMPLE
    PS C:\> .\Configure-DC.ps1 -domainName "yourdomain.local" -domainAdminPassword "YourSecurePassword" -dnsIpAddress "127.0.0.1"

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - The script must be run as Administrator.
      - The server hardware and OS must meet the requirements for Domain Controller promotion.
      - Be aware that the DC promotion will automatically reboot the server.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$domainName,
    
    [Parameter(Mandatory = $true)]
    [string]$domainAdminPassword,
    
    [Parameter(Mandatory = $true)]
    [string]$dnsIpAddress
)

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Logs messages with a timestamp and severity level.
    
    .PARAMETER Message
        The text message to log.
    
    .PARAMETER Level
        The log severity (e.g., "INFO", "ERROR"). Defaults to "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# 1. Install AD DS Role and Management Tools
#----------------------------------------------
Write-Log -Message "Installing Active Directory Domain Services (AD DS) role and management tools..."
try {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    Write-Log -Message "AD DS role installed successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error installing AD DS role: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 2. Promote Server to Domain Controller
#----------------------------------------------
Write-Log -Message "Promoting server to a Domain Controller for the domain '$domainName'..."
try {
    # Promote the server to a Domain Controller (creating a new forest). 
    # -NoRebootOnCompletion:$false ensures that the server reboots after promotion.
    Install-ADDSForest `
        -DomainName $domainName `
        -SafeModeAdministratorPassword (ConvertTo-SecureString -String $domainAdminPassword -AsPlainText -Force) `
        -Force:$true `
        -InstallDns:$true `
        -NoRebootOnCompletion:$false -ErrorAction Stop
    Write-Log -Message "Domain Controller promotion initiated; the server will reboot to complete the process." -Level "INFO"
} catch {
    Write-Log -Message "Error promoting server to Domain Controller: $_" -Level "ERROR"
    exit
}

# --------------------------------------------
# Note: The server will reboot after Install-ADDSForest.
# Post-promotion configuration (e.g., DNS settings) must be applied after the reboot.
# The following section is intended for post-reboot execution.
# --------------------------------------------

#----------------------------------------------
# 3. Configure DNS Settings (Post-Reboot)
#----------------------------------------------
Write-Log -Message "Configuring DNS settings on the 'Ethernet' adapter..."
try {
    # Set the DNS client setting for the "Ethernet" interface to use the specified DNS IP address.
    Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses $dnsIpAddress -ErrorAction Stop
    Write-Log -Message "DNS settings applied successfully on the 'Ethernet' adapter." -Level "INFO"
} catch {
    Write-Log -Message "Error configuring DNS settings: $_" -Level "ERROR"
}

Write-Log -Message "Domain Controller installation and configuration completed." -Level "INFO"
Write-Log -Message "Please note: The Domain Controller promotion triggered a reboot. Run post-promotion steps after the system is back online." -Level "INFO"
