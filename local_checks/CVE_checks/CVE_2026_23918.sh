#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SERVICE_NAME="CVE-2026-23918 Apache2 HTTP2 Flaw"

MIN_2404="2.4.58-1ubuntu8.12"
MIN_2204="2.4.52-1ubuntu4.20"

UBUNTU_CODENAME=$(lsb_release -sc 2>/dev/null || echo "unknown")

case "$UBUNTU_CODENAME" in
    noble)
        UBUNTU_LABEL="Ubuntu 24.04"
        REQ_VER="$MIN_2404"
        ;;
    jammy)
        UBUNTU_LABEL="Ubuntu 22.04"
        REQ_VER="$MIN_2204"
        ;;
    *)
        echo "0 \"$SERVICE_NAME\" - Nicht unterstützt: erkannt wurde '$UBUNTU_CODENAME', erwartet wird Ubuntu 24.04 (noble) oder 22.04 (jammy)"
        exit 0
        ;;
esac

if ! dpkg-query -W -f='${Status}' apache2 2>/dev/null | grep -q "install ok installed"; then
    echo "0 \"$SERVICE_NAME\" - Apache2 ist nicht installiert"
    exit 0
fi

INST_VER=$(dpkg-query -W -f='${Version}' apache2 2>/dev/null)

if [[ -z "$INST_VER" ]]; then
    echo "0 \"$SERVICE_NAME\" - Apache2 konnte nicht sauber abgefragt werden"
    exit 0
fi

if dpkg --compare-versions "$INST_VER" ge "$REQ_VER"; then
    echo "0 \"$SERVICE_NAME\" - $UBUNTU_LABEL: installierte Version $INST_VER, erforderlich mindestens $REQ_VER"
else
    echo "1 \"$SERVICE_NAME\" - Update erforderlich: $UBUNTU_LABEL: installierte Version $INST_VER, erforderlich mindestens $REQ_VER"
fi
