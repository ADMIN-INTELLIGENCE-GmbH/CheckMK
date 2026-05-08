#!/bin/bash
#
############################################################
#    _   ___  __  __ ___ _  _                             #
#   /_\ |   \|  \/  |_ _| \| |                            #
#  / _ \| |) | |\/| || || .` |                            #
# /_/ \_\___/|_|  |_|___|_|\_|                            #
#  ___ _  _ _____ ___ _    _    ___ ___ ___ _  _  ___ ___ #
# |_ _| \| |_   _| __| |  | |  |_ _/ __| __| \| |/ __| __|#
#  | || .` | | | | _|| |__| |__ | | (_ | _|| .` | (__| _| #
# |___|_|\_| |_| |___|____|____|___\___|___|_|\_|\___|___|#
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
# Updated: 2026-05-07
# Version: 1.3.3
# Web: https://www.admin-intelligence.de
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
# v1.3.1 - human readable output, labels in summary/details, rounded costs with leading zero, compact snapshot output
# v1.3.2 - human readable output with pipe separators
# v1.3.3 - pipe separator for main summary, comma separator
#          inside snapshot section, human readable labels
############################################################

#########################################
# you need to install the prerequisites #
# just copy the following line          #
# apt -y install curl jq bc             #
#########################################

rm -f /tmp/Snapshots_* /tmp/Servers_* >/dev/null 2>&1

SNAP_NUM_WARN=1
SNAP_NUM_CRIT=2
SNAP_AGE_WARN=3
SNAP_AGE_CRIT=7
SNAP_COSTS=0.014 # €/GB/Monat
SNAP_COSTS_HOUR=$(echo "scale=6; $SNAP_COSTS / 720" | bc)
EXCLUDED_PROJECTS=() # ausgeschlossene Projekte die nicht eskalieren sollen, separiert durch "Leerzeichen", z.B. "Projekt 1" "Projekt 2" "usw."

declare -a API_KEYS
declare -a PROJECT_NAME
declare -a CUSTOMER_NAME

while IFS=';' read -r CUSTOMER PROJECT APIKEY; do
    [[ -z "$CUSTOMER" ]] && continue
    [[ "$CUSTOMER" =~ ^# ]] && continue

    CUSTOMER=$(echo "$CUSTOMER" | xargs)
    PROJECT=$(echo "$PROJECT" | xargs)
    APIKEY=$(echo "$APIKEY" | xargs)

    [[ -z "$APIKEY" ]] && continue

    CUSTOMER_NAME+=("$CUSTOMER")
    PROJECT_NAME+=("$PROJECT")
    API_KEYS+=("$APIKEY")
done < /usr/lib/check_mk_agent/api_keys

is_excluded_project() {
    local project="$1"
    for excluded in "${EXCLUDED_PROJECTS[@]}"; do
        if [[ "$project" == "$excluded" ]]; then
            return 0
        fi
    done
    return 1
}

format_cost() {
    printf "%.2f" "$1"
}

format_labels_human() {
    local json="$1"

    if [[ -z "$json" || "$json" == "null" || "$json" == "{}" ]]; then
        echo "none"
        return
    fi

    echo "$json" | jq -r '
        if (type == "object" and length > 0) then
            to_entries
            | sort_by(.key)
            | map(
                if (.value == null or .value == "") then
                    "\(.key)"
                else
                    "\(.key)(\(.value))"
                end
            )
            | join(", ")
        else
            "none"
        end
    '
}

TIMENOW=$(date +%s)

for apikeys in "${!API_KEYS[@]}"; do
    SERVERPAGES=1
    SNAPPAGES=1

    SNAP_TMP="/tmp/Snapshots_${apikeys}"
    SRV_TMP="/tmp/Servers_${apikeys}"

    : > "$SNAP_TMP"
    : > "$SRV_TMP"

    SERVERPAGES=$(curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" \
        "https://api.hetzner.cloud/v1/servers" | jq -r '.meta.pagination.last_page // 1')

    SNAPPAGES=$(curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" \
        "https://api.hetzner.cloud/v1/images" | jq -r '.meta.pagination.last_page // 1')

    for serverpage in $(seq 1 "$SERVERPAGES"); do
        curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" \
            "https://api.hetzner.cloud/v1/servers?page=${serverpage}" \
            | jq -c '.servers[]' >> "$SRV_TMP"
    done

    mapfile -t SERVERID            < <(jq -r '.id' "$SRV_TMP")
    mapfile -t SERVERNAME          < <(jq -r '.name' "$SRV_TMP")
    mapfile -t SERVERSTATUS        < <(jq -r '.status' "$SRV_TMP")
    mapfile -t SERVERTYPE          < <(jq -r '.server_type.name // "unknown"' "$SRV_TMP")
    mapfile -t SERVERCREATED       < <(jq -r '.created // ""' "$SRV_TMP")
    mapfile -t SERVERBACKUPWINDOW  < <(jq -r '.backup_window // ""' "$SRV_TMP")
    mapfile -t SERVERLABELJSON     < <(jq -c '.labels // {}' "$SRV_TMP")

    for snappage in $(seq 1 "$SNAPPAGES"); do
        curl -s -H "Authorization: Bearer ${API_KEYS[$apikeys]}" \
            "https://api.hetzner.cloud/v1/images?page=${snappage}" >> "$SNAP_TMP"
    done

    for index in "${!SERVERID[@]}"; do
        SRV_ID=${SERVERID[$index]}

        SNAP_NUM=0
        UNLOCKED_SNAP_NUM=0
        LOCKED_COUNT=0
        SNAP_SIZE_SUM=0
        SNAP_COSTS_SUM=0
        OLDESTSNAP=""

        mapfile -t SNAP_ID < <(
            jq ".images[] | select((.type == \"snapshot\") and (.created_from != null) and (.created_from.id == ${SRV_ID})) | .id" "$SNAP_TMP"
        )

        for keyid in "${!SNAP_ID[@]}"; do
            SNAP_NUM=$((SNAP_NUM + 1))

            SNAP_SIZE=$(jq -r ".images[] | select(.id == ${SNAP_ID[$keyid]}) | .image_size // 0" "$SNAP_TMP")
            SNAP_AGE=$(jq -r ".images[] | select(.id == ${SNAP_ID[$keyid]}) | .created // \"\"" "$SNAP_TMP")
            SNAP_LOCKED=$(jq -r ".images[] | select(.id == ${SNAP_ID[$keyid]}) | .protection.delete // false" "$SNAP_TMP")

            SNAP_SIZE=$(printf "%.2f" "$SNAP_SIZE")
            SNAP_SIZE_SUM=$(echo "$SNAP_SIZE_SUM + $SNAP_SIZE" | bc)

            if [[ "$SNAP_LOCKED" == "true" ]]; then
                LOCKED_COUNT=$((LOCKED_COUNT + 1))
            else
                UNLOCKED_SNAP_NUM=$((UNLOCKED_SNAP_NUM + 1))
            fi

            if [[ -n "$SNAP_AGE" ]]; then
                TIMESTAMP=$(date --date="$SNAP_AGE" +"%s")
                TIMESECONDS=$((TIMENOW - TIMESTAMP))
                TIMEHOURS=$((TIMESECONDS / 3600))
                TIMEDAYS=$((TIMESECONDS / 86400))

                SNAP_COSTS_SINGLE=$(echo "scale=6; $SNAP_COSTS_HOUR * $TIMEHOURS * $SNAP_SIZE" | bc)
                SNAP_COSTS_SUM=$(echo "scale=6; $SNAP_COSTS_SUM + $SNAP_COSTS_SINGLE" | bc)

                if [[ "$SNAP_LOCKED" != "true" ]]; then
                    if [[ -z "$OLDESTSNAP" ]] || [[ "$TIMEDAYS" -gt "$OLDESTSNAP" ]]; then
                        OLDESTSNAP=$TIMEDAYS
                    fi
                fi
            fi
        done

        SNAP_SIZE_SUM=$(printf "%.2f" "$SNAP_SIZE_SUM")
        SNAP_COSTS_SUM=$(format_cost "$SNAP_COSTS_SUM")

        STATUS_STR=${SERVERSTATUS[$index]:-unknown}
        TYPE_STR=${SERVERTYPE[$index]:-unknown}
        CREATED_RAW=${SERVERCREATED[$index]}
        BACKUP_WINDOW=${SERVERBACKUPWINDOW[$index]:-""}
        LABELS_JSON=${SERVERLABELJSON[$index]:-\{\}}
        status=0

        if [[ -n "$CREATED_RAW" && "$CREATED_RAW" != "null" ]]; then
            CREATED_STR=$(date --date="$CREATED_RAW" +"%Y-%m-%d %H:%M:%S")
        else
            CREATED_STR="unknown"
        fi

        if [[ -n "$BACKUP_WINDOW" ]]; then
            BACKUP_STR="yes"
        else
            BACKUP_STR="no"
            # status=1
        fi

        LABELS_STR=$(format_labels_human "$LABELS_JSON")
        LABELCOUNT=$(echo "$LABELS_JSON" | jq 'length')

        LABELS_WARN_TEXT=""
        templabelstatus=0
        if [[ "$LABELCOUNT" -eq 0 ]]; then
            LABELS_WARN_TEXT=" (no labels)"
            templabelstatus=1
            LABEL_SUMMARY="labels: none"
        else
            LABEL_SUMMARY="labels: $LABELS_STR"
        fi

        if is_excluded_project "${PROJECT_NAME[$apikeys]}"; then
            status=0
        else
            if [[ -z "$OLDESTSNAP" ]]; then
                #status=0
                :
            elif [[ "$OLDESTSNAP" -lt "$SNAP_AGE_WARN" ]]; then
                #status=0
                :
            elif [[ "$OLDESTSNAP" -ge "$SNAP_AGE_CRIT" ]]; then
                #status=2
                :
            elif [[ "$OLDESTSNAP" -ge "$SNAP_AGE_WARN" ]]; then
                #status=1
                :
            else
                #status=0
                :
            fi

            # if [[ $templabelstatus -eq 1 && $status -lt 2 ]]; then
            #     status=1
            # fi
        fi

        SERVERNAME_CLEAN=${SERVERNAME[$index]//\"/}
        METRICS="count=$SNAP_NUM|unlocked_count=$UNLOCKED_SNAP_NUM|size=$SNAP_SIZE_SUM|age=${OLDESTSNAP:-0}|cost=$SNAP_COSTS_SUM"

        SNAP_SUMMARY="snaps=$SNAP_NUM (${UNLOCKED_SNAP_NUM} unlocked/${LOCKED_COUNT} locked), oldest=${OLDESTSNAP:-0}d, size=${SNAP_SIZE_SUM}GB, cost=${SNAP_COSTS_SUM}€"
        SUMMARY="status=$STATUS_STR | backup=$BACKUP_STR | type=$TYPE_STR | $LABEL_SUMMARY | $SNAP_SUMMARY"

        LONGOUTPUT="Server details:\n"
        LONGOUTPUT+="- Status: $STATUS_STR\n"
        LONGOUTPUT+="- Type: $TYPE_STR\n"
        LONGOUTPUT+="- Created: $CREATED_STR\n"
        LONGOUTPUT+="- Backups: $BACKUP_STR\n"
        LONGOUTPUT+="- Labels: $LABELS_STR${LABELS_WARN_TEXT}\n"
        LONGOUTPUT+="Snapshot details:\n"
        LONGOUTPUT+="- Total snapshots: $SNAP_NUM\n"
        LONGOUTPUT+="- Unlocked snapshots: $UNLOCKED_SNAP_NUM\n"
        LONGOUTPUT+="- Locked snapshots: $LOCKED_COUNT\n"
        LONGOUTPUT+="- Oldest unlocked snapshot: ${OLDESTSNAP:-0} days\n"
        LONGOUTPUT+="- Total snapshot size: ${SNAP_SIZE_SUM} GB\n"
        LONGOUTPUT+="- Estimated total costs: ${SNAP_COSTS_SUM} €"

        echo "$status \"Hetzner [${CUSTOMER_NAME[$apikeys]} - ${PROJECT_NAME[$apikeys]}] ${SERVERNAME_CLEAN}\" $METRICS $SUMMARY\\n$LONGOUTPUT"
    done

    ZOMBIECOUNT=0
    ZOMBIELOCKED=0
    ZSNAP_SIZE_SUM=0
    ZSNAP_COSTS_SUM=0
    ZOLDESTSNAP=""

    mapfile -t SSERVER_ID < <(
        jq '.images[] | select((.type == "snapshot") and (.created_from != null)) | .created_from.id' "$SNAP_TMP"
    )

    for sindex in "${!SSERVER_ID[@]}"; do
        FOUND=0
        for del in "${SERVERID[@]}"; do
            if [[ "${SSERVER_ID[$sindex]}" == "$del" ]]; then
                FOUND=1
                break
            fi
        done

        if [[ $FOUND -eq 0 ]]; then
            mapfile -t ZSERVER_ID < <(
                jq ".images[] | select((.type == \"snapshot\") and (.created_from != null) and (.created_from.id == ${SSERVER_ID[$sindex]})) | .id" "$SNAP_TMP"
            )

            for zindex in "${!ZSERVER_ID[@]}"; do
                ZSNAP_SIZE=$(jq -r ".images[] | select(.id == ${ZSERVER_ID[$zindex]}) | .image_size // 0" "$SNAP_TMP")
                ZSNAP_AGE=$(jq -r ".images[] | select(.id == ${ZSERVER_ID[$zindex]}) | .created // \"\"" "$SNAP_TMP")
                ZSNAP_LOCKED=$(jq -r ".images[] | select(.id == ${ZSERVER_ID[$zindex]}) | .protection.delete // false" "$SNAP_TMP")

                ZSNAP_SIZE=$(printf "%.2f" "$ZSNAP_SIZE")
                ZSNAP_SIZE_SUM=$(echo "$ZSNAP_SIZE_SUM + $ZSNAP_SIZE" | bc)

                if [[ -n "$ZSNAP_AGE" ]]; then
                    ZTIMESTAMP=$(date --date="$ZSNAP_AGE" +"%s")
                    ZTIMESECONDS=$((TIMENOW - ZTIMESTAMP))
                    ZTIMEHOURS=$((ZTIMESECONDS / 3600))
                    ZTIMEDAYS=$((ZTIMESECONDS / 86400))

                    ZSNAP_COSTS=$(echo "scale=6; $SNAP_COSTS_HOUR * $ZTIMEHOURS * $ZSNAP_SIZE" | bc)
                    ZSNAP_COSTS_SUM=$(echo "scale=6; $ZSNAP_COSTS_SUM + $ZSNAP_COSTS" | bc)

                    if [[ -z "$ZOLDESTSNAP" ]] || [[ "$ZTIMEDAYS" -gt "$ZOLDESTSNAP" ]]; then
                        ZOLDESTSNAP=$ZTIMEDAYS
                    fi
                fi

                if [[ "$ZSNAP_LOCKED" == "true" ]]; then
                    ZOMBIELOCKED=$((ZOMBIELOCKED + 1))
                fi

                ZOMBIECOUNT=$((ZOMBIECOUNT + 1))
            done
        fi
    done

    ZSNAP_SIZE_SUM=$(printf "%.2f" "$ZSNAP_SIZE_SUM")
    ZSNAP_COSTS_SUM=$(format_cost "$ZSNAP_COSTS_SUM")

    if [[ $ZOMBIECOUNT -eq 0 ]]; then
        zstatus=0
        zstatustext="No zombie snapshots found"
    else
        if [[ $ZOMBIECOUNT -eq $ZOMBIELOCKED ]]; then
            zstatus=0
            zstatustext="$ZOMBIECOUNT zombie snapshots found without active server | all locked | size=${ZSNAP_SIZE_SUM}GB | cost=${ZSNAP_COSTS_SUM}€"
        else
            zstatus=0 #2
            zstatustext="$ZOMBIECOUNT zombie snapshots found without active server | locked=$ZOMBIELOCKED | oldest=${ZOLDESTSNAP:-0}d | size=${ZSNAP_SIZE_SUM}GB | cost=${ZSNAP_COSTS_SUM}€"
        fi
    fi

    if [[ "${CUSTOMER_NAME[$apikeys]}" != "AI" ]] || is_excluded_project "${PROJECT_NAME[$apikeys]}"; then
        zstatus=0
    fi

    ZMETRICS="count=$ZOMBIECOUNT|size=$ZSNAP_SIZE_SUM|age=${ZOLDESTSNAP:-0}|cost=$ZSNAP_COSTS_SUM"
    echo "$zstatus \"Hetzner Zombie Snapshots [${CUSTOMER_NAME[$apikeys]} - ${PROJECT_NAME[$apikeys]}]\" $ZMETRICS $zstatustext"
done

rm -f /tmp/Snapshots_* /tmp/Servers_* >/dev/null 2>&1
