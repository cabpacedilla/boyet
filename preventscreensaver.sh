#!/usr/bin/bash

# Function to check if media is playing
is_media_playing() {
	#~ MEDIA_PLAY=$(pacmd list-sink-inputs | grep -w "RUNNING" | awk '{ print $2 }')
    MEDIA_PLAY=$(pactl list | grep -w "RUNNING" | awk '{ print $2 }')
}

# Main loop
while true; do
    MEDIA_PLAY=$(is_media_playing)

    if [ $? -eq 0 ]; then
        if [ -n "$MEDIA_PLAY" ]; then
            xscreensaver-command -deactivate
        else
			:
        fi
    else
		continue
    fi

    sleep 0.1
done

