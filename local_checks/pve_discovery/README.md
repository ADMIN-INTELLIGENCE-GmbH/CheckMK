# PVE Monitored Guests Discovery – Local Check for Checkmk

This script checks which Proxmox VMs on remote PVE hosts are not monitored in Checkmk, providing a summary and details grouped by PVE host IP. The status is reported as a local check in Checkmk, making it easy to identify unmonitored guests.

# Features

*   Scans all configured Proxmox hosts for running VMs.
*   Groups results by PVE host IP (from a configurable server list).
*   Compares each VM name against Checkmk host aliases to determine monitoring status.
*   Supports blacklist file to exclude specific VMIDs and hosts from the check.
*   Outputs aggregated results: total VMs, total unmonitored, and lists of unmonitored VMs per host IP.
*   Summarizes as a single status line for Checkmk service monitoring.

# Requirements

*   Linux host with **Checkmk** installed.
*   Local execution rights for `omd`, `unixcat`, and `ssh` to Proxmox hosts.
*   Access to Proxmox hosts with passwordless SSH key authentication for automation.
*   Configured `server_file` and optional `blacklist_file` as described below.

# Installation

## **1\. Copy the script** to your Checkmk monitoring server.

## **2\. Set permissions:**

```
chmod +x /path/to/pve_monitored_guests.sh
```

_(Rename as appropriate.)_

## **3\. Configure the Proxmox host list and blacklist files:**

*   **Server file:** `/etc/check_mk/pve_discovery_server.txt`
    *   List each PVE host IP or DNS name to monitor, one per line.
*   **Blacklist file:** `/etc/check_mk/pve_discovery_blacklist.txt`
    *   Format: `host:vmid`, one per line

### Example:

```
192.168.1.100:107
192.168.1.101:205
```

**4\. Ensure Checkmk site OMDs is initialized and running** (the script requires `omd sites`, `unixcat`, and site user access.)

# Integration in the Checkmk GUI

1.  **Deploy the Script:**  
    Place your monitoring script on the Checkmk server under `/usr/lib/check_mk_agent/local/` and configure server and blacklist files.
2.  **Service Discovery:**  
    After executing the script at least once, perform a "Service Discovery" for the host associated with your Checkmk site (usually the Checkmk server itself).  
    Navigate to:
    1.  Hosts → \[Your Monitoring Server\] → Service Discovery
    2.  Look for the new service: **"PVE monitored guests"**
3.  **Add the Service:**  
    After discovery, add it to your monitored services so alerts and reporting will work as expected.
4.  **Configure Notifications (Optional):**  
    Set up notification rules for the service to send alerts if any guest is found **unmonitored** (status `CRIT`).  
    E.g.:
    1.  Setup → Notifications → Rules
    2.  Create email, Slack, or pager rules for "Critical" service states on this service.
5.  **Dashboards & Reporting:**  
    You can add the "PVE monitored guests" service to dashboards, custom views, or setup periodic reports for documentation and audits.
6.  **Tuning:**
    1.  Adjust your cronjob schedule for appropriate check intervals.
    2.  Keep server and blacklist files updated as your environment changes.
    3.  Verify Checkmk host aliases correspond to your expected VM names.

# How It Works

*   Reads the current Checkmk site and alias mapping for hosts.
*   Iterates all hosts from the configured server file.
*   Connects to each host via SSH and runs `qm list` to get VM names and IDs.
*   Compares VM names with Checkmk host aliases. If no match, considers VM unmonitored.
*   Respects blacklist to skip specified VMs.
*   Outputs a single status line for Checkmk with details:
    *   **OK:** All VMs are monitored
    *   **CRIT:** Lists all unmonitored VMs and the total per IP

# Output Example

If all VMs are monitored:

```
0 "PVE monitored guests" - All 42 VMs are monitored
```

If unmonitored VMs are found:

```
2 "PVE monitored guests" - 3 of 42 VMs not monitored --- Unmonitored VMs by host IPs: 192.168.1.100: VM1 (101), VM2 (102), 192.168.1.101: VM3 (203),
```

# Troubleshooting & Tips

*   Check SSH access and keys between monitoring host and Proxmox servers.
*   Ensure all aliases in Checkmk are correct and updated.
*   Review `/tmp/checkmk_pve_discovery.log` for debug logs.
*   Maintain the server and blacklist files for accuracy as your environment changes.
*   Test the script manually (`bash pve_monitored_guests.sh`) before enabling cron or agent integration.
*   Use Checkmk's "Service Graphs" and "Availability" views to visualize historic monitoring coverage.

# Changelog

*   **v1.0.1:** Removed lowercase translation of alias.
*   **v1.0.2:** Added VM-ID to the output.
*   **v1.0.3:** Grouping by PVE host IP with IP output.
*   **v1.0.4:** Use IP directly from server file without DNS resolution.
*   **v1.0.5:** Single summarized output for all hosts.
*   **v1.0.6:** Total VMs count includes all hosts regardless of monitoring status.
*   **v1.0.7:** Changed wordings for output clarity.

# Author

*   Author: **Sascha Jelinek**
*   Company: **ADMIN INTELLIGENCE GmbH**
*   Website: [www.admin-intelligence.de/checkmk](https://www.admin-intelligence.de/checkmk)