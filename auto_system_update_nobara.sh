#!/usr/bin/env bash
# Nobara Auto-Update Daemon v2.2
# Integrated Failure Handler & Full-Log Logic

# --- CONFIG ---
LOGFILE_GENERAL="$HOME/scriptlogs/general_update_log.txt"
LIST="$HOME/scriptlogs/updateable.txt"
FAIL_DIR="$HOME/scriptlogs/failures"
mkdir -p "$FAIL_DIR"

while true; do
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 1. Synchronization Phase ---
    echo "$log_time - Initial repository sync and cache cleanup." >> "$LOGFILE_GENERAL"

    sudo dnf clean all 2>> "$LOGFILE_GENERAL"
    
    if sudo nobara-updater check-updates 2>> "$LOGFILE_GENERAL"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Repositories re-synchronized." >> "$LOGFILE_GENERAL"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Repository refresh had issues." >> "$LOGFILE_GENERAL"
    fi

    # 2. Detection Phase ---
    sudo dnf list updates -q > "$LIST.tmp" 2>/dev/null
    
    # Capture the FULL list for the log file
    FULL_PENDING=$(grep -E '\.' "$LIST.tmp" | awk '{print $1 " (" $2 ")"}' | sort -u)

    if [ -z "$FULL_PENDING" ]; then
        echo "$log_time - System up to date." >> "$LOGFILE_GENERAL"
        notify-send -t 5000 "Auto-updates" "System is already up to date."
    else
        notify-send -t 0 "Updates Detected" "Ready to update:\n$FULL_PENDING\n...(and more)"
        
        # 3. Execution Phase ---
        TEMP_SYNC_LOG=$(mktemp)
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Launching nobara-sync cli..." >> "$LOGFILE_GENERAL"

        sudo nobara-sync cli | tee "$TEMP_SYNC_LOG" >> "$LOGFILE_GENERAL" 2>&1

        # 4. Verification & Failure Handling ---
        if grep -aiE "Updates complete!|Complete!" "$TEMP_SYNC_LOG" > /dev/null; then
            # SUCCESS PATH
            LOG_FRIENDLY_LIST=$(echo "$FULL_PENDING" | xargs | sed 's/ /, /g')
            echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS. Updated: $LOG_FRIENDLY_LIST" >> "$LOGFILE_GENERAL"
            
            notify-send -t 0 "Updates Complete" "Verified success.\n\nUpdated:\n$FULL_PENDING"
            rm -f "$TEMP_SYNC_LOG"
        else
            # FAILURE PATH
            FAIL_LOG_NAME="fail_$(date '+%Y%m%d_%H%M%S').log"
            cp "$TEMP_SYNC_LOG" "$FAIL_DIR/$FAIL_LOG_NAME"
            
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Verification failed. Log saved to $FAIL_DIR/$FAIL_LOG_NAME" >> "$LOGFILE_GENERAL"
            notify-send -u critical "Auto-updates" "Update failed! Log saved to:\n$FAIL_DIR/$FAIL_LOG_NAME"
            
            rm -f "$TEMP_SYNC_LOG"
        fi
    fi

    rm -f "$LIST.tmp"
    
    # Sleep 1 Hour
    echo "$log_time - Waiting for 1 hour..." >> "$LOGFILE_GENERAL"
    sleep 1h
done
