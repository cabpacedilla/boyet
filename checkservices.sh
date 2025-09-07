#!/usr/bin/bash
# Multi-script monitor: ensures scripts in SCRIPTS array are running, kills extras, and notifies

SCRIPTS=(
    "autosync"
    "autobrightness"
    "backlisten"
    "batteryAlertBashScript"
    "battery_usage"
    "btrfs_balance_quarterly"
    "btrfs_scrub_monthly"
    "fortune4you"
    "hot_parts"
    "keyLocked"
    "laptopLid_close"
    "login_monitor"
    "lowMemAlert"
    "runscreensaver"
    "security_check"
    "weather_alarm"
)

COOLDOWN=2  # seconds between checks
MIN_INSTANCES=1

while true; do
    for SCRIPT_NAME in "${SCRIPTS[@]}"; do
        SCRIPT_PATH="$HOME/Documents/bin/${SCRIPT_NAME}.sh"

        # Skip if script not found
        if [ ! -x "$SCRIPT_PATH" ]; then
            notify-send --app-name "Check services" "$SCRIPT_NAME script not found or not executable!"
            continue
        fi

        # Get all PIDs of this script
        PROCS=($(pgrep -f "${SCRIPT_NAME}.sh"))
        NUM_RUNNING=${#PROCS[@]}

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            # Kill extra instances, leave only one
            for i in $(seq 0 $((NUM_RUNNING - 2))); do
                kill "${PROCS[$i]}"
                notify-send -t 10000 --app-name "Check services" "Extra $SCRIPT_NAME instance killed: PID ${PROCS[$i]}"
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            # Start the script if not running
            "$SCRIPT_PATH" &
            notify-send -t 10000 --app-name "Check services" "$SCRIPT_NAME started."
        fi
    done

    sleep "$COOLDOWN"
done
