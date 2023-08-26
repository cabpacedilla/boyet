#!/usr/bin/bash
while true; do

PACMANDINPUTS=$(pacmd list-sink-inputs | grep RUNNING | awk '{ print $2 }')
if [ "$PACMANDINPUTS" = "RUNNING
RUNNING
RUNNING
RUNNING" ]; then
	xscreensaver-command -deactivate
fi

sleep 0.1s
done
