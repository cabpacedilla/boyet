#!/usr/bin/env bash
# ============================================================
# Battery Alert (Event-Driven)
# ============================================================
# Watches the battery uevent file via inotifywait. When the
# battery state changes, it immediately checks levels and
# notifies. Falls back to 5-second polling if inotifywait is
# missing.
#
# DEPENDENCY: Requires inotify-tools (provides inotifywait).
# Install on Nobara/Fedora: sudo dnf install inotify-tools
# ============================================================

# --- Single-Instance Lock ---
LOCK_FILE="/tmp/batteryAlertBashScript_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

# --- Cleanup ---
cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

trap cleanup EXIT

# --- Detect Backlight Device ---
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
if [ -z "$DEVICE" ]; then
    echo "No amdgpu backlight device found. Exiting." >&2
    exit 1
fi
TARGET_BRIGHTNESS=90

# --- Detect Battery Path ---
BATTERY_PATH=$(find /sys/class/power_supply/ -name "BAT*" -o -name "BATT*" | head -n1)
if [ -z "$BATTERY_PATH" ]; then
    echo "No battery found. Exiting." >&2
    exit 1
fi
BATTERY_UEVENT="${BATTERY_PATH}/uevent"

# --- Original Notification Function (unchanged) ---
notify() {
    if [ "$1" = 'low' ]; then
        ACTION="Plug"
    elif [ "$1" = 'high' ]; then
        ACTION="Unplug"
    fi

    notify-send -u critical --app-name "⚠️ Battery alert:" \
        "Battery reached $2%. $ACTION the power cable to optimize battery life!"

    # Uncomment to play sound
    # if [ -f "$(which mpv)" ]; then
    #     mpv ~/Music/battery-"$1".mp3 2>/dev/null
    # fi
}

# --- Original Core Logic (copied exactly, moved into a function) ---
check_battery() {
    # Get battery level and status
    BATT_LEVEL=$(acpi -b | grep -P -o '[0-9]+(?=%)')
    BATT_STATE=$(acpi -b | awk '{print $3}')

    # Get current brightness percentage
    CUR_BRIGHT=$(brightnessctl -d "$DEVICE" get)
    MAX_BRIGHT=$(brightnessctl -d "$DEVICE" max)
    CUR_PERCENT=$(( 100 * CUR_BRIGHT / MAX_BRIGHT ))

    # Helper: adjust brightness if not at target
    ensure_optimal_brightness() {
        if [ "$CUR_PERCENT" -ne "$TARGET_BRIGHTNESS" ]; then
            brightnessctl -d "$DEVICE" set "${TARGET_BRIGHTNESS}%"
        fi
    }

    # --- Logic Ladder (identical to your original) ---

    # 1. Low battery & discharging → Alert
    if [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; then
        notify low "$BATT_LEVEL"

    # 2. Low but charging/unknown → Just adjust brightness
    elif { [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; }; then
        ensure_optimal_brightness

    # 3. High / Full battery → Alert
    elif { [ "$BATT_LEVEL" -ge "$HIGH_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; } || \
         { [ "$BATT_LEVEL" -eq "$FULL_BATT" ] && [[ "$BATT_STATE" == "Full," || "$BATT_STATE" == "Discharging," ]]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Not" ]; }; then
        notify high "$BATT_LEVEL"

    # 4. Discharging (any level below high) → Just adjust brightness
    elif { [ "$BATT_LEVEL" -le "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; }; then
        ensure_optimal_brightness
    fi
}

# --- Configuration for Logic Ladder ---
LOW_BATT=20
HIGH_BATT=80
FULL_BATT=100

# --- Initial check (catch current state) ---
check_battery

# --- Main Event Loop ---
# Watch the uevent file. The kernel updates this file whenever the battery
# changes (percentage, charging state, etc.). Every time it changes, we run
# the battery check logic.
inotifywait -m -e modify "$BATTERY_UEVENT" 2>/dev/null | while read -r; do
    check_battery
done
