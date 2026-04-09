#!/usr/bin/env bash
# Monthly Btrfs Scrub Script – Refined 2026 Edition (Final Stable)
# SSD/NVMe friendly with idle I/O priority and resume support.
set -euo pipefail

# --- Pre-Loop Initialization ---
: "${LOG_DIR:=$HOME/scriptlogs}"
: "${MOUNTPOINT:=/}"
: "${SCRUB_INTERVAL_DAYS:=30}"
: "${NOTIFICATIONS:=true}"
: "${SLEEP_HOURS:=1}"

# Validate configuration
if [[ ! "$SCRUB_INTERVAL_DAYS" =~ ^[0-9]+$ ]] || [[ "$SCRUB_INTERVAL_DAYS" -lt 1 ]]; then
    echo "ERROR: SCRUB_INTERVAL_DAYS must be a positive integer" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
LAST_RUN_FILE="$LOG_DIR/btrfs-scrub-last-run"
LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m).log"

# --- Locking Strategy (commented out) ---
LOCK_FILE="/tmp/btrfs_scrub_monthly_$(whoami).lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 1
fi

# --- Helper Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

notify() {
    [[ "${NOTIFICATIONS}" == "true" ]] || return 0
    command -v notify-send >/dev/null || return 0

    if [[ "$1" == "-u" ]]; then
        # Format: -u urgency title message
        notify-send -u "$2" -t 0 "$3" "$4"
    else
        # Format: title message
        notify-send -u normal -t 0 "$1" "$2"
    fi
}

cleanup() {
    log "Daemon exiting. Releasing lock."
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

# --- Trap Handling ---
trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT

# --- Main Daemon Loop ---
FIRST_RUN=1

while true; do
    LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m).log"
    
    if [[ $FIRST_RUN -eq 1 ]]; then
        log "Btrfs scrub daemon started (Interval: ${SCRUB_INTERVAL_DAYS} days)"
        log "Monitoring $MOUNTPOINT, notifications: $NOTIFICATIONS"
        FIRST_RUN=0
    fi

    if ! mountpoint -q "$MOUNTPOINT"; then
        log "$MOUNTPOINT not available, retrying in ${SLEEP_HOURS}h"
        sleep $((SLEEP_HOURS * 3600))
        continue
    fi

    NOW=$(date +%s)
    LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
    DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))

    if [[ "$DIFF_DAYS" -ge "$SCRUB_INTERVAL_DAYS" ]]; then
        
        # Use sudo for status check
        SCRUB_STATUS=$(sudo btrfs scrub status "$MOUNTPOINT" 2>/dev/null || echo "")
        
        if [[ "$SCRUB_STATUS" == *"running"* ]]; then
            log "Scrub already active in background. Waiting..."
            sleep $((SLEEP_HOURS * 3600))
            continue
        fi

        SCRUB_CMD="start"
        # Robust regex check for various interruption states
        if [[ "$SCRUB_STATUS" =~ (was aborted|cancelled|interrupted) ]]; then
            SCRUB_CMD="resume"
            log "Detected interrupted scrub, will resume"
        fi
        
        log "Action: Executing $SCRUB_CMD (Days since last: $DIFF_DAYS)"
        notify "Btrfs Maintenance" "Performing monthly $SCRUB_CMD..."

        # Execution with low I/O priority
        if ionice -c3 nice -n 19 sudo btrfs scrub "$SCRUB_CMD" -B "$MOUNTPOINT" >> "$LOGFILE" 2>&1; then
            
            FINAL_REPORT=$(sudo btrfs scrub status "$MOUNTPOINT" 2>/dev/null)
            if echo "$FINAL_REPORT" | grep -qiE "no errors found|0 errors"; then
                # Extract statistics for logging
                DATA_SCRUBBED=$(echo "$FINAL_REPORT" | grep "Total to scrub" | awk '{print $4}' || echo "unknown")
                log "Scrub completed successfully. Data scrubbed: $DATA_SCRUBBED"
                date +%s > "$LAST_RUN_FILE"
                notify "Btrfs Scrub Complete" "System integrity verified. No errors found."
            else
                ERROR_COUNT=$(echo "$FINAL_REPORT" | grep -i "error" | grep -v "0 errors" | awk '{print $2}' || echo "unknown")
                log "Scrub finished with errors (count: $ERROR_COUNT). Check $LOGFILE"
                notify -u critical "Btrfs Error" "Integrity issues found on $MOUNTPOINT"
            fi
        else
            exit_code=$?
            log "Scrub process failed with exit code $exit_code"
            if [[ $exit_code -eq 1 ]]; then
                notify -u critical "Btrfs Error" "Scrub failed to complete properly"
            fi
        fi
    fi

    sleep $((SLEEP_HOURS * 3600))
done
