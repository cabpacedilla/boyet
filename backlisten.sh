#!/usr/bin/env bash

LOCK_FILE="/tmp/backlisten_$(whoami).lock"
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

SCRIPT_NAME="checkservices.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1
COOLDOWN=5   # seconds between checks

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
            "$SCRIPT_PATH" > /dev/null 2>&1 &
            notify-send -t 10000 --app-name "✅ Check services" "checkservices started." &
            sleep 5
        else
            notify-send --app-name "⚠️ Check services" "checkservices script not found or not executable!" &
        fi
    fi

    sleep "$COOLDOWN"
done
