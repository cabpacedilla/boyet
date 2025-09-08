#!/usr/bin/env bash
# hot_parts.sh - Detect hot components (CPU, GPU, NVMe, Battery, ACPI zones)
# Author: Claive Alvin P. Acedilla (with ChatGPT refinements)
# Uses sysfs for temperature monitoring. No lm-sensors required.

LOGFILE="$HOME/scriptlogs/hot_parts.log"
mkdir -p "$(dirname "$LOGFILE")"

trap 'echo "$(date) - SIGTERM received, exiting..." >> "$LOGFILE"; exit 0' TERM
trap 'echo "$(date) - SIGINT received, exiting..." >> "$LOGFILE"; exit 0' INT

NOTIFY=true    # Enable desktop notifications

# Get safe threshold depending on sensor name
get_threshold() {
    case "$1" in
        *cpu*|*k10temp*|*amdgpu*) echo 95 ;;   # CPU/GPU critical
        *nvme*)                   echo 75 ;;   # NVMe SSDs throttle earlier
        *BAT*|*bat*)              echo 50 ;;   # Batteries should stay cool
        *acpitz*|*pch*)           echo 95 ;;   # ACPI/Chipset zones
        *)                        echo 85 ;;   # Fallback
    esac
}

print_alert() {
    local part=$1
    local temp=$2
    echo "$(date) 🔥 Hot: $part — ${temp}°C" | tee -a "$LOGFILE"
    if $NOTIFY; then
        notify-send -u critical "🔥 Overheating Alert" "$part is at ${temp}°C" 2>>"$LOGFILE" || \
            echo "$(date) ⚠️ notify-send failed" >> "$LOGFILE" &
    fi
}

# Detect and monitor all hwmon devices
check_hwmon() {
    for dir in /sys/class/hwmon/hwmon*; do
        [[ -d "$dir" ]] || continue
        name=$(<"$dir/name")

        for tfile in "$dir"/temp*_input; do
            [[ -f "$tfile" ]] || continue
            temp=$(( $(cat "$tfile") / 1000 ))
            threshold=$(get_threshold "$name")

            if (( temp > threshold )); then
                label="${name}"
                # If a label file exists (temp1_label, temp2_label, etc.), use it
                lfile="${tfile%_*}_label"
                [[ -f "$lfile" ]] && label="$name ($(cat "$lfile"))"

                print_alert "$label" "$temp"
            fi
        done
    done
}

while true; do
    echo "$(date) 🔎 Checking system temperatures..." >> "$LOGFILE"
    check_hwmon
    echo "$(date) ✅ Done." >> "$LOGFILE"
    sleep 5
done
