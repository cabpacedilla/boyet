#!/usr/bin/env bash
# Hybrid battery monitor: udevadm events + periodic polling
# Written by Claive Alvin P. Acedilla. Modified for hybrid monitoring.

LOCK_FILE="/tmp/batteryAlertBashScript_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
    # Kill background udevadm process if still running
    kill "$UDEV_PID" 2>/dev/null
}

trap cleanup EXIT

# ---------- Notification function (unchanged) ----------
notify() {
    if [ "$1" = 'low' ]; then
        ACTION="Plug"
    elif [ "$1" = 'high' ]; then
        ACTION="Unplug"
    fi
    notify-send -u critical --app-name "⚠️ Battery alert:" \
        "Battery reached $2%. $ACTION the power cable to optimize battery life!"
    # Uncomment sound if desired
}

# ---------- Configuration ----------
LOW_BATT=20
HIGH_BATT=80
FULL_BATT=100
TARGET_BRIGHTNESS=90

# Detect backlight device
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
if [ -z "$DEVICE" ]; then
    echo "No AMD GPU backlight device found. Exiting." >&2
    exit 1
fi

# ---------- Core battery-check function ----------
check_battery() {
    # Read battery level and status from acpi
    BATT_LEVEL=$(acpi -b | grep -P -o '[0-9]+(?=%)')
    BATT_STATE=$(acpi -b | awk '{print $3}')

    # Current brightness
    CUR_BRIGHT=$(brightnessctl -d "$DEVICE" get)
    MAX_BRIGHT=$(brightnessctl -d "$DEVICE" max)
    CUR_PERCENT=$(( 100 * CUR_BRIGHT / MAX_BRIGHT ))

    ensure_optimal_brightness() {
        if [ "$CUR_PERCENT" -ne "$TARGET_BRIGHTNESS" ]; then
            brightnessctl -d "$DEVICE" set "${TARGET_BRIGHTNESS}%"
        fi
    }

    # --- Logic ladder (same as original) ---
    if [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; then
        notify low "$BATT_LEVEL"
    elif { [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; }; then
        ensure_optimal_brightness
    elif { [ "$BATT_LEVEL" -ge "$HIGH_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; } || \
         { [ "$BATT_LEVEL" -eq "$FULL_BATT" ] && [[ "$BATT_STATE" == "Full," || "$BATT_STATE" == "Discharging," ]]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Not" ]; }; then
        notify high "$BATT_LEVEL"
    elif { [ "$BATT_LEVEL" -le "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; }; then
        ensure_optimal_brightness
    fi
}

# ---------- Start udevadm monitor in the background ----------
# It will call check_battery on every power-supply uevent
udevadm monitor -k -s power_supply -p 2>/dev/null | while read -r; do
    check_battery
done &
UDEV_PID=$!

# ---------- Main polling loop (runs every 60 seconds) ----------
# This catches gradual battery percentage changes
while true; do
    check_battery
    sleep 60
done
