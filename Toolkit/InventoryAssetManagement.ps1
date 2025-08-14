<#
.SYNOPSIS
    Inventory & Asset Management Script.
.DESCRIPTION
    Collects and exports hardware/software inventory across environment. Outputs to CSV.
.PARAMETER ComputerList
    Array of computer names or IPs to inventory.
#>
param (
    [Parameter(Mandatory)]
    [string[]]$ComputerList
)
function Write-Log { param($Message); Write-Host "[Inventory] $Message" }
$results = @()
foreach ($computer in $ComputerList) {
    Write-Log "Collecting inventory from $computer..."
    $info = Invoke-Command -ComputerName $computer -ScriptBlock {
        Get-CimInstance Win32_ComputerSystem
        Get-CimInstance Win32_OperatingSystem
        Get-CimInstance Win32_Product
    }
    $results += $info
}
$results | Export-Csv -Path "InventoryReport.csv" -NoTypeInformation
Write-Log "Inventory collection completed."
