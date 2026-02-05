#!/usr/bin/env bash

# --- CONFIG ---
LOGFILE_GENERAL="$HOME/scriptlogs/general_update_log.txt"
HISTORY_LOG="$HOME/scriptlogs/update_history.csv"
LIST="$HOME/scriptlogs/updateable.txt"
FAIL_DIR="$HOME/scriptlogs/failures"

mkdir -p "$FAIL_DIR" "$(dirname "$LOGFILE_GENERAL")"

if [ ! -f "$HISTORY_LOG" ]; then
    echo "Date,Package_Name,Version" > "$HISTORY_LOG"
fi

while true; do
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$log_time - Starting update cycle" >> "$LOGFILE_GENERAL"

    # 1. Sync & cleanup metadata
    sudo dnf clean all >> "$LOGFILE_GENERAL" 2>&1
    sudo nobara-updater check-updates -y >> "$LOGFILE_GENERAL" 2>&1

    # 2. Get full pending updates list
    sudo dnf check-update > "$LIST.tmp" 2>/dev/null
    
    # --- NEW: INDIVIDUAL & TOTAL SIZE CALCULATION ---
    PENDING_RAW=$(grep -E '\.' "$LIST.tmp" | awk '{print $1}')
    DISPLAY_LIST=""
    TOTAL_BYTES=0

    if [[ -n "$PENDING_RAW" ]]; then
        while read -r pkg; do
            # Fetch download size in bytes
            size_bytes=$(sudo dnf repoquery --qf "%{size}" --latest-limit 1 "$pkg" 2>/dev/null | head -n1)
            [[ -z "$size_bytes" ]] && size_bytes=0
            
            # Convert bytes to human readable string
            if [ "$size_bytes" -ge 1048576 ]; then
                readable_size="$(echo "scale=2; $size_bytes/1048576" | bc) MB"
            else
                readable_size="$(echo "scale=0; $size_bytes/1024" | bc) KB"
            fi
            
            # Get version for display
            version=$(grep "$pkg" "$LIST.tmp" | awk '{print $2}' | head -n1)
            
            # Format: Package (Version) - [Size]
            DISPLAY_LIST+="$pkg ($version) - [$readable_size]\n"
            TOTAL_BYTES=$((TOTAL_BYTES + size_bytes))
        done <<< "$PENDING_RAW"
    fi

    # Format Total Download Size
    if [ "$TOTAL_BYTES" -ge 1048576 ]; then
        DOWNLOAD_SIZE="$(echo "scale=2; $TOTAL_BYTES/1048576" | bc) MB"
    else
        DOWNLOAD_SIZE="$(echo "scale=0; $TOTAL_BYTES/1024" | bc) KB"
    fi

    PENDING_COUNT=$(echo -e "$DISPLAY_LIST" | grep -v '^$' | wc -l)

    # KERNEL CHECK
    KERNEL_UPDATE=false
    if echo "$DISPLAY_LIST" | grep -iq "kernel"; then
        KERNEL_UPDATE=true
    fi

    if [[ $PENDING_COUNT -eq 0 ]]; then
        echo "$log_time - System up to date." >> "$LOGFILE_GENERAL"
        notify-send -t 5000 "Auto-updates" "System is already up to date."
    else
        # Pre-Update Notification
        TITLE="Updates Detected"
        [[ "$KERNEL_UPDATE" = true ]] && TITLE="⚠️ Kernel Update Detected"
        
        # This will now show the total size and individual sizes as requested
        notify-send -t 0 "$TITLE" "Pending: $PENDING_COUNT packages\nEst. Total Size: $DOWNLOAD_SIZE\n\nFull List:\n$(echo -e "$DISPLAY_LIST")"

        # 3. Run update
        TEMP_SYNC_LOG=$(mktemp)
        sudo nobara-sync cli | tee "$TEMP_SYNC_LOG" >> "$LOGFILE_GENERAL" 2>&1
        EXIT_CODE=${PIPESTATUS[0]}

        # 4. Verification & Archive
        if [ $EXIT_CODE -eq 0 ] || grep -aiE "Complete!|All Updates complete" "$TEMP_SYNC_LOG" > /dev/null; then
            grep -E '\.' "$LIST.tmp" | awk -v dt="$(date '+%Y-%m-%d')" '{print dt "," $1 "," $2}' >> "$HISTORY_LOG"
            sudo dnf clean packages >> "$LOGFILE_GENERAL" 2>&1
            
            FINAL_TITLE="Updates Complete"
            [[ "$KERNEL_UPDATE" = true ]] && FINAL_TITLE="✅ Updates Complete (Reboot Required)"
            
            notify-send -t 0 "$FINAL_TITLE" "Successfully updated $PENDING_COUNT packages ($DOWNLOAD_SIZE)."
        else
            FAIL_LOG_NAME="fail_$(date '+%Y%m%d_%H%M%S').log"
            cp "$TEMP_SYNC_LOG" "$FAIL_DIR/$FAIL_LOG_NAME"
            notify-send -u critical -t 0 "Auto-updates" "Update failed! Log: $FAIL_LOG_NAME"
        fi
        rm -f "$TEMP_SYNC_LOG"
    fi

    rm -f "$LIST.tmp"
    sleep 1h
done
