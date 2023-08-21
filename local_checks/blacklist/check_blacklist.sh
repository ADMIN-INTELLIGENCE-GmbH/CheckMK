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
# "local check" script to check the public IP of the server
#  against a list of SBL-servers
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2022-03-30
# Web: www.admin-intelligence.de
############################################################

if [ $# -eq 0 ]; then
    IPADDR=`curl -s -4 ifconfig.me`
else
    if [[ $1 =~ ([0-9]{1,3}\.){3}([0-9]{1,3}) ]]; then
        IPADDR=$1
    else
        IPADDR=`ping -c1 -t1 $1 2>&1 | tr -d '():' | awk '/^PING/{print $3}'`
    fi
fi

# Move the IP around to get the reverse IP
IPOCTET1=$(echo $IPADDR | awk -F. '{print $1}')
IPOCTET2=$(echo $IPADDR | awk -F. '{print $2}')
IPOCTET3=$(echo $IPADDR | awk -F. '{print $3}')
IPOCTET4=$(echo $IPADDR | awk -F. '{print $4}')

# check format failures
if [ "$IPOCTET1" == "" ]; then
    echo "Please enter the Valid IP address"
    exit 2
elif [ "$IPOCTET2" == "" ]; then
    echo "Please enter the Valid IP address"
    exit 2
elif [ "$IPOCTET3" == "" ]; then
    echo "Please enter the Valid IP address"
    exit 2
elif [ "$IPOCTET4" == "" ]; then
    echo "Please enter the Valid IP address"
    exit 2
fi

# build reverse IP
REVIP="${IPOCTET4}.${IPOCTET3}.${IPOCTET2}.${IPOCTET1}"

# Blacklist list
BLIST=`curl -s https://raw.githubusercontent.com/ADMIN-INTELLIGENCE-GmbH/CheckMK/main/local_checks/blacklist/black.list`

COUNT=0
COUNTBL=0
EXITCODE=0
EXITTEXT=""
# check every Server in the list
for server in $BLIST; do
        COUNT=$((COUNT+1))
    dig ${REVIP}.${server} >> /dev/null
    if [ $? = 0 ]; then
        EXITCODE=0
    else
        EXITCODE=2
        EXITTEXT+="IP ${IPADDR} is blacklisted on ${server}\n"
        COUNTBL=$((COUNTBL+1))
    fi
done

if [[ $COUNTBL = 0 ]]; then
    echo "0 \"Blacklist Check\" blacklist=${COUNTBL};;; IP not listet on ${COUNT} servers"
else
    echo "2 \"Blacklist Check\" blacklist=${COUNTBL};;; blacklisted on ${COUNTBL} of ${COUNT} servers\n${EXITTEXT}"
fi

