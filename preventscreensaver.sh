#!/usr/bin/bash
while true; do

#PROCSOUND=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING")
AUDIO_PAUSED=$(pacmd list-sink-inputs | grep -w "START_CORKED" | awk '{ print $2 }')
if [ -n "$AUDIO_PAUSED" ]; then
	xscreensaver-command -deactivate
else
	:
fi

sleep 0.1s
done
