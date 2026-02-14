#!/usr/bin/env bash

# --- Environment Setup ---
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
LID_PATH="/proc/acpi/button/lid/LID0/state"

# 1. IMMEDIATE ACTION: LOCK THE SESSION
# We do this first so that if the script logic fails later, 
# the desktop is already secured.
loginctl lock-session
echo "$(date '+%Y-%m-%d %H:%M:%S') - [SECURITY] Session lock signal sent." >> "$LOGFILE"

# 2. STOP VISUALS
# Kill the screensaver loop and any active animation processes
pkill -9 -f "randscreensavers.sh"
pkill -9 -f "screensaver-"
echo "$(date '+%Y-%m-%d %H:%M:%S') - [CLEANUP] Screensaver processes terminated." >> "$LOGFILE"

# --- Hardware & Environment Detection ---

# Auto-detect AMD GPU brightness device
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

# Function to check lid state
get_lid_state() {
    if [ -f "$LID_PATH" ]; then
        awk '{print $2}' < "$LID_PATH"
    else
        echo "unknown"
    fi
}

# Check for external displays (HDMI)
HDMI_DISPLAY=$(xrandr --display :0 | grep ' connected' | grep 'HDMI' | awk '{print $1}')

# 3. PROACTIVE BRIGHTNESS RESTORATION
# We restore brightness only if the lid is open OR if an HDMI is connected 
# (clamshell mode).
LID_STATE=$(get_lid_state)

if [[ "$LID_STATE" == "open" || -n "$HDMI_DISPLAY" ]]; then
    if [ -n "$BRIGHT_DEVICE" ]; then
        # Restore to a comfortable 90%
        brightnessctl --device="$BRIGHT_DEVICE" set 90%
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [HARDWARE] Brightness restored to 90%." >> "$LOGFILE"
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [IDLE] System active but lid closed; brightness kept at 0%." >> "$LOGFILE"
fi

exit 0
