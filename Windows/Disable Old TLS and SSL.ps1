<#
.SYNOPSIS
    Disables deprecated SSL and TLS protocols on a Windows system by updating registry settings.

.DESCRIPTION
    This script enforces strong cryptography by:
      1. Enabling strong cryptographic algorithms in the .NET Framework by setting the 
         "SchUseStrongCrypto" registry key.
      2. Disabling deprecated protocols (SSL 2.0, SSL 3.0, TLS 1.0, and TLS 1.1) for both
         client and server sides by updating the "DisabledByDefault" registry values.
         
    **Important:**  
      - This script must be run with Administrator privileges.  
      - A reboot may be required for all changes to take full effect.
      
.EXAMPLE
    PS C:\> .\DisableDeprecatedProtocols.ps1
    This command updates registry settings to disable SSL 2.0, SSL 3.0, TLS 1.0, and TLS 1.1, 
    and enables strong cryptography in the .NET Framework.

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
        Writes a message with a timestamp and a specified severity level.
    
    .PARAMETER Message
        The text of the log message.
    
    .PARAMETER Level
        The severity level (e.g., "INFO", "ERROR"). Defaults to "INFO".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

#----------------------------------------------
# 1. Enable Strong Cryptography in the .NET Framework
#----------------------------------------------
# Registry path for .NET Framework version 4.0.30319
$registryPath = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
$propertyName = "SchUseStrongCrypto"

Write-Log -Message "Configuring strong cryptography in .NET Framework..."

try {
    # Check if the registry key exists; if not, create it.
    if (-not (Test-Path -Path $registryPath)) {
        Write-Log -Message "Registry path '$registryPath' not found. Creating it..." -Level "INFO"
        New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
        Write-Log -Message "Registry key created at '$registryPath'." -Level "INFO"
    } else {
        Write-Log -Message "Registry path '$registryPath' exists." -Level "INFO"
    }

    # Set the SchUseStrongCrypto property to enable strong cryptography.
    Set-ItemProperty -Path $registryPath -Name $propertyName -Value 1 -ErrorAction Stop
    Write-Log -Message "Set '$propertyName' to 1 successfully in '$registryPath'." -Level "INFO"
} catch {
    Write-Log -Message "Error configuring .NET cryptography: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 2. Disable Deprecated Protocols (SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1)
#----------------------------------------------
$protocols = @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1")
$baseRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"

Write-Log -Message "Disabling deprecated protocols: $($protocols -join ', ')..."

foreach ($protocol in $protocols) {
    foreach ($role in @("Client", "Server")) {
        $fullPath = "$baseRegPath\$protocol\$role"
        try {
            # Ensure the protocol registry path exists. If not, create it.
            if (-not (Test-Path -Path $fullPath)) {
                Write-Log -Message "Registry path '$fullPath' not found. Creating it..." -Level "INFO"
                New-Item -Path $fullPath -Force -ErrorAction Stop | Out-Null
            }

            # Set the "DisabledByDefault" property to 1 to disable the protocol.
            Set-ItemProperty -Path $fullPath -Name "DisabledByDefault" -Value 1 -Force -ErrorAction Stop
            Write-Log -Message "Set 'DisabledByDefault' to 1 at '$fullPath'." -Level "INFO"
        } catch {
            Write-Log -Message "Error setting 'DisabledByDefault' for '$fullPath': $_" -Level "ERROR"
        }
    }
}

#----------------------------------------------
# 3. Verify Configuration
#----------------------------------------------
Write-Log -Message "Verifying configuration for strong cryptography and disabled protocols..."

try {
    $netConfig = Get-ItemProperty -Path $registryPath -Name $propertyName -ErrorAction Stop
    Write-Log -Message "Verification: '$propertyName' is set to $($netConfig.$propertyName) in '$registryPath'."
} catch {
    Write-Log -Message "Error reading registry value at '$registryPath': $_" -Level "ERROR"
}

foreach ($protocol in $protocols) {
    foreach ($role in @("Client", "Server")) {
        $fullPath = "$baseRegPath\$protocol\$role"
        try {
            $protoConfig = Get-ItemProperty -Path $fullPath -Name "DisabledByDefault" -ErrorAction Stop
            Write-Log -Message "Verification: '$protocol' ($role) 'DisabledByDefault' = $($protoConfig.DisabledByDefault) at '$fullPath'."
        } catch {
            Write-Log -Message "Error reading '$fullPath': $_" -Level "ERROR"
        }
    }
}

Write-Log -Message "Deprecated protocols have been disabled and strong cryptography enabled." -Level "INFO"
