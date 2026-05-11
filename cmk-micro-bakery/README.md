**Centralized plugin management and automated deployment for Checkmk.**

The Checkmk Micro-Bakery is a lightweight "alternative" to the official Checkmk Bakery. It allows you to centrally manage Checkmk plugins (Local Checks) via a web interface, automatically register hosts, and roll out scripts based on tags or customer relationships.

---

## 🚀 Core Features

### 1\. Central Management Dashboard

*   **Status Monitoring:** Instant overview of active hosts, offline alerts (>1h stale), pending updates, and plugins in quarantine.
*   **Wide-Layout UI:** Optimized user interface for maximum visibility with many hosts.
*   **Audit Log:** Complete tracking of all changes (who assigned which plugin and when?).

### 2\. Intelligent Plugin Rollout

*   **Tag System:** Plugins can be assigned tags (e.g., `Linux`, `Webserver`, `Database`). Hosts with these tags receive the plugins automatically.
*   **Multi-Tenancy:** Assignment of hosts to customers for better structuring and organization.
*   **GitHub Synchronization:** Automatic import of plugins from a GitHub repository (including recursive scanning of subfolders).
*   **Version Control:** Local scripts are checked against GitHub versions; an update is signaled if there are discrepancies.

### 3\. Security & Failsafe Mechanisms

*   **Quarantine Mode (Discovery):** New scripts found on the host are automatically uploaded to the Bakery but not deleted. They are placed in quarantine and must first be approved by the admin.
*   **Failsafe Re-Bootstrap:** If the Bakery database is reset, the client detects this (HTTP 403) and automatically re-registers using its global key.
*   **2FA Protection:** Admin login is secured by Two-Factor Authentication (TOTP).
*   **Orphan Protection:** Orphaned files (files on the host that are not in the Bakery) are marked and only deleted after explicit admin approval.

### 4\. Client Intelligence

*   **OS & Kernel Detection:** The client reports the operating system (Ubuntu, Debian, Windows, etc.) and kernel version to the central server (including icon display in the dashboard).
*   **Automatic Setup:** Generates individual host tokens after the initial communication.

---

## 🛠 Installation

### Server (Bakery Backend)

*   Install Python 3.10+.
*   Install dependencies:  
    `pip install flask flask-sqlalchemy flask-admin flask-apscheduler flask-login pyotp requests markdown`
*   Start the script `bakery_server.py`.
*   On the first start, an admin account is created (`admin` / `admin123`). **Activate 2FA in the user menu immediately!**

### Client (Checkmk Host)

*   Place the Bash script in the `/usr/lib/check_mk_agent/local/` directory.
*   Make the script executable: `chmod +755 checkmk_bakery.sh`.
*   Adjust the `API_URL` and `GLOBAL_SETUP_KEY` inside the script.
*   The client will register automatically during the next Checkmk execution.

---

## 📈 Changelog

### v4.0.1

*   **Fix:** Minor bugs fixed.

### v4.0.0

*   **NEW:** Added multi-tenancy (customer objects).
*   **NEW:** OS detection (icons for Ubuntu, Debian, Windows, etc. in the dashboard).
*   **NEW:** Kernel version reporting.
*   **NEW:** Failsafe re-bootstrap logic (automatic recovery in case of database loss).
*   **NEW:** Maintenance mode for hosts (suppresses updates/deletions).
*   **Fix:** CSS "container breakout" for true wide-screen view in the admin panel.

### v3.5.0

*   **NEW:** Quarantine system for newly discovered plugins (auto-discovery).
*   **NEW:** Base64 upload of script contents from the client to the server.
*   **NEW:** Global "Undo" button to cancel planned deletions of orphaned files.

### v3.0.0

*   **NEW:** GitHub integration (recursive sync via the GitHub API).
*   **NEW:** Tag-based deployment (many-to-many relationship).
*   **NEW:** Audit logging for all GUI actions.
*   **NEW:** Plugin history (archiving of old script versions).

### v2.0.0

*   **NEW:** Migration to Flask-Admin UI.
*   **NEW:** Individual host tokens (Bearer Auth) instead of a global key.
*   **NEW:** 2FA (TOTP) for admin login.

### v1.0.0

*   Basic synchronization between client and server.
*   Simple SQLite database for plugin assignment.

---

## 📝 Author & License

**Author:** Sascha Jelinek  
**Company:** ADMIN INTELLIGENCE GmbH  
**Web:** [www.admin-intelligence.de](https://www.admin-intelligence.de)

_Concept, architecture, and testing by Sascha Jelinek. Code implementation was assisted by AI (Google Gemini)._

_This project was developed to simplify the management of Checkmk Local Checks in dynamic environments._