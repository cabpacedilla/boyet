#!/usr/bin/env bash
# Nobara Auto-Update Daemon v2.5
# Fixes: False failure notifications & reliable package listing

# --- CONFIG ---
LOGFILE_GENERAL="$HOME/scriptlogs/general_update_log.txt"
LIST="$HOME/scriptlogs/updateable.txt"
FAIL_DIR="$HOME/scriptlogs/failures"
mkdir -p "$FAIL_DIR" "$(dirname "$LOGFILE_GENERAL")"

while true; do
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$log_time - Starting update cycle" >> "$LOGFILE_GENERAL"

    # 1. Sync & cleanup
    sudo dnf clean all >> "$LOGFILE_GENERAL" 2>&1
    sudo nobara-updater check-updates -y >> "$LOGFILE_GENERAL" 2>&1

    # 2. Get full pending updates list
    sudo dnf check-update > "$LIST.tmp" 2>/dev/null

    # Format nice list for notifications
    PENDING_NAMES=$(grep -E '\.' "$LIST.tmp" | awk '{print $1}' | sort -u | head -n 15)
    PENDING_COUNT=$(grep -E '\.' "$LIST.tmp" | wc -l)

    if [[ $PENDING_COUNT -eq 0 ]]; then
        echo "$log_time - System up to date." >> "$LOGFILE_GENERAL"
        notify-send -t 5000 "Auto-updates" "System is already up to date."
    else
        # Show short list + count in notification
        NOTIFY_TEXT="Ready to update $PENDING_COUNT packages:\n$PENDING_NAMES"
        [[ $PENDING_COUNT -gt 15 ]] && NOTIFY_TEXT+="\n...and $((PENDING_COUNT-15)) more"

        notify-send -t 0 "Updates Detected" "$NOTIFY_TEXT"

        # 3. Run update
        TEMP_SYNC_LOG=$(mktemp)
        echo "$log_time - Running nobara-sync cli..." >> "$LOGFILE_GENERAL"
        
        # We use PIPESTATUS to catch the exit code of nobara-sync, not tee
        sudo nobara-sync cli | tee "$TEMP_SYNC_LOG" >> "$LOGFILE_GENERAL" 2>&1
        EXIT_CODE=${PIPESTATUS[0]}

        # 4. Verification: Check Exit Code OR Success Strings
        if [ $EXIT_CODE -eq 0 ] || grep -aiE "Updates complete!|Complete!|Transaction test succeeded|Nothing to do|All Updates complete" "$TEMP_SYNC_LOG" > /dev/null; then
            
            # Success – determine what was actually updated using our previous list
            UPDATED_LIST=$(grep -E '\.' "$LIST.tmp" | awk '{print $1}' | sort -u)
            UPDATED_COUNT=$(echo "$UPDATED_LIST" | grep -v '^$' | wc -l)

            if [[ $UPDATED_COUNT -gt 0 ]]; then
                DISPLAY_LIST=$(echo "$UPDATED_LIST" | head -n 15)
                SUCCESS_TEXT="Updated $UPDATED_COUNT packages:\n$DISPLAY_LIST"
                [[ $UPDATED_COUNT -gt 15 ]] && SUCCESS_TEXT+="\n...and $((UPDATED_COUNT-15)) more"
            else
                SUCCESS_TEXT="Updates completed (System already clean)."
            fi

            notify-send -t 10000 "Updates Complete" "$SUCCESS_TEXT"
            echo "$log_time - SUCCESS. $SUCCESS_TEXT" >> "$LOGFILE_GENERAL"
        else
            # Actual Failure
            FAIL_LOG_NAME="fail_$(date '+%Y%m%d_%H%M%S').log"
            cp "$TEMP_SYNC_LOG" "$FAIL_DIR/$FAIL_LOG_NAME"
            echo "$log_time - ERROR: Update verification failed. Log: $FAIL_DIR/$FAIL_LOG_NAME" >> "$LOGFILE_GENERAL"
            notify-send -u critical "Auto-updates" "Update failed!\nLog saved to:\n$FAIL_DIR/$FAIL_LOG_NAME"
        fi

        rm -f "$TEMP_SYNC_LOG"
    fi

    rm -f "$LIST.tmp"

    echo "$log_time - Waiting 1 hour..." >> "$LOGFILE_GENERAL"
    sleep 1h
done
