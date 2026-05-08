# Security Policy

This document outlines the security practices, vulnerability disclosure process, and security considerations for the PowerShell-Scripts repository.

## Table of Contents

- [Security Philosophy](#security-philosophy)
- [Supported Versions](#supported-versions)
- [Security Features](#security-features)
- [Vulnerability Disclosure](#vulnerability-disclosure)
- [Security Guidelines](#security-guidelines)
- [Credential Management](#credential-management)
- [Audit Logging](#audit-logging)
- [Compliance Standards](#compliance-standards)
- [Security Updates](#security-updates)
- [Incident Response](#incident-response)

---

## Security Philosophy

The PowerShell-Scripts repository prioritizes:

1. **Principle of Least Privilege** - Scripts request only necessary permissions
2. **Defense in Depth** - Multiple layers of security controls
3. **Secure by Default** - Safe configurations out-of-the-box
4. **Audit & Accountability** - Comprehensive logging of all actions
5. **Transparency** - Clear documentation of security practices
6. **Community Security** - Responsible disclosure and collaborative fixes

---

## Supported Versions

### Version Support Timeline

| Version | Release Date | End of Life | Support Level |
|---------|-------------|------------|--------------|
| 2.x     | 2025-10-30  | 2027-10-30 | Active       |
| 1.x     | 2024-01-15  | 2025-10-30 | Security Only|

### Support Levels

- **Active**: Security and feature updates
- **Security Only**: Critical security patches only
- **Unsupported**: No updates provided

### PowerShell Version Support

- **Minimum**: PowerShell 5.1
- **Recommended**: PowerShell 7.x (latest stable)
- **Note**: Scripts compatible with both Windows PowerShell 5.1 and PowerShell 7+

---

## Security Features

### Built-in Security Controls

#### 1. Execution Requirements
```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator
```
- Enforces minimum PowerShell version
- Requires administrator privileges
- Prevents accidental unprivileged execution

#### 2. Strict Mode
```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```
- Detects use of uninitialized variables
- Prevents implicit type conversions
- Enforces script best practices

#### 3. Input Validation
```powershell
[ValidateNotNullOrEmpty()]
[ValidatePattern('^[a-zA-Z0-9\-\.]+$')]
[ValidateRange(1,365)]
[ValidateScript({ Test-Path $_ -PathType Container })]
```
- Validates parameter types and formats
- Prevents injection attacks
- Enforces required parameter values

#### 4. Credential Handling
```powershell
[System.Management.Automation.PSCredential]
[System.Management.Automation.Credential()]
```
- Uses secure PSCredential objects
- Never stores passwords in plaintext
- Supports Windows Credential Manager integration

#### 5. Error Handling
```powershell
try {
    # Operations
}
catch {
    Write-AuditLog "Error: $_" -Level ERROR
    throw
}
finally {
    # Cleanup - Clear sensitive data
    $credential.Password.Clear()
}
```
- Comprehensive exception handling
- Sensitive data cleanup on error
- Proper error propagation

#### 6. Audit Logging
```powershell
function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO'
    )
    # Logs to file and Windows Event Log
}
```
- File-based logging
- Windows Event Log integration
- Timestamped audit trail
- Classification levels

#### 7. Session Transcription
```powershell
Start-Transcript -Path $transcriptPath -NoClobber
# ... script execution ...
Stop-Transcript
```
- Full session recording
- Non-overwritable transcripts
- Compliance documentation

#### 8. WhatIf/Confirm Support
```powershell
[CmdletBinding(SupportsShouldProcess = $true)]
if ($PSCmdlet.ShouldProcess($target, "Action")) {
    # Destructive operation
}
```
- Preview mode for destructive operations
- Confirmation prompts for critical changes
- Safe testing capability

---

## Vulnerability Disclosure

### Reporting Security Issues

**DO NOT** open public GitHub issues for security vulnerabilities.

Follow this responsible disclosure process:

#### Step 1: Contact Security Team

Send vulnerability details to:
```
Email: security@github.com/Koga1985/PowerShell-Scripts
```

**Or via GitHub Security Advisory:**
1. Go to repository
2. Click "Security" tab
3. Click "Advisories"
4. Click "Report a vulnerability"

#### Step 2: Provide Details

Include:
- **Description**: Clear description of vulnerability
- **Impact**: Severity and potential impact
- **Steps to Reproduce**: Detailed reproduction steps
- **Affected Versions**: Which versions are affected
- **Suggested Fix**: Any proposed solutions
- **Timeline**: When you discovered it

**Example Report:**
```
Title: Credential Exposure in Log Files

Description:
The LogOn Creds.ps1 script exposes service account passwords in the 
audit log file when verbose mode is enabled.

Impact:
HIGH - Service account credentials could be compromised if log files 
are accessed by unauthorized users.

Affected Versions:
- v2.0 and earlier

Steps to Reproduce:
1. Run: .\LogOn Creds.ps1 -Verbose
2. View log file: C:\Logs\ServiceCredUpdate.log
3. Service password visible in plaintext

Suggested Fix:
Sanitize credential objects before logging. Check credentials with 
mask flag before writing to logs.

Timeline:
- Discovered: 2026-05-01
- Reported: 2026-05-02
```

#### Step 3: Embargo Period

- **Embargo**: 90 days (standard disclosure timeline)
- **Extension**: Can request if patch not ready (max 180 days)
- **Public Disclosure**: After patch release or embargo expiration

#### Step 4: Tracking

- Receive acknowledgment within 48 hours
- Updates on fix progress at 30-day intervals
- Advance notice before public disclosure
- Credit in security advisory (if desired)

### Security Advisory Process

1. **Assessment** (24 hours)
   - Confirm vulnerability
   - Assess severity
   - Determine affected versions

2. **Fix Development** (3-30 days)
   - Develop and test fix
   - Create patch
   - Prepare security advisory

3. **Patch Release** (Up to 90 days)
   - Release patched version
   - Publish security advisory
   - Notify users

4. **Public Disclosure**
   - GitHub Security Advisory published
   - CVE assigned (if applicable)
   - Community notified via email/changelog

### Severity Classification

| Severity | CVSS Score | Examples | Action |
|----------|-----------|----------|--------|
| Critical | 9.0-10.0  | Remote code execution, authentication bypass | Immediate patch |
| High     | 7.0-8.9   | Credential exposure, privilege escalation | Urgent patch (7 days) |
| Medium   | 4.0-6.9   | Partial information disclosure | Regular patch (30 days) |
| Low      | 0.1-3.9   | Minor information leak, edge cases | Next release |

---

## Security Guidelines

### For Users

#### 1. Validate Scripts Before Execution
```powershell
# Review script content
Get-Content .\Script.ps1 | Out-Host

# Check for suspicious patterns
Select-String -Path ".\Script.ps1" -Pattern "(Invoke-WebRequest|IEX|Bypass)"

# Use WhatIf to preview
.\Script.ps1 -WhatIf
```

#### 2. Use Restricted Execution Policy
```powershell
# Recommended execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Or even more restrictive
Set-ExecutionPolicy -ExecutionPolicy AllSigned -Scope CurrentUser -Force
```

#### 3. Run with Least Privilege
```powershell
# Only grant administrator access when necessary
# Use runas with specific account if available
runas /user:domain\admin powershell.exe
```

#### 4. Audit Log Files
```powershell
# Regularly review script execution logs
Get-ChildItem -Path "C:\Logs\" -Filter "*.log" -Recurse | 
    ForEach-Object { 
        Get-Content $_.FullName | 
        Where-Object { $_ -match "ERROR|SECURITY" }
    }
```

#### 5. Manage Credentials Securely
```powershell
# Use Windows Credential Manager
cmdkey /add:servername /user:username /pass:password

# Or prompt at runtime
$cred = Get-Credential

# Never hardcode credentials
# Never store in scripts
# Never display in logs
```

#### 6. Monitor for Unauthorized Changes
```powershell
# Use Group Policy Auditing
auditpol.exe /set /subcategory:"File System" /success:enable /failure:enable

# Or use File Integrity Monitoring
# Monitor critical system files for changes
```

#### 7. Keep Systems Updated
```powershell
# Check for Windows updates
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10

# Install critical updates
Install-WindowsUpdate -AcceptAll -AutoReboot
```

### For Contributors

#### 1. Never Commit Credentials
```powershell
# Bad - NEVER DO THIS
$password = "MySecretPassword123"
$cred = New-Object System.Management.Automation.PSCredential("user", (ConvertTo-SecureString $password -AsPlainText -Force))

# Good - Use secure methods
$cred = Get-Credential
$cred = Get-StoredCredential -Target "MyApp"
```

#### 2. Sanitize Logs & Output
```powershell
# Sanitize sensitive data from logs
$logContent = $logContent -replace $password, "[PASSWORD_REDACTED]"
$logContent = $logContent -replace $apiKey, "[API_KEY_REDACTED]"
```

#### 3. Validate All Input
```powershell
# Use parameter attributes for validation
[Parameter(Mandatory=$true)]
[ValidateNotNullOrEmpty()]
[ValidatePattern('^[a-zA-Z0-9\-\.]+$')]
[string]$ComputerName
```

#### 4. Implement Error Handling
```powershell
# Always use try-catch for operations
try {
    $result = Invoke-Command -ComputerName $server -ScriptBlock $script
}
catch {
    Write-AuditLog "Error on $server : $_" -Level ERROR
    throw
}
finally {
    # Cleanup - clear sensitive variables
}
```

#### 5. Use Least Privilege
```powershell
# Only request necessary permissions
#Requires -RunAsAdministrator  # Only if truly needed

# Specify minimum version needed
#Requires -Version 5.1  # Not 7.0 if 5.1 works
```

#### 6. Document Security Decisions
```powershell
<#
.SECURITY FEATURES
    - Validates input against injection patterns
    - Uses PSCredential for credential handling
    - Implements comprehensive audit logging
    - Supports WhatIf for preview mode
#>
```

---

## Credential Management

### Best Practices

#### 1. PSCredential Objects
```powershell
# Prompt for credentials (recommended)
$cred = Get-Credential -Message "Enter admin credentials"

# Use securely from console input
$password = Read-Host -Prompt "Password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential("user", $password)
```

#### 2. Windows Credential Manager
```powershell
# Store credentials securely
cmdkey /add:myserver /user:myuser /pass:mypassword

# Retrieve stored credentials
$cred = Get-StoredCredential -Target "myserver"

# Or use CredentialManager module
Install-Module -Name CredentialManager -Force
$cred = Get-StoredCredential -Target "myapp"
```

#### 3. Never Hardcode Credentials
```powershell
# ❌ BAD - Security Risk
$password = "P@ssw0rd123"
$cred = New-Object PSCredential "admin", (ConvertTo-SecureString $password -AsPlainText -Force)

# ✓ GOOD - Secure
$cred = Get-Credential
# or
$cred = Get-StoredCredential -Target "AdminAccount"
```

#### 4. Credential Cleanup
```powershell
# Clear sensitive data after use
$cred.Password.Clear()
$password = $null
[GC]::Collect()  # Force garbage collection
```

#### 5. Pass Credentials Safely
```powershell
# Pass via parameter, not in plaintext
& ".\Script.ps1" -Credential $cred

# NOT like this:
& ".\Script.ps1" -Username "admin" -Password "secret123"
```

### Credential Manager Integration

```powershell
# Save credential for script reuse
$cred = Get-Credential
$cred | Export-CliXml -Path "$env:APPDATA\Cred_ServerName.xml"

# Load in future script runs
$cred = Import-CliXml -Path "$env:APPDATA\Cred_ServerName.xml"

# Note: Encrypted based on user context - only current user can decrypt
```

---

## Audit Logging

### Logging Best Practices

#### 1. Log to Multiple Destinations
```powershell
# File logging
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logMessage = "[$timestamp] [INFO] Operation completed"
Add-Content -Path $logPath -Value $logMessage

# Event Log logging
Write-EventLog -LogName Application -Source "MyScript" -EventId 1000 -Message $logMessage

# Console output
Write-Host $logMessage
```

#### 2. Log Security Events
```powershell
function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $user = [Environment]::UserName
    $computer = $env:COMPUTERNAME
    
    $auditEntry = "[$timestamp] [$Level] User: $user | Computer: $computer | $Message"
    
    # File log
    Add-Content -Path $logPath -Value $auditEntry
    
    # Event log
    $eventType = @{
        'INFO'    = 'Information'
        'WARNING' = 'Warning'
        'ERROR'   = 'Error'
        'SECURITY' = 'SuccessAudit'
    }[$Level]
    
    Write-EventLog -LogName Application -Source "ScriptExecution" `
        -EventId 1000 -EntryType $eventType -Message $auditEntry
}
```

#### 3. Sanitize Sensitive Data
```powershell
# Never log credentials
Write-Log "Connected as $($cred.UserName)"  # OK
# Write-Log $cred  # NEVER DO THIS

# Sanitize IP addresses from logs
$logContent = $logContent -replace '\b(?:\d{1,3}\.){3}\d{1,3}\b', '[IP_ADDRESS]'

# Sanitize email addresses
$logContent = $logContent -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', '[EMAIL]'

# Sanitize file paths
$logContent = $logContent -replace '\\\\[^\\]*\\', '[UNC_PATH]\'
```

#### 4. Log Retention
```powershell
# Archive old logs
$oldLogs = Get-ChildItem -Path "C:\Logs" -Filter "*.log" `
    -CreationTime (Get-Date).AddMonths(-1)
$oldLogs | Move-Item -Destination "C:\Logs\Archive"

# Delete very old logs (after compliance period)
Get-ChildItem -Path "C:\Logs\Archive" -Filter "*.log" `
    -CreationTime (Get-Date).AddYears(-7) | Remove-Item
```

#### 5. Log Analysis
```powershell
# Find error events
Get-EventLog -LogName Application -Source "ScriptExecution" -EntryType Error -After (Get-Date).AddDays(-7)

# Search logs for specific patterns
Select-String -Path "C:\Logs\*.log" -Pattern "ERROR|SECURITY"

# Generate summary report
Get-ChildItem -Path "C:\Logs" -Filter "*.log" | 
    ForEach-Object { Get-Content $_.FullName } |
    Group-Object { $_ -match "ERROR" } |
    Select-Object Name, Count
```

---

## Compliance Standards

### Standards Alignment

#### NIST SP 800-53 (Security & Privacy Controls)

- **AU-2**: Audit Events - Comprehensive logging
- **AU-3**: Content of Audit Records - Detailed audit information
- **AU-12**: Audit Generation, Integration, and Retention - Log storage
- **CM-3**: Configuration Change Control - Change management
- **CM-6**: Configuration Settings - Secure defaults
- **CP-9**: Information System Backup - Backup procedures
- **SC-8**: Transmission Confidentiality and Integrity - Secure communications
- **SI-10**: Information System Monitoring - Input validation

#### DISA STIG (Security Technical Implementation Guide)

- PowerShell hardening requirements
- Credential management standards
- Audit logging requirements
- Error handling expectations

#### FedRAMP

- Federal information security standards
- Control implementation verification
- Documentation requirements
- Third-party assessment compatibility

#### Fourth Estate Requirements

- Defense-in-depth security
- Least privilege enforcement
- Comprehensive audit trails
- Incident response procedures

### Compliance Verification

```powershell
# Verify audit logging enabled
Get-EventLog -LogName Application -Source "ScriptExecution" | Measure-Object

# Check firewall configuration
Get-NetFirewallProfile | Select-Object Name, Enabled

# Verify admin access restrictions
Get-LocalGroupMember -Group "Administrators"

# Check password policy
Get-ADDefaultDomainPasswordPolicy | Select-Object MaxPasswordAge, MinPasswordLength

# Audit SMBv1 disabled
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol
```

---

## Security Updates

### Receiving Updates

#### 1. Watch Repository
```
Click "Watch" → "All Activity" on GitHub repository
```

#### 2. Subscribe to Security Advisories
```
Click "Security" → "Advisories" → "Enable notifications"
```

#### 3. Email Notifications
```
Add email to list: security-updates@github.com/Koga1985
```

#### 4. RSS Feed
```
Subscribe to: https://github.com/Koga1985/PowerShell-Scripts/security/advisories.atom
```

### Applying Updates

```powershell
# 1. Backup current version
Copy-Item -Path ".\Scripts" -Destination ".\Scripts.backup"

# 2. Update to latest version
git pull origin main

# 3. Run prerequisite setup
.\Setup-Prerequisites.ps1

# 4. Review changelog
Get-Content CHANGELOG.md | Select-String "^## \[" -Context 5

# 5. Test updated scripts
.\Script.ps1 -WhatIf

# 6. Deploy to production after validation
```

### Patch Timeline

- **Critical (CVSS 9-10)**: Within 7 days
- **High (CVSS 7-8)**: Within 30 days
- **Medium (CVSS 4-6)**: Within 60 days
- **Low (CVSS 0-3)**: Next regular release

---

## Incident Response

### Reporting Security Incidents

If you discover a security incident or breach:

1. **Immediate Actions**
   ```powershell
   # Stop affected script
   Stop-Process -Name "powershell" -Force
   
   # Preserve evidence
   Copy-Item -Path "C:\Logs" -Destination "C:\Logs.backup" -Recurse
   
   # Isolate systems if necessary
   Disconnect-VIServer -Force
   Disconnect-SMBShare -Force
   ```

2. **Report Security Incident**
   - Email: security@github.com
   - Include: Timeline, affected systems, potential impact
   - Preserve: Logs, transcripts, error messages

3. **Containment**
   - Disable compromised accounts
   - Reset exposed credentials
   - Review audit logs for unauthorized access
   - Apply emergency patches

4. **Recovery**
   - Restore from clean backups
   - Verify system integrity
   - Re-enable with updated security
   - Monitor for recurrence

### Example Incident Response

```powershell
# Timeline of incident
$timeline = @{
    '2026-05-08 14:23' = 'Suspicious activity detected in logs'
    '2026-05-08 14:25' = 'Script execution halted'
    '2026-05-08 14:27' = 'Event logs archived'
    '2026-05-08 14:30' = 'Security team notified'
    '2026-05-08 15:00' = 'Initial investigation began'
    '2026-05-08 16:00' = 'Root cause identified'
    '2026-05-08 17:00' = 'Emergency patch deployed'
}

# Document findings
$findings = @{
    RootCause = "Unvalidated input in parameter X"
    Impact = "Potential code execution in Y systems"
    Mitigation = "Patch applied restricting input format"
    Severity = "HIGH"
}
```

---

## Bug Bounty Program

Currently **not active**. When established, details will be published at:
- GitHub Security page
- Security advisory section
- Dedicated Bug Bounty Platform

---

## Security Contacts

- **General Security**: security@github.com
- **Maintenance**: Dewain Smith #TheBeardedEngineer
- **Repository**: https://github.com/Koga1985/PowerShell-Scripts

---

## Changelog

### Security Policy Updates

| Date       | Update |
|-----------|--------|
| 2026-05-08 | Initial security policy creation |

---

**Last Updated:** May 8, 2026
**Maintained By:** Dewain Smith #TheBeardedEngineer
**Version:** 1.0

