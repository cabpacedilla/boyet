#!/usr/bin/bash
# Low Memory Alert Script (Clean notify-send + log rotation)
# Alerts when free RAM drops below a percentage threshold
# Author: Claive Alvin P. Acedilla

# --------------------------
# User-configurable settings
MEMFREE_LIMIT_PERCENT=15       # Threshold (%)
CHECK_INTERVAL=30              # Seconds
MAX_PROCESSES=5                # Top memory-consuming processes to display
LOG_FILE="$HOME/lowMemAlert.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 50 MB in bytes

# --------------------------
while true; do
    # Get total and available memory in MB
    TOTAL_MEM=$(free -m | awk 'NR==2 {print $2}')
    MEMFREE=$(free -m | awk 'NR==2 {print $7}')
    THRESHOLD=$(( TOTAL_MEM * MEMFREE_LIMIT_PERCENT / 100 ))

    # Check if free memory is below or equal to threshold
    if [[ "$MEMFREE" =~ ^[0-9]+$ ]] && [ "$MEMFREE" -le "$THRESHOLD" ]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        # Get top memory-consuming processes (only command names)
        TOP_PROCESSES=$(ps -eo %mem,comm --sort=-%mem | head -n $((MAX_PROCESSES + 1)) | \
            awk 'NR>1 {printf "%s: %.0f%%\n", $2, $1}')

        # Build notification message
        NOTIF="RAM below ${MEMFREE_LIMIT_PERCENT}%.
        Top memory users:
        $TOP_PROCESSES"

        # Send desktop notification
        notify-send -u critical "⚠️ Low Memory Alert" "$NOTIF"

        # --------------------------
        # Log rotation by file size
        if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d_%H%M%S')"
            touch "$LOG_FILE"
        fi

        # Append alert to log
        echo -e "[$TIMESTAMP] $NOTIF\n" >> "$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
