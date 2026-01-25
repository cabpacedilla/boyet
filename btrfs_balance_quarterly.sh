#!/usr/bin/env bash
# Btrfs Balance Script – Twice-a-year, SSD/NVMe friendly (2026 edition)
# Gentle data-only balance, metadata avoided unless really needed

set -o pipefail
set -u

# Configurable via environment variables
: "${LOG_DIR:=$HOME/scriptlogs}"
: "${BALANCE_INTERVAL_DAYS:=180}"
: "${DATA_USAGE_THRESHOLD:=50}"
: "${MIN_FREE_GB:=15}"
: "${MAX_RETRIES:=24}"
: "${RETRY_STALE_DAYS:=200}"    # Slightly > interval to allow new cycle
: "${MOUNTPOINT:=/}"
: "${NOTIFICATIONS:=true}"

mkdir -p "$LOG_DIR"
LAST_RUN_FILE="$LOG_DIR/btrfs-balance-last-run"
RETRY_COUNT_FILE="$LOG_DIR/btrfs-balance-retry-count"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

while true; do
    # Monthly log file with automatic cleanup
    LOGFILE="$LOG_DIR/btrfs-balance-$(date +%Y-%m).log"
    find "$LOG_DIR" -name "btrfs-balance-*.log" -mtime +365 -delete 2>/dev/null || true

    # Initial log only on first loop iteration of each check
    log "Btrfs balance daemon active (interval: ${BALANCE_INTERVAL_DAYS} days, dusage=${DATA_USAGE_THRESHOLD})"

    NOW=$(date +%s)

    # Mountpoint validation
    if [[ ! -d "$MOUNTPOINT" ]] || ! mountpoint -q "$MOUNTPOINT"; then
        log "⚠️ $MOUNTPOINT not available, skipping"
        sleep 3600
        continue
    fi

    # Filesystem type check
    if ! findmnt -no FSTYPE "$MOUNTPOINT" 2>/dev/null | grep -q "^btrfs$"; then
        log "⚠️ $MOUNTPOINT is not Btrfs, skipping"
        sleep 3600
        continue
    fi

    # Determine days since last successful run
    if [[ -f "$LAST_RUN_FILE" ]]; then
        LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
        DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))
    else
        DIFF_DAYS=9999
    fi

    # Only proceed if balance interval has passed
    if [[ "$DIFF_DAYS" -ge "$BALANCE_INTERVAL_DAYS" ]]; then
        log "Starting gentle balance on $MOUNTPOINT (days since last: $DIFF_DAYS)"

        # Load and validate retry counter
        RETRY_COUNT=0
        if [[ -f "$RETRY_COUNT_FILE" ]]; then
            RETRY_COUNT=$(cat "$RETRY_COUNT_FILE" 2>/dev/null || echo "0")
            # Reset retry count if we're in a new cycle
            if [[ "$DIFF_DAYS" -gt "$RETRY_STALE_DAYS" ]]; then
                rm -f "$RETRY_COUNT_FILE"
                RETRY_COUNT=0
                log "🔄 Resetting stale retry count for new cycle"
            fi
        fi

        # Check if we've exhausted retries
        if [[ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]]; then
            log "🛑 Max retries reached. Manual check required."
            [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1 && \
                notify-send -u critical "🛑 Btrfs Balance" "Max retries reached – check logs!"
            sleep 3600
            continue
        fi

        # Free space check (robust parsing)
        AVAILABLE_BYTES=$(df -B1 --output=avail "$MOUNTPOINT" 2>/dev/null | awk 'NR==2 && $1 ~ /^[0-9]+$/ {print $1}')
        if [[ -z "$AVAILABLE_BYTES" ]]; then
            log "⚠️ Failed to read free space – retry later"
            sleep 3600
            continue
        fi
        AVAILABLE_GB=$(( AVAILABLE_BYTES / 1024 / 1024 / 1024 ))

        if [[ "$AVAILABLE_GB" -lt "$MIN_FREE_GB" ]]; then
            log "⚠️ Low space (${AVAILABLE_GB}GB < ${MIN_FREE_GB}GB) – retry later"
            [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1 && \
                notify-send "⚠️ Btrfs Balance" "Skipped: low free space (${AVAILABLE_GB}GB)"
            # Note: Not counting this as a retry since it's a pre-condition, not a balance failure
            sleep 3600
            continue
        fi

        # Check for already running balance
        if sudo btrfs balance status "$MOUNTPOINT" 2>&1 | grep -q "is running"; then
            log "Balance already in progress – skipping"
            sleep 3600
            continue
        fi

        # Log pre-balance state
        log "Pre-balance filesystem usage:"
        sudo btrfs filesystem usage "$MOUNTPOINT" >> "$LOGFILE" 2>&1

        # Send start notification
        [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1 && \
            notify-send "🧹 Btrfs Maintenance" "Starting gentle balance…"

        # Execute balance
        BALANCE_FAILED=0
        log "Running data balance (dusage=${DATA_USAGE_THRESHOLD})"
        if ! sudo ionice -c3 nice -n 19 \
            btrfs balance start -B -dusage="${DATA_USAGE_THRESHOLD}" "$MOUNTPOINT" \
            >> "$LOGFILE" 2>&1; then
            log "❌ Data balance failed – see $LOGFILE for btrfs error details"
            BALANCE_FAILED=1
        fi

        # Handle result
        if [[ "$BALANCE_FAILED" -eq 0 ]]; then
            log "✅ Balance completed successfully"
            [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1 && \
                notify-send "✅ Btrfs Balance" "Gentle balance finished"
            sudo btrfs filesystem usage "$MOUNTPOINT" >> "$LOGFILE" 2>&1
            date +%s > "$LAST_RUN_FILE"
            rm -f "$RETRY_COUNT_FILE"
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "$RETRY_COUNT" > "$RETRY_COUNT_FILE"
            log "❌ Balance failed (attempt ${RETRY_COUNT}/${MAX_RETRIES}) – retrying later"
            [[ "$NOTIFICATIONS" == "true" ]] && command -v notify-send >/dev/null 2>&1 && \
                notify-send -u critical "⚠️ Btrfs Balance" "Failed (attempt ${RETRY_COUNT}/${MAX_RETRIES}) – retrying"
        fi
    else
        log "Not yet time for balance (${DIFF_DAYS}/${BALANCE_INTERVAL_DAYS} days)"
    fi

    sleep 3600
done
