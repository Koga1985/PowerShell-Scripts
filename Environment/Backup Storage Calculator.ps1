<#
.SYNOPSIS
    Secure Backup Storage Calculator for Fourth Estate infrastructure planning.

.DESCRIPTION
    This script calculates required backup storage based on retention policies and backup strategies.
    It supports multiple backup models with comprehensive input validation and audit logging:
      1. Full Backups Only
      2. Full + Incremental Backups
      3. Full + Differential Backups

    All calculations are logged for audit compliance and capacity planning documentation.

.NOTES
    Author:         Dewain Smith, #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

.SECURITY FEATURES
    - Requires PowerShell 5.1+ and Administrator privileges
    - Strict mode enabled for enhanced script reliability
    - Comprehensive input validation with range checking
    - Audit logging to file and Windows Event Log
    - All user inputs validated against numeric ranges
    - Protection against malicious input injection

.COMPLIANCE
    - NIST SP 800-53 Rev 5: AU-2, AU-3, AU-12 (Audit and Accountability)
    - NIST SP 800-53 Rev 5: SI-10 (Input Validation)
    - NIST SP 800-53 Rev 5: CP-9 (Information System Backup)
    - DISA STIG PowerShell Security Technical Implementation Guide
    - DoD Fourth Estate security and capacity planning requirements
    - FedRAMP security controls

    Disclaimer: Scripts are provided as-is. Review and test for your environment and compliance needs.

.EXAMPLE
    .\BackupStorageCalculator.ps1
    Follow the interactive prompts to calculate backup storage requirements.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Security Configuration
$Global:AuditLogPath = "$env:ProgramData\BackupCalculator\Logs\audit.log"
$Global:EventLogSource = "BackupStorageCalculator"
$Global:EventLogName = "Application"

# Initialize audit logging
function Initialize-AuditLog {
    try {
        $logDir = Split-Path $Global:AuditLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        # Register event source if not exists
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
    <#
    .SYNOPSIS
        Writes comprehensive audit logs to file and Windows Event Log.
    .PARAMETER Message
        The audit message to log.
    .PARAMETER Level
        Log level: INFO, WARNING, ERROR, SECURITY. Default is INFO.
    .PARAMETER Action
        The action being performed.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory=$false)]
        [string]$Action = 'Calculation'
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $computerName = $env:COMPUTERNAME

        $auditEntry = "$timestamp | $computerName | $username | $Level | $Action | $Message"

        # Write to file
        Add-Content -Path $Global:AuditLogPath -Value $auditEntry -ErrorAction SilentlyContinue

        # Write to Windows Event Log
        $eventType = switch ($Level) {
            'ERROR' { 'Error' }
            'WARNING' { 'Warning' }
            'SECURITY' { 'SuccessAudit' }
            default { 'Information' }
        }

        $eventId = switch ($Level) {
            'ERROR' { 2001 }
            'WARNING' { 2002 }
            'SECURITY' { 2003 }
            default { 2000 }
        }

        Write-EventLog -LogName $Global:EventLogName -Source $Global:EventLogSource `
            -EventId $eventId -EntryType $eventType -Message $auditEntry -ErrorAction SilentlyContinue

        # Console output with color
        $color = switch ($Level) {
            'ERROR' { 'Red' }
            'WARNING' { 'Yellow' }
            'SECURITY' { 'Cyan' }
            default { 'White' }
        }
        Write-Host "$timestamp [$Level] $Message" -ForegroundColor $color

    } catch {
        Write-Warning "Failed to write audit log: $_"
    }
}
#endregion

#region Input Validation Functions
function Get-NumericInput {
    <#
    .SYNOPSIS
        Prompts for and validates numeric input with range checking.
    .PARAMETER Prompt
        The prompt message to display to the user.
    .PARAMETER Default
        The default value if user presses Enter.
    .PARAMETER MinValue
        Minimum acceptable value (default: 0.1).
    .PARAMETER MaxValue
        Maximum acceptable value (default: 1000000).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Prompt,

        [Parameter(Mandatory=$true)]
        [ValidateRange(0.1, 1000000)]
        [double]$Default,

        [Parameter(Mandatory=$false)]
        [double]$MinValue = 0.1,

        [Parameter(Mandatory=$false)]
        [double]$MaxValue = 1000000
    )

    $attempts = 0
    $maxAttempts = 3

    do {
        $inputVal = Read-Host "$Prompt (Default: $Default, Min: $MinValue, Max: $MaxValue)"

        if ([string]::IsNullOrWhiteSpace($inputVal)) {
            $inputVal = $Default
            Write-AuditLog -Message "Using default value: $inputVal for prompt: $Prompt" -Level INFO
            return $inputVal
        }

        $num = $null
        $valid = [double]::TryParse($inputVal, [ref]$num)

        if (-not $valid) {
            $attempts++
            Write-AuditLog -Message "Invalid numeric input attempt $attempts for prompt: $Prompt" -Level WARNING
            Write-Host "ERROR: Invalid input. Please enter a numeric value." -ForegroundColor Red

            if ($attempts -ge $maxAttempts) {
                Write-AuditLog -Message "Maximum input attempts exceeded. Using default value: $Default" -Level WARNING
                return $Default
            }
        }
        elseif ($num -lt $MinValue -or $num -gt $MaxValue) {
            $attempts++
            Write-AuditLog -Message "Out of range input attempt $attempts : $num (Range: $MinValue - $MaxValue)" -Level WARNING
            Write-Host "ERROR: Value must be between $MinValue and $MaxValue." -ForegroundColor Red

            if ($attempts -ge $maxAttempts) {
                Write-AuditLog -Message "Maximum input attempts exceeded. Using default value: $Default" -Level WARNING
                return $Default
            }
            $valid = $false
        }
        else {
            Write-AuditLog -Message "Valid input received: $num for prompt: $Prompt" -Level INFO
            return $num
        }

    } while (-not $valid)
}

function Get-MenuChoice {
    <#
    .SYNOPSIS
        Prompts for and validates menu selection with injection prevention.
    .PARAMETER ValidChoices
        Array of valid choice strings (e.g., '1', '2', '3').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ValidChoices
    )

    $attempts = 0
    $maxAttempts = 3

    do {
        $choice = Read-Host "Enter selection ($(($ValidChoices -join ', ')))"

        # Sanitize input - only allow single digit or character
        if ($choice -match '^[0-9]$' -and $choice -in $ValidChoices) {
            Write-AuditLog -Message "Valid menu choice selected: $choice" -Level INFO -Action "MenuSelection"
            return $choice
        }
        else {
            $attempts++
            Write-AuditLog -Message "Invalid menu selection attempt $attempts : $choice" -Level WARNING -Action "MenuSelection"
            Write-Host "ERROR: Invalid selection. Please enter one of: $($ValidChoices -join ', ')" -ForegroundColor Red

            if ($attempts -ge $maxAttempts) {
                Write-AuditLog -Message "Maximum selection attempts exceeded. Exiting." -Level ERROR -Action "MenuSelection"
                throw "Maximum invalid selection attempts exceeded. Operation cancelled for security."
            }
        }

    } while ($true)
}
#endregion

#region Calculation Functions
function Show-CalculationResult {
    <#
    .SYNOPSIS
        Displays and logs backup storage calculation results.
    .PARAMETER Strategy
        The backup strategy used.
    .PARAMETER Details
        Hashtable of calculation details.
    .PARAMETER TotalStorage
        Total storage required in GB.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Strategy,

        [Parameter(Mandatory=$true)]
        [hashtable]$Details,

        [Parameter(Mandatory=$true)]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$TotalStorage
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  BACKUP STORAGE CALCULATION RESULT" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Backup Strategy: $Strategy" -ForegroundColor Cyan
    Write-Host "----------------------------------------"

    foreach ($key in $Details.Keys | Sort-Object) {
        Write-Host "  $key : $($Details[$key])" -ForegroundColor White
    }

    Write-Host "----------------------------------------" -ForegroundColor Green
    Write-Host "  TOTAL STORAGE REQUIRED: $TotalStorage GB" -ForegroundColor Yellow
    Write-Host "  TOTAL STORAGE REQUIRED: $([math]::Round($TotalStorage/1024, 2)) TB" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Green

    # Log the calculation result
    $detailsString = ($Details.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
    Write-AuditLog -Message "Calculation completed: Strategy=$Strategy; $detailsString; Total=$TotalStorage GB" `
        -Level SECURITY -Action "CalculationComplete"
}

function Invoke-FullBackupCalculation {
    <#
    .SYNOPSIS
        Calculates storage requirements for Full Backups Only strategy.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Starting Full Backups Only calculation" -Level INFO

    try {
        $numBackups = Get-NumericInput -Prompt "Enter the number of full backups to retain" `
            -Default 10 -MinValue 1 -MaxValue 365

        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB)" `
            -Default 50 -MinValue 0.1 -MaxValue 100000

        $totalStorage = $numBackups * $fullBackupSize

        $details = [ordered]@{
            "Number of full backups retained" = $numBackups
            "Size per full backup (GB)" = $fullBackupSize
            "Calculation" = "$numBackups backups × $fullBackupSize GB"
        }

        Show-CalculationResult -Strategy "Full Backups Only" -Details $details -TotalStorage $totalStorage

    } catch {
        Write-AuditLog -Message "Error in Full Backup calculation: $_" -Level ERROR
        throw
    }
}

function Invoke-IncrementalBackupCalculation {
    <#
    .SYNOPSIS
        Calculates storage requirements for Full + Incremental strategy.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Starting Full + Incremental Backups calculation" -Level INFO

    try {
        $numCycles = Get-NumericInput -Prompt "Enter the number of full backup cycles to retain" `
            -Default 4 -MinValue 1 -MaxValue 52

        $numIncrementalsPerCycle = Get-NumericInput -Prompt "Enter the number of incremental backups per cycle" `
            -Default 6 -MinValue 1 -MaxValue 30

        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB)" `
            -Default 100 -MinValue 0.1 -MaxValue 100000

        $incrementalBackupSize = Get-NumericInput -Prompt "Enter the size of each incremental backup (GB)" `
            -Default 10 -MinValue 0.1 -MaxValue 100000

        $cycleStorage = $fullBackupSize + ($numIncrementalsPerCycle * $incrementalBackupSize)
        $totalStorage = $numCycles * $cycleStorage

        $details = [ordered]@{
            "Full backup cycles retained" = $numCycles
            "Incremental backups per cycle" = $numIncrementalsPerCycle
            "Full backup size (GB)" = $fullBackupSize
            "Incremental backup size (GB)" = $incrementalBackupSize
            "Storage per cycle (GB)" = $cycleStorage
            "Calculation" = "$numCycles cycles × ($fullBackupSize GB + $numIncrementalsPerCycle × $incrementalBackupSize GB)"
        }

        Show-CalculationResult -Strategy "Full + Incremental Backups" -Details $details -TotalStorage $totalStorage

    } catch {
        Write-AuditLog -Message "Error in Incremental Backup calculation: $_" -Level ERROR
        throw
    }
}

function Invoke-DifferentialBackupCalculation {
    <#
    .SYNOPSIS
        Calculates storage requirements for Full + Differential strategy.
    #>
    [CmdletBinding()]
    param()

    Write-AuditLog -Message "Starting Full + Differential Backups calculation" -Level INFO

    try {
        $numCycles = Get-NumericInput -Prompt "Enter the number of full backup cycles to retain" `
            -Default 4 -MinValue 1 -MaxValue 52

        $numDifferentialsPerCycle = Get-NumericInput -Prompt "Enter the number of differential backups per cycle" `
            -Default 6 -MinValue 1 -MaxValue 30

        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB)" `
            -Default 120 -MinValue 0.1 -MaxValue 100000

        $differentialBackupSize = Get-NumericInput -Prompt "Enter the size of each differential backup (GB)" `
            -Default 60 -MinValue 0.1 -MaxValue 100000

        $cycleStorage = $fullBackupSize + ($numDifferentialsPerCycle * $differentialBackupSize)
        $totalStorage = $numCycles * $cycleStorage

        $details = [ordered]@{
            "Full backup cycles retained" = $numCycles
            "Differential backups per cycle" = $numDifferentialsPerCycle
            "Full backup size (GB)" = $fullBackupSize
            "Differential backup size (GB)" = $differentialBackupSize
            "Storage per cycle (GB)" = $cycleStorage
            "Calculation" = "$numCycles cycles × ($fullBackupSize GB + $numDifferentialsPerCycle × $differentialBackupSize GB)"
        }

        Show-CalculationResult -Strategy "Full + Differential Backups" -Details $details -TotalStorage $totalStorage

    } catch {
        Write-AuditLog -Message "Error in Differential Backup calculation: $_" -Level ERROR
        throw
    }
}
#endregion

#region Main Script
try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  BACKUP STORAGE CALCULATOR v2.0" -ForegroundColor Cyan
    Write-Host "  Fourth Estate Secure Edition" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-AuditLog -Message "Backup Storage Calculator started" -Level SECURITY -Action "SessionStart"

    # Display backup strategy options
    Write-Host "Choose your backup strategy:" -ForegroundColor Yellow
    Write-Host "  [1] Full Backups Only"
    Write-Host "  [2] Full + Incremental Backups"
    Write-Host "  [3] Full + Differential Backups"
    Write-Host ""

    # Get and validate user choice
    $backupChoice = Get-MenuChoice -ValidChoices @('1', '2', '3')

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan

    # Execute appropriate calculation based on choice
    switch ($backupChoice) {
        "1" {
            Invoke-FullBackupCalculation
        }
        "2" {
            Invoke-IncrementalBackupCalculation
        }
        "3" {
            Invoke-DifferentialBackupCalculation
        }
    }

    Write-Host ""
    Write-Host "NOTE: Add 15-20% overhead for filesystem metadata and growth." -ForegroundColor Yellow
    Write-Host ""

    Write-AuditLog -Message "Backup Storage Calculator completed successfully" -Level SECURITY -Action "SessionEnd"

} catch {
    Write-AuditLog -Message "Critical error in Backup Storage Calculator: $_" -Level ERROR -Action "SessionError"
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1

} finally {
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
#endregion
