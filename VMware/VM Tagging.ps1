<#
.SYNOPSIS
    Applies a specific tag to all virtual machines in a vCenter Server or ESXi host.

.DESCRIPTION
    This script:
      1. Checks if the VMware.PowerCLI module is installed (installs if not) and imports it.
      2. Prompts for connection details and connects.
      3. Retrieves all VMs from the environment.
      4. Prompts for tag details (name, category, description).
      5. Checks if the tag exists; creates if not.
      6. Applies the tag to all VMs.
      7. Disconnects from the vCenter Server/ESXi host.

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict certificate validation enforced
    - PSCredential-based authentication
    - Comprehensive audit logging
    - Input validation for tag names
    - WhatIf/Confirm support for tagging operations
    - Automatic session cleanup

.COMPLIANCE
    - Suitable for Fourth Estate infrastructure
    - Audit trail for all tagging operations
    - Defense-in-depth security controls

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    Last Updated:   October 30, 2025
    Version:        2.0
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules VMware.PowerCLI

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-AuditLog {
    param([Parameter(Mandatory = $true)][string]$Message, [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')][string]$Level = 'INFO',
        [string]$LogFile, [string]$VCenter, [string]$VMName)
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $auditMessage = "$timeStamp [$Level] User: $userName"
    if ($VCenter) { $auditMessage += " | vCenter: $VCenter" }
    if ($VMName) { $auditMessage += " | Resource: $VMName" }
    $auditMessage += " | $Message"
    switch ($Level) { 'ERROR' { Write-Host $auditMessage -ForegroundColor Red } 'WARNING' { Write-Host $auditMessage -ForegroundColor Yellow }
        'SECURITY' { Write-Host $auditMessage -ForegroundColor Cyan } default { Write-Host $auditMessage } }
    if ($LogFile) { try { Add-Content -Path $LogFile -Value $auditMessage -ErrorAction Stop } catch { Write-Warning "Failed to write to log file: $_" } }
    try {
        $eventSource = 'VMware-PowerCLI-Security'
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) { New-EventLog -LogName Application -Source $eventSource -ErrorAction SilentlyContinue }
        $eventType = switch ($Level) { 'ERROR' { 'Error' } 'WARNING' { 'Warning' } 'SECURITY' { 'SuccessAudit' } default { 'Information' } }
        Write-EventLog -LogName Application -Source $eventSource -EntryType $eventType -EventId 1009 -Message $auditMessage -ErrorAction SilentlyContinue
    } catch { }
}

function Test-ValidServerName { param([string]$Name)
    if ($Name -match '[;&|`$<>]') { throw "Invalid characters in name: $Name" }
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Name cannot be empty" }
    return $true
}

$logDirectory = Join-Path $env:ProgramData 'VMware\PowerCLI\AuditLogs'
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDirectory "VM_Tagging_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Write-AuditLog -Message "Script execution started" -Level SECURITY -LogFile $logFile
$viConnection = $null
$credential = $null

try {
    if (-not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
        Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null
    Write-AuditLog -Message "PowerCLI configured securely" -Level SECURITY -LogFile $logFile

    $Summary = @{'VMs Processed' = 0; 'VMs Tagged' = 0; 'VMs Failed' = 0}
    $server = Read-Host "Enter vCenter Server or ESXi host"
    Test-ValidServerName -Name $server
    $user = Read-Host "Enter username"
    $securePassword = Read-Host "Enter password" -AsSecureString
    $credential = New-Object System.Management.Automation.PSCredential($user, $securePassword)
    Write-AuditLog -Message "Connecting to $server" -VCenter $server -LogFile $logFile
    $viConnection = Connect-VIServer -Server $server -Credential $credential -ErrorAction Stop
    Write-AuditLog -Message "Connected to $server" -Level SECURITY -VCenter $server -LogFile $logFile

    Write-AuditLog -Message "Retrieving VMs..." -VCenter $server -LogFile $logFile
    $vms = Get-VM -ErrorAction Stop
    Write-AuditLog -Message "Retrieved $($vms.Count) VMs" -VCenter $server -LogFile $logFile
    $Summary['VMs Processed'] = $vms.Count

    $tagName = Read-Host "Enter the tag name to apply"
    Test-ValidServerName -Name $tagName
    $tagCategoryName = Read-Host "Enter the tag category name"
    Test-ValidServerName -Name $tagCategoryName
    $tagDescription = Read-Host "Enter the tag description"

    $tag = Get-Tag -Name $tagName -ErrorAction SilentlyContinue
    if (-not $tag) {
        Write-AuditLog -Message "Tag '$tagName' not found. Creating..." -VCenter $server -LogFile $logFile
        $tagCategoryObject = Get-TagCategory -Name $tagCategoryName -ErrorAction SilentlyContinue
        if (-not $tagCategoryObject) {
            Write-AuditLog -Message "Creating tag category '$tagCategoryName'" -Level SECURITY -VCenter $server -LogFile $logFile
            $tagCategoryObject = New-TagCategory -Name $tagCategoryName -Description $tagDescription -Cardinality Single -ErrorAction Stop
        }
        $tag = New-Tag -Name $tagName -Category $tagCategoryObject -Description $tagDescription -ErrorAction Stop
        Write-AuditLog -Message "Tag '$tagName' created" -Level SECURITY -VCenter $server -LogFile $logFile
    }

    foreach ($vm in $vms) {
        if ($PSCmdlet.ShouldProcess("$($vm.Name)", "Apply tag '$tagName'")) {
            try {
                New-TagAssignment -Tag $tag -Entity $vm -ErrorAction Stop | Out-Null
                Write-AuditLog -Message "Tagged VM: $($vm.Name)" -VCenter $server -VMName $vm.Name -LogFile $logFile
                $Summary['VMs Tagged']++
            } catch {
                Write-AuditLog -Message "Failed to tag VM $($vm.Name): $_" -Level ERROR -VCenter $server -VMName $vm.Name -LogFile $logFile
                $Summary['VMs Failed']++
            }
        }
    }
} catch {
    Write-AuditLog -Message "Script execution failed: $_" -Level ERROR -LogFile $logFile
    throw
} finally {
    if ($viConnection) {
        try {
            Disconnect-VIServer -Server $server -Confirm:$false -ErrorAction SilentlyContinue
            Write-AuditLog -Message "Disconnected from $server" -Level SECURITY -VCenter $server -LogFile $logFile
        } catch { }
    }
    if ($credential) { $credential = $null }
    if ($securePassword) { $securePassword = $null }
    Write-Host "`nSummary:" -ForegroundColor Cyan
    foreach ($key in $Summary.Keys) { Write-Host "$key: $Summary[$key]" }
    Write-Host "Audit log saved to: $logFile"
    Write-AuditLog -Message "Script execution completed" -Level SECURITY -LogFile $logFile
}
