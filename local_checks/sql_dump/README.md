# Checkmk Local Check – SQL Dump Status

This Bash script monitors SQL dump files by checking their recency and completion status, ensuring that backups are current and were properly finalized. Output is structured for native Checkmk agent integration with alerting and summary data.

# Features

*   **Checks all SQL dump files** in `/sicherung` matching `[name]-YYYYMMDD-HHmm.sql`.
*   Ensures the most recent dump for each type is up-to-date (not older than 1 day and 6 hours).
*   Scans the last lines of each file for "Dump completed" information to verify successful completion.
*   Reports file age, completion state, and file size.
*   Outputs Checkmk-compatible status lines for direct monitoring and alerting.

# Usage

**1\. Copy the script** to the agent directory on your Checkmk client:

```
/usr/local/check_mk_agent/local/check_sql_dump.sh
```

**2\. Make it executable:**

```
chmod +x /usr/local/check_mk_agent/local/check_sql_dump.sh
```

3\. (Optional) Adjust any search paths or time thresholds in the script to match your SQL dump setup.

# How It Works

*   For every dump type (based on filename prefix in `/sicherung`), the most recent `.sql` file is selected (pattern `[name]-YYYYMMDD-HHmm.sql`).
*   Files modified within the last 2 minutes are ignored (to avoid incomplete dumps).
*   Performs a date check:
    *   **OK (0):** Recent dump file and log shows completion.
    *   **CRIT (2):** Recent dump file but no completion marker in last lines, OR dump is too old (older than 1 day 6 hours).
    *   **WARN (1):** No suitable dump files found in `/sicherung`.
*   Reports file name, age, completion status, and size.

## Example Output

```
0 "SQL Dump mydatabase" - Dump mydatabase-20250924-2305.sql is up-to-date and completed properly. Size: 142M.
2 "SQL Dump otherdb" - Warning: Dump otherdb-20250922-1100.sql is older than 1 day and 6 hours! Size: 28M.
2 "SQL Dump customer" - Dump customer-20250924-0705.sql is recent but not completed properly. Size: 4M.
1 sql_dump - No SQL dumps with name pattern [name]-YYYYMMDD-HHmm.sql found.
```

# Integration with Checkmk

*   Upon execution, the script outputs status lines for every detected dump type.
*   Privileges and output directory must allow Checkmk agent to read/execute this script on each check cycle.
*   Use Checkmk rules and notifications to alert when a backup is missing, stale, or incomplete.

# Customization

*   Adjust path from `/sicherung` if your dumps are elsewhere.
*   Tune `MAX_DIFF_SECONDS` (default = 30 hours) for stricter freshness requirements.
*   Add or modify completion markers in the `check_dump_file` function to match your database dump conventions.

# Author

*   Author: **Sascha Jelinek**
*   Company: **ADMIN INTELLIGENCE GmbH**
*   Website: [www.admin-intelligence.de/checkmk](https://www.admin-intelligence.de/checkmk)