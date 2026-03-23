#!/usr/bin/env bash
# Suspend only when lid is closed AND HDMI is NOT connected

LOCK_FILE="/tmp/laptopLid_close_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

# Auto-detect lid device (LID0, LID, LID1, etc.)
#~ LID_DEVICE=$(ls /proc/acpi/button/lid/ | head -n1)
#~ LID_DEVICE=$(ls /proc/acpi/button/lid/)

get_lid_state() {
    awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null
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
            #systemctl suspend 
            loginctl lock-session
        fi
    fi

    PREV="$LID"
    sleep 0.1s
done
