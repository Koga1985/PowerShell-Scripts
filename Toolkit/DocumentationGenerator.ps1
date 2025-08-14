<#
.SYNOPSIS
    Documentation Generator Script.
.DESCRIPTION
    Auto-generates Markdown documentation for environment and scripts.
.PARAMETER SourceFolder
    Path to folder containing scripts to document.
.PARAMETER OutputFile
    Path to output Markdown file.
#>
param (
    [Parameter(Mandatory)]
    [string]$SourceFolder,
    [Parameter(Mandatory)]
    [string]$OutputFile
)
function Write-Log { param($Message); Write-Host "[DocGen] $Message" }
Write-Log "Generating documentation for $SourceFolder..."
$docs = @()
Get-ChildItem -Path $SourceFolder -Filter *.ps1 | ForEach-Object {
    $content = Get-Content $_.FullName
    $synopsis = ($content | Select-String -Pattern '.SYNOPSIS' -Context 0,2).Line
    $docs += "## $($_.Name)
$synopsis
---"
}
Set-Content -Path $OutputFile -Value ($docs -join "`n")
Write-Log "Documentation generated at $OutputFile."
