#!/usr/bin/bash

BRIGHT_PATH=/sys/class/backlight/amdgpu_bl0/brightness
BRIGHTNESS=$(cat /sys/class/backlight/amdgpu_bl0/brightness)
OPTIMAL=80

if [ "$BRIGHTNESS" != "$OPTIMAL" ]; then
	echo 80 | sudo tee /sys/class/backlight/amdgpu_bl0/brightness
else
	:
fi

while inotifywait -e modify $BRIGHT_PATH; do
BRIGHTNESS=$(cat /sys/class/backlight/amdgpu_bl0/brightness)

if [ "$BRIGHTNESS" != "$OPTIMAL" ]; then
	echo 80 | sudo tee /sys/class/backlight/amdgpu_bl0/brightness
else
	:
fi

done
