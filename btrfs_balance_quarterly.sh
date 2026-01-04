#!/usr/bin/env bash

# 1. Define Logging Functions (Must be at the top)
log_info() {
    local MESSAGE="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] - $1"
    echo -e "$MESSAGE" | tee -a "$LOGFILE"
}

# Ensure the log directory exists
mkdir -p "$HOME/scriptlogs"

while true; do
    LAST_RUN_FILE="$HOME/scriptlogs/btrfs-balance-last-run"
    LOGFILE="$HOME/scriptlogs/btrfs-balance-$(date +%Y-%m-%d).log"
    NOW=$(date +%s)

    if [ -f "$LAST_RUN_FILE" ]; then
        LAST_RUN=$(cat "$LAST_RUN_FILE")
        DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))
    else
        DIFF_DAYS=9999
    fi

    if [ "$DIFF_DAYS" -ge 120 ]; then
        log_info "Starting Btrfs balance on /"
        notify-send "✅ Btrfs Balance" "Starting Btrfs balance on /."

        log_info "Running: safe filtered Data balance (-dusage=10)..."
        sudo btrfs balance start -dusage=10 / >> "$LOGFILE" 2>&1

        log_info "Running: safe Metadata balance (-musage=5)..."
        sudo btrfs balance start -musage=5 / >> "$LOGFILE" 2>&1

        log_info "Recording filesystem usage after balance:"
        sudo btrfs filesystem usage / >> "$LOGFILE"
        
        log_info "Btrfs balance completed successfully."
        notify-send "✅ Btrfs Balance" "Completed successfully."
        date +%s > "$LAST_RUN_FILE"
    else
        # We don't want to spam the log file every day while sleeping
        # so we only log the "Skip" to the console, or remove this line entirely.
        echo "Check: Only $DIFF_DAYS days since last balance. Sleeping..."
    fi

    # Wait 24 hours before checking again
    sleep 86400
done
