#!/bin/bash

output_file="/usr/lib/check_mk_agent/pve_backup_check"

not_backed_up_entries=()

### VMs prüfen
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
    disks=$(qm config $vmid | grep -E '^(scsi|sata|ide|virtio)[0-9]+' | grep -v 'media=cdrom' | awk -F: '{print $1}')
    for disk in $disks; do
        config_line=$(qm config $vmid | grep "^$disk:")
        if echo "$config_line" | grep -q "backup=0"; then
            not_backed_up_entries+=("VM $vmid Disk $disk")
        fi
    done
done

### Container prüfen
for ctid in $(pct list | awk 'NR>1 {print $1}'); do
    mounts=$(pct config $ctid | grep -E '^(mp[0-9]+|rootfs):' | awk -F: '{print $1}')
    for mount in $mounts; do
        config_line=$(pct config $ctid | grep "^$mount:")
        if echo "$config_line" | grep -q "backup=0"; then
            not_backed_up_entries+=("LXC $ctid Mount $mount")
        fi
    done
done

# Checkmk Agent Ausgabe: Single line with status and description
if [ ${#not_backed_up_entries[@]} -eq 0 ]; then
    echo "0 \"PVE Backup check\" - All disks and mounts are included in backup" > "$output_file"
else
    description=$(IFS=', '; echo "${not_backed_up_entries[*]}")
    echo "2 \"PVE Backup check\" - NOT backed up: $description" > "$output_file"
fi
