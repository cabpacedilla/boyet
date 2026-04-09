#!/usr/bin/env bash
# Btrfs Balance Script – Twice-a-year, SSD/NVMe friendly (2026 edition)
# Gentle data-only balance, metadata avoided unless really needed

# --- Locking & Cleanup ---
LOCK_FILE="/tmp/btrfs_balance_quarterly_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT

set -o pipefail
set -u

# --- Configuration ---
: "${LOG_DIR:=$HOME/scriptlogs}"
: "${BALANCE_INTERVAL_DAYS:=180}"
: "${DATA_USAGE_THRESHOLD:=15}"
: "${MIN_FREE_GB:=15}"
: "${MAX_RETRIES:=24}"
: "${RETRY_STALE_DAYS:=200}"
: "${MOUNTPOINT:=/}"
: "${NOTIFICATIONS:=true}"

mkdir -p "$LOG_DIR"
LAST_RUN_FILE="$LOG_DIR/btrfs-balance-last-run"
RETRY_COUNT_FILE="$LOG_DIR/btrfs-balance-retry-count"

log() {
    LOGFILE="$LOG_DIR/btrfs-balance-$(date +%Y-%m).log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

notify() {
    [[ "${NOTIFICATIONS}" == "true" ]] || return 0
    command -v notify-send >/dev/null || return 0

    if [[ "$1" == "-u" ]]; then
        local urgency="$2"
        local title="$3"
        local message="$4"
        local icon="drive-harddisk"

        case "$urgency" in
            critical) icon="dialog-error" ;;
            normal)   icon="drive-harddisk" ;;
            low)      icon="task-accepted" ;;
        esac

        notify-send -i "$icon" -u "$urgency" -t 0 "$title" "$message"
    else
        notify-send -i "task-accepted" -u normal -t 0 "Btrfs Balance" "$1"
    fi
}

# --- Main Loop ---
while true; do
    NOW=$(date +%s)
    LOGFILE="$LOG_DIR/btrfs-balance-$(date +%Y-%m).log"
    SLEEP_DURATION=604800  # Default: 7 days

    # Validations
    if ! mountpoint -q "$MOUNTPOINT"; then
        log "⚠️ $MOUNTPOINT not available, retrying in 1 week"
        sleep 604800 && continue
    fi

    # Filesystem type check - retry if not Btrfs (handles external drives)
    if ! findmnt -no FSTYPE "$MOUNTPOINT" 2>/dev/null | grep -q "^btrfs$"; then
        log "⚠️ $MOUNTPOINT is not Btrfs or not mounted, retrying in 1 week"
        sleep 604800 && continue
    fi

    # Timing Check
    LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
    DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))

    if [[ "$DIFF_DAYS" -ge "$BALANCE_INTERVAL_DAYS" ]]; then
        log "Btrfs balance daemon active (interval: ${BALANCE_INTERVAL_DAYS} days)"
        log "Starting gentle balance on $MOUNTPOINT (days since last: $DIFF_DAYS)"

        # Retry Counter Logic
        RETRY_COUNT=$(cat "$RETRY_COUNT_FILE" 2>/dev/null || echo "0")
        if [[ "$DIFF_DAYS" -gt "$RETRY_STALE_DAYS" ]]; then
            rm -f "$RETRY_COUNT_FILE" && RETRY_COUNT=0
        fi

        if [[ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]]; then
            log "🛑 Max retries reached. Manual intervention required."
            notify -u critical "Balance Error" "Max retries reached – check logs!"
            SLEEP_DURATION=2592000  # 30 days
        else
            # Space Check
            AVAILABLE_GB=$(df -BG --output=avail "$MOUNTPOINT" 2>/dev/null | tail -n1 | tr -d 'G ')
            AVAILABLE_GB=${AVAILABLE_GB:-0}
            if [[ "$AVAILABLE_GB" -lt "$MIN_FREE_GB" ]]; then
                log "⚠️ Low space (${AVAILABLE_GB}GB < ${MIN_FREE_GB}GB)"
                notify -u critical "Balance Skipped" "Low space: ${AVAILABLE_GB}GB available."
                sleep 604800 && continue
            fi

            # Check for active balance
            if sudo btrfs balance status "$MOUNTPOINT" 2>&1 | grep -q "is running"; then
                log "Balance already in progress – skipping"
                sleep 604800 && continue
            fi

            notify "Starting gentle balance (dusage=${DATA_USAGE_THRESHOLD})..."

            # Execute
            if sudo ionice -c3 nice -n 19 \
                btrfs balance start -B -dusage="${DATA_USAGE_THRESHOLD}" "$MOUNTPOINT" \
                >> "$LOGFILE" 2>&1; then

                log "✅ Balance completed successfully"
                notify "✅ Gentle balance finished"
                date +%s > "$LAST_RUN_FILE"
                rm -f "$RETRY_COUNT_FILE"
            else
                RETRY_COUNT=$((RETRY_COUNT + 1))
                echo "$RETRY_COUNT" > "$RETRY_COUNT_FILE"
                log "❌ Balance failed (attempt ${RETRY_COUNT}/${MAX_RETRIES})"
                notify -u critical "⚠️ Balance Failed" "Attempt ${RETRY_COUNT}/${MAX_RETRIES}"
            fi
        fi
    fi

    sleep "$SLEEP_DURATION"
done
