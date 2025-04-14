<#
.SYNOPSIS
    Executes a SQL query on multiple servers, exports the combined results to a CSV file, and then converts the CSV to an Excel file.

.DESCRIPTION
    This script reads a list of SQL Server instance names from a file (serverlist.txt), then executes a specified SQL query on each server using Invoke-Sqlcmd.
    The results from all servers are aggregated and exported to a CSV file. The CSV file is then opened in Excel (using COM automation), all used columns are auto-fitted,
    and the file is saved as an Excel file.
    
.PARAMETERS
    - query:
        The SQL query to be executed on each server.
    - csvFilePath:
        The file path where the query results (in CSV format) will be saved.
    - excelFilePath:
        The file path where the final Excel file (in .xls format) will be saved.
    - serverListFile:
        The path to a text file containing the list of target SQL Server instance names (one per line).
        
.EXAMPLE
    PS C:\> .\Invoke-MultiServerQuery.ps1 `
        -query "SELECT * FROM YourDatabase.dbo.YourTable" `
        -csvFilePath "C:\Scripts\queryresults.csv" `
        -excelFilePath "C:\Scripts\queryresults.xls" `
        -serverListFile "C:\serverlist.txt"

.NOTES
    Author: Your Name or Organization
    Date: 2025-04-14
    Version: 1.1
    Prerequisites:
      - Administrator privileges.
      - SQLPS or SQLServer module must be installed.
      - The remote servers must be configured to allow remote SQL command execution.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$query,
    
    [Parameter(Mandatory = $true)]
    [string]$csvFilePath,
    
    [Parameter(Mandatory = $true)]
    [string]$excelFilePath,
    
    [Parameter(Mandatory = $true)]
    [string]$serverListFile
)

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a timestamped log message with a specified severity.
    
    .PARAMETER Message
        The log message.
    
    .PARAMETER Level
        The log severity (e.g., "INFO", "ERROR"). Defaults to "INFO".
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message"
}

Write-Log -Message "Starting SQL query execution across multiple servers." -Level "INFO"

#----------------------------------------------
# 1. Retrieve the List of Servers
#----------------------------------------------
try {
    Write-Log -Message "Reading server list from file: $serverListFile" -Level "INFO"
    $serverList = Get-Content -Path $serverListFile -ErrorAction Stop
    Write-Log -Message "Retrieved $($serverList.Count) server(s) from the list." -Level "INFO"
} catch {
    Write-Log -Message "Error reading server list: $_" -Level "ERROR"
    exit 1
}

#----------------------------------------------
# 2. Execute SQL Query on Each Server and Aggregate Results
#----------------------------------------------
# Initialize the result collection.
$results = @()

foreach ($instance in $serverList) {
    Write-Log -Message "Executing query against server: $instance" -Level "INFO"
    try {
        # Execute the query using Invoke-Sqlcmd.
        # Ensure that the SQLServer or SQLPS module is loaded.
        $queryResult = Invoke-Sqlcmd -Query $query -ServerInstance $instance -ErrorAction Stop
        
        if ($queryResult) {
            Write-Log -Message "Query returned $($queryResult.Count) record(s) from $instance." -Level "INFO"
            $results += $queryResult
        }
    } catch {
        Write-Log -Message "Error executing query on $instance: $_" -Level "ERROR"
    }
}

if ($results.Count -eq 0) {
    Write-Log -Message "No records were returned from any server." -Level "WARNING"
    exit 1
}

#----------------------------------------------
# 3. Export Aggregated Results to CSV
#----------------------------------------------
Write-Log -Message "Saving query results to CSV: $csvFilePath" -Level "INFO"
try {
    $results | Export-Csv -Path $csvFilePath -NoTypeInformation -Force -ErrorAction Stop
    Write-Log -Message "CSV export succeeded." -Level "INFO"
} catch {
    Write-Log -Message "Error exporting results to CSV: $_" -Level "ERROR"
    exit 1
}

#----------------------------------------------
# 4. Convert CSV to Excel Format
#----------------------------------------------
Write-Log -Message "Converting CSV to Excel format: $excelFilePath" -Level "INFO"
try {
    # Create a new Excel COM object.
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    # Open the CSV file in Excel.
    $workbook = $excel.Workbooks.Open($csvFilePath)
    $worksheet = $workbook.Worksheets.Item(1)
    # Auto-fit the columns
    $worksheet.UsedRange.EntireColumn.AutoFit() | Out-Null

    # Save the workbook as an Excel file using Excel 8.0 format (XLS).
    $xlExcel8 = 56
    $workbook.SaveAs($excelFilePath, $xlExcel8)
    $workbook.Close()
    $excel.Quit()

    # Release the COM objects.
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($worksheet) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    Write-Log -Message "CSV successfully converted to Excel file: $excelFilePath" -Level "INFO"
} catch {
    Write-Log -Message "Error converting CSV to Excel: $_" -Level "ERROR"
    exit 1
}

Write-Log -Message "Script execution completed successfully." -Level "INFO"
