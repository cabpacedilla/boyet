#!/usr/bin/bash
while true; do

#PROCSOUND=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING")
MEDIA_PLAY=$(pacmd list-sink-inputs | grep -w "START_CORKED" | awk '{ print $2 }')
if [ -n "$MEDIA_PLAY" ]; then
	xscreensaver-command -deactivate
else
	:
fi

sleep 45s
done
