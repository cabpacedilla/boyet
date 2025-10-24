#!/usr/bin/env bash

SCRIPT_NAME="runscreensaver.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1

# Function to check if media is currently playing
is_media_playing() {
    pactl list | grep -qw "RUNNING"
}

# Real-time listener for playback changes
pactl subscribe | grep --line-buffered "sink" | while read -r event; do
    if is_media_playing; then
        echo "🎵 Media is playing, skipping screensaver..."
    else
        echo "💤 No media playing, checking screensaver process..."
        PROCS=$(pgrep -f "bash $SCRIPT_PATH$")
        NUM_RUNNING=$(echo "$PROCS" | wc -w)

        if [ "$NUM_RUNNING" -ge "$MIN_INSTANCES" ]; then
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
done
