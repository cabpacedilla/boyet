#!/usr/bin/bash
# This script runs randomly selected screensaver- programs every 15 seconds.

LOGFILE="$HOME/scriptlogs/idle_log.txt"

# Trap signals from outside (resume handler, active state, etc.)
trap cleanup INT TERM

# Handle case where brightness device is not found
if [ -z "$BRIGHT_DEVICE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - No amdgpu_bl* brightness device found. Brightness control will be skipped." >> "$LOGFILE"
fi

# --- Paths for screensaver tracking ---
UNPLAYED_LIST="$HOME/scriptlogs/unplayed_screensavers.txt"
PLAYED_LIST="$HOME/scriptlogs/played_screensavers.txt"
SCREENSAVER_DIR="$HOME/Documents/screensavers"

# Ensure scriptlogs directory exists
mkdir -p "$HOME/scriptlogs"

# Function: initialize screensaver lists
initialize_screensaver_lists() {
    if [ ! -f "$UNPLAYED_LIST" ] || [ ! -s "$UNPLAYED_LIST" ] || [ ! -f "$PLAYED_LIST" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Initializing/Resetting screensaver play order." >> "$LOGFILE"
        find "$SCREENSAVER_DIR" -maxdepth 1 -type f -name "screensaver-*" -perm /u+x -print0 | shuf -z | xargs -0 -n 1 basename > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST"
    fi
}

# Main logic
initialize_screensaver_lists

# Load screensavers into an array
mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}

if [ "$NUM_UNPLAYED" -eq 0 ]; then
	echo "$(date '+%Y-%m-%d %H:%M:%S') - All screensavers played. Resetting list." >> "$LOGFILE"
	shuf "$PLAYED_LIST" > "$UNPLAYED_LIST"
	echo "" > "$PLAYED_LIST"
	mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
	NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}
	if [ "$NUM_UNPLAYED" -eq 0 ]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: No screensavers found in $SCREENSAVER_DIR" >> "$LOGFILE"
		exit 1
	fi
fi

# Select random screensaver
RANDOM_INDEX=$(( RANDOM % NUM_UNPLAYED ))
SELECTED_BASENAME="${UNPLAYED_SCREENSAVERS[RANDOM_INDEX]}"
RANDOM_SCREENSAVER="$SCREENSAVER_DIR/$SELECTED_BASENAME"

# Update lists
sed -i "$((RANDOM_INDEX + 1))d" "$UNPLAYED_LIST"
echo "$SELECTED_BASENAME" >> "$PLAYED_LIST"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_SCREENSAVER (Remaining: $((NUM_UNPLAYED - 1)))" >> "$LOGFILE"

"$RANDOM_SCREENSAVER" 

 # 3. Handle the Overlap:
# pgrep -c counts how many screensavers are currently running.
current_count=$(pgrep -c -f "screensaver-")

if [ "$current_count" -gt 1 ]; then
	# If more than one is running, kill the OLDEST instance only (-o)
	pkill -o -f "screensaver-" 2>/dev/null
	echo "$(date) - Transition complete: New screensaver active, old one killed." >> "$LOGFILE"
else
	# On the very first run, we don't kill anything.
	echo "$(date) - First run: Initial screensaver started." >> "$LOGFILE"
fi

