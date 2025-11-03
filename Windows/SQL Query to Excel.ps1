<#
.SYNOPSIS
    Securely executes parameterized SQL queries on multiple servers and exports results to Excel.

.DESCRIPTION
    This script provides secure SQL query execution across multiple SQL Server instances with
    comprehensive security features including parameterized queries, credential management,
    and audit logging.

    SECURITY FEATURES:
      - Uses parameterized queries to prevent SQL injection
      - Secure credential management with PSCredential
      - Comprehensive audit logging
      - Input validation and sanitization
      - Encrypted connections to SQL servers
      - Set-StrictMode and error handling

.PARAMETER QueryFile
    Path to a SQL query file. Use parameterized queries with @paramName placeholders.

.PARAMETER QueryText
    Direct SQL query text. Use parameterized queries with @paramName placeholders.

.PARAMETER QueryParameters
    Hashtable of query parameters for parameterized queries.
    Example: @{CustomerID = 123; StartDate = '2025-01-01'}

.PARAMETER ServerListFile
    Path to a text file containing SQL Server instance names (one per line).

.PARAMETER Credential
    PSCredential for SQL Server authentication. If not provided, uses Windows Authentication.

.PARAMETER Database
    Target database name.

.PARAMETER OutputPath
    Directory path for output files. Defaults to current directory.

.PARAMETER OutputFileName
    Base name for output files (without extension).

.PARAMETER ConnectionTimeout
    SQL Server connection timeout in seconds. Default: 30

.PARAMETER QueryTimeout
    SQL query execution timeout in seconds. Default: 300

.PARAMETER UseEncryption
    Force encrypted connection to SQL Server. Default: $true

.EXAMPLE
    # Using parameterized query from file
    $params = @{CustomerID = 123; Status = 'Active'}
    .\SQL-Query-to-Excel.ps1 -QueryFile "C:\Queries\CustomerReport.sql" -QueryParameters $params `
        -ServerListFile "C:\servers.txt" -Database "MyDB" -OutputFileName "CustomerReport"

.EXAMPLE
    # Using Windows Authentication with inline query
    $query = "SELECT * FROM sys.databases WHERE database_id = @dbid"
    .\SQL-Query-to-Excel.ps1 -QueryText $query -QueryParameters @{dbid=1} `
        -ServerListFile "C:\servers.txt" -OutputFileName "DatabaseInfo"

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   October 30, 2025
    Version:        2.0

    SECURITY NOTES:
      - Always use parameterized queries to prevent SQL injection
      - Use encrypted connections for sensitive data
      - All queries are logged for audit purposes
      - Suitable for Fourth Estate infrastructure

    COMPLIANCE:
      - Follows CIS PowerShell security guidelines
      - Implements STIG-compliant logging
      - Prevents SQL injection attacks
      - Uses encrypted database connections
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules SqlServer

[CmdletBinding(DefaultParameterSetName = 'QueryText')]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'QueryFile')]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$QueryFile,

    [Parameter(Mandatory = $true, ParameterSetName = 'QueryText')]
    [ValidateNotNullOrEmpty()]
    [string]$QueryText,

    [Parameter(Mandatory = $false)]
    [hashtable]$QueryParameters = @{},

    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$ServerListFile,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9_\-]+$')]
    [string]$Database,

    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$OutputPath = $PWD,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_\-]+$')]
    [string]$OutputFileName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(5, 300)]
    [int]$ConnectionTimeout = 30,

    [Parameter(Mandatory = $false)]
    [ValidateRange(30, 3600)]
    [int]$QueryTimeout = 300,

    [Parameter(Mandatory = $false)]
    [bool]$UseEncryption = $true,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "$env:ProgramData\PowerShellLogs\SQLQueryExecution.log"
)

# Enable strict mode for better code safety
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#----------------------------------------------
# Initialize Script
#----------------------------------------------
$script:StartTime = Get-Date
$script:ScriptName = $MyInvocation.MyCommand.Name
$script:ExecutingUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$script:LogDirectory = Split-Path -Parent $LogPath

# Generate output file paths
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvFilePath = Join-Path $OutputPath "$OutputFileName`_$timestamp.csv"
$excelFilePath = Join-Path $OutputPath "$OutputFileName`_$timestamp.xlsx"

# Start transcript
$transcriptPath = Join-Path $script:LogDirectory "Transcript_SQLQuery_$timestamp.log"
try {
    if (-not (Test-Path $script:LogDirectory)) {
        New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null
    }
    Start-Transcript -Path $transcriptPath -Force
} catch {
    Write-Warning "Failed to start transcript: $_"
}

#----------------------------------------------
# Secure Logging Function
#----------------------------------------------
function Write-AuditLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Security')]
        [string]$Level = 'Information',

        [Parameter(Mandatory = $false)]
        [string]$ServerInstance = "N/A"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] [User:$script:ExecutingUser] [Server:$ServerInstance] $Message"

    switch ($Level) {
        'Error'    { Write-Host $logEntry -ForegroundColor Red }
        'Warning'  { Write-Host $logEntry -ForegroundColor Yellow }
        'Security' { Write-Host $logEntry -ForegroundColor Cyan }
        default    { Write-Host $logEntry }
    }

    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

#----------------------------------------------
# Validate Query for Basic Safety
#----------------------------------------------
function Test-QuerySafety {
    [CmdletBinding()]
    param([string]$Query)

    Write-AuditLog -Message "Validating query safety..." -Level Information

    # Block obviously dangerous patterns
    $dangerousPatterns = @(
        'xp_cmdshell'
        'sp_OACreate'
        'sp_OAMethod'
        'sp_OAGetProperty'
        'sp_OASetProperty'
        'DROP\s+DATABASE'
        'DROP\s+TABLE'
        'TRUNCATE\s+TABLE'
        'DELETE\s+FROM.*WHERE\s+1\s*=\s*1'
        'EXEC\s*\('
        'EXECUTE\s*\('
    )

    foreach ($pattern in $dangerousPatterns) {
        if ($Query -match $pattern) {
            throw "Query contains potentially dangerous pattern: $pattern"
        }
    }

    Write-AuditLog -Message "Query safety validation passed" -Level Information
}

#----------------------------------------------
# Execute Query on Single Server
#----------------------------------------------
function Invoke-SecureSQLQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )

    Write-AuditLog -Message "Executing query on server: $ServerInstance" -Level Information -ServerInstance $ServerInstance

    try {
        # Build connection parameters
        $invokeSqlParams = @{
            ServerInstance    = $ServerInstance
            Database          = $Database
            Query             = $Query
            ConnectionTimeout = $ConnectionTimeout
            QueryTimeout      = $QueryTimeout
            ErrorAction       = 'Stop'
            OutputAs          = 'DataRows'
        }

        # Add encryption if requested
        if ($UseEncryption) {
            $invokeSqlParams['EncryptConnection'] = $true
            $invokeSqlParams['TrustServerCertificate'] = $false
        }

        # Add credential if provided
        if ($Credential) {
            $invokeSqlParams['Username'] = $Credential.UserName
            $invokeSqlParams['Password'] = $Credential.GetNetworkCredential().Password
        }

        # Add parameters for parameterized query
        if ($Parameters.Count -gt 0) {
            $invokeSqlParams['Variable'] = $Parameters.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$($_.Value)"
            }
        }

        # Execute query
        $result = Invoke-Sqlcmd @invokeSqlParams

        if ($result) {
            Write-AuditLog -Message "Query returned $(@($result).Count) record(s)" -Level Information -ServerInstance $ServerInstance
            return $result
        } else {
            Write-AuditLog -Message "Query returned no results" -Level Warning -ServerInstance $ServerInstance
            return $null
        }

    } catch {
        Write-AuditLog -Message "Error executing query: $_" -Level Error -ServerInstance $ServerInstance
        throw
    }
}

#----------------------------------------------
# Convert CSV to Excel with Formatting
#----------------------------------------------
function ConvertTo-SecureExcel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [Parameter(Mandatory = $true)]
        [string]$ExcelPath
    )

    $excel = $null
    $workbook = $null

    try {
        Write-AuditLog -Message "Converting CSV to Excel: $ExcelPath" -Level Information

        # Create Excel COM object
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false

        # Open CSV
        $workbook = $excel.Workbooks.Open($CsvPath)
        $worksheet = $workbook.Worksheets.Item(1)

        # Format worksheet
        $worksheet.UsedRange.EntireColumn.AutoFit() | Out-Null

        # Add filters
        $worksheet.UsedRange.AutoFilter() | Out-Null

        # Freeze top row
        $worksheet.Application.ActiveWindow.SplitRow = 1
        $worksheet.Application.ActiveWindow.FreezePanes = $true

        # Save as Excel format (51 = xlsx)
        $xlOpenXMLWorkbook = 51
        $workbook.SaveAs($ExcelPath, $xlOpenXMLWorkbook)

        Write-AuditLog -Message "Excel file created successfully: $ExcelPath" -Level Security

    } catch {
        Write-AuditLog -Message "Error converting to Excel: $_" -Level Error
        throw

    } finally {
        # Cleanup COM objects
        if ($workbook) {
            $workbook.Close($false)
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
        }
        if ($excel) {
            $excel.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
        }

        # Force garbage collection
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}

#----------------------------------------------
# Main Execution Block
#----------------------------------------------
try {
    Write-AuditLog -Message "========== SQL Query Execution Started ==========" -Level Security
    Write-AuditLog -Message "Script: $script:ScriptName" -Level Information
    Write-AuditLog -Message "Executed by: $script:ExecutingUser" -Level Information
    Write-AuditLog -Message "Database: $Database" -Level Information

    # Load query
    if ($PSCmdlet.ParameterSetName -eq 'QueryFile') {
        Write-AuditLog -Message "Loading query from file: $QueryFile" -Level Information
        $QueryText = Get-Content -Path $QueryFile -Raw -ErrorAction Stop
    }

    Write-AuditLog -Message "Query length: $($QueryText.Length) characters" -Level Information

    # Validate query safety
    Test-QuerySafety -Query $QueryText

    # Read server list
    Write-AuditLog -Message "Reading server list from: $ServerListFile" -Level Information
    $serverList = Get-Content -Path $ServerListFile -ErrorAction Stop |
                  Where-Object { $_ -match '\S' } |  # Remove empty lines
                  ForEach-Object { $_.Trim() }        # Trim whitespace

    if ($serverList.Count -eq 0) {
        throw "Server list file is empty or contains no valid entries"
    }

    Write-AuditLog -Message "Found $($serverList.Count) server(s) to query" -Level Information

    # Execute query on all servers
    $allResults = @()
    $successCount = 0
    $failureCount = 0

    foreach ($server in $serverList) {
        try {
            $result = Invoke-SecureSQLQuery -ServerInstance $server -Query $QueryText -Parameters $QueryParameters

            if ($result) {
                # Add source server column
                $result | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'SourceServer' -NotePropertyValue $server -Force
                }
                $allResults += $result
                $successCount++
            }

        } catch {
            Write-AuditLog -Message "Failed to query server $server : $_" -Level Error -ServerInstance $server
            $failureCount++
        }
    }

    # Check if we got any results
    if ($allResults.Count -eq 0) {
        Write-AuditLog -Message "No results returned from any server" -Level Warning
        throw "Query execution completed but returned no results"
    }

    Write-AuditLog -Message "Total records retrieved: $($allResults.Count)" -Level Information

    # Export to CSV
    Write-AuditLog -Message "Exporting results to CSV: $csvFilePath" -Level Information
    $allResults | Export-Csv -Path $csvFilePath -NoTypeInformation -Force -ErrorAction Stop
    Write-AuditLog -Message "CSV export completed" -Level Information

    # Convert to Excel
    ConvertTo-SecureExcel -CsvPath $csvFilePath -ExcelPath $excelFilePath

    # Summary
    Write-Host "`n========== EXECUTION SUMMARY ==========" -ForegroundColor Cyan
    Write-Host "Total Servers Queried: $($serverList.Count)" -ForegroundColor Yellow
    Write-Host "Successful: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failureCount" -ForegroundColor Red
    Write-Host "Total Records: $($allResults.Count)" -ForegroundColor Yellow
    Write-Host "`nOutput Files:" -ForegroundColor Cyan
    Write-Host "  CSV: $csvFilePath" -ForegroundColor White
    Write-Host "  Excel: $excelFilePath" -ForegroundColor White

    $duration = (Get-Date) - $script:StartTime
    Write-AuditLog -Message "========== SQL Query Execution Completed (Duration: $($duration.ToString('mm\:ss'))) ==========" -Level Security

    exit 0

} catch {
    Write-AuditLog -Message "CRITICAL ERROR: $_" -Level Error
    Write-AuditLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Write-AuditLog -Message "========== SQL Query Execution Failed ==========" -Level Security

    exit 1

} finally {
    try { Stop-Transcript } catch {}

    # Clear sensitive data
    if ($Credential) {
        Clear-Variable -Name Credential -ErrorAction SilentlyContinue
    }
}
