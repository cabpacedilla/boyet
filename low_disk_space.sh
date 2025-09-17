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
USER_DIRS=("/home" "/root")
TOP_USERS_LIMIT=5

# Safe directory names (no spaces, no special chars)
SAFE_USER_DIRS=()
for dir in "${USER_DIRS[@]}"; do
    SAFE_USER_DIRS+=("$(printf '%q' "$dir")")
done

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Safe log rotation function
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="${LOG_FILE}.${TIMESTAMP}.old"
        mv "$LOG_FILE" "$BACKUP_FILE"
        # Create new log file immediately to prevent race conditions
        touch "$LOG_FILE"
        log_message "LOG ROTATED: Previous log moved to $(basename "$BACKUP_FILE")"
        # Safe cleanup with error handling
        ls -t "${LOG_FILE}".*.old 2>/dev/null | tail -n +$(($MAX_OLD_LOGS + 1)) | xargs -r rm -f --
    fi
}

# Safe function to get user directory sizes
get_user_space_usage() {
    local top_users=""
    for user_dir in "${SAFE_USER_DIRS[@]}"; do
        if [ -d "$user_dir" ]; then
            # Use temporary file to avoid large command substitution
            local temp_file=$(mktemp)
            find "$user_dir" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | \
                sort -hr | head -n $TOP_USERS_LIMIT > "$temp_file"

            if [ -s "$temp_file" ]; then
                top_users+=$(cat "$temp_file")
                top_users+=$'\n'
            fi
            rm -f "$temp_file"
        fi
    done
    echo -n "$top_users"
}

# Safe function for notifications
get_user_space_for_alert() {
    local alert_info=""
    local count=0

    for user_dir in "${SAFE_USER_DIRS[@]}"; do
        if [ -d "$user_dir" ] && [ $count -lt 3 ]; then
            # Use temporary file for safe processing
            local temp_file=$(mktemp)
            find "$user_dir" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | \
                sort -hr | head -n 3 > "$temp_file"

            while IFS= read -r line && [ $count -lt 3 ]; do
                if [ -n "$line" ]; then
                    size=$(echo "$line" | awk '{print $1}')
                    user=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')
                    # Truncate long paths for safety
                    user_short=${user##*/}
                    user_short=${user_short:0:30}  # Limit to 30 chars
                    alert_info+="• $user_short: $size\n"
                    ((count++))
                fi
            done < "$temp_file"
            rm -f "$temp_file"
        fi
    done

    echo -n "$alert_info"
}

# Safe user space checking
check_user_space() {
    if [ "$USER_DIRS_CHECK" = true ]; then
        local user_usage=$(get_user_space_usage)
        if [ -n "$user_usage" ]; then
            log_message "TOP USER SPACE USAGE:"
            # Use temporary file to avoid large here documents
            local temp_file=$(mktemp)
            echo -n "$user_usage" > "$temp_file"
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    log_message "  $line"
                fi
            done < "$temp_file"
            rm -f "$temp_file"
        fi
    fi
}

# Safe notification function
safe_notify_send() {
    local urgency="$1"
    local app_name="$2"
    local message="$3"

    # Truncate very long messages
    if [ ${#message} -gt 1000 ]; then
        message="${message:0:997}..."
    fi

    notify-send --urgency="$urgency" --app-name "$app_name" "$message" 2>/dev/null || true
}

# Initial setup
rotate_log
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

    # Safe disk usage check
    if ! USED_PERCENT=$(df "$MOUNT_POINT" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//'); then
        log_message "ERROR: Failed to get disk usage for $MOUNT_POINT"
        sleep $INTERVAL
        continue
    fi

    # Check if we got a valid number
    if ! [[ "$USED_PERCENT" =~ ^[0-9]+$ ]]; then
        log_message "ERROR: Invalid disk usage value: $USED_PERCENT"
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
            ALERT_MESSAGE="Disk usage has reached ${USED_PERCENT}%. Threshold: ${LEVEL}%."

            # Add top space-using users if available
            if [ -n "$USER_SPACE_INFO" ]; then
                ALERT_MESSAGE+="\n\nTop space users:\n${USER_SPACE_INFO}"
            fi

            # Send safe desktop notification
            safe_notify_send "critical" "Low disk space" "$ALERT_MESSAGE"

            # Log the alert
            log_message "ALERT: Disk usage ${USED_PERCENT}% >= ${LEVEL}% threshold"

            LAST_ALERT=$LEVEL
        fi
    done

    # Check if usage dropped below 80% (recovery condition)
    if [ "$USED_PERCENT" -lt 80 ]; then
        if [ "$LAST_ALERT" -ne 0 ]; then
            RECOVERY_MESSAGE="Disk usage normalized to ${USED_PERCENT}%"

            # Add space usage summary to recovery message
            if [ "$USER_DIRS_CHECK" = true ]; then
                TOP_USER=$(find "/home" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | sort -hr | head -n 1)
                if [ -n "$TOP_USER" ]; then
                    # Truncate long user info
                    TOP_USER_SHORT=$(echo "$TOP_USER" | cut -c1-50)
                    RECOVERY_MESSAGE+="\nLargest user: $TOP_USER_SHORT"
                fi
            fi

            safe_notify_send "normal" "Disk space normal" "$RECOVERY_MESSAGE"
            log_message "INFO: Disk usage normalized to ${USED_PERCENT}%"
        fi
        LAST_ALERT=0
    fi

    sleep $INTERVAL
done
