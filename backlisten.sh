#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Watchdog for checkservices.sh
# Ensures the main monitor (checkservices.sh) is always running.
# Starts it with high CPU/I/O priority and protects both scripts from OOM killer.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Self-priority setup ---
# Give this watchdog script high priority and OOM protection
renice -n -10 -p $$ 2>/dev/null || true
ionice -c2 -n0 -p $$ 2>/dev/null || true
if [[ -w /proc/$$/oom_score_adj ]]; then
    sudo bash -c "echo -1000 > /proc/$$/oom_score_adj" 2>/dev/null || true
fi

# --- Configuration ---
SCRIPT_NAME="checkservices.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1
COOLDOWN=2   # seconds between checks
LOGFILE="$HOME/scriptlogs/watch_checkservices.log"
mkdir -p "$(dirname "$LOGFILE")"

# --- Main loop ---
while true; do
    PROCS=($(pgrep -f "[/]Documents/bin/${SCRIPT_NAME}" || true))
    NUM_RUNNING=${#PROCS[@]}

    if (( NUM_RUNNING > MIN_INSTANCES )); then
        # Kill older instances, keep the newest
        PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -"$MIN_INSTANCES")
        for pid in $PIDS_TO_KILL; do
            kill "$pid"
            notify-send -t 5000 --app-name "💀 CheckServices Watchdog" \
                "Extra $SCRIPT_NAME killed: PID $pid" &
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Killed extra $SCRIPT_NAME (PID $pid)" >> "$LOGFILE"
        done

    elif (( NUM_RUNNING < MIN_INSTANCES )); then
        if [[ -x "$SCRIPT_PATH" ]]; then
            # Start with high priority and OOM protection
            nice -n -5 ionice -c2 -n0 "$SCRIPT_PATH" &
            PID=$!

            if [[ -w /proc/$PID/oom_score_adj ]]; then
                sudo bash -c "echo -1000 > /proc/$PID/oom_score_adj" 2>/dev/null || \
                    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [WARN] Failed OOM adjust for PID $PID" >> "$LOGFILE"
            fi

            notify-send -t 5000 --app-name "✅ CheckServices Watchdog" \
                "$SCRIPT_NAME started (PID $PID) with high priority + OOM protection." &
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Started $SCRIPT_NAME (PID $PID)" >> "$LOGFILE"
        else
            notify-send --app-name "⚠️ CheckServices Watchdog" \
                "$SCRIPT_NAME not found or not executable!" &
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ERROR] Missing or non-executable $SCRIPT_NAME" >> "$LOGFILE"
        fi
    fi

    sleep "$COOLDOWN"
done
