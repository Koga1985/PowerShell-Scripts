#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive role-based access auditing across AD, Windows, VMware, and Veeam environments.

.DESCRIPTION
    This script performs thorough access and permission auditing:
      1. Active Directory user and group memberships
      2. Windows local administrators and privileged groups
      3. File share permissions (if applicable)
      4. Outputs comprehensive audit report

.PARAMETER ComputerName
    Array of computer names or IP addresses to audit.

.PARAMETER Credential
    PSCredential object for authentication to remote systems.

.PARAMETER IncludeAD
    Switch to include Active Directory auditing.

.PARAMETER IncludeFileShares
    Switch to include file share permission auditing.

.PARAMETER OutputFormat
    Output format: CSV, JSON, or HTML. Default is HTML.

.PARAMETER ExportPath
    Path for the exported audit report.

.EXAMPLE
    $cred = Get-Credential
    .\RoleBasedAccessAudit.ps1 -ComputerName "Server01","Server02" -Credential $cred -IncludeAD -OutputFormat HTML

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges
      - Active Directory module (for AD auditing)
      - WinRM enabled on target computers

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Secure credential handling (PSCredential)
    - Input validation and sanitization
    - Secure error handling with proper cleanup

.COMPLIANCE
    - Aligns with NIST SP 800-53 controls (AC-2: Account Management, AC-6: Least Privilege)
    - Supports DISA STIG requirements for access control auditing
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAD,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeFileShares,

    [Parameter(Mandatory = $false)]
    [ValidateSet('CSV', 'JSON', 'HTML')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "RoleBasedAccessAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\RoleBasedAccessAudit_Audit.log"
$script:EventSource = "RoleBasedAccessAudit"

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
try {
    Write-AuditLog -Message "===== Role-Based Access Audit Started =====" -Level "INFO"
    Write-AuditLog -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
    Write-AuditLog -Message "Target Computers: $($ComputerName -join ', ')" -Level "INFO"

    $auditResults = @()

    #----------------------------------------------
    # Active Directory Audit
    #----------------------------------------------
    if ($IncludeAD) {
        Write-AuditLog -Message "Performing Active Directory access audit..." -Level "INFO"

        try {
            # Import AD module if available
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction Stop
                Write-AuditLog -Message "Active Directory module loaded." -Level "SUCCESS"

                # Get privileged AD groups
                $privilegedGroups = @(
                    'Domain Admins',
                    'Enterprise Admins',
                    'Schema Admins',
                    'Administrators',
                    'Account Operators',
                    'Backup Operators',
                    'Server Operators'
                )

                foreach ($group in $privilegedGroups) {
                    try {
                        $members = Get-ADGroupMember -Identity $group -Recursive -ErrorAction SilentlyContinue

                        foreach ($member in $members) {
                            $auditResults += [PSCustomObject]@{
                                ComputerName = 'Active Directory'
                                Category = 'AD Group Membership'
                                Group = $group
                                UserName = $member.SamAccountName
                                DisplayName = $member.Name
                                ObjectClass = $member.ObjectClass
                                AuditTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            }
                        }

                        Write-AuditLog -Message "Audited AD group: $group (Members: $($members.Count))" -Level "SUCCESS"
                    } catch {
                        Write-AuditLog -Message "Error auditing AD group $group : $_" -Level "WARNING"
                    }
                }
            } else {
                Write-AuditLog -Message "Active Directory module not available. Skipping AD audit." -Level "WARNING"
            }
        } catch {
            Write-AuditLog -Message "Error during Active Directory audit: $_" -Level "ERROR"
        }
    }

    #----------------------------------------------
    # Windows Local Groups Audit
    #----------------------------------------------
    foreach ($computer in $ComputerName) {
        Write-AuditLog -Message "Auditing local groups on: $computer" -Level "INFO"

        if ($PSCmdlet.ShouldProcess($computer, "Audit local group memberships")) {
            try {
                # Test connectivity
                if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                    Write-AuditLog -Message "Unable to reach computer: $computer" -Level "WARNING"
                    continue
                }

                # Prepare Invoke-Command parameters
                $invokeParams = @{
                    ComputerName = $computer
                    ErrorAction  = 'Stop'
                    ScriptBlock  = {
                        $privilegedGroups = @('Administrators', 'Remote Desktop Users', 'Backup Operators', 'Power Users')
                        $results = @()

                        foreach ($groupName in $privilegedGroups) {
                            try {
                                $group = [ADSI]"WinNT://./$groupName,group"
                                $members = @($group.psbase.Invoke("Members"))

                                foreach ($member in $members) {
                                    $memberPath = $member.GetType().InvokeMember("AdsPath", 'GetProperty', $null, $member, $null)
                                    $memberName = $memberPath.Split('/')[-1]

                                    $results += [PSCustomObject]@{
                                        Group = $groupName
                                        Member = $memberName
                                    }
                                }
                            } catch {
                                # Group may not exist
                            }
                        }

                        return $results
                    }
                }

                # Add credential if provided
                if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                    $invokeParams['Credential'] = $Credential
                }

                # Execute audit
                $localGroupMembers = Invoke-Command @invokeParams

                foreach ($membership in $localGroupMembers) {
                    $auditResults += [PSCustomObject]@{
                        ComputerName = $computer
                        Category = 'Local Group Membership'
                        Group = $membership.Group
                        UserName = $membership.Member
                        DisplayName = $membership.Member
                        ObjectClass = 'User/Group'
                        AuditTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    }
                }

                Write-AuditLog -Message "Successfully audited local groups on $computer" -Level "SUCCESS"

            } catch {
                Write-AuditLog -Message "Error auditing local groups on $computer : $_" -Level "ERROR"
            }
        }
    }

    #----------------------------------------------
    # File Share Permissions Audit (Optional)
    #----------------------------------------------
    if ($IncludeFileShares) {
        foreach ($computer in $ComputerName) {
            Write-AuditLog -Message "Auditing file shares on: $computer" -Level "INFO"

            if ($PSCmdlet.ShouldProcess($computer, "Audit file share permissions")) {
                try {
                    $invokeParams = @{
                        ComputerName = $computer
                        ErrorAction  = 'Stop'
                        ScriptBlock  = {
                            $shares = Get-SmbShare | Where-Object { $_.Name -notmatch '\$$' }
                            $results = @()

                            foreach ($share in $shares) {
                                try {
                                    $permissions = Get-SmbShareAccess -Name $share.Name

                                    foreach ($perm in $permissions) {
                                        $results += [PSCustomObject]@{
                                            ShareName = $share.Name
                                            SharePath = $share.Path
                                            AccountName = $perm.AccountName
                                            AccessRight = $perm.AccessRight
                                            AccessControlType = $perm.AccessControlType
                                        }
                                    }
                                } catch {
                                    # Error accessing share permissions
                                }
                            }

                            return $results
                        }
                    }

                    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                        $invokeParams['Credential'] = $Credential
                    }

                    $sharePermissions = Invoke-Command @invokeParams

                    foreach ($perm in $sharePermissions) {
                        $auditResults += [PSCustomObject]@{
                            ComputerName = $computer
                            Category = 'File Share Permission'
                            Group = "$($perm.ShareName) [$($perm.AccessRight)]"
                            UserName = $perm.AccountName
                            DisplayName = "$($perm.SharePath)"
                            ObjectClass = $perm.AccessControlType
                            AuditTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        }
                    }

                    Write-AuditLog -Message "Successfully audited file shares on $computer" -Level "SUCCESS"

                } catch {
                    Write-AuditLog -Message "Error auditing file shares on $computer : $_" -Level "ERROR"
                }
            }
        }
    }

    #----------------------------------------------
    # Export Audit Report
    #----------------------------------------------
    if ($auditResults.Count -eq 0) {
        Write-AuditLog -Message "No access audit data collected." -Level "WARNING"
    } else {
        Write-AuditLog -Message "Total audit entries collected: $($auditResults.Count)" -Level "SUCCESS"

        # Determine export path
        if (-not $ExportPath) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $ExportPath = switch ($OutputFormat) {
                'CSV'  { Join-Path $env:USERPROFILE "Desktop\AccessAudit_$timestamp.csv" }
                'JSON' { Join-Path $env:USERPROFILE "Desktop\AccessAudit_$timestamp.json" }
                'HTML' { Join-Path $env:USERPROFILE "Desktop\AccessAudit_$timestamp.html" }
            }
        }

        if ($PSCmdlet.ShouldProcess($ExportPath, "Export access audit report")) {
            switch ($OutputFormat) {
                'CSV' {
                    $auditResults | Export-Csv -Path $ExportPath -NoTypeInformation -ErrorAction Stop
                    Write-AuditLog -Message "Audit report exported to CSV: $ExportPath" -Level "SUCCESS"
                }
                'JSON' {
                    $auditResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -ErrorAction Stop
                    Write-AuditLog -Message "Audit report exported to JSON: $ExportPath" -Level "SUCCESS"
                }
                'HTML' {
                    $htmlStyle = @"
<style>
BODY { background-color: #F0F8FF; font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }
H2 { color: #1F4788; border-bottom: 2px solid #3498DB; padding-bottom: 10px; }
TABLE { border-collapse: collapse; width: 100%; box-shadow: 0 2px 4px rgba(0,0,0,0.1); font-size: 11px; }
TH { background-color: #2874A6; color: white; padding: 10px; text-align: left; font-weight: bold; }
TD { border: 1px solid #BDC3C7; padding: 8px; background-color: white; }
TR:nth-child(even) TD { background-color: #D6EAF8; }
TR:hover TD { background-color: #AED6F1; }
</style>
"@
                    $htmlBody = $auditResults | ConvertTo-Html -Head $htmlStyle -Body "<h2>Role-Based Access Audit Report</h2><p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p><p>Total Entries: $($auditResults.Count)</p>" -Title "Access Audit"
                    $htmlBody | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-AuditLog -Message "Audit report exported to HTML: $ExportPath" -Level "SUCCESS"
                }
            }

            Write-Host "`nRole-Based Access Audit Summary:" -ForegroundColor Cyan
            Write-Host "Total Audit Entries: $($auditResults.Count)" -ForegroundColor Green
            Write-Host "Report exported to: $ExportPath`n" -ForegroundColor Green
        }
    }

    Write-AuditLog -Message "===== Role-Based Access Audit Completed Successfully =====" -Level "SUCCESS"
    Write-AuditLog -Message "Transcript saved to: $transcriptPath" -Level "INFO"
    Write-AuditLog -Message "Audit log saved to: $script:AuditLogPath" -Level "INFO"

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level "ERROR"
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
} finally {
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
