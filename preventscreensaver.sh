#!/usr/bin/bash
while true; do

#PROCSOUND=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING")
PLAYING="RUNNING"
PACMANDINPUTS=$(pacmd list-sink-inputs | grep RUNNING | awk '{ print $2 }')
if [ "$PACMANDINPUTS" = "$PLAYING" ]; then
	xscreensaver-command -deactivate
else
	:
fi

sleep 0.1s
done
