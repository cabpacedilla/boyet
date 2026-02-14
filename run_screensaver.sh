#!/usr/bin/env bash

# --- Environment & Paths ---
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
LOGFILE="$HOME/scriptlogs/secure_screensaver.log"
IDLE_STATUS_FILE="/tmp/rocky_idle_status"
SCREENSAVER_DIR="$HOME/Documents/screensavers"
UNPLAYED_LIST="$HOME/scriptlogs/unplayed_screensavers.txt"
PLAYED_LIST="$HOME/scriptlogs/played_screensavers.txt"

# --- Initialization ---
mkdir -p "$HOME/scriptlogs"
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
SCRIPT_PATH=$(realpath "$0")

# --- Functions ---

# Shuffle Deck Algorithm: Ensures every screensaver plays once before repeating
refresh_lists() {
    if [ ! -s "$UNPLAYED_LIST" ]; then
        echo "$(date) - [ALGO] Deck empty. Re-shuffling all screensavers." >> "$LOGFILE"
        find "$SCREENSAVER_DIR" -maxdepth 1 -type f -name "screensaver-*" -executable -printf "%f\n" | shuf > "$UNPLAYED_LIST"
        > "$PLAYED_LIST"
    fi
}

# The Security Lock
lock_system() {
    echo "$(date) - [SECURITY] Locking session via loginctl" >> "$LOGFILE"
    loginctl lock-session
}

# The Screensaver Loop
start_visuals() {
    echo "idle" > "$IDLE_STATUS_FILE"
    
    while [ "$(< "$IDLE_STATUS_FILE")" == "idle" ]; do
        refresh_lists
        
        # Pick the top screensaver
        SELECTED_NAME=$(head -n 1 "$UNPLAYED_LIST")
        [ -z "$SELECTED_NAME" ] && break
        
        # Move it to the "Played" deck
        sed -i '1d' "$UNPLAYED_LIST"
        echo "$SELECTED_NAME" >> "$PLAYED_LIST"
        
        # Run in background
        "$SCREENSAVER_DIR/$SELECTED_NAME" &
        SAVER_PID=$!
        
        # RANDOM PLAY LENGTH (10-30 seconds)
        PLAY_TIME=$(shuf -i 10-30 -n 1)
        for (( i=0; i<$PLAY_TIME; i++ )); do
            # Check every second: If status is no longer 'idle', stop immediately
            if [ "$(< "$IDLE_STATUS_FILE")" != "idle" ]; then 
                kill $SAVER_PID 2>/dev/null
                break 2 
            fi
            sleep 1
        done
        
        kill $SAVER_PID 2>/dev/null
    done
}

# The Resume Handler (Input Detected)
handle_resume() {
    echo "active" > "$IDLE_STATUS_FILE"
    
    # 1. LOCK FIRST (Security Best Practice)
    lock_system
    
    # 2. Kill all screensaver processes
    pkill -9 -f "screensaver-"
    
    # 3. Restore Brightness
    if [ -n "$BRIGHT_DEVICE" ]; then
        brightnessctl -d "$BRIGHT_DEVICE" set 100%
    fi
    echo "$(date) - [RESUME] System active and locked." >> "$LOGFILE"
}

# --- Main Execution Router ---

if [[ "$1" == "--idle" ]]; then
    # Check for media (audio) playing before starting
    if ! pactl list sink-inputs | grep -q "sink-input"; then
        echo "$(date) - [IDLE] Starting screensaver sequence" >> "$LOGFILE"
        [ -n "$BRIGHT_DEVICE" ] && brightnessctl -d "$BRIGHT_DEVICE" set 0%
        start_visuals
    else
        echo "$(date) - [IDLE] Media detected, skipping screensaver" >> "$LOGFILE"
    fi

elif [[ "$1" == "--resume" ]]; then
    handle_resume

else
    # DAEMON MODE: This runs when you start the script manually
    pkill swayidle 2>/dev/null
    
    echo "$(date) - [START] Launching swayidle daemon manager" >> "$LOGFILE"
    
    # swayidle calls THIS script with the flags when events occur
    swayidle -w \
        timeout 60 "$SCRIPT_PATH --idle" \
        resume "$SCRIPT_PATH --resume" &
        
    echo "Swayidle manager is now running in the background."
    echo "Log: $LOGFILE"
fi
