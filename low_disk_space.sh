#!/bin/bash

# Set the threshold for free space (in percentage)
THRESHOLD=80
# Set the interval for checking (in seconds)
INTERVAL=10

while true; do
    # Get the percentage of used space on root directory
    USED_PERCENT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    # Check if used space exceeds the threshold
    if [ "$USED_PERCENT" -ge "$THRESHOLD" ]; then
        notify-send --app-name "Low disk space:" "Disk space used is $USED_PERCENT%. Free up disk space to ensure system stability."
    fi

    # Wait for the specified interval before checking again
    sleep $INTERVAL
done
