# Introduction

With this local check for Checkmk you can monitor your BorgBackup with ease.

# Prerequisites

It relies on reading out a file named `/sicherung/borg_backup.sh` from us, which we use on neraly every server.

Within this script there is header where some variables are defined, it looks like this:

```bash
#!/bin/bash

#####################################
# Name of the repository to be initiated
HOST=[server.tld]
# name of the subaccount (only for Hetzner storage)
SUB=[x]
# Passphrase of the initiated repository, avoid special characters
PHRASE=12345678dfe5unzfdcfdmHNTGWAV432234567899876543
#####################################

# Borg repo at Hetzner, you can also use a local path if you want
export BORG_REPO="ssh://[user]-sub[x]@[user].your-storagebox.de:23/./backup/$HOST"
export BORG_PASSPHRASE="$PHRASE"

[...] # rest of the script
```

# Installation

Just copy the script `check_borg_backup` into the following folder on your Checkmk client:

```
/usr/lib/check_mk_agent/local
```

Make the script executable:

```
chmod +x /usr/lib/check_mk_agent/local/check_borg_backup
```

# Activate in Checkmk

After you copied the script you need to restart your Checkmk agent service.

After the restart you can rescan the server in Checkmk and the check should appear and looks like this:

![BorgBackup overview](image-1.png)

![BorgBackup service view](image.png)

Here you can see the following information:

## Summary
* Number of backups
* Date and time of the last backup
* Deduped size of the last backup
* Original size of the last backup

## Details
* A list of all backups in the repository with name and date

## Performance data
* A graph for every metric
  * Number of all backup
  * "This backup" original size
  * "This backup" compressed size
  * "This backup" deduplicated size
  * "All backups" original size
  * "All backups" compressed size
  * "All backups" deduplicated size

## Changelog
### v2.1.1
- added /backup to possible path to search for the script

### v2.2.0
- added extra logfile parsing for failed directories