#!/usr/bin/env bash

while true; do

    # File to store the last run date
    LAST_RUN_FILE="$HOME/scriptlogs/btrfs-balance-last-run"
    LOGFILE="$HOME/scriptlogs/btrfs-balance-$(date +%Y-%m-%d).log"

    # Get the current and last run dates
    NOW=$(date +%s)

    if [ -f "$LAST_RUN_FILE" ]; then
        LAST_RUN=$(cat "$LAST_RUN_FILE")
        # Calculate difference in days (~120 days for 4 months)
        DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))
    else
        DIFF_DAYS=9999
    fi

    if [ "$DIFF_DAYS" -ge 120 ]; then
        echo -e "\n[$(date)] Starting Btrfs balance on /" | tee -a "$LOGFILE"
        notify-send "✅ Btrfs Balance" "Starting Btrfs balance on / at $(date)."
        sudo btrfs balance start / >> "$LOGFILE" 2>&1
        echo "[$(date)] Btrfs balance completed" | tee -a "$LOGFILE"
        notify-send "✅ Btrfs Balance" "Btrfs balance completed at $(date)."
        date +%s > "$LAST_RUN_FILE"
    else
        echo -e "\n[$(date)] Less than 4 months since last balance. Skipping." | tee -a "$LOGFILE"
    fi

    sleep 86400
done
