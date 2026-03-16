#!/usr/bin/env bash
# This script runs randomly selected rss-glx programs every minute.

LOGFILE="$HOME/scriptlogs/idle_log.txt"
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl1/brightness

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOGFILE")"

# Log rotation function
rotate_log() {
    if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="${LOGFILE}.${TIMESTAMP}.old"
        mv "$LOGFILE" "$BACKUP_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - LOG ROTATED: Previous log moved to $(basename "$BACKUP_FILE")" >> "$LOGFILE"

        # Clean up old logs (keep only MAX_OLD_LOGS)
        ls -t "${LOGFILE}".*.old 2>/dev/null | tail -n +$(($MAX_OLD_LOGS + 1)) | xargs rm -f --
    fi
}


# Function to check if a media player is running
is_media_playing() {
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    if [ -n "$MEDIA_PLAY" ]; then
        return 0
    else
        return 1
    fi
}

if ! is_media_playing; then
        # Kill the previous screensaver if it is running
        pkill -9 -f screensaver- # Force Kill the screensaver

        brightnessctl --device=amdgpu_bl1 set 0% &
        sleep 0.1

        SCREENSAVER_PROGRAMS=(~/Documents/screensaver-*)
        RANDOM_PROGRAM=${SCREENSAVER_PROGRAMS[RANDOM % ${#SCREENSAVER_PROGRAMS[@]}]}
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_PROGRAM" >> "$LOGFILE"

        # Run the screensaver
         "$RANDOM_PROGRAM" &
         sleep 0.5
         brightnessctl --device=amdgpu_bl1 set 90%
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Media player is running, skipping screensaver" >> "$LOGFILE"
fi
