#!/usr/bin/bash
# This script runs randomly selected screensaver- programs every 15 seconds.

LOGFILE="$HOME/scriptlogs/idle_log.txt"

# Cleanup function to kill screensavers if interrupted
cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Interrupt received. Killing screensavers." >> "$LOGFILE"
    pkill -9 -f screensaver-
    exit 0
}
trap cleanup INT TERM

# --- Paths for screensaver tracking ---
UNPLAYED_LIST="$HOME/scriptlogs/unplayed_screensavers.txt"
PLAYED_LIST="$HOME/scriptlogs/played_screensavers.txt"
SCREENSAVER_DIR="$HOME/Documents/screensavers"

mkdir -p "$HOME/scriptlogs"

# IMPROVED: Check if hardware is actually outputting sound
is_media_playing() {
    pactl list sink-inputs | awk -v RS="" '/Corked: no/ && /Mute: no/ && !/speech-dispatcher/'
}

initialize_screensaver_lists() {
    if [ ! -f "$UNPLAYED_LIST" ] || [ ! -s "$UNPLAYED_LIST" ] || [ ! -f "$PLAYED_LIST" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Resetting screensaver play order." >> "$LOGFILE"
        find "$SCREENSAVER_DIR" -maxdepth 1 -type f -name "screensaver-*" -perm /u+x -print0 | shuf -z | xargs -0 -n 1 basename > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST"
    fi
}

initialize_screensaver_lists

# Logic: Only proceed if NO media is playing (ignoring paused apps like Elisa)
if ! is_media_playing; then
    # Kill previous screensaver before starting new one
    pkill -9 -f screensaver-
    
    mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
    NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}

    if [ "$NUM_UNPLAYED" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - All played. Resetting." >> "$LOGFILE"
        shuf "$PLAYED_LIST" > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST"
        mapfile -t UNPLAYED_SCREENSAVERS < "$UNPLAYED_LIST"
        NUM_UNPLAYED=${#UNPLAYED_SCREENSAVERS[@]}
    fi

    RANDOM_INDEX=$(( RANDOM % NUM_UNPLAYED ))
    SELECTED_BASENAME="${UNPLAYED_SCREENSAVERS[RANDOM_INDEX]}"
    RANDOM_SCREENSAVER="$SCREENSAVER_DIR/$SELECTED_BASENAME"

    sed -i "$((RANDOM_INDEX + 1))d" "$UNPLAYED_LIST"
    echo "$SELECTED_BASENAME" >> "$PLAYED_LIST"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $SELECTED_BASENAME" >> "$LOGFILE"

    # Start the screensaver in the background so the script can finish
    "$RANDOM_SCREENSAVER" & 
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Media playing (or unmuted), skipping." >> "$LOGFILE"
fi


