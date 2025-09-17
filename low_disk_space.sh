#!/bin/bash

# Configuration
INTERVAL=120
LEVELS=$(seq 80 1 100)
LAST_ALERT=0
MOUNT_POINT="/"
LOG_FILE="$HOME/scriptlogs/disk_monitor.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))   # 50 MB
MAX_OLD_LOGS=5

# Dependencies
REQUIRED_CMDS=(df awk sed date stat notify-send find sort xargs)
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing dependency: $cmd" >&2
        exit 1
    }
done

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Log rotation
rotate_log() {
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt $MAX_LOG_SIZE ]; then
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="${LOG_FILE}.${TIMESTAMP}.old"
        mv "$LOG_FILE" "$BACKUP_FILE" 2>/dev/null || return
        touch "$LOG_FILE"
        log_message "LOG ROTATED: Previous log moved to $(basename "$BACKUP_FILE")"
        find "$(dirname "$LOG_FILE")" -maxdepth 1 -name "$(basename "$LOG_FILE")*.old" \
            -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | \
            awk "NR>$MAX_OLD_LOGS {print \$2}" | xargs -r rm -f --
    fi
}

# Safe notifications
safe_notify_send() {
    local urgency="$1"
    local app_name="$2"
    local message="$3"

    [ -z "$message" ] && return
    if [ ${#message} -gt 1000 ]; then
        message="${message:0:997}..."
    fi

    notify-send --urgency="$urgency" --app-name "$app_name" "$message" 2>/dev/null || \
        log_message "WARNING: notify-send failed (no session bus?)"
}

# Initial setup
rotate_log
log_message "=== Disk Monitoring Script Started ==="
log_message "Monitoring mount point: $MOUNT_POINT"
log_message "Check interval: $INTERVAL seconds"
log_message "Alert thresholds: 80% to 100%"
log_message "Max log size: $((MAX_LOG_SIZE / 1024 / 1024))MB"
log_message "Max old logs to keep: $MAX_OLD_LOGS"

# Main loop
while true; do
    rotate_log

    USED_PERCENT=$(df "$MOUNT_POINT" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    [[ "$USED_PERCENT" =~ ^[0-9]+$ ]] || USED_PERCENT=0

    for LEVEL in $LEVELS; do
        if [ "$USED_PERCENT" -ge "$LEVEL" ] && [ "$LAST_ALERT" -lt "$LEVEL" ]; then
            ALERT_MESSAGE="Disk usage has reached ${USED_PERCENT}%. Threshold: ${LEVEL}%."
            safe_notify_send "critical" "Low disk space" "$ALERT_MESSAGE"
            log_message "ALERT: Disk usage ${USED_PERCENT}% >= ${LEVEL}% threshold"
            LAST_ALERT=$LEVEL
        fi
    done

    if [ "$USED_PERCENT" -lt 80 ]; then
        if [ "$LAST_ALERT" -ne 0 ]; then
            RECOVERY_MESSAGE="Disk usage normalized to ${USED_PERCENT}%"
            safe_notify_send "normal" "Disk space normal" "$RECOVERY_MESSAGE"
            log_message "INFO: Disk usage normalized to ${USED_PERCENT}%"
        fi
        LAST_ALERT=0
    fi

    sleep $INTERVAL
done
