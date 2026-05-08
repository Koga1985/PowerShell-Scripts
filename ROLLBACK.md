# Rollback Procedures Guide

This document provides detailed rollback procedures for scripts that modify system configurations. Rollback capabilities vary by script; this guide explains available options.

## Table of Contents

- [Rollback Concepts](#rollback-concepts)
- [Scripts with Rollback Support](#scripts-with-rollback-support)
- [Scripts without Rollback](#scripts-without-rollback)
- [Manual Rollback Procedures](#manual-rollback-procedures)
- [Prevention Strategies](#prevention-strategies)
- [Recovery Tools](#recovery-tools)

---

## Rollback Concepts

### What is Rollback?

Rollback is the process of reverting system changes to a previous known-good state. PowerShell scripts implement rollback through:

1. **Automatic Rollback** - Script automatically reverts changes on error
2. **Manual Rollback** - Administrator invokes rollback script manually
3. **Restore Points** - Windows System Restore for OS-level recovery
4. **File Backups** - Backed-up configuration files restored
5. **Registry Backups** - Registry exports restored

### Rollback Safety Levels

- **LEVEL 1: No Rollback** - Changes cannot be undone
- **LEVEL 2: Manual Rollback** - Administrator must execute rollback manually
- **LEVEL 3: Semi-Automatic** - Rollback available with confirmation
- **LEVEL 4: Automatic** - Script auto-reverts on error

---

## Scripts with Rollback Support

### HIGH ROLLBACK CAPABILITY (Level 4)

#### **HyperV Hardening.ps1**

**Rollback Level:** 4 (Automatic with System Restore)

**Rollback Methods:**
1. **Automatic Rollback** - On error, reverts all changes made in current session
2. **System Restore Point** - Script creates restore point before changes
3. **Configuration Tracking** - All changes logged for manual recovery

**How to Rollback:**

Option 1 - Automatic (if script created restore point):
```powershell
# Script creates restore point before modifications
# On critical error, script automatically reverts changes

# Manual system restore if needed
Restore-Computer -RestorePoint (Get-ComputerRestorePoint | Select-Object -First 1)
```

Option 2 - Manual Restore Point:
```powershell
# Access Windows System Restore
# 1. Open System Restore: systemreset.exe
# 2. Select restore point created before hardening
# 3. Follow prompts to restore system state
```

Option 3 - Registry Rollback:
```powershell
# Registry changes are logged; manually revert:
$backupPath = "C:\Windows\Logs\Security\HyperVHardening_Registry_Backup.reg"
reg import $backupPath
```

**Pre-Execution Safeguards:**
- [ ] Run with `-WhatIf` first to preview changes
- [ ] Create manual system restore point before running
- [ ] Test in isolated environment first
- [ ] Back up VM configurations before starting

**Recovery Checklist:**
- [ ] Note error message and time
- [ ] Verify which changes were completed
- [ ] Use System Restore Point or manual registry recovery
- [ ] Test VM functionality after rollback
- [ ] Review logs: `C:\Windows\Logs\Security\HyperVHardening_Audit.log`

---

#### **Windows Hardening.ps1**

**Rollback Level:** 3 (Semi-Automatic)

**Rollback Methods:**
1. **WhatIf Preview** - Preview all changes before execution
2. **Transcript Log** - Full session transcript for reference
3. **Registry Backup** - Registry exported before changes
4. **Manual Reversion** - Changes documented for manual rollback

**How to Rollback:**

Option 1 - Preview Before Committing:
```powershell
# Preview changes (no modifications made)
.\Windows Hardening.ps1 -WhatIf

# Review output carefully
# Only run without -WhatIf if comfortable with changes
```

Option 2 - Transcript-Based Rollback:
```powershell
# Transcript shows all commands executed
# Location: $env:TEMP\WindowsHardening_*.log

# Review transcript:
Get-Content "$env:TEMP\WindowsHardening_$(Get-Date -Format 'yyyyMMdd')*.log"

# Manually revert specific changes based on transcript
```

Option 3 - Service Rollback:
```powershell
# Services can be re-enabled manually
Start-Service -Name "Telnet"          # If disabled by script
Start-Service -Name "FTP"             # If disabled by script
Start-Service -Name "SNMP"            # If disabled by script
```

Option 4 - Firewall Rollback:
```powershell
# Reset Windows Firewall to default
Remove-NetFirewallRule -Direction Inbound -Action Block
Set-NetFirewallProfile -Profile Domain, Public, Private -DefaultInboundAction Allow
```

Option 5 - Feature Rollback:
```powershell
# Re-enable Windows features if needed
Enable-WindowsOptionalFeature -Online -FeatureName "TelnetClient"
Enable-WindowsOptionalFeature -Online -FeatureName "SNMP"
```

**Pre-Execution Safeguards:**
- [ ] Run with `-WhatIf` to preview all changes
- [ ] Verify services needed in your environment
- [ ] Create system restore point
- [ ] Document current firewall rules
- [ ] Test on non-production system first

**Recovery Checklist:**
- [ ] Stop script if errors occur (Ctrl+C)
- [ ] Review transcript for incomplete changes
- [ ] Verify which services actually disabled
- [ ] Re-enable necessary services
- [ ] Test network connectivity
- [ ] Verify required applications still function

---

#### **Hyper-V Hardening.ps1**

**Rollback Level:** 3 (Manual with Tracking)

**Rollback Methods:**
1. **Change Tracking** - All changes logged to `$Global:ConfigChanges`
2. **Manual Reversion** - Each change can be reverted individually
3. **System Restore** - Windows restore point for full recovery

**How to Rollback:**

Option 1 - Manual Registry Rollback:
```powershell
# Registry changes tracked during execution
# Revert individual settings:

# Disable Enhanced Session Mode
Set-Item -Path 'HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation' `
         -Name 'AllowFreshCredentials' -Value 0 -Force

# Re-enable legacy features if needed
Enable-WindowsOptionalFeature -Online -FeatureName "HyperV-Tools-All"
```

Option 2 - VM Configuration Rollback:
```powershell
# Re-enable VM clipboard if disabled
Get-VMIntegrationService -VMName "VM-Name" | 
    Where-Object { $_.Name -match "Clipboard" } | 
    Enable-VMIntegrationService
```

Option 3 - Full System Restore:
```powershell
# Use Windows System Restore
Restore-Computer -RestorePoint (Get-ComputerRestorePoint | Where-Object { $_.CreationTime -lt (Get-Date).AddHours(-1) })
```

**Pre-Execution Safeguards:**
- [ ] Test in lab Hyper-V environment first
- [ ] Document current VM configurations
- [ ] Create system snapshot before changes
- [ ] Verify no active VM operations
- [ ] Close all Hyper-V management tools

**Recovery Checklist:**
- [ ] Verify Hyper-V service status: `Get-Service -Name "vmms"`
- [ ] Check VMs can still start: `Start-VM -Name "test-vm"`
- [ ] Verify network connectivity in VMs
- [ ] Test clipboard functionality if re-enabled
- [ ] Review logs for any service errors

---

### MEDIUM ROLLBACK CAPABILITY (Level 2-3)

#### **Disable SMBv1.ps1**

**Rollback Level:** 2 (Manual)

**Rollback Methods:**
1. **Registry Reversion** - Re-enable SMBv1 in registry
2. **SMB Configuration** - Re-enable via Set-SmbServerConfiguration
3. **Feature Reversion** - Re-enable SMBv1 feature

**How to Rollback:**

```powershell
# Option 1: Registry-based enablement
reg add "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" /v SMB1 /t REG_DWORD /d 1 /f
reg add "HKLM\System\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v SMB1 /t REG_DWORD /d 1 /f

# Option 2: SMB cmdlet-based enablement
Set-SmbServerConfiguration -EnableSMB1Protocol $true -Confirm:$false

# Option 3: Windows Feature-based enablement (if available)
Enable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol"

# Restart SMB service
Restart-Service -Name "LanmanServer" -Force
Restart-Service -Name "LanmanWorkstation" -Force

# Verify SMBv1 re-enabled
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol
```

**Pre-Execution Safeguards:**
- [ ] Verify no legacy systems requiring SMBv1
- [ ] Test with clients before production deployment
- [ ] Document applications using SMBv1
- [ ] Plan rollback if issues occur

**Recovery Checklist:**
- [ ] Verify SMBv1 registry values: `HKLM:\System\...\SMB1`
- [ ] Test SMBv1 connections work
- [ ] Monitor for related errors in Event Log
- [ ] Check application functionality

---

#### **SecurityBaselineEnforcement.ps1**

**Rollback Level:** 3 (Manual with Documentation)

**Rollback Methods:**
1. **Change Documentation** - Changes documented in execution log
2. **Policy Reversion** - Group Policy settings can be reverted
3. **Registry Reversion** - Registry changes documented for manual rollback

**How to Rollback:**

```powershell
# Review what was changed
Get-Content "C:\Windows\Logs\Security\SecurityBaselineEnforcement_Audit.log"

# Revert Group Policy changes
gpupdate /force  # This often reverts to defaults if policies are deleted

# Or manually revert registry changes documented in log
# Example: If UAC was lowered
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 5 /f

# Verify Group Policy refresh
gpresult /h gpresult.html
```

---

### LOW ROLLBACK CAPABILITY (Level 1-2)

#### **Deployment Scripts** (Simple Lab Deployment, VM Migration, etc.)

**Rollback Level:** 1-2 (Manual, Limited Options)

**Rollback Methods:**
1. **Manual Cleanup** - Delete created resources manually
2. **Manual Restoration** - Restore from backups
3. **Manual Configuration** - Reconfigure systems manually

**How to Rollback:**

```powershell
# For VMs/VLANs created during deployment:

# Option 1: Delete created VMs
Get-VM -Name "Lab-VM-*" | Remove-VM -Force

# Option 2: Remove created vLANs/vSwitches
Get-VirtualSwitch -Name "Lab-vSwitch" | Remove-VirtualSwitch -Force

# Option 3: Manual vCenter/ESXi cleanup
# Use vSphere Web Client to:
# 1. Delete created VMs
# 2. Remove created networks
# 3. Delete created datastores (if applicable)

# Option 4: PowerCLI-based cleanup
Disconnect-VIServer -Server vcenter.lab -Confirm:$false
Remove-Item "C:\Lab\DeploymentBackup.xml" -Force  # Clean temp files
```

**Pre-Execution Safeguards:**
- [ ] Test script in isolated lab first
- [ ] Document all created resources (VMs, networks, storage)
- [ ] Have manual cleanup procedure documented
- [ ] Verify no production VMs affected
- [ ] Back up any existing configurations

**Recovery Checklist:**
- [ ] List all created resources: `Get-VM -Name "Lab-*"`
- [ ] Verify each deletion successful
- [ ] Check vCenter for orphaned resources
- [ ] Verify network connectivity restored
- [ ] Clean up any temporary files

---

## Scripts without Rollback

The following scripts are **read-only** or **non-destructive** and do not require rollback:

- ✓ **Health Check.ps1** - Read-only assessment
- ✓ **Job Status.ps1** - Read-only reporting
- ✓ **ConfigurationDriftDetection.ps1** - Read-only analysis
- ✓ **InventoryAssetManagement.ps1** - Read-only data collection
- ✓ **RoleBasedAccessAudit.ps1** - Read-only audit
- ✓ **DocumentationGenerator.ps1** - Documentation creation only
- ✓ **Export Roles and Permissions.ps1** - Read-only export
- ✓ **AD User Logon History.ps1** - Read-only query
- ✓ **Security Log LogOn LogOff.ps1** - Read-only audit

These scripts can be safely run without rollback concerns.

---

## Manual Rollback Procedures

### Generic Rollback Procedure

For scripts without built-in rollback:

1. **Document Initial State**
   ```powershell
   # Before running script, capture current state
   Get-Service | Export-Csv "PreChangeServices.csv"
   Get-Process | Export-Csv "PreChangeProcesses.csv"
   reg export HKLM "PreChangeRegistry.reg"
   ```

2. **Execute with Logging**
   ```powershell
   # Run script with full transcript
   Start-Transcript -Path "Execution_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
   & ".\Script.ps1"
   Stop-Transcript
   ```

3. **Verify Changes**
   ```powershell
   # Compare new state with pre-change state
   Compare-Object (Import-Csv "PreChangeServices.csv") (Get-Service) | 
       Where-Object { $_.SideIndicator -eq "=>" }
   ```

4. **If Rollback Needed**
   ```powershell
   # Option 1: Services
   Get-Service -Name "ServiceName" | Start-Service
   
   # Option 2: Registry
   reg import "PreChangeRegistry.reg"
   
   # Option 3: Files
   Copy-Item "BackupFile.bak" -Destination "OriginalFile"
   ```

### Rollback Checklist

- [ ] Identify what changes need to be reverted
- [ ] Document reason for rollback
- [ ] Create backup before attempting rollback
- [ ] Execute rollback procedure
- [ ] Verify rollback successful
- [ ] Test affected systems/services
- [ ] Update documentation
- [ ] Review logs for root cause

---

## Prevention Strategies

### 1. WhatIf Testing

```powershell
# Always preview before executing destructive scripts
.\Script.ps1 -WhatIf

# Review output carefully
# Only proceed if output matches expectations
```

### 2. Staging Environment

```powershell
# Test in non-production first
# Lab environment, test server, VM snapshot

# Only deploy to production after validation
.\Script.ps1 -Environment Production
```

### 3. Backup Before Changes

```powershell
# Create comprehensive backups
Backup-Computer -Path "C:\Backups\PreScript_$(Get-Date -Format 'yyyyMMdd')"

# Registry backup
reg export HKLM "C:\Backups\Registry_$(Get-Date -Format 'yyyyMMdd').reg"

# File backup
Copy-Item -Path "C:\Critical\Config" -Destination "C:\Backups\Config_$(Get-Date -Format 'yyyyMMdd')" -Recurse
```

### 4. System Restore Point

```powershell
# Create restore point before major changes
Checkpoint-Computer -Description "Before Security Hardening"

# Verify point created
Get-ComputerRestorePoint | Select-Object -First 1
```

### 5. Change Windows

```powershell
# Run destructive scripts during maintenance windows
# Schedule for off-peak hours when impact is minimal
# Notify users in advance
# Have support staff standing by
```

### 6. Documentation

```powershell
# Document all changes made
# Keep detailed execution logs
# Document rollback procedure before starting
# Create quick-reference rollback guide
```

---

## Recovery Tools

### Windows System Tools

```powershell
# System Restore
Restore-Computer -RestorePoint (Get-ComputerRestorePoint | Select-Object -First 1)

# File Recovery (VSS)
Get-Volume | Where-Object { $_.ShadowCopyVolume } | Repair-Volume

# Event Log Recovery
Get-EventLog -LogName System -After (Get-Date).AddHours(-2) | Where-Object { $_.EntryType -eq 'Error' }
```

### PowerShell Recovery Tools

```powershell
# Transaction support
$transaction = Start-Transaction
# Make changes
Complete-Transaction  # Or Undo-Transaction

# Error handling with fallback
try {
    & ".\ChangeScript.ps1"
} catch {
    & ".\RollbackScript.ps1"
}

# Backup/Restore registry
Get-Item -Path 'HKLM:\Path' | Export-Clixml "Backup.xml"
Import-Clixml "Backup.xml" | Set-Item
```

### Third-Party Recovery

- **Veeam Backup** - Full system recovery
- **Acronis** - Disk imaging and recovery
- **Windows Backup** - Built-in backup and restore
- **Git** - Version control for configuration files

---

## Rollback Verification

After rollback, verify:

```powershell
# 1. System Services Status
Get-Service | Where-Object { $_.Status -ne 'Running' } | 
    Where-Object { $_.StartType -eq 'Automatic' }

# 2. Network Connectivity
Test-NetConnection -ComputerName 'google.com' -InformationLevel Quiet

# 3. Application Functionality
# Test critical applications

# 4. Event Log for Errors
Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddHours(-1)

# 5. Firewall Rules
Get-NetFirewallRule -Enabled $true | Measure-Object

# 6. User Permissions
Get-Acl 'C:\' | Format-List

# 7. Registry Keys
Get-Item 'HKLM:\Software\...' | Get-ItemProperty
```

---

## Emergency Rollback

In critical situations:

```powershell
# 1. Immediate system restore
Restore-Computer -RestorePoint (Get-ComputerRestorePoint | Select-Object -First 1) -Confirm:$false

# 2. Or full system recovery from backup
Restore-ComputerFromBackup -BackupPath "E:\Backups\System_2026-05-07.vhd"

# 3. Or reboot and disable auto-start of problematic services
Get-Service -Name "ProblematicService" | Set-Service -StartupType Disabled
Restart-Computer -Force

# 4. If all else fails, boot from recovery media
# (Physical action required)
```

---

**Last Updated:** May 8, 2026
**Maintained By:** Dewain Smith #TheBeardedEngineer
