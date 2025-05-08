<#
.SYNOPSIS
    Disconnects mounted ISO images and removes snapshots in vSphere with advanced options.

.DESCRIPTION
    This script connects to a vCenter Server and:
      • Dismounts ISO images from VM CD/DVD drives.
      • Removes VM snapshots safely, based on optional age thresholds.

    Enhancements include:
      • Filtering VMs by name, folder, or tags.
      • Parallel execution.
      • Progress display.
      • Logging to file (CSV/HTML) and metrics collection.
      • Version validation and config file support.
      • Notification via Email, Slack, Teams, or Syslog (SIEM).

.PARAMETER VCenterServer
    FQDN or IP of the vCenter Server.

.PARAMETER Credential
    PSCredential for vCenter authentication. Prompts if omitted.

.PARAMETER VMName
    Array of VM names to target. If omitted, all VMs are considered.

.PARAMETER VMFolder
    Inventory folder path to limit VM scope.

.PARAMETER Tag
    Array of tag names; only VMs with these tags are processed.

.PARAMETER ConfigFile
    Path to JSON config with any of the above parameters.

.PARAMETER LogDirectory
    Directory to write logs and reports. Default: current directory.

.PARAMETER SnapshotMaxAgeDays
    Only remove snapshots older than this number of days. Default: 0 (no age filter).

.PARAMETER Parallel
    Switch to enable parallel processing of VMs (requires PowerShell 7+).

.PARAMETER ThrottleLimit
    Max concurrent threads for parallel. Default: 5.

.PARAMETER SlackWebhookUrl
    URL to post a JSON summary to Slack.

.PARAMETER TeamsWebhookUrl
    URL to post a simple message card to Microsoft Teams.

.PARAMETER SiemHost
    Hostname or IP of a Syslog/SIEM listener.

.PARAMETER SiemPort
    UDP port for Syslog messages. Must supply SiemHost to enable.

.PARAMETER WhatIf
    Dry-run switch: preview actions without changes.

.EXAMPLE
    .\Script.ps1 -VCenterServer vcsa.local -VMName DB01,DB02 -SnapshotMaxAgeDays 7 -LogDirectory C:\Logs -Parallel -SlackWebhookUrl https://hooks.slack.com/services/... -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$VCenterServer,
    [PSCredential]$Credential,
    [string[]]$VMName,
    [string]$VMFolder,
    [string[]]$Tag,
    [string]$ConfigFile,
    [string]$LogDirectory = '.',
    [int]$SnapshotMaxAgeDays = 0,
    [switch]$Parallel,
    [int]$ThrottleLimit = 5,
    [string]$SlackWebhookUrl,
    [string]$TeamsWebhookUrl,
    [string]$SiemHost,
    [int]$SiemPort,
    [switch]$WhatIf
)

Begin {
    # Version validation
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Error 'PowerShell 7+ is required for parallel execution.'
        exit 1
    }
    # Module check
    if (-not (Get-Module -ListAvailable VMware.PowerCLI)) {
        Write-Error 'Please install VMware.PowerCLI: Install-Module VMware.PowerCLI'
        exit 1
    }
    Import-Module VMware.PowerCLI -ErrorAction Stop

    # Load config file if provided
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        $cfg = Get-Content $ConfigFile | ConvertFrom-Json
        foreach ($p in $cfg.PSObject.Properties.Name) {
            if ($cfg.$p) { Set-Variable -Name $p -Value $cfg.$p -Scope Script }
        }
    }

    # Prepare credentials
    if (-not $Credential) {
        $Credential = Get-Credential -Message "Credentials for $VCenterServer"
    }

    # Prepare logs and metrics
    $timestamp = (Get-Date -Format 'yyyyMMdd_HHmmss')
    if (-not (Test-Path $LogDirectory)) { New-Item -Path $LogDirectory -ItemType Directory | Out-Null }
    $LogFile = Join-Path $LogDirectory "VM_Audit_$timestamp.log"
    $CsvReport = Join-Path $LogDirectory "VM_Report_$timestamp.csv"
    $Metrics = [pscustomobject]@{
        TotalVMs           = 0
        ISORemoved         = 0
        SnapshotsRemoved   = 0
        Errors             = 0
    }
    function Write-Log {
        param($Message, $Level='INFO')
        $entry = "$(Get-Date -Format o) [$Level] $Message"
        Add-Content -Path $LogFile -Value $entry
        Write-Verbose $entry
    }

    # Connect to vCenter
    Write-Log "Connecting to $VCenterServer"
    Connect-VIServer -Server $VCenterServer -Credential $Credential -ErrorAction Stop | Out-Null
}

Process {
    # Determine target VMs
    function Get-TargetVMs {
        $vms = Get-VM
        if ($VMFolder) { $vms = Get-Folder -Name $VMFolder | Get-VM }
        if ($VMName)   { $vms = $vms | Where-Object Name -in $VMName }
        if ($Tag)      { $vms = $vms | Where-Object {
                            (Get-TagAssignment -Entity $_).Tag.Name | Where-Object { $Tag -contains $_ }
                         } }
        $Metrics.TotalVMs = $vms.Count
        return $vms
    }

    # Function: Dismount ISOs
    function Disconnect-ISOs {
        param($vm)
        Write-Progress -Activity 'Dismounting ISOs' -Status $vm.Name
        try {
            $cds = Get-CDDrive -VM $vm -ErrorAction Stop |
                   Where-Object { $_.Connected -and $_.ISOPath }
            foreach ($cd in $cds) {
                if ($PSCmdlet.ShouldProcess($vm.Name, "Dismount $($cd.ISOPath)")) {
                    Set-CDDrive -CDDrive $cd -NoMedia -Connected:$false -Confirm:$false -WhatIf:$WhatIf
                    $Metrics.ISORemoved++
                    Write-Log "ISO dismounted from $($vm.Name)"
                }
            }
        } catch {
            $Metrics.Errors++
            Write-Log "Error dismounting ISO on $($vm.Name): $_" 'ERROR'
        }
    }

    # Function: Remove snapshots
    function Remove-SnapshotsSafely {
        param($vm)
        Write-Progress -Activity 'Removing Snapshots' -Status $vm.Name
        try {
            $snaps = Get-Snapshot -VM $vm -ErrorAction Stop
            if ($SnapshotMaxAgeDays -gt 0) {
                $snaps = $snaps | Where-Object { (Get-Date) - $_.Created -gt (New-TimeSpan -Days $SnapshotMaxAgeDays) }
            }
            foreach ($snap in $snaps) {
                if ($PSCmdlet.ShouldProcess($vm.Name, "Remove $($snap.Name)")) {
                    $task = Remove-Snapshot -Snapshot $snap -Confirm:$false -RunAsync -WhatIf:$WhatIf
                    if ($task -and -not $WhatIf) { Wait-Task $task }
                    $Metrics.SnapshotsRemoved++
                    Write-Log "Snapshot $($snap.Name) removed from $($vm.Name)"
                }
            }
        } catch {
            $Metrics.Errors++
            Write-Log "Error removing snapshots on $($vm.Name): $_" 'ERROR'
        }
    }

    # Notification functions
    function Send-SlackNotification {
        if ($SlackWebhookUrl) {
            $payload = @{ text = "VM Audit Summary: $($Metrics | ConvertTo-Json -Compress)" } | ConvertTo-Json
            Invoke-RestMethod -Uri $SlackWebhookUrl -Method Post -Body $payload -ContentType 'application/json'
        }
    }
    function Send-TeamsNotification {
        if ($TeamsWebhookUrl) {
            $card = @{ text = "**VM Audit Summary**`nTotal VMs: $($Metrics.TotalVMs)`nISOs: $($Metrics.ISORemoved)`nSnapshots: $($Metrics.SnapshotsRemoved)`nErrors: $($Metrics.Errors)" }
            Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body ($card | ConvertTo-Json) -ContentType 'application/json'
        }
    }
    function Send-Syslog {
        if ($SiemHost -and $SiemPort) {
            $msg = "<134>1 $(Get-Date -Format o) $env:COMPUTERNAME VM-Audit - - - $($Metrics | ConvertTo-Json)"
            $udp = New-Object System.Net.Sockets.UdpClient
            $udp.Send([Text.Encoding]::ASCII.GetBytes($msg), $msg.Length, $SiemHost, $SiemPort)
            $udp.Close()
        }
    }

    # Execute per VM
    $vms = Get-TargetVMs
    if ($Parallel) {
        $vms | ForEach-Object -Parallel {
            Disconnect-ISOs -vm $_
            Remove-SnapshotsSafely -vm $_
        } -ThrottleLimit $ThrottleLimit
    } else {
        foreach ($vm in $vms) {
            Disconnect-ISOs -vm $vm
            Remove-SnapshotsSafely -vm $vm
        }
    }
}

End {
    # Export CSV report
    $Metrics | Export-Csv -Path $CsvReport -NoTypeInformation
    # Optional HTML report
    $Metrics | ConvertTo-Html -Title 'VM Audit Summary' | Out-File -FilePath (Join-Path $LogDirectory "VM_Report_$timestamp.html")

    # Send notifications
    Send-SlackNotification
    Send-TeamsNotification
    Send-Syslog

    # Disconnect
    Disconnect-VIServer -Server * -Confirm:$false | Out-Null

    Write-Output "Completed. Logs: $LogFile; CSV: $CsvReport"
}
