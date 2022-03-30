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
# "local check" script to parse the apache vhost and create
#  a DNS check for every occurance
#
# you will need the "check_dns" binary from the checkmk
#  server
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2022-03-29
# Web: www.admin-intelligence.de
############################################################

TEMPFILE=/usr/lib/check_mk_agent/dns_check.txt

echo >$TEMPFILE

for I in `ls /etc/apache2/sites-enabled/*.conf`; do
    SERVER=`cat $I | grep ServerName | awk '{ print $2 }' | uniq >>$TEMPFILE`
done

sed -i "" -e "s/\r//g" $TEMPFILE >/dev/null 2>&1
awk -i inplace '!seen[$0]++' $TEMPFILE

for SERVERNAME in `cat $TEMPFILE`; do
    DNSCHECK=`/usr/lib/check_mk_agent/check_dns $SERVERNAME`
    EXIT=$?
    RESULT=`echo $DNSCHECK | cut -d"|" -f1`
    if [[ $EXIT == 0 ]]; then
        PERFDATA=`echo $DNSCHECK | cut -d"|" -f2`
        echo "$EXIT \"DNS $SERVERNAME\" $PERFDATA $RESULT"
    else
        echo "$EXIT \"DNS $SERVERNAME\" - $RESULT"
    fi
done

rm -f $TEMPFILE
