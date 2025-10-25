#!/usr/bin/env bash

SCRIPT_NAME="runscreensaver.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1

# Function to check if media is playing
is_media_playing() {
    pactl list sink-inputs | grep -B1 "Mute: no" | grep -c "Corked: no"
}

# Main loop
while true; do
	if [[ "$MEDIA_PLAY" -eq 0  ]]; then
		PROCS=$(pgrep -f "bash $SCRIPT_PATH$")
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
			sleep 5
		fi
	else
		:
	fi
    sleep 0.1
done
