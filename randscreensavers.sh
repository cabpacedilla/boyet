#!/usr/bin/bash
# This script runs randomly selected screensaver- programs every 15 seconds.

LOGFILE="$HOME/scriptlogs/idle_log.txt"
MINIMAL=0
OPTIMAL=49961

# Automatically detect AMD GPU backlight device (e.g. amdgpu_bl0 or amdgpu_bl1)
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

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

# Function: check if a media player is running
is_media_playing() {
    pactl list | grep -qw "RUNNING"
}

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

if ! is_media_playing; then
    pkill -9 -f screensaver-

    # Dim brightness before screensaver
    if [ -n "$BRIGHT_DEVICE" ]; then
        brightnessctl -d "$BRIGHT_DEVICE" set 0%
        sleep 0.1
    fi

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
    RANDOM_PROGRAM="$SCREENSAVER_DIR/$SELECTED_BASENAME"

    # Update lists
    sed -i "$((RANDOM_INDEX + 1))d" "$UNPLAYED_LIST"
    echo "$SELECTED_BASENAME" >> "$PLAYED_LIST"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_PROGRAM (Remaining: $((NUM_UNPLAYED - 1)))" >> "$LOGFILE"

    "$RANDOM_PROGRAM" &
    sleep 0.5

    # Restore brightness after starting screensaver
    if [ -n "$BRIGHT_DEVICE" ]; then
        brightnessctl -d "$BRIGHT_DEVICE" set 90%
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Media playing, skipping screensaver" >> "$LOGFILE"
    # Kill any leftover screensaver
    pkill -9 -f screensaver-

    # Optionally restore brightness if needed
    if [ -n "$BRIGHT_DEVICE" ]; then
        brightnessctl -d "$BRIGHT_DEVICE" set 90%
    fi
fi
