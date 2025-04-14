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

    **Note:** This script must be run with administrator privileges.

.EXAMPLE
    PS C:\> .\DisableCortana.ps1
    The script will modify the registry and restart Explorer to disable Cortana.

.NOTES
    Author: Your Name or Organization
    Date: 2025-04-14
    Version: 1.0
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to the host with a timestamp and specified log level.
    
    .PARAMETER Message
        The log message text.
    
    .PARAMETER Level
        The severity level (e.g., INFO, ERROR). Default value is INFO.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

#----------------------------------------------
# 1. Define the Registry Path for Windows Search Policies
#----------------------------------------------
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
Write-Log -Message "Using registry path: $registryPath"

#----------------------------------------------
# 2. Ensure the Registry Key Exists
#----------------------------------------------
Write-Log -Message "Checking if registry key exists..."
try {
    if (-not (Test-Path -Path $registryPath)) {
        Write-Log -Message "Registry key not found. Creating key..." -Level "INFO"
        New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
        Write-Log -Message "Registry key created successfully." -Level "INFO"
    } else {
        Write-Log -Message "Registry key already exists." -Level "INFO"
    }
} catch {
    Write-Log -Message "Error creating registry key: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 3. Disable Cortana by Setting the AllowCortana Value
#----------------------------------------------
Write-Log -Message "Setting 'AllowCortana' registry value to 0 to disable Cortana..."
try {
    Set-ItemProperty -Path $registryPath -Name "AllowCortana" -Value 0 -ErrorAction Stop
    Write-Log -Message "'AllowCortana' value set to 0 successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error setting 'AllowCortana' value: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 4. Restart Windows Explorer to Apply Changes
#----------------------------------------------
Write-Log -Message "Restarting Windows Explorer to apply changes..."
try {
    # Stop Explorer process
    Stop-Process -Name explorer -Force -ErrorAction Stop
    # Start Explorer process
    Start-Process explorer -ErrorAction Stop
    Write-Log -Message "Windows Explorer restarted successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error restarting Windows Explorer: $_" -Level "ERROR"
    exit
}

Write-Log -Message "Cortana has been disabled successfully. Please log off or reboot for all changes to take effect." -Level "INFO"
