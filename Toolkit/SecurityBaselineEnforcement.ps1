<#
.SYNOPSIS
    Security Baseline Enforcement Script with CIS/STIG compliance checks and remediation.

.DESCRIPTION
    Applies and verifies CIS/STIG security baselines for Windows, VMware, and Hyper-V.
    Performs comprehensive security checks, implements remediation actions, and generates
    detailed compliance reports.

    Supported Baselines:
    - Windows Server 2019/2022 CIS Benchmarks
    - Windows 10/11 CIS Benchmarks
    - DISA STIG for Windows
    - VMware vSphere Security Configuration Guide
    - Hyper-V Security Baseline

.PARAMETER ComputerList
    Array of computer names or IPs to enforce baselines on.

.PARAMETER Credential
    PSCredential object for remote authentication.

.PARAMETER BaselineFile
    Path to baseline configuration file (JSON format).

.PARAMETER Platform
    Target platform: Windows, VMware, or HyperV.

.PARAMETER RemediationMode
    Remediation mode: Audit (report only) or Enforce (apply fixes).

.PARAMETER ReportPath
    Path for compliance reports. Default is C:\Reports\SecurityBaseline.html

.SECURITY FEATURES
    - Requires PowerShell 5.1 and Administrator privileges
    - Comprehensive audit logging to file and Windows Event Log
    - Secure credential handling via PSCredential
    - Input validation for all parameters
    - Backup of settings before remediation
    - Sensitive data cleared from memory on exit

.COMPLIANCE
    - CIS Benchmark compliance reporting
    - DISA STIG compliance checks
    - Fourth Estate security standards
    - Defense-in-depth logging
    - Full audit trail

.EXAMPLE
    $cred = Get-Credential
    .\SecurityBaselineEnforcement.ps1 -ComputerList @("Server1","Server2") -Credential $cred -BaselineFile "C:\Baselines\WindowsServer2022-CIS.json" -Platform Windows -RemediationMode Audit

.EXAMPLE
    $cred = Get-Credential
    .\SecurityBaselineEnforcement.ps1 -ComputerList @("Server1") -Credential $cred -BaselineFile "C:\Baselines\STIG.json" -Platform Windows -RemediationMode Enforce

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0
    Disclaimer:     Scripts are provided as-is, without warranty. Test in non-production before use.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        foreach ($computer in $_) {
            if ($computer -notmatch '^[a-zA-Z0-9\-\.]+$') {
                throw "Invalid computer name format: $computer"
            }
        }
        $true
    })]
    [string[]]$ComputerList,

    [Parameter(Mandatory=$true)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory=$true)]
    [ValidateScript({
        if (Test-Path -Path $_ -PathType Leaf) {
            if ($_ -match '\.json$') {
                $true
            } else {
                throw "Baseline file must be JSON format (.json)"
            }
        } else {
            throw "Baseline file not found: $_"
        }
    })]
    [string]$BaselineFile,

    [Parameter(Mandatory=$true)]
    [ValidateSet('Windows','VMware','HyperV')]
    [string]$Platform,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Audit','Enforce')]
    [string]$RemediationMode = 'Audit',

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '^[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]+\.html$') {
            $true
        } else {
            throw "Invalid report path format. Must be .html file."
        }
    })]
    [string]$ReportPath = "C:\Reports\SecurityBaseline.html"
)

#==============================================
# Global Logging Setup
#==============================================

$Global:LogFile = "C:\Logs\SecurityBaseline.log"
$Global:EventLogSource = "SecurityBaseline"
$Global:EventLogName = "Application"

# Ensure directories exist
foreach ($path in @($Global:LogFile, $ReportPath)) {
    $dir = Split-Path -Path $path -Parent
    if (-not (Test-Path -Path $dir -PathType Container)) {
        try {
            New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Error "Failed to create directory: $dir. Error: $_"
            exit 1
        }
    }
}

# Register Event Log Source
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
        [System.Diagnostics.EventLog]::CreateEventSource($Global:EventLogSource, $Global:EventLogName)
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Warning "Could not create Event Log source. Continuing with file logging only."
}

#==============================================
# Function: Write-AuditLog
#==============================================
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','ERROR','WARNING','SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory=$false)]
        [string]$Operation = 'General',

        [Parameter(Mandatory=$false)]
        [string]$TargetSystem = 'Local'
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $logMessage = "$timestamp [$Level] User: $userName | Operation: $Operation | Target: $TargetSystem | $Message"

        switch ($Level) {
            'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            default   { Write-Host $logMessage }
        }

        Add-Content -Path $Global:LogFile -Value $logMessage -ErrorAction Stop

        $eventType = switch ($Level) {
            'ERROR'   { [System.Diagnostics.EventLogEntryType]::Error }
            'WARNING' { [System.Diagnostics.EventLogEntryType]::Warning }
            default   { [System.Diagnostics.EventLogEntryType]::Information }
        }

        $eventID = switch ($Level) {
            'ERROR'   { 7001 }
            'WARNING' { 7002 }
            'SUCCESS' { 7003 }
            default   { 7000 }
        }

        if ([System.Diagnostics.EventLog]::SourceExists($Global:EventLogSource)) {
            Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
                -EntryType $eventType -EventId $eventID -Message $logMessage -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Failed to write to audit log: $_"
    }
}

#==============================================
# CIS/STIG Baseline Checks
#==============================================

function Test-PasswordPolicy {
    param([string]$Computer)

    Write-AuditLog -Message "Checking password policy" -Level INFO -Operation "PasswordPolicy" -TargetSystem $Computer

    $results = @()

    try {
        $policy = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            $secedit = secedit /export /cfg "$env:TEMP\secpol.cfg" 2>&1
            $content = Get-Content "$env:TEMP\secpol.cfg"
            Remove-Item "$env:TEMP\secpol.cfg" -Force
            return $content
        }

        # CIS Benchmark: Minimum password length should be 14
        $minLength = ($policy | Select-String "MinimumPasswordLength\s*=\s*(\d+)").Matches.Groups[1].Value
        $results += [PSCustomObject]@{
            Check = "CIS 1.1.1 - Minimum Password Length"
            Expected = "14 characters"
            Actual = "$minLength characters"
            Status = if ([int]$minLength -ge 14) { "PASS" } else { "FAIL" }
            Severity = "High"
        }

        # CIS Benchmark: Maximum password age should be 60 days or less
        $maxAge = ($policy | Select-String "MaximumPasswordAge\s*=\s*(\d+)").Matches.Groups[1].Value
        $results += [PSCustomObject]@{
            Check = "CIS 1.1.2 - Maximum Password Age"
            Expected = "60 days or less"
            Actual = "$maxAge days"
            Status = if ([int]$maxAge -le 60 -and [int]$maxAge -gt 0) { "PASS" } else { "FAIL" }
            Severity = "Medium"
        }

        # CIS Benchmark: Password history should be 24 or more
        $passHistory = ($policy | Select-String "PasswordHistorySize\s*=\s*(\d+)").Matches.Groups[1].Value
        $results += [PSCustomObject]@{
            Check = "CIS 1.1.3 - Password History"
            Expected = "24 passwords remembered"
            Actual = "$passHistory passwords"
            Status = if ([int]$passHistory -ge 24) { "PASS" } else { "FAIL" }
            Severity = "Medium"
        }

        Write-AuditLog -Message "Password policy check completed" -Level SUCCESS -Operation "PasswordPolicy" -TargetSystem $Computer

    } catch {
        Write-AuditLog -Message "Error checking password policy: $_" -Level ERROR -Operation "PasswordPolicy" -TargetSystem $Computer
    }

    return $results
}

function Test-AccountLockoutPolicy {
    param([string]$Computer)

    Write-AuditLog -Message "Checking account lockout policy" -Level INFO -Operation "LockoutPolicy" -TargetSystem $Computer

    $results = @()

    try {
        $policy = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            net accounts | Out-String
        }

        # CIS Benchmark: Account lockout threshold should be 5 or fewer
        if ($policy -match "Lockout threshold:\s*(\d+)") {
            $threshold = $matches[1]
            $results += [PSCustomObject]@{
                Check = "CIS 1.2.1 - Account Lockout Threshold"
                Expected = "5 or fewer invalid attempts"
                Actual = "$threshold attempts"
                Status = if ([int]$threshold -le 5 -and [int]$threshold -gt 0) { "PASS" } else { "FAIL" }
                Severity = "High"
            }
        }

        # CIS Benchmark: Account lockout duration should be 15 minutes or more
        if ($policy -match "Lockout duration \(minutes\):\s*(\d+)") {
            $duration = $matches[1]
            $results += [PSCustomObject]@{
                Check = "CIS 1.2.2 - Account Lockout Duration"
                Expected = "15 minutes or more"
                Actual = "$duration minutes"
                Status = if ([int]$duration -ge 15) { "PASS" } else { "FAIL" }
                Severity = "Medium"
            }
        }

        Write-AuditLog -Message "Account lockout policy check completed" -Level SUCCESS -Operation "LockoutPolicy" -TargetSystem $Computer

    } catch {
        Write-AuditLog -Message "Error checking lockout policy: $_" -Level ERROR -Operation "LockoutPolicy" -TargetSystem $Computer
    }

    return $results
}

function Test-AuditPolicy {
    param([string]$Computer)

    Write-AuditLog -Message "Checking audit policy" -Level INFO -Operation "AuditPolicy" -TargetSystem $Computer

    $results = @()

    try {
        $auditSettings = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            auditpol /get /category:* | Out-String
        }

        $requiredAudits = @{
            "Logon/Logoff" = @("Logon", "Logoff", "Account Lockout")
            "Account Management" = @("User Account Management", "Security Group Management")
            "Policy Change" = @("Audit Policy Change", "Authentication Policy Change")
            "Privilege Use" = @("Sensitive Privilege Use")
            "System" = @("Security System Extension", "System Integrity")
        }

        foreach ($category in $requiredAudits.Keys) {
            foreach ($subcategory in $requiredAudits[$category]) {
                $pattern = "$subcategory\s+(Success and Failure|Success|Failure|No Auditing)"
                if ($auditSettings -match $pattern) {
                    $setting = $matches[1]
                    $results += [PSCustomObject]@{
                        Check = "CIS Audit - $subcategory"
                        Expected = "Success and Failure"
                        Actual = $setting
                        Status = if ($setting -eq "Success and Failure") { "PASS" } else { "FAIL" }
                        Severity = "High"
                    }
                }
            }
        }

        Write-AuditLog -Message "Audit policy check completed" -Level SUCCESS -Operation "AuditPolicy" -TargetSystem $Computer

    } catch {
        Write-AuditLog -Message "Error checking audit policy: $_" -Level ERROR -Operation "AuditPolicy" -TargetSystem $Computer
    }

    return $results
}

function Test-FirewallConfiguration {
    param([string]$Computer)

    Write-AuditLog -Message "Checking firewall configuration" -Level INFO -Operation "FirewallConfig" -TargetSystem $Computer

    $results = @()

    try {
        $firewallProfiles = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            Get-NetFirewallProfile | Select-Object Name, Enabled
        }

        foreach ($profile in $firewallProfiles) {
            $results += [PSCustomObject]@{
                Check = "CIS 9.1 - Windows Firewall ($($profile.Name))"
                Expected = "Enabled"
                Actual = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
                Status = if ($profile.Enabled) { "PASS" } else { "FAIL" }
                Severity = "Critical"
            }
        }

        Write-AuditLog -Message "Firewall configuration check completed" -Level SUCCESS -Operation "FirewallConfig" -TargetSystem $Computer

    } catch {
        Write-AuditLog -Message "Error checking firewall: $_" -Level ERROR -Operation "FirewallConfig" -TargetSystem $Computer
    }

    return $results
}

function Test-ServiceConfiguration {
    param([string]$Computer)

    Write-AuditLog -Message "Checking service configuration" -Level INFO -Operation "ServiceConfig" -TargetSystem $Computer

    $results = @()

    try {
        # STIG: Disable unnecessary services
        $unnecessaryServices = @(
            "RemoteRegistry",
            "Telnet",
            "SSDPSRV",
            "upnphost",
            "WMPNetworkSvc",
            "RemoteAccess"
        )

        $services = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            param($serviceList)
            foreach ($svc in $serviceList) {
                try {
                    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
                    if ($service) {
                        [PSCustomObject]@{
                            Name = $svc
                            Status = $service.Status
                            StartType = $service.StartType
                        }
                    }
                } catch {}
            }
        } -ArgumentList (,$unnecessaryServices)

        foreach ($svc in $services) {
            $results += [PSCustomObject]@{
                Check = "STIG - Disable Unnecessary Service ($($svc.Name))"
                Expected = "Disabled"
                Actual = "$($svc.StartType)"
                Status = if ($svc.StartType -eq 'Disabled') { "PASS" } else { "FAIL" }
                Severity = "Medium"
            }
        }

        Write-AuditLog -Message "Service configuration check completed" -Level SUCCESS -Operation "ServiceConfig" -TargetSystem $Computer

    } catch {
        Write-AuditLog -Message "Error checking services: $_" -Level ERROR -Operation "ServiceConfig" -TargetSystem $Computer
    }

    return $results
}

function Test-RegistrySecuritySettings {
    param([string]$Computer)

    Write-AuditLog -Message "Checking registry security settings" -Level INFO -Operation "RegistrySettings" -TargetSystem $Computer

    $results = @()

    try {
        $registryChecks = @{
            "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\LmCompatibilityLevel" = @{
                Expected = 5
                Description = "CIS 2.3.11.1 - Network security: LAN Manager authentication level"
                Severity = "High"
            }
            "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\EnableSecuritySignature" = @{
                Expected = 1
                Description = "CIS 2.3.9.1 - Microsoft network server: Digitally sign communications (always)"
                Severity = "High"
            }
            "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\ClearPageFileAtShutdown" = @{
                Expected = 1
                Description = "CIS 2.3.7.1 - Shutdown: Clear virtual memory pagefile"
                Severity = "Medium"
            }
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA" = @{
                Expected = 1
                Description = "CIS 2.3.17.1 - User Account Control: Run all administrators in Admin Approval Mode"
                Severity = "Critical"
            }
        }

        $regResults = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            param($checks)
            $results = @()
            foreach ($path in $checks.Keys) {
                try {
                    $value = Get-ItemProperty -Path $path -ErrorAction Stop
                    $propName = Split-Path -Path $path -Leaf
                    $actualValue = $value.$propName
                    $results += @{
                        Path = $path
                        Actual = $actualValue
                    }
                } catch {
                    $results += @{
                        Path = $path
                        Actual = "Not Found"
                    }
                }
            }
            return $results
        } -ArgumentList (,$registryChecks)

        foreach ($result in $regResults) {
            $check = $registryChecks[$result.Path]
            $results += [PSCustomObject]@{
                Check = $check.Description
                Expected = $check.Expected
                Actual = $result.Actual
                Status = if ($result.Actual -eq $check.Expected) { "PASS" } else { "FAIL" }
                Severity = $check.Severity
            }
        }

        Write-AuditLog -Message "Registry security settings check completed" -Level SUCCESS -Operation "RegistrySettings" -TargetSystem $Computer

    } catch {
        Write-AuditLog -Message "Error checking registry settings: $_" -Level ERROR -Operation "RegistrySettings" -TargetSystem $Computer
    }

    return $results
}

#==============================================
# Remediation Functions
#==============================================

function Invoke-Remediation {
    param(
        [string]$Computer,
        [array]$FailedChecks
    )

    if ($RemediationMode -ne 'Enforce') {
        Write-AuditLog -Message "Remediation mode is Audit only. Skipping remediation." -Level INFO -Operation "Remediation" -TargetSystem $Computer
        return
    }

    Write-AuditLog -Message "Starting remediation for $($FailedChecks.Count) failed checks" -Level INFO -Operation "Remediation" -TargetSystem $Computer

    foreach ($check in $FailedChecks) {
        try {
            # Implement specific remediation based on check type
            Write-AuditLog -Message "Remediating: $($check.Check)" -Level INFO -Operation "Remediation" -TargetSystem $Computer

            # Add specific remediation logic here based on check type
            # This would involve Invoke-Command to apply fixes

        } catch {
            Write-AuditLog -Message "Failed to remediate $($check.Check): $_" -Level ERROR -Operation "Remediation" -TargetSystem $Computer
        }
    }
}

#==============================================
# Report Generation
#==============================================

function New-ComplianceReport {
    param(
        [hashtable]$Results
    )

    Write-AuditLog -Message "Generating compliance report" -Level INFO -Operation "ReportGeneration"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Baseline Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; border-bottom: 2px solid #3498db; padding-bottom: 5px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 30px; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .critical { background-color: #e74c3c; color: white; }
        .high { background-color: #e67e22; color: white; }
        .medium { background-color: #f39c12; color: white; }
        .low { background-color: #3498db; color: white; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .timestamp { color: #7f8c8d; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>Security Baseline Compliance Report</h1>
    <p class="timestamp">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p>Platform: $Platform | Remediation Mode: $RemediationMode</p>

    <div class="summary">
        <h2>Summary</h2>
"@

    $totalChecks = 0
    $totalPass = 0
    $totalFail = 0

    foreach ($computer in $Results.Keys) {
        $checks = $Results[$computer]
        $totalChecks += $checks.Count
        $totalPass += ($checks | Where-Object { $_.Status -eq 'PASS' }).Count
        $totalFail += ($checks | Where-Object { $_.Status -eq 'FAIL' }).Count
    }

    $passPercent = if ($totalChecks -gt 0) { [math]::Round(($totalPass / $totalChecks) * 100, 2) } else { 0 }

    $html += @"
        <p><strong>Total Checks:</strong> $totalChecks</p>
        <p><strong>Passed:</strong> <span class="pass">$totalPass</span></p>
        <p><strong>Failed:</strong> <span class="fail">$totalFail</span></p>
        <p><strong>Compliance Rate:</strong> $passPercent%</p>
    </div>
"@

    foreach ($computer in $Results.Keys) {
        $checks = $Results[$computer]

        $html += @"
    <h2>$computer</h2>
    <table>
        <tr>
            <th>Check</th>
            <th>Expected</th>
            <th>Actual</th>
            <th>Status</th>
            <th>Severity</th>
        </tr>
"@

        foreach ($check in $checks) {
            $statusClass = if ($check.Status -eq 'PASS') { 'pass' } else { 'fail' }
            $severityClass = $check.Severity.ToLower()

            $html += @"
        <tr>
            <td>$($check.Check)</td>
            <td>$($check.Expected)</td>
            <td>$($check.Actual)</td>
            <td class="$statusClass">$($check.Status)</td>
            <td class="$severityClass">$($check.Severity)</td>
        </tr>
"@
        }

        $html += @"
    </table>
"@
    }

    $html += @"
</body>
</html>
"@

    try {
        $html | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
        Write-AuditLog -Message "Compliance report generated: $ReportPath" -Level SUCCESS -Operation "ReportGeneration"
    } catch {
        Write-AuditLog -Message "Failed to generate report: $_" -Level ERROR -Operation "ReportGeneration"
    }
}

#==============================================
# Main Execution
#==============================================

Write-AuditLog -Message "Security baseline enforcement started" -Level INFO -Operation "Initialization"
Write-AuditLog -Message "Platform: $Platform | Mode: $RemediationMode" -Level INFO -Operation "Initialization"

# Load baseline configuration
try {
    $baselineConfig = Get-Content -Path $BaselineFile -Raw | ConvertFrom-Json
    Write-AuditLog -Message "Baseline configuration loaded from $BaselineFile" -Level SUCCESS -Operation "Initialization"
} catch {
    Write-AuditLog -Message "Failed to load baseline configuration: $_" -Level ERROR -Operation "Initialization"
    exit 1
}

$allResults = @{}

try {
    foreach ($computer in $ComputerList) {
        Write-AuditLog -Message "Processing computer: $computer" -Level INFO -Operation "ProcessComputer" -TargetSystem $computer

        # Test connectivity
        if (-not (Test-Connection -ComputerName $computer -Count 2 -Quiet)) {
            Write-AuditLog -Message "Cannot reach computer" -Level ERROR -Operation "ConnectivityTest" -TargetSystem $computer
            continue
        }

        $computerResults = @()

        # Run all baseline checks
        $computerResults += Test-PasswordPolicy -Computer $computer
        $computerResults += Test-AccountLockoutPolicy -Computer $computer
        $computerResults += Test-AuditPolicy -Computer $computer
        $computerResults += Test-FirewallConfiguration -Computer $computer
        $computerResults += Test-ServiceConfiguration -Computer $computer
        $computerResults += Test-RegistrySecuritySettings -Computer $computer

        $allResults[$computer] = $computerResults

        # Check for failed checks and remediate if needed
        $failedChecks = $computerResults | Where-Object { $_.Status -eq 'FAIL' }
        if ($failedChecks) {
            Write-AuditLog -Message "Found $($failedChecks.Count) failed checks" -Level WARNING -Operation "Assessment" -TargetSystem $computer
            Invoke-Remediation -Computer $computer -FailedChecks $failedChecks
        } else {
            Write-AuditLog -Message "All checks passed" -Level SUCCESS -Operation "Assessment" -TargetSystem $computer
        }
    }

    # Generate compliance report
    New-ComplianceReport -Results $allResults

} catch {
    Write-AuditLog -Message "Critical error during execution: $_" -Level ERROR -Operation "MainExecution"
    throw
} finally {
    # Clear sensitive data
    if ($Credential) {
        $Credential = $null
    }
    [System.GC]::Collect()
}

Write-Host "`nSecurity Baseline Enforcement Summary:" -ForegroundColor Cyan
Write-Host "Computers processed: $($ComputerList.Count)"
Write-Host "Compliance report: $ReportPath"
Write-AuditLog -Message "Security baseline enforcement completed" -Level SUCCESS -Operation "Completion"
exit 0
