#!/usr/bin/bash

# Function to check if media is playing
is_media_playing() {
	#MEDIA_PLAY=$(pacmd list-sink-inputs | grep -w "RUNNING" | awk '{ print $2 }')
    local MEDIA_PLAY
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
    echo "$MEDIA_PLAY"
}

# Main loop
while true; do
    if MEDIA_PLAY=$(is_media_playing); then
        if [[ -n "$MEDIA_PLAY" ]]; then
            xscreensaver-command -deactivate
        else
			:
        fi
    else
		continue
    fi

    sleep 0.1
done
