#!/usr/bin/bash
while true; do

#PROCSOUND=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING")
PLAYING="RUNNING
RUNNING
RUNNING
RUNNING"
PACMANDINPUTS=$(pacmd list-sink-inputs | grep RUNNING | awk '{ print $2 }')
if [ "$PACMANDINPUTS" = "$PLAYING" ]; then
	xscreensaver-command -deactivate
fi

sleep 0.1s
done
