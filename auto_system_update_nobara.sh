#!/usr/bin/env bash

# --- CONFIG ---
LOGFILE_GENERAL="$HOME/scriptlogs/general_update_log.txt"
HISTORY_LOG="$HOME/scriptlogs/update_history.csv"
LIST_TMP="/tmp/updateable.txt"

mkdir -p "$(dirname "$LOGFILE_GENERAL")"

while true; do
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$log_time - Starting update cycle" >> "$LOGFILE_GENERAL"

    # 1. Sync & cleanup metadata
    sudo dnf clean all >> "$LOGFILE_GENERAL" 2>&1
    sudo dnf makecache >> "$LOGFILE_GENERAL" 2>&1
    sudo nobara-updater check-updates >> "$LOGFILE_GENERAL" 2>&1

    # 2. Capture Pending Updates
    sudo dnf check-update > "$LIST_TMP" 2>/dev/null
    
    # Extract package names and versions (Name Version)
    PENDING_RAW=$(grep -E '\.(x86_64|noarch|i686)' "$LIST_TMP" | awk '{print $1 " " $2}')
    
    if [[ -z "$PENDING_RAW" ]]; then
        echo "$log_time - System is up to date." >> "$LOGFILE_GENERAL"
        notify-send -t 0 "System is up to date."
    else
        COUNT=$(echo "$PENDING_RAW" | wc -l)
        
        # Format the list for notifications
        DISPLAY_LIST=$(echo "$PENDING_RAW" | sed 's/ / /g')

        # Pre-Update Notification (With Names and Versions)
        notify-send -t 15000 "Updates Detected" "Pending: $COUNT packages\n\n$DISPLAY_LIST\n\nStarting background sync..."

        # 3. Run Update
        TEMP_SYNC_LOG=$(mktemp)
        sudo nobara-sync cli | tee "$TEMP_SYNC_LOG" >> "$LOGFILE_GENERAL" 2>&1
        EXIT_CODE=${PIPESTATUS[0]}

        if [ $EXIT_CODE -eq 0 ] || grep -aiE "Complete!|All Updates complete" "$TEMP_SYNC_LOG" > /dev/null; then
            # Log to CSV (Date, Package Name, Version)
            echo "$PENDING_RAW" | awk -v dt="$(date '+%Y-%m-%d')" '{print dt "," $1 "," $2}' >> "$HISTORY_LOG"
            
            # Cleanup
            sudo dnf autoremove -y >> "$LOGFILE_GENERAL" 2>&1
            sudo dnf clean packages >> "$LOGFILE_GENERAL" 2>&1
            
            # Final Notification (With Names and Versions)
            notify-send -t 0 "Updates Complete" "Successfully updated $COUNT packages:\n\n$DISPLAY_LIST"
        else
            notify-send -u critical -t 0 "Auto-updates" "Update failed! Check logs at $LOGFILE_GENERAL"
        fi
        rm -f "$TEMP_SYNC_LOG"
    fi

    rm -f "$LIST_TMP"
    sleep 1h
done
