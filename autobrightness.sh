#!/usr/bin/bash

BRIGHT_PATH=/sys/class/backlight/amdgpu_bl0/brightness
BRIGHTNESS=$(cat $BRIGHT_PATH)
OPTIMAL=80

brightness_check()
{
	if [ "$BRIGHTNESS" != "$OPTIMAL" ]; then
		echo $OPTIMAL | sudo tee $BRIGHT_PATH
	else
		:
	fi
}

brightness_check
while inotifywait -e modify $BRIGHT_PATH; do
	brightness_check
done
