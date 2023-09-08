#!/usr/bin/bash
while true; do

#PROCSOUND=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING")
NOTPLAYING="CORKED"
PACMANDINPUTS=$(pacmd list-sink-inputs | grep -w "CORKED" | awk '{ print $2 }')
if [ "$PACMANDINPUTS" = "$NOTPLAYING" ]; then
	:
elif [ -z "$PACMANDINPUTS" ]; then
	xscreensaver-command -deactivate
fi

sleep 0.1s
done
