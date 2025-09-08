#!/usr/bin/env bash
# hot_parts.sh - Detect hot components (CPU, GPU, NVMe, Battery, ACPI zones)
# Author: Claive Alvin P. Acedilla (with ChatGPT refinements)
# Uses sysfs for temperature monitoring. No lm-sensors required.

LOGFILE="$HOME/scriptlogs/hot_parts.log"
mkdir -p "$(dirname "$LOGFILE")"

trap 'echo "$(date) - SIGTERM received, exiting..." >> "$LOGFILE"; exit 0' TERM
trap 'echo "$(date) - SIGINT received, exiting..." >> "$LOGFILE"; exit 0' INT

THRESHOLD=95   # Default warning temperature in °C
NOTIFY=true    # Enable desktop notifications

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

            if (( temp > THRESHOLD )); then
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
