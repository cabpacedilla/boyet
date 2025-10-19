#!/usr/bin/env bash
# Multi-script monitor - SIMPLE and RELIABLE version

SCRIPTS=(
    "autosync" "autobrightness" "backlisten" "batteryAlertBashScript"
    "btrfs_balance_quarterly" "btrfs_scrub_monthly" "fortune4you"
    "keyLocked" "laptopLid_close" "login_monitor" "low_disk_space"
    "lowMemAlert" "power_usage" "runscreensaver" "security_check"
    "weather_alarm"
)

COOLDOWN=2
MIN_INSTANCES=1

while true; do
    for SCRIPT_BASENAME in "${SCRIPTS[@]}"; do
        SCRIPT_NAME="${SCRIPT_BASENAME}.sh"
        SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"

        [ ! -f "$SCRIPT_PATH" ] && continue

        # SIMPLE: Just count processes that contain the script path
        PROCS=($(pgrep -f "$SCRIPT_PATH"))
        NUM_RUNNING=${#PROCS[@]}

        echo "DEBUG: $SCRIPT_NAME → Running: $NUM_RUNNING, PIDs: ${PROCS[*]:-none}"

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -$MIN_INSTANCES)
            for pid in $PIDS_TO_KILL; do
                kill "$pid" 2>/dev/null
                echo "Killed extra $SCRIPT_NAME (PID: $pid)"
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            "$SCRIPT_PATH" &
            echo "Started $SCRIPT_NAME (PID: $!)"
        fi
    done

    sleep "$COOLDOWN"
done
