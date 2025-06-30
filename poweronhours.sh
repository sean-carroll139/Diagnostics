#!/bin/bash

# Threshold for power-on hours
THRESHOLD=30660

# Function to check the power-on hours of a drive
check_power_on_hours() {
    local device=$1

    # Get the power-on hours from smartctl
    power_on_hours=$(smartctl -A "$device" | grep "Power_On_Hours" | awk '{print $10}')

    if [ -z "$power_on_hours" ]; then
        echo "Error: Could not retrieve power-on hours for $device."
        return 1
    fi

    # Compare with the threshold and flag if necessary
    if [ "$power_on_hours" -gt "$THRESHOLD" ]; then
        echo "Warning: $device has $power_on_hours power-on hours, which exceeds the threshold of $THRESHOLD hours. Consider replacing the drive."
    else
        echo "$device is within the safe power-on hours limit ($power_on_hours hours)."
    fi
}

# Check all connected drives (sda, sdb, etc.)
for drive in /dev/sd?; do
    check_power_on_hours "$drive"
done
