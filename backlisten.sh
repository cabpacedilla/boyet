#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Watchdog for checkservices.sh
# Ensures the main monitor (checkservices.sh) is always running.
# Starts it with high CPU/I/O priority and protects both scripts from OOM killer.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Configuration ---
SCRIPT_NAME="checkservices.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1
COOLDOWN=2   # seconds between checks
LOGFILE="$HOME/scriptlogs/watch_checkservices.log"
LOCKFILE="/tmp/checkservices_watchdog.lock"

# --- Locking to prevent multiple instances ---
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ERROR] Another watchdog instance is running" >&2
    exit 1
fi

# --- Setup ---
mkdir -p "$(dirname "$LOGFILE")" "$(dirname "$LOCKFILE")"

# --- Self-priority setup ---
renice -n -10 -p $$ 2>/dev/null || true
ionice -c2 -n0 -p $$ 2>/dev/null || true
if [[ -w /proc/$$/oom_score_adj ]]; then
    echo -1000 > /proc/$$/oom_score_adj 2>/dev/null || true
fi

# --- Signal handling for clean shutdown ---
cleanup() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Watchdog shutting down" >> "$LOGFILE"
    rm -f "$LOCKFILE"
    exit 0
}
trap cleanup TERM INT EXIT

# --- Process validation function ---
validate_process() {
    local pid="$1"
    # Check if process exists and matches our expected command
    if ps -p "$pid" >/dev/null 2>&1; then
        # Verify it's actually our target script
        if ps -p "$pid" -o command= | grep -qF "Documents/bin/$SCRIPT_NAME"; then
            return 0
        fi
    fi
    return 1
}

# --- Main loop ---
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Watchdog started (PID: $$)" >> "$LOGFILE"

while true; do
    # Get current valid processes
    VALID_PROCS=()
    ALL_PROCS=($(pgrep -f "bin/$SCRIPT_NAME" 2>/dev/null || true))
    
    for pid in "${ALL_PROCS[@]}"; do
        if validate_process "$pid"; then
            VALID_PROCS+=("$pid")
        fi
    done
    
    NUM_RUNNING=${#VALID_PROCS[@]}

    if (( NUM_RUNNING > MIN_INSTANCES )); then
        # Kill older instances, keep the newest (validated)
        PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${VALID_PROCS[@]}" 2>/dev/null | head -n -"$MIN_INSTANCES")
        for pid in $PIDS_TO_KILL; do
            if validate_process "$pid"; then  # Re-validate before killing
                kill "$pid"
                notify-send -t 5000 --app-name "💀 CheckServices Watchdog" \
                    "Extra $SCRIPT_NAME killed: PID $pid" &
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Killed extra $SCRIPT_NAME (PID $pid)" >> "$LOGFILE"
            fi
        done

    elif (( NUM_RUNNING < MIN_INSTANCES )); then
        # Check file existence and permissions atomically
        if [[ -f "$SCRIPT_PATH" && -x "$SCRIPT_PATH" && -r "$SCRIPT_PATH" ]]; then
            # Start process and capture PID atomically
            if nice -n -5 ionice -c2 -n0 "$SCRIPT_PATH" & PID=$!; then
                # Set OOM protection if possible (without sudo)
                if [[ -w /proc/$PID/oom_score_adj ]]; then
                    echo -1000 > /proc/$PID/oom_score_adj 2>/dev/null || \
                        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [WARN] Failed OOM adjust for PID $PID" >> "$LOGFILE"
                fi
                
                # Wait briefly to see if process starts successfully
                sleep 0.5
                if validate_process "$PID"; then
                    notify-send -t 5000 --app-name "✅ CheckServices Watchdog" \
                        "$SCRIPT_NAME started (PID $PID) with high priority + OOM protection." &
                    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Started $SCRIPT_NAME (PID $PID)" >> "$LOGFILE"
                else
                    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ERROR] Process $PID failed to start properly" >> "$LOGFILE"
                fi
            else
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ERROR] Failed to start $SCRIPT_NAME" >> "$LOGFILE"
            fi
        else
            notify-send --app-name "⚠️ CheckServices Watchdog" \
                "$SCRIPT_NAME not found or not executable!" &
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ERROR] Missing or non-executable $SCRIPT_NAME" >> "$LOGFILE"
        fi
    fi

    sleep "$COOLDOWN"
done
