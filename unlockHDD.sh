#!/bin/bash

###########################################################
# Script: unlockHDD.sh
# Author: [Sean Carroll]
# Description: This script checks for locked drives and attempts
#              to unlock them using the 'hdparm' command with
#              a default password. It loops through all drives
#              detected on the system and checks if they are locked.
#              If a drive is locked, it attempts to unlock it
#              using various methods. Finally, it provides a prompt
#              for the user to manually check if the drives have been
#              successfully unlocked.
# Usage: Run the script to automatically unlock locked drives. 
#        Optionally, run 'hdparm -I /dev/sd{a..x} | grep locked'
#        to manually verify the unlocking status of the drives.
###########################################################

# Function to check and unlock locked drives
unlock_drives() {
    local drive=$1
    local password="password"

    # Check if the drive is locked
    if hdparm -I "$drive" | grep -q "not locked"; then
        echo "$drive is not locked"
    else
        # Unlock the drive
        if hdparm --security-unlock "$password" "$drive" >/dev/null 2>&1 ||
           hdparm --user-master u --security-unlock "$password" "$drive" >/dev/null 2>&1 ||
           hdparm --user-master u --security-disable "$password" "$drive" >/dev/null 2>&1; then
            echo "Successfully unlocked $drive"
        else
            echo "Failed to unlock $drive"
        fi
    fi
}

# Get list of all drives
drives=$(lsblk -o NAME -n -d)

# Loop through each drive
for drive in $drives; do
    unlock_drives "/dev/$drive"
done

#Inform the user to manually check if the drives have been unlocked
echo "If you'd like to manually verify that the HDDs have been unlocked, you can run the following command: hdparm -I /dev/sd{a..x} | grep locked"