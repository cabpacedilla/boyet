#!/usr/bin/bash

BRIGHT_PATH=/sys/class/backlight/amdgpu_bl0/brightness
#OPTIMAL=200 # for ubuntu
OPTIMAL=39321

brightness_check()
{
	BRIGHTNESS=$(cat $BRIGHT_PATH)
	if [ "$BRIGHTNESS" != "$OPTIMAL" ]; then
		brightnessctl --device=amdgpu_bl0 set 60%
	else
		:
	fi
}

brightnessctl --device=amdgpu_bl0 set 60%
brightness_check
while inotifywait -e modify $BRIGHT_PATH; do
	brightness_check
done
