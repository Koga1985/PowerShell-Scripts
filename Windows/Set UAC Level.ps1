<#
.SYNOPSIS
    Reads and sets UAC settings via registry modifications.

.DESCRIPTION
    This module provides two main functions:
      - Get-UACLevel: Reads the UAC settings (ConsentPromptBehaviorAdmin and PromptOnSecureDesktop)
                      from the registry and returns a descriptive string for the UAC level.
      - Set-UACLevel: Configures UAC by setting registry keys based on a specified numeric level (0, 1, 2, or 3).
      
    The functions use SupportsShouldProcess so they can be safely previewed before making changes.
    
.PARAMETER Level (for Set-UACLevel)
    Numeric UAC level (0, 1, 2, or 3) corresponding to the desired UAC behavior.
    
.EXAMPLE
    # To see the current UAC configuration:
    Get-UACLevel

    # To set the UAC level to 2 (Notify me only when apps try to make changes – default):
    Set-UACLevel -Level 2

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
# Global Variables for Registry Paths and Value Names
#----------------------------------------------
$global:UACRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$global:ConsentPromptBehaviorAdmin_Name = "ConsentPromptBehaviorAdmin"
$global:PromptOnSecureDesktop_Name = "PromptOnSecureDesktop"

#----------------------------------------------
# Function: Set-RegistryValue
#----------------------------------------------
function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    Param (
        [Parameter(Mandatory=$true)]
        [string]$Key,
        
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [Object]$Value,
        
        [string]$Type = "Dword"
    )
    try {
        # Ensure the registry key exists; create it if not.
        if (-not (Test-Path -Path $Key)) {
            Write-Log -Message "Registry key '$Key' not found. Creating it." -Level "INFO"
            New-Item -Path $Key -Force -ErrorAction Stop | Out-Null
        }
        # Use ShouldProcess for safe operations
        if ($PSCmdlet.ShouldProcess("$Key\$Name", "Set registry value to $Value")) {
            Set-ItemProperty -Path $Key -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            Write-Log -Message "Successfully set '$Name' to '$Value' in '$Key'." -Level "INFO"
        }
    } catch {
        Write-Log -Message "Error setting registry value '$Name' in '$Key': $_" -Level "ERROR"
    }
}

#----------------------------------------------
# Function: Get-RegistryValue
#----------------------------------------------
function Get-RegistryValue {
    Param (
        [Parameter(Mandatory=$true)]
        [string]$Key,
        
        [Parameter(Mandatory=$true)]
        [string]$Value
    )
    try {
        $result = (Get-ItemProperty -Path $Key -Name $Value -ErrorAction Stop).$Value
        Write-Log -Message "Retrieved value '$Value': $result from '$Key'." -Level "INFO"
        return $result
    } catch {
        Write-Log -Message "Error reading registry value '$Value' from '$Key': $_" -Level "ERROR"
        return $null
    }
}

#----------------------------------------------
# Function: Get-UACLevel
#----------------------------------------------
function Get-UACLevel {
    <#
    .SYNOPSIS
        Reads the current UAC settings and returns a descriptive string.
        
    .DESCRIPTION
        This function retrieves the registry values for ConsentPromptBehaviorAdmin and PromptOnSecureDesktop
        from the system policies and returns a description corresponding to the UAC level.
        
          - If ConsentPromptBehaviorAdmin = 0 and PromptOnSecureDesktop = 0 => "Never Notify"
          - If ConsentPromptBehaviorAdmin = 5 and PromptOnSecureDesktop = 0 => "Notify me only when apps try to make changes (do not dim desktop)"
          - If ConsentPromptBehaviorAdmin = 5 and PromptOnSecureDesktop = 1 => "Notify me only when apps try to make changes (default)"
          - If ConsentPromptBehaviorAdmin = 2 and PromptOnSecureDesktop = 1 => "Always Notify"
          - Else => "Unknown"
    #>
    $consentValue = Get-RegistryValue -Key $global:UACRegistryPath -Value $global:ConsentPromptBehaviorAdmin_Name
    $desktopValue = Get-RegistryValue -Key $global:UACRegistryPath -Value $global:PromptOnSecureDesktop_Name

    if (($consentValue -eq 0) -and ($desktopValue -eq 0)) {
        return "Never Notify"
    } elseif (($consentValue -eq 5) -and ($desktopValue -eq 0)) {
        return "Notify me only when apps try to make changes (do not dim desktop)"
    } elseif (($consentValue -eq 5) -and ($desktopValue -eq 1)) {
        return "Notify me only when apps try to make changes (default)"
    } elseif (($consentValue -eq 2) -and ($desktopValue -eq 1)) {
        return "Always Notify"
    } else {
        return "Unknown"
    }
}

#----------------------------------------------
# Function: Set-UACLevel
#----------------------------------------------
function Set-UACLevel {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("0", "1", "2", "3")]
        [int]$Level
    )
    
    # Determine the registry values based on the UAC level
    switch ($Level) {
        0 {
            $consentValue = 0
            $desktopValue = 0
        }
        1 {
            $consentValue = 5
            $desktopValue = 0
        }
        2 {
            $consentValue = 5
            $desktopValue = 1
        }
        3 {
            $consentValue = 2
            $desktopValue = 1
        }
    }
    
    # Log the intended changes
    if ($PSCmdlet.ShouldProcess("UAC Level $Level", "Set ConsentPromptBehaviorAdmin = $consentValue and PromptOnSecureDesktop = $desktopValue")) {
        Set-RegistryValue -Key $global:UACRegistryPath -Name $global:ConsentPromptBehaviorAdmin_Name -Value $consentValue
        Set-RegistryValue -Key $global:UACRegistryPath -Name $global:PromptOnSecureDesktop_Name -Value $desktopValue
    }
    
    # Return the current UAC level description
    $currentLevel = Get-UACLevel
    Write-Log -Message "Current UAC configuration: $currentLevel" -Level "INFO"
    return $currentLevel
}

#----------------------------------------------
# Export Module Members
#----------------------------------------------
Export-ModuleMember -Function Get-UACLevel, Set-UACLevel

# Optional: Output current UAC level if script is run interactively
Write-Log -Message "Current UAC Level: $(Get-UACLevel)" -Level "INFO"
