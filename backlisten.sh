#!/usr/bin/env bash

SCRIPT_NAME="checkservices.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1
COOLDOWN=2   # seconds between checks

while true; do
    # Find all running processes for the script with bash
    PROCS=($(pgrep -f "bash $SCRIPT_PATH$"))
    NUM_RUNNING=$(echo "$PROCS" | wc -w)

    if [ "$NUM_RUNNING" -ge "$MIN_INSTANCES" ]; then
        # More than one instance? Kill extras and notify
        PROC_ARRAY=($PROCS)
        LAST_INDEX=$(( ${#PROC_ARRAY[@]} - 1 ))
        for i in $(seq 0 $((LAST_INDEX - 1))); do
            kill "${PROC_ARRAY[$i]}"
            notify-send -t 10000 --app-name "💀 Check services" "Extra checkservices instance killed: PID ${PROC_ARRAY[$i]}" &
        done
    else
        # Script not running, start it
        if [ -x "$SCRIPT_PATH" ]; then
            "$SCRIPT_PATH" &
            notify-send -t 10000 --app-name "✅ Check services" "checkservices started." &
            sleep 1
        else
            notify-send --app-name "⚠️ Check services" "checkservices script not found or not executable!" &
        fi
    fi

    sleep "$COOLDOWN"
done
