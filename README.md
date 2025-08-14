
Can# PowerShell Scripts for IT Automation

## Overview
This repository contains a comprehensive collection of PowerShell scripts designed to automate, secure, and manage IT environments. The scripts cover a wide range of tasks, including:
- **Veeam Backup & Replication**: Job status, log management, best practices, and hardening.
- **VMware vSphere/ESXi**: VM tagging, migration, health checks, snapshot management, audit and cleanup, and more.
- **Windows Server & Desktop**: Service credential management, UAC configuration, SMBv1 disabling, AD self-healing, Cortana disabling, and other hardening tasks.
- **Hyper-V**: Security hardening and STIG compliance.
- **Lab Automation**: Automated deployment of home lab environments.
- **Environment Toolkit**: One-line functions for everyday IT tasks.

Scripts are organized by technology and use case in subfolders for easy navigation.

## Usage Instructions
1. **Prerequisites**
   - Run scripts in an elevated (Administrator) PowerShell session.
   - Ensure required modules are installed:
     - `Veeam.Backup.PowerShell` for Veeam scripts
     - `VMware.PowerCLI` for VMware scripts
     - `Hyper-V` module for Hyper-V scripts
     - `ActiveDirectory` module for AD scripts
   - Some scripts require network connectivity to remote servers or vCenter/ESXi hosts.

2. **Running a Script**
   - Open PowerShell as Administrator.
   - Navigate to the script's folder.
   - Review the script header for usage notes, parameters, and examples.
   - Execute the script, providing required parameters if prompted.
   - Example:
     ```powershell
     .\Job Status.ps1
     .\VM Migration.ps1
     .\Set UAC Level.ps1 -Level 2
     ```

3. **Logging & Output**
   - Most scripts log actions and errors to both the console and a log file (see script header for log location).
   - Summary output is provided at the end of each script for quick review.

4. **Customization**
   - Scripts are designed to be modular and easy to modify for your environment.
   - Update variables (e.g., server names, paths) as needed.
   - Inline comments and usage notes are included for clarity.

## Disclaimer

> **Warning:**
> These scripts are provided as-is, without warranty of any kind. Use at your own risk.
> - Always test scripts in a non-production environment before deploying to production.
> - The authors and contributors are not responsible for any damage, data loss, or security issues resulting from the use or misuse of these scripts.
> - Review and understand each script before running, especially those that modify system or network configurations.
> - Ensure you have appropriate backups and change management procedures in place.

## Contributing
- Pull requests and suggestions are welcome! Please ensure your contributions follow best practices for PowerShell scripting and include clear documentation.

## License
This repository is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Contact
For questions, issues, or feature requests, please open an issue on GitHub.

---

**Author:** Dewain Smith #TheBeardedEngineer
**Last Updated:** August 14, 2025



