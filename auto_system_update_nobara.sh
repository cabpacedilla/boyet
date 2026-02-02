#!/usr/bin/env bash

# --- CONFIG ---
LOGFILE_GENERAL="$HOME/scriptlogs/general_update_log.txt"
HISTORY_LOG="$HOME/scriptlogs/update_history.csv"  # New dedicated history file
LIST="$HOME/scriptlogs/updateable.txt"
FAIL_DIR="$HOME/scriptlogs/failures"

mkdir -p "$FAIL_DIR" "$(dirname "$LOGFILE_GENERAL")"

# Initialize History CSV header if it doesn't exist
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
    
    # Calculate Total Size (Approximate via Dry-Run)
    DOWNLOAD_SIZE=$(sudo dnf update --assumeno 2>/dev/null | grep "Total download size" | cut -d ':' -f 2 | xargs)
    [[ -z "$DOWNLOAD_SIZE" ]] && DOWNLOAD_SIZE="Unknown size"

    # FILTERING: Capture Name and Version
    PENDING_LIST=$(grep -E '\.' "$LIST.tmp" | awk '{print $1 " (" $2 ")"}')
    PENDING_COUNT=$(echo "$PENDING_LIST" | grep -v '^$' | wc -l)

    # KERNEL CHECK
    KERNEL_UPDATE=false
    if echo "$PENDING_LIST" | grep -iq "kernel"; then
        KERNEL_UPDATE=true
    fi

    if [[ $PENDING_COUNT -eq 0 ]]; then
        echo "$log_time - System up to date." >> "$LOGFILE_GENERAL"
        notify-send -t 0 "Auto-updates" "System is already up to date."
    else
        # Pre-Update Notification
        TITLE="Updates Detected"
        [[ "$KERNEL_UPDATE" = true ]] && TITLE="⚠️ Kernel Update Detected"
        notify-send -t 0 "$TITLE" "Pending: $PENDING_COUNT packages\nEst. Size: $DOWNLOAD_SIZE\n\nFull List:\n$PENDING_LIST"

        # 3. Run update
        TEMP_SYNC_LOG=$(mktemp)
        echo "$log_time - Running nobara-sync cli..." >> "$LOGFILE_GENERAL"
        
        sudo nobara-sync cli | tee "$TEMP_SYNC_LOG" >> "$LOGFILE_GENERAL" 2>&1
        EXIT_CODE=${PIPESTATUS[0]}

        # 4. Verification & Post-Update Cleanup
        if [ $EXIT_CODE -eq 0 ] || grep -aiE "Updates complete!|Complete!|Transaction test succeeded|Nothing to do|All Updates complete" "$TEMP_SYNC_LOG" > /dev/null; then
            
            # --- THE ARCHIVIST STEP ---
            # Saves each package to a CSV: Date, Name, Version
            grep -E '\.' "$LIST.tmp" | awk -v dt="$(date '+%Y-%m-%d')" '{print dt "," $1 "," $2}' >> "$HISTORY_LOG"

            # --- CLEANUP ---
            sudo dnf clean packages >> "$LOGFILE_GENERAL" 2>&1
            notify-send -t 3000 "Auto-updates" "System update cleaned."

            # Final "Hero" notification
            FINAL_TITLE="Updates Complete"
            FOOTER=""
            if [[ "$KERNEL_UPDATE" = true ]]; then
                FINAL_TITLE="✅ Updates Complete (Reboot Needed)"
                FOOTER="\n\n⚠️ A new kernel was installed. Please reboot soon!"
            fi

            SUCCESS_TEXT="Successfully updated $PENDING_COUNT packages ($DOWNLOAD_SIZE):\n$PENDING_LIST$FOOTER"
            notify-send -t 0 "$FINAL_TITLE" "$SUCCESS_TEXT"
            echo "$log_time - SUCCESS. $SUCCESS_TEXT" >> "$LOGFILE_GENERAL"
        else
            # Failure Logic
            FAIL_LOG_NAME="fail_$(date '+%Y%m%d_%H%M%S').log"
            cp "$TEMP_SYNC_LOG" "$FAIL_DIR/$FAIL_LOG_NAME"
            echo "$log_time - ERROR: Update verification failed. Log: $FAIL_DIR/$FAIL_LOG_NAME" >> "$LOGFILE_GENERAL"
            notify-send -u critical -t 0 "Auto-updates" "Update failed!\nLog saved to:\n$FAIL_DIR/$FAIL_LOG_NAME"
        fi
        rm -f "$TEMP_SYNC_LOG"
    fi

    rm -f "$LIST.tmp"
    echo "$log_time - Waiting 1 hour..." >> "$LOGFILE_GENERAL"
    sleep 1h
done
