# CheckMK Agent Deployment and Management Script for Ubuntu

This repository provides a universal Bash script to deploy and manage the Checkmk monitoring agent on Ubuntu machines. The script supports flexible installation modes for both the RAW edition and Enterprise/Cloud/MSP editions of Checkmk.

## Overview

The script automates many complex tasks including:

- Installing the Checkmk agent with options for standard RAW or Cloud/Enterprise registration.
- Agent registration and automatic update setup (for Enterprise/Cloud/MSP editions).
- Plugin management and configuration to extend agent functionality.
- Local check management with custom self-developed local checks included.
- Cleanup and removal of Checkmk agent installations.
- Additional helper tools and scripts.

Several custom local checks are provided in the `local_checks` directory, including checks for BorgBackup, SQL dumps, reboot requirement, Proxmox VE monitoring, and PVE backup configuration.

## Features

- Flexible installation modes with interactive menu and command line options.
- Automated agent registration and updater configuration for cloud environments.
- Support for managing built-in plugins and external custom plugins.
- Local check installation, configuration, and removal management.
- Proxmox VE host and VM blacklist management for fine-tuned monitoring.
- Detailed logging with colored message dialogs using whiptail.
- Integration with Docker and Python for advanced scenarios.

## Requirements

- Ubuntu-based system.
- Existing Checkmk server installation (RAW or Enterprise/Cloud editions).
- Root privileges to run the installation script.

## Usage

1. Download and run the `manage_cmk_agent.sh` script as root.
2. Follow interactive menus to select installation mode, register the agent, manage plugins or local checks.
3. For cloud installations, provide registration details and credentials as prompted.
4. Configure additional local checks and Proxmox VE hosts if applicable.

## Local Checks Included

- `check_borg_backup`: Monitor BorgBackup status.
- `check_sql_dump`: Monitor SQL dump backups.
- `reboot_required`: Monitor if system reboot is required.
- `pve_monitored_guests`: Discover and monitor Proxmox VE guests.
- `pve_backup_config_check`: Monitor Proxmox VE backup configuration.

## License

This project is licensed under the GPL-3.0 License.

## Author and Support

- Author: Sascha Jelinek  
- Company: ADMIN INTELLIGENCE GmbH  
- Website: https://www.admin-intelligence.de
- Checkmk Website: https://www.admin-intelligence.de/checkmk
- Blog: https://blog.admin-intelligence.de/category/checkmk/
