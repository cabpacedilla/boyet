#!/usr/bin/bash
# This script runs randomly selected rss-glx programs every minute.

LOGFILE="$HOME/scriptlogs/idle_log.txt"
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl1/brightness
MINIMAL=0
OPTIMAL=39321


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

        echo $MINIMAL | sudo tee $BRIGHT_PATH &
        sleep 0.1

        SCREENSAVER_PROGRAMS=(~/screensavers/screensaver-*)
        RANDOM_PROGRAM=${SCREENSAVER_PROGRAMS[RANDOM % ${#SCREENSAVER_PROGRAMS[@]}]}
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Running $RANDOM_PROGRAM" >> "$LOGFILE"

        # Run the screensaver
         "$RANDOM_PROGRAM" &
         sleep 0.5
         echo $OPTIMAL | sudo tee $BRIGHT_PATH
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Media player is running, skipping screensaver" >> "$LOGFILE"
fi
