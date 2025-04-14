<#
.SYNOPSIS
    Installs and configures Microsoft Exchange Server 2016 with basic settings and a self-contained deployment process.

.DESCRIPTION
    This script downloads the Exchange Server 2016 ISO, mounts it, and promotes the server to a Domain Controller by installing 
    Exchange Server in "Install" mode (fresh installation). It then configures the Transport Rule Agent for Exchange.
    
    The script performs the following steps:
      1. Define and validate parameters and variables.
      2. Create a designated folder for Exchange setup files.
      3. Download the Exchange Server 2016 ISO from Microsoft.
      4. Mount the ISO and retrieve the associated drive letter.
      5. Execute Exchange Setup with specified parameters.
      6. Configure Exchange by installing and enabling the Transport Rule Agent.
      
    **Note:**
      - Ensure that Windows Server is pre-configured with a static IP address, has joined the domain, and that all 
        prerequisites for Exchange Server 2016 are met.
      - The Exchange installation process may require additional post-installation configuration (e.g., certificates,
        accepted domains, etc.) based on your environment.
      
.PARAMETER domainName
    The fully qualified domain name for the Exchange organization (for informational purposes).

.PARAMETER organizationName
    The name of your organization (used during Exchange setup).

.PARAMETER exchangeIsoUrl
    URL from where to download the Exchange Server 2016 ISO.

.PARAMETER exchangeSetupFolder
    The local directory where the Exchange ISO will be downloaded and mounted.

.PARAMETER installationMode
    The installation mode for Exchange Setup. Default is "Install" (fresh installation).

.PARAMETER additionalSetupArgs
    Additional command-line arguments to pass to the Exchange Setup executable if needed.

.EXAMPLE
    .\Install-Exchange2016.ps1 -domainName "yourdomain.local" -organizationName "YourOrganization" `
        -exchangeIsoUrl "https://download.microsoft.com/download/2/3/5/2358F155-51DA-4D3A-BB23-C73A8684CD25/ExchangeServer2016-x64-CU20.iso" `
        -exchangeSetupFolder "C:\Exchange\Setup" -installationMode "Install"
        
.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
    Prerequisites:
        - Must be run as Administrator.
        - Windows Server must be prepared with required roles/features, static IP, and domain membership.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$domainName,
    
    [Parameter(Mandatory = $true)]
    [string]$organizationName,
    
    [Parameter(Mandatory = $true)]
    [string]$exchangeIsoUrl,
    
    [Parameter(Mandatory = $true)]
    [string]$exchangeSetupFolder,
    
    [Parameter(Mandatory = $false)]
    [string]$installationMode = "Install",
    
    [Parameter(Mandatory = $false)]
    [string]$additionalSetupArgs = "/InstallWindowsComponents"
)

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a standardized log message with a timestamp and severity level.
    
    .PARAMETER Message
        The log message text.
    
    .PARAMETER Level
        The severity level (e.g., "INFO", "ERROR"). Defaults to "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

Write-Log -Message "Starting Exchange Server 2016 installation and configuration." -Level "INFO"

#----------------------------------------------
# 1. Prepare the Exchange Setup Directory
#----------------------------------------------
Write-Log -Message "Creating/ensuring the Exchange setup folder exists at: $exchangeSetupFolder" -Level "INFO"
try {
    New-Item -ItemType Directory -Path $exchangeSetupFolder -Force -ErrorAction Stop | Out-Null
    Write-Log -Message "Exchange setup folder is ready." -Level "INFO"
} catch {
    Write-Log -Message "Error creating setup folder: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 2. Download the Exchange Server 2016 ISO
#----------------------------------------------
$isoPath = Join-Path -Path $exchangeSetupFolder -ChildPath "ExchangeServer2016.iso"
Write-Log -Message "Downloading Exchange Server 2016 ISO from $exchangeIsoUrl to $isoPath" -Level "INFO"
try {
    Invoke-WebRequest -Uri $exchangeIsoUrl -OutFile $isoPath -ErrorAction Stop
    Write-Log -Message "ISO downloaded successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error downloading ISO: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 3. Mount the Exchange Server 2016 ISO and Retrieve Drive Letter
#----------------------------------------------
Write-Log -Message "Mounting the ISO image..." -Level "INFO"
try {
    # Mount the ISO; the -PassThru parameter returns the disk image object
    $mountedImage = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    
    # Wait a few seconds for the image to mount and volumes to become available.
    Start-Sleep -Seconds 5
    
    # Retrieve the drive letter of the mounted ISO. Use Get-DiskImage and Get-Volume.
    $driveLetter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter
    if (-not $driveLetter) {
        Write-Log -Message "Failed to retrieve drive letter for mounted ISO." -Level "ERROR"
        exit
    }
    Write-Log -Message "ISO mounted successfully. Drive letter: $driveLetter" -Level "INFO"
    
    # Update the ExchangeSetupPath to point to the root of the mounted ISO.
    $exchangeSetupPath = "$driveLetter`:"
    Write-Log -Message "Updated Exchange setup path: $exchangeSetupPath" -Level "INFO"
} catch {
    Write-Log -Message "Error mounting ISO: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 4. Install Exchange Server 2016
#----------------------------------------------
# Build the command-line arguments for the Exchange Setup
$setupExe = Join-Path -Path $exchangeSetupPath -ChildPath "Setup.exe"
$setupArgs = "/Mode:$installationMode /OrganizationName:`"$organizationName`" $additionalSetupArgs /IAcceptExchangeServerLicenseTerms"
Write-Log -Message "Starting Exchange Server installation with command: `"$setupExe $setupArgs`"" -Level "INFO"
try {
    # Execute the setup; the call operator (&) is used to run the executable.
    & $setupExe $setupArgs
    Write-Log -Message "Exchange Server installation initiated. Follow the on-screen instructions." -Level "INFO"
} catch {
    Write-Log -Message "Error during Exchange Server installation: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 5. Post-Installation: Configure Exchange (Transport Agent)
#----------------------------------------------
# Note: Additional configuration steps may be required based on environment needs.
Write-Log -Message "Configuring Exchange Server transport agent..." -Level "INFO"
try {
    # Retrieve the assembly path for the Transport Rule Agent from the Hub transport service.
    $transportAgent = Get-TransportAgent -TransportService Hub | Where-Object {$_.Name -eq "Transport Rule Agent"}
    if ($transportAgent) {
        Install-TransportAgent -Name "Transport Rule Agent" -TransportAgentFactory "Microsoft.Exchange.MessagingPolicies.RulesTransportAgent.RulesTransportAgentFactory" -AssemblyPath $transportAgent.AssemblyPath -ErrorAction Stop
        Enable-TransportRuleAgent -Identity "Transport Rule Agent" -ErrorAction Stop
        Write-Log -Message "Exchange Transport Rule Agent configured successfully." -Level "INFO"
    } else {
        Write-Log -Message "Transport Rule Agent not found; skipping transport agent configuration." -Level "WARNING"
    }
} catch {
    Write-Log -Message "Error configuring Exchange transport agent: $_" -Level "ERROR"
}

#----------------------------------------------
# 6. Final Notification
#----------------------------------------------
Write-Log -Message "Exchange Server installation and basic configuration completed." -Level "INFO"
Write-Log -Message "Note: Additional configurations (certificates, accepted domains, etc.) may be required based on your environment." -Level "INFO"
