#!/bin/bash

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
