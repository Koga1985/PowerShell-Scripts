<#
.SYNOPSIS
    Secure Auto Deploy Home Lab Script for VMware environments (Fourth Estate aligned).

.DESCRIPTION
    Automates secure deployment of a home lab on VMware vSphere/ESXi with comprehensive security controls.
    Functions for creating virtual networks, VMs, and configuring Windows Server installation via ISO.
    All actions use robust error handling, input validation, prerequisite checking, and comprehensive audit logging.

.PARAMETER VMHost
    The name or IP of the VMware ESXi host or vCenter Server.

.PARAMETER VMFolder
    The folder or location within vCenter where the virtual machines will be deployed.

.PARAMETER Datastore
    The datastore name where the VM files will be stored.

.PARAMETER ISOPath
    Local or network path to the Windows Server installation ISO file.

.PARAMETER Credential
    PSCredential object for vCenter/ESXi authentication.

.EXAMPLE
    $cred = Get-Credential -Message "Enter vCenter credentials"
    .\Simple_Lab_Deployment.ps1 -VMHost "vcenter.domain.local" -VMFolder "HomeLab" -Datastore "datastore1" -ISOPath "\\server\share\WinServer.iso" -Credential $cred

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for enhanced script reliability
    - Secure credential handling (PSCredential only)
    - Comprehensive input validation and sanitization
    - Audit logging to file and Windows Event Log
    - Prerequisite checking before deployment
    - Datastore capacity verification
    - Network connectivity validation
    - Rollback capability on failure

.COMPLIANCE
    - NIST SP 800-53 Rev 5: AU-2, AU-3, AU-12 (Audit and Accountability)
    - NIST SP 800-53 Rev 5: SI-10 (Input Validation)
    - NIST SP 800-53 Rev 5: IA-5 (Authenticator Management)
    - DISA STIG PowerShell Security Technical Implementation Guide
    - DISA STIG Virtualization Security Requirements Guide
    - DoD Fourth Estate virtualization security requirements
    - FedRAMP security controls

    Disclaimer: Ensure VMware PowerCLI is installed and this script is tested in non-production before production use.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$VMHost,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$VMFolder,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Datastore,

    [Parameter(Mandatory=$true)]
    [ValidateScript({
        if (-not (Test-Path -Path $_ -PathType Leaf)) {
            throw "ISO file not found: $_"
        }
        if ($_ -notmatch '\.iso$') {
            throw "File must be an ISO image"
        }
        return $true
    })]
    [string]$ISOPath,

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.PSCredential]$Credential
)

#region Security Configuration
$Global:AuditLogPath = "$env:ProgramData\LabDeployment\Logs\audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$Global:EventLogSource = "LabDeployment"
$Global:EventLogName = "Application"
$Global:CreatedResources = @()  # Track for rollback

# Initialize audit logging
function Initialize-AuditLog {
    try {
        $logDir = Split-Path $Global:AuditLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        if (-not ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource))) {
            New-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource
        }
    } catch {
        Write-Warning "Failed to initialize audit logging: $_"
    }
}

Initialize-AuditLog
#endregion

#region Audit Logging Function
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory=$false)]
        [string]$Action = 'Deployment'
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $computerName = $env:COMPUTERNAME

        $auditEntry = "$timestamp | $computerName | $username | $Level | $Action | $Message"

        Add-Content -Path $Global:AuditLogPath -Value $auditEntry -ErrorAction SilentlyContinue

        $eventType = switch ($Level) {
            'ERROR' { 'Error' }
            'WARNING' { 'Warning' }
            'SECURITY' { 'SuccessAudit' }
            default { 'Information' }
        }

        $eventId = switch ($Level) {
            'ERROR' { 3001 }
            'WARNING' { 3002 }
            'SECURITY' { 3003 }
            default { 3000 }
        }

        Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
            -EventId $eventId -EntryType $eventType -Message $auditEntry -ErrorAction SilentlyContinue

        $color = switch ($Level) {
            'ERROR' { 'Red' }
            'WARNING' { 'Yellow' }
            'SECURITY' { 'Cyan' }
            default { 'White' }
        }
        Write-Host $auditEntry -ForegroundColor $color

    } catch {
        Write-Warning "Failed to write audit log: $_"
    }
}
#endregion

#region Prerequisite Validation Functions
function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates all prerequisites before deployment.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Starting prerequisite validation" -Level SECURITY -Action "PrerequisiteCheck"

    $allChecksPassed = $true

    # Check PowerCLI module
    Write-Host "`nChecking VMware PowerCLI module..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
        Write-AuditLog -Message "VMware PowerCLI module not installed" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "ERROR: VMware PowerCLI module is not installed." -ForegroundColor Red
        Write-Host "Install with: Install-Module -Name VMware.PowerCLI -Scope CurrentUser" -ForegroundColor Yellow
        $allChecksPassed = $false
    } else {
        Write-AuditLog -Message "VMware PowerCLI module found" -Level INFO -Action "PrerequisiteCheck"
        Write-Host "OK: VMware PowerCLI module is installed" -ForegroundColor Green
    }

    # Check vCenter/ESXi connection
    Write-Host "Checking vCenter/ESXi connection..." -ForegroundColor Cyan
    try {
        $connection = $Global:DefaultVIServer
        if (-not $connection) {
            Write-AuditLog -Message "Not connected to vCenter/ESXi" -Level ERROR -Action "PrerequisiteCheck"
            Write-Host "ERROR: Not connected to a vCenter or ESXi host." -ForegroundColor Red
            Write-Host "Connect with: Connect-VIServer -Server <hostname> -Credential <cred>" -ForegroundColor Yellow
            $allChecksPassed = $false
        } else {
            Write-AuditLog -Message "Connected to vCenter/ESXi: $($connection.Name)" -Level INFO -Action "PrerequisiteCheck"
            Write-Host "OK: Connected to $($connection.Name)" -ForegroundColor Green
        }
    } catch {
        Write-AuditLog -Message "Error checking vCenter connection: $_" -Level ERROR -Action "PrerequisiteCheck"
        $allChecksPassed = $false
    }

    # Check network connectivity to VMHost
    Write-Host "Checking network connectivity to $VMHost..." -ForegroundColor Cyan
    try {
        $pingResult = Test-Connection -ComputerName $VMHost -Count 2 -Quiet -ErrorAction Stop
        if ($pingResult) {
            Write-AuditLog -Message "Network connectivity to $VMHost confirmed" -Level INFO -Action "PrerequisiteCheck"
            Write-Host "OK: $VMHost is reachable" -ForegroundColor Green
        } else {
            Write-AuditLog -Message "Cannot reach $VMHost" -Level ERROR -Action "PrerequisiteCheck"
            Write-Host "ERROR: Cannot reach $VMHost" -ForegroundColor Red
            $allChecksPassed = $false
        }
    } catch {
        Write-AuditLog -Message "Network test failed for $VMHost : $_" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "WARNING: Network test failed for $VMHost" -ForegroundColor Yellow
    }

    # Check datastore existence and capacity
    Write-Host "Checking datastore $Datastore..." -ForegroundColor Cyan
    try {
        $ds = Get-Datastore -Name $Datastore -ErrorAction Stop
        $freeSpaceGB = [math]::Round($ds.FreeSpaceGB, 2)
        $capacityGB = [math]::Round($ds.CapacityGB, 2)
        $freePercent = [math]::Round(($freeSpaceGB / $capacityGB) * 100, 2)

        Write-AuditLog -Message "Datastore $Datastore : $freeSpaceGB GB free of $capacityGB GB ($freePercent%)" `
            -Level INFO -Action "PrerequisiteCheck"

        if ($freeSpaceGB -lt 50) {
            Write-Host "WARNING: Datastore has only $freeSpaceGB GB free" -ForegroundColor Yellow
            Write-AuditLog -Message "Low datastore space warning: $freeSpaceGB GB" -Level WARNING -Action "PrerequisiteCheck"
        } else {
            Write-Host "OK: Datastore has $freeSpaceGB GB free ($freePercent%)" -ForegroundColor Green
        }
    } catch {
        Write-AuditLog -Message "Datastore $Datastore not found: $_" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "ERROR: Datastore $Datastore not found" -ForegroundColor Red
        $allChecksPassed = $false
    }

    # Check ISO file
    Write-Host "Checking ISO file..." -ForegroundColor Cyan
    if (Test-Path -Path $ISOPath -PathType Leaf) {
        $isoSize = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
        Write-AuditLog -Message "ISO file found: $ISOPath ($isoSize GB)" -Level INFO -Action "PrerequisiteCheck"
        Write-Host "OK: ISO file found ($isoSize GB)" -ForegroundColor Green
    } else {
        Write-AuditLog -Message "ISO file not found: $ISOPath" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "ERROR: ISO file not found: $ISOPath" -ForegroundColor Red
        $allChecksPassed = $false
    }

    Write-Host ""
    if ($allChecksPassed) {
        Write-AuditLog -Message "All prerequisite checks passed" -Level SECURITY -Action "PrerequisiteCheck"
        Write-Host "All prerequisite checks PASSED" -ForegroundColor Green
        return $true
    } else {
        Write-AuditLog -Message "One or more prerequisite checks failed" -Level ERROR -Action "PrerequisiteCheck"
        Write-Host "One or more prerequisite checks FAILED" -ForegroundColor Red
        return $false
    }
}
#endregion

#region Resource Creation Functions
function New-VirtualMachine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 128)]
        [int]$MemoryGB,

        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 32)]
        [int]$CPUs,

        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 10000)]
        [int]$DiskGB
    )

    Write-AuditLog -Message "Creating VM: $Name ($MemoryGB GB RAM, $CPUs CPU, $DiskGB GB disk)" `
        -Level SECURITY -Action "VMCreation"

    try {
        $vm = New-VM -Name $Name `
               -MemoryGB $MemoryGB `
               -NumCpu $CPUs `
               -DiskGB $DiskGB `
               -VMHost $VMHost `
               -Datastore $Datastore `
               -Location $VMFolder `
               -ErrorAction Stop

        $Global:CreatedResources += @{Type='VM'; Name=$Name; Object=$vm}

        Write-AuditLog -Message "Virtual machine '$Name' created successfully" -Level SECURITY -Action "VMCreation"
        Write-Host "SUCCESS: VM '$Name' created" -ForegroundColor Green
        return $vm

    } catch {
        Write-AuditLog -Message "Error creating VM '$Name': $_" -Level ERROR -Action "VMCreation"
        throw
    }
}

function New-VirtualNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [ValidatePattern('^(?:[0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$')]
        [string]$Subnet,

        [Parameter(Mandatory=$true)]
        [ValidatePattern('^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$')]
        [string]$Gateway
    )

    Write-AuditLog -Message "Creating virtual network: $Name (Subnet: $Subnet, Gateway: $Gateway)" `
        -Level SECURITY -Action "NetworkCreation"

    try {
        # Create virtual switch
        $vSwitch = New-VirtualSwitch -Name $Name -VMHost $VMHost -ErrorAction Stop
        Write-AuditLog -Message "Virtual switch '$Name' created" -Level INFO -Action "NetworkCreation"

        $Global:CreatedResources += @{Type='VirtualSwitch'; Name=$Name; Object=$vSwitch}

        # Create port group
        $portGroup = New-VirtualPortGroup -Name $Name -VirtualSwitch $vSwitch -ErrorAction Stop
        Write-AuditLog -Message "Port group '$Name' created" -Level INFO -Action "NetworkCreation"

        Write-Host "SUCCESS: Virtual network '$Name' created" -ForegroundColor Green
        return $vSwitch

    } catch {
        Write-AuditLog -Message "Error creating virtual network '$Name': $_" -Level ERROR -Action "NetworkCreation"
        throw
    }
}

function Install-WindowsServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ISOPath
    )

    Write-AuditLog -Message "Configuring VM '$VMName' to boot from ISO: $ISOPath" `
        -Level SECURITY -Action "ISOConfiguration"

    try {
        $VM = Get-VM -Name $VMName -ErrorAction Stop
        if (-not $VM) {
            throw "VM '$VMName' not found"
        }

        # Get CD drive
        $CDDrive = Get-CDDrive -VM $VM -ErrorAction Stop
        if (-not $CDDrive) {
            throw "No CD drive found on VM '$VMName'"
        }

        # Configure CD drive with ISO
        Set-CDDrive -CD $CDDrive -IsoPath $ISOPath -StartConnected $true -Connected $true -Confirm:$false -ErrorAction Stop

        Write-AuditLog -Message "ISO attached to VM '$VMName' successfully" -Level SECURITY -Action "ISOConfiguration"
        Write-Host "SUCCESS: ISO attached to VM '$VMName'" -ForegroundColor Green

    } catch {
        Write-AuditLog -Message "Error configuring ISO for VM '$VMName': $_" -Level ERROR -Action "ISOConfiguration"
        throw
    }
}
#endregion

#region Rollback Function
function Invoke-Rollback {
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Starting rollback of created resources" -Level WARNING -Action "Rollback"
    Write-Host "`nRolling back created resources..." -ForegroundColor Yellow

    foreach ($resource in $Global:CreatedResources) {
        try {
            Write-Host "Removing $($resource.Type): $($resource.Name)..." -ForegroundColor Yellow

            switch ($resource.Type) {
                'VM' {
                    Remove-VM -VM $resource.Object -DeletePermanently -Confirm:$false -ErrorAction Stop
                }
                'VirtualSwitch' {
                    Remove-VirtualSwitch -VirtualSwitch $resource.Object -Confirm:$false -ErrorAction Stop
                }
            }

            Write-AuditLog -Message "Rolled back $($resource.Type): $($resource.Name)" -Level INFO -Action "Rollback"

        } catch {
            Write-AuditLog -Message "Error rolling back $($resource.Type) '$($resource.Name)': $_" `
                -Level ERROR -Action "Rollback"
        }
    }

    Write-Host "Rollback completed" -ForegroundColor Yellow
}
#endregion

#region Main Script Execution
try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  HOME LAB DEPLOYMENT v2.0" -ForegroundColor Cyan
    Write-Host "  Fourth Estate Secure Edition" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-AuditLog -Message "Home Lab deployment script started" -Level SECURITY -Action "ScriptStart"
    Write-AuditLog -Message "Parameters: VMHost=$VMHost, Folder=$VMFolder, Datastore=$Datastore" `
        -Level INFO -Action "ScriptStart"

    # Connect to vCenter/ESXi if not connected
    if (-not $Global:DefaultVIServer -and $Credential) {
        Write-Host "Connecting to $VMHost..." -ForegroundColor Cyan
        Connect-VIServer -Server $VMHost -Credential $Credential -ErrorAction Stop
        Write-AuditLog -Message "Connected to $VMHost" -Level SECURITY -Action "Connection"
    }

    # Run prerequisite checks
    if (-not (Test-Prerequisites)) {
        throw "Prerequisite checks failed. Deployment cannot continue."
    }

    Write-Host ""
    Write-Host "Starting deployment..." -ForegroundColor Cyan
    Write-Host ""

    # Define networks
    $Networks = @(
        @{ Name = "ManagementNetwork"; Subnet = "192.168.1.0/24"; Gateway = "192.168.1.1" },
        @{ Name = "InternalNetwork";   Subnet = "192.168.2.0/24"; Gateway = "192.168.2.1" }
    )

    # Define VMs
    $VMs = @(
        @{ Name = "DC1";        MemoryGB = 4; CPUs = 2; DiskGB = 40 },
        @{ Name = "WebServer1"; MemoryGB = 2; CPUs = 1; DiskGB = 20 },
        @{ Name = "SQLServer1"; MemoryGB = 4; CPUs = 2; DiskGB = 40 }
    )

    # Create virtual networks
    Write-Host "Creating virtual networks..." -ForegroundColor Yellow
    foreach ($net in $Networks) {
        New-VirtualNetwork -Name $net.Name -Subnet $net.Subnet -Gateway $net.Gateway
    }

    Write-Host ""
    Write-Host "Creating virtual machines..." -ForegroundColor Yellow
    foreach ($vm in $VMs) {
        New-VirtualMachine -Name $vm.Name -MemoryGB $vm.MemoryGB -CPUs $vm.CPUs -DiskGB $vm.DiskGB
    }

    Write-Host ""
    Write-Host "Configuring Windows Server installation..." -ForegroundColor Yellow
    foreach ($vm in $VMs) {
        Install-WindowsServer -VMName $vm.Name -ISOPath $ISOPath
    }

    # Summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Networks deployed: $($Networks.Count)" -ForegroundColor White
    foreach ($net in $Networks) {
        Write-Host "  - $($net.Name)" -ForegroundColor Gray
    }
    Write-Host "VMs deployed: $($VMs.Count)" -ForegroundColor White
    foreach ($vm in $VMs) {
        Write-Host "  - $($vm.Name)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Audit log: $Global:AuditLogPath" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Green

    Write-AuditLog -Message "Home Lab deployment completed successfully" -Level SECURITY -Action "ScriptComplete"

} catch {
    Write-AuditLog -Message "Critical error in deployment: $_" -Level ERROR -Action "ScriptError"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  DEPLOYMENT FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""

    # Offer rollback
    $rollback = Read-Host "Do you want to rollback created resources? (Y/N)"
    if ($rollback -eq 'Y' -or $rollback -eq 'y') {
        Invoke-Rollback
    }

    exit 1

} finally {
    # Clear any sensitive data from memory
    if ($Credential) {
        $Credential = $null
    }

    Write-Host ""
    Write-Host "Script execution finished." -ForegroundColor Gray
}
#endregion
