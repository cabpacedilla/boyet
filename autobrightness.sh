#!/bin/bash
BRIGHT_PATH=/sys/class/backlight/amdgpu_bl1/brightness
OPTIMAL_BRIGHTNESS=56206

while true; do
    BRIGHTNESS=$(cat "$BRIGHT_PATH")
    if [ "$BRIGHTNESS" != "$OPTIMAL_BRIGHTNESS" ]; then
        brightnessctl --device=amdgpu_bl1 set 90%
    fi
    sleep 5 # Check every 5 seconds
done
