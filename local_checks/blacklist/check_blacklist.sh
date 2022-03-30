#!/bin/bash

if [ $# -eq 0 ]; then
    echo -n "Enter the IP Address of the server to check: "
    # get IP from STDIN
    read IPADDR
else
    IPADDR=$1
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
echo "Reverse IP: ${REVIP}"

# Blacklist list
BLIST="cbl.abuseat.org
dnsbl.sorbs.net
bl.spamcop.net
zen.spamhaus.org
spam.dnsbl.sorbs.net
spamguard.leadmon.net
dnsbl.justspam.org
relays.mail-abuse.org
bl.emailbasura.org
"

# check every Server in the list
for server in $BLIST; do
    dig ${REVIP}.${server} >> /dev/null
    if [ $? = 0 ]; then
        echo "The ${IPADDR} IS White Listed"
    else
        echo "The ${IPADDR} IS Black Listed"
    fi
done