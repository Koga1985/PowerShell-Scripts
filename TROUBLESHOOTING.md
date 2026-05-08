# Troubleshooting Guide

This guide provides solutions to common issues encountered when running PowerShell scripts from this repository.

## Table of Contents

- [Prerequisites Issues](#prerequisites-issues)
- [Module Issues](#module-issues)
- [Credential Issues](#credential-issues)
- [Execution Issues](#execution-issues)
- [Logging Issues](#logging-issues)
- [Veeam Script Issues](#veeam-script-issues)
- [VMware Script Issues](#vmware-script-issues)
- [Windows Script Issues](#windows-script-issues)
- [Performance Issues](#performance-issues)
- [Security/Permission Issues](#securitypermission-issues)

---

## Prerequisites Issues

### Issue: "This script must be run as Administrator"

**Symptoms:**
```
#Requires -RunAsAdministrator
The script 'script-name.ps1' cannot be run because it contains "#Requires" statements that are not met.
```

**Solution:**
1. Open PowerShell as Administrator
2. Right-click PowerShell icon → Run as Administrator
3. Or use: `Start-Process powershell -Verb RunAs`
4. Navigate to script directory and run again

### Issue: "PowerShell version is too old"

**Symptoms:**
```
#Requires -Version 5.1
The script 'script-name.ps1' cannot be run because it contains "#Requires" statements that are not met.
```

**Solution:**
1. Check current version: `$PSVersionTable.PSVersion`
2. For Windows PowerShell 5.0, update to 5.1
3. For older versions, consider installing PowerShell 7+
4. Download from: https://github.com/PowerShell/PowerShell/releases

### Issue: Required module not listed by #Requires

**Symptoms:**
```
#Requires -Modules VMware.PowerCLI
Module VMware.PowerCLI not found
```

**Solution:**
1. Run Setup-Prerequisites.ps1: `.\Setup-Prerequisites.ps1`
2. Or install manually:
   ```powershell
   Install-Module -Name VMware.PowerCLI -Force -AllowClobber
   Import-Module VMware.PowerCLI
   ```
3. Verify installation: `Get-Module -Name VMware.PowerCLI -ListAvailable`

---

## Module Issues

### Issue: Module installation fails

**Symptoms:**
```
PackageManagement\Install-Package : No match was found for the specified search criteria
```

**Solution:**
1. Check internet connectivity
2. Verify NuGet provider is current:
   ```powershell
   Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
   ```
3. Check PowerShell Gallery availability
4. Try explicit repository:
   ```powershell
   Install-Module -Name ModuleName -Repository PSGallery -Force
   ```

### Issue: Module import fails with version conflict

**Symptoms:**
```
Import-Module : The version of the loaded module 'ModuleName' does not match the version of the file
```

**Solution:**
1. Remove old version:
   ```powershell
   Remove-Module ModuleName -Force -ErrorAction SilentlyContinue
   ```
2. Uninstall old module:
   ```powershell
   Uninstall-Module -Name ModuleName -AllVersions -Force
   ```
3. Reinstall latest:
   ```powershell
   Install-Module -Name ModuleName -Force -AllowClobber
   ```

### Issue: Module has breaking changes in newer version

**Symptoms:**
Script works with older version but fails with newer version

**Solution:**
1. Pin module version in script:
   ```powershell
   Import-Module -Name ModuleName -RequiredVersion 12.0.0
   ```
2. Or specify minimum version:
   ```powershell
   #Requires -Module ModuleName -MinimumVersion 12.0.0
   ```
3. Review module changelog for breaking changes
4. Update script if necessary

---

## Credential Issues

### Issue: Credential Manager shows error

**Symptoms:**
```
Get-StoredCredential : The term 'Get-StoredCredential' is not recognized
```

**Solution:**
1. Install CredentialManager module:
   ```powershell
   Install-Module -Name CredentialManager -Force
   ```
2. Or use built-in PSCredential prompt:
   ```powershell
   $cred = Get-Credential -Message "Enter credentials"
   ```

### Issue: Password not working with Get-Credential

**Symptoms:**
Script runs but authentication fails with provided credentials

**Solution:**
1. Verify account has necessary permissions in target system
2. Check if password has special characters requiring escaping
3. Try entering credentials manually:
   ```powershell
   $cred = Get-Credential -UserName 'domain\username'
   ```
4. Verify account isn't locked or disabled
5. Check if multi-factor authentication is required

### Issue: Credential exposure in logs

**Symptoms:**
Credentials appear in log files

**Solution:**
1. Never log credential objects directly
2. Use this pattern:
   ```powershell
   Write-Log "Connected as $($cred.UserName)" # OK
   Write-Log $cred  # DO NOT DO THIS
   ```
3. Review log files for exposed credentials
4. Clear sensitive variables before exit:
   ```powershell
   $cred.Password.Clear()
   ```

---

## Execution Issues

### Issue: Script stops unexpectedly

**Symptoms:**
Script exits with no error message

**Solution:**
1. Add verbose output:
   ```powershell
   .\ScriptName.ps1 -Verbose
   ```
2. Check $Error variable:
   ```powershell
   $Error[0] | Format-List *
   ```
3. Review log file for errors
4. Run with debug:
   ```powershell
   .\ScriptName.ps1 -Debug
   ```

### Issue: WhatIf doesn't show expected output

**Symptoms:**
```
-WhatIf: What if: Performing the operation...
Script doesn't show detailed changes
```

**Solution:**
1. Check script implements $PSCmdlet.ShouldProcess():
   ```powershell
   if ($PSCmdlet.ShouldProcess($target, "Action")) { }
   ```
2. Verify -Confirm parameter support
3. Add verbose output for detailed preview:
   ```powershell
   .\ScriptName.ps1 -WhatIf -Verbose
   ```

### Issue: Script timeout or hangs

**Symptoms:**
Script takes extremely long time or stops responding

**Solution:**
1. Check network connectivity to remote systems
2. Verify remote server availability:
   ```powershell
   Test-NetConnection -ComputerName 'servername' -Port 5985
   ```
3. Check for background jobs:
   ```powershell
   Get-Job | Stop-Job
   ```
4. Use timeout parameters if available:
   ```powershell
   .\ScriptName.ps1 -Timeout 300
   ```
5. Review log file for last successful action

---

## Logging Issues

### Issue: Log directory not created

**Symptoms:**
```
Cannot find path 'C:\Logs' because it does not exist
```

**Solution:**
1. Create directory manually:
   ```powershell
   New-Item -ItemType Directory -Path 'C:\Logs' -Force
   ```
2. Or update script with explicit parameter:
   ```powershell
   .\ScriptName.ps1 -LogPath 'C:\Temp\log.txt'
   ```
3. Verify write permissions to directory

### Issue: Cannot write to log file

**Symptoms:**
```
Add-Content : Access to the path 'log.txt' is denied
```

**Solution:**
1. Check file permissions:
   ```powershell
   icacls 'C:\Logs\log.txt' /T
   ```
2. Verify account has write permissions
3. Close file if open in another application
4. Use explicit path with full permissions:
   ```powershell
   .\ScriptName.ps1 -LogPath 'C:\Temp\newlog.txt'
   ```

### Issue: Event Log source registration fails

**Symptoms:**
```
New-EventLog : The source 'SourceName' does not exist
```

**Solution:**
1. Run PowerShell as Administrator
2. Create event log source manually:
   ```powershell
   New-EventLog -LogName Application -Source 'SourceName'
   ```
3. Script will retry after successful creation

---

## Veeam Script Issues

### Issue: Cannot connect to Veeam server

**Symptoms:**
```
Add-PSSnapin : The Windows PowerShell snap-in 'Veeam.Backup.PowerShell' is not installed
```

**Solution:**
1. Verify Veeam Backup & Replication is installed on machine
2. Install module: `.\Setup-Prerequisites.ps1 -ModuleList "Veeam.Backup.PowerShell"`
3. Ensure account has permissions in Veeam
4. Check Veeam service is running:
   ```powershell
   Get-Service -Name 'VeeamBackupSvc' | Start-Service
   ```

### Issue: Job Status script shows no sessions

**Symptoms:**
No backup sessions returned

**Solution:**
1. Verify backup jobs have run recently:
   ```powershell
   Get-VBRBackupSession | Select-Object -First 5
   ```
2. Check -DaysBack parameter (default is 10):
   ```powershell
   .\Job Status.ps1 -DaysBack 30
   ```
3. Verify Veeam has sufficient permissions
4. Check Veeam database connectivity

### Issue: Log Scrubber misses sensitive data

**Symptoms:**
Some IP addresses or hostnames not replaced

**Solution:**
1. Review regex patterns in script
2. Add custom patterns:
   ```powershell
   .\Log Scrubber.ps1 -LogLocation 'C:\Logs\Veeam' -Verbose
   ```
3. Verify file encoding (UTF-8 vs ANSI):
   ```powershell
   Get-Content -Encoding Utf8 'logfile.log'
   ```

---

## VMware Script Issues

### Issue: VMware PowerCLI certificate validation error

**Symptoms:**
```
Connect-VIServer : The certificate of the specified server is not trusted
```

**Solution:**
1. Verify script sets certificate validation:
   ```powershell
   Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false
   ```
2. Or ignore for lab environments:
   ```powershell
   Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
   ```
3. Check vCenter certificate validity
4. Add CA certificate to trusted store

### Issue: Cannot connect to vCenter

**Symptoms:**
```
Connect-VIServer : Cannot complete login due to an incorrect user name or password
```

**Solution:**
1. Verify credentials with direct test:
   ```powershell
   Connect-VIServer -Server 'vcenter.domain.local' -Credential (Get-Credential)
   ```
2. Check vCenter service running:
   ```powershell
   Get-Service -Computer 'vcenter-host' | Where-Object {$_.Name -like 'vpxa*'}
   ```
3. Verify network connectivity:
   ```powershell
   Test-NetConnection -ComputerName 'vcenter.domain.local' -Port 443
   ```
4. Check vCenter logs for authentication errors

### Issue: Snapshot operations very slow

**Symptoms:**
Snapshot creation/deletion takes excessive time

**Solution:**
1. Check VM storage performance
2. Verify no snapshot chains exist:
   ```powershell
   Get-VM -Name 'VMName' | Get-Snapshot | Select-Object -ExpandProperty Name
   ```
3. Consolidate snapshots on VM
4. Check vCenter resource utilization:
   ```powershell
   Get-VMHost | Select-Object Name, CpuUsageMhz, MemoryUsageMB
   ```

---

## Windows Script Issues

### Issue: Registry modification fails

**Symptoms:**
```
New-ItemProperty : Access to the registry key 'HKLM:\...' is denied
```

**Solution:**
1. Run PowerShell as Administrator
2. Verify registry path exists:
   ```powershell
   Test-Path 'HKLM:\Path\To\Registry'
   ```
3. Create path if missing:
   ```powershell
   New-Item -Path 'HKLM:\Path\To' -Name 'Registry' -Force
   ```
4. Check Group Policy isn't blocking registry modifications

### Issue: Service modification fails

**Symptoms:**
```
Set-Service : Access is denied
```

**Solution:**
1. Run PowerShell as Administrator
2. Verify service exists:
   ```powershell
   Get-Service -Name 'ServiceName'
   ```
3. Check service isn't protected by System File Protection
4. Stop service before modification:
   ```powershell
   Stop-Service -Name 'ServiceName' -Force
   ```

### Issue: Windows Defender script blocked

**Symptoms:**
Script blocks at Defender scanning step

**Solution:**
1. Disable real-time monitoring temporarily:
   ```powershell
   Set-MpPreference -DisableRealtimeMonitoring $true
   ```
2. Or skip Defender operations:
   ```powershell
   .\Windows Hardening.ps1 -SkipDefenderScan
   ```
3. Review Defender exclusions for script

---

## Performance Issues

### Issue: Script uses excessive CPU/Memory

**Symptoms:**
System becomes unresponsive during script execution

**Solution:**
1. Add throttling to loops:
   ```powershell
   Start-Sleep -Milliseconds 100  # Between operations
   ```
2. Process items in batches:
   ```powershell
   $items | ForEach-Object -Begin {} -Process {} -End {} -PipelineVariable item
   ```
3. Clear variables to free memory:
   ```powershell
   $largeArray = $null
   [GC]::Collect()
   ```

### Issue: Network timeouts with remote operations

**Symptoms:**
Script fails communicating with remote servers

**Solution:**
1. Increase timeout values in script
2. Implement retry logic with exponential backoff
3. Check network connectivity:
   ```powershell
   Test-NetConnection -ComputerName 'servername' -InformationLevel Detailed
   ```
4. Verify remote PowerShell enabled:
   ```powershell
   Test-WSMan -ComputerName 'servername'
   ```

---

## Security/Permission Issues

### Issue: Access Denied errors

**Symptoms:**
```
Error: Access denied while attempting to access/modify resources
```

**Solution:**
1. Verify running as Administrator
2. Check user account has necessary permissions on target resources
3. Review Active Directory group memberships
4. Check resource-level permissions (NTFS, Registry, Service)
5. Use explicit credential with elevated permissions:
   ```powershell
   .\ScriptName.ps1 -Credential (Get-Credential -UserName 'domain\admin')
   ```

### Issue: Credential stored in plaintext log

**Symptoms:**
Password visible in log file

**Solution:**
1. Do not log $Credential object directly
2. Use only usernames in logs:
   ```powershell
   Write-Log "User: $($Credential.UserName)"
   ```
3. Audit existing log files for exposed credentials
4. Remove or encrypt affected logs

### Issue: Script marked as Untrusted

**Symptoms:**
```
Cannot be loaded because running scripts is disabled on this system
```

**Solution:**
1. Check Execution Policy:
   ```powershell
   Get-ExecutionPolicy
   ```
2. Set to RemoteSigned (recommended):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
   ```
3. Or bypass for single execution:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "script.ps1"
   ```

---

## Getting Additional Help

- **Check Script Header** - Help documentation in script comments
- **View Help** - `Get-Help .\ScriptName.ps1 -Full`
- **Verbose Output** - Run with `-Verbose` flag
- **GitHub Issues** - https://github.com/Koga1985/PowerShell-Scripts/issues
- **Review Logs** - Check script log files for detailed error messages

---

**Last Updated:** May 8, 2026
**Maintained By:** Dewain Smith #TheBeardedEngineer
