#!/bin/bash

#ver1.2 fixed 0 for time not functioning.
#added an option for bidirectional, but it doesnt work in forge6, only forge7. put note for prompt that its only forge7 option.
#added option for TCP or UDP
#need to add code to make input error detection, ie case sensitivity, different letters etc causing failures and ending the script.
echo "--------------------------------------------------------------------------"
echo "Setup your server test system to boot to a Linux distro, and run iperf3"
echo "as the server with a specific port of your choosing that no one else is"
echo "currently using (default 5002). The NIC or System that you will be testing"
echo "can be run in forge7. When running iperf this way, there are no errors,"
echo "unlike when testing from forge7 to forge7. Therefore, I suggest using a"
echo "Linux distribution instead of forge for the server system if you want to"
echo "perform network testing. Additionally, when using ping, avoid pinging a"
echo "website like Google. Instead, ping the system with the Linux distribution"
echo "on it. Pinging a website will always show dropped packets."
echo ""
echo "To acquire the IP address of the system you are configuring as the server,"
echo "execute the following command and identify the populated IP address"
echo "(ensure only one NIC is connected)."
echo ""
echo -e "To obtain the IP address from your Linux distro as the server, use the command: \033[1mifconfig -a\033[0m"
echo "Use that IP address for the prompts that will be asked of you below."
echo -e "Setup your server via the command: \033[1miperf3 -p 5002 -s\033[0m"
echo -e "To monitor, open a new terminal and install and load \033[1mnload\033[0m"
echo "--------------------------------------------------------------------------"

# Prompt for the port number
read -p "Enter the port number: " port

# Prompt for the IP address
read -p "Enter the IP address: " ip

# Prompt for the time in seconds, minutes, or hours
read -p "Enter the time (s/m/h, 0 for infinite): " time_input
time_unit=${time_input: -1} # Get the last character of the input
time_value=${time_input::-1} # Get the input without the last character

# Set the time to 0 if the user inputs 0
if [[ $time_input == "0" ]]; then
  time_in_seconds=0
else
  # Convert the time to seconds
  case $time_unit in
    "s")
      time_in_seconds=$time_value
      ;;
    "m")
      time_in_seconds=$((time_value * 60))
      ;;
    "h")
      time_in_seconds=$((time_value * 60 * 60))
      ;;
    *)
      echo "Invalid time unit. Exiting..."
      exit 1
      ;;
  esac
fi

# Prompt for simultaneous connections
read -p "Use simultaneous connections? Make multiple parallel connections. (y/n): " use_connections

if [[ $use_connections == "y" ]]; then
  read -p "Enter the number of simultaneous connections: " connections
  connections_arg="-P $connections"
else
  connections_arg=""
fi

# Prompt for reverse mode
read -p "Run iPerf3 in reverse mode? Server sends, client receives. (y/n): " reverse_mode

if [[ $reverse_mode == "y" ]]; then
  reverse_arg="-R"
else
  reverse_arg=""
fi

# Prompt for bidirectional mode
read -p "Run iPerf3 in bidirectional mode? Forge7 only. iperf3 v3.7 or greater. The client opens two TCP connections with the server: one is used for the forward test and one for the reverse. (y/n): " bidir_mode

if [[ $bidir_mode == "y" ]]; then
  bidir_arg="--bidir"
else
  bidir_arg=""
fi

# Prompt for TCP or UDP
read -p "Use TCP or UDP? (t/u): " protocol

if [[ $protocol == "t" ]]; then
  # Run iPerf3 with TCP and the specified parameters
  iperf3 -c $ip -p $port -t $time_in_seconds $connections_arg $reverse_arg $bidir_arg -i 1 -d -O 2 -V
elif [[ $protocol == "u" ]]; then
  # Run iPerf3 with UDP and the specified parameters
  iperf3 -c $ip -p $port -t $time_in_seconds $connections_arg $reverse_arg $bidir_arg -u -i 1 -d -O 2 -V
else
  echo "Invalid protocol. Exiting..."
  exit 1
fi

# Find the first Ethernet port starting with 172
eth_port=$(ip -o addr show | awk '/172/ {print $2}' | cut -d':' -f1 | head -n 1)

#add log files for the commands.
#filename="output_$(date +'%Y-%m-%d_%H-%M-%S')_${eth_port}_${ip}.txt"
#> $filename
#>> $filename
#echo "Commands and outputs saved to $filename"


# Run ethtool -S with the found port and grep for 'dropped\|error'
echo "Tested port: $eth_port Time in seconds: $time_in_seconds"
#ping -I $eth_port -n -c 4 "www.google.com"
read -p "Would you like to run ping? (yes/no): " choice
choice=${choice,,}  # Convert input to lowercase

if [[ "$choice" == "yes" || "$choice" == "y" ]]; then
    ping -I $eth_port -c 4 $ip
elif [[ "$choice" == "no" || "$choice" == "n" ]]; then
    echo "Exiting..."
    exit 0
else
    echo "Moving along"
fi

ethtool -S $eth_port | grep 'dropped\|error'
ip -s link show $eth_port
ifconfig $eth_port
#echo "You also try ethtool -t $eth_port or mtr google.com for additional testing"