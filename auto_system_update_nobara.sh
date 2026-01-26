#!/usr/bin/env bash
# Nobara Auto-Update Daemon
# Detects updates via DNF and verifies success via Nobara-Sync logs.

LOGFILE_GENERAL="$HOME/scriptlogs/general_update_log.txt"
LIST="$HOME/scriptlogs/updateable.txt"

mkdir -p "$HOME/scriptlogs"

while true; do
    log_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$log_time - Checking for updates..." >> "$LOGFILE_GENERAL"

    # 1. Detection Phase: Exit code 100 means updates are available
    sudo dnf check-update > "$LIST.tmp"
    CHECK_EXIT=$?

    if [ $CHECK_EXIT -eq 100 ]; then
        # PRE-UPDATE NOTIFICATION: One package per line with version
        PENDING_LIST=$(grep -E '^[a-zA-Z0-9]' "$LIST.tmp" | awk '{print $1 " (" $2 ")"}' | sort)
        
        notify-send -t 0 "Updates Detected" "The following packages are ready to update:\n$PENDING_LIST"
        notify-send "Auto-updates" "Launching system maintenance via nobara-sync cli..."

        # 2. Execution Phase: nobara-sync cli
        TEMP_SYNC_LOG=$(mktemp)

        # Runs the update and pipes output to logs
        sudo nobara-sync cli | tee "$TEMP_SYNC_LOG" >> "$LOGFILE_GENERAL" 2>&1

        # 3. Verification and Extraction Phase
        if grep -q "All Updates complete!" "$TEMP_SYNC_LOG"; then

            # Scrape the package names from the "Upgrading:" section
            UPDATED_LIST=$(sed -n '/Upgrading:/,/Transaction Summary:/p' "$TEMP_SYNC_LOG" | \
                           grep "INFO -" | \
                           grep -vE "Upgrading:|Transaction Summary:|replacing" | \
                           awk -F 'INFO - ' '{print $2}' | \
                           awk '{print $1}' | xargs)

            if [ -z "$UPDATED_LIST" ]; then
                UPDATED_LIST="System and Flatpak components"
            fi

            echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS. Updated: $UPDATED_LIST" >> "$LOGFILE_GENERAL"
            notify-send -t 0 "Updates Complete" "Verified success.\n\nPackages updated:\n$UPDATED_LIST"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Completion message missing." >> "$LOGFILE_GENERAL"
            notify-send -u critical "Auto-updates" "Update failed or interrupted. Check $LOGFILE_GENERAL"
        fi

        rm -f "$TEMP_SYNC_LOG"

    elif [ $CHECK_EXIT -eq 0 ]; then
        # NOTIFICATION FOR SYSTEM UP TO DATE
        echo "$log_time - System up to date." >> "$LOGFILE_GENERAL"
        notify-send -t 5000 "Auto-updates" "System is already up to date."
    else
        # NOTIFICATION FOR DNF ERROR
        echo "$log_time - Error during dnf check (Exit: $CHECK_EXIT)" >> "$LOGFILE_GENERAL"
        notify-send -u critical "Auto-updates" "Error checking for updates (Exit code: $CHECK_EXIT). Check your connection or $LOGFILE_GENERAL."
    fi

    # Cleanup and wait
    rm -f "$LIST.tmp"
    sleep 1h
done
