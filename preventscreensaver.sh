#!/usr/bin/bash
while true; do

PLAYING=$(sudo cat /proc/asound/card1/pcm0p/sub0/status | grep -o "RUNNING" &)
if [ "$PLAYING" = "RUNNING" ]; then
	xscreensaver-command -deactivate
fi

if pacmd list-sink-inputs | grep RUNNING | awk '{ print $2 }' ; then
	xscreensaver-command -deactivate
fi

sleep 0.1s
done
