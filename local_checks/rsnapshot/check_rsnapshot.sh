#!/bin/bash
#
############################################################
#    _   ___  __  __ ___ _  _                              #
#   /_\ |   \|  \/  |_ _| \| |                             #
#  / _ \| |) | |\/| || || .` |                             #
# /_/ \_\___/|_|  |_|___|_|\_|                             #
#  ___ _  _ _____ ___ _    _    ___ ___ ___ _  _  ___ ___  #
# |_ _| \| |_   _| __| |  | |  |_ _/ __| __| \| |/ __| __| #
#  | || .` | | | | _|| |__| |__ | | (_ | _|| .` | (__| _|  #
# |___|_|\_| |_| |___|____|____|___\___|___|_|\_|\___|___| #
#   ___       _    _  _                                    #
#  / __|_ __ | |__| || |                                   #                               
# | (_ | '  \| '_ \ __ |                                   #                              
#  \___|_|_|_|_.__/_||_|                                   #
#                                                          #
############################################################
############################################################
# "local check" script to check the status of rsnapshot
# backups
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2022-02-17
# Web: www.admin-intelligence.de
############################################################

# the root folder of your rsnapshot, passed through parameter or set static path if needed
if [[ $1 ]]; then
    BACKUPPATH=$1
else
    BACKUPPATH="[your rsnapshot root folder]"
fi

# CRIT & WARN times (in days)
CRIT=3
WARN=2
CRITHOURS=$((CRIT * 60))
WARNHOURS=$((WARN * 60))

for I in `ls ${BACKUPPATH}`; do
    # grep through every rsnapshot.log file
    result=$(tail -n 1 ${BACKUPPATH}/$I/rsnapshot.log)

    # time calculations
    TIME=`echo $result | awk '{ print $1 }'`
    TIME=${TIME:1:-1}
    TIMESTAMP=`date -d"${TIME}" +%s`
    NOW=$(date +%s)
    DELTA=$((NOW - $TIMESTAMP))
    MINUTES=$(($DELTA / 60 %60))
    HOURS=$((DELTA / 60 / 60 %60))
    DAYS=$((DELTA / 60 / 60 / 24))
    PASSEDTIME=`echo $DAYS"d-"$HOURS"h-"$MINUTES"m"`

    if [[ $result == *"completed successfully"* ]]; then
        if [[ $DAYS -lt $WARN ]]; then
            status=0
            statustext="Last Backup has completed successfully, age $PASSEDTIME"
        elif [[ $DAYS -ge $WARN ]] && [[ $DAYS -lt $CRIT ]]; then
            status=1
            statustext="Last Backup has completed successfully, but is too old with $PASSEDTIME"
        elif [[ $DAYS -lt $CRIT ]]; then
            status=2
            statustext="Last Backup has completed successfully, but is way too old with $PASSEDTIME"
        else
            status=3
            statustext="Unknown error"
        fi
    elif [[ $result == *"completed, but with some warnings"* ]]; then
        if [[ $DAYS -lt $WARN ]]; then
            status=1
            statustext="Last Backup completed with WARNINGS, age $PASSEDTIME"
        elif [[ $DAYS -ge $WARN ]] && [[ $DAYS -lt $CRIT ]]; then
            status=1
            statustext="Last Backup completed with WARNINGS, age $PASSEDTIME"
        elif [[ $DAYS -lt $CRIT ]]; then
            status=2
            statustext="Last Backup completed with WARNINGS, but is too old with $PASSEDTIME"
        else
            status=3
            statustext="Unknown error"
        fi
    else
        running=$(ps -ef | grep rsnapshot | grep $I)
        if [[ ! -z $running ]]; then
            status=1
            statustext="RSnapshot currently running... please wait for result."
        else
            status=2
            statustext="Last Backup has FAILED, age $PASSEDTIME"
        fi
    fi

    # output (perfdata not working proberly and displaying the unit "s" instead of "d")
    # echo "$status \"RSnapshot $I\" age=$HOURS;$WARNHOURS;$CRITHOURS $statustext"
    echo "$status \"RSnapshot $I\" - $statustext"
done
