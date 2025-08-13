<#
.SYNOPSIS
    Backup Storage Calculator Script

.DESCRIPTION
    This script is an all-around backup storage calculator. It computes the required storage based on 
    different retention policies and backup strategies. Users can choose between:
      1. Full Backups Only
      2. Full + Incremental Backups
      3. Full + Differential Backups
    The script prompts for the necessary parameters (e.g., number of backups to retain, backup sizes, etc.)
    and outputs the calculated total storage requirement in GB.

.NOTES
    Author: Dewain Smith, #TheBeardedEngineer
    Date: $(Get-Date -Format "yyyy-MM-dd")
    Version: 1.0
    Usage: Run this script in a PowerShell console. Follow the on-screen prompts.
#>

# Clear the screen to improve readability.
Clear-Host

# Display a welcome message.
Write-Output "=== Backup Storage Calculator ==="
Write-Output ""

# Function: Get-NumericInput
# This function prompts the user for a numeric input and validates that the input is numeric.
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
            Write-Host "Using default value: $inputVal" -ForegroundColor Yellow
        }
        $num = $null
        $valid = [double]::TryParse($inputVal, [ref]$num)
        if (-not $valid) {
            Write-Host "Invalid input. Please enter a numeric value." -ForegroundColor Red
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
        Write-Host "Invalid selection. Please enter 1, 2, or 3." -ForegroundColor Red
    }
} while (-not $validChoice)

# Use a switch statement to handle each backup strategy.
switch ($backupChoice) {
    "1" {
        Write-Host "You selected Full Backups Only." -ForegroundColor Green
        $numBackups = Get-NumericInput -Prompt "Enter the number of full backups to retain" -Default 10
        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB)" -Default 50
        $totalStorage = $numBackups * $fullBackupSize
        $details = @{ "Number of full backups retained" = $numBackups; "Size per full backup (GB)" = $fullBackupSize }
        Show-CalculationResult -Strategy "Full Backups Only" -Details $details -TotalStorage $totalStorage
    }
    "2" {
        Write-Host "You selected Full + Incremental Backups." -ForegroundColor Green
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
        Write-Host "You selected Full + Differential Backups." -ForegroundColor Green
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
Write-Host "Calculation complete. Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
