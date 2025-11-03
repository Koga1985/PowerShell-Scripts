#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Adds users listed in a CSV file to a specified Active Directory group.

.DESCRIPTION
    This script performs the following actions:
      1. Imports the ActiveDirectory module.
      2. Imports a CSV file containing user information with proper validation.
      3. Iterates through each user from the CSV and attempts to add the user (using the "UserName" field)
         to a target AD group.
      4. Logs successes and errors for each add-operation with comprehensive auditing.

.PARAMETER CsvPath
    The path to the CSV file containing user information. Must have a "UserName" column.

.PARAMETER GroupName
    The name of the target Active Directory group to which users will be added.

.PARAMETER Credential
    Optional PSCredential object for authentication to Active Directory.

.EXAMPLE
    .\Add Users to Group.ps1 -CsvPath "C:\Scripts\Users.csv" -GroupName "TestGroup1"
    Adds all users from the CSV file to TestGroup1.

.EXAMPLE
    $cred = Get-Credential
    .\Add Users to Group.ps1 -CsvPath "C:\Scripts\Users.csv" -GroupName "TestGroup1" -Credential $cred
    Adds users using alternate credentials.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - ActiveDirectory PowerShell module must be installed
      - Appropriate permissions to modify Active Directory group memberships
      - CSV file must exist with a header column named "UserName"

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Input validation and path sanitization
    - Secure credential handling with PSCredential
    - Validates CSV structure before processing

.COMPLIANCE
    - Aligns with NIST 800-53 AC-2 controls
    - Supports DISA STIG access control requirements
    - Fourth Estate infrastructure compatible
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Path to CSV file containing users")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [ValidatePattern('\.csv$', ErrorMessage = "File must have .csv extension")]
    [string]$CsvPath,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the AD group")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9 _-]+$', ErrorMessage = "Group name contains invalid characters")]
    [ValidateLength(1, 64)]
    [string]$GroupName,

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
$transcriptPath = Join-Path $env:TEMP "AddUsersToGroup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\AddUsersToGroup_Audit.log"
$script:EventSource = "ADGroupMgmt"

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
# Input Validation Function
#----------------------------------------------
function Test-SecurePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Check for dangerous patterns
    $dangerousPatterns = @('\$\(', '`', ';', '&', '|', '<', '>')
    foreach ($pattern in $dangerousPatterns) {
        if ($Path -match [regex]::Escape($pattern)) {
            throw "Path contains potentially dangerous characters"
        }
    }

    # Resolve to absolute path
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
    return $resolvedPath.Path
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
try {
    Write-AuditLog -Message "===== Add Users to Group Script Started =====" -Level "INFO"
    Write-AuditLog -Message "CSV Path: $CsvPath" -Level "INFO"
    Write-AuditLog -Message "Target Group: $GroupName" -Level "INFO"

    # Validate and resolve CSV path
    $resolvedCsvPath = Test-SecurePath -Path $CsvPath
    Write-AuditLog -Message "Resolved CSV path: $resolvedCsvPath" -Level "INFO"

    # Import ActiveDirectory Module
    Write-AuditLog -Message "Importing ActiveDirectory module..." -Level "INFO"
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-AuditLog -Message "ActiveDirectory module imported successfully." -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Failed to import ActiveDirectory module: $_" -Level "ERROR"
        throw
    }

    # Verify target group exists
    Write-AuditLog -Message "Verifying target group '$GroupName' exists..." -Level "INFO"
    try {
        $getGroupParams = @{
            Identity    = $GroupName
            ErrorAction = 'Stop'
        }
        if ($Credential) {
            $getGroupParams['Credential'] = $Credential
        }

        $targetGroup = Get-ADGroup @getGroupParams
        Write-AuditLog -Message "Group verified: $($targetGroup.DistinguishedName)" -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Target group '$GroupName' not found: $_" -Level "ERROR"
        throw
    }

    # Import CSV File
    Write-AuditLog -Message "Importing CSV file..." -Level "INFO"
    try {
        $users = Import-Csv -Path $resolvedCsvPath -ErrorAction Stop

        if (-not $users) {
            Write-AuditLog -Message "CSV file is empty or invalid." -Level "ERROR"
            throw "CSV file contains no data."
        }

        # Validate CSV structure
        $requiredColumns = @('UserName')
        $csvColumns = $users[0].PSObject.Properties.Name

        foreach ($column in $requiredColumns) {
            if ($column -notin $csvColumns) {
                Write-AuditLog -Message "CSV missing required column: $column" -Level "ERROR"
                throw "CSV file must contain column: $column"
            }
        }

        Write-AuditLog -Message "CSV imported successfully. Total records: $($users.Count)" -Level "SUCCESS"
    } catch {
        Write-AuditLog -Message "Error importing CSV file: $_" -Level "ERROR"
        throw
    }

    # Process Each User
    $successCount = 0
    $skipCount = 0
    $failureCount = 0

    foreach ($userRecord in $users) {
        $userName = $userRecord.UserName

        if ([string]::IsNullOrWhiteSpace($userName)) {
            Write-AuditLog -Message "Skipping empty username entry." -Level "WARNING"
            $skipCount++
            continue
        }

        # Validate username format
        if ($userName -notmatch '^[a-zA-Z0-9._-]+$') {
            Write-AuditLog -Message "Skipping invalid username format: $userName" -Level "WARNING"
            $skipCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess($userName, "Add user to group '$GroupName'")) {
            Write-AuditLog -Message "Processing user: $userName" -Level "INFO"

            try {
                # Verify user exists
                $getUserParams = @{
                    Identity    = $userName
                    ErrorAction = 'Stop'
                }
                if ($Credential) {
                    $getUserParams['Credential'] = $Credential
                }

                $adUser = Get-ADUser @getUserParams

                if ($adUser) {
                    # Check if user is already a member
                    $getMemberParams = @{
                        Identity    = $GroupName
                        ErrorAction = 'Stop'
                    }
                    if ($Credential) {
                        $getMemberParams['Credential'] = $Credential
                    }

                    $groupMembers = Get-ADGroupMember @getMemberParams | Select-Object -ExpandProperty SamAccountName

                    if ($userName -in $groupMembers) {
                        Write-AuditLog -Message "User '$userName' is already a member of '$GroupName'. Skipping." -Level "INFO"
                        $skipCount++
                    } else {
                        # Add user to group
                        $addMemberParams = @{
                            Identity    = $GroupName
                            Members     = $adUser
                            ErrorAction = 'Stop'
                        }
                        if ($Credential) {
                            $addMemberParams['Credential'] = $Credential
                        }

                        Add-ADGroupMember @addMemberParams
                        Write-AuditLog -Message "SUCCESS: User '$userName' added to group '$GroupName'." -Level "SUCCESS"
                        $successCount++
                    }
                } else {
                    Write-AuditLog -Message "User '$userName' not found in Active Directory. Skipping." -Level "WARNING"
                    $skipCount++
                }
            } catch {
                Write-AuditLog -Message "ERROR: Failed to add user '$userName' to group '$GroupName': $_" -Level "ERROR"
                $failureCount++
            }
        }
    }

    # Summary
    Write-AuditLog -Message "===== Processing Summary =====" -Level "INFO"
    Write-AuditLog -Message "Total records processed: $($users.Count)" -Level "INFO"
    Write-AuditLog -Message "Successful additions: $successCount" -Level "SUCCESS"
    Write-AuditLog -Message "Skipped: $skipCount" -Level "INFO"
    Write-AuditLog -Message "Failures: $failureCount" -Level "INFO"

    Write-AuditLog -Message "===== Add Users to Group Script Completed Successfully =====" -Level "SUCCESS"
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
    if (Test-Path variable:users) {
        Remove-Variable -Name users -Force -ErrorAction SilentlyContinue
    }
}
