<#
.SYNOPSIS
    Adds users listed in a CSV file to a specified Active Directory group.

.DESCRIPTION
    This script performs the following actions:
      1. Imports the ActiveDirectory module.
      2. Imports a CSV file containing user information.
      3. Iterates through each user from the CSV and attempts to add the user (using the "UserName" field)
         to a target AD group (hardcoded to "TestGroup1" in this example).
      4. Logs successes and errors for each add-operation.

    Prerequisites:
      - The ActiveDirectory PowerShell module must be installed.
      - You must have the appropriate permissions to modify Active Directory group memberships.
      - The CSV file (e.g., "C:\Scripts\Users.csv") must exist and have a header column named "UserName".

.EXAMPLE
    PS C:\> .\AddUsersToGroup.ps1
    The script will prompt for no additional input since the CSV file path and group are preconfigured.

.NOTES
    Author: Your Name or Organization
    Created: 2025-04-14
    Version: 1.0
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message with a timestamp and a specified log level.
    
    .PARAMETER Message
        The log message to output.
    
    .PARAMETER Level
        The severity level (e.g., "INFO" or "ERROR"). Default value is "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# 1. Import ActiveDirectory Module
#----------------------------------------------
Write-Log -Message "Importing ActiveDirectory module..."
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log -Message "ActiveDirectory module imported successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error importing ActiveDirectory module: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 2. Define Variables
#----------------------------------------------
$csvPath = "C:\Scripts\Users.csv"      # Path to the CSV file containing user information
$targetGroup = "TestGroup1"            # The name of the target AD group to which users will be added

#----------------------------------------------
# 3. Validate CSV File Existence
#----------------------------------------------
if (-not (Test-Path -Path $csvPath)) {
    Write-Log -Message "Error: CSV file not found at '$csvPath'" -Level "ERROR"
    exit
}

#----------------------------------------------
# 4. Import the CSV File
#----------------------------------------------
Write-Log -Message "Importing CSV file from '$csvPath'..."
try {
    $users = Import-Csv -Path $csvPath -ErrorAction Stop
    Write-Log -Message "Successfully imported CSV file. Total records: $($users.Count)" -Level "INFO"
} catch {
    Write-Log -Message "Error importing CSV file: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 5. Add Each User to the Target Group
#----------------------------------------------
foreach ($userRecord in $users) {
    $userName = $userRecord.UserName
    Write-Log -Message "Attempting to add user '$userName' to group '$targetGroup'..."
    
    try {
        Add-ADGroupMember -Identity $targetGroup -Members $userName -ErrorAction Stop
        Write-Log -Message "User '$userName' added to group '$targetGroup' successfully." -Level "INFO"
    } catch {
        Write-Log -Message "Error adding user '$userName' to group '$targetGroup': $_" -Level "ERROR"
    }
}

Write-Log -Message "User addition process completed." -Level "INFO"
