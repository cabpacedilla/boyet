#!/usr/bin/env bash

SCRIPT_NAME="runscreensaver.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1

# Function to check if media is playing
is_media_playing() {
	#MEDIA_PLAY=$(pacmd list-sink-inputs | grep -w "RUNNING" | awk '{ print $2 }')
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    echo "$MEDIA_PLAY"
}

# Main loop
while true; do
    if MEDIA_PLAY=$(is_media_playing); then
        if [[ -n "$MEDIA_PLAY" ]]; then
           :
        else
            PROCS=($(pgrep -f "bash.*$SCRIPT_NAME$" 2>/dev/null || true))
            NUM_RUNNING=$(echo "$PROCS" | wc -w)

             if [ "$NUM_RUNNING" -ge "$MIN_INSTANCES" ]; then
                # Kill older ones, keep the newest
                PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -$MIN_INSTANCES)
                for pid in $PIDS_TO_KILL; do
                    kill "$pid"
                    notify-send -t 5000 --app-name "💀 CheckServices" "Extra $SCRIPT_NAME killed: PID $pid" &
                done
            elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
                "$SCRIPT_PATH" &
                notify-send -t 5000 --app-name "✅ CheckServices" "$SCRIPT_NAME started."
            fi
        fi
    fi

    sleep 0.2s
done
