#!/bin/bash

# Create a folder to save SMART data in the /smart/data directory
data_folder="/smart/data"
mkdir -p "$data_folder"

# Get a list of all drives using lsblk
drives=$(lsblk -o name -d -n | grep -E '^sd[a-z]$|^nvme[0-9]n[0-9]$')

# Function to extract serial number
get_serial_number() {
    local device_path="$1"
    local smartctl_info=$(smartctl -i "$device_path")
    echo "$smartctl_info" | grep -oP 'Serial [Nn]umber:\s*\K\S+'
}

# Iterate through each drive and fetch SMART data
for drive in $drives; do
    if [[ "$drive" =~ ^nvme[0-9]n[0-9]$ ]]; then
        # NVMe device detected, drop the nX to get SMART data
        device="/dev/${drive%n*}"
    else
        device="/dev/$drive"
    fi

    serial_number=$(get_serial_number "$device")

    if [ -n "$serial_number" ]; then
        echo "Fetching SMART data for $device (Serial Number: $serial_number)"
        output_file="$data_folder/$serial_number.txt"
        smartctl --all "$device" > "$output_file"
        echo "Data saved to: $output_file"
        echo "------------------------------------"
    else
        echo "Failed to fetch SMART data for $device (Serial Number not found)"
        echo "------------------------------------"
    fi
done

# Prompt to save a copy of the "smart/data" directory to a specific drive
read -p "Do you want to save a copy of the 'smart/data' directory to a specific drive? (y/n) " choice
if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
    echo "Available drives for copying:"
    lsblk -o name,rm -d -n

    read -p "Enter the target drive (e.g., /dev/sdq1) for copying the folder: " target_partition

    if [ -b "$target_partition" ]; then
        if [ -d "$data_folder" ]; then
            echo "Mounting $target_partition..."
            sudo mount "$target_partition" /mnt

            # Copy the entire "/smart/data" directory to the target
            echo "Copying contents to /mnt/smart/data on $target_partition..."
            sudo cp -ar "$data_folder" "/mnt/smart/"

            echo "Unmounting $target_partition..."
            sudo umount "$target_partition"
            echo "Data copied to $target_partition in /mnt/smart/data"
        else
            echo "Failed to find the '/smart/data' directory."
        fi
    else
        echo "Invalid target partition: $target_partition"
    fi
fi
