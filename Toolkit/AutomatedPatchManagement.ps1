<#
.SYNOPSIS
    Production-Ready Automated Patch Management for Windows Servers/Workstations.
.DESCRIPTION
    Schedules, deploys, and verifies OS/application updates across target systems. Includes robust logging, error handling, input validation, and reporting.
.PARAMETER ComputerList
    Array of computer names or IPs to patch.
.PARAMETER Schedule
    Optional: Schedule time for patch deployment.
.EXAMPLE
    .\AutomatedPatchManagement.ps1 -ComputerList ("Server1","Server2")
#>
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerList,
    [datetime]$Schedule
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','ERROR','WARNING')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
    Add-Content -Path "PatchMgmt.log" -Value "$timestamp [$Level] $Message"
}

function Invoke-RemotePatch {
    param(
        [string]$Computer
    )
    Write-Log -Message "Checking updates on $Computer..." -Level 'INFO'
    try {
        $result = Invoke-Command -ComputerName $Computer -ScriptBlock {
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
            }
            Import-Module PSWindowsUpdate
            Get-WindowsUpdate -AcceptAll -Install -AutoReboot -ErrorAction Stop
        } -ErrorAction Stop
        Write-Log -Message "Updates installed on $Computer. Result: $($result | Out-String)" -Level 'INFO'
        return $true
    } catch {
    Write-Log -Message ("Error patching ${Computer}. Error: $($_)") -Level 'ERROR'
        return $false
    }
}

if ($Schedule) {
    Write-Log -Message "Patch deployment scheduled for $Schedule. Waiting..." -Level 'INFO'
    $now = Get-Date
    $wait = ($Schedule - $now).TotalSeconds
    if ($wait -gt 0) { Start-Sleep -Seconds $wait }
}

$summary = @{}
foreach ($computer in $ComputerList) {
    $success = Invoke-RemotePatch -Computer $computer
    $summary[$computer] = if ($success) { 'Success' } else { 'Failed' }
}

Write-Log -Message "Patch management completed." -Level 'INFO'
Write-Host "\nPatch Summary:"
foreach ($key in $summary.Keys) {
    Write-Host "$key : $($summary[$key])"
}
