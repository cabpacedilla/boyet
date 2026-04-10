#!/usr/bin/env bash

LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
LID_PATH="/proc/acpi/button/lid/LID0/state"
IDLE_STATUS_FILE="/tmp/sway_idle_status"

# Auto-detect AMD GPU brightness device (amdgpu_bl0, bl1, etc.)
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

echo "active" > "$IDLE_STATUS_FILE"
echo "$(date +%Y-%m-%d\ %H:%M:%S) - System is active again" >> "$LOGFILE"

idle_status=$(<"$IDLE_STATUS_FILE")

# Function to get the lid state
get_lid_state() {
    if [ -f "$LID_PATH" ]; then
        awk '{print $2}' < "$LID_PATH"
    fi
}

# Main condition
HDMI_DISPLAY=$(xrandr | grep ' connected' | grep -i 'HDMI' | awk '{print $1}')

if [[ "$idle_status" == "active" ]]; then
    # FIXED: Properly call the function
    if [[ "$(get_lid_state)" == "open" ]] || \
       [[ -n "$HDMI_DISPLAY" && "$(get_lid_state)" == "closed" ]]; then

        echo "$(date +%Y-%m-%d\ %H:%M:%S) - Video playing or HDMI+closed lid, inhibiting screensaver" >> "$LOGFILE"

        # Kill screensavers
        pkill -9 -f "/home/claiveapa/Documents/bin/randscreensavers.sh"
        pkill -9 -f "screensaver-"

        # Restore brightness if device is found
        if [ -n "$BRIGHT_DEVICE" ]; then
            brightnessctl --device="$BRIGHT_DEVICE" set 90%
        else
            echo "$(date +%Y-%m-%d\ %H:%M:%S) - No amdgpu_bl* device found, skipping brightness restore." >> "$LOGFILE"
        fi

    else
        loginctl lock-session
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [SECURITY] Session lock signal sent (no video or lid condition not met)." >> "$LOGFILE"
    fi
fi
