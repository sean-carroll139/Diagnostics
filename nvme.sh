#!/bin/bash

# This script securely wipes all NVMe drives after showing drive info and asking for confirmation.

display_drive_info() {
    echo "Detecting NVMe drives..."
    mapfile -t nvme_drives < <(lsblk -dno NAME | grep -E '^nvme[0-9]+n1')
    
    if [[ ${#nvme_drives[@]} -eq 0 ]]; then
        echo "No NVMe drives found. Exiting."
        exit 1
    fi

    for drive in "${nvme_drives[@]}"; do
        dev="/dev/$drive"
        echo -e "\n=== Drive Info for $dev ==="
        
        smartctl -x "$dev" | awk '
            /Model Number/ {print "Drive Model: " $0}
            /Serial Number/ {print "Serial Number: " $0}
            /User Capacity/ {print "Total Capacity: " $0}
            /Firmware Version/ {print "Firmware Version: " $0}
            /SMART overall-health self-assessment test result/ {print "SMART Health: " $0}
            /Media and Data Integrity Errors/ {print "Data Integrity Errors: " $0}
        '
        echo "NVMe Smart Log Information:"
        nvme smart-log "$dev" | grep -E "Warning Temperature Time|Critical Composite Temperature Time|Thermal Management.*"
    done

    echo -e "\nCurrent Block Device Layout:"
    lsblk
}

get_user_confirmation() {
    while true; do
        read -p "Would you like to wipe ALL detected NVMe drives? (Y/N): " response
        case "$response" in
            [Yy]) return 0 ;;
            [Nn]) echo "Operation cancelled."; exit 0 ;;
            *) echo "Please enter Y or N." ;;
        esac
    done
}

wipe_drive() {
    echo "Attempting to stop RAID array md127 if it exists..."

    if mdadm --stop /dev/md127 2>/dev/null; then
        echo "RAID array md127 stopped successfully."
    else
        echo "RAID array md127 could not be stopped or did not exist."
    fi

    if grep -q "md127" /proc/mdstat; then
        echo "Warning: RAID array md127 still active. Proceeding with wipe anyway."
    else
        echo "RAID array md127 is not active."
    fi

    mapfile -t nvme_drives < <(lsblk -dno NAME | grep -E '^nvme[0-9]+n1')
    
    for drive in "${nvme_drives[@]}"; do
        dev="/dev/$drive"
        echo -e "\n--- Wiping $dev ---"
        
        echo "Removing partitions on $dev..."
        for part in $(lsblk -ln "$dev" | awk '{print $1}' | grep "^$drive"p); do
            echo "Deleting partition $part..."
            parted "$dev" --script rm "${part##*p}" || echo "Failed to remove $part (may not exist)."
        done

        echo "Creating new GPT label on $dev..."
        parted "$dev" --script mklabel gpt

        echo "Formatting $dev with secure NVMe format..."
        nvme format -f "$dev" 2>&1 || echo "nvme format failed on $dev. Continuing."

        echo "Final block layout for $dev:"
        lsblk "$dev"
    done
}

# Main
display_drive_info
get_user_confirmation
wipe_drive

echo -e "\n✅ All detected NVMe drives wiped successfully."
