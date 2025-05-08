<#!
.SYNOPSIS
    VMAuditandCleanup - Disconnects mounted ISO images and removes snapshots in vSphere with advanced options.

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
    .\VMAuditandCleanup.ps1 -VCenterServer vcsa.local -VMName DB01,DB02 -SnapshotMaxAgeDays 7 -LogDirectory C:\Logs -Parallel -SlackWebhookUrl https://hooks.slack.com/services/... -WhatIf
#>
