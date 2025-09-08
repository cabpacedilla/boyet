#!/usr/bin/bash
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
LID_PATH="/proc/acpi/button/lid/LID0/state"
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl1/brightness
OPTIMAL_BRIGHTNESS=56206

echo "$(date +%Y-%m-%d\ %H:%M:%S) - System is active again" >> $LOGFILE

# Function to get the lid state
get_lid_state() {
    local LID_STATE
    if [ -f "$LID_PATH" ]; then
        LID_STATE=$(awk '{print $2}' < "$LID_PATH")
    fi
    echo "$LID_STATE"
}

is_media_playing() {
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    if [ -n "$MEDIA_PLAY" ]; then
        return 0
    else
        return 1
    fi
}

if ! is_media_playing && [ "$(get_lid_state)" == "open" ]; then
    # Kill any running screensaver programs
    pkill -9 -f "/home/claiveapa/Documents/bin/rand_screensavers.sh"  # Force Kill the loop!
    pkill -9 -f screensaver- # Force Kill the screensaver
    qdbus org.kde.screensaver /ScreenSaver Lock
    brightnessctl --device=amdgpu_bl1 set 90%
else
    :
fi

