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
is_video_playing() {
    pactl list sink-inputs 2>/dev/null | awk -v RS="Sink Input #" '
    BEGIN { found = 0 }
    /Sink Input/ {next}
    {
        # Get application name
        app_name = "unknown"
        if (match($0, /application.name = "([^"]+)"/, arr)) {
            app_name = arr[1]
        } else if (match($0, /node.name = "([^"]+)"/, arr)) {
            app_name = arr[1]
        }
        
        # Check if this is a video app
        is_video_app = 0
        
        # Video players
        if (app_name ~ /dragonplayer/ || app_name == "dragonplayer" ||
            app_name ~ /[Vv]LC/ || app_name == "VLC" || app_name == "vlc" ||
            app_name ~ /celluloid/ || app_name == "celluloid" ||
            app_name ~ /totem/ || app_name == "totem") {
            is_video_app = 1
        }
        
        # Browsers
        if (app_name == "Vivaldi" || app_name == "Firefox" || 
            app_name == "Chromium" || app_name == "chrome") {
            is_video_app = 1
        }
        
        # If it'\''s a video app and not corked, consider it playing
        if (is_video_app && !/Corked: yes/ && !/pulse.corked = "true"/) {
            found = 1
        }
        
        # Also check for video role
        if (/media.role/ && (/video/ || /Video/ || /movie/ || /Movie/)) {
            found = 1
        }
    }
    END { exit found ? 0 : 1 }
    '
    return $?
}

# Main condition
MEDIA_STATUS=$(is_video_playing)
HDMI_DISPLAY=$(xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}')

if [[ ( -n "$MEDIA_STATUS" && "$(get_lid_state)" == "open" ) || \
	( -n "$HDMI_DISPLAY" && "$(get_lid_state)" == "closed" ) ]]; then

    # Kill screensavers and lock screen
    pkill -9 -f "/home/claiveapa/Documents/bin/rand_screensavers.sh" 2>/dev/null
    pkill -9 -f "screensaver-" 2>/dev/null

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
