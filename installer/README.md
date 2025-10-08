# Checkmk Agent Installation and Configuration Script

This script automates the installation, configuration, and management of the Checkmk monitoring agent and its plugins on Linux systems. It provides a text-based user interface for selecting installation options, configuring plugins, managing local checks, and handling cleanup tasks.

## Features

*   Interactive menu-driven installation of the Checkmk agent.
*   Supports installation of multiple monitoring plugins including:
    *   MySQL/MariaDB
    *   Apache server status
    *   NGINX status
    *   File monitoring
    *   Backup file checks
    *   Various database, storage, monitoring, security, webserver, and network plugins.
*   Integration with Proxmox VE for VM monitoring and blacklist management.
*   Automatic download and installation of required dependencies.
*   Configuration dialogs for specific plugins to tailor monitoring parameters.
*   Supports manual site configuration or selection from predefined cloud/raw site lists.
*   Real-time progress display using whiptail gauges.
*   Cleanup and uninstallation routines for agent and plugins.
*   Error handling and user notifications via dialog boxes.

## Requirements

*   Linux operating system
*   Bash shell
*   whiptail (for dialog UI)
*   wget, dpkg, apt-get (for package management)
*   Internet connection to download agent and plugins
*   Root or sudo privileges for installation and configuration

## Usage

1.  Run the script with appropriate permissions (e.g., `sudo ./manage_checkmk_agent.sh`).
2.  Follow the interactive menus to:
    *   Select installation mode (cloud, raw, manual).
    *   Choose and configure desired monitoring plugins.
    *   Configure site-specific settings such as URLs and registration endpoints.
    *   Review and confirm installation summary.
3.  The script will download and install the Checkmk agent package and dependencies.
4.  Configure additional plugins as prompted.
5.  Optionally, use the script to uninstall and clean up the Checkmk agent installation.

## Plugins

The script supports a wide range of plugins, some of which are enabled by default, others can be selected or deselected during installation:

| Plugin Category | Example Plugins | Description |
| --- | --- | --- |
| Local Checks | Bakery, BorgBackup, SQLDump | Monitoring for bakery, backups, database dumps |
| Database | MySQL, PostgreSQL, MongoDB | Monitoring database status and performance |
| Storage | Ceph, Filesystem stats, SMART | Storage cluster and disk health monitoring |
| Monitoring | Logfile, IBM TSM, SUSE Connect | Log and system state monitoring |
| Security | Kaspersky AV, Symantec AV | Antivirus status monitoring |
| Webserver | Apache, NGINX | Web server performance and status |
| Network | Netstat, IPTables, DNS client | Network connection and firewall monitoring |

## Configuration

*   The script uses whiptail dialogs to prompt for required inputs such as site URL, registration endpoint, and plugin-specific settings.
*   For Proxmox VE environments, it can manage VM blacklists and host configurations.
*   Plugin configurations can be adjusted post-installation through provided menu options.

# Special configurations

## Configuration of local PVE checks

This script supports the integration and management of Proxmox VE (PVE) hosts for advanced monitoring scenarios. Administrators can add or select PVE servers from a maintained host list and define which virtual machines should be excluded from automated discovery using interactive dialogs. Configuration is persistent, allowing host and VM selections to be updated as needed.

**Important:**

*   SSH key-based authentication must be pre-configured between the Checkmk server and any Proxmox VE host to enable secure, passwordless access for inventory queries.
*   The local check configuration must be set up directly on the Checkmk server itself, not on the individual PVE hosts.

# Disclaimer

This script is provided as-is without warranty. Use at your own risk. Ensure you test in a controlled environment before deploying to production systems.

---

For detailed information on individual functions or further customization, refer to the script source code and inline comments.