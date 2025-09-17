#!/bin/bash

# Configuration
INTERVAL=120
LEVELS=$(seq 80 1 100)
LAST_ALERT=0
MOUNT_POINT="/"
LOG_FILE="$HOME/scriptlogs/disk_monitor.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 10MB
MAX_OLD_LOGS=5  # Keep up to 5 old log files

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Improved log rotation function with timestamping
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        # Create timestamped backup instead of simple .old
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="${LOG_FILE}.${TIMESTAMP}.old"
        mv "$LOG_FILE" "$BACKUP_FILE"
        log_message "LOG ROTATED: Previous log moved to $(basename "$BACKUP_FILE")"

        # Clean up old logs (keep only MAX_OLD_LOGS)
        ls -t "${LOG_FILE}".*.old 2>/dev/null | tail -n +$(($MAX_OLD_LOGS + 1)) | xargs rm -f --
    fi
}

# Initial log entry
log_message "=== Disk Monitoring Script Started ==="
log_message "Monitoring mount point: $MOUNT_POINT"
log_message "Check interval: $INTERVAL seconds"
log_message "Alert thresholds: 80% to 100%"
log_message "Max log size: $((MAX_LOG_SIZE / 1024 / 1024))MB"
log_message "Max old logs to keep: $MAX_OLD_LOGS"

# Main monitoring loop
while true; do
    # Rotate log if it's too large
    rotate_log

    # Get current disk usage percentage
    if ! USED_PERCENT=$(df "$MOUNT_POINT" | awk 'NR==2 {print $5}' | sed 's/%//'); then
        log_message "ERROR: Failed to get disk usage for $MOUNT_POINT"
        sleep $INTERVAL
        continue
    fi

    # Check against all threshold levels
    for LEVEL in $LEVELS; do
        if [ "$USED_PERCENT" -ge "$LEVEL" ] && [ "$LAST_ALERT" -lt "$LEVEL" ]; then
            # Send desktop notification (if GUI environment)
            notify-send --urgency=critical --app-name "Low disk space" \
                        "Disk usage on $MOUNT_POINT has reached ${USED_PERCENT}%. Threshold: ${LEVEL}%."

            # Log the alert
            log_message "ALERT: Disk usage ${USED_PERCENT}% >= ${LEVEL}% threshold"
            LAST_ALERT=$LEVEL
        fi
    done

    # Check if usage dropped below 80% (recovery condition)
    if [ "$USED_PERCENT" -lt 80 ]; then
        if [ "$LAST_ALERT" -ne 0 ]; then
            log_message "INFO: Disk usage normalized to ${USED_PERCENT}%"
            notify-send --urgency=normal --app-name "Disk space normal" \
                       "Disk usage on $MOUNT_POINT is now ${USED_PERCENT}%"
        fi
        LAST_ALERT=0
    fi

    # Wait for next check
    sleep $INTERVAL
done
