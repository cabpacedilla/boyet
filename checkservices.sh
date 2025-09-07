#!/usr/bin/bash
# Multi-script monitor: ensures scripts in SCRIPTS array are running,
# kills extras, and notifies if missing.

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

COOLDOWN=2   # seconds between checks
MIN_INSTANCES=1

while true; do
    for SCRIPT_BASENAME in "${SCRIPTS[@]}"; do
        SCRIPT_NAME="${SCRIPT_BASENAME}.sh"
        SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"

        # Skip if not found
        if [ ! -x "$SCRIPT_PATH" ]; then
            notify-send --app-name "CheckServices" "$SCRIPT_NAME not found or not executable!" &
            continue
        fi

        # Detect running processes by name (handles both ./script.sh and bash script.sh)
        PROCS=($(pgrep -f "$SCRIPT_NAME"))
        NUM_RUNNING=${#PROCS[@]}

        echo "DEBUG: Checking $SCRIPT_NAME → PIDs: ${PROCS[*]:-none}"

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            # Kill extra instances, keep the newest
            for i in $(seq 0 $((NUM_RUNNING - MIN_INSTANCES - 1))); do
                kill "${PROCS[$i]}"
                notify-send -t 5000 --app-name "CheckServices" \
                    "Extra $SCRIPT_NAME killed: PID ${PROCS[$i]}" &
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            "$SCRIPT_PATH" &
            notify-send -t 5000 --app-name "CheckServices" "$SCRIPT_NAME started."
        fi
    done

    sleep "$COOLDOWN"
done
