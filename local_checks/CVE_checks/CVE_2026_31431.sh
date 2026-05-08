#!/bin/bash
#############################################################
#    _   ___  __  __ ___ _  _                               #
#   /_\ |   \|  \/  |_ _| \| |                              #
#  / _ \| |) | |\/| || || .` |                              #
# /_/ \_\___/|_|  |_|___|_|\_|                              #
#   ___ _  _ _____ ___ _    _    ___ ___ ___ _  _  ___ ___  #
#  |_ _| \| |_   _| __| |  | |  |_ _/ __| __| \| |/ __| __| #
#   | || .` | | | | _|| |__| |__ | | (_ | _|| .` | (__| _|  #
#  |___|_|\_| |_| |___|____|____|___\___|___|_|\_|\___|___| #
#   ___       _    _  _                                     #
#  / __|_ __ | |__| || |                                    #
# | (_ | '  \| '_ \ __ |                                    #
#  \___|_|_|_|_.__/_||_|                                    #
#                                                           #
#############################################################
#############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2026-05-08
# Version: 1.0.0
# Web: www.admin-intelligence.de
#############################################################
# Changelog
# v1.0.0 - inital release
#############################################################

set -u

SERVICE_NAME="CVE-2026-31431_Copy_Fail"

kernel="$(uname -r 2>/dev/null || echo unknown)"
base="${kernel%%-*}"

kernel_state="unknown"
algif_loaded="0"
algif_available="0"
algif_blocked="0"
suid_su="0"
python_ok="0"
score=0
details=()

ver_ge() {
  [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

ver_lt() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ] && [ "$1" != "$2" ]
}

add_detail() {
  details+=("$1")
}

if [ "$base" = "unknown" ] || [ -z "$base" ]; then
  kernel_state="unknown"
  add_detail "Kernel unbekannt"
elif ver_lt "$base" "4.14"; then
  kernel_state="not_affected"
  add_detail "Kernel < 4.14"
elif ver_ge "$base" "7.0"; then
  kernel_state="fixed"
  add_detail "Kernel >= 7.0"
elif ver_ge "$base" "6.19.12"; then
  kernel_state="fixed"
  add_detail "Kernel >= 6.19.12"
elif ver_ge "$base" "6.18.22"; then
  kernel_state="fixed"
  add_detail "Kernel >= 6.18.22"
else
  kernel_state="possibly_vulnerable"
  score=$((score+3))
  add_detail "Kernel im betroffenen Bereich"
fi

if lsmod 2>/dev/null | awk '{print $1}' | grep -qx 'algif_aead'; then
  algif_loaded="1"
  score=$((score+2))
  add_detail "algif_aead geladen"
fi

if modinfo algif_aead >/dev/null 2>&1; then
  algif_available="1"
  score=$((score+1))
  add_detail "algif_aead verfuegbar"
fi

if grep -RqsE '^[[:space:]]*install[[:space:]]+algif_aead[[:space:]]+/bin/false([[:space:]]|$)' \
  /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null; then
  algif_blocked="1"
  score=$((score-3))
  add_detail "algif_aead blockiert"
fi

if [ -u /usr/bin/su ] && [ -x /usr/bin/su ]; then
  suid_su="1"
  score=$((score+1))
  add_detail "SUID /usr/bin/su vorhanden"
fi

if command -v python3 >/dev/null 2>&1; then
  pyver="$(python3 - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
  if ver_ge "$pyver" "3.10"; then
    python_ok="1"
    score=$((score+1))
    add_detail "Python >= 3.10"
  else
    add_detail "Python < 3.10"
  fi
else
  add_detail "Python3 fehlt"
fi

state=3
label="unbekannt"

if [ "$kernel_state" = "not_affected" ] || [ "$kernel_state" = "fixed" ]; then
  state=0
  label="sicher"
elif [ "$algif_blocked" = "1" ] && [ "$algif_loaded" = "0" ]; then
  state=0
  label="sicher"
elif [ "$kernel_state" = "possibly_vulnerable" ] && \
     [ "$algif_available" = "1" ] && \
     [ "$algif_blocked" = "0" ] && \
     [ "$suid_su" = "1" ] && \
     [ "$python_ok" = "1" ]; then
  state=2
  label="verwundbar"
elif [ "$kernel_state" = "possibly_vulnerable" ]; then
  state=1
  label="moeglicherweise verwundbar"
else
  state=3
  label="unbekannt"
fi

summary="${label} - kernel=${kernel}, kernel_state=${kernel_state}, score=${score}"
if [ ${#details[@]} -gt 0 ]; then
  summary="${summary}; $(IFS='; '; echo "${details[*]}")"
fi

metrics="score=${score};4;6|algif_loaded=${algif_loaded};1;1|algif_available=${algif_available};1;1|algif_blocked=${algif_blocked};0;0|suid_su=${suid_su};1;1|python_ok=${python_ok};1;1"

printf '%s "%s" %s %s\n' "$state" "$SERVICE_NAME" "$metrics" "$summary"
exit 0