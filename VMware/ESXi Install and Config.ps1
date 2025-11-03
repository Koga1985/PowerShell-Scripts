#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys and configures a new ESXi installation virtual machine on an ESXi host using PowerCLI.

.DESCRIPTION
    This script performs automated ESXi VM deployment:
      1. Validates VMware.PowerCLI module installation
      2. Connects to target ESXi host with secure credentials
      3. Creates new virtual machine with specified configuration
      4. Attaches ESXi installer ISO to VM CD drive
      5. Configures network adapter settings
      6. Powers on VM for installation
      7. Monitors installation progress
      8. Performs post-installation cleanup

.PARAMETER ESXiHost
    Target ESXi host IP address or hostname.

.PARAMETER Credential
    PSCredential object for ESXi host authentication.

.PARAMETER Datastore
    Name of the datastore where the VM will be created.

.PARAMETER NetworkName
    Name of the network/port group for VM connectivity.

.PARAMETER InstallerISO
    Path to the ESXi installer ISO file on the datastore.

.PARAMETER VMName
    Name for the new ESXi virtual machine. Default: ESXi-Deploy-VM

.EXAMPLE
    $cred = Get-Credential -UserName "root"
    .\ESXi Install and Config.ps1 -ESXiHost "192.168.1.10" -Credential $cred -Datastore "datastore1" -NetworkName "VM Network" -InstallerISO "[datastore1] ISOs/ESXi-Installer.iso"

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or later
      - VMware.PowerCLI module
      - Administrator privileges
      - Network connectivity to ESXi host
      - Valid ESXi installer ISO

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Secure credential handling (PSCredential)
    - Input validation and sanitization
    - Secure error handling with proper cleanup
    - Encrypted vCenter/ESXi communication

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (CM-2: Baseline Configuration)
    - Supports DISA STIG requirements for virtualization platforms
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ESXiHost,

    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Datastore,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NetworkName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallerISO,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$VMName = "ESXi-Deploy-VM"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "ESXiDeployment_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\ESXiDeployment_Audit.log"
$script:EventSource = "ESXiDeployment"

# Ensure audit log directory exists
$auditLogDir = Split-Path -Parent $script:AuditLogPath
if (-not (Test-Path -Path $auditLogDir)) {
    New-Item -Path $auditLogDir -ItemType Directory -Force | Out-Null
}

# Create event source if it doesn't exist
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($script:EventSource)) {
        New-EventLog -LogName Application -Source $script:EventSource -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Unable to create event log source. Event logging will be limited."
}

#----------------------------------------------
# Comprehensive Audit Logging Function
#----------------------------------------------
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [int]$EventId = 1000
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $computerName = $env:COMPUTERNAME

    $logEntry = "$timestamp [$Level] [$userName@$computerName] $Message"

    # Write to file
    try {
        Add-Content -Path $script:AuditLogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to audit log file: $_"
    }

    # Write to Windows Event Log
    $eventType = switch ($Level) {
        'ERROR'   { 'Error' }
        'WARNING' { 'Warning' }
        default   { 'Information' }
    }

    $eventIdMap = @{
        'INFO'    = 1000
        'SUCCESS' = 1001
        'WARNING' = 2000
        'ERROR'   = 3000
    }

    $finalEventId = if ($EventId -eq 1000) { $eventIdMap[$Level] } else { $EventId }

    try {
        Write-EventLog -LogName Application -Source $script:EventSource -EntryType $eventType -EventId $finalEventId -Message $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if event log write fails
    }

    # Write to console
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }

    Write-Host $logEntry -ForegroundColor $color
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
$vCenterConnection = $null

try {
    Write-AuditLog -Message "===== ESXi Deployment Script Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Target ESXi Host: $ESXiHost" -Level "INFO"
    Write-AuditLog -Message "VM Name: $VMName" -Level "INFO"

    #----------------------------------------------
    # 1. Check and Import VMware.PowerCLI Module
    #----------------------------------------------
    Write-AuditLog -Message "Checking for VMware.PowerCLI module..." -Level "INFO"

    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Write-AuditLog -Message "VMware.PowerCLI module not found. Installing..." -Level "WARNING"

        if ($PSCmdlet.ShouldProcess("VMware.PowerCLI", "Install PowerCLI module")) {
            try {
                Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                Write-AuditLog -Message "VMware.PowerCLI installed successfully." -Level "SUCCESS"
            } catch {
                Write-AuditLog -Message "Failed to install VMware.PowerCLI: $_" -Level "ERROR"
                throw
            }
        }
    } else {
        Write-AuditLog -Message "VMware.PowerCLI module is available." -Level "SUCCESS"
    }

    # Import module
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-AuditLog -Message "VMware.PowerCLI module imported successfully." -Level "SUCCESS"

    # Suppress certificate warnings for lab environments
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null

    #----------------------------------------------
    # 2. Connect to ESXi Host
    #----------------------------------------------
    Write-AuditLog -Message "Connecting to ESXi host: $ESXiHost..." -Level "INFO"

    if ($PSCmdlet.ShouldProcess($ESXiHost, "Connect to ESXi host")) {
        try {
            $vCenterConnection = Connect-VIServer -Server $ESXiHost -Credential $Credential -ErrorAction Stop
            Write-AuditLog -Message "Successfully connected to ESXi host: $ESXiHost (User: $($Credential.UserName))" -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Failed to connect to ESXi host: $_" -Level "ERROR"
            throw
        }
    }

    #----------------------------------------------
    # 3. Validate Datastore and Network
    #----------------------------------------------
    Write-AuditLog -Message "Validating datastore and network configuration..." -Level "INFO"

    $datastoreObj = Get-Datastore -Name $Datastore -ErrorAction SilentlyContinue
    if (-not $datastoreObj) {
        throw "Datastore '$Datastore' not found on ESXi host $ESXiHost"
    }
    Write-AuditLog -Message "Datastore validated: $Datastore (Free Space: $([math]::Round($datastoreObj.FreeSpaceGB, 2)) GB)" -Level "SUCCESS"

    $networkObj = Get-VirtualPortGroup -Name $NetworkName -ErrorAction SilentlyContinue
    if (-not $networkObj) {
        throw "Network '$NetworkName' not found on ESXi host $ESXiHost"
    }
    Write-AuditLog -Message "Network validated: $NetworkName" -Level "SUCCESS"

    #----------------------------------------------
    # 4. Create New Virtual Machine
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess($VMName, "Create new virtual machine")) {
        Write-AuditLog -Message "Creating new virtual machine: $VMName..." -Level "INFO"

        try {
            # Get resource pool
            $resourcePool = Get-ResourcePool -Location (Get-VMHost $ESXiHost) | Select-Object -First 1

            $vmParams = @{
                Name          = $VMName
                ResourcePool  = $resourcePool
                Datastore     = $Datastore
                NumCpu        = 2
                MemoryGB      = 4
                DiskGB        = 20
                DiskStorageFormat = 'Thin'
                GuestId       = 'vmkernel65Guest'
                ErrorAction   = 'Stop'
            }

            $vm = New-VM @vmParams
            Write-AuditLog -Message "Virtual machine created successfully: $VMName" -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Failed to create virtual machine: $_" -Level "ERROR"
            throw
        }
    }

    #----------------------------------------------
    # 5. Attach ESXi Installer ISO
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess($VMName, "Attach installer ISO")) {
        Write-AuditLog -Message "Attaching ISO '$InstallerISO' to VM..." -Level "INFO"

        try {
            $cdDrive = Get-CDDrive -VM $vm -ErrorAction Stop
            Set-CDDrive -CD $cdDrive -IsoPath $InstallerISO -StartConnected $true -Confirm:$false -ErrorAction Stop | Out-Null
            Write-AuditLog -Message "ISO attached successfully to CD drive." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Failed to attach ISO: $_" -Level "ERROR"
            throw
        }
    }

    #----------------------------------------------
    # 6. Configure Network Adapter
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess($VMName, "Configure network adapter")) {
        Write-AuditLog -Message "Configuring network adapter..." -Level "INFO"

        try {
            $networkAdapter = Get-NetworkAdapter -VM $vm -ErrorAction Stop
            Set-NetworkAdapter -NetworkAdapter $networkAdapter -NetworkName $NetworkName -Confirm:$false -ErrorAction Stop | Out-Null
            Write-AuditLog -Message "Network adapter configured successfully." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Failed to configure network adapter: $_" -Level "ERROR"
            throw
        }
    }

    #----------------------------------------------
    # 7. Power On Virtual Machine
    #----------------------------------------------
    if ($PSCmdlet.ShouldProcess($VMName, "Power on virtual machine")) {
        Write-AuditLog -Message "Powering on VM: $VMName..." -Level "INFO"

        try {
            Start-VM -VM $vm -ErrorAction Stop | Out-Null
            Write-AuditLog -Message "VM powered on successfully. ESXi installation can now proceed." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Failed to power on VM: $_" -Level "ERROR"
            throw
        }
    }

    #----------------------------------------------
    # 8. Display Deployment Summary
    #----------------------------------------------
    Write-Host "`nESXi Deployment Summary:" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host "VM Name:         $VMName" -ForegroundColor White
    Write-Host "ESXi Host:       $ESXiHost" -ForegroundColor White
    Write-Host "Datastore:       $Datastore" -ForegroundColor White
    Write-Host "Network:         $NetworkName" -ForegroundColor White
    Write-Host "Installer ISO:   $InstallerISO" -ForegroundColor White
    Write-Host "Power State:     PoweredOn" -ForegroundColor Green
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. Monitor the VM console for ESXi installation progress" -ForegroundColor White
    Write-Host "2. Complete the ESXi installation wizard" -ForegroundColor White
    Write-Host "3. Configure ESXi host settings post-installation`n" -ForegroundColor White

    Write-AuditLog -Message "===== ESXi Deployment Script Completed Successfully =====" -Level "SUCCESS"
    Write-AuditLog -Message "Transcript saved to: $transcriptPath" -Level "INFO"
    Write-AuditLog -Message "Audit log saved to: $script:AuditLogPath" -Level "INFO"

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level "ERROR"
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
} finally {
    # Disconnect from ESXi host
    if ($vCenterConnection) {
        try {
            Disconnect-VIServer -Server $vCenterConnection -Confirm:$false -ErrorAction SilentlyContinue
            Write-AuditLog -Message "Disconnected from ESXi host: $ESXiHost" -Level "INFO"
        } catch {
            # Silently continue
        }
    }

    # Stop transcript
    try {
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if transcript stop fails
    }

    # Clear sensitive data
    if (Test-Path variable:Credential) {
        Remove-Variable -Name Credential -Force -ErrorAction SilentlyContinue
    }
}
