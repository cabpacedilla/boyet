#!/usr/bin/env bash
# Suspend only when lid is closed AND HDMI is NOT connected

# Auto-detect lid device (LID0, LID, LID1, etc.)
LID_DEVICE=$(ls /proc/acpi/button/lid/ | head -n1)

get_lid_state() {
    awk '{print $2}' /proc/acpi/button/lid/"$LID_DEVICE"/state 2>/dev/null
}

# HDMI connected? (returns success if yes)
hdmi_connected() {
    xrandr | grep ' connected' | grep 'HDMI' | awk '{print $1}'
}

# To avoid repeated suspends while lid remains closed
PREV="open"

while true; do
    LID=$(get_lid_state)

    # Trigger only when lid transitions from open → closed
    if [[ "$LID" == "closed" && "$PREV" == "open" ]]; then
        
        if hdmi_connected; then
            # Lid closed but HDMI is connected → do nothing
            :
        else
            # Lid closed and HDMI NOT connected → suspend
            systemctl suspend 
        fi
    fi

    PREV="$LID"
    sleep 0.1s
done
