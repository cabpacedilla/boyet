#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# ============================================================================
# Runs a randomly selected screensaver from ~/Documents/screensaver/
# Tracks played/unplayed screensavers so each is used once per cycle.
# ============================================================================

LOGFILE="$HOME/scriptlogs/idle_log.txt"

# --- Cleanup on signal ---
cleanup_screensaver() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Signal received, stopping screensaver" >> "$LOGFILE"
    pkill -f "screensaver-" 2>/dev/null
    exit 0
}
trap cleanup_screensaver INT TERM

# --- Paths ---
UNPLAYED_LIST="$HOME/scriptlogs/unplayed_screensavers.txt"
PLAYED_LIST="$HOME/scriptlogs/played_screensavers.txt"
SCREENSAVER_DIR="$HOME/Documents/screensaver"

mkdir -p "$HOME/scriptlogs"

# --- Initialize play lists ---
initialize_screensaver_lists() {
    if [ ! -f "$UNPLAYED_LIST" ] || [ ! -s "$UNPLAYED_LIST" ] || [ ! -f "$PLAYED_LIST" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Initializing/Resetting screensaver play order." >> "$LOGFILE"
        find "$SCREENSAVER_DIR" -maxdepth 1 \
            \( -type f -o -type l \) \
            -name "screensaver-*" -perm /u+x -print0 \
            | shuf -z \
            | xargs -0 -n 1 basename > "$UNPLAYED_LIST"
        echo "" > "$PLAYED_LIST"
    fi
}

initialize_screensaver_lists

# --- Load unplayed screensavers ---
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

# --- Pick one at random ---
RANDOM_INDEX=$(( RANDOM % NUM_UNPLAYED ))
SELECTED_BASENAME="${UNPLAYED_SCREENSAVERS[RANDOM_INDEX]}"
RANDOM_SCREENSAVER="$SCREENSAVER_DIR/$SELECTED_BASENAME"

# --- Update lists ---
sed -i "$((RANDOM_INDEX + 1))d" "$UNPLAYED_LIST"
echo "$SELECTED_BASENAME" >> "$PLAYED_LIST"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_SCREENSAVER (Remaining: $((NUM_UNPLAYED - 1)))" >> "$LOGFILE"

"$RANDOM_SCREENSAVER"

# --- Overlap handling ---
current_count=$(pgrep -c -f "screensaver-")

if [ "$current_count" -gt 1 ]; then
    pkill -o -f "screensaver-" 2>/dev/null
    echo "$(date) - Transition complete: New screensaver active, old one killed." >> "$LOGFILE"
else
    echo "$(date) - First run: Initial screensaver started." >> "$LOGFILE"
fi
