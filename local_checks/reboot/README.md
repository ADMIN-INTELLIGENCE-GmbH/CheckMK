# Descrption

A simple local check that checks if the file `/var/run/reboot-required` exists and produces an appropriate output.

# Usage

1. To use this script, just copy it to the `/usr/local/check_mk_agent/local` folder on your client with the agent installed.
2. Set the execution bit on the file to make it executable: `chmod +x /usr/local/check_mk_agent/local/reboot_required.sh`