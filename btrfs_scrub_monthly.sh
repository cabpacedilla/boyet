#!/usr/bin/env bash
# Monthly Btrfs Scrub Script – SSD/NVMe friendly (2026 edition)
# Low-impact checksum verification + repair (if possible)

LOCK_FILE="/tmp/btrfs_scrub_monthly_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

set -o pipefail
set -u

# Configurable via environment variables
: "${LOG_DIR:=$HOME/scriptlogs}"
: "${MOUNTPOINT:=/}"
: "${SCRUB_INTERVAL_DAYS:=30}"
: "${NOTIFICATIONS:=true}"
: "${SLEEP_HOURS:=1}"
: "${MIN_FREE_GB_FOR_SCRUB:=1}"   # Optional safety threshold

mkdir -p "$LOG_DIR"
LAST_RUN_FILE="$LOG_DIR/btrfs-scrub-last-run"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Graceful shutdown handling
trap 'log "Received shutdown signal, exiting..."; exit 0' INT TERM

FIRST_RUN=1

while true; do
    LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m).log"
    find "$LOG_DIR" -name "btrfs-scrub-*.log" -mtime +365 -delete 2>/dev/null || true

    if [[ $FIRST_RUN -eq 1 ]]; then
        log "Btrfs scrub daemon started (interval: ${SCRUB_INTERVAL_DAYS} days)"
        FIRST_RUN=0
    fi

    NOW=$(date +%s)

    # Mountpoint and filesystem checks
    if [[ ! -d "$MOUNTPOINT" ]] || ! mountpoint -q "$MOUNTPOINT"; then
        log "⚠️ $MOUNTPOINT not available, skipping"
        sleep $((SLEEP_HOURS * 3600))
        continue
    fi

    if ! findmnt -no FSTYPE "$MOUNTPOINT" 2>/dev/null | grep -q "^btrfs$"; then
        log "⚠️ $MOUNTPOINT is not Btrfs, skipping"
        sleep $((SLEEP_HOURS * 3600))
        continue
    fi

    # Optional: minimal free space safety net
    AVAILABLE_BYTES=$(df -B1 --output=avail "$MOUNTPOINT" 2>/dev/null | awk 'NR==2 {print $1}')
    AVAILABLE_GB=$(( AVAILABLE_BYTES / 1024 / 1024 / 1024 ))
    if [[ "$AVAILABLE_GB" -lt "$MIN_FREE_GB_FOR_SCRUB" ]]; then
        log "⚠️ Extremely low free space (${AVAILABLE_GB}GB < ${MIN_FREE_GB_FOR_SCRUB}GB) – skipping scrub"
        sleep $((SLEEP_HOURS * 3600))
        continue
    fi

    # Days since last successful scrub
    if [[ -f "$LAST_RUN_FILE" ]]; then
        LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
        DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))
    else
        DIFF_DAYS=9999
    fi

    if [[ "$DIFF_DAYS" -ge "$SCRUB_INTERVAL_DAYS" ]]; then
        log "Starting monthly scrub on $MOUNTPOINT (days since last: $DIFF_DAYS)"

        if [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1; then
            notify-send "🛡️ Btrfs Maintenance" "Starting monthly scrub…"
        fi

        # Skip if scrub already running
        if sudo btrfs scrub status "$MOUNTPOINT" 2>&1 | grep -q "running"; then
            log "Scrub already in progress – skipping this cycle"
            sleep $((SLEEP_HOURS * 3600))
            continue
        fi

        log "Executing scrub with idle I/O priority"
        SCRUB_SUCCESS=false
        
        if sudo ionice -c3 nice -n 19 \
            btrfs scrub start -B "$MOUNTPOINT" >> "$LOGFILE" 2>&1; then

            sleep 2  # Brief pause to allow status to finalize

            SCRUB_STATUS=$(sudo btrfs scrub status "$MOUNTPOINT" 2>/dev/null || echo "")
            log "Scrub status report:"
            echo "$SCRUB_STATUS" >> "$LOGFILE"

            # Robust success detection (covers common output patterns across versions)
            if echo "$SCRUB_STATUS" | grep -qiE "no errors found|Error summary: *no errors|Corrected: *0[^0-9]|Uncorrectable: *0[^0-9]|Unverified: *0[^0-9]"; then
                log "✅ Scrub completed successfully – no errors detected"
                SCRUB_SUCCESS=true
                if [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1; then
                    notify-send "✅ Btrfs Scrub" "Completed successfully (no errors)"
                fi
            elif echo "$SCRUB_STATUS" | grep -q "csum.*:"; then
                # Parse csum errors specifically
                CSUM_ERRORS=$(echo "$SCRUB_STATUS" | grep -o "csum.*: *[0-9]*" | awk '{print $NF}' | head -1)
                if [[ "$CSUM_ERRORS" -eq 0 ]]; then
                    log "✅ Scrub completed successfully – no csum errors"
                    SCRUB_SUCCESS=true
                    if [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1; then
                        notify-send "✅ Btrfs Scrub" "Completed successfully (no errors)"
                    fi
                else
                    log "⚠️ Scrub finished WITH CSUM ERRORS ($CSUM_ERRORS errors)"
                    if [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1; then
                        notify-send -u critical "⚠️ Btrfs Scrub" "CSUM errors detected ($CSUM_ERRORS)"
                    fi
                fi
            else
                log "⚠️ Scrub finished – unrecognized status format"
                # Conservative: don't mark as success if we can't verify
                if [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1; then
                    notify-send -u low "ℹ️ Btrfs Scrub" "Completed – check log for details"
                fi
            fi
        else
            log "❌ Scrub command failed to execute or complete"
            if [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1; then
                notify-send -u critical "⚠️ Btrfs Scrub" "Scrub failed to start/complete"
            fi
        fi

        # Log post-scrub allocation (useful for debugging)
        log "Post-scrub filesystem usage:"
        sudo btrfs filesystem usage "$MOUNTPOINT" >> "$LOGFILE" 2>&1

        # Only mark as successful run if scrub completed without errors
        if [[ "$SCRUB_SUCCESS" == "true" ]]; then
            date +%s > "$LAST_RUN_FILE"
            log "✅ Updated last run timestamp"
        else
            log "⚠️ Not updating last run timestamp (errors or incomplete)"
        fi
    fi

    sleep $((SLEEP_HOURS * 3600))
done
