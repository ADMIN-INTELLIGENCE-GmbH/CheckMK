# Synology Backup Check – Integration with Checkmk

Monitor your Synology NAS backup jobs in Checkmk with this simple two-part script system. It supports **Active Backup for Business** (AB) and can be extended for HyperBackup. The check fetches backup job status and timing from your NAS and makes monitoring easy via SSH and piggyback data.

# Overview

The integration consists of two main parts:

*   **Part 1: Synology NAS script** (`checkmk_synology_backups.sh`) – runs directly on the NAS.
*   **Part 2: Checkmk SSH wrapper** (example configuration script) – runs on the Checkmk monitoring server, fetches results via SSH, and outputs piggyback-compatible data.

# Part 1 – Synology NAS Script

**1\. Copy** `**checkmk_synology_backups.sh**` **to your Synology NAS**, ideally under `/volume1/`.

**2\. Set permissions:**

```
chmod +x /volume1/checkmk_synology_backups.sh
chown root:root /volume1/checkmk_synology_backups.sh
```

3\. The script queries the Synology backup logs and/or activity database (activity.db) to determine the most recent backup completion time and result for each backup job.

4\. It outputs a single Checkmk local check status line for each job, containing:

*   Status (OK/WARN/CRIT)
*   Job name
*   Age since last backup in hours
*   Backup result details (transfer counts, errors)

5\. Supports warning/critical thresholds via command line parameters.

# General

This script is split into two parts.

## Part 1 - Synology

The file `checkmk_synology_backups.sh` should be places on the Synology nas directly unter `/volume1/`.

The owner of the file should be root and it needs to be executable (`chmod +x checkmk_synology_backups.sh`).

## Part 2 - Checkmk

On the Checkmk server which has been choosen to execute the check there are several things to be done:

1.  you need a ssh key which needs to be exchanged with the nas. So you have to create on for your Checkmk server and transfer the public part to the root account of your Synology nas.
2.  you need to specify the path of the script on the Synology nas, this can be kept if you followed the instructions.
3.  you need the rest of the data from your nas:
    1.  `HOSTNAME=""` - the **hostname** of your nas
    2.  `IP=""` - the **ip** of your nas
    3.  `USER="admin"` - the **admin user** of your nas
    4.  `TYPE="AB"` - the **type of backup** to be checked (only **AB** is supported at the moment)
    5.  `WARN=30` - warn value in **hours**
    6.  `CRIT=60` - crit value in **hours**
4.  multiple lines for the configured tasks on your nas. The name should corresprond with the name of the job on your nas:
    1.  `TASK=""` - the name of the backup job on your nas

# Part 2 – Checkmk Monitoring Server Script

**1\. Locate** `**check_by_ssh**` (usually `/usr/lib/nagios/plugins/check_by_ssh`).

**2\. Create and exchange SSH keys:**

*   On your Checkmk server, create a keypair for the monitoring site.
*   Copy the public key to the Synology NAS for the user you want to run checks as (usually `root` or `admin`).

**3\. Edit the wrapper script:**

*   Set the Synology NAS hostname and IP.
*   Set SSH user (`USER`), path to key (`SSHKEY`), and check script path on NAS (`CHECKPATH`).
*   For each backup job, set the correct job/task name (`TASK`) as it appears on your NAS in Active Backup for Business.
*   Set backup type (`TYPE`), warn/crit thresholds (`WARN`, `CRIT`).
*   Each block for a NAS outputs piggyback and local data for multiple jobs.
*   Add additional blocks to monitor extra NAS hosts or jobs.

**4\. Run the wrapper script** via the monitoring site or OMDs cron/check routines.

# Example Configuration Block

```
# Host-Config #1
HOSTNAME="syno-nas01"
IP="192.168.1.2"
USER="admin"
TYPE="AB"
WARN=30
CRIT=60
echo "<<<<${HOSTNAME}>>>>"
echo "<<<local>>>"

TASK="VM-Backup"
echo `${SSHCOMMAND} -H ${IP} -i ${SSHKEY} -o StrictHostKeyChecking=accept-new -l ${USER} -C "${CHECKPATH} -t ${TASK} -a ${TYPE} -w ${WARN} -c ${CRIT} -v ''"`

TASK="Server-Backup"
echo `${SSHCOMMAND} -H ${IP} -i ${SSHKEY} -o StrictHostKeyChecking=accept-new -l ${USER} -C "${CHECKPATH} -t ${TASK} -a ${TYPE} -w ${WARN} -c ${CRIT} -v ''"`

echo "<<<<>>>>"
```

Repeat for multiple NAS hosts or multiple jobs.

# Important Notes

*   **Synchronize job names:** The `TASK` value should match the exact name of the job as shown in Synology Active Backup for Business.
*   **Threshold tuning:** Use the `-w` and `-c` options to set the warning and critical thresholds (in hours since last backup).
*   **SSH connection:** Ensure passwordless SSH from your Checkmk server to the Synology NAS.
*   **Piggyback data:** Output is formatted for Checkmk piggyback integration so backups appear under the correct NAS host object.

# Integration Steps

*   Deploy and configure both scripts.
*   Add/re-discover the relevant NAS hosts in Checkmk.
*   Monitor new or existing services for backup status.
*   Set up notifications or dashboards for backup age and result alerting.

# Example – Adding More Hosts

Simply copy and modify the block for each additional NAS or backup job you want to monitor. Ensure each host’s configuration matches your environment and the script paths.

# Author

*   Original Authors: **Anton Daudrich, Simon Hätty**
*   Improvements and Checkmk migration: **Sascha Jelinek**
*   Company: **ADMIN INTELLIGENCE GmbH**
*   Website: [www.admin-intelligence.de/checkmk](https://www.admin-intelligence.de/checkmk)