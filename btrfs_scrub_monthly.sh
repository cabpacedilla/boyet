#!/usr/bin/env bash
# Monthly Btrfs Scrub Script – Production Ready 2026 Edition
# Designed for both standalone daemon mode AND systemd timer mode
# SSD/NVMe friendly with idle I/O priority, resume support, and timeout protection.
set -euo pipefail

# --- Configuration ---
: "${LOG_DIR:=$HOME/scriptlogs}"
: "${MOUNTPOINT:=/}"
: "${SCRUB_INTERVAL_DAYS:=30}"
: "${NOTIFICATIONS:=true}"
: "${ALLOW_SYSTEMD_NOTIFY:=false}"
: "${SLEEP_HOURS:=1}"
: "${SCRUB_TIMEOUT_HOURS:=12}"
: "${LOG_RETENTION_DAYS:=365}"
: "${SCRUB_COOLDOWN_HOURS:=24}"  # Prevent resume storms after timeout

# Validate configuration
if [[ ! "$SCRUB_INTERVAL_DAYS" =~ ^[0-9]+$ ]] || [[ "$SCRUB_INTERVAL_DAYS" -lt 1 ]]; then
    echo "ERROR: SCRUB_INTERVAL_DAYS must be a positive integer" >&2
    exit 1
fi

if [[ ! "$SCRUB_TIMEOUT_HOURS" =~ ^[0-9]+$ ]] || [[ "$SCRUB_TIMEOUT_HOURS" -lt 1 ]]; then
    echo "ERROR: SCRUB_TIMEOUT_HOURS must be a positive integer" >&2
    exit 1
fi

# --- Prerequisite Checks ---
if ! command -v btrfs >/dev/null 2>&1; then
    echo "ERROR: btrfs command not found - please install btrfs-progs" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
LAST_RUN_FILE="$LOG_DIR/btrfs-scrub-last-run"
LAST_ATTEMPT_FILE="$LOG_DIR/btrfs-scrub-last-attempt"
LAST_ROTATE_FILE="$LOG_DIR/.last_log_rotate"
LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m).log"

# Detect if running as systemd service
if [[ -n "${INVOCATION_ID:-}" ]] || [[ -n "${JOURNAL_STREAM:-}" ]]; then
    SYSTEMD_MODE=true
else
    SYSTEMD_MODE=false
fi

# --- Log Rotation (max once per day) ---
rotate_logs_if_needed() {
    local NOW=$(date +%s)
    local LAST_ROTATE=$(cat "$LAST_ROTATE_FILE" 2>/dev/null || echo "0")
    
    if (( NOW - LAST_ROTATE > 86400 )); then
        find "$LOG_DIR" -name "btrfs-scrub-*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
        date +%s > "$LAST_ROTATE_FILE"
    fi
}

# --- Locking Strategy (only for daemon mode) ---
if [[ "$SYSTEMD_MODE" == "false" ]]; then
    LOCK_FILE="/tmp/btrfs_scrub_monthly_$(whoami).lock"
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "Another instance is already running" | tee -a "$LOGFILE"
        exit 1
    fi
fi

# --- Helper Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

notify() {
    [[ "${NOTIFICATIONS}" == "true" ]] || return 0
    
    # Skip notifications in systemd mode unless explicitly allowed
    if [[ "$SYSTEMD_MODE" == "true" ]] && [[ "$ALLOW_SYSTEMD_NOTIFY" != "true" ]]; then
        log "Skipping notification (systemd mode, ALLOW_SYSTEMD_NOTIFY=false)"
        return 0
    fi
    
    command -v notify-send >/dev/null || return 0
    
    # Don't attempt notifications in headless environments
    if [[ -z "${DISPLAY:-}" ]]; then
        log "Skipping notification (no DISPLAY)"
        return 0
    fi

    if [[ "$1" == "-u" ]]; then
        notify-send -u "$2" -t 0 "$3" "$4" 2>/dev/null || true
    else
        notify-send -u normal -t 0 "$1" "$2" 2>/dev/null || true
    fi
}

cleanup() {
    if [[ "$SYSTEMD_MODE" == "false" ]]; then
        log "Daemon exiting. Releasing lock."
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
    fi
}

# --- Safe Command Wrappers ---
# Check if ionice is available (using array for safe expansion)
IONICE_CMD=()
if command -v ionice >/dev/null 2>&1; then
    IONICE_CMD=(ionice -c3)
    log "ionice available - will use idle I/O priority"
else
    log "ionice not available - skipping I/O priority setting"
fi

# Smart sudo detection - avoid sudo when running as root
if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
    log "Running as root - no sudo needed"
elif sudo -n true 2>/dev/null; then
    SUDO_CMD="sudo -n"
    log "Non-interactive sudo available"
else
    SUDO_CMD="sudo"
    log "WARNING: Non-interactive sudo not available - may prompt for password"
fi

# --- Trap Handling ---
trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT

# --- Scrub Execution (shared logic) ---
perform_scrub() {
    # Check for cooldown period (prevent resume storms)
    local NOW=$(date +%s)
    local LAST_ATTEMPT=$(cat "$LAST_ATTEMPT_FILE" 2>/dev/null || echo "0")
    
    if (( NOW - LAST_ATTEMPT < SCRUB_COOLDOWN_HOURS * 3600 )); then
        log "Recent scrub attempt detected (${SCRUB_COOLDOWN_HOURS}h cooldown), delaying retry"
        return 1
    fi
    date +%s > "$LAST_ATTEMPT_FILE"
    
    # Check scrub status using strict matching
    local SCRUB_STATUS=$($SUDO_CMD btrfs scrub status "$MOUNTPOINT" 2>/dev/null || echo "")
    
    if echo "$SCRUB_STATUS" | grep -q "running"; then
        log "Scrub already active in background. Waiting..."
        return 1
    fi

    local SCRUB_CMD="start"
    if echo "$SCRUB_STATUS" | grep -qiE "was aborted|cancelled|interrupted"; then
        SCRUB_CMD="resume"
        log "Detected interrupted scrub, will resume"
    fi
    
    log "Action: Executing $SCRUB_CMD"
    notify "Btrfs Maintenance" "Performing monthly $SCRUB_CMD..."
    
    local SCRUB_START=$(date +%s)

    # Execute scrub with timeout, low I/O priority, and proper signal propagation
    set +e
    timeout --kill-after=30s ${SCRUB_TIMEOUT_HOURS}h "${IONICE_CMD[@]}" nice -n 19 $SUDO_CMD btrfs scrub "$SCRUB_CMD" -B "$MOUNTPOINT" >> "$LOGFILE" 2>&1
    local SCRUB_EXIT=$?
    set -e
    
    local SCRUB_END=$(date +%s)
    local SCRUB_DURATION=$((SCRUB_END - SCRUB_START))
    
    # Check if scrub is still running in background after timeout
    if [[ $SCRUB_EXIT -eq 124 ]]; then
        if $SUDO_CMD btrfs scrub status "$MOUNTPOINT" 2>/dev/null | grep -q "running"; then
            log "Scrub continues in background after timeout (will resume monitoring)"
            # Clear attempt file since scrub is still active
            rm -f "$LAST_ATTEMPT_FILE" 2>/dev/null || true
            return 0
        fi
        log "Scrub timed out after ${SCRUB_TIMEOUT_HOURS} hours and is not running"
        notify -u critical "Btrfs Timeout" "Scrub exceeded ${SCRUB_TIMEOUT_HOURS} hour timeout"
        return 1
    fi
    
    case $SCRUB_EXIT in
        0)
            # Get machine-readable status for reliable parsing
            local FINAL_REPORT=$($SUDO_CMD btrfs scrub status -d "$MOUNTPOINT" 2>/dev/null)
            
            # Parse errors from machine-readable output (more reliable)
            local ERRORS_FOUND=$(echo "$FINAL_REPORT" | awk '/errors/ {print $NF}' | head -1)
            
            if [[ -z "$ERRORS_FOUND" ]]; then
                # Fallback to human-readable parsing
                ERRORS_FOUND=$(echo "$FINAL_REPORT" | awk -F: '/errors found/ {print $2}' | tr -d ' ' | head -1)
            fi
            
            if [[ -z "$ERRORS_FOUND" ]]; then
                log "Could not parse error count from scrub output"
                ERRORS_FOUND="unknown"
            fi
            
            if [[ "$ERRORS_FOUND" =~ ^0$ ]]; then
                local DATA_SCRUBBED=$(echo "$FINAL_REPORT" | awk -F: '/Total to scrub/ {print $2}' | tr -d ' ' | sed 's/[^0-9.]//g' || echo "unknown")
                log "Scrub completed successfully in ${SCRUB_DURATION}s. Data scrubbed: $DATA_SCRUBBED"
                date +%s > "$LAST_RUN_FILE"
                notify "Btrfs Scrub Complete" "System integrity verified. No errors found."
                # Clear attempt file on success
                rm -f "$LAST_ATTEMPT_FILE" 2>/dev/null || true
            else
                log "Scrub finished with errors (count: $ERRORS_FOUND). Duration: ${SCRUB_DURATION}s. Check $LOGFILE"
                notify -u critical "Btrfs Error" "Integrity issues found on $MOUNTPOINT (errors: $ERRORS_FOUND)"
            fi
            ;;
        *)
            log "Scrub process failed with exit code $SCRUB_EXIT (duration: ${SCRUB_DURATION}s)"
            if [[ $SCRUB_EXIT -eq 1 ]]; then
                notify -u critical "Btrfs Error" "Scrub failed to complete properly"
            fi
            ;;
    esac
}

# --- Run Once Mode (for systemd timer) ---
run_once() {
    log "Running single scrub check (systemd timer mode)"
    rotate_logs_if_needed
    
    # Check if mount point exists
    if ! mountpoint -q "$MOUNTPOINT"; then
        log "$MOUNTPOINT not available"
        exit 1
    fi
    
    # Verify it's actually a Btrfs filesystem
    if ! findmnt -n -o FSTYPE "$MOUNTPOINT" 2>/dev/null | grep -q btrfs; then
        log "$MOUNTPOINT is not a Btrfs filesystem"
        exit 1
    fi
    
    # Read and validate last run timestamp
    local LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
    if [[ ! "$LAST_RUN" =~ ^[0-9]+$ ]]; then
        log "Invalid last_run timestamp: '$LAST_RUN', resetting to 0"
        LAST_RUN=0
    fi
    
    local NOW=$(date +%s)
    
    # Handle clock skew
    if (( NOW < LAST_RUN )); then
        log "System clock moved backwards, resetting last_run"
        LAST_RUN=0
        date +%s > "$LAST_RUN_FILE"
    fi
    
    local DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))
    
    if [[ "$DIFF_DAYS" -ge "$SCRUB_INTERVAL_DAYS" ]]; then
        perform_scrub
    else
        log "No scrub needed (last run: $((DIFF_DAYS)) days ago, threshold: $SCRUB_INTERVAL_DAYS)"
        exit 0
    fi
}

# --- Main Execution ---
main() {
    # Check for --once flag (systemd timer mode)
    if [[ "${1:-}" == "--once" ]]; then
        run_once
        exit $?
    fi
    
    # Daemon mode (original while loop)
    local FIRST_RUN=1
    
    while true; do
        LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m).log"
        rotate_logs_if_needed
        
        if [[ $FIRST_RUN -eq 1 ]]; then
            log "Btrfs scrub daemon started (Interval: ${SCRUB_INTERVAL_DAYS} days)"
            log "Monitoring $MOUNTPOINT, notifications: $NOTIFICATIONS"
            log "Timeout: ${SCRUB_TIMEOUT_HOURS} hours, Cooldown: ${SCRUB_COOLDOWN_HOURS} hours"
            FIRST_RUN=0
        fi

        # Check if mount point exists
        if ! mountpoint -q "$MOUNTPOINT"; then
            log "$MOUNTPOINT not available, retrying in ${SLEEP_HOURS}h"
            sleep $((SLEEP_HOURS * 3600))
            continue
        fi
        
        # Verify it's actually a Btrfs filesystem
        if ! findmnt -n -o FSTYPE "$MOUNTPOINT" 2>/dev/null | grep -q btrfs; then
            log "$MOUNTPOINT is not a Btrfs filesystem, skipping"
            sleep $((SLEEP_HOURS * 3600))
            continue
        fi

        # Read and validate last run timestamp
        local LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
        if [[ ! "$LAST_RUN" =~ ^[0-9]+$ ]]; then
            log "Invalid last_run timestamp: '$LAST_RUN', resetting to 0"
            LAST_RUN=0
        fi
        
        local NOW=$(date +%s)
        
        # Handle clock skew
        if (( NOW < LAST_RUN )); then
            log "System clock moved backwards (LAST_RUN=$LAST_RUN, NOW=$NOW), resetting last_run"
            LAST_RUN=0
            date +%s > "$LAST_RUN_FILE"
        fi
        
        local DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))

        if [[ "$DIFF_DAYS" -ge "$SCRUB_INTERVAL_DAYS" ]]; then
            perform_scrub
        fi

        sleep $((SLEEP_HOURS * 3600))
    done
}

# Run main with command line arguments
main "$@"
