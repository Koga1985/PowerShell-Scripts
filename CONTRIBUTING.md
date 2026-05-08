# Contributing to PowerShell-Scripts

Thank you for your interest in contributing! This document provides guidelines and procedures for contributing to the PowerShell-Scripts repository.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Contribution Types](#contribution-types)
- [Development Standards](#development-standards)
- [Submission Process](#submission-process)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Documentation Standards](#documentation-standards)
- [Security Considerations](#security-considerations)

## Code of Conduct

We are committed to providing a welcoming and inclusive environment for all contributors. All contributors are expected to:

- Be respectful and constructive
- Assume good intentions
- Focus on the code, not the person
- Report violations to the maintainers

## Getting Started

1. **Fork the Repository** - Click the "Fork" button on GitHub
2. **Clone Your Fork** - `git clone https://github.com/YOUR-USERNAME/PowerShell-Scripts.git`
3. **Create a Branch** - `git checkout -b feature/your-feature-name`
4. **Make Changes** - Follow the guidelines below
5. **Commit with Clear Messages** - Use conventional commit format
6. **Push to Your Fork** - `git push origin feature/your-feature-name`
7. **Create a Pull Request** - Submit your PR with a descriptive title

## Contribution Types

### Bug Fixes
- **Scope**: Fix existing issues without changing intended functionality
- **Requirements**:
  - Clear description of the bug
  - Steps to reproduce
  - Expected vs. actual behavior
  - Link to related issue (if applicable)

### Feature Additions
- **Scope**: New functionality or scripts for the repository
- **Requirements**:
  - Discussion via issue before major features
  - Follows coding standards
  - Includes documentation
  - Includes examples
  - Tested in multiple environments

### Documentation Improvements
- **Scope**: README, guides, comments, help content
- **Requirements**:
  - Clear, accurate information
  - Consistent formatting
  - Spell-checked and grammar-reviewed

### Security Enhancements
- **Scope**: Security patches and hardening improvements
- **Requirements**:
  - Follows SECURITY.md disclosure process
  - Detailed threat model
  - Mitigation validation
  - No public discussion before patch release

### Module Enhancements
- **Scope**: Improvements to existing module structure
- **Requirements**:
  - Maintains backward compatibility
  - Updates version in module manifest
  - Updates CHANGELOG.md

## Development Standards

### PowerShell Version
- Minimum supported version: **PowerShell 5.1**
- Target compatibility: **PowerShell 5.1 through latest stable**

### Repository Structure
```
PowerShell-Scripts/
├── Environment/           # Environment setup scripts
├── Hyper-V/              # Hyper-V management
├── Lab/                  # Lab deployment
├── Toolkit/              # Utility and toolkit scripts
├── Veeam/                # Veeam backup automation
├── VMware/               # VMware automation
├── Windows/              # Windows administration
├── Modules/              # Reusable PowerShell modules
├── Tests/                # Pester test files
├── Docs/                 # Documentation
├── Setup-Prerequisites.ps1
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE
```

### New Script Guidelines
1. **Category Placement** - Choose appropriate subfolder
2. **Naming Convention** - Use descriptive names with spaces: `My Script Name.ps1`
3. **Module Prefix** - If creating a module, use: `Prefix-Verb-Noun.psm1`
4. **Manifest Files** - Modules require `.psd1` manifest

## Submission Process

### Before Submitting

- [ ] Code follows PowerShell best practices
- [ ] Script includes help documentation (comment-based help)
- [ ] All parameters validated with appropriate attributes
- [ ] Error handling implemented (try-catch blocks)
- [ ] Logging functionality included
- [ ] WhatIf/Confirm support for destructive operations
- [ ] Tested in non-production environment
- [ ] No hardcoded credentials or sensitive data
- [ ] No third-party code without proper attribution

### Pull Request Checklist

- [ ] Branch name follows pattern: `feature/name` or `fix/issue-name`
- [ ] Title clearly describes changes
- [ ] Description includes motivation and context
- [ ] References related issue(s) with `#ISSUE_NUMBER`
- [ ] CHANGELOG.md updated with changes
- [ ] Documentation updated if applicable
- [ ] No merge conflicts with main branch
- [ ] Commits are logical and well-message

### PR Title Format

```
[TYPE] Brief description

Types: Feature, Fix, Enhancement, Documentation, Security
Examples:
  [Feature] Add AWS S3 backup verification
  [Fix] Resolve SMBv1 registry validation
  [Enhancement] Improve error messages in Patch Management
  [Documentation] Add troubleshooting guide
  [Security] Patch credential exposure vulnerability
```

### PR Description Template

```markdown
## Description
Brief description of changes

## Motivation
Why this change is needed

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Enhancement
- [ ] Documentation
- [ ] Security patch

## Related Issue
Closes #ISSUE_NUMBER

## Testing
Describe testing performed:
- [ ] Tested in non-production
- [ ] Tested on PowerShell 5.1
- [ ] Tested on PowerShell 7.x
- [ ] Tested on Windows Server 2019+
- [ ] Tested on Windows 10/11

## Environment
- OS: Windows Server/Desktop version
- PowerShell Version: 5.1 / 7.x
- Modules: List modules required for testing

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated
- [ ] No new warnings generated
- [ ] Tested locally
```

## Coding Standards

### Script Header
Every script must include:
```powershell
<#
.SYNOPSIS
    Brief description (one line)

.DESCRIPTION
    Detailed description of functionality

.PARAMETER ParameterName
    Description of parameter

.EXAMPLE
    .\ScriptName.ps1 -Parameter value
    Description of example

.NOTES
    Author:         Your Name
    Repository:     https://github.com/Koga1985/PowerShell-Scripts
    License:        MIT
    Last Updated:   YYYY-MM-DD
    Version:        X.Y
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

### Function Standards
- Use verb-noun naming: `Get-ServerHealth`, `Set-ConfigValue`
- Include comment-based help for all functions
- Validate all parameters
- Use consistent naming conventions

### Variables
- Use descriptive names in camelCase: `$computerName`, `$errorCount`
- Prefix script scope: `$script:AuditLogPath`
- Prefix global scope: `$Global:ConfigSettings` (use sparingly)

### Error Handling
```powershell
try {
    # Code here
}
catch {
    Write-Log "Error message: $_" -Level ERROR
    throw
}
finally {
    # Cleanup code
}
```

### Logging
All scripts should implement:
```powershell
function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SECURITY')]
        [string]$Level = 'INFO'
    )
    # Log to file and event log
}
```

## Testing Requirements

### Mandatory Testing
- [ ] Script executes without syntax errors
- [ ] All parameters work as documented
- [ ] Help documentation displays correctly
- [ ] Error conditions handled gracefully
- [ ] Logging captures all important events
- [ ] WhatIf simulates actions correctly
- [ ] Confirm prompts work as expected

### Environment Testing
- [ ] Tested in isolated lab environment
- [ ] Tested with least-privilege account
- [ ] Tested with elevated administrator account
- [ ] Verified behavior on target system

### Pester Tests (If Applicable)
```powershell
Describe "Script-Name" {
    It "Should do something" {
        # Test assertion
    }
}
```

## Documentation Standards

### Help Content
- Accurate and current information
- Clear, concise language
- Multiple examples for complex functionality
- Links to related scripts
- Version history if applicable

### Comments
- Comment complex logic, not obvious code
- Use region tags for organization
- Keep comments up-to-date with code

### README Updates
- Document new scripts added
- Update module lists if applicable
- Add prerequisites if needed

## Security Considerations

### Required Security Practices
1. **No Credentials in Code** - Use PSCredential or Credential Manager
2. **Input Validation** - Validate all user inputs
3. **Secure Logging** - Don't log sensitive data
4. **Error Messages** - Don't expose system details
5. **Permissions** - Request minimum necessary privileges
6. **Audit Logging** - Log all significant actions
7. **Memory Cleanup** - Clear sensitive data after use

### Security Review Checklist
- [ ] No hardcoded passwords or tokens
- [ ] All inputs validated
- [ ] Sensitive data not logged
- [ ] Error messages don't reveal system details
- [ ] Principle of least privilege enforced
- [ ] Audit logging implemented
- [ ] External input sanitized
- [ ] No deprecated cmdlets used

### Reporting Security Issues
**Do not open public issues for security vulnerabilities.**

Follow the process in [SECURITY.md](SECURITY.md) for responsible disclosure.

## Review Process

1. **Automated Checks** - Code style, syntax validation
2. **Maintainer Review** - Functionality, security, standards
3. **Testing Verification** - Confirmation of test results
4. **Documentation Review** - Help content and guides
5. **Approval & Merge** - Maintainer approval required

## After Merge

- Your contribution will be included in the next release
- You'll be recognized in CHANGELOG.md
- Your GitHub profile may be featured in repository discussions

## Getting Help

- **Questions**: Open a GitHub Discussion
- **Issues**: Search existing issues before creating new
- **Documentation**: Check README.md and script headers
- **Email**: Contact maintainer for sensitive topics

## License

By contributing, you agree that your contributions will be licensed under the MIT License. All contributions must respect existing licenses and attribute third-party code appropriately.

---

**Thank you for contributing to PowerShell-Scripts!**

*Last Updated: May 8, 2026*
*Maintained By: Dewain Smith #TheBeardedEngineer*
