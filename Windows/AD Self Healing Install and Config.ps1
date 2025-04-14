<#
.SYNOPSIS
    Installs and configures a Domain Controller with self-healing features.

.DESCRIPTION
    This script applies several STIG-based configurations for a Domain Controller:
      1. Installs the AD DS role and management tools.
      2. Promotes the server to a Domain Controller, creating a new AD forest.
      3. Configures DNS settings.
      4. Deploys a self-healing script that monitors critical AD services (e.g., NTDS and DNS)
         and restarts them if they are not running.
      5. Schedules the self-healing script to run automatically at startup every 15 minutes.
      
    **Note:** The promotion to Domain Controller will automatically reboot the server.  
    Consider splitting the script into pre-reboot and post-reboot sections, or be prepared to re-run the post-promotion portion
    after the server is back online.

.PARAMETER domainName
    The fully qualified domain name for the new AD forest (e.g., yourdomain.local).

.PARAMETER domainAdminPassword
    The password for the Domain Admin account. This should be a strong password.

.PARAMETER dnsIpAddress
    The DNS server IP address to apply to the network adapter (typically the server's own IP).

.PARAMETER selfHealingScriptPath
    The full file path where the self-healing script will be created and stored.

.EXAMPLE
    .\Configure-DC.ps1 -domainName "yourdomain.local" -domainAdminPassword "YourSecurePassword" `
                       -dnsIpAddress "192.168.1.10" -selfHealingScriptPath "C:\Scripts\SelfHealingScript.ps1"

.NOTES
    Author: Your Name or Organization  
    Date: 2025-04-14  
    Version: 1.0  
    Prerequisites:
      - Must be run as an Administrator.
      - Server must meet all requirements for Domain Controller promotion.
      - Post-promotion steps (DNS & self-healing scheduling) may need to run after reboot.
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$domainName,

    [Parameter(Mandatory=$true)]
    [string]$domainAdminPassword,

    [Parameter(Mandatory=$true)]
    [string]$dnsIpAddress,

    [Parameter(Mandatory=$true)]
    [string]$selfHealingScriptPath
)

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped log message with a specified severity level.
    
    .PARAMETER Message
        The text of the log message.
    
    .PARAMETER Level
        The severity level (e.g., "INFO", "ERROR"). Default is "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

Write-Log -Message "Starting Domain Controller configuration script."

#----------------------------------------------
# 1. Install AD DS Role and Management Tools
#----------------------------------------------
Write-Log -Message "Installing Active Directory Domain Services role and management tools..."
try {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    Write-Log -Message "AD DS role installed successfully." 
} catch {
    Write-Log -Message "Error installing AD DS role: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 2. Promote Server to Domain Controller (Create New Forest)
#----------------------------------------------
Write-Log -Message "Promoting server to Domain Controller for domain '$domainName'..."
try {
    # Promote server to DC and create a new forest. The -NoRebootOnCompletion:$false forces an immediate reboot.
    Install-ADDSForest `
        -DomainName $domainName `
        -SafeModeAdministratorPassword (ConvertTo-SecureString -String $domainAdminPassword -AsPlainText -Force) `
        -Force:$true `
        -InstallDns:$true `
        -NoRebootOnCompletion:$false -ErrorAction Stop
    Write-Log -Message "Domain Controller promotion initiated. The server will reboot automatically."
} catch {
    Write-Log -Message "Error promoting to Domain Controller: $_" -Level "ERROR"
    exit
}

# NOTE: The server will reboot after Install-ADDSForest.
# Subsequent steps (DNS configuration, self-healing script deployment and scheduling) must be executed post-reboot.
# You can integrate this script into a deployment workflow that re-runs post-DC promotion.

#----------------------------------------------
# 3. Configure DNS Settings (Post-Reboot)
#----------------------------------------------
Write-Log -Message "Configuring DNS settings on the 'Ethernet' interface to use DNS server $dnsIpAddress..."
try {
    Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses $dnsIpAddress -ErrorAction Stop
    Write-Log -Message "DNS settings configured successfully." 
} catch {
    Write-Log -Message "Error configuring DNS settings: $_" -Level "ERROR"
}

#----------------------------------------------
# 4. Deploy the Self-Healing Script
#----------------------------------------------
Write-Log -Message "Deploying self-healing script to '$selfHealingScriptPath'..."
try {
    $selfHealingContent = @"
# Self-Healing Script for AD Services
# This script monitors critical AD services and restarts them if they are not running.
Get-Service -Name "NTDS","DNS" | ForEach-Object {
    if ($_.Status -ne "Running") {
        Write-Host "Service $($_.DisplayName) is not running. Attempting to restart..."
        Restart-Service -Name $_.Name -Force
    }
}
"@
    # Save the self-healing script content to the specified file path.
    $selfHealingContent | Out-File -FilePath $selfHealingScriptPath -Encoding UTF8 -Force
    Write-Log -Message "Self-healing script deployed successfully." 
} catch {
    Write-Log -Message "Error deploying self-healing script: $_" -Level "ERROR"
}

#----------------------------------------------
# 5. Schedule the Self-Healing Script to Run Automatically
#----------------------------------------------
Write-Log -Message "Scheduling self-healing script to run every 15 minutes at startup..."
try {
    # Create a scheduled task that runs at startup and repeats every 15 minutes indefinitely.
    $trigger = New-ScheduledTaskTrigger -AtStartup -RepetitionInterval ([TimeSpan]::FromMinutes(15)) -RepeatIndefinitely
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$selfHealingScriptPath`""
    Register-ScheduledTask -TaskName "ADSelfHealingTask" -Action $action -Trigger $trigger -RunLevel Highest -Force
    Write-Log -Message "Scheduled task 'ADSelfHealingTask' created successfully." 
} catch {
    Write-Log -Message "Error scheduling self-healing script: $_" -Level "ERROR"
}

Write-Log -Message "Domain Controller configuration and self-healing setup completed." 
Write-Log -Message "Please reboot the system if it has not already been restarted during DC promotion." -Level "INFO"
