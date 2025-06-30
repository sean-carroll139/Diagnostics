#!/bin/bash

###########################################################
# Script: port-flap-single-interface.sh
# Author: [Sean Carroll]
# Description: This script monitors a single network interface
#              for port flaps (i.e., interface going down
#              and up unexpectedly). It continuously brings
#              the specified network interface down and up,
#              while logging any unexpected flaps to a log file.
#              The script also displays the total number of
#              expected and unexpected flaps for the interface.
#              Log files are saved in the /testing/flap_logs directory.
# Usage: Run the script, select the network interface from the list,
#        and specify the corresponding number (e.g., 1).
###########################################################

# Function to prompt the user to choose an interface
prompt_interface_selection() {
    # Get a list of network interfaces and sort them alphabetically
    interfaces=($(ls /sys/class/net | sort))

    # Display a numbered list of network interfaces for the user to choose from
    echo "Select the network interface to monitor:"
    for i in "${!interfaces[@]}"; do
        echo "$(($i+1)). ${interfaces[$i]}"
    done

    # Prompt the user to choose an interface by its corresponding number
    read -p "Enter the number of the network interface: " interface_number

    # Validate the user input
    if ! [[ "$interface_number" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid input. Please enter a valid number."
        prompt_interface_selection
    fi

    # Check if the chosen interface number is within the valid range
    if ((interface_number < 1)) || ((interface_number > ${#interfaces[@]})); then
        echo "Error: Invalid interface number. Please choose a number within the valid range."
        prompt_interface_selection
    fi

    # Get the selected interface name based on the chosen number
    INTERFACE="${interfaces[$(($interface_number-1))]}"
}

# Prompt the user to select the network interface
prompt_interface_selection

# Set the path for the log directory
LOG_DIR="/testing/flap_logs"

# Create the log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Set the log file for the interface
LOG_FILE="$LOG_DIR/$INTERFACE.log"

# Initialize counters for expected and unexpected flaps
EXPECTED_FLAPS=0
UNEXPECTED_FLAPS=0

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S"): $message" >> "$LOG_FILE"
    echo "$message"
}

# Function to handle Ctrl+C and save the log file
cleanup() {
    log_message "Script terminated. Saving log file..."
    log_message "Interface: $INTERFACE"
    log_message "Total Expected Flaps: $EXPECTED_FLAPS"
    log_message "Total Unexpected Flaps: $UNEXPECTED_FLAPS"
    log_message "Log file saved at: $LOG_FILE"  # Indicate where the log file is saved
    exit 0
}

# Trap Ctrl+C signal to call the cleanup function
trap cleanup SIGINT

# Log the initial message for the interface
log_message "Monitoring port flaps on interface $INTERFACE..."
log_message "Log file saved at: $LOG_FILE"  # Indicate where the log file is saved

# Main loop for the interface
while true; do
    # Bring the interface down
    log_message "Bringing $INTERFACE down..."
    if ! ip link set $INTERFACE down; then
        log_message "Failed to bring $INTERFACE down! Exiting..."
        exit 1
    fi
    sleep 5  # Delay after bringing the interface down

    # Check if the interface is down
    if ! ip link show $INTERFACE | grep -q "state UP"; then
        ((EXPECTED_FLAPS++))
        log_message "Interface $INTERFACE is down as expected."
    else
        log_message "Unexpected flap detected on $INTERFACE. Logging..."
        ((UNEXPECTED_FLAPS++))
        # Notify administrators or take other actions here
    fi

    # Bring the interface up
    log_message "Bringing $INTERFACE up..."
    if ! ip link set $INTERFACE up; then
        log_message "Failed to bring $INTERFACE up! Exiting..."
        exit 1
    fi
    sleep 5  # Delay after bringing the interface up

    # Check if the interface is up
    if ip link show $INTERFACE | grep -q "state UP"; then
        log_message "Interface $INTERFACE is up."
    else
        log_message "Failed to bring $INTERFACE up! Logging as an unexpected flap..."
        ((UNEXPECTED_FLAPS++))
        # Notify administrators or take other actions here
    fi
done
