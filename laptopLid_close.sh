#!/usr/bin/env bash
# This script will handle display switching and screen lock when laptop lid is closed
# Written by Claive Alvin P. Acedilla. Modified for proper display management.

# Pre-requisite: 
# Install xscreensaver and run xscreensaver at startup

# Path to lid state file
LID_PATH="/proc/acpi/button/lid/LID0/state"
OPTIMAL_BRIGHTNESS=56206

# Function to detect internal display
detect_internal_display() {
    local internal_display
    internal_display=$(xrandr | grep -w connected | grep -E '^(eDP|LVDS|DSI)' | awk '{print $1}' | head -n1)
    
    if [[ -z "$internal_display" ]]; then
        internal_display=$(xrandr | grep -w connected | grep -v HDMI | awk '{print $1}' | head -n1)
    fi
    
    echo "$internal_display"
}

# Function to check if HDMI is connected and get its name
check_hdmi() {
    local hdmi_display
    hdmi_display=$(xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}')
    echo "$hdmi_display"
}

# Function to get the lid state
get_lid_state() {
    local lid_state
    if [ -f "$LID_PATH" ]; then
        lid_state=$(awk '{print $2}' < "$LID_PATH")
    fi
    echo "$lid_state"
}

# Function to setup displays for lid closed with HDMI (optimized working version)
setup_external_only() {
    local internal_display="$1"
    local hdmi_display="$2"
    
    echo "Switching to external display only..."
    
    # Use the approach that actually works from our debug:
    # Even though the first command shows error, it prepares the system
    # The second command successfully activates HDMI
    xrandr --output "$internal_display" --off 2>/dev/null
    sleep 1
    xrandr --output "$hdmi_display" --auto --primary
    
    echo "Display switched to $hdmi_display only"
}

# Function to restore both displays when lid opens
restore_displays() {
    local internal_display="$1"
    local hdmi_display="$2"
    
    echo "Restoring display configuration..."
    
    # Reset and enable internal display first
    xrandr --auto
    sleep 1
    xrandr --output "$internal_display" --auto --primary
    
    if [[ -n "$hdmi_display" ]] && xrandr | grep -w connected | grep -q "$hdmi_display"; then
        # Both displays connected - extend them
        xrandr --output "$hdmi_display" --auto --right-of "$internal_display"
        echo "Extended display setup: $internal_display + $hdmi_display"
    else
        echo "Internal display only: $internal_display"
    fi
}

# Detect displays once at startup
INTERNAL_DISPLAY=$(detect_internal_display)
PREV_LID_STATE="open"

echo "Display manager started: Internal=$INTERNAL_DISPLAY"

# Main loop
while true; do
    LID_STATE=$(get_lid_state)
    HDMI_DISPLAY=$(check_hdmi)
    
    # Only act if lid state changed
    if [[ "$LID_STATE" != "$PREV_LID_STATE" ]]; then
        
        if [[ "$LID_STATE" == "closed" ]]; then
            if [[ -n "$HDMI_DISPLAY" && -n "$INTERNAL_DISPLAY" ]]; then
                echo "Lid closed with HDMI connected. Switching to external display..."
                setup_external_only "$INTERNAL_DISPLAY" "$HDMI_DISPLAY"
                
            elif [[ -z "$HDMI_DISPLAY" ]]; then
                # No HDMI connected, lock and suspend
                echo "Lid closed without HDMI. Locking and suspending..."
                brightnessctl --device=amdgpu_bl1 set 80%
                #xscreensaver-command --lock
                systemctl suspend
            fi
            
        elif [[ "$LID_STATE" == "open" ]]; then
            if [[ -n "$INTERNAL_DISPLAY" ]]; then
                echo "Lid opened. Restoring displays..."
                restore_displays "$INTERNAL_DISPLAY" "$HDMI_DISPLAY"
            fi
        fi
        
        PREV_LID_STATE="$LID_STATE"
    fi

    sleep 1
done
