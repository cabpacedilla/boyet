#!/usr/bin/bash
# This script runs randomly selected rss-glx programs every minute.

LOGFILE="$HOME/scriptlogs/idle_log.txt"
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl1/brightness
MINIMAL=0
OPTIMAL=49961

# --- UPDATED LOCATION FOR SCREENSAVER LISTS ---
# File to store the list of screensavers that have NOT yet been played in the current cycle
UNPLAYED_LIST="$HOME/scriptlogs/unplayed_screensavers.txt"
# File to store the list of screensavers that HAVE been played in the current cycle
PLAYED_LIST="$HOME/scriptlogs/played_screensavers.txt"
# --- END UPDATED LOCATION ---

# Directory containing all screensaver programs
SCREENSAVER_DIR="$HOME/Documents/screensavers"

# Ensure the log directory exists (this also covers the new list files)
mkdir -p "$HOME/scriptlogs"


# Function to check if a media player is running
is_media_playing() {
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    if [ -n "$MEDIA_PLAY" ]; then
        return 0 # Media is playing
    else
        return 1 # Media is not playing
    fi
}

# Function to initialize or refresh the unplayed list
initialize_screensaver_lists() {
    # If the unplayed list doesn't exist or is empty, or if played list is missing,
    # re-populate unplayed list with all screensavers and clear played list.
    if [ ! -f "$UNPLAYED_LIST" ] || [ ! -s "$UNPLAYED_LIST" ] || [ ! -f "$PLAYED_LIST" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Initializing/Resetting screensaver play order." >> "$LOGFILE"
        find "$SCREENSAVER_DIR" -maxdepth 1 -type f -name "screensaver-*" -perm /u+x -print0 | shuf -z | xargs -0 -n 1 basename > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST" # Clear the played list
    fi
}

# --- Main Script Logic ---

# Perform initial list check/setup on every run
initialize_screensaver_lists

if ! is_media_playing; then
    # Kill the previous screensaver if it is running
    pkill -9 -f screensaver- # Force Kill the screensaver

    brightnessctl --device=amdgpu_bl0 set 0%
    sleep 0.1

    # Read the available screensavers from the unplayed list
    mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
    NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}

    if [ "$NUM_UNPLAYED" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - All screensavers played in this cycle. Resetting cycle." >> "$LOGFILE"
        # Move all screensavers from played to unplayed, then shuffle
        cat "$PLAYED_LIST" | shuf > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST" # Clear the played list
        mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
        NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}
        if [ "$NUM_UNPLAYED" -eq 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: No screensavers found in $SCREENSAVER_DIR after reset. Aborting." >> "$LOGFILE"
            exit 1
        fi
    fi

    # Select a random screensaver from the unplayed list
    RANDOM_INDEX=$(( RANDOM % NUM_UNPLAYED ))
    SELECTED_BASENAME="${UNPLAYED_SCREENSAVERS[RANDOM_INDEX]}"
    RANDOM_PROGRAM="$SCREENSAVER_DIR/$SELECTED_BASENAME"

    # Remove the selected screensaver from UNPLAYED_LIST and add to PLAYED_LIST
    # Using sed to remove the line from UNPLAYED_LIST
    RANDOM_INDEX_PLUS_1=$((RANDOM_INDEX + 1)) # Calculate for sed's 1-based indexing
    sed -i "${RANDOM_INDEX_PLUS_1}d" "$UNPLAYED_LIST"
    echo "$SELECTED_BASENAME" >> "$PLAYED_LIST"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_PROGRAM (Remaining unplayed: $((NUM_UNPLAYED - 1)))" >> "$LOGFILE"

    # Run the screensaver
    "$RANDOM_PROGRAM" &
    sleep 0.5
    brightnessctl --device=amdgpu_bl1 set 90%

else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Media player is running, skipping screensaver" >> "$LOGFILE"
    # If media is playing, ensure brightness is optimal and no screensaver is running
#     echo $OPTIMAL | sudo tee $BRIGHT_PATH
#     pkill -9 -f screensaver- # Force Kill any running screensaver
fi
