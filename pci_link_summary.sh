#!/bin/bash

# Colorblind-friendly ANSI codes with orange instead of yellow
ORANGE='\033[38;5;208m'
BWHITE='\033[1;97m'
NC='\033[0m'

# Warn if required tools aren't available
if ! command -v udevadm &>/dev/null && ! command -v lshw &>/dev/null; then
    echo -e "${ORANGE}Warning: Neither 'udevadm' nor 'lshw' is installed. Serial number info may be unavailable for some devices.${NC}"
fi

get_link_info() {
    local dev="$1"
    local sysfs_base="/sys/bus/pci/devices"
    local full_path="$sysfs_base/0000:$dev"

    if [[ ! -d "$full_path" ]]; then
        full_path="$sysfs_base/$dev"
    fi

    if [[ -e "$full_path/current_link_speed" && -e "$full_path/current_link_width" ]]; then
        current_speed=$(cat "$full_path/current_link_speed")
        current_width=$(cat "$full_path/current_link_width")
        max_speed=$(cat "$full_path/max_link_speed")
        max_width=$(cat "$full_path/max_link_width")
        echo "$current_speed|$current_width|$max_speed|$max_width"
    else
        echo "N/A|N/A|N/A|N/A"
    fi
}

get_serial_number() {
    local pci_addr="$1"
    local sys_path="/sys/bus/pci/devices/$pci_addr"
    local serial="N/A"

    if command -v udevadm &>/dev/null; then
        serial=$(udevadm info --query=all --path="$sys_path" 2>/dev/null | grep 'ID_SERIAL=' | cut -d'=' -f2)
    fi

    if [[ -z "$serial" || "$serial" == "N/A" ]] && command -v lshw &>/dev/null; then
        serial=$(lshw -c storage -c disk -c network -businfo 2>/dev/null | grep "$pci_addr" | awk '{print $NF}')
    fi

    if [[ -z "$serial" ]]; then
        serial="N/A"
    fi

    echo "$serial"
}

get_nvme_serial() {
    local pci_addr="$1"
    local serial="N/A"
    nvme_name=$(basename "$(readlink -f /sys/bus/pci/devices/$pci_addr/nvme/nvme* 2>/dev/null)" 2>/dev/null)
    if [[ -n "$nvme_name" && -e "/sys/class/nvme/$nvme_name/serial" ]]; then
        serial=$(cat "/sys/class/nvme/$nvme_name/serial")
    fi
    echo "$serial"
}

mapfile -t all_devices < <(lspci -D)

declare -a nvme_devs raid_devs gpu_devs net_devs usb_devs audio_devs storage_devs misc_devs cpu_devs unknown_devs bridge_devs noinfo_devs ram_devs warnings

for line in "${all_devices[@]}"; do
    pci_addr=$(echo "$line" | awk '{print $1}')
    desc=$(echo "$line" | cut -d' ' -f2-)
    short_addr="${pci_addr#0000:}"
    link_raw=$(get_link_info "$short_addr")
    IFS='|' read -r cur_speed cur_width max_speed max_width <<< "$link_raw"

    if [[ "$cur_speed" == "N/A" && "$cur_width" == "N/A" ]]; then
        noinfo_devs+=("$pci_addr|$desc|$cur_speed|$cur_width|$max_speed|$max_width")
        continue
    fi

    entry="$pci_addr|$desc|$cur_speed|$cur_width|$max_speed|$max_width"

    if [[ "$desc" =~ Unknown ]]; then
        unknown_devs+=("$entry")
        continue
    fi

    if [[ "$desc" =~ "Non-Volatile memory controller" || "$desc" =~ "NVMe" ]]; then
        if [[ ! "$desc" =~ Memory ]] && [[ ! "$desc" =~ DIMM ]] && [[ ! "$desc" =~ Persistent ]]; then
            nvme_devs+=("$entry")
            continue
        fi
    fi

    if [[ "$desc" =~ "Memory controller" || "$desc" =~ "DIMM" || "$desc" =~ "Persistent Memory" ]]; then
        ram_devs+=("$entry")
        continue
    fi

    case "$desc" in
        *"PCI bridge"*|*"Host bridge"*)
            bridge_devs+=("$entry")
            ;;
        *"RAID bus controller"*|*"SATA controller"*)
            raid_devs+=("$entry")
            ;;
        *"VGA compatible controller"*|*"3D controller"*|*"Display controller"*)
            gpu_devs+=("$entry")
            ;;
        *"Ethernet controller"*|*"Network controller"*)
            net_devs+=("$entry")
            ;;
        *"USB controller"*)
            usb_devs+=("$entry")
            ;;
        *"Audio device"*|*"Multimedia audio controller"*)
            audio_devs+=("$entry")
            ;;
        *"Mass storage controller"*|*"Storage controller"*)
            storage_devs+=("$entry")
            ;;
        *"Host bridge"*|*"Root Complex"*|*"ISA bridge"*|*"System controller"*|*"Processor"*)
            cpu_devs+=("$entry")
            ;;
        *)
            misc_devs+=("$entry")
            ;;
    esac
done

print_devices() {
    local devs=("$@")
    for entry in "${devs[@]}"; do
        IFS='|' read -r pci_addr desc cur_speed cur_width max_speed max_width <<< "$entry"

        line=$(printf "%-12s %-60s Current: %s x%s | Max: %s x%s" \
            "$pci_addr" "$desc" "$cur_speed" "$cur_width" "$max_speed" "$max_width")

        if [[ "$cur_speed" != "$max_speed" || "$cur_width" != "$max_width" ]]; then
            echo -e "${ORANGE}${line}${NC}\n"
        else
            echo -e "${BWHITE}${line}${NC}\n"
        fi
    done
}

print_nvme_devices() {
    local devs=("$@")
    for entry in "${devs[@]}"; do
        IFS='|' read -r pci_addr desc cur_speed cur_width max_speed max_width <<< "$entry"
        serial=$(get_nvme_serial "$pci_addr")

        line=$(printf "%-12s %-60s Current: %s x%s | Max: %s x%s | Serial: %s" \
            "$pci_addr" "$desc" "$cur_speed" "$cur_width" "$max_speed" "$max_width" "$serial")

        if [[ "$cur_speed" != "$max_speed" || "$cur_width" != "$max_width" ]]; then
            echo -e "${ORANGE}${line}${NC}\n"
        else
            echo -e "${BWHITE}${line}${NC}\n"
        fi
    done
}

add_warnings_from_group() {
    local group=("$@")
    for entry in "${group[@]}"; do
        IFS='|' read -r pci_addr desc cur_speed cur_width max_speed max_width <<< "$entry"
        if [[ "$cur_speed" != "$max_speed" || "$cur_width" != "$max_width" ]]; then
            if [[ "$desc" =~ "Non-Volatile memory controller" || "$desc" =~ "NVMe" ]]; then
                serial=$(get_nvme_serial "$pci_addr")
            else
                serial=$(get_serial_number "$pci_addr")
            fi
            line=$(printf "%-12s %-60s Current: %s x%s | Max: %s x%s | Serial: %s" \
                "$pci_addr" "$desc" "$cur_speed" "$cur_width" "$max_speed" "$max_width" "$serial")
            warnings+=("$line")
        fi
    done
}

add_warnings_from_group "${nvme_devs[@]}"
add_warnings_from_group "${ram_devs[@]}"
add_warnings_from_group "${raid_devs[@]}"
add_warnings_from_group "${gpu_devs[@]}"
add_warnings_from_group "${net_devs[@]}"
add_warnings_from_group "${usb_devs[@]}"
add_warnings_from_group "${audio_devs[@]}"
add_warnings_from_group "${storage_devs[@]}"
add_warnings_from_group "${misc_devs[@]}"
add_warnings_from_group "${cpu_devs[@]}"
add_warnings_from_group "${bridge_devs[@]}"
add_warnings_from_group "${unknown_devs[@]}"

if [[ ${#warnings[@]} -gt 0 ]]; then
    echo -e "${ORANGE}⚠️  Devices NOT at Max PCI Speed:${NC}"
    for warn in "${warnings[@]}"; do
        echo -e "$warn"
        echo
    done
else
    echo -e "${BWHITE}✅ All PCI devices are running at their maximum supported speed and width.${NC}"
fi

echo -e "${BWHITE}================ NVMe Devices ================${NC}"
print_nvme_devices "${nvme_devs[@]}"

echo -e "${BWHITE}================ RAM / Memory Devices ================${NC}"
print_devices "${ram_devs[@]}"

echo -e "${BWHITE}================ RAID / SATA Controllers ================${NC}"
print_devices "${raid_devs[@]}"

echo -e "${BWHITE}================ GPUs / Display Controllers ================${NC}"
print_devices "${gpu_devs[@]}"

echo -e "${BWHITE}================ Network Controllers ================${NC}"
print_devices "${net_devs[@]}"

echo -e "${BWHITE}================ USB Controllers ================${NC}"
print_devices "${usb_devs[@]}"

echo -e "${BWHITE}================ Audio Devices ================${NC}"
print_devices "${audio_devs[@]}"

echo -e "${BWHITE}================ Other Storage Controllers ================${NC}"
print_devices "${storage_devs[@]}"

echo -e "${BWHITE}================ Miscellaneous PCI Devices ================${NC}"
print_devices "${misc_devs[@]}"

echo -e "${BWHITE}================ CPU / Chipset PCI Devices ================${NC}"
print_devices "${cpu_devs[@]}"

echo -e "${BWHITE}================ PCI Bridges and Host Bridges ================${NC}"
print_devices "${bridge_devs[@]}"

echo -e "${BWHITE}================ Unknown Devices ================${NC}"
print_devices "${unknown_devs[@]}"

if [[ ${#noinfo_devs[@]} -gt 0 ]]; then
    echo -e "${BWHITE}================ Devices with No Link Info (Possibly Disabled) ================${NC}"
    print_devices "${noinfo_devs[@]}"
fi
