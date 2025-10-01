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

# Get HDMI display name (if connected)
get_hdmi_display() {
    xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}'
}

# Logging helper
log() {
    echo "[$(date)] $*" >> "$LOG_FILE"
}

PREV_STATE="unknown"

while true; do
    LID_STATE=$(get_lid_state)
    HDMI_DISPLAY=$(get_hdmi_display)
    HDMI_CONNECTED="no"

    if [[ -n "$HDMI_DISPLAY" ]]; then
        HDMI_CONNECTED="yes"
    fi

    CURRENT_STATE="${LID_STATE}_${HDMI_CONNECTED}"
    if [[ "$CURRENT_STATE" != "$PREV_STATE" ]]; then
        log "Lid: $LID_STATE, HDMI: $HDMI_CONNECTED"

        if [[ "$LID_STATE" == "closed" && "$HDMI_CONNECTED" == "yes" ]]; then
            log "Lid closed and HDMI connected. Switching to HDMI display only..."
            sleep 1  # Give system time to register display change
            xrandr --output "$INTERNAL_DISPLAY" --off \
                   --output "$HDMI_DISPLAY" --auto --primary
            log "Internal display disabled. HDMI active."
        
        elif [[ "$LID_STATE" == "closed" && "$HDMI_CONNECTED" == "no" ]]; then
            log "Lid closed and no HDMI connected. Suspending system..."
            [[ -n "$BRIGHT_DEVICE" ]] && brightnessctl -d "$BRIGHT_DEVICE" set 90%
            # Optional: xscreensaver-command --lock
            systemctl suspend
        
        elif [[ "$LID_STATE" == "open" ]]; then
            log "Lid opened. Enabling internal display..."
            xrandr --output "$INTERNAL_DISPLAY" --auto
            [[ -n "$HDMI_DISPLAY" ]] && xrandr --output "$HDMI_DISPLAY" --auto
            log "Internal display enabled."
        fi

        PREV_STATE="$CURRENT_STATE"
    fi

    sleep 1
done
