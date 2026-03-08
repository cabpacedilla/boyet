#!/usr/bin/env bash
# This script alerts when battery level is low or high and adjusts brightness for battery optimization.
# Written by Claive Alvin P. Acedilla. Modified for dynamic brightnessctl use.

LOCK_FILE="/tmp/batteryAlertBashScript_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

notify()
{
   if [ "$1" = 'low' ]; then
        ACTION="Plug"
   elif [ "$1" = 'high' ]; then
        ACTION="Unplug"
   fi

   notify-send -u critical --app-name "⚠️ Battery alert:" "Battery reached $2%. $ACTION the power cable to optimize battery life!"

   # Uncomment to play sound
   # if [ -f "$(which mpv)" ]; then
   #     mpv ~/Music/battery-"$1".mp3 2>/dev/null
   # fi
}

# Detect amdgpu_bl* device dynamically
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
if [ -z "$DEVICE" ]; then
    echo "No AMD GPU backlight device found. Exiting."
    exit 1
fi

# Settings
LOW_BATT=20
HIGH_BATT=80
FULL_BATT=100
TARGET_BRIGHTNESS=90

while true; do

    # Get battery level and status
    BATT_LEVEL=$(acpi -b | grep -P -o '[0-9]+(?=%)')
    BATT_STATE=$(acpi -b | awk '{print $3}')

    # Get current brightness percentage
    CUR_BRIGHT=$(brightnessctl -d "$DEVICE" get)
    MAX_BRIGHT=$(brightnessctl -d "$DEVICE" max)
    CUR_PERCENT=$(( 100 * CUR_BRIGHT / MAX_BRIGHT ))

    # Function to adjust brightness if not 90%
    ensure_optimal_brightness() {
        if [ "$CUR_PERCENT" -ne "$TARGET_BRIGHTNESS" ]; then
            brightnessctl -d "$DEVICE" set "${TARGET_BRIGHTNESS}%"
        fi
    }

    # 1. Notify if battery is low and discharging
    if [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; then
        notify low "$BATT_LEVEL"

    # 2. If low but charging/unknown, adjust brightness
    elif { [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; }; then
        ensure_optimal_brightness

    # 3. Notify if battery is full or nearly full
    elif { [ "$BATT_LEVEL" -ge "$HIGH_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; } || \
         { [ "$BATT_LEVEL" -eq "$FULL_BATT" ] && [[ "$BATT_STATE" == "Full," || "$BATT_STATE" == "Discharging," ]]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Not" ]; }; then
        notify high "$BATT_LEVEL"

    # 4. If battery is discharging and < 80%, just adjust brightness
    elif { [ "$BATT_LEVEL" -le "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; }; then
        ensure_optimal_brightness
    fi

    sleep 5
done
