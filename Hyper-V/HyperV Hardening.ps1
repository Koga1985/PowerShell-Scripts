<#
.SYNOPSIS
    Implements basic STIG recommendations for Hyper-V security configuration.

.DESCRIPTION
    This script applies several recommended security settings for a Hyper-V host, including:
      1. Enabling the VirtualMachinePlatform feature (used by Credential Guard / virtualization-based security).
      2. Enabling Enhanced Session Mode and Guest Services on the Hyper-V host.
      3. Disabling named pipe connections (COM ports) for VMs to reduce their exposure.
      4. Disabling clipboard integration for VMs to mitigate data exfiltration risks.
      5. Configuring VMs to use the HvSocket transport type for Enhanced Session Mode (disabling the default Enhanced Session Mode).
      
    These settings align with basic Security Technical Implementation Guide (STIG) recommendations.
    
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
      - Script must be run as an administrator.
      - Hyper-V must be installed and the Hyper-V PowerShell module must be available.
      - The target system must support the VirtualMachinePlatform feature.
#>

#----------------------------------------------
<#
Checks for admin rights and Hyper-V module before running.
#>
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Script must be run as Administrator." -ForegroundColor Red
    exit 1
}
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    Write-Host "ERROR: Hyper-V PowerShell module is not available." -ForegroundColor Red
    exit 1
}

# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a timestamped log message with a severity level.
    
    .PARAMETER Message
        The message text.
    
    .PARAMETER Level
        The message severity (e.g., "INFO", "ERROR"). Default is "INFO".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# 1. Enable VirtualMachinePlatform Feature
#----------------------------------------------
# This optional feature is a prerequisite for virtualization-based security (e.g., Credential Guard).
Write-Log -Message "Enabling VirtualMachinePlatform feature (if applicable)..."
try {
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -ErrorAction Stop
    Write-Log -Message "VirtualMachinePlatform feature enabled successfully." -Level "INFO"
} catch {
    Write-Log -Message "Failed to enable VirtualMachinePlatform: $_" -Level "ERROR"
}

#----------------------------------------------
# 2. Configure Hyper-V Host Security Options
#----------------------------------------------
try {
    Write-Log -Message "Enabling Enhanced Session Mode on Hyper-V host..."
    Set-VMHost -EnableEnhancedSessionMode $true -ErrorAction Stop
    Write-Log -Message "Enhanced Session Mode enabled." -Level "INFO"
    
    Write-Log -Message "Enabling Guest Services on Hyper-V host..."
    Set-VMHost -EnableGuestServices $true -ErrorAction Stop
    Write-Log -Message "Guest Services enabled." -Level "INFO"
} catch {
    Write-Log -Message "Error configuring Hyper-V host security settings: $_" -Level "ERROR"
}

#----------------------------------------------

# Helper function for VM actions with error handling
function Invoke-VMAction {
    param(
        [string]$ActionDesc,
        [scriptblock]$Action
    )
    try {
        Write-Log -Message $ActionDesc
        & $Action
        Write-Log -Message "$ActionDesc completed." -Level "INFO"
        return $true
    } catch {
        Write-Log -Message "Error: $ActionDesc failed: $_" -Level "ERROR"
        return $false
    }
}

# 3. Disable Named Pipe Connections for VMs
#----------------------------------------------
$pipeCom1 = Invoke-VMAction -ActionDesc "Disabling named pipe for COM1 on all VMs..." -Action {
    Get-VM | ForEach-Object { Set-VMComPort -VM $_ -Number 1 -Name "COM1" -PipeName $null -ErrorAction Stop }
}
$pipeCom2 = Invoke-VMAction -ActionDesc "Disabling named pipe for COM2 on all VMs..." -Action {
    Get-VM | ForEach-Object { Set-VMComPort -VM $_ -Number 2 -Name "COM2" -PipeName $null -ErrorAction Stop }
}

#----------------------------------------------
# 4. Disable Clipboard Integration for VMs
#----------------------------------------------
$clipboard = Invoke-VMAction -ActionDesc "Disabling clipboard integration for all VMs..." -Action {
    Get-VM | ForEach-Object { Set-VMIntegrationService -VM $_ -Name "Clipboard" -Enabled $false -ErrorAction Stop }
}

#----------------------------------------------
# 5. Set Enhanced Session Transport Type to HvSocket for VMs
#----------------------------------------------
$hvSocket = Invoke-VMAction -ActionDesc "Setting Enhanced Session Transport Type to HvSocket for all VMs..." -Action {
    Get-VM | ForEach-Object { Set-VM -VM $_ -EnhancedSessionTransportType HvSocket -ErrorAction Stop }
}


#----------------------------------------------
# Summary Output
#----------------------------------------------
Write-Log -Message "Hyper-V STIG configuration completed." -Level "INFO"
Write-Host "\nSummary:" -ForegroundColor Cyan
Write-Host "Named pipe for COM1: $($pipeCom1 ? 'Success' : 'Failed')"
Write-Host "Named pipe for COM2: $($pipeCom2 ? 'Success' : 'Failed')"
Write-Host "Clipboard integration: $($clipboard ? 'Success' : 'Failed')"
Write-Host "Enhanced Session Transport Type: $($hvSocket ? 'Success' : 'Failed')"
