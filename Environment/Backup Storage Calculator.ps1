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
        # Prompt the user for input.
        $inputVal = Read-Host $Prompt

        # If the user enters nothing, use the default value.
        if ([string]::IsNullOrWhiteSpace($inputVal)) {
            $inputVal = $Default
            Write-Host "Using default value: $inputVal" -ForegroundColor Yellow
        }

        # Try to parse the input as a double.
        $num = $null
        $valid = [double]::TryParse($inputVal, [ref]$num)
        if (-not $valid) {
            Write-Host "Invalid input. Please enter a numeric value." -ForegroundColor Red
        }
    } while (-not $valid)
    return $num
}

# Prompt the user to choose a backup strategy.
Write-Output "Choose your backup strategy:"
Write-Output "1. Full Backups Only"
Write-Output "2. Full + Incremental Backups"
Write-Output "3. Full + Differential Backups"
$backupChoice = Read-Host "Enter selection (1, 2, or 3)"

# Use a switch statement to handle each backup strategy.
switch ($backupChoice) {
    "1" {
        # Strategy 1: Full Backups Only
        Write-Host "You selected Full Backups Only." -ForegroundColor Green
        # Prompt for the number of full backups to retain.
        $numBackups = Get-NumericInput -Prompt "Enter the number of full backups to retain:" -Default 10
        # Prompt for the size of each full backup in GB.
        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB):" -Default 50
        
        # Calculate total storage requirement.
        $totalStorage = $numBackups * $fullBackupSize
        
        Write-Output ""
        Write-Output "=== Calculation Result ==="
        Write-Output "Backup Strategy: Full Backups Only"
        Write-Output "-----------------------------------------"
        Write-Output "Number of full backups retained: $numBackups"
        Write-Output "Size per full backup: $fullBackupSize GB"
        Write-Output "Total storage required: $totalStorage GB"
    }
    "2" {
        # Strategy 2: Full + Incremental Backups
        Write-Host "You selected Full + Incremental Backups." -ForegroundColor Green
        # Prompt for the number of full backup cycles to retain.
        $numCycles = Get-NumericInput -Prompt "Enter the number of full backup cycles to retain:" -Default 4
        # Prompt for the number of incremental backups per cycle.
        $numIncrementalsPerCycle = Get-NumericInput -Prompt "Enter the number of incremental backups per cycle:" -Default 6
        
        # Prompt for backup sizes.
        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB):" -Default 100
        $incrementalBackupSize = Get-NumericInput -Prompt "Enter the size of each incremental backup (GB):" -Default 10
        
        # Calculate storage for one cycle and then multiply by number of cycles.
        $cycleStorage = $fullBackupSize + ($numIncrementalsPerCycle * $incrementalBackupSize)
        $totalStorage = $numCycles * $cycleStorage
        
        Write-Output ""
        Write-Output "=== Calculation Result ==="
        Write-Output "Backup Strategy: Full + Incremental Backups"
        Write-Output "----------------------------------------------------"
        Write-Output "Full backup cycles retained: $numCycles"
        Write-Output "Incremental backups per cycle: $numIncrementalsPerCycle"
        Write-Output "Full backup size: $fullBackupSize GB"
        Write-Output "Incremental backup size: $incrementalBackupSize GB"
        Write-Output "Total storage required: $totalStorage GB"
    }
    "3" {
        # Strategy 3: Full + Differential Backups
        Write-Host "You selected Full + Differential Backups." -ForegroundColor Green
        # Prompt for the number of full backup cycles to retain.
        $numCycles = Get-NumericInput -Prompt "Enter the number of full backup cycles to retain:" -Default 4
        # Prompt for the number of differential backups per cycle.
        $numDifferentialsPerCycle = Get-NumericInput -Prompt "Enter the number of differential backups per cycle:" -Default 6
        
        # Prompt for backup sizes.
        $fullBackupSize = Get-NumericInput -Prompt "Enter the size of each full backup (GB):" -Default 120
        $differentialBackupSize = Get-NumericInput -Prompt "Enter the size of each differential backup (GB):" -Default 60
        
        # Calculate storage for one cycle and then multiply by number of cycles.
        $cycleStorage = $fullBackupSize + ($numDifferentialsPerCycle * $differentialBackupSize)
        $totalStorage = $numCycles * $cycleStorage
        
        Write-Output ""
        Write-Output "=== Calculation Result ==="
        Write-Output "Backup Strategy: Full + Differential Backups"
        Write-Output "-------------------------------------------------------"
        Write-Output "Full backup cycles retained: $numCycles"
        Write-Output "Differential backups per cycle: $numDifferentialsPerCycle"
        Write-Output "Full backup size: $fullBackupSize GB"
        Write-Output "Differential backup size: $differentialBackupSize GB"
        Write-Output "Total storage required: $totalStorage GB"
    }
    default {
        # Invalid selection handling.
        Write-Host "Invalid selection. Please run the script again and choose a valid option (1, 2, or 3)." -ForegroundColor Red
    }
}

# Wait for the user to acknowledge before closing.
Write-Output ""
Write-Host "Press any key to exit..."
$x = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
