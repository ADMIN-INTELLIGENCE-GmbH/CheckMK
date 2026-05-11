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
# Checkmk Micro-Bakery Client v4.0
############################################################
# Author: Sascha Jelinek
# Company: ADMIN INTELLIGENCE GmbH
# Date: 2026-05-11
# Version: 4.0.1
# Web: www.admin-intelligence.de
############################################################

# --- KONFIGURATION ---
API_URL="https://[your_domain]/api/checkin"
GLOBAL_SETUP_KEY="..."
KEY_FILE="/etc/check_mk_bakery.key"
AGENT_LOCAL="/usr/lib/check_mk_agent/local"
# ---------------------

# 1. Voraussetzungen sicherstellen (jq)
if ! command -v jq &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq jq > /dev/null 2>&1
fi

# 2. Token bestimmen (Individueller Key oder Bootstrap-Key)
if [ -f "$KEY_FILE" ]; then
    CURRENT_TOKEN=$(cat "$KEY_FILE")
    TOKEN_INFO="Individual Host-Token"
else
    CURRENT_TOKEN="$GLOBAL_SETUP_KEY"
    TOKEN_INFO="Global Setup-Key"
fi

# 3. Metadaten sammeln
HOSTNAME=$(hostname -f)
IP_LIST=$(hostname -I)

# OS Informationen (Wichtig für das Icon in der GUI)
OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
[ -z "$OS_NAME" ] && OS_NAME=$(lsb_release -ds 2>/dev/null)
[ -z "$OS_NAME" ] && OS_NAME="Linux (Unknown Distro)"

# Kernel Version
KERNEL_VERSION=$(uname -r)

# 4. Lokale Plugins scannen & Inhalte für Discovery sammeln
PLUGINS_JSON="{}"
DISCOVERED_CONTENTS="{}"

if [ -d "$AGENT_LOCAL" ]; then
    for script in "$AGENT_LOCAL"/*; do
        # Nur echte Dateien verarbeiten, keine Verzeichnisse oder das Bakery-Skript selbst
        if [ -f "$script" ] && [ "$(basename "$script")" != "98_check_mk_bakery.sh" ]; then
            FILENAME=$(basename "$script")
            
            # Version extrahieren (Suche nach # Version: X.X.X)
            VERSION=$(grep -E '^# Version:' "$script" | head -n1 | sed -e 's/^# Version: *//' -e 's/[^0-9a-zA-Z.\-]//g')
            [ -z "$VERSION" ] && VERSION="1.0.0"
            
            # Zu Plugin-Liste hinzufügen
            PLUGINS_JSON=$(echo "$PLUGINS_JSON" | jq --arg k "$FILENAME" --arg v "$VERSION" '.[$k]=$v')
            
            # Inhalt mitsenden für Discovery (Base64 kodiert)
            CONTENT_B64=$(base64 -w 0 < "$script")
            DISCOVERED_CONTENTS=$(echo "$DISCOVERED_CONTENTS" | jq --arg k "$FILENAME" --arg v "$CONTENT_B64" '.[$k]=$v')
        fi
    done
fi

# 5. JSON Payload bauen (Hier werden OS und KERNEL gemappt!)
PAYLOAD=$(jq -n \
    --arg h "$HOSTNAME" \
    --arg i "$IP_LIST" \
    --arg os "$OS_NAME" \
    --arg kn "$KERNEL_VERSION" \
    --argjson p "$PLUGINS_JSON" \
    --argjson d "$DISCOVERED_CONTENTS" \
    '{hostname: $h, ip_addresses: $i, os_name: $os, kernel: $kn, plugins: $p, discovered_contents: $d}')

# 6. API Call Funktion
TMP_RES="/tmp/bakery_res.json"

perform_checkin() {
    local token=$1
    curl -s -k -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$PAYLOAD" \
        -o "$TMP_RES" \
        -w "%{http_code}" \
        "$API_URL"
}

HTTP_CODE=$(perform_checkin "$CURRENT_TOKEN")

# --- 7. FAILSAFE: Re-Bootstrap ---
if [ "$HTTP_CODE" -eq 403 ]; then
    # Wenn der Token abgelehnt wird, löschen wir ihn und versuchen es mit dem Global Key
    rm -f "$KEY_FILE"
    CURRENT_TOKEN="$GLOBAL_SETUP_KEY"
    TOKEN_INFO="Global Setup-Key (Failsafe)"
    HTTP_CODE=$(perform_checkin "$CURRENT_TOKEN")
fi

if [ "$HTTP_CODE" -ne 200 ]; then
    echo "2 \"Checkmk micro bakery\" - Error: API rejected request (HTTP $HTTP_CODE). Auth: $TOKEN_INFO"
    exit 2
fi

BODY=$(cat "$TMP_RES")

# 8. Neuen API-Key speichern bei Erst-Registrierung
NEW_KEY=$(echo "$BODY" | jq -r '.new_api_key // empty')
if [ -n "$NEW_KEY" ] && [ "$NEW_KEY" != "null" ]; then
    echo "$NEW_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
fi

# 9. Aktionen verarbeiten (install / update / delete)
ACTIONS_B64=$(echo "$BODY" | jq -r '.actions[]? | @base64' 2>/dev/null)
installs=0; updates=0; deletes=0; errors=0; DETAILS=""

for action_b64 in $ACTIONS_B64; do
    ACTION_ROW=$(echo "$action_b64" | base64 --decode)
    TYPE=$(echo "$ACTION_ROW" | jq -r '.action')
    FILE=$(echo "$ACTION_ROW" | jq -r '.filename')
    B64_CONTENT=$(echo "$ACTION_ROW" | jq -r '.content')
    FILE_PATH="$AGENT_LOCAL/$FILE"

    if [[ "$TYPE" == "install" || "$TYPE" == "update" ]]; then
        # Skriptinhalt dekodieren und speichern
        if echo "$B64_CONTENT" | base64 --decode > "$FILE_PATH"; then
            chmod 755 "$FILE_PATH"
            DETAILS="$DETAILS\n - $TYPE: $FILE"
            [[ "$TYPE" == "install" ]] && ((installs++)) || ((updates++))
        else
            ((errors++))
            DETAILS="$DETAILS\n - error during $TYPE: $FILE"
        fi
    elif [[ "$TYPE" == "delete" ]]; then
        # Löschen nur auf expliziten Befehl der Bakery GUI
        if rm -f "$FILE_PATH"; then
            ((deletes++))
            DETAILS="$DETAILS\n - deleted: $FILE"
        else
            ((errors++))
            DETAILS="$DETAILS\n - error deleting: $FILE"
        fi
    fi
done

# 10. Status für Checkmk ausgeben
orphans_count=$(echo "$BODY" | jq -r '.orphans_to_confirm | length' 2>/dev/null)
STATUS=0
((orphans_count > 0 || installs > 0 || updates > 0 || deletes > 0)) && STATUS=1
((errors > 0)) && STATUS=2

# Finales Output für den Agenten
echo "$STATUS \"Checkmk micro bakery\" - OS: $OS_NAME | Kernel: $KERNEL_VERSION | Tasks: +$installs/~$updates/-$deletes | Pending: $orphans_count\nDetails:$DETAILS"

rm -f "$TMP_RES"