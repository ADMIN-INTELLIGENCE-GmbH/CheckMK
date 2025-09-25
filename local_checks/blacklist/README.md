# Blacklist Check Script

This repository contains a Bash script to check the **public IP address** of a server against a list of known blacklist (SBL) servers.  
It is designed to be used as a **local check** within Checkmk.

---

## Features

*   Automatically detects the **public IP address** if no argument is provided.
*   Allows manual input of an **IP address** or **hostname**.
*   Converts IP addresses into their reverse DNS lookup format for blacklist queries.
*   Retrieves an up-to-date list of blacklist servers from GitHub.
*   Checks each blacklist server and provides a monitoring-friendly output.

---

## Requirements

*   Linux/Unix-based system with Bash
*   Installed tools:
    *   `curl`
    *   `dig`
    *   `awk`
    *   `ping`
    *   `tr`

---

## Usage

```
# Run without arguments: automatically checks your public IP
./blacklist_check.sh

# Run with a specific IP
./blacklist_check.sh 192.168.1.100

# Run with a hostname (the script resolves it automatically)
./blacklist_check.sh myserver.domain.com
```

---

## Output Examples

```
0 "Blacklist Check" blacklist=0;;; IP not listet on 53 servers
```

The IP is **not listed** on any blacklist servers.

```
2 "Blacklist Check" blacklist=3;;; blacklisted on 3 of 53 servers
IP 203.0.113.45 is blacklisted on bl.example1.org
IP 203.0.113.45 is blacklisted on bl.example2.net
IP 203.0.113.45 is blacklisted on bl.example3.com
```

The IP is **listed on one or more blacklists**.

---

## Exit Codes

*   `0` → IP is **not** blacklisted
*   `2` → IP **is** blacklisted on at least one server

---

## Checkmk Integration

This script can be used directly with **Checkmk Local Checks**.

### Copy the script to your Checkmk local checks directory:

```
cp blacklist_check.sh ~/local/share/check_mk/local/
chmod +x ~/local/share/check_mk/local/blacklist_check.sh
```

### Test the script manually inside Checkmk’s local directory:

```
~/local/share/check_mk/local/blacklist_check.sh
```

### Perform an **agent reload** or inventory update so Checkmk can discover the new local check:

```
cmk -R      # OMD site reload
cmk -II HOSTNAME
cmk -O
```

The service will appear as **"Blacklist Check"** in Checkmk’s monitoring view.

---

## Blacklist Sources

The list of blacklist servers is dynamically fetched from:

```
https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/main/local_checks/blacklist/black.list
```

This ensures the script always uses the latest available data.

---

## Author & License

*   Author: **Sascha Jelinek**
*   Company: **ADMIN INTELLIGENCE GmbH**
*   Date: 2022-03-30
*   Website: [www.admin-intelligence.de/checkmk](https://www.admin-intelligence.de/)
*   License: MIT (or specify the license you want to use)