#!/usr/bin/env bash
# Monthly Btrfs Scrub Script - SSD Optimized
# Runs a scrub every 30 days with proper error detection and SSD-friendly I/O

set -o pipefail

LOG_DIR="$HOME/scriptlogs"
LAST_RUN_FILE="$LOG_DIR/btrfs-scrub-last-run"
MOUNTPOINT="/"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

while true; do
    LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m-%d).log"
    NOW=$(date +%s)

    if [[ -f "$LAST_RUN_FILE" ]]; then
        LAST_RUN=$(cat "$LAST_RUN_FILE")
        DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))
    else
        DIFF_DAYS=9999
    fi

    if [[ "$DIFF_DAYS" -ge 30 ]]; then
        log "Starting monthly Btrfs scrub on $MOUNTPOINT"
        notify-send "🛡️ Btrfs Maintenance" "Starting monthly scrub (SSD-friendly mode)…"

        # Check if scrub is already running
        if sudo btrfs scrub status "$MOUNTPOINT" 2>&1 | grep -q "running"; then
            log "Scrub already running. Skipping."
            sleep 3600
            continue
        fi

        # Run scrub with low I/O priority to reduce SSD wear
        log "Running scrub with ionice class 3 (idle priority)"
        if sudo ionice -c3 nice -n 19 btrfs scrub start -Bd "$MOUNTPOINT" >> "$LOGFILE" 2>&1; then
            # Check scrub results
            SCRUB_STATUS=$(sudo btrfs scrub status "$MOUNTPOINT")
            
            if echo "$SCRUB_STATUS" | grep -qE "total errors: 0|no errors found"; then
                log "✅ Scrub completed cleanly (no errors)."
                notify-send "✅ Btrfs Scrub" "Scrub completed with no errors."
            else
                log "⚠️  Scrub completed WITH ERRORS!"
                echo "$SCRUB_STATUS" >> "$LOGFILE"
                notify-send -u critical "⚠️ Btrfs Scrub" "Errors detected during scrub. Check logs!"
            fi
        else
            log "❌ Scrub failed to complete!"
            notify-send -u critical "⚠️ Btrfs Scrub" "Scrub command failed!"
        fi

        log "Post-scrub filesystem usage:"
        sudo btrfs filesystem usage "$MOUNTPOINT" >> "$LOGFILE"

        date +%s > "$LAST_RUN_FILE"
    fi

    sleep 3600
done
