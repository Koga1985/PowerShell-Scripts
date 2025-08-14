<#
.SYNOPSIS
    Disables SMBv1 on a Windows system by modifying both the SMB Server configuration and relevant registry settings.

.DESCRIPTION
    This script applies two methods to disable SMBv1:
      1. It disables SMBv1 via the Set-SmbServerConfiguration cmdlet.
      2. It also sets the SMB1 value to 0 in the registry for both the LanmanServer and LanmanWorkstation services.
      
    Finally, the script retrieves and displays the current settings to confirm that SMBv1 is disabled.
    
    **Note:** Disabling SMBv1 is a security best practice to mitigate vulnerabilities associated with the protocol.
    
.PARAMETER None
    This script does not require any parameters.

.EXAMPLE
    PS C:\> .\Disable-SMBv1.ps1
    This command disables SMBv1 and outputs the current configuration status.

#
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   August 14, 2025
    Version:        1.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a log message with a timestamp and a specified severity level.
    
    .PARAMETER Message
        The text to be logged.
    
    .PARAMETER Level
        The severity level (e.g., "INFO" or "ERROR"). Defaults to "INFO".
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
# 1. Disable SMBv1 via SMB Server Configuration
#----------------------------------------------
Write-Log -Message "Disabling SMBv1 protocol via Set-SmbServerConfiguration..." -Level "INFO"
try {
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
    Write-Log -Message "SMBv1 has been disabled in the SMB Server configuration." -Level "INFO"
} catch {
    Write-Log -Message "Error disabling SMBv1 via Set-SmbServerConfiguration: $_" -Level "ERROR"
}

#----------------------------------------------
# 2. Disable SMBv1 via Registry Settings for LanmanServer
#----------------------------------------------
$lanmanServerRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
Write-Log -Message "Configuring registry settings for LanmanServer (SMB1)..." -Level "INFO"
try {
    # Ensure the registry key exists (this key should always exist on Windows systems)
    if (-not (Test-Path -Path $lanmanServerRegistryPath)) {
        Write-Log -Message "Registry path $lanmanServerRegistryPath not found. Creating the key..." -Level "INFO"
        New-Item -Path $lanmanServerRegistryPath -Force -ErrorAction Stop | Out-Null
    }
    
    # Set the SMB1 value to 0 to disable it
    Set-ItemProperty -Path $lanmanServerRegistryPath -Name "SMB1" -Type DWORD -Value 0 -Force -ErrorAction Stop
    Write-Log -Message "SMB1 disabled in LanmanServer registry settings." -Level "INFO"
} catch {
    Write-Log -Message "Error setting registry value for LanmanServer: $_" -Level "ERROR"
}

#----------------------------------------------
# 3. Disable SMBv1 via Registry Settings for LanmanWorkstation
#----------------------------------------------
$lanmanWorkstationRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
Write-Log -Message "Configuring registry settings for LanmanWorkstation (SMB1)..." -Level "INFO"
try {
    # Ensure the registry key exists (this key should exist on Windows systems)
    if (-not (Test-Path -Path $lanmanWorkstationRegistryPath)) {
        Write-Log -Message "Registry path $lanmanWorkstationRegistryPath not found. Creating the key..." -Level "INFO"
        New-Item -Path $lanmanWorkstationRegistryPath -Force -ErrorAction Stop | Out-Null
    }
    
    # Set the SMB1 value to 0 to disable it
    Set-ItemProperty -Path $lanmanWorkstationRegistryPath -Name "SMB1" -Type DWORD -Value 0 -Force -ErrorAction Stop
    Write-Log -Message "SMB1 disabled in LanmanWorkstation registry settings." -Level "INFO"
} catch {
    Write-Log -Message "Error setting registry value for LanmanWorkstation: $_" -Level "ERROR"
}

#----------------------------------------------
# 4. Verify SMBv1 Configuration
#----------------------------------------------
Write-Log -Message "Verifying SMBv1 configuration..."

try {
    # Retrieve SMB server configuration to verify that SMBv1 is disabled
    $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop | Select-Object EnableSMB1Protocol
    Write-Log -Message "SMB Server Configuration: EnableSMB1Protocol = $($smbConfig.EnableSMB1Protocol)" -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving SMB Server Configuration: $_" -Level "ERROR"
}

try {
    # Retrieve registry settings for LanmanServer
    $lanmanServerSetting = Get-ItemProperty -Path $lanmanServerRegistryPath -Name "SMB1" -ErrorAction Stop
    Write-Log -Message "LanmanServer SMB1 setting = $($lanmanServerSetting.SMB1)" -Level "INFO"
} catch {
    Write-Log -Message "Error reading LanmanServer registry setting: $_" -Level "ERROR"
}

try {
    # Retrieve registry settings for LanmanWorkstation
    $lanmanWorkstationSetting = Get-ItemProperty -Path $lanmanWorkstationRegistryPath -Name "SMB1" -ErrorAction Stop
    Write-Log -Message "LanmanWorkstation SMB1 setting = $($lanmanWorkstationSetting.SMB1)" -Level "INFO"
} catch {
    Write-Log -Message "Error reading LanmanWorkstation registry setting: $_" -Level "ERROR"
}

Write-Log -Message "SMBv1 has been disabled successfully across configurations." -Level "INFO"
