# General
This script is split into two parts.

## Part 1 - Synology
The file `check_synology_backup.sh` should be places on the Synology nas directly unter `/volume1/`.

The owner of the file should be root and it needs to be executable (`chmod +x check_synology_backup.sh`).

## Part 2 - Checkmk
On the Checkmk server which has been choosen to execute the check there are several things to be done:

1. you need to locate the file `check_by_ssh`, which is usually located here: `/usr/lib/nagios/plugins/check_by_ssh`.
2. you need a ssh key which needs to be exchanged with the nas. So you have to create on for your Checkmk server and transfer the public part to the root account of your Synology nas.
3. you need to specify the path of the script on the Synology nas, this can be kept if you followed the instructions.
4. you need the rest of the data from your nas:
    1. `HOSTNAME=""` - the **hostname** of your nas
    2. `IP=""` - the **ip** of your nas
    3. `USER="admin"` - the **admin user** of your nas
    4. `TYPE="AB"` - the **type of backup** to be checked (only **AB** is supported at the moment)
    5. `WARN=30` - warn value in **hours**
    6. `CRIT=60` - crit value in **hours**
5. multiple lines for the configured tasks on your nas. The name should corresprond with the name of the job on your nas:
    1. ``TASK=""`` - the name of the backup job on your nas