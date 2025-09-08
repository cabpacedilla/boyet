#!/usr/bin/bash
# This script will check if a process is running. If the process is not running, it will run the process.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# December 2020

declare -a SCRIPTS=(
    "autosync.sh"
    "autobrightness.sh"
    "backlisten.sh"
    "batteryAlertBashScript.sh"
    "battery_usage.sh"
    "btrfs_balance_quarterly.sh"
    "btrfs_scrub_monthly.sh"
    "fortune4you.sh"
    "keyLocked.sh"
    "laptopLid_close.sh"
    "lowMemAlert.sh"
    "runscreensaver.sh"
    "weather_alarm.sh"
)

MIN_ID=1
NO_ID=0

while true; do
    SCRIPTS_CTR=0

    while [ "$SCRIPTS_CTR" -lt "${#SCRIPTS[@]}" ] ; do
        SCRIPT_NAME="${SCRIPTS[$SCRIPTS_CTR]}"
        SCRIPT_FULL_PATH="/home/claiveapa/Documents/bin/${SCRIPT_NAME}"

        # --- Using ONLY pidof -x ---
        # 1. Get all PIDs of processes executing the target script.
        #    pidof -x takes the full path of the script.
        PROCS_RAW=$(pidof -x "$SCRIPT_FULL_PATH")

        # 2. Filter out the current script's own PID ($$) from the list.
        #    This is essential if checkService.sh itself is in the SCRIPTS array
        #    or if you're paranoid about other edge cases.
        FILTERED_PIDS=""
        for pid in $PROCS_RAW; do
            if [ "$pid" -ne "$$" ]; then
                FILTERED_PIDS="$FILTERED_PIDS $pid"
            fi
        done

        # 3. Count the remaining (filtered) PIDs for the 'IDS' variable.
        #    awk 'NF' counts the number of space-separated fields (PIDs)
        IDS=$(echo "$FILTERED_PIDS" | awk 'NF')

        # 4. 'PROCS' is now simply the 'FILTERED_PIDS' list
        PROCS="$FILTERED_PIDS"

        # --- Debugging output (remove or comment out in production) ---
        # echo "Checking script: $SCRIPT_NAME"
        # echo "Full script path: $SCRIPT_FULL_PATH"
        # echo "Current script PID: $$"
        # echo "PIDs_RAW (from pidof -x before self-exclusion): $PROCS_RAW"
        # echo "FILTERED_PIDS (after self-exclusion): $FILTERED_PIDS"
        # echo "IDS (count of other instances): $IDS"
        # echo "PROCS (PIDs for killing): $PROCS"
        # echo "---"

        # If number of processes is more than 1 (i.e., duplicates exist beyond the one allowed)
        if [ "$IDS" -gt "$MIN_ID" ]; then
            declare -a SCRIPTSARR=($PROCS) # Create array from space-separated PIDs

            # Calculate how many to kill
            kill_count=$((IDS - MIN_ID))
            killed_this_loop=0

            # Kill excess instances (from the beginning of the list)
            while [ "$killed_this_loop" -lt "$kill_count" ] && [ "$killed_this_loop" -lt "${#SCRIPTSARR[@]}" ]; do
                echo "Killing excess instance: ${SCRIPTSARR[$killed_this_loop]} for $SCRIPT_NAME"
                kill "${SCRIPTSARR[$killed_this_loop]}" # Use default SIGTERM (15) for graceful termination
                notify-send --app-name "Check services:" "$SCRIPT_NAME: Excess instance killed (PID ${SCRIPTSARR[$killed_this_loop]})."
                killed_this_loop=$((killed_this_loop + 1))
            done

        # If no instances are running (excluding self)
        elif [ "$IDS" -eq "$NO_ID" ]; then
            notify-send --app-name "Check services:" "$SCRIPT_NAME is not running. Attempting to start..."
            if [ -x "$SCRIPT_FULL_PATH" ]; then
                # Start the script in the background using nohup for robustness
                nohup "$SCRIPT_FULL_PATH" &
                notify-send --app-name "Check services:" "$SCRIPT_NAME started successfully."
            else
                notify-send --app-name "Check services:" "Error: $SCRIPT_FULL_PATH is not executable or not found!"
            fi
        else
            # IDS is equal to MIN_ID (1), so exactly one instance is running (excluding self)
            : # Do nothing, everything is good
        fi

        SCRIPTS_CTR=$((SCRIPTS_CTR + 1))
    done

    sleep 1s
done
