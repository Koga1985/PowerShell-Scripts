# Integration Guide

This document describes how PowerShell scripts in this repository work together and can be integrated into automated workflows.

## Table of Contents

- [Script Categories](#script-categories)
- [Integration Patterns](#integration-patterns)
- [Workflow Examples](#workflow-examples)
- [Data Flow](#data-flow)
- [Orchestration](#orchestration)
- [Best Practices](#best-practices)
- [Troubleshooting Integration](#troubleshooting-integration)

---

## Script Categories

### Category 1: Foundation & Setup

**Setup-Prerequisites.ps1** - Initializes environment
- **Purpose**: Verify and install all required modules
- **Outputs**: Module installation status, log file
- **Used By**: All other scripts depend on this
- **Triggers**: First-time setup, environment changes

**Example Integration:**
```powershell
# Run before any other script
.\Setup-Prerequisites.ps1 -LogPath 'C:\Logs\Setup.log'
```

### Category 2: Infrastructure Health & Monitoring

**Scripts:**
- `VMware\Health Check.ps1` - vCenter/ESXi health assessment
- `Veeam\Job Status.ps1` - Backup job status review
- `Toolkit\InventoryAssetManagement.ps1` - Asset discovery

**Purpose**: Collect infrastructure metrics
**Outputs**: CSV reports, health status
**Orchestration**: Run on schedule (daily/weekly)

**Integration Point:**
```powershell
# Collect all health data in one workflow
$veeamStatus = & ".\Veeam\Job Status.ps1" -DaysBack 7
$vmwareHealth = & ".\VMware\Health Check.ps1"
# Consolidate and report
```

### Category 3: Configuration Management

**Scripts:**
- `Windows\Windows Hardening.ps1` - OS hardening
- `Hyper-V\HyperV Hardening.ps1` - Hypervisor hardening
- `Windows\Disable SMBv1.ps1` - SMB hardening
- `Toolkit\SecurityBaselineEnforcement.ps1` - Baseline compliance

**Purpose**: Apply and enforce security configurations
**Outputs**: Audit logs, compliance reports
**Dependencies**: Administrator access, prerequisite modules

**Integration Pattern:**
```powershell
# Configuration drift detection → enforcement
$driftReport = & ".\Toolkit\ConfigurationDriftDetection.ps1"
if ($driftReport.HasDrift) {
    & ".\Toolkit\SecurityBaselineEnforcement.ps1" -Remediate
}
```

### Category 4: Automation & Deployment

**Scripts:**
- `Lab\Simple Lab Deployment.ps1` - Lab VM deployment
- `VMware\VM Migration.ps1` - VM movement
- `Veeam\Backup & Replication Install & Config.ps1` - Backup setup

**Purpose**: Deploy and configure infrastructure
**Outputs**: Deployment status, resource IDs
**Risk Level**: HIGH (modifications)

**Integration Pattern:**
```powershell
# Multi-step deployment workflow
$credVCenter = Get-Credential -Message "vCenter admin"
$credVeeam = Get-Credential -Message "Veeam admin"

& ".\Lab\Simple Lab Deployment.ps1" -VMHost "vcenter.lab" -Credential $credVCenter
& ".\Veeam\Backup & Replication Install & Config.ps1" -Credential $credVeeam
```

### Category 5: Maintenance & Cleanup

**Scripts:**
- `Veeam\Log Scrubber.ps1` - Log sanitization
- `Toolkit\DocumentationGenerator.ps1` - Documentation
- `VMware\Remove Snapshot.ps1` - Snapshot cleanup
- `VMware\VMAuditandCleanup.ps1` - VM lifecycle management

**Purpose**: Maintain system hygiene
**Outputs**: Cleanup reports, sanitized data
**Schedule**: Daily/Weekly/Monthly

**Integration Pattern:**
```powershell
# Weekly maintenance job
& ".\Veeam\Log Scrubber.ps1" -LogLocation "C:\Logs\Veeam"
& ".\VMware\Remove Snapshot.ps1" -VMName "lab-*"
& ".\Toolkit\DocumentationGenerator.ps1" -SourceFolder ".\Scripts" -OutputFile ".\Docs\Inventory.md"
```

### Category 6: Audit & Compliance

**Scripts:**
- `Windows\Security Log LogOn LogOff.ps1` - Login auditing
- `Windows\AD User Logon History.ps1` - User activity
- `Toolkit\RoleBasedAccessAudit.ps1` - Access review
- `VMware\Export Roles and Permissions.ps1` - VMware RBAC

**Purpose**: Audit and compliance reporting
**Outputs**: Audit logs, compliance reports
**Retention**: Long-term archival

**Integration Pattern:**
```powershell
# Monthly compliance reporting
$auditReport = New-Object System.Collections.ArrayList

$auditReport.Add((& ".\Windows\Security Log LogOn LogOff.ps1" -Days 30))
$auditReport.Add((& ".\Toolkit\RoleBasedAccessAudit.ps1"))
$auditReport.Add((& ".\VMware\Export Roles and Permissions.ps1"))

Export-Csv -InputObject $auditReport -Path ".\Reports\Compliance_$(Get-Date -Format 'yyyyMM').csv"
```

### Category 7: Support & Utilities

**Scripts:**
- `Windows\LogOn Creds.ps1` - Service credential management
- `Windows\Set Service Creds.ps1` - Batch credential update
- `Environment\Backup Storage Calculator.ps1` - Capacity planning
- `Toolkit\InventoryAssetManagement.ps1` - Inventory tracking

**Purpose**: Support operations and planning
**Outputs**: Operational data
**Ad-hoc**: Run as needed

---

## Integration Patterns

### Pattern 1: Sequential Workflow

Run scripts in order, passing outputs between them:

```powershell
# Step 1: Verify prerequisites
$setupResult = & ".\Setup-Prerequisites.ps1"
if ($setupResult.FailureCount -gt 0) { exit 1 }

# Step 2: Check health
$health = & ".\VMware\Health Check.ps1"

# Step 3: If issues found, remediate
if ($health.IssuesFound) {
    & ".\Toolkit\SecurityBaselineEnforcement.ps1" -Remediate
}

# Step 4: Report results
& ".\Toolkit\DocumentationGenerator.ps1"
```

### Pattern 2: Parallel Execution

Run independent scripts simultaneously:

```powershell
# Health checks can run in parallel
$jobs = @(
    Start-Job { & ".\VMware\Health Check.ps1" },
    Start-Job { & ".\Veeam\Job Status.ps1" },
    Start-Job { & ".\Toolkit\InventoryAssetManagement.ps1" }
)

# Wait for all to complete
$results = $jobs | Wait-Job | Receive-Job
```

### Pattern 3: Conditional Branching

Execute different scripts based on conditions:

```powershell
$environment = Read-Host "Production or Lab?"

if ($environment -eq "Lab") {
    & ".\Lab\Simple Lab Deployment.ps1"
} elseif ($environment -eq "Production") {
    & ".\Toolkit\SecurityBaselineEnforcement.ps1"
    & ".\Toolkit\ConfigurationDriftDetection.ps1"
}
```

### Pattern 4: Error Recovery

Handle failures with fallback scripts:

```powershell
try {
    & ".\Veeam\Backup & Replication Install & Config.ps1"
} catch {
    Write-Log "Installation failed: $_"
    & ".\Veeam\Log Scrubber.ps1" -LogLocation "C:\Veeam\Logs"
    throw
}
```

### Pattern 5: Scheduled Tasks

Integrate with Windows Task Scheduler:

```powershell
# Create scheduled task for daily health checks
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Scripts\DailyHealthCheck.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 02:00AM
Register-ScheduledTask -TaskName "Daily Health Check" -Action $action -Trigger $trigger
```

---

## Workflow Examples

### Example 1: Daily Infrastructure Health Report

```powershell
<#
Daily comprehensive health check and reporting
#>
param(
    [string]$EmailRecipient = 'admin@domain.com'
)

# 1. Setup
& ".\Setup-Prerequisites.ps1" -SkipModuleImport

# 2. Collect health data in parallel
$jobs = @(
    Start-Job -ScriptBlock { & ".\VMware\Health Check.ps1" } -Name "VMware",
    Start-Job -ScriptBlock { & ".\Veeam\Job Status.ps1" -DaysBack 1 } -Name "Veeam",
    Start-Job -ScriptBlock { & ".\Toolkit\ConfigurationDriftDetection.ps1" } -Name "Drift"
)

$results = $jobs | Wait-Job | Receive-Job

# 3. Consolidate findings
$report = @{
    Timestamp = Get-Date
    VMwareHealth = $results[0]
    BackupStatus = $results[1]
    ConfigDrift = $results[2]
}

# 4. Generate report
$htmlReport = $report | ConvertTo-Html -As Table | Out-String
Send-MailMessage -To $EmailRecipient -From "automation@domain.com" `
    -Subject "Daily Infrastructure Health Report" -Body $htmlReport -SmtpServer "smtp.domain.com"

Write-Log "Daily health report completed and sent"
```

### Example 2: Secure Deployment with Verification

```powershell
<#
Deploy lab environment with security verification
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$LabName,
    
    [Parameter(Mandatory=$true)]
    [PSCredential]$VMwareCredential,
    
    [Parameter(Mandatory=$true)]
    [PSCredential]$VeeamCredential
)

# 1. Pre-flight checks
Write-Host "Running pre-flight checks..."
$health = & ".\VMware\Health Check.ps1" -Server "vcenter.lab"
if (-not $health.IsHealthy) {
    throw "vCenter not healthy. Aborting deployment."
}

# 2. Deploy infrastructure
Write-Host "Deploying lab environment..."
& ".\Lab\Simple Lab Deployment.ps1" `
    -VMHost "vcenter.lab" `
    -VMFolder "Labs\$LabName" `
    -Credential $VMwareCredential

# 3. Install backup solution
Write-Host "Installing Veeam Backup..."
& ".\Veeam\Backup & Replication Install & Config.ps1" `
    -Credential $VeeamCredential

# 4. Apply security hardening
Write-Host "Applying security hardening..."
& ".\Windows\Windows Hardening.ps1" -WhatIf
$confirm = Read-Host "Proceed with hardening? (y/n)"
if ($confirm -eq 'y') {
    & ".\Windows\Windows Hardening.ps1"
}

# 5. Verify security baseline
Write-Host "Verifying security baseline..."
& ".\Toolkit\SecurityBaselineEnforcement.ps1"

# 6. Generate documentation
Write-Host "Generating deployment documentation..."
& ".\Toolkit\DocumentationGenerator.ps1" `
    -SourceFolder ".\Lab\$LabName" `
    -OutputFile ".\Docs\Lab_$LabName.md" `
    -IncludeIndex

Write-Host "Lab deployment complete!"
```

### Example 3: Monthly Compliance Audit

```powershell
<#
Monthly compliance audit and reporting
#>
param(
    [ValidateRange(1, 12)]
    [int]$Month = (Get-Date).Month,
    
    [ValidateRange(2000, 2099)]
    [int]$Year = (Get-Date).Year
)

$reportDate = Get-Date -Year $Year -Month $Month -Day 1
$reportPath = "C:\Reports\Compliance_$('{0:yyyyMM}' -f $reportDate)"

# Create report directory
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

# 1. Windows security audit
$windowsAudit = @()
$windowsAudit += & ".\Windows\Security Log LogOn LogOff.ps1" -Days 30
$windowsAudit += & ".\Windows\AD User Logon History.ps1" -Days 30
$windowsAudit | Export-Csv "$reportPath\Windows_Audit.csv"

# 2. VMware RBAC audit
$vmwareRBAC = & ".\VMware\Export Roles and Permissions.ps1"
$vmwareRBAC | Export-Csv "$reportPath\VMware_RBAC.csv"

# 3. Access control audit
$accessAudit = & ".\Toolkit\RoleBasedAccessAudit.ps1"
$accessAudit | Export-Csv "$reportPath\Access_Control_Audit.csv"

# 4. Create compliance summary
$summary = @{
    ReportDate = $reportDate
    WindowsEventsCount = ($windowsAudit | Measure-Object).Count
    VMwareRBACEntriesCount = ($vmwareRBAC | Measure-Object).Count
    AccessControlIssuesFound = ($accessAudit | Where-Object { $_.IsCompliant -eq $false } | Measure-Object).Count
}

$summary | Export-Csv "$reportPath\Compliance_Summary.csv"

Write-Host "Monthly compliance audit completed: $reportPath"
```

### Example 4: Automated Patch Management Workflow

```powershell
<#
Automated patch management with validation
#>
param(
    [string[]]$ComputerList,
    [PSCredential]$Credential,
    [int]$ScheduleMinutes = 120  # 2 hours from now
)

# 1. Pre-patch verification
Write-Host "Pre-patch verification..."
$preHealth = & ".\VMware\Health Check.ps1"
if (-not $preHealth.IsHealthy) {
    throw "Infrastructure not ready for patching"
}

# 2. Schedule patch deployment
$scheduleTime = (Get-Date).AddMinutes($ScheduleMinutes)
Write-Host "Scheduling patches for $scheduleTime"

& ".\Toolkit\AutomatedPatchManagement.ps1" `
    -ComputerList $ComputerList `
    -Credential $Credential `
    -Schedule $scheduleTime

# 3. Monitor patching progress
Start-Sleep -Seconds 5
$inProgress = $true
while ($inProgress) {
    $status = Get-EventLog -LogName System -Source "PatchManagement" `
        -After (Get-Date).AddHours(-1) | Select-Object -First 1
    
    if ($status.Message -match "completed") {
        $inProgress = $false
        Write-Host "Patching completed"
    } else {
        Write-Host "Patching in progress..."
        Start-Sleep -Seconds 30
    }
}

# 4. Post-patch verification
Write-Host "Post-patch verification..."
$postHealth = & ".\VMware\Health Check.ps1"

# 5. Create report
$report = @{
    PrePatchStatus = $preHealth
    PostPatchStatus = $postHealth
    PatchedComputers = $ComputerList.Count
    TimestampCompleted = Get-Date
}

$report | Export-Csv "C:\Reports\PatchReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
```

---

## Data Flow

### Information Flow Diagram

```
Setup-Prerequisites (Initialize)
    ↓
Health Check Scripts (Assess)
    ├→ VMware Health Check
    ├→ Veeam Job Status
    └→ Configuration Drift Detection
    ↓
Decision Point (Is Issues Found?)
    ├→ YES: Remediation Scripts (Fix)
    │   ├→ Security Baseline Enforcement
    │   └→ Windows Hardening
    └→ NO: Documentation (Document)
        └→ Documentation Generator
    ↓
Audit & Compliance (Report)
    ├→ Security Log Auditing
    ├→ RBAC Export
    └→ Compliance Reports
    ↓
Cleanup & Maintenance (Sustain)
    ├→ Log Scrubber
    ├→ Snapshot Cleanup
    └→ VM Audit and Cleanup
```

### Data Flow Example: Complete Daily Operations

```powershell
# Morning: Health Assessment
$health = Get-Health-Status

# Midday: Process Work
Process-Changes based on $health

# Afternoon: Verification
Verify-Changes and Generate Reports

# Evening: Cleanup
Cleanup-And-Archive-Logs

# Scheduled: Compliance Audit
Run-Monthly-Compliance-Audit
```

---

## Orchestration

### Using PowerShell Workflows

```powershell
workflow Daily-Operations {
    # Parallel execution
    parallel {
        Invoke-HealthCheck
        Invoke-BackupVerification
        Invoke-SecurityAudit
    }
    
    # Sequential validation
    Validate-Results
    Generate-Report
    Archive-Logs
}

Invoke-AsWorkflow -Name Daily-Operations
```

### Using Windows Task Scheduler

```powershell
# Create master orchestration script
$orchestrationScript = @'
# 1. Setup
.\Setup-Prerequisites.ps1

# 2. Health checks
$health = .\VMware\Health Check.ps1

# 3. Conditional remediation
if (-not $health.IsHealthy) {
    .\Toolkit\SecurityBaselineEnforcement.ps1
}

# 4. Reporting
.\Toolkit\DocumentationGenerator.ps1
'@

# Register as scheduled task
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Orchestration.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 02:00AM
Register-ScheduledTask -TaskName "Daily Orchestration" -Action $action -Trigger $trigger
```

### Using External Orchestration Tools

- **Azure Automation** - Run scripts in cloud
- **Ansible** - Multi-system orchestration
- **Jenkins** - CI/CD pipeline integration
- **Kubernetes** - Container-based execution
- **GitOps** - Git-driven operations

---

## Best Practices

### 1. Error Handling & Recovery

```powershell
try {
    & ".\Script1.ps1"
    & ".\Script2.ps1"
    & ".\Script3.ps1"
} catch {
    Write-Log "Error: $_" -Level ERROR
    & ".\Cleanup.ps1"  # Rollback
    Send-Alert "Workflow failed"
    exit 1
}
```

### 2. Logging & Monitoring

```powershell
# Centralize logging
$logPath = "C:\Logs\Integration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Log all operations
Write-Log "Workflow started" -LogPath $logPath
& ".\Script1.ps1" | Tee-Object -FilePath $logPath -Append
& ".\Script2.ps1" | Tee-Object -FilePath $logPath -Append
Write-Log "Workflow completed" -LogPath $logPath
```

### 3. Performance Optimization

```powershell
# Use parallel execution for independent scripts
$jobs = @(
    Start-Job { & ".\Health Check 1.ps1" },
    Start-Job { & ".\Health Check 2.ps1" },
    Start-Job { & ".\Health Check 3.ps1" }
)
$results = $jobs | Wait-Job | Receive-Job
```

### 4. Credential Management

```powershell
# Use Credential Manager
$cred = Get-StoredCredential -Target "vCenter-Admin"

# Or prompt once, reuse
$cred = Get-Credential -Message "vCenter credentials"
& ".\Script1.ps1" -Credential $cred
& ".\Script2.ps1" -Credential $cred
```

### 5. Dependency Management

```powershell
# Verify all prerequisites before starting
$requirements = @{
    'VMware.PowerCLI' = '12.0.0'
    'Veeam.Backup.PowerShell' = '11.0.0'
}

foreach ($module in $requirements.Keys) {
    $version = (Get-Module $module -ListAvailable | Sort-Object Version | Select-Object -Last 1).Version
    if ($version -lt $requirements[$module]) {
        throw "Module $module version $version is below required $($requirements[$module])"
    }
}
```

---

## Troubleshooting Integration

### Issue: Scripts fail in sequence

**Solution:**
```powershell
# Add error handling between scripts
if (-not (& ".\Script1.ps1")) {
    Write-Error "Script1 failed"
    exit 1
}

if (-not (& ".\Script2.ps1")) {
    Write-Error "Script2 failed"
    exit 1
}
```

### Issue: Parallel jobs timeout

**Solution:**
```powershell
# Increase job timeout
$jobs | Wait-Job -Timeout 600 | Receive-Job
```

### Issue: Credentials not passed between scripts

**Solution:**
```powershell
# Pass credentials explicitly
$cred = Get-Credential
& ".\Script1.ps1" -Credential $cred
& ".\Script2.ps1" -Credential $cred
```

### Issue: Output conflicts between scripts

**Solution:**
```powershell
# Redirect output to separate files
& ".\Script1.ps1" > output1.txt 2>&1
& ".\Script2.ps1" > output2.txt 2>&1
```

---

**Last Updated:** May 8, 2026
**Maintained By:** Dewain Smith #TheBeardedEngineer
