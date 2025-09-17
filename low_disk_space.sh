#!/bin/bash

INTERVAL=120
LEVELS=$(seq 80 1 100)
LAST_ALERT=0
MOUNT_POINT="/"
LOG_FILE="~/scriptlogs/disk_monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

while true; do
    if ! USED_PERCENT=$(df "$MOUNT_POINT" | awk 'NR==2 {print $5}' | sed 's/%//'); then
        log_message "ERROR: Failed to get disk usage for $MOUNT_POINT"
        sleep $INTERVAL
        continue
    fi

    for LEVEL in $LEVELS; do
        if [ "$USED_PERCENT" -ge "$LEVEL" ] && [ "$LAST_ALERT" -lt "$LEVEL" ]; then
            notify-send --urgency=critical --app-name "Low disk space" \
                        "Disk usage on $MOUNT_POINT has reached ${USED_PERCENT}%. Threshold: ${LEVEL}%."
            log_message "ALERT: Disk usage ${USED_PERCENT}% >= ${LEVEL}% threshold"
            LAST_ALERT=$LEVEL
        fi
    done

    if [ "$USED_PERCENT" -lt 80 ]; then
        if [ "$LAST_ALERT" -ne 0 ]; then
            log_message "INFO: Disk usage normalized to ${USED_PERCENT}%"
            notify-send --urgency=normal --app-name "Disk space normal" \
                       "Disk usage on $MOUNT_POINT is now ${USED_PERCENT}%"
        fi
        LAST_ALERT=0
    fi

    sleep $INTERVAL
done
