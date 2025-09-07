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

        # Detect running processes by full path
        PROCS=($(pgrep -f "bash $SCRIPT_PATH"))
        NUM_RUNNING=${#PROCS[@]}

        echo "DEBUG: Checking $SCRIPT_NAME → PIDs: ${PROCS[*]:-none}"

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            # Kill older ones, keep the newest
            PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -$MIN_INSTANCES)
            for pid in $PIDS_TO_KILL; do
                kill "$pid"
                notify-send -t 5000 --app-name "CheckServices" "Extra $SCRIPT_NAME killed: PID $pid" &
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            "$SCRIPT_PATH" &
            notify-send -t 5000 --app-name "CheckServices" "$SCRIPT_NAME started."
        fi
    done

    sleep "$COOLDOWN"
done
