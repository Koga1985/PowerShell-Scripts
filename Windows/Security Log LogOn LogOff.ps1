<#
.SYNOPSIS
    Retrieves logon and logoff events from a specified computer's Security event log and outputs the results.

.DESCRIPTION
    This script performs the following actions:
      1. Creates a DataTable to capture logon/logoff activity with columns for Date, Type, Status, User, and IPAddress.
      2. Prompts the user for:
          - The target computer name or IP (defaults to local if blank).
          - The start date (defaults to 1/1/2000 if blank).
          - The end date (defaults to the current date/time if blank).
          - Whether to print only failed logins.
          - The desired output type (Table, GridView, HTML, or List).
      3. Retrieves Security event log entries from the target computer within the specified date range.
      4. Depending on the user's choice, filters events:
          - If "only failed logins" is chosen, only events with failure (EventID 4625) are processed.
          - Otherwise, it processes both successful (4624) and failed (4625) logon events, as well as logoffs (4647).
      5. Populates the DataTable with the relevant event data.
      6. Outputs the data in the selected format:
          - Table: Uses Format-Table.
          - GridView: Uses Out-GridView.
          - HTML: Converts the table to HTML with custom styling.
          - Default (List): Outputs the raw DataTable object.

.PARAMETER None
    This script runs interactively; all required inputs are requested from the user.

.EXAMPLE
    PS C:\> .\Get-LogonActivity.ps1
    Follow prompts to enter the computer name, start and end dates, filtering and output options.

.NOTES
    Author: Your Name or Organization
    Date: 2025-04-14
    Version: 1.0
    Prerequisites:
      - Administrative privileges.
      - Access to the Security event log on the target computer.
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a timestamped log message with a specified severity level.
    
    .PARAMETER Message
        The message text.
    
    .PARAMETER Level
        The severity level, e.g., "INFO", "WARNING", or "ERROR". Default is "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

Write-Log -Message "Starting Logon/Logoff Activity Report script." -Level "INFO"

#----------------------------------------------
# 1. Create a DataTable for Logon/Logoff Activity
#----------------------------------------------
try {
    Write-Log -Message "Creating DataTable to store logon/logoff events..."
    $LogonActivityTable = New-Object System.Data.DataTable "Logon/Logoff Activity"
    
    # Define columns for date, type, status, user, and IP address
    $colDate = New-Object System.Data.DataColumn "Date", ([string])
    $colType = New-Object System.Data.DataColumn "Type", ([string])
    $colStatus = New-Object System.Data.DataColumn "Status", ([string])
    $colUser = New-Object System.Data.DataColumn "User", ([string])
    $colIPAddress = New-Object System.Data.DataColumn "IPAddress", ([string])
    
    # Add columns to the DataTable
    $LogonActivityTable.Columns.Add($colDate)   | Out-Null
    $LogonActivityTable.Columns.Add($colType)   | Out-Null
    $LogonActivityTable.Columns.Add($colStatus) | Out-Null
    $LogonActivityTable.Columns.Add($colUser)   | Out-Null
    $LogonActivityTable.Columns.Add($colIPAddress) | Out-Null

    Write-Log -Message "DataTable created successfully." -Level "INFO"
} catch {
    Write-Log -Message "Error creating DataTable: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 2. Prompt for User Input Parameters
#----------------------------------------------
# Prompt for the target computer name; default to local if blank.
$hostname = Read-Host "Enter the IP or hostname of the computer you wish to scan (Leave blank for local)"
if ([string]::IsNullOrWhiteSpace($hostname)) {
    $hostname = $env:COMPUTERNAME
    Write-Log -Message "No hostname provided. Defaulting to local machine: $hostname." -Level "INFO"
} else {
    Write-Log -Message "Scanning computer: $hostname." -Level "INFO"
}

# Prompt for the start date for scanning; default to January 1, 2000 if left blank.
$startInput = Read-Host "Enter the start date to scan from (MM/DD/YYYY, default 1/1/2000)"
if ([string]::IsNullOrWhiteSpace($startInput)) {
    $startInput = "1/1/2000"
    Write-Log -Message "No start date provided. Defaulting to 1/1/2000." -Level "INFO"
}
try {
    $startDate = Get-Date $startInput -ErrorAction Stop
    Write-Log -Message "Start date set to: $startDate." -Level "INFO"
} catch {
    Write-Log -Message "Invalid start date format. Error: $_" -Level "ERROR"
    exit
}

# Prompt for the end date for scanning; default to current date/time if left blank.
$endInput = Read-Host "Enter the end date to scan to (MM/DD/YYYY, default current time)"
if ([string]::IsNullOrWhiteSpace($endInput)) {
    $endDate = Get-Date
    Write-Log -Message "No end date provided. Defaulting to current date and time: $endDate." -Level "INFO"
} else {
    try {
        $endDate = Get-Date $endInput -ErrorAction Stop
        Write-Log -Message "End date set to: $endDate." -Level "INFO"
    } catch {
        Write-Log -Message "Invalid end date format. Error: $_" -Level "ERROR"
        exit
    }
}

# Prompt whether to print only failed logins; default to No.
$scope = Read-Host "Print only failed logins? (Y/N, default N)"
if ([string]::IsNullOrWhiteSpace($scope)) {
    $scope = "N"
}
Write-Log -Message "Filter failed logins only: $scope" -Level "INFO"

# Prompt for output type: Table, GridView, HTML, or List.
$output = Read-Host "Output Type ((T)able, (G)ridview, (H)TML, default List)"
if ([string]::IsNullOrWhiteSpace($output)) {
    $output = "List"
}
Write-Log -Message "Selected output type: $output" -Level "INFO"

# Display the selected parameters for confirmation.
Write-Host "`nSelected Parameters:"
Write-Host "Hostname: $hostname"
Write-Host "Start Date: $startDate"
Write-Host "End Date: $endDate"
Write-Host "Print only Failed Logins: $scope"
Write-Host "Output Type: $output"
Write-Host ""

#----------------------------------------------
# 3. Retrieve the Event Log Data from the Target Computer
#----------------------------------------------
Write-Log -Message "Querying Security event log on $hostname from $startDate to $endDate..." -Level "INFO"
try {
    # Retrieve events from the Security log. Adjust -LogName if necessary.
    $logEntries = Get-Eventlog -LogName Security -ComputerName $hostname -After $startDate -Before $endDate -ErrorAction Stop
    Write-Log -Message "Retrieved $($logEntries.Count) events from Security log." -Level "INFO"
} catch {
    Write-Log -Message "Error retrieving event log data from $hostname: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 4. Process Each Event Record
#----------------------------------------------
if ($scope -match "Y") {
    Write-Log -Message "Filtering only failed logon events." -Level "INFO"
    foreach ($event in $logEntries) {
        # Process logon failure events (EventID 4625)
        # For local failures, ReplacementStrings index 10 equals 2
        if (($event.EventID -eq 4625) -and ($event.ReplacementStrings[10] -eq 2)) {
            $row = $LogonActivityTable.NewRow()
            $row.Date = $event.TimeGenerated
            $row.Type = "Logon - Local"
            $row.Status = "Failure"
            $row.User = $event.ReplacementStrings[5]
            $row.IPAddress = ""
            $LogonActivityTable.Rows.Add($row)
        }
        # For remote failures, ReplacementStrings index 10 equals 10
        if (($event.EventID -eq 4625) -and ($event.ReplacementStrings[10] -eq 10)) {
            $row = $LogonActivityTable.NewRow()
            $row.Date = $event.TimeGenerated
            $row.Type = "Logon - Remote"
            $row.Status = "Failure"
            $row.User = $event.ReplacementStrings[5]
            $row.IPAddress = $event.ReplacementStrings[19]
            $LogonActivityTable.Rows.Add($row)
        }
    }
} else {
    Write-Log -Message "Processing all logon and logoff events." -Level "INFO"
    foreach ($event in $logEntries) {
        # Process successful local logon events (EventID 4624, Logon Type 2, at ReplacementStrings index 8)
        if (($event.EventID -eq 4624) -and ($event.ReplacementStrings[8] -eq 2)) {
            $row = $LogonActivityTable.NewRow()
            $row.Date = $event.TimeGenerated
            $row.Type = "Logon - Local"
            $row.Status = "Success"
            $row.User = $event.ReplacementStrings[5]
            $row.IPAddress = ""
            $LogonActivityTable.Rows.Add($row)
        }
        # Process successful remote logon events (EventID 4624, Logon Type 10, at ReplacementStrings index 8)
        if (($event.EventID -eq 4624) -and ($event.ReplacementStrings[8] -eq 10)) {
            $row = $LogonActivityTable.NewRow()
            $row.Date = $event.TimeGenerated
            $row.Type = "Logon - Remote"
            $row.Status = "Success"
            $row.User = $event.ReplacementStrings[5]
            $row.IPAddress = $event.ReplacementStrings[18]
            $LogonActivityTable.Rows.Add($row)
        }
        # Process failed local logon events (EventID 4625, local - ReplacementStrings index 10 equals 2)
        if (($event.EventID -eq 4625) -and ($event.ReplacementStrings[10] -eq 2)) {
            $row = $LogonActivityTable.NewRow()
            $row.Date = $event.TimeGenerated
            $row.Type = "Logon - Local"
            $row.Status = "Failure"
            $row.User = $event.ReplacementStrings[5]
            $row.IPAddress = ""
            $LogonActivityTable.Rows.Add($row)
        }
        # Process failed remote logon events (EventID 4625, remote - ReplacementStrings index 10 equals 10)
        if (($event.EventID -eq 4625) -and ($event.ReplacementStrings[10] -eq 10)) {
            $row = $LogonActivityTable.NewRow()
            $row.Date = $event.TimeGenerated
            $row.Type = "Logon - Remote"
            $row.Status = "Failure"
            $row.User = $event.ReplacementStrings[5]
            $row.IPAddress = $event.ReplacementStrings[19]
            $LogonActivityTable.Rows.Add($row)
        }
        # Process logoff events (EventID 4647)
        if ($event.EventID -eq 4647) {
            $row = $LogonActivityTable.NewRow()
            $row.Date = $event.TimeGenerated
            $row.Type = "Logoff"
            $row.Status = "Success"
            $row.User = $event.ReplacementStrings[1]
            $row.IPAddress = ""
            $LogonActivityTable.Rows.Add($row)
        }
    }
}

#----------------------------------------------
# 5. Output the Results in the Selected Format
#----------------------------------------------
Write-Log -Message "Outputting the logon activity report using the selected format: $output" -Level "INFO"
if ($output -match "T") {
    # Output as a table
    $LogonActivityTable | Format-Table -AutoSize
}
elseif ($output -match "H") {
    # Create custom HTML styles
    $htmlStyle = @"
<style>
BODY { background-color: #F2F2F2; font-family: Arial, sans-serif; }
TABLE { border-collapse: collapse; width: 100%; }
TH, TD { border: 1px solid #000; padding: 8px; text-align: left; }
TH { background-color: #BDBDBD; }
TD { background-color: #D8D8D8; }
</style>
"@
    # Convert the DataTable to HTML and save it to a file
    $htmlOutput = $LogonActivityTable | Select-Object Date, Type, Status, User, IPAddress | ConvertTo-Html -Head $htmlStyle -Body "<h2>Logon Activity Report</h2>" -Title "Logon Activity"
    $htmlFile = Join-Path -Path (Get-Location) -ChildPath "LogonActivity.html"
    $htmlOutput | Out-File -FilePath $htmlFile -Encoding UTF8
    Write-Log -Message "HTML report generated at: $htmlFile" -Level "INFO"
    # Optionally, open the HTML file in the default browser
    Invoke-Item -Path $htmlFile
}
elseif ($output -match "G") {
    # Output using GridView
    $LogonActivityTable | Out-GridView -Title "Logon Activity Report"
}
else {
    # Default output: simply return the DataTable object as a list.
    $LogonActivityTable
}

Write-Log -Message "Logon activity report processing completed." -Level "INFO"
