#!/usr/bin/env bash

LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
LID_PATH="/proc/acpi/button/lid/LID0/state"

# Auto-detect AMD GPU brightness device (amdgpu_bl0, bl1, etc.)
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

echo "$(date +%Y-%m-%d\ %H:%M:%S) - System is active again" >> "$LOGFILE"

# Function to get the lid state
get_lid_state() {
    if [ -f "$LID_PATH" ]; then
        awk '{print $2}' < "$LID_PATH"
    fi
}

# Function to detect media playback
is_media_playing() {
    # We search for any sink-input where 'Corked: no' is present.
    # We exclude 'speech-dispatcher' if you don't want system beeps to block your screensaver.
    pactl list sink-inputs | awk -v RS="" '/Corked: no/ && /media.class = "Stream\/Output\/Audio"/ && !/elisa/ && /media.name/'
}

# Main condition
MEDIA_STATUS=$(is_media_playing)
HDMI_DISPLAY=$(xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}')

if [[ ( -n "$MEDIA_STATUS" && "$(get_lid_state)" == "open" ) || \
	( -n "$HDMI_DISPLAY" && "$(get_lid_state)" == "closed" ) ]]; then

    # Kill screensavers and lock screen
    pkill -9 -f "/home/claiveapa/Documents/bin/randscreensavers.sh"
    pkill -9 -f screensaver-

    # Restore brightness if device is found
    if [ -n "$BRIGHT_DEVICE" ]; then
        brightnessctl --device="$BRIGHT_DEVICE" set 90%
    else
        echo "$(date +%Y-%m-%d\ %H:%M:%S) - No amdgpu_bl* device found, skipping brightness restore." >> "$LOGFILE"
    fi
    
else
	loginctl lock-session
	echo "$(date '+%Y-%m-%d %H:%M:%S') - [SECURITY] Session lock signal sent." >> "$LOGFILE"
fi
