#!/usr/bin/bash
# Auto-lock & suspend laptop when lid is closed (unless HDMI is connected)
# Written by Claive Alvin P. Acedilla — Updated for dynamic HDMI and brightness handling

# ==================
# Prerequisites:
# - Install xscreensaver (optional, for screen locking)
# - Add this script to ~/.icewm/startup as: lid_close.sh &
# ==================

# Function to check if any HDMI display is connected
check_hdmi() {
	xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}'
}

# Function to get the lid state
get_lid_state() {
    if [ -f /proc/acpi/button/lid/LID0/state ]; then
        awk '{print $2}' < /proc/acpi/button/lid/LID0/state
    fi
}

# Detect the brightness device dynamically (e.g., amdgpu_bl0, amdgpu_bl1)
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

# Main loop
while true; do
    LID_STATE=$(get_lid_state)

    if [ "$LID_STATE" == "closed" ] && ! check_hdmi; then
        # If brightness device found, adjust brightness
        if [ -n "$BRIGHT_DEVICE" ]; then
            brightnessctl -d "$BRIGHT_DEVICE" set 90%
        fi

        # Optional: Lock screen with xscreensaver (uncomment if used)
        # xscreensaver-command --lock

        # Suspend the system
        systemctl suspend
    fi

    sleep 0.1
done
