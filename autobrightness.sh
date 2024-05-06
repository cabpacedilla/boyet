#!/usr/bin/bash

BRIGHT_PATH=/sys/class/backlight/amdgpu_bl0/brightness
OPTIMAL=128

brightness_check()
{
	BRIGHTNESS=$(cat $BRIGHT_PATH)
	if [ "$BRIGHTNESS" != "$OPTIMAL" ]; then
		sudo echo $OPTIMAL | sudo tee $BRIGHT_PATH
	else
		:
	fi
}

brightness_check
while inotifywait -e modify $BRIGHT_PATH; do
	brightness_check
done
