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
# "local check" script to check if a reboot is required
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2022-02-21
# Web: www.admin-intelligence.de
############################################################

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin

if [ -f "/var/run/reboot-required" ]; then
    ExitCode=2
    Summary=$(cat /var/run/reboot-required)
else
    ExitCode=0
    Summary="no reboot required"
fi

case ${ExitCode} in
 0)
  echo "0 \"Reboot required\" - ${Summary}"
  ;;
 2)
  echo "2 \"Reboot required\" - ${Summary}"
  ;;
esac
