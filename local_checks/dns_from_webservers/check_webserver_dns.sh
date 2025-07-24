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
# "local check" script to parse the vhost and create
#  a DNS check for every occurance
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2024-07-24
# Version: 2.0.0
# Web: www.admin-intelligence.de
############################################################

TEMPFILE=$(mktemp)
DNS_SERVER="1.1.1.1"
FILTERED_TEMPFILE=$(mktemp)

# Funktion zum Extrahieren von ServerName-Einträgen
extract_server_names() {
    local config_file="$1"
    local server_type="$2"

    case "$server_type" in
        "apache")
            # Apache
            APACHE_DIR="/etc/apache2/sites-enabled"
            if [ -d "$APACHE_DIR" ]; then
                while IFS= read -r -d '' file; do
                    # Extrahiere ServerName
                    grep -h "^\s*ServerName" "$file" | awk '{print $2}' >> "$TEMPFILE"
                    # Extrahiere ServerAlias
                    grep -h "^\s*ServerAlias" "$file" | sed 's/ServerAlias//' | tr ' ' '\n' | sed '/^$/d' >> "$TEMPFILE"
                done < <(find -L "$APACHE_DIR" -type f -name '*.conf' -print0)
            else
                echo "Apache configuration directory not found: $APACHE_DIR" >&2
            fi
            ;;
        "nginx")
            awk '/server_name/ {for (i=2; i<=NF; i++) print $i}' "$config_file" | sed 's/;//'
            ;;
        "caddy")
            awk '{print $1}' "$config_file" | grep -v '#' | grep -v '^$'
            ;;
    esac
}

# Apache
if [ -d "/etc/apache2/sites-enabled" ]; then
    extract_server_names "/etc/apache2/sites-enabled/*.conf" "apache" >> "$TEMPFILE"
fi

# NGINX
if [ -d "/etc/nginx/sites-enabled" ]; then
    extract_server_names "/etc/nginx/sites-enabled/*" "nginx" >> "$TEMPFILE"
fi

# Caddy
if [ -f "/etc/caddy/Caddyfile" ]; then
    extract_server_names "/etc/caddy/Caddyfile" "caddy" >> "$TEMPFILE"
fi

# Zusätzlicher Pfad für Caddy
if [ -f "/docker/caddy/Caddyfile" ]; then
    extract_server_names "/docker/caddy/Caddyfile" "caddy" >> "$TEMPFILE"
fi

# Funktion zur Überprüfung von FQDNs und öffentlichen TLDs
is_valid_fqdn() {
    local domain="$1"
    # Überprüfe, ob die Domain mindestens einen Punkt enthält und nicht mit einem Punkt beginnt oder endet
    if [[ "$domain" == *.* && "$domain" != .* && "$domain" != *. ]]; then
        # Liste öffentlicher TLDs (dies ist eine vereinfachte Liste, die erweitert werden kann)
        local public_tlds="com|net|org|edu|gov|mil|info|biz|name|pro|aero|coop|museum|eu|de|at|ch|uk|fr|it|es|nl|be|se|no|dk|fi|pl|cz|hu|ro|bg|gr|pt|ie|lu"
        # Überprüfe, ob die TLD in der Liste der öffentlichen TLDs ist
        if [[ "$domain" =~ \.(${public_tlds})$ ]]; then
            return 0
        fi
    fi
    return 1
}

# Filtere die Einträge
while IFS= read -r SERVERNAME; do
    if is_valid_fqdn "$SERVERNAME"; then
        echo "$SERVERNAME" >> "$FILTERED_TEMPFILE"
    fi
done < "$TEMPFILE"

# Ersetze das ursprüngliche TEMPFILE mit dem gefilterten
mv "$FILTERED_TEMPFILE" "$TEMPFILE"

# Entferne Duplikate, leere Zeilen und führende/nachfolgende Leerzeichen
sort -u "$TEMPFILE" | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "${TEMPFILE}.tmp"
mv "${TEMPFILE}.tmp" "$TEMPFILE"

while IFS= read -r SERVERNAME; do
    if [[ -z "$SERVERNAME" ]]; then
        continue
    fi
    
    # DNS-Abfrage mit dig und spezifischem DNS-Server
    DNSCHECK=$(dig @$DNS_SERVER +short "$SERVERNAME" A)
    EXIT=$?
    
    if [[ $EXIT -eq 0 && -n "$DNSCHECK" ]]; then
        IP=$(echo "$DNSCHECK" | head -n1)
        RESPONSE_TIME=$(dig @$DNS_SERVER "$SERVERNAME" +tries=1 +time=2 +stats | grep "Query time:" | awk '{print $4}')
        echo "0 \"DNS $SERVERNAME\" response_time=${RESPONSE_TIME}ms;;;0; IP address: $IP"
    else
        echo "0 \"DNS $SERVERNAME\" - DNS resolution failed"
    fi
done < "$TEMPFILE"

rm -f "$TEMPFILE"
