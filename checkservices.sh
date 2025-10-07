#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# checkservices.sh — Watchdog-style service monitor
# Ensures essential scripts are running, prevents duplicates,
# starts missing ones with high priority and OOM protection.
#
# Dependencies: pgrep, ps, sudo, notify-send
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Self protection ---
renice -n -10 -p $$ 2>/dev/null || true
ionice -c2 -n0 -p $$ 2>/dev/null || true
if [[ -w /proc/$$/oom_score_adj ]]; then
    sudo bash -c "echo -1000 > /proc/$$/oom_score_adj" 2>/dev/null || true
fi

# --- Configuration ---
SCRIPTS=(
    "autosync"
    "autobrightness"
    "backlisten"
    "batteryAlertBashScript"
    "battery_usage"
    "btrfs_balance_quarterly"
    "btrfs_scrub_monthly"
    "fortune4you"
#   "hot_parts"
    "keyLocked"
    "laptopLid_close"
    "login_monitor"
    "low_disk_space"
    "lowMemAlert"
    "prevent_screensaver"
    "security_check"
    "weather_alarm"
)
MIN_INSTANCES=1
COOLDOWN=2
LOGFILE="$HOME/scriptlogs/checkservices.log"
mkdir -p "$(dirname "$LOGFILE")"

# --- Function: start script safely ---
start_script() {
    local SCRIPT_PATH="$1"
    local SCRIPT_NAME
    SCRIPT_NAME="$(basename "$SCRIPT_PATH")"

    if [[ -x "$SCRIPT_PATH" ]]; then
        nice -n -5 ionice -c2 -n0 "$SCRIPT_PATH" &
        local PID=$!
        if [[ -w /proc/$PID/oom_score_adj ]]; then
            sudo bash -c "echo -1000 > /proc/$PID/oom_score_adj" 2>/dev/null || \
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [WARN] OOM adjust failed for $SCRIPT_NAME (PID $PID)" >> "$LOGFILE"
        fi
        notify-send -t 4000 --app-name "✅ CheckServices" "$SCRIPT_NAME started (PID $PID)"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Started $SCRIPT_NAME (PID $PID)" >> "$LOGFILE"
    else
        notify-send --app-name "⚠️ CheckServices" "$SCRIPT_NAME not found or not executable!"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ERROR] Missing/non-executable: $SCRIPT_NAME" >> "$LOGFILE"
    fi
}

# --- Main loop ---
while true; do
    for SCRIPT in "${SCRIPTS[@]}"; do
        SCRIPT_PATH="$HOME/Documents/bin/${SCRIPT}.sh"
        PROCS=($(pgrep -f "[/]Documents/bin/${SCRIPT}.sh" || true))
        NUM_RUNNING=${#PROCS[@]}

        if (( NUM_RUNNING > MIN_INSTANCES )); then
            # Kill older processes, keep the newest
            PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -"$MIN_INSTANCES")
            for PID in $PIDS_TO_KILL; do
                kill "$PID" 2>/dev/null || true
                notify-send -t 3000 --app-name "💀 CheckServices" "Killed extra ${SCRIPT}.sh (PID $PID)"
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] Killed duplicate $SCRIPT.sh (PID $PID)" >> "$LOGFILE"
            done
        elif (( NUM_RUNNING < MIN_INSTANCES )); then
            start_script "$SCRIPT_PATH"
        fi
    done

    sleep "$COOLDOWN"
done
