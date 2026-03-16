#!/usr/bin/env bash

LOCK_FILE="/tmp/autobrightness_$(whoami).lock"
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

# Detect the amdgpu backlight device dynamically
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)

if [ -z "$DEVICE" ]; then
    echo "No amdgpu backlight device found."
    exit 1
fi

TARGET_PERCENT=90

while true; do
    CURRENT_BRIGHTNESS=$(brightnessctl -d "$DEVICE" get)
    MAX_BRIGHTNESS=$(brightnessctl -d "$DEVICE" max)
    CURRENT_PERCENT=$(( 100 * CURRENT_BRIGHTNESS / MAX_BRIGHTNESS ))

    if [ "$CURRENT_PERCENT" -ne "$TARGET_PERCENT" ]; then
        brightnessctl -d "$DEVICE" set "${TARGET_PERCENT}%"
    fi

    sleep 5
done
