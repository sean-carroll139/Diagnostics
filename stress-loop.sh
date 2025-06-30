#!/bin/bash

# Check and install stress if not installed
if ! command -v stress &> /dev/null; then
    echo "Installing stress command..."
    sudo apt-get install -y stress
fi

# Check and install lxterminal if not installed
if ! command -v lxterminal &> /dev/null; then
    echo "Installing lxterminal..."
    sudo apt-get install -y lxterminal
fi

# Check and install htop if not installed
if ! command -v htop &> /dev/null; then
    echo "Installing htop..."
    sudo apt-get install htop
fi

# Check and install xdotool if not installed
if ! command -v xdotool &> /dev/null; then
    echo "Installing xdotool..."
    sudo apt-get install -y xdotool
fi

# Open htop in a new terminal window
lxterminal --title "htop" -e "htop"

vm_toggle=1  # Initialize toggle to vm 1
iteration=1   # Initialize the iteration counter

while true; do
    clear

    echo "===================================="
    echo "Stress Test Automation Script"
    echo "===================================="

    # Get the number of CPU cores/threads
    cpu_cores=$(nproc)
    echo "Number of CPU cores/threads: $cpu_cores"

    # Get the total installed RAM in megabytes
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    echo "Total installed RAM: $total_ram MB"

    # Calculate the amount of RAM to stress (80-85%)
    ram_to_stress=$((total_ram * 85 / 100))
    
    # Create a random duration for stress (1-20 minutes) and sleep (1-5 minutes) in seconds
    stress_duration=$((1 + RANDOM % 1200))  # 1-20 minutes in seconds
    sleep_duration=$((1 + RANDOM % 300))    # 1-5 minutes in seconds

    echo "===================================="
    echo "Starting Stress Test (Iteration $iteration)"
    echo "Stress Duration: $((stress_duration / 60)) minutes"
    echo "Sleep Duration: $((sleep_duration / 60)) minutes"
    echo "===================================="

    if [ $vm_toggle -eq 1 ]; then
        stress_command="stress --cpu $cpu_cores --vm 1 --vm-bytes ${ram_to_stress}M --timeout ${stress_duration}s"
        echo "Stress Command (vm 1):"
        echo "$stress_command"
        echo "===================================="
        echo "Amount of RAM to stress (85% of total RAM) - Iteration $iteration: $ram_to_stress MB"
		echo "===================================="
    else
        stress_command="stress --cpu $cpu_cores --vm 3 --vm-bytes $((ram_to_stress * 30 / 100))M --timeout ${stress_duration}s"
        echo "Stress Command (vm 3):"
        echo "$stress_command"
        echo "===================================="
        echo "Amount of RAM to stress (30% of total RAM) - Iteration $iteration: $ram_to_stress MB"
		echo "===================================="
    fi

    # Run the stress command to stress CPU and RAM in the background
    ($stress_command) & stress_pid=$!

    # Display a timer for the stress test
    while [ -n "$(ps -p $stress_pid -o pid=)" ]; do
        stress_runtime=$(ps -o etimes= -p $stress_pid)
        remaining_time=$((stress_duration - stress_runtime))
        printf "\rTime remaining in stress test (Iteration $iteration): %02d:%02d" $((remaining_time / 60)) $((remaining_time % 60))
        sleep 1
    done

    echo -e "\r\033[KStress test (Iteration $iteration) completed."

    # Wait for the stress test to finish
    wait $stress_pid

    echo "===================================="
    echo "Sleeping Before Next Iteration"
    echo "===================================="

    # Display a timer for the sleep duration
    while [ $sleep_duration -gt 0 ]; do
        printf "\rTime remaining in sleep (Iteration $iteration): %02d:%02d" $((sleep_duration / 60)) $((sleep_duration % 60))
        sleep 1
        sleep_duration=$((sleep_duration - 1))
    done

    echo -e "\r\033[KSleep (Iteration $iteration) completed."

    iteration=$((iteration + 1))

    if [ $vm_toggle -eq 1 ]; then
        vm_toggle=0  # Toggle to vm 3 for the next iteration
    else
        vm_toggle=1  # Toggle back to vm 1 for the next iteration
    fi
done
