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
# "local check" script for Hetzner Cloud Snapshots
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2022-05-11
# Updated: 2022-05-17
# Web: www.admin-intelligence.de
############################################################
# v0.0.1 - initial release
#          count number of snapshots
# v0.0.2 - added size of snapshots
# v0.0.3 - added multiple API Tokens
# v0.0.4 - calculate age of snapshot
# v0.0.5 - added zombie snapshot detection
# v0.0.6 - added cost calculation
# v1.0.0 - added graphs
#          changed warn/crit values to time
# v1.0.1 - added locked snapshot detection
# v1.1.0 - added pagination, as hetzner only allows a maximum of 50 entries per page
# v1.2.0 - changed calculation of snapshot age and size

# TODO

#########################################
# you need to install the prerequisites #
# just copy the following line          #
# apt -y install curl jq                #
#########################################

# remove temp files
rm -f /tmp/Snapshots_* >/dev/null 2>&1

# tresholds
SNAP_NUM_WARN=1
SNAP_NUM_CRIT=2
SNAP_AGE_WARN=3 # days
SNAP_AGE_CRIT=7 # days
SNAP_COSTS=0.011 # €/GB/Monat
SNAP_COSTS_HOUR=`echo "scale=6 ; $SNAP_COSTS / 720" | bc`
MONTHSECONDS=2592000 # 1 month in seconds
MONTHHOURS=720 # 1 month in hours
EXCLUDED_PROJECTS=("Schatzschneider29cm") # ausgeschlossene Projekte die nicht eskalieren sollen, separiert durch "Leerzeichen", z.B. "Projekt 1" "Projekt 2" "usw."

# read API keys from file
for keylist in `cat /usr/lib/check_mk_agent/api_keys`; do
    declare -a API_KEYS
    declare -a PROJECT_NAME
    declare -a CUSTOMER
    CUSTOMER=`echo $keylist | grep -v "#" | cut -d";" -f1`
    PROJECT=`echo $keylist | grep -v "#" | cut -d";" -f2`
    APIKEY=`echo $keylist | grep -v "#" | cut -d";" -f3`
    API_KEYS=(${API_KEYS[@]} `echo $APIKEY`)
    PROJECT_NAME=(${PROJECT_NAME[@]} `echo $PROJECT`)
    CUSTOMER_NAME=(${CUSTOMER_NAME[@]} `echo $CUSTOMER`)
done

is_excluded_project() {
    local project="$1"
    for excluded in "${EXCLUDED_PROJECTS[@]}"; do
        if [[ "$project" == "$excluded" ]]; then
            return 0
        fi
    done
    return 1
}

# actual time
TIMENOW=$(date +%s)

for apikeys in "${!API_KEYS[@]}"; do
    SERVERPAGES=1
    SNAPPAGES=1
    unset SERVERID
    unset SERVERNAME
    touch /tmp/Snapshots_${API_KEYS[$apikeys]}
    # get number of pages
    SERVERPAGES=`curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" "https://api.hetzner.cloud/v1/servers" | jq '.meta.pagination.last_page'`
    SNAPPAGES=`curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" "https://api.hetzner.cloud/v1/images" | jq '.meta.pagination.last_page'`
    # get all servers
    for serverpage in `seq 1 $SERVERPAGES`; do
        SERVERID=(${SERVERID[@]} `curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" "https://api.hetzner.cloud/v1/servers?page=${serverpage}" | jq '.servers[].id'`)
        SERVERNAME=(${SERVERNAME[@]} `curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" "https://api.hetzner.cloud/v1/servers?page=${serverpage}" | jq '.servers[].name'`)
    done
    # get all images (including snapshots)
    for snappage in `seq 1 $SNAPPAGES`; do
        curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" "https://api.hetzner.cloud/v1/images?page=${snappage}" >> /tmp/Snapshots_${API_KEYS[$apikeys]}
    done

    for index in "${!SERVERID[@]}"; do
        # get ID of snapshot
        SNAP_ID=(`jq '.images[] | select((.type == "snapshot") and (.created_from != null) and (.created_from.id == '${SERVERID[$index]}')) | {id} | .id' /tmp/Snapshots_${API_KEYS[$apikeys]}`)
        # set sum variable
        SNAP_SIZE_SUM=0
        SNAP_COSTS_SUM=0
        LOCKED_COUNT=0
        OLDESTSNAP=""
        TIMEDAYS_A=""
        SNAPAGEOUT=""
        SNAPSIZEOUT=""
        SNAPCOSTSOUT=""
        SNAP_DETAIL=""
        BACKUP_ENABLED=""
        for keyid in ${!SNAP_ID[@]}; do
            declare -a TIMEDAYS_A
            lockedtext=""
            # get description of snapshot
            SNAP_DESC=`jq '.images[] | select(.id == '${SNAP_ID[$keyid]}') | {description} | .description' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            # get size of snapshots
            SNAP_SIZE=`jq '.images[] | select(.id == '${SNAP_ID[$keyid]}') | {image_size} | .image_size' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            SNAP_SIZE=$(printf "%.2f" $SNAP_SIZE)
            SNAP_SIZE_SUM=`echo $SNAP_SIZE_SUM + ${SNAP_SIZE} | bc`
            # get age of snapshots
            SNAP_AGE=`jq '.images[] | select(.id == '${SNAP_ID[$keyid]}') | {created} | .created' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            # get locked state of snapshots
            SNAP_LOCKED=`jq '.images[] | select(.id == '${SNAP_ID[$keyid]}') | {protection} | .protection.delete' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            if [[ $SNAP_LOCKED == true ]]; then
                LOCKED_COUNT=$((LOCKED_COUNT + 1))
                lockedtext=" (locked)"
            fi
            # time calculation
            DATETIME=${SNAP_AGE}
            DATETIME=${DATETIME#?} # cut first character
            DATETIME=${DATETIME%?} # cut last character
            TIMESTAMP=`date --date=$DATETIME +"%s"`
            TIMESECONDS=$((TIMENOW - TIMESTAMP))
            TIMEMINUTES=$((TIMESECONDS / 60))
            TIMEHOURS=$((TIMESECONDS / 60 / 60))
            SNAP_COSTS=`echo "scale=2 ; $SNAP_COSTS_HOUR * $TIMEHOURS * $SNAP_SIZE" | bc`
            SNAP_COSTS_SUM=`echo "scale=2 ; $SNAP_COSTS_SUM + $SNAP_COSTS" | bc`
            SNAP_COSTS=$(printf "%.2f" $SNAP_COSTS)
            TIMEDAYS=$((TIMESECONDS / 60 / 60 / 24))
            TIMEREADABLE=$TIMEDAYS"d "`date -d@${TIMESECONDS} -u +%H:%M`
            #TIMEDAYS_A=(${TIMEDAYS_A[@]} `echo $((TIMESECONDS / 60 / 60 / 24))`)

            ### echo ${SNAP_ID[$keyid]}" - "${SNAP_SIZE[$keysize]}" - "$TIMESECONDS" - "$TIMEMINUTES" - "$TIMEHOURS" - "$TIMEDAYS
            SNAP_SIZE_SUM=$(printf "%.2f" $SNAP_SIZE_SUM)
            SNAP_COSTS_SUM=$(printf "%.2f" $SNAP_COSTS_SUM)
            if [[ $SNAP_SIZE_SUM != "0" ]]; then
                SNAPSIZEOUT=" with $SNAP_SIZE_SUM GB total size"
            fi

            TIMEDAYS_A=()
            for keyid in ${!SNAP_ID[@]}; do
                SNAP_LOCKED=`jq '.images[] | select(.id == '${SNAP_ID[$keyid]}') | {protection} | .protection.delete' /tmp/Snapshots_${API_KEYS[$apikeys]}`
                if [[ $SNAP_LOCKED != true ]]; then
                    SNAP_AGE=`jq '.images[] | select(.id == '${SNAP_ID[$keyid]}') | {created} | .created' /tmp/Snapshots_${API_KEYS[$apikeys]}`
                    DATETIME=${SNAP_AGE}
                    DATETIME=${DATETIME#?}
                    DATETIME=${DATETIME%?}
                    TIMESTAMP=`date --date=$DATETIME +"%s"`
                    TIMESECONDS=$((TIMENOW - TIMESTAMP))
                    TIMEDAYS=$((TIMESECONDS / 60 / 60 / 24))
                    TIMEDAYS_A=(${TIMEDAYS_A[@]} $TIMEDAYS)
                fi
            done

            IFS=$'\n'
            OLDESTSNAP=`echo "${TIMEDAYS_A[*]}" | sort -nr | head -n1`
            
            if [[ -n $OLDESTSNAP ]]; then
                SNAPAGEOUT=", oldest snapshot is $OLDESTSNAP days old"
            fi
            SNAPCOSTSOUT=", est. total costs ${SNAP_COSTS_SUM}€"
            SNAP_DETAIL=$SNAP_DETAIL"\nSnapshot Name: ${SNAP_DESC}${lockedtext} - Size: $SNAP_SIZE GB - Age: $TIMEREADABLE - est. costs: ${SNAP_COSTS}€"
        done

        # count all snapshots
        SNAP_NUM=(`jq '.images[] | select((.type == "snapshot") and (.created_from != null) and (.created_from.id == '${SERVERID[$index]}')) | {id} | .id' /tmp/Snapshots_${API_KEYS[$apikeys]} | wc -l`)
        UNLOCKED_SNAP_NUM=(`jq '.images[] | select((.type == "snapshot") and (.created_from != null) and (.created_from.id == '${SERVERID[$index]}') and (.protection.delete == false)) | {id} | .id' /tmp/Snapshots_${API_KEYS[$apikeys]} | wc -l`)

        # BACKUP_ENABLED=(${BACKUP_ENABLED[@]} `curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" "https://api.hetzner.cloud/v1/servers?page=${serverpage}" | jq '.servers[].protection.delete'`)

        # generate output for Checkmk
        if [[ "${CUSTOMER_NAME[$apikeys]}" != "AI" ]] || is_excluded_project "${PROJECT_NAME[$apikeys]}"; then
            status=0
        else
            # Bestehende Statusprüfung hier
            if [[ -z "$OLDESTSNAP" ]]; then
                status=0
            elif [[ "$OLDESTSNAP" -lt "$SNAP_AGE_WARN" ]]; then
                status=0
            elif [[ "$OLDESTSNAP" -ge "$SNAP_AGE_CRIT" ]]; then
                status=2
            elif [[ "$OLDESTSNAP" -ge "$SNAP_AGE_WARN" ]]; then
                status=1
            fi
        fi

        # # final output string for Checkmk
        # METRICS="count=$SNAP_NUM|size=$SNAP_SIZE_SUM|age=$OLDESTSNAP|cost=$SNAP_COSTS_SUM"
        SERVERNAME_CLEAN=${SERVERNAME[$index]//\"/}
        # echo "$status \"Hetzner [${CUSTOMER_NAME[$apikeys]} - ${PROJECT_NAME[$apikeys]}] Snapshot ${SERVERNAME_CLEAN}\" $METRICS $SNAP_NUM active snapshots on the server, $LOCKED_COUNT locked snapshots${SNAPSIZEOUT}${SNAPAGEOUT}${SNAPCOSTSOUT}${SNAP_DETAIL}"
        # #echo "$status \"Hetzner [${CUSTOMER_NAME[$apikeys]} - ${PROJECT_NAME[$apikeys]}] Snapshot ${SERVERNAME[$index]}\" $METRICS $SNAP_NUM active snapshots on the server, $LOCKED_COUNT locked snapshots${SNAPSIZEOUT}${SNAPAGEOUT}${SNAPCOSTSOUT}${SNAP_DETAIL}"
        METRICS="count=$SNAP_NUM|unlocked_count=$UNLOCKED_SNAP_NUM|size=$SNAP_SIZE_SUM|age=$OLDESTSNAP|cost=$SNAP_COSTS_SUM"
        echo "$status \"Hetzner [${CUSTOMER_NAME[$apikeys]} - ${PROJECT_NAME[$apikeys]}] Snapshot ${SERVERNAME_CLEAN}\" $METRICS $SNAP_NUM total snapshots on the server ($UNLOCKED_SNAP_NUM unlocked / $LOCKED_COUNT locked)${SNAPSIZEOUT}${SNAPAGEOUT}, est. total costs ${SNAP_COSTS_SUM}€${SNAP_DETAIL}"
    done

    # get zombie snapshots
    ZOMBIECOUNT=0
    ZOMBIELOCKED=0
    ZSNAP_SIZE_SUM=0
    ZSNAP_COSTS_SUM=0
    ZOMBIEDETAIL=""
    ZOLDESTSNAP=""
    ZTIMEDAYS_A=""
    SSERVER_ID=(`jq '.images[] | select((.type == "snapshot") and (.created_from != null)) | {created_from} | .created_from.id' /tmp/Snapshots_${API_KEYS[$apikeys]}`)
    for index in "${!SSERVER_ID[@]}"; do
        for del in "${SERVERID[@]}"; do
            if [[ ${SSERVER_ID[$index]} == $del ]]; then
                unset 'SSERVER_ID[index]'
            fi
        done
    done
    for sindex in "${!SSERVER_ID[@]}"; do
        ZSERVER_ID=(`jq '.images[] | select((.type == "snapshot") and (.created_from != null) and (.created_from.id == '${SSERVER_ID[$sindex]}')) | {id} | .id' /tmp/Snapshots_${API_KEYS[$apikeys]}`)
        if [[ ! "${SERVERID[*]}" =~ "${SSERVER_ID[$sindex]}" ]]; then
            declare -a ZTIMEDAYS_A
            declare -A ZOLDESTSNAP_PER_PROJECT
            zlockedtext=""
            ZSNAP_DESC=`jq '.images[] | select(.id == '${ZSERVER_ID[$zindex]}') | {description} | .description' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            ZSNAP_SIZE=`jq '.images[] | select(.id == '${ZSERVER_ID[$zindex]}') | {image_size} | .image_size' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            ZSNAP_SIZE=$(printf "%.2f" $ZSNAP_SIZE)
            ZSNAP_SIZE_SUM=`echo $ZSNAP_SIZE_SUM + $ZSNAP_SIZE | bc`
            ZSNAP_SIZE_SUM=$(printf "%.2f" $ZSNAP_SIZE_SUM)
            ZSNAP_AGE=`jq '.images[] | select(.id == '${ZSERVER_ID[$zindex]}') | {created} | .created' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            ZSNAP_LOCKED=`jq '.images[] | select(.id == '${ZSERVER_ID[$zindex]}') | {protection} | .protection.delete' /tmp/Snapshots_${API_KEYS[$apikeys]}`
            if [[ $ZSNAP_LOCKED == true ]]; then
                ZOMBIELOCKED=$((ZOMBIELOCKED + 1))
                zlockedtext=" (locked)"
            fi
            ZDATETIME=${ZSNAP_AGE}
            ZDATETIME=${ZDATETIME#?}
            ZDATETIME=${ZDATETIME%?}
            ZTIMESTAMP=`date --date=$ZDATETIME +"%s"`
            ZTIMESECONDS=$((TIMENOW - ZTIMESTAMP))
            ZTIMEMINUTES=$((ZTIMESECONDS / 60))
            ZTIMEHOURS=$((ZTIMESECONDS / 60 / 60))
            ZSNAP_COSTS=`echo "scale=2 ; $SNAP_COSTS_HOUR * $ZTIMEHOURS * $ZSNAP_SIZE" | bc`
            ZSNAP_COSTS_SUM=`echo "scale=2 ; $ZSNAP_COSTS_SUM + $ZSNAP_COSTS" | bc`
            ZTIMEDAYS=$((ZTIMESECONDS / 60 / 60 / 24))
            ZTIMEDAYS_A=(${ZTIMEDAYS_A[@]} `echo $((ZTIMESECONDS / 60 / 60 / 24))`)
            ZTIMEREADABLE=$ZTIMEDAYS"d "`date -d@${ZTIMESECONDS} -u +%H:%M`
            ZSNAP_COSTS=$(printf "%.2f" $ZSNAP_COSTS)
            ZOMBIEDETAIL=$ZOMBIEDETAIL"\n${ZSNAP_DESC}${zlockedtext} - Size: $ZSNAP_SIZE GB - Age: $ZTIMEREADABLE - est. costs: ${ZSNAP_COSTS}€"
            ZOMBIECOUNT=$((ZOMBIECOUNT + 1))
            if [[ -z ${ZOLDESTSNAP_PER_PROJECT[${PROJECT_NAME[$apikeys]}]} ]] || [[ $ZTIMEDAYS -gt ${ZOLDESTSNAP_PER_PROJECT[${PROJECT_NAME[$apikeys]}]} ]]; then
                ZOLDESTSNAP_PER_PROJECT[${PROJECT_NAME[$apikeys]}]=$ZTIMEDAYS
            fi
        fi
    done
    IFS=$'\n'
    ZOLDESTSNAP=${ZOLDESTSNAP_PER_PROJECT[${PROJECT_NAME[$apikeys]}]}
    ZOLDESTSNAP=`echo "${ZTIMEDAYS_A[*]}" | sort -nr | head -n1`
    ZSNAP_COSTS_SUM=$(printf "%.2f" $ZSNAP_COSTS_SUM)
    if [[ $ZOMBIECOUNT -eq 0 ]]; then
        zstatus=0
        zstatustext="No zombie snapshots found"
    else
        if [[ $ZOMBIECOUNT -eq $ZOMBIELOCKED ]]; then
            zstatus=1
            # zstatustext="$ZOMBIECOUNT zombie snapshots found without active server, but all are locked - size: $ZSNAP_SIZE_SUM GB - oldest zombie: ${ZOLDESTSNAP}d - est. total costs: ${ZSNAP_COSTS_SUM}€"
            zstatustext="$ZOMBIECOUNT zombie snapshots found without active server, but all are locked - size: $ZSNAP_SIZE_SUM GB - est. total costs: ${ZSNAP_COSTS_SUM}€"
        else
            zstatus=2
            # zstatustext="$ZOMBIECOUNT zombie snapshots found without active server, $ZOMBIELOCKED of it are locked - size: $ZSNAP_SIZE_SUM GB - oldest zombie: ${ZOLDESTSNAP}d - est. total costs: ${ZSNAP_COSTS_SUM}€"
            zstatustext="$ZOMBIECOUNT zombie snapshots found without active server, $ZOMBIELOCKED of it are locked - size: $ZSNAP_SIZE_SUM GB - est. total costs: ${ZSNAP_COSTS_SUM}€"
        fi
    fi
    if [[ "${CUSTOMER_NAME[$apikeys]}" != "AI" ]] || is_excluded_project "${PROJECT_NAME[$apikeys]}"; then
        zstatus=0
    fi
    ZMETRICS="count=$ZOMBIECOUNT|size=$ZSNAP_SIZE_SUM|age=$ZOLDESTSNAP|cost=$ZSNAP_COSTS_SUM"
    echo "$zstatus \"Hetzner Zombie Snapshots [${CUSTOMER_NAME[$apikeys]} - ${PROJECT_NAME[$apikeys]}]\" $ZMETRICS ${zstatustext}${ZOMBIEDETAIL}"
done

# remove temp files
rm -f /tmp/Snapshots_* >/dev/null 2>&1
