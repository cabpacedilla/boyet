#!/usr/bin/bash
while true; do

#PLAYING=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING")

PLAYING=$(pacmd list-sink-inputs | grep RUNNING | awk '{ print $2 }' &)

if [ -z "$PLAYING" ]; then
	:
elif [ "$PLAYING" = "RUNNING" ]; then
	xscreensaver-command -deactivate
fi

sleep 0.1s
done
