#!/usr/bin/bash
while true; do

#PROCSOUND=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING")
PLAYING="START_ CORKED"
PACMANDINPUTS=$(pacmd list-sink-inputs | grep -w "CORKED" | awk '{ print $2 }')
if [ "$PACMANDINPUTS" = "$PLAYING" ]; then
	xscreensaver-command -deactivate
else
	:
fi

sleep 0.1s
done
