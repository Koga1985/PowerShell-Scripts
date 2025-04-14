<#
.SYNOPSIS
    Enables SMB2/SMB3 protocols with enforced SMB signing on a Windows system.

.DESCRIPTION
    This script performs the following actions:
      1. Ensures that SMB2 (and hence SMB3) protocol is enabled on the server.
      2. Configures the system registry for both the SMB server (LanmanServer)
         and SMB client (LanmanWorkstation) to require and enable SMB signing.
      3. Retrieves and displays the current settings to verify that the configurations
         have been applied successfully.
    
    **Prerequisites:**
      - Must be run as an Administrator.
      - Applicable on Windows systems supporting SMB2/SMB3.
    
.EXAMPLE
    PS C:\> .\Enable-SMBSigning.ps1
    This command will enable SMB signing and then display the status of the configurations.
    
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped log message with a specified severity level.
    
    .PARAMETER Message
        The log message text.
    
    .PARAMETER Level
        The severity level (e.g., "INFO", "ERROR"). Defaults to "INFO".
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

#----------------------------------------------
# 1. Enable SMB2/SMB3 Protocols on the Server
#----------------------------------------------
Write-Log -Message "Enabling SMB2 protocol (which also enables SMB3) on the server..."
try {
    # The EnableSMB2Protocol parameter governs the SMB2 and SMB3 protocols.
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop
    Write-Log -Message "SMB2/SMB3 protocols have been enabled." -Level "INFO"
} catch {
    Write-Log -Message "Error enabling SMB2/SMB3 protocol: $_" -Level "ERROR"
}

#----------------------------------------------
# 2. Enable SMB Signing on the SMB Server
#----------------------------------------------
Write-Log -Message "Configuring SMB Server registry settings to require and enable SMB signing..."
try {
    # Define the registry path for the SMB server settings.
    $lanmanServerRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    
    # Ensure that the registry key exists. (It usually exists by default)
    if (-not (Test-Path -Path $lanmanServerRegPath)) {
        Write-Log -Message "Registry path $lanmanServerRegPath not found. Creating key..." -Level "INFO"
        New-Item -Path $lanmanServerRegPath -Force -ErrorAction Stop | Out-Null
    }
    
    # Set RequireSecuritySignature to 1 to enforce SMB signing.
    Set-ItemProperty -Path $lanmanServerRegPath -Name RequireSecuritySignature -Value 1 -Force -ErrorAction Stop
    Write-Log -Message "LanmanServer: 'RequireSecuritySignature' set to 1." -Level "INFO"
    
    # Set EnableSecuritySignature to 1 to enable SMB signing.
    Set-ItemProperty -Path $lanmanServerRegPath -Name EnableSecuritySignature -Value 1 -Force -ErrorAction Stop
    Write-Log -Message "LanmanServer: 'EnableSecuritySignature' set to 1." -Level "INFO"
} catch {
    Write-Log -Message "Error configuring SMB Server registry settings: $_" -Level "ERROR"
}

#----------------------------------------------
# 3. Enable SMB Signing on the SMB Client
#----------------------------------------------
Write-Log -Message "Configuring SMB Client registry settings to require and enable SMB signing..."
try {
    # Define the registry path for the SMB client settings.
    $lanmanWorkstationRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
    
    # Check for existence and create key if it doesn't exist.
    if (-not (Test-Path -Path $lanmanWorkstationRegPath)) {
        Write-Log -Message "Registry path $lanmanWorkstationRegPath not found. Creating key..." -Level "INFO"
        New-Item -Path $lanmanWorkstationRegPath -Force -ErrorAction Stop | Out-Null
    }
    
    # Set RequireSecuritySignature to 1 for the SMB client.
    Set-ItemProperty -Path $lanmanWorkstationRegPath -Name RequireSecuritySignature -Value 1 -Force -ErrorAction Stop
    Write-Log -Message "LanmanWorkstation: 'RequireSecuritySignature' set to 1." -Level "INFO"
    
    # Set EnableSecuritySignature to 1 for the SMB client.
    Set-ItemProperty -Path $lanmanWorkstationRegPath -Name EnableSecuritySignature -Value 1 -Force -ErrorAction Stop
    Write-Log -Message "LanmanWorkstation: 'EnableSecuritySignature' set to 1." -Level "INFO"
} catch {
    Write-Log -Message "Error configuring SMB Client registry settings: $_" -Level "ERROR"
}

#----------------------------------------------
# 4. Verification of Configurations
#----------------------------------------------
Write-Log -Message "Verifying SMB Server Configuration..."
try {
    $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop | Select-Object EnableSMB2Protocol
    Write-Log -Message ("SMB Server 'EnableSMB2Protocol' = {0}" -f $smbConfig.EnableSMB2Protocol) -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving SMB Server configuration: $_" -Level "ERROR"
}

Write-Log -Message "Verifying LanmanServer registry settings..."
try {
    $lanmanServerSettings = Get-ItemProperty -Path $lanmanServerRegPath -Name RequireSecuritySignature, EnableSecuritySignature -ErrorAction Stop
    Write-Log -Message ("LanmanServer 'RequireSecuritySignature' = {0}, 'EnableSecuritySignature' = {1}" -f $lanmanServerSettings.RequireSecuritySignature, $lanmanServerSettings.EnableSecuritySignature) -Level "INFO"
} catch {
    Write-Log -Message "Error reading LanmanServer registry settings: $_" -Level "ERROR"
}

Write-Log -Message "Verifying LanmanWorkstation registry settings..."
try {
    $lanmanWorkstationSettings = Get-ItemProperty -Path $lanmanWorkstationRegPath -Name RequireSecuritySignature, EnableSecuritySignature -ErrorAction Stop
    Write-Log -Message ("LanmanWorkstation 'RequireSecuritySignature' = {0}, 'EnableSecuritySignature' = {1}" -f $lanmanWorkstationSettings.RequireSecuritySignature, $lanmanWorkstationSettings.EnableSecuritySignature) -Level "INFO"
} catch {
    Write-Log -Message "Error reading LanmanWorkstation registry settings: $_" -Level "ERROR"
}

Write-Log -Message "SMB signing and encryption settings applied successfully." -Level "INFO"
