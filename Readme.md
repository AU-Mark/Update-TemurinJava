# Update-TemurinJava.ps1

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)
[![Admin Required](https://img.shields.io/badge/Admin-Required-red.svg)](#requirements)
[![Eclipse Temurin](https://img.shields.io/badge/Eclipse%20Temurin-OpenJDK-orange.svg)](https://adoptium.net/)
[![Auto Update](https://img.shields.io/badge/Updates-Automated-green.svg)](#how-it-works)
[![Version](https://img.shields.io/badge/Version-1.0-green.svg)](#version-history)

An enterprise-grade PowerShell script for automated management of Adoptium Eclipse Temurin OpenJDK/OpenJRE installations on Windows systems, featuring automatic update detection, silent installation, and scheduled task integration for continuous Java version management.

## 🔥 Features

- **Automatic Update Detection** - Monitors installed Temurin versions and checks GitHub releases for updates within the same major version
- **Silent Installation & Updates** - Performs unattended installations and updates without user interaction
- **Multi-Version Support** - Manages Java 8, 11, 17, and 21 simultaneously on the same system
- **Architecture Flexibility** - Supports both x64 and x86 architectures for diverse environment needs
- **JRE/JDK Selection** - Install and manage both JRE and JDK distributions based on requirements
- **Self-Installing Architecture** - Automatically deploys to ProgramData and creates scheduled tasks for daily checks
- **Comprehensive Logging** - Detailed logging with automatic rotation, compression, and MSI installation logs
- **SHA256 Verification** - Validates all downloaded installers using official SHA256 checksums
- **Process-Aware Updates** - Intelligently waits for running Java processes to close before updating
- **Enterprise-Ready Retry Logic** - Implements exponential backoff for failed downloads with configurable attempts

## 📋 Requirements

- **Windows 10, Windows 11, or Windows Server 2016+**
- **PowerShell 5.1 or later**
- **Administrative privileges** (required for installation and scheduled task creation)
- **.NET Framework 4.5+** (for System.Net.Http functionality)
- **Internet connectivity** to GitHub API and Adoptium CDN
- **500MB+ free disk space** for downloads and temporary files

## 🚀 Quick Start

### Check and Update Existing Installations
```powershell
.\Update-TemurinJava.ps1
```

### Install and Configure Auto-Updates
```powershell
.\Update-TemurinJava.ps1 -Force
```

### Install Specific Java Versions
```powershell
# Install JRE 8 and 17 for x64
.\Update-TemurinJava.ps1 -Install -Versions "8,17" -Arch "x64" -Type "JRE"

# Install JDK 21 for x64
.\Update-TemurinJava.ps1 -Install -Versions "21" -Arch "x64" -Type "JDK"
```

## 📖 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Install` | Switch | - | Enables installation mode for new Java versions |
| `Versions` | String | - | Comma-separated list of major versions to install (8,11,17,21) |
| `Arch` | String | - | Architecture to install: **x64** or **x86** |
| `Type` | String | `JRE` | Installation type: **JRE** or **JDK** |
| `Force` | Switch | `False` | Forces script reinstallation even if already present |
| `SkipScheduledTask` | Switch | `False` | Skips scheduled task creation during installation |

## 🛠️ How It Works

The script provides comprehensive Java version management through automated detection, comparison, and update mechanisms:

### 1. **Installation Detection System**
- **Registry Scanning**: Queries Windows registry for all Eclipse Adoptium installations
- **Version Parsing**: Extracts version information from display names and registry values
- **Multi-Format Support**: Handles both Java 8 format (8u432b06) and modern format (17.0.9+9)
- **Architecture Detection**: Identifies x64 and x86 installations independently

### 2. **GitHub API Integration**
- **Release Monitoring**: Queries Adoptium's GitHub repositories for latest releases
- **Asset Matching**: Identifies correct MSI installers based on version, type, and architecture
- **SHA256 File Detection**: Locates corresponding checksum files for integrity verification
- **Version Extraction**: Parses version numbers from release assets for comparison

### 3. **Intelligent Version Comparison**
- **Major Version Matching**: Only updates within the same major version (e.g., Java 8 stays Java 8)
- **Build Number Analysis**: Compares update and build numbers for Java 8 format
- **Semantic Versioning**: Handles modern version format for Java 11+ releases
- **Update Decision Logic**: Determines if newer version is available based on comprehensive comparison

### 4. **Download and Verification System**
- **HttpClient Implementation**: Uses System.Net.Http.HttpClient for efficient downloads
- **Progress Tracking**: Real-time progress bars with speed and completion estimates
- **Retry Mechanism**: Exponential backoff with configurable maximum attempts
- **SHA256 Validation**: Verifies downloaded files against official checksums before installation
- **Automatic Cleanup**: Removes temporary files after successful installation or on failure

### 5. **Process-Safe Installation**
- **Java Process Detection**: Identifies running java.exe and javaw.exe processes
- **Graceful Waiting**: Waits indefinitely for processes to close with periodic status updates
- **Silent MSI Execution**: Runs installations with comprehensive logging and error capture
- **Revision Handling**: Automatically uninstalls same-version builds before installing updates

### 6. **Self-Installation and Scheduling**
- **Script Deployment**: Copies itself to `C:\ProgramData\Update-TemurinJava\`
- **Scheduled Task Creation**: Configures daily checks at 8:00 AM and system startup
- **SYSTEM Account Execution**: Runs with highest privileges for system-wide updates
- **Automatic Logging**: Creates detailed logs with rotation and compression

## 📂 Supported Java Versions

### Version Compatibility Matrix
| Major Version | LTS Status | Version Format | Example | GitHub Repository |
|---------------|------------|----------------|---------|-------------------|
| **Java 8** | LTS | 8u{update}b{build} | 8u432b06 | [temurin8-binaries](https://github.com/adoptium/temurin8-binaries) |
| **Java 11** | LTS | {major}.{minor}.{patch}+{build} | 11.0.25+9 | [temurin11-binaries](https://github.com/adoptium/temurin11-binaries) |
| **Java 17** | LTS | {major}.{minor}.{patch}+{build} | 17.0.13+11 | [temurin17-binaries](https://github.com/adoptium/temurin17-binaries) |
| **Java 21** | LTS | {major}.{minor}.{patch}+{build} | 21.0.5+11 | [temurin21-binaries](https://github.com/adoptium/temurin21-binaries) |

### Installation Features by Type
| Feature | JRE | JDK |
|---------|-----|-----|
| Java Runtime | ✅ | ✅ |
| Development Tools | ❌ | ✅ |
| JAR File Association | ✅ | ✅ |
| JAVA_HOME Variable | ✅ | ✅ |
| PATH Integration | ✅ | ✅ |
| Oracle Registry Keys | ❌ | ✅ |

## 🔧 Advanced Configuration

### Customizable Script Variables

**Installation Paths**
```powershell
$Script:InstallPath = 'C:\ProgramData\Update-TemurinJava'
$Script:TempDownloadPath = Join-Path $Script:InstallPath 'Installers'
$Script:LogPath = 'C:\ProgramData\Update-TemurinJava\Logs'
```

**Scheduled Task Configuration**
```powershell
$Script:ScheduledTaskName = 'UpdateTemurinJava'
$Script:ScheduledTaskDescription = 'Daily check for Adoptium Eclipse Temurin Java updates'
$Script:ScheduledTaskTime = '08:00:00'
```

**Update Behavior**
```powershell
$Script:MaxRetryAttempts = 5
$Script:InitialRetryDelaySeconds = 5
```

### Enterprise Deployment Scenarios

**Mass Deployment via PowerShell Remoting**
```powershell
# Deploy to multiple servers
$Servers = Get-Content "C:\Infrastructure\JavaServers.txt"
$ScriptPath = "\\FileServer\Scripts\Update-TemurinJava.ps1"

Invoke-Command -ComputerName $Servers -ScriptBlock {
    param($Path)
    & $Path -Install -Versions "11,17" -Arch "x64" -Type "JRE"
} -ArgumentList $ScriptPath
```

**Group Policy Deployment**
```powershell
# Computer Configuration > Policies > Windows Settings > Scripts > Startup
# Add script with parameters:
-Install -Versions "8,11,17,21" -Arch "x64" -Type "JRE"
```

**SCCM/ConfigMgr Application**
```powershell
# Detection Method: Registry key existence
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{GUID}

# Installation Program:
powershell.exe -ExecutionPolicy Bypass -File "Update-TemurinJava.ps1" -Install -Versions "17" -Arch "x64" -Type "JDK"
```

### Logging Architecture

**Log File Structure**
```
C:\ProgramData\Update-TemurinJava\
├── Logs\
│   ├── Update-TemurinJava.log          # Primary log file (current)
│   ├── Update-TemurinJava.1.log        # Rotated log file
│   ├── Update-TemurinJava-archive.zip  # Compressed historical logs
│   └── MSI_Logs\
│       ├── OpenJDK8U-jre_x64_Install_20250815_140023.log
│       ├── OpenJDK17U-jdk_x64_Update_20250815_140512.log
│       └── Eclipse_Temurin_JRE_Uninstall_20250815_135847.log
```

**Log Rotation Configuration**
- **Rotation Trigger**: 1MB file size
- **Maximum Rotated Files**: 5
- **Compression**: Automatic ZIP archiving
- **MSI Logs**: Verbose logging with timestamps

## 📊 Examples

### Example 1: Initial Setup with Auto-Updates
```powershell
PS C:\> .\Update-TemurinJava.ps1 -Force
```

**Expected Output:**
```
[2025-08-15 14:00:00][INFO] Starting Temurin Java Update Script
[2025-08-15 14:00:00][INFO] Script version: 1.0
[2025-08-15 14:00:00][INFO] Execution mode: Update
[2025-08-15 14:00:00][INFO] Script not running from installation directory
[2025-08-15 14:00:01][INFO] Creating installation directory: C:\ProgramData\Update-TemurinJava\Update-TemurinJava
[2025-08-15 14:00:01][INFO] Copying script to C:\ProgramData\Update-TemurinJava\Update-TemurinJava\Update-TemurinJava.ps1
[2025-08-15 14:00:01][SUCCESS] Script copied successfully
[2025-08-15 14:00:01][INFO] Creating scheduled task
[2025-08-15 14:00:02][SUCCESS] Scheduled task created successfully
[2025-08-15 14:00:02][INFO] Update mode - checking existing installations
[2025-08-15 14:00:02][INFO] Detecting installed Temurin Java installations
[2025-08-15 14:00:03][INFO] Found: Eclipse Temurin JRE with Hotspot 8u432-b06 (x64) - Version: 8u432b06
[2025-08-15 14:00:03][INFO] Found 1 Temurin installation(s)
[2025-08-15 14:00:03][INFO] Checking for updates: Eclipse Temurin JRE with Hotspot 8u432-b06 (x64)
[2025-08-15 14:00:04][INFO] Update available: 8u432b06 -> 8u462b08
[2025-08-15 14:00:04][INFO] Updating Eclipse Temurin JRE with Hotspot 8u432-b06 (x64) from 8u432b06 to 8u462b08
[2025-08-15 14:00:05][INFO] Downloading MSI (Attempt 1/5): OpenJDK8U-jre_x64_windows_hotspot_8u462b08.msi
[2025-08-15 14:00:45][SUCCESS] SHA256 verification successful - hashes match
[2025-08-15 14:00:45][INFO] Installing new version
[2025-08-15 14:00:55][SUCCESS] Successfully updated Eclipse Temurin JRE with Hotspot 8u432-b06 (x64) to version 8u462b08
[2025-08-15 14:00:55][INFO] Update check complete. Updated: 1, Failed: 0
[2025-08-15 14:00:55][SUCCESS] Script execution completed
```

### Example 2: Installing Multiple Java Versions
```powershell
PS C:\> .\Update-TemurinJava.ps1 -Install -Versions "8,11,17,21" -Arch "x64" -Type "JRE"
```

**Expected Output:**
```
[2025-08-15 14:10:00][INFO] Starting Temurin Java Update Script
[2025-08-15 14:10:00][INFO] Installation mode activated
[2025-08-15 14:10:00][INFO] Processing installation request for Java 8
[2025-08-15 14:10:00][INFO] Installing Temurin Java 8 JRE (x64)
[2025-08-15 14:10:01][INFO] Latest version available: 8u462b08
[2025-08-15 14:10:01][INFO] Downloading MSI (Attempt 1/5): OpenJDK8U-jre_x64_windows_hotspot_8u462b08.msi
[2025-08-15 14:10:41][SUCCESS] SHA256 verification successful - hashes match
[2025-08-15 14:10:41][INFO] Starting installation
[2025-08-15 14:10:51][SUCCESS] Successfully installed Java 8 JRE version 8u462b08
[2025-08-15 14:10:51][INFO] Processing installation request for Java 11
[2025-08-15 14:10:52][INFO] Installing Temurin Java 11 JRE (x64)
[2025-08-15 14:10:52][INFO] Latest version available: 11.0.25_9
[2025-08-15 14:10:53][INFO] Downloading MSI (Attempt 1/5): OpenJDK11U-jre_x64_windows_hotspot_11.0.25_9.msi
[2025-08-15 14:11:35][SUCCESS] SHA256 verification successful - hashes match
[2025-08-15 14:11:35][INFO] Starting installation
[2025-08-15 14:11:45][SUCCESS] Successfully installed Java 11 JRE version 11.0.25_9
[2025-08-15 14:11:45][INFO] Processing installation request for Java 17
[2025-08-15 14:11:46][INFO] Installing Temurin Java 17 JRE (x64)
[2025-08-15 14:11:46][INFO] Latest version available: 17.0.13_11
[2025-08-15 14:11:47][INFO] Downloading MSI (Attempt 1/5): OpenJDK17U-jre_x64_windows_hotspot_17.0.13_11.msi
[2025-08-15 14:12:30][SUCCESS] SHA256 verification successful - hashes match
[2025-08-15 14:12:30][INFO] Starting installation
[2025-08-15 14:12:40][SUCCESS] Successfully installed Java 17 JRE version 17.0.13_11
[2025-08-15 14:12:40][INFO] Processing installation request for Java 21
[2025-08-15 14:12:41][INFO] Installing Temurin Java 21 JRE (x64)
[2025-08-15 14:12:41][INFO] Latest version available: 21.0.5_11
[2025-08-15 14:12:42][INFO] Downloading MSI (Attempt 1/5): OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.msi
[2025-08-15 14:13:25][SUCCESS] SHA256 verification successful - hashes match
[2025-08-15 14:13:25][INFO] Starting installation
[2025-08-15 14:13:35][SUCCESS] Successfully installed Java 21 JRE version 21.0.5_11
[2025-08-15 14:13:35][INFO] Installation complete. Success: 4, Failed: 0
[2025-08-15 14:13:35][SUCCESS] Script execution completed
```

### Example 3: Update Check with No Updates Available
```powershell
PS C:\> .\Update-TemurinJava.ps1
```

**Expected Output:**
```
[2025-08-15 15:00:00][INFO] Starting Temurin Java Update Script
[2025-08-15 15:00:00][INFO] Update mode - checking existing installations
[2025-08-15 15:00:00][INFO] Detecting installed Temurin Java installations
[2025-08-15 15:00:01][INFO] Found: Eclipse Temurin JRE with Hotspot 8u462-b08 (x64) - Version: 8u462b08
[2025-08-15 15:00:01][INFO] Found: Eclipse Temurin JRE with Hotspot 11.0.25+9 (x64) - Version: 11.0.25_9
[2025-08-15 15:00:01][INFO] Found: Eclipse Temurin JRE with Hotspot 17.0.13+11 (x64) - Version: 17.0.13_11
[2025-08-15 15:00:01][INFO] Found: Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64) - Version: 21.0.5_11
[2025-08-15 15:00:01][INFO] Found 4 Temurin installation(s)
[2025-08-15 15:00:01][INFO] Checking for updates: Eclipse Temurin JRE with Hotspot 8u462-b08 (x64)
[2025-08-15 15:00:02][INFO] Already up to date: 8u462b08
[2025-08-15 15:00:02][INFO] Checking for updates: Eclipse Temurin JRE with Hotspot 11.0.25+9 (x64)
[2025-08-15 15:00:03][INFO] Already up to date: 11.0.25_9
[2025-08-15 15:00:03][INFO] Checking for updates: Eclipse Temurin JRE with Hotspot 17.0.13+11 (x64)
[2025-08-15 15:00:04][INFO] Already up to date: 17.0.13_11
[2025-08-15 15:00:04][INFO] Checking for updates: Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64)
[2025-08-15 15:00:05][INFO] Already up to date: 21.0.5_11
[2025-08-15 15:00:05][INFO] Update check complete. Updated: 0, Failed: 0
[2025-08-15 15:00:05][SUCCESS] Script execution completed
```

### Example 4: Process Detection and Waiting
```powershell
PS C:\> .\Update-TemurinJava.ps1
```

**Expected Output (with running Java processes):**
```
[2025-08-15 16:00:00][INFO] Starting Temurin Java Update Script
[2025-08-15 16:00:01][INFO] Found: Eclipse Temurin JRE with Hotspot 17.0.12+7 (x64) - Version: 17.0.12_7
[2025-08-15 16:00:02][INFO] Update available: 17.0.12_7 -> 17.0.13_11
[2025-08-15 16:00:02][INFO] Updating Eclipse Temurin JRE with Hotspot 17.0.12+7 (x64) from 17.0.12_7 to 17.0.13_11
[2025-08-15 16:00:02][WARNING] Java processes detected. Waiting for them to close...
[2025-08-15 16:01:02][INFO] Still waiting for Java processes to close (1 minutes)...
[2025-08-15 16:02:02][INFO] Still waiting for Java processes to close (2 minutes)...
[2025-08-15 16:03:15][INFO] All Java processes closed
[2025-08-15 16:03:15][INFO] Installing new version
[2025-08-15 16:03:25][SUCCESS] Successfully updated Eclipse Temurin JRE with Hotspot 17.0.12+7 (x64) to version 17.0.13_11
```

### Example 5: Network Failure with Retry
```powershell
PS C:\> .\Update-TemurinJava.ps1 -Install -Versions "11" -Arch "x64" -Type "JDK"
```

**Expected Output:**
```
[2025-08-15 17:00:00][INFO] Installation mode activated
[2025-08-15 17:00:00][INFO] Processing installation request for Java 11
[2025-08-15 17:00:00][INFO] Installing Temurin Java 11 JDK (x64)
[2025-08-15 17:00:01][INFO] Latest version available: 11.0.25_9
[2025-08-15 17:00:01][INFO] Downloading MSI (Attempt 1/5): OpenJDK11U-jdk_x64_windows_hotspot_11.0.25_9.msi
[2025-08-15 17:00:31][WARNING] Download attempt 1 failed: The operation has timed out
[2025-08-15 17:00:31][DEBUG] Waiting 5 seconds before retry...
[2025-08-15 17:00:36][INFO] Downloading MSI (Attempt 2/5): OpenJDK11U-jdk_x64_windows_hotspot_11.0.25_9.msi
[2025-08-15 17:01:06][WARNING] Download attempt 2 failed: Unable to connect to the remote server
[2025-08-15 17:01:06][DEBUG] Waiting 10 seconds before retry...
[2025-08-15 17:01:16][INFO] Downloading MSI (Attempt 3/5): OpenJDK11U-jdk_x64_windows_hotspot_11.0.25_9.msi
[2025-08-15 17:02:00][SUCCESS] SHA256 verification successful - hashes match
[2025-08-15 17:02:00][INFO] Starting installation
[2025-08-15 17:02:10][SUCCESS] Successfully installed Java 11 JDK version 11.0.25_9
```

## ⚠️ Important Notes

### Script Behavior

**Automatic Self-Installation**
- Script automatically copies itself to ProgramData when run from any other location
- Creates scheduled task for daily update checks unless `-SkipScheduledTask` is specified
- Existing script in target location won't be overwritten without `-Force` parameter

**Update Logic**
- Only updates within the same major version (Java 8 stays Java 8, Java 17 stays Java 17)
- Handles revision updates by uninstalling current version before installing new build
- Waits indefinitely for Java processes to close - does not force termination

**Network Requirements**
- Requires access to `api.github.com` for version information
- Downloads installers from `github.com` CDN
- No proxy authentication support in current version

### Troubleshooting

**Common Issues and Solutions**

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Access Denied** | Cannot create scheduled task or modify registry | Run PowerShell as Administrator |
| **Network Timeout** | Download failures after multiple retries | Check firewall/proxy settings for GitHub access |
| **Script Won't Execute** | Execution policy error | Run: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process` |
| **Java Process Stuck** | Update waiting indefinitely | Manually close Java applications or services |
| **No Updates Found** | Script reports up-to-date when updates exist | Check GitHub API rate limiting |

**Viewing Logs**
```powershell
# View main log
Get-Content "C:\ProgramData\Update-TemurinJava\Logs\Update-TemurinJava.log" -Tail 50

# Check MSI installation logs
Get-ChildItem "C:\ProgramData\Update-TemurinJava\Logs\MSI_Logs\" | Sort-Object LastWriteTime -Descending | Select -First 5

# Monitor real-time log updates
Get-Content "C:\ProgramData\Update-TemurinJava\Logs\Update-TemurinJava.log" -Wait
```

**Manual Verification**
```powershell
# Check installed Temurin versions
Get-WmiObject -Class Win32_Product | Where-Object {$_.Vendor -eq "Eclipse Adoptium"} | Select Name, Version

# Verify scheduled task
Get-ScheduledTask -TaskName "UpdateTemurinJava" | Format-List

# Test GitHub API connectivity
Invoke-RestMethod -Uri "https://api.github.com/repos/adoptium/temurin17-binaries/releases/latest" | Select tag_name
```

### MSI Exit Codes

| Code | Description | Action Required |
|------|-------------|-----------------|
| 0 | Success | None - installation completed |
| 1603 | Fatal error during installation | Check MSI logs for details |
| 1619 | Installation package could not be opened | Verify download completed successfully |
| 1638 | Another version already installed | Script handles automatically |
| 1641 | Restart initiated | System restart required |
| 3010 | Restart required | Schedule system restart |

## 🔍 Script Architecture

### Core Components

**Logger Class System**
- Custom logging implementation with rotation and compression
- Multiple log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL, SUCCESS
- Automatic file rotation at 1MB with ZIP archiving
- Retry logic for file access conflicts

**Download Management**
- `Get-HttpClientDownload` - Modern HTTP client implementation
- Progress tracking with real-time speed calculations
- Configurable timeout and buffer sizes
- Automatic retry with exponential backoff

**Registry Detection**
- `Get-InstalledApplication` - High-performance registry scanner
- Multi-architecture support (32-bit and 64-bit registry views)
- Comprehensive property extraction

**Version Management**
- `Compare-TemurinVersions` - Intelligent version comparison
- Format-aware parsing for Java 8 vs. modern versions
- Build number and update version analysis

**Process Safety**
- Java process detection and monitoring
- Graceful waiting with periodic status updates
- No forced termination to prevent data loss

### File Structure

```
Script Components:
├── Parameters Region
│   ├── Install/Update mode selection
│   └── Configuration parameters
├── Configuration Variables
│   ├── Editable settings
│   └── System constants
├── Logging Functions
│   ├── Logger class definition
│   └── Write-Log implementation
├── Helper Functions
│   ├── MSI exit code descriptions
│   ├── HTTP download client
│   └── Cleanup utilities
├── Detection Functions
│   ├── Temurin installation scanner
│   └── Architecture converter
├── Update Functions
│   ├── GitHub API integration
│   ├── Version comparison
│   └── Update orchestration
├── Install Functions
│   ├── New version installation
│   └── Script self-installation
└── Main Execution
    ├── Initialization
    ├── Mode selection
    └── Error handling
```

## 📝 Version History

- **v1.0** - Initial release (January 2025)
  - Automatic update detection for installed Temurin versions
  - Support for Java 8, 11, 17, and 21
  - Silent installation and update capabilities
  - Self-installing architecture with scheduled task creation
  - Comprehensive logging with rotation and MSI logs
  - SHA256 verification for all downloads
  - Process-aware update mechanism
  - Retry logic with exponential backoff
  - Support for both JRE and JDK installations
  - x64 and x86 architecture support

## 🔗 Related Links

- [Eclipse Temurin Homepage](https://adoptium.net/)
- [Adoptium Documentation](https://adoptium.net/docs/)
- [Temurin Support Matrix](https://adoptium.net/support/)
- [GitHub Releases - Java 8](https://github.com/adoptium/temurin8-binaries/releases)
- [GitHub Releases - Java 11](https://github.com/adoptium/temurin11-binaries/releases)
- [GitHub Releases - Java 17](https://github.com/adoptium/temurin17-binaries/releases)
- [GitHub Releases - Java 21](https://github.com/adoptium/temurin21-binaries/releases)
- [Adoptium Installation Guide](https://adoptium.net/installation/)

---


> **Enterprise Note**: This script is designed for system administrators managing Temurin Java deployments across Windows environments. It provides hands-off Java version management while maintaining full control over update scheduling and system impact. The script's self-installing nature and scheduled task integration make it ideal for deployment through Group Policy, SCCM, or other enterprise management tools.
