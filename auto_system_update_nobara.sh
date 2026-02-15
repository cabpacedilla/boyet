#!/usr/bin/env bash

# --- CONFIG ---
LOGFILE_GENERAL="$HOME/scriptlogs/general_update_log.txt"
HISTORY_LOG="$HOME/scriptlogs/update_history.csv"
LIST_TMP="/tmp/updateable.txt"

mkdir -p "$(dirname "$LOGFILE_GENERAL")"

while true; do
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$log_time - Starting update cycle" >> "$LOGFILE_GENERAL"

    # 1. Metadata Cleanup & Sync
    sudo dnf clean all >> "$LOGFILE_GENERAL" 2>&1
    sudo dnf makecache >> "$LOGFILE_GENERAL" 2>&1
    sudo flatpak repair >> "$LOGFILE_GENERAL" 2>&1
    flatpak repair --user >> "$LOGFILE_GENERAL" 2>&1
    sudo nobara-updater check-updates >> "$LOGFILE_GENERAL" 2>&1

    # 2. Capture Pending Updates
    # DNF: Extract Name and Version, format as "Name (Version)"
    sudo dnf check-update > "$LIST_TMP" 2>/dev/null
    PENDING_DNF=$(grep -E '\.(x86_64|noarch|i686)' "$LIST_TMP" | awk '{print $1 " (" $2 ")"}')
    
    # Flatpak: Extract App ID and Version, format as "ID (Version)"
    # We use sed to turn the tab/multiple spaces into " (" and add the closing ")"
    PENDING_FP=$(flatpak remote-ls --updates --columns=application,version 2>/dev/null | awk 'NF > 1 {print $1 " (" $2 ")"}')

    if [[ -z "$PENDING_DNF" && -z "$PENDING_FP" ]]; then
        echo "$log_time - System is up to date." >> "$LOGFILE_GENERAL"
        notify-send -t 5000 "System is up to date."
    else
        DNF_COUNT=$(echo "$PENDING_DNF" | grep -v '^$' | wc -l)
        FP_COUNT=$(echo "$PENDING_FP" | grep -v '^$' | wc -l)
        TOTAL_COUNT=$((DNF_COUNT + FP_COUNT))
        
        # Build the formatted Display List
        DISPLAY_LIST=""
        if [[ ! -z "$PENDING_DNF" ]]; then
            DISPLAY_LIST+="<b>[Packages]</b>\n$PENDING_DNF"
        fi
        if [[ ! -z "$PENDING_FP" ]]; then
            # Add spacing if DNF list exists
            [[ ! -z "$DISPLAY_LIST" ]] && DISPLAY_LIST+="\n\n"
            DISPLAY_LIST+="<b>[Flatpaks]</b>\n$PENDING_FP"
        fi

        # Pre-Update Notification
        notify-send -t 15000 "Updates Detected ($TOTAL_COUNT)" "$DISPLAY_LIST"

        # 3. Run Update
        TEMP_SYNC_LOG=$(mktemp)
        sudo nobara-sync cli | tee "$TEMP_SYNC_LOG" >> "$LOGFILE_GENERAL" 2>&1
        EXIT_CODE=${PIPESTATUS[0]}

        if [ $EXIT_CODE -eq 0 ] || grep -aiE "Complete!|All Updates complete" "$TEMP_SYNC_LOG" > /dev/null; then
            # 4. Post-Update Housekeeping
            sudo dnf autoremove -y >> "$LOGFILE_GENERAL" 2>&1
            sudo dnf clean packages >> "$LOGFILE_GENERAL" 2>&1
            sudo flatpak uninstall --unused -y >> "$LOGFILE_GENERAL" 2>&1
            flatpak uninstall --user --unused -y >> "$LOGFILE_GENERAL" 2>&1
            
            # Log to History CSV
            [[ ! -z "$PENDING_DNF" ]] && echo "$PENDING_DNF" | awk -v dt="$(date '+%Y-%m-%d')" 'NF {print dt ",DNF," $0}' >> "$HISTORY_LOG"
            [[ ! -z "$PENDING_FP" ]] && echo "$PENDING_FP" | awk -v dt="$(date '+%Y-%m-%d')" 'NF {print dt ",Flatpak," $0}' >> "$HISTORY_LOG"
            
            # Final Success Notification
            notify-send -t 0 "Updates Complete" "Successfully updated $TOTAL_COUNT items:\n\n$DISPLAY_LIST"
        else
            notify-send -u critical -t 0 "Auto-updates" "Update failed! Check logs at $LOGFILE_GENERAL"
        fi
        rm -f "$TEMP_SYNC_LOG"
    fi

    rm -f "$LIST_TMP"
    sleep 1h
done
