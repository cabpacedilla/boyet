#!/usr/bin/bash
# This script will activate screen lock when the laptop lid is closed for auto lid-close security in IceWM.
# Written by Claive Alvin P. Acedilla. Updated for dynamic brightness device handling.

# ==================
# Prerequisites:
# - Install xscreensaver (optional, for screen locking)
# - Add this script to ~/.icewm/startup (as: lid_close.sh &)
# ==================

# Function to check if HDMI is connected
check_hdmi() {
    xrandr | grep -q 'HDMI-1 connected'
}

# Function to get the lid state
get_lid_state() {
    if [ -f /proc/acpi/button/lid/LID0/state ]; then
        awk '{print $2}' < /proc/acpi/button/lid/LID0/state
    fi
}

# Detect backlight device (e.g. amdgpu_bl0, amdgpu_bl1)
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
if [ -z "$DEVICE" ]; then
    echo "No AMD GPU backlight device found. Brightness control will be skipped."
fi

# Main loop
while true; do
    LID_STATE=$(get_lid_state)

    if [ "$LID_STATE" == "closed" ] && ! check_hdmi; then
        # Set brightness if device is detected
        if [ -n "$DEVICE" ]; then
            brightnessctl -d "$DEVICE" set 90%
        fi

        # Optional screen lock (uncomment if using xscreensaver)
        # xscreensaver-command --lock

        # Suspend the system
        systemctl suspend
    fi

    sleep 0.1
done
