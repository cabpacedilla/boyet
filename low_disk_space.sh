#!/bin/bash

INTERVAL=120
# Levels from 80% to 90%
LEVELS=$(seq 80 1 90)
LAST_ALERT=0

while true; do
    USED_PERCENT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    for LEVEL in $LEVELS; do
        if [ "$USED_PERCENT" -ge "$LEVEL" ] && [ "$LAST_ALERT" -lt "$LEVEL" ]; then
            notify-send --urgency=critical --app-name "Low disk space" \
                        "Disk usage has reached ${USED_PERCENT}%. Threshold: ${LEVEL}%."
            LAST_ALERT=$LEVEL
        fi
    done

    # Reset if usage goes back below first threshold
    if [ "$USED_PERCENT" -lt 80 ]; then
        LAST_ALERT=0
    fi

    sleep $INTERVAL
done
