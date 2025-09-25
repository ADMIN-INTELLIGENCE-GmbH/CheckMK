# Proxmox Backup Config Check – Local Check for Checkmk

This check set helps monitor Proxmox VMs and containers to ensure that all relevant disks and mounts are included in backups. The status is displayed directly in Checkmk for comprehensive monitoring.

# Features

*   Checks all **VM disks** and **LXC container mounts** for backup exclusions.
*   Flags disks/mounts not set for backup (with `backup=0`).
*   Aggregates results for a single status line in Checkmk.
*   Easy integration via agent local check output file.
*   Includes helper script for Checkmk agent plug-in output.

# Requirements

*   Proxmox server (PVE) with `qm` (QEMU/KVM management) and `pct` (LXC container management) installed.
*   Checkmk agent installed on the Proxmox node.
*   Scripts placed with read and execute permissions for the agent.

# Installation

## 1\. **Copy the scripts** to your monitoring server (Proxmox host):

*   `pve_backup_check.sh`: Generates the backup status file.
*   `check_pve_backup_config_cron.sh`: Outputs the status file content for Checkmk.

## 2\. **Set file permissions:**

```
chmod +x /usr/lib/check_mk_agent/pve_backup_check.sh chmod +x /usr/lib/check_mk_agent/check_pve_backup_config_cron.sh
```

## 3\. **Schedule periodic execution** of `pve_backup_check.sh` to update the status file, e.g. with a cronjob:

```
*/10 * * * * /usr/lib/check_mk_agent/pve_backup_check.sh
```

## 4\. The output file will be written to:

```
/usr/lib/check_mk_agent/pve_backup_check
```

## 5\. Placement of the scripts

The Checkmk plug-in script (`check_pve_backup_config_cron.sh`) should be placed in the agent’s local or spool directory and will read and output the status for Checkmk.

# How It Works

*   **Main check script (**`**pve_backup_check.sh**`**) scans:**
    *   All VM disks
    *   All LXC mounts
    *   Looks for `backup=0` flag (excluded from backup)
    *   Builds a list of non-backed-up disks/mounts
*   **Checkmk agent plug-in (**`**check_pve_backup_config_cron.sh**`**):**
    *   Reads the output file and echoes its content for Checkmk agent data collection.

## Status output:

If all disks/mounts are included:

```
0 "PVE Backup check" - All disks and mounts are included in backup
```

If any disks/mounts are excluded:

```
2 "PVE Backup check" - NOT backed up: VM <ID> Disk <name>, LXC <ID> Mount <name>
```

# Integration with Checkmk

*   After installation, perform a service scan in Checkmk to discover the _"PVE Backup check"_ service.
*   The single-line status ensures clear display and alerting for missing backup coverage.
*   Use performance and status history in Checkmk to track backup configuration completeness over time.

# Author

*   Author: **Sascha Jelinek**
*   Company: **ADMIN INTELLIGENCE GmbH**
*   Website: [www.admin-intelligence.de/checkmk](https://www.admin-intelligence.de/checkmk)