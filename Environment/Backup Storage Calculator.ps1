<#
.SYNOPSIS
    Backup Storage Calculator Script

.DESCRIPTION
    This script calculates required backup storage based on retention policies and backup strategies. It supports:
      1. Full Backups Only
      2. Full + Incremental Backups
      3. Full + Differential Backups
    Prompts for parameters and outputs total storage required in GB.

.NOTES
    Author: Dewain Smith, #TheBeardedEngineer
    Updated: 2025-08-20
    Version: 1.1
    Usage: Run in PowerShell console. Follow prompts.
    Compliance: NIST SP 800-53, STIG PowerShell Security Requirements
    Security: Input validation, logging, no hardcoded credentials, least privilege
    Disclaimer: This script is provided as-is. Review for your environment and compliance needs.
#>


# Display a welcome message.
Write-Output "=== Backup Storage Calculator ==="
Write-Output "NIST & STIG-aligned. Ensure script is run with least privilege."
Write-Output ""


# Function: Write-Log (NIST/STIG: Logging/Auditing)
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

# Function: Get-NumericInput (NIST/STIG: Input Validation)
function Get-NumericInput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,
        [Parameter(Mandatory=$true)]
        [double]$Default
    )
    do {
        $inputVal = Read-Host "$Prompt (Default: $Default)"
        if ([string]::IsNullOrWhiteSpace($inputVal)) {
            $inputVal = $Default
            Write-Log -Message "Using default value: $inputVal" -Level "WARNING"
        }
        $num = $null
        $valid = [double]::TryParse($inputVal, [ref]$num)
        if (-not $valid) {
            Write-Log -Message "Invalid input. Please enter a numeric value." -Level "ERROR"
        }
    } while (-not $valid)
    return $num
}

# Function: Show-CalculationResult
function Show-CalculationResult {
    param(
        [string]$Strategy,
        [hashtable]$Details,
        [double]$TotalStorage
    )
    Write-Output ""
    Write-Output "=== Calculation Result ==="
    Write-Output "Backup Strategy: $Strategy"
    Write-Output ("-" * 50)
    foreach ($key in $Details.Keys) {
        Write-Output "$key: $($Details[$key])"
    }
    Write-Output "Total storage required: $TotalStorage GB"
    Write-Log -Message "Calculation completed for strategy: $Strategy" -Level "INFO"
}



# Prompt the user to choose a backup strategy with validation
do {
    Write-Output "Choose your backup strategy:"
    Write-Output "1. Full Backups Only"
    Write-Output "2. Full + Incremental Backups"
    Write-Output "3. Full + Differential Backups"
    $backupChoice = Read-Host "Enter selection (1, 2, or 3)"
    $validChoice = $backupChoice -in @('1','2','3')
    if (-not $validChoice) {
        Write-Log -Message "Invalid selection. Please enter 1, 2, or 3." -Level "ERROR"
    }
} while (-not $validChoice)

# Use a switch statement to handle each backup strategy.
switch ($backupChoice) {
    "1" {
        Write-Log -Message "User selected Full Backups Only." -Level "INFO"
        $numBackups = Get-NumericInput -Prompt "Enter the number of full backups to retain" -Default 10
        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB)" -Default 50
        $totalStorage = $numBackups * $fullBackupSize
        $details = @{ "Number of full backups retained" = $numBackups; "Size per full backup (GB)" = $fullBackupSize }
        Show-CalculationResult -Strategy "Full Backups Only" -Details $details -TotalStorage $totalStorage
    }
    "2" {
        Write-Log -Message "User selected Full + Incremental Backups." -Level "INFO"
        $numCycles = Get-NumericInput -Prompt "Enter the number of full backup cycles to retain" -Default 4
        $numIncrementalsPerCycle = Get-NumericInput -Prompt "Enter the number of incremental backups per cycle" -Default 6
        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB)" -Default 100
        $incrementalBackupSize = Get-NumericInput -Prompt "Enter the size of each incremental backup (GB)" -Default 10
        $cycleStorage = $fullBackupSize + ($numIncrementalsPerCycle * $incrementalBackupSize)
        $totalStorage = $numCycles * $cycleStorage
        $details = @{ "Full backup cycles retained" = $numCycles; "Incremental backups per cycle" = $numIncrementalsPerCycle; "Full backup size (GB)" = $fullBackupSize; "Incremental backup size (GB)" = $incrementalBackupSize }
        Show-CalculationResult -Strategy "Full + Incremental Backups" -Details $details -TotalStorage $totalStorage
    }
    "3" {
        Write-Log -Message "User selected Full + Differential Backups." -Level "INFO"
        $numCycles = Get-NumericInput -Prompt "Enter the number of full backup cycles to retain" -Default 4
        $numDifferentialsPerCycle = Get-NumericInput -Prompt "Enter the number of differential backups per cycle" -Default 6
        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB)" -Default 120
        $differentialBackupSize = Get-NumericInput -Prompt "Enter the size of each differential backup (GB)" -Default 60
        $cycleStorage = $fullBackupSize + ($numDifferentialsPerCycle * $differentialBackupSize)
        $totalStorage = $numCycles * $cycleStorage
        $details = @{ "Full backup cycles retained" = $numCycles; "Differential backups per cycle" = $numDifferentialsPerCycle; "Full backup size (GB)" = $fullBackupSize; "Differential backup size (GB)" = $differentialBackupSize }
        Show-CalculationResult -Strategy "Full + Differential Backups" -Details $details -TotalStorage $totalStorage
    }
}



# Show summary and wait for user to exit
Write-Output ""
Write-Log -Message "Calculation complete. Press any key to exit..." -Level "INFO"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
