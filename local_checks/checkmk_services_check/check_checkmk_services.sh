#!/bin/bash
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
# local check to monitor the checkmk services on an agent via ssh
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2025-09-25
# Version: 1.0.0
# Web: www.admin-intelligence.de
############################################################
# Changelog
# v1.0.0
# - first release

# Path to the file containing the list of target servers
SERVER_LIST_FILE="/usr/lib/check_mk_agent/servers_for_cmk_servicechecks"

# Maximum acceptable socket inactivity age (in seconds, here 5 minutes)
SOCKET_MAX_AGE=300 # 5 minutes

# List of systemd services and timers expected to run on the remote servers
EXPECTED_SERVICES=(
    "check-mk-agent-async.service"
    "check-mk-agent.socket"
    "cmk-agent-ctl-daemon.service"
    "cmk-update-agent.timer"
)

# Read server names from the configuration file into an array
mapfile -t SERVERNAMES < "$SERVER_LIST_FILE"

# Loop through each target server
for TARGET_SERVER in "${SERVERNAMES[@]}"; do
    [ -z "$TARGET_SERVER" ] && continue  # Skip empty lines in the server list

    # SSH command template to check the remote server
    ZSSH="ssh root@$TARGET_SERVER"

    # Define piggyback monitoring file (used by CheckMK agent)
    PIGGY_NAME="$TARGET_SERVER"
    PIGGY_SECTIONFILE="/var/lib/check_mk_agent/spool/piggy_${PIGGY_NAME}.txt"

    # Temp file for tracking socket state
    SOCKET_STATE_FILE="/tmp/checkmk_socket_state_${PIGGY_NAME}.tmp"

    # Current UNIX timestamp
    NOW_EPOCH=$(date +%s)

    # Count how many relevant services are listed on the remote host
    service_count=$($ZSSH "systemctl list-units 'cmk*' 'check-mk-agent*' 2>/dev/null | grep -E 'cmk|check-mk-agent' | wc -l")
    running_count=0
    missing_services=""

    # Loop over each expected service and check its state
    for svc in "${EXPECTED_SERVICES[@]}"; do
        status_result=$($ZSSH "systemctl status $svc 2>&1")

        # If the service does not exist
        if echo "$status_result" | grep -q -E "could not be found|Loaded: not-found"; then
            missing_services+="$svc (not found), "
            continue
        fi

        # Check if the service is active, timer waiting, or socket listening
        is_active=$($ZSSH "systemctl is-active $svc" 2>/dev/null)
        if [[ "$svc" == *.timer ]]; then
            # Expected state for timer units
            if echo "$status_result" | grep -q "Active: active (waiting)"; then
                ((running_count++))
            else
                missing_services+="$svc ($is_active), "
            fi
        elif [[ "$svc" == *.socket ]]; then
            # Expected state for socket units
            if echo "$status_result" | grep -q "Active: active (listening)"; then
                ((running_count++))
            else
                missing_services+="$svc ($is_active), "
            fi
        else
            # Expected state for service units
            if echo "$status_result" | grep -q "Active: active (running)"; then
                ((running_count++))
            else
                missing_services+="$svc ($is_active), "
            fi
        fi
    done

    # Evaluate overall service health
    # Expected: 4 or 5 running services with no missing ones
    if [[ $running_count -ge 4 && $running_count -le 5 && -z "$missing_services" ]]; then
        service_status=0
        service_text="$running_count relevant services are running"
    else
        service_status=2
        if [[ -n "$missing_services" ]]; then
            service_text="$running_count relevant services are running, NOT running: ${missing_services%, }"
        else
            service_text="$running_count relevant services are running, but number outside expected range"
        fi
    fi

    # Check the state of check-mk-agent.socket (connections/accepted requests)
    socket_info=$($ZSSH "systemctl status check-mk-agent.socket 2>/dev/null | grep -E 'Accepted|Connected'")
    accepted=$(echo "$socket_info" | grep 'Accepted:' | awk '{print $2}' | sed 's/;//')
    connected=$(echo "$socket_info" | grep 'Connected:' | awk '{print $2}' | sed 's/;//')
    crit_socket=0
    crit_reason_socket=""

    # Compare against past state to detect inactivity
    if [[ -n "$accepted" && -n "$connected" ]]; then
        prev_accepted=0
        prev_time=0
        if [[ -e $SOCKET_STATE_FILE ]]; then
            source $SOCKET_STATE_FILE
        fi

        # If new connections have been accepted, update state
        if [[ "$accepted" -gt "$prev_accepted" ]]; then
            echo "prev_accepted=$accepted" > $SOCKET_STATE_FILE
            echo "prev_time=$(date +%s)" >> $SOCKET_STATE_FILE
        else
            # If no new connections and too much time has passed, flag as critical
            diff=$((NOW_EPOCH - prev_time))
            if [[ $diff -gt $SOCKET_MAX_AGE ]]; then
                crit_socket=2
                crit_reason_socket="check-mk-agent.socket Accepted value ($accepted) has not increased for over 5 minutes"
            fi
        fi
    else
        # If no socket info could be retrieved, set UNKNOWN
        crit_socket=3
        crit_reason_socket="Socket information not found!"
    fi

    # Detect long-running check-mk-agent@ instances (potentially stuck processes)
    long_running_proc=""
    while IFS= read -r svc; do
        pid=$($ZSSH "systemctl show -p MainPID $svc" | awk -F= '{print $2}')
        if [[ $pid =~ ^[0-9]+$ && $pid -gt 1 ]]; then
            starttime=$($ZSSH "ps -o etimes= -p $pid --no-headers" | xargs)
            if [[ $starttime =~ ^[0-9]+$ && $starttime -gt $SOCKET_MAX_AGE ]]; then
                # Convert runtime (seconds) into human-readable format
                days=$((starttime/86400))
                hours=$(( (starttime%86400)/3600 ))
                mins=$(( (starttime%3600)/60 ))
                secs=$((starttime%60))
                readable="${days}d ${hours}h ${mins}m ${secs}s"
                long_running_proc+="$svc has been running for $readable, "
            fi
        fi
    done < <($ZSSH "systemctl list-units --type=service --state=running 'check-mk-agent@*.service' | awk 'NR>1 {print \$1}'")

    if [[ -n "$long_running_proc" ]]; then
        crit_longrun=2
    else
        crit_longrun=0
    fi

    # Write monitoring results to piggyback spool file
    {
        echo "<<<<$PIGGY_NAME>>>>"
        echo "<<<local>>>"
        echo "$service_status \"Check_MK cmk_services\" - $service_text"
        if [[ $crit_socket -gt 0 ]]; then
            echo "$crit_socket \"Check_MK cmk_agent_socket\" - $crit_reason_socket"
        else
            echo "0 \"Check_MK cmk_agent_socket\" - Socket Accepted=$accepted, Connected=$connected"
        fi
        if [[ $crit_longrun -gt 0 ]]; then
            echo "2 \"Check_MK cmk_agent_longrun\" - ${long_running_proc%, }"
        else
            echo "0 \"Check_MK cmk_agent_longrun\" - no critical check-mk-agent@ instances"
        fi
        echo "<<<<>>>>"
    } > $PIGGY_SECTIONFILE

    # Set proper file permissions and display the results
    chmod 644 $PIGGY_SECTIONFILE
    cat $PIGGY_SECTIONFILE

done
