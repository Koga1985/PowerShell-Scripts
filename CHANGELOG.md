# Changelog

All notable changes to the PowerShell-Scripts repository are documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## [2.0] - 2025-10-30

### Added
- Comprehensive audit logging to file and Windows Event Log across all scripts
- Full session transcription for compliance trails
- Input validation and sanitization for all parameters
- WhatIf/Confirm support for destructive operations
- Rollback capability for configuration changes
- Security compliance documentation (NIST 800-53, DISA STIG, FedRAMP)
- Event logging integration with proper event IDs
- Credential handling using PSCredential objects
- Automatic prerequisite checking and installation
- Environment variable support for flexible deployment

### Enhanced Scripts
- **Job Status.ps1** - Enhanced with robust error handling and credential management
- **AutomatedPatchManagement.ps1** - Added pre-flight connectivity checks and scheduling support
- **Health Check.ps1** - Improved with strict certificate validation and resource isolation
- **Windows Hardening.ps1** - Expanded with STIG baseline configurations
- **Backup Storage Calculator.ps1** - Added capacity planning audit logging
- **HyperV Hardening.ps1** - Enhanced with system restore point creation and rollback capability
- **Snapshot Creation.ps1** - Improved error handling and validation
- **Log Scrubber.ps1** - Enhanced path traversal protection and backup capabilities
- **Disable SMBv1.ps1** - Added verification and registry validation
- **Remove Snapshot.ps1** - Improved confirmation prompts and resource cleanup
- **LogOn Creds.ps1** - Enhanced credential handling and service restart logic
- **DocumentationGenerator.ps1** - Improved Markdown generation and index creation
- **Simple Lab Deployment.ps1** - Added datastore validation and network connectivity checks

### Changed
- All scripts now require PowerShell 5.1+ and Administrator privileges
- Moved from legacy WMI to modern CIM cmdlets where applicable
- Standardized parameter naming conventions
- Updated logging directory structures
- Improved error messages with actionable guidance
- Enhanced help documentation with compliance references

### Fixed
- Path validation vulnerabilities
- Injection attack surface reduction
- Session cleanup improvements
- Event log source registration errors
- Transcript path handling

### Deprecated
- Legacy WMI-based operations (use CIM alternatives)

### Security
- Credential Manager integration for secure credential storage
- Sensitive data memory cleanup on exit
- Input validation against known injection patterns
- Network security validation
- Certificate pinning for VMware operations

### Documentation
- Added comprehensive SECURITY.md policy
- Enhanced CONTRIBUTING.md guidelines
- Added CHANGELOG.md for version tracking
- Created Troubleshooting guide
- Added Integration documentation
- Created Rollback procedures guide
- Added setup prerequisite script

## [1.0] - 2024-01-15

### Initial Release
- Initial collection of IT automation scripts
- Veeam Backup & Replication management
- VMware vSphere/ESXi automation
- Windows Server hardening
- Hyper-V management
- Active Directory utilities
- Lab deployment automation
- Basic logging and error handling
- Parameter validation
- Help documentation

---

## Version Numbering

- **MAJOR** version incremented for breaking changes or significant feature additions
- **MINOR** version incremented for new features in a backwards-compatible manner
- **PATCH** version incremented for bug fixes and security patches

## Upgrade Path

- **v1.0 → v2.0**: Full review of all scripts recommended. Test in non-production before deploying to production.
- No breaking changes in parameters; all v1.0 scripts compatible with v2.0 execution environment.

## Future Roadmap

### Planned for v3.0
- PowerShell module structure reorganization
- Pester unit test framework integration
- CI/CD pipeline with GitHub Actions
- Performance monitoring and profiling
- Machine Learning-based anomaly detection
- REST API wrapper for script orchestration
- Slack/Teams integration for notifications

### Community Contributions Welcome
- Bug reports and feature requests: [GitHub Issues](https://github.com/Koga1985/PowerShell-Scripts/issues)
- Pull requests: See CONTRIBUTING.md for guidelines

---

**Last Updated:** May 8, 2026
**Maintained By:** Dewain Smith #TheBeardedEngineer
