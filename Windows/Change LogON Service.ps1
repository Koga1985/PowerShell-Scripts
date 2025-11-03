#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Updates the logon credentials for a specified service on a remote computer and restarts the service.

.DESCRIPTION
    This function, Set-ServiceAcctCreds, does the following:
      1. Connects to a remote computer using CIM and retrieves the specified service.
      2. Updates the service's logon account and password by invoking the Change method of the Win32_Service class.
      3. Stops and then starts the service to apply the new credentials.
      4. Provides comprehensive audit logging of all actions.

    NOTE: The Win32_Service Change method returns a numeric code:
          0 indicates success; non-zero values indicate error.

.PARAMETER ComputerName
    The name or IP address of the remote computer. Must be a valid hostname or IP.

.PARAMETER ServiceName
    The name of the service for which credentials should be updated.

.PARAMETER Credential
    PSCredential object containing the new service account credentials.
    Use Get-Credential to securely provide credentials.

.EXAMPLE
    $cred = Get-Credential -Message "Enter new service account credentials"
    .\Change LogON Service.ps1 -ComputerName "Server01" -ServiceName "Spooler" -Credential $cred
    Updates the Spooler service on Server01 with new credentials.

.EXAMPLE
    $cred = Get-Credential "DOMAIN\ServiceAccount"
    Set-ServiceAcctCreds -ComputerName "192.168.1.100" -ServiceName "MyService" -Credential $cred
    Updates MyService on the remote computer using the function directly.

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        October 30, 2025
    Version:        2.0
    Prerequisites:
      - PowerShell 5.1 or higher
      - Administrator privileges required
      - WinRM must be enabled on target computer
      - Appropriate permissions to modify services

.SECURITY FEATURES
    - Requires Administrator privileges via #Requires directive
    - Comprehensive audit logging to file and Windows Event Log
    - Full session transcript for compliance
    - Secure credential handling with PSCredential (no plaintext passwords)
    - Input validation for computer names and service names
    - Uses modern CIM cmdlets instead of WMI
    - Credentials cleared from memory after use

.COMPLIANCE
    - Aligns with NIST 800-53 IA-5 controls
    - Supports DISA STIG password management requirements
    - Fourth Estate infrastructure compatible
    - Full audit trail for compliance reporting
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Computer name or IP address")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9.\-]+$', ErrorMessage = "Computer name contains invalid characters")]
    [ValidateLength(1, 255)]
    [string]$ComputerName,

    [Parameter(Mandatory = $true, HelpMessage = "Service name to update")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9 _-]+$', ErrorMessage = "Service name contains invalid characters")]
    [ValidateLength(1, 256)]
    [string]$ServiceName,

    [Parameter(Mandatory = $true, HelpMessage = "New service account credentials")]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Transcript and Audit Logging
#----------------------------------------------
$transcriptPath = Join-Path $env:TEMP "ChangeServiceLogon_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -NoClobber

$script:AuditLogPath = "C:\Windows\Logs\Security\ChangeServiceLogon_Audit.log"
$script:EventSource = "ServiceLogonChange"

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
# Function: Set-ServiceAcctCreds
#----------------------------------------------
function Set-ServiceAcctCreds {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    try {
        Write-AuditLog -Message "===== Service Credential Update Started =====" -Level "INFO"
        Write-AuditLog -Message "Target Computer: $ComputerName" -Level "INFO"
        Write-AuditLog -Message "Target Service: $ServiceName" -Level "INFO"
        Write-AuditLog -Message "New Account: $($Credential.UserName)" -Level "INFO"

        # Test connectivity to remote computer
        Write-AuditLog -Message "Testing connectivity to $ComputerName..." -Level "INFO"
        try {
            $testConnection = Test-Connection -ComputerName $ComputerName -Count 2 -Quiet -ErrorAction Stop
            if (-not $testConnection) {
                throw "Cannot reach computer $ComputerName"
            }
            Write-AuditLog -Message "Successfully connected to $ComputerName." -Level "SUCCESS"
        } catch {
            Write-AuditLog -Message "Failed to connect to $ComputerName: $_" -Level "ERROR"
            throw
        }

        # Create CIM session
        Write-AuditLog -Message "Creating CIM session to $ComputerName..." -Level "INFO"
        $cimSessionParams = @{
            ComputerName = $ComputerName
            ErrorAction  = 'Stop'
        }

        $cimSession = New-CimSession @cimSessionParams
        Write-AuditLog -Message "CIM session established successfully." -Level "SUCCESS"

        # Retrieve service
        Write-AuditLog -Message "Retrieving service '$ServiceName' from $ComputerName..." -Level "INFO"

        $getCimParams = @{
            CimSession  = $cimSession
            ClassName   = 'Win32_Service'
            Filter      = "Name='$ServiceName'"
            ErrorAction = 'Stop'
        }

        $service = Get-CimInstance @getCimParams

        if (-not $service) {
            Write-AuditLog -Message "Service '$ServiceName' not found on '$ComputerName'." -Level "ERROR"
            throw "Service '$ServiceName' not found."
        }

        Write-AuditLog -Message "Service found: $($service.DisplayName)" -Level "SUCCESS"
        Write-AuditLog -Message "Current Status: $($service.State)" -Level "INFO"
        Write-AuditLog -Message "Current StartMode: $($service.StartMode)" -Level "INFO"
        Write-AuditLog -Message "Current StartName: $($service.StartName)" -Level "INFO"

        if ($PSCmdlet.ShouldProcess($ServiceName, "Update logon credentials on $ComputerName")) {
            # Extract username and password from PSCredential
            $newUsername = $Credential.UserName
            $newPassword = $Credential.GetNetworkCredential().Password

            # Update service credentials using CIM method
            Write-AuditLog -Message "Updating service credentials..." -Level "INFO"

            $changeParams = @{
                StartName     = $newUsername
                StartPassword = $newPassword
            }

            $result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments $changeParams -ErrorAction Stop

            # Check return value
            if ($result.ReturnValue -eq 0) {
                Write-AuditLog -Message "Service credentials updated successfully." -Level "SUCCESS"

                # Restart the service to apply changes
                Write-AuditLog -Message "Restarting service '$ServiceName'..." -Level "INFO"

                try {
                    # Stop service
                    $stopResult = Invoke-CimMethod -InputObject $service -MethodName StopService -ErrorAction Stop
                    if ($stopResult.ReturnValue -eq 0) {
                        Write-AuditLog -Message "Service stopped successfully." -Level "SUCCESS"
                    } else {
                        Write-AuditLog -Message "Service stop returned code: $($stopResult.ReturnValue)" -Level "WARNING"
                    }

                    # Wait for service to stop
                    Start-Sleep -Seconds 2

                    # Refresh service object
                    $service = Get-CimInstance @getCimParams

                    # Start service
                    $startResult = Invoke-CimMethod -InputObject $service -MethodName StartService -ErrorAction Stop
                    if ($startResult.ReturnValue -eq 0) {
                        Write-AuditLog -Message "Service started successfully." -Level "SUCCESS"
                    } else {
                        Write-AuditLog -Message "Service start returned code: $($startResult.ReturnValue)" -Level "WARNING"
                    }

                    # Verify service is running
                    Start-Sleep -Seconds 2
                    $service = Get-CimInstance @getCimParams
                    Write-AuditLog -Message "Service current state: $($service.State)" -Level "INFO"

                } catch {
                    Write-AuditLog -Message "Error restarting service: $_" -Level "ERROR"
                    throw
                }

            } else {
                Write-AuditLog -Message "Failed to update credentials. Return code: $($result.ReturnValue)" -Level "ERROR"
                throw "Service credential update failed with return code: $($result.ReturnValue)"
            }

            Write-AuditLog -Message "===== Service Credential Update Completed Successfully =====" -Level "SUCCESS"
        }

    } catch {
        Write-AuditLog -Message "ERROR in Set-ServiceAcctCreds: $_" -Level "ERROR"
        throw
    } finally {
        # Clean up CIM session
        if ($cimSession) {
            Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
            Write-AuditLog -Message "CIM session closed." -Level "INFO"
        }

        # Clear sensitive data from memory
        if ($newPassword) {
            Remove-Variable -Name newPassword -Force -ErrorAction SilentlyContinue
        }
    }
}

#----------------------------------------------
# Main Script Execution
#----------------------------------------------
try {
    # Call the function with provided parameters
    $functionParams = @{
        ComputerName = $ComputerName
        ServiceName  = $ServiceName
        Credential   = $Credential
    }

    Set-ServiceAcctCreds @functionParams

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

    # Clear all sensitive data from memory
    if ($Credential) {
        Remove-Variable -Name Credential -Force -ErrorAction SilentlyContinue
    }
}
