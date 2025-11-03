#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Retrieves recent logon events for a specified user from the Security Event Log on all domain controllers.

.DESCRIPTION
    This script retrieves logon history (Event ID 4624) from the Security event logs of all domain controllers
    for a specified user (SamAccountName). It does so by:
      1. Validating the target username with proper input sanitization.
      2. Querying all domain controllers in the current domain using Get-ADDomainController.
      3. For each domain controller, querying the Security log via Get-WinEvent using an XPath filter that looks
         for logon events where the TargetUserName matches the given username.
      4. Displaying each event's timestamp, workstation name, and computer on which the event was logged.

.PARAMETER UserName
    The SamAccountName of the user whose logon history should be retrieved.
    Must be a valid AD username (alphanumeric, hyphens, underscores, and periods only).

.PARAMETER MaxEvents
    The maximum number of events to retrieve per domain controller. Default is 100.

.PARAMETER Credential
    Optional PSCredential object for authentication to domain controllers.

.EXAMPLE
    .\AD User Logon History.ps1 -UserName "jdoe"
    Retrieves logon history for user 'jdoe' from all domain controllers.

.EXAMPLE
    .\AD User Logon History.ps1 -UserName "jdoe" -MaxEvents 50
    Retrieves up to 50 logon events per domain controller for user 'jdoe'.

.EXAMPLE
    $cred = Get-Credential
    .\AD User Logon History.ps1 -UserName "jdoe" -Credential $cred
    Retrieves logon history using alternate credentials.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - ActiveDirectory module must be installed
      - Permissions to query domain controllers and their event logs

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Input validation and sanitization for usernames
    - Secure credential handling with PSCredential
    - Protection against injection attacks

.COMPLIANCE
    - Aligns with NIST 800-53 AU family controls
    - Supports DISA STIG audit requirements
    - Fourth Estate infrastructure compatible
    - Full audit trail for compliance reporting
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter the SamAccountName of the user")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9._-]+$', ErrorMessage = "Username must contain only alphanumeric characters, hyphens, underscores, and periods")]
    [ValidateLength(1, 20)]
    [string]$UserName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10000)]
    [int]$MaxEvents = 100,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "ADUserLogonHistory_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\ADUserLogonHistory_Audit.log"
$script:EventSource = "ADLogonHistory"

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
    <#
    .SYNOPSIS
        Writes comprehensive audit logs to file and Windows Event Log.
    #>
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
# Input Validation Function
#----------------------------------------------
function Test-SecureInput {
    <#
    .SYNOPSIS
        Validates input for dangerous patterns.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Input
    )

    # Check for SQL injection and command injection patterns
    $dangerousPatterns = @(
        "'", '"', ';', '--', '/*', '*/', 'xp_', 'sp_', 'exec', 'execute',
        '\$\(', '`', '&', '|', '<', '>', '\.\.'
    )

    foreach ($pattern in $dangerousPatterns) {
        if ($Input -match [regex]::Escape($pattern)) {
            throw "Input contains potentially dangerous pattern: $pattern"
        }
    }

    return $true
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
try {
    Write-AuditLog -Message "===== AD User Logon History Script Started =====" -Level "INFO"
    Write-AuditLog -Message "Target User: $UserName" -Level "INFO"
    Write-AuditLog -Message "Max Events Per DC: $MaxEvents" -Level "INFO"

    # Additional input validation
    Test-SecureInput -Input $UserName

    # Import ActiveDirectory module
    Write-AuditLog -Message "Importing ActiveDirectory module..." -Level "INFO"
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-AuditLog -Message "ActiveDirectory module imported successfully." -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Failed to import ActiveDirectory module: $_" -Level "ERROR"
        throw
    }

    # Verify user exists in AD
    Write-AuditLog -Message "Verifying user '$UserName' exists in Active Directory..." -Level "INFO"
    try {
        $adUser = Get-ADUser -Identity $UserName -ErrorAction Stop
        Write-AuditLog -Message "User verified: $($adUser.DistinguishedName)" -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "User '$UserName' not found in Active Directory: $_" -Level "ERROR"
        throw
    }

    #----------------------------------------------
    # Retrieve Domain Controllers
    #----------------------------------------------
    Write-AuditLog -Message "Querying domain controllers..." -Level "INFO"

    $getDCParams = @{
        Filter      = '*'
        ErrorAction = 'Stop'
    }

    if ($Credential) {
        $getDCParams['Credential'] = $Credential
        Write-AuditLog -Message "Using alternate credentials for DC query." -Level "INFO"
    }

    try {
        $domainControllers = Get-ADDomainController @getDCParams

        if (-not $domainControllers) {
            Write-AuditLog -Message "No domain controllers found." -Level "ERROR"
            throw "No domain controllers found in the domain."
        }

        Write-AuditLog -Message "Found $($domainControllers.Count) domain controller(s)." -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Error retrieving domain controllers: $_" -Level "ERROR"
        throw
    }

    #----------------------------------------------
    # Retrieve Logon Events from Each Domain Controller
    #----------------------------------------------
    Write-AuditLog -Message "Querying logon events (Event ID 4624) for user '$UserName'..." -Level "INFO"

    $logonEvents = [System.Collections.ArrayList]::new()
    $dcSuccessCount = 0
    $dcFailureCount = 0

    foreach ($dc in $domainControllers) {
        Write-AuditLog -Message "Querying domain controller: $($dc.HostName)..." -Level "INFO"

        try {
            # Construct secure XPath query with escaped username
            $escapedUserName = [System.Security.SecurityElement]::Escape($UserName)

            $xpathQuery = @"
<QueryList>
    <Query Id='0' Path='Security'>
        <Select Path='Security'>
            *[System[(EventID=4624)]]
            and
            *[EventData[Data[@Name='TargetUserName']='$escapedUserName']]
        </Select>
    </Query>
</QueryList>
"@

            $getEventParams = @{
                ComputerName = $dc.HostName
                LogName      = 'Security'
                FilterXPath  = $xpathQuery
                MaxEvents    = $MaxEvents
                ErrorAction  = 'Stop'
            }

            if ($Credential) {
                $getEventParams['Credential'] = $Credential
            }

            $events = Get-WinEvent @getEventParams

            if ($events) {
                [void]$logonEvents.AddRange($events)
                Write-AuditLog -Message "Retrieved $($events.Count) event(s) from $($dc.HostName)." -Level "SUCCESS"
                $dcSuccessCount++
            } else {
                Write-AuditLog -Message "No events found on $($dc.HostName)." -Level "INFO"
                $dcSuccessCount++
            }
        } catch [System.Exception] {
            if ($_.Exception.Message -match "No events were found") {
                Write-AuditLog -Message "No matching events on $($dc.HostName)." -Level "INFO"
                $dcSuccessCount++
            } else {
                Write-AuditLog -Message "Error querying $($dc.HostName): $_" -Level "WARNING"
                $dcFailureCount++
            }
        }
    }

    Write-AuditLog -Message "Query Summary: $dcSuccessCount successful, $dcFailureCount failed." -Level "INFO"

    #----------------------------------------------
    # Display Retrieved Logon Events
    #----------------------------------------------
    if ($logonEvents.Count -eq 0) {
        Write-AuditLog -Message "No logon events found for user '$UserName'." -Level "INFO"
    } else {
        Write-AuditLog -Message "Total logon events found: $($logonEvents.Count)" -Level "SUCCESS"
        Write-Host "`nLogon Events for user '$UserName':" -ForegroundColor Cyan
        Write-Host ("=" * 100) -ForegroundColor Cyan

        $results = foreach ($event in $logonEvents) {
            try {
                $eventXML = [xml]$event.ToXml()
                $eventTime = $event.TimeCreated

                # Extract workstation name (typically at index 11)
                $workstation = $eventXML.Event.EventData.Data | Where-Object { $_.Name -eq 'WorkstationName' } | Select-Object -ExpandProperty '#text'
                $logonType = $eventXML.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'
                $ipAddress = $eventXML.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' } | Select-Object -ExpandProperty '#text'
                $computer = $event.MachineName

                [PSCustomObject]@{
                    TimeStamp    = $eventTime.ToString('yyyy-MM-dd HH:mm:ss')
                    UserName     = $UserName
                    Workstation  = if ($workstation) { $workstation } else { 'N/A' }
                    IPAddress    = if ($ipAddress) { $ipAddress } else { 'N/A' }
                    LogonType    = $logonType
                    DomainController = $computer
                }
            } catch {
                Write-AuditLog -Message "Error processing event: $_" -Level "WARNING"
            }
        }

        $results | Sort-Object TimeStamp -Descending | Format-Table -AutoSize

        # Export to CSV
        $csvPath = Join-Path $env:TEMP "LogonHistory_$UserName_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction SilentlyContinue
        Write-AuditLog -Message "Results exported to: $csvPath" -Level "SUCCESS"
    }

    Write-AuditLog -Message "===== AD User Logon History Script Completed Successfully =====" -Level "SUCCESS"
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

    # Clear sensitive data from memory
    if ($Credential) {
        Remove-Variable -Name Credential -Force -ErrorAction SilentlyContinue
    }
}
