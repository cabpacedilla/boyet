#!/usr/bin/env bash
# Auto suspend or disable internal screen based on lid and HDMI state
# Author: Claive Alvin P. Acedilla (improved by ChatGPT)
# Dependencies: xrandr, brightnessctl, systemd, optional: xscreensaver

# === Configuration ===
LOG_FILE="$HOME/.lid_close.log"

# Detect internal display (usually eDP-1 or eDP-0)
INTERNAL_DISPLAY=$(xrandr | grep -w connected | grep -Eo '^eDP[0-9]*')
BRIGHT_DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

# Get lid state
get_lid_state() {
    grep -q closed /proc/acpi/button/lid/LID0/state && echo "closed" || echo "open"
}

# Check HDMI connected
is_hdmi_connected() {
   xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}'
}

# Logging helper
log() {
    echo "[$(date)] $*" >> "$LOG_FILE"
}

PREV_STATE="unknown"

while true; do
    LID_STATE=$(get_lid_state)
    HDMI_CONNECTED=$(is_hdmi_connected && echo "yes" || echo "no")

    # Only react if state changed
    CURRENT_STATE="${LID_STATE}_${HDMI_CONNECTED}"
    if [[ "$CURRENT_STATE" != "$PREV_STATE" ]]; then
        log "Lid: $LID_STATE, HDMI: $HDMI_CONNECTED"

        if [[ "$LID_STATE" == "closed" && "$HDMI_CONNECTED" == "yes" ]]; then
            log "Disabling internal display to prevent overheating..."
            xrandr --output "$INTERNAL_DISPLAY" --off
        elif [[ "$LID_STATE" == "closed" && "$HDMI_CONNECTED" == "no" ]]; then
            log "Suspending system..."
            [[ -n "$BRIGHT_DEVICE" ]] && brightnessctl -d "$BRIGHT_DEVICE" set 90%
            # xscreensaver-command --lock  # Optional
            systemctl suspend
        elif [[ "$LID_STATE" == "open" ]]; then
            log "Enabling internal display..."
            xrandr --output "$INTERNAL_DISPLAY" --auto
        fi

        PREV_STATE="$CURRENT_STATE"
    fi

    sleep 1
done
