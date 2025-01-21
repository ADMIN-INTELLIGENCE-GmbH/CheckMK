#!/bin/bash

# General
SSHCOMMAND="/opt/omd/versions/2.0.0p18.cre/lib/nagios/plugins/check_by_ssh"
SSHKEY="/omd/sites/monitoring/.ssh/id_ed25519" # SSH-Key
CHECKPATH="/volume1/checkmk_synology_backups.sh" # Check script on synology nas

# Host-Config #1
HOSTNAME=""
IP=""
USER="admin"
TYPE="AB"
WARN=30
CRIT=60

# Output for Piggyback-Check
echo "<<<<${HOSTNAME}>>>>"
echo "<<<local>>>"

# Task-Configurations (you need a task for each task in Active Backup for Business)
TASK="VM-Backup"
echo `${SSHCOMMAND} -H ${IP} -i ${SSHKEY} -o StrictHostKeyChecking=accept-new -l ${USER} -C "${CHECKPATH} -t ${TASK} -a ${TYPE} -w ${WARN} -c ${CRIT} -v ''"`
TASK="Server-Backup"
echo `${SSHCOMMAND} -H ${IP} -i ${SSHKEY} -o StrictHostKeyChecking=accept-new -l ${USER} -C "${CHECKPATH} -t ${TASK} -a ${TYPE} -w ${WARN} -c ${CRIT} -v ''"`
# END Host-Config #1

# you can add multiple Host-Configs, just copy the block from above.

# need to stay to mark the end of the piggyback data
echo "<<<<>>>>"
