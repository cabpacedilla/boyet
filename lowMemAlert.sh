#!/bin/bash

# Configuration
INTERVAL=120
LEVELS=$(seq 80 1 100)
LAST_ALERT=0
MOUNT_POINT="/"
LOG_FILE="$HOME/scriptlogs/disk_monitor.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))
MAX_OLD_LOGS=5
USER_DIRS_CHECK=true
USER_DIRS=("/home/*" "/root")
TOP_USERS_LIMIT=5

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Improved log rotation function with timestamping
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="${LOG_FILE}.${TIMESTAMP}.old"
        mv "$LOG_FILE" "$BACKUP_FILE"
        log_message "LOG ROTATED: Previous log moved to $(basename "$BACKUP_FILE")"
        ls -t "${LOG_FILE}".*.old 2>/dev/null | tail -n +$(($MAX_OLD_LOGS + 1)) | xargs rm -f --
    fi
}

# Function to get user directory sizes (formatted for alerts)
get_user_space_usage() {
    local top_users=""
    for user_dir in ${USER_DIRS[@]}; do
        if [ -d "$user_dir" ]; then
            top_users+=$(find "$user_dir" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | sort -hr | head -n $TOP_USERS_LIMIT)
            top_users+="\n"
        fi
    done
    echo -e "$top_users"
}

# Function to get user space usage for notifications (compact format)
get_user_space_for_alert() {
    local alert_info=""
    local count=0

    for user_dir in ${USER_DIRS[@]}; do
        if [ -d "$user_dir" ]; then
            while IFS= read -r line; do
                if [ -n "$line" ] && [ $count -lt 3 ]; then
                    size=$(echo "$line" | awk '{print $1}')
                    user=$(echo "$line" | awk '{print $2}')
                    alert_info+="• ${user##*/}: $size\n"
                    ((count++))
                fi
            done <<< $(find "$user_dir" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | sort -hr | head -n 3)
        fi
    done

    echo -e "$alert_info"
}

# Function to check and log user space usage
check_user_space() {
    if [ "$USER_DIRS_CHECK" = true ]; then
        local user_usage=$(get_user_space_usage)
        if [ -n "$user_usage" ]; then
            log_message "TOP USER SPACE USAGE:"
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    log_message "  $line"
                fi
            done <<< "$user_usage"
        fi
    fi
}

# Initial log entry
log_message "=== Disk Monitoring Script Started ==="
log_message "Monitoring mount point: $MOUNT_POINT"
log_message "Check interval: $INTERVAL seconds"
log_message "Alert thresholds: 80% to 100%"
log_message "Max log size: $((MAX_LOG_SIZE / 1024 / 1024))MB"
log_message "Max old logs to keep: $MAX_OLD_LOGS"
log_message "User directory monitoring: $USER_DIRS_CHECK"

# Main monitoring loop
while true; do
    rotate_log

    # Get current disk usage percentage
    if ! USED_PERCENT=$(df "$MOUNT_POINT" | awk 'NR==2 {print $5}' | sed 's/%//'); then
        log_message "ERROR: Failed to get disk usage for $MOUNT_POINT"
        sleep $INTERVAL
        continue
    fi

    # Check user space usage on alert conditions or periodically
    if [ "$USED_PERCENT" -ge 80 ] || [ "$(date +%M)" -le 1 ]; then
       check_user_space
    fi


    # Check against all threshold levels
    for LEVEL in $LEVELS; do
        if [ "$USED_PERCENT" -ge "$LEVEL" ] && [ "$LAST_ALERT" -lt "$LEVEL" ]; then
            # Get user space info for alerts
            USER_SPACE_INFO=$(get_user_space_for_alert)

            # Create alert message with space usage
            ALERT_MESSAGE="Disk usage: ${USED_PERCENT}% (Threshold: ${LEVEL}%)"

            if [ -n "$USER_SPACE_INFO" ]; then
                ALERT_MESSAGE+="\n\nTop space users:\n${USER_SPACE_INFO}"
            fi

            # Send desktop notification with space usage info
            notify-send --urgency=critical --app-name "Low disk space" "$ALERT_MESSAGE"

            # Log the alert with full user space details
            log_message "ALERT: Disk usage ${USED_PERCENT}% >= ${LEVEL}% threshold"

            # Log detailed user space info
            if [ "$USED_PERCENT" -ge 85 ]; then
                DETAILED_USAGE=$(get_user_space_usage)
                if [ -n "$DETAILED_USAGE" ]; then
                    log_message "DETAILED SPACE USAGE:"
                    while IFS= read -r line; do
                        if [ -n "$line" ]; then
                            log_message "  $line"
                        fi
                    done <<< "$DETAILED_USAGE"
                fi
            fi

            LAST_ALERT=$LEVEL
        fi
    done

    # Check if usage dropped below 80% (recovery condition)
    if [ "$USED_PERCENT" -lt 80 ]; then
        if [ "$LAST_ALERT" -ne 0 ]; then
            RECOVERY_MESSAGE="Disk usage normalized to ${USED_PERCENT}%"

            # Add space usage summary to recovery message
            if [ "$USER_DIRS_CHECK" = true ]; then
                TOP_USER=$(find "${USER_DIRS[0]}" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | sort -hr | head -n 1)
                if [ -n "$TOP_USER" ]; then
                    RECOVERY_MESSAGE+="\nLargest user: $TOP_USER"
                fi
            fi

            notify-send --urgency=normal --app-name "Disk space normal" "$RECOVERY_MESSAGE"
            log_message "INFO: Disk usage normalized to ${USED_PERCENT}%"
        fi
        LAST_ALERT=0
    fi

    sleep $INTERVAL
done
