#!/usr/bin/env bash
# hot_parts.sh - Detect hot components inside the computer (CPU, GPU, thermal zones)
# Author: Claive Alvin P. Acedilla (modified with ChatGPT help)

while true; do

THRESHOLD=75   # Warning temperature in Celsius
NOTIFY=true    # Set to false if you don't want desktop notifications

print_alert() {
    local part=$1
    local temp=$2
    echo "🔥 Hot: $part — ${temp}°C"
    if $NOTIFY; then
        notify-send "🔥 Overheating Alert" "$part is at ${temp}°C"
    fi
}

check_cpu() {
    if command -v sensors >/dev/null 2>&1; then
        sensors | awk -v threshold="$THRESHOLD" '
        /:/ {
            for (i=1;i<=NF;i++) {
                if ($i ~ /\+[0-9]+\.[0-9]+°C/) {
                    gsub(/[+°C]/,"",$i)
                    temp=$i
                    part=$1
                    if (temp > threshold) {
                        printf "%s %s\n", part, temp
                    }
                }
            }
        }' | while read -r part temp; do
            print_alert "CPU ($part)" "$temp"
        done
    fi
}

check_amd_gpu() {
    for hwmon in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do
        if [[ -f "$hwmon" ]]; then
            temp=$(( $(cat "$hwmon") / 1000 ))
            if (( temp > THRESHOLD )); then
                print_alert "AMD GPU" "$temp"
            fi
        fi
    done
}

check_nvidia_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)
        if [[ -n "$temp" && "$temp" -gt "$THRESHOLD" ]]; then
            print_alert "NVIDIA GPU" "$temp"
        fi
    fi
}

check_thermal_zones() {
    for t in /sys/class/thermal/thermal_zone*/temp; do
        [[ -f "$t" ]] || continue
        name=$(cat "$(dirname "$t")/type")
        temp=$(( $(cat "$t") / 1000 ))
        if (( temp > THRESHOLD )); then
            print_alert "$name" "$temp"
        fi
    done
}

echo "🔎 Checking system temperatures..."
check_cpu
check_amd_gpu
check_nvidia_gpu
check_thermal_zones
echo "✅ Done."

done
