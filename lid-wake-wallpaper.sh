#!/usr/bin/env bash
# ============================================================
# lid-wake-wallpaper.sh
#
# - Restarts random_wallpaper.sh on system resume
# - Watchdog: restarts it if the last line of wallpaper.log
#   stays identical for STUCK_THRESHOLD consecutive checks
#
# Intended to run as a systemd --user service.
# ============================================================
set -uo pipefail

# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------
WALLPAPER_SCRIPT="$HOME/Documents/bin/random_wallpaper.sh"
WALLPAPER_LOG="$HOME/scriptlogs/wallpaper.log"
LOCK_FILE="$HOME/.cache/random_wallpaper.lock"

LOG="$HOME/scriptlogs/lid-wake.log"
mkdir -p "$(dirname "$LOG")" "$(dirname "$WALLPAPER_LOG")"

# Watchdog tuning
CHECK_INTERVAL=60        # How often to check (seconds)
STUCK_THRESHOLD=5        # Consecutive identical last-lines = stuck
                         # 5 * 60s = 5 minutes before restart
GRACE_AFTER_RESTART=90   # Don't fire right after a restart (seconds)

# Runtime state
LAST_RESUME=0
LAST_RESTART=0

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
wallpaper_running() {
    pgrep -f -- "^${WALLPAPER_SCRIPT}$" >/dev/null 2>&1
}

# ------------------------------------------------------------
# Restart the wallpaper script
# ------------------------------------------------------------
restart_wallpaper() {
    local reason="${1:-manual}"
    local now
    now=$(date +%s)

    # Debounce duplicate resume signals
    if [ "$reason" = "resume" ] && [ $((now - LAST_RESUME)) -lt 10 ]; then
        log "Ignoring duplicate resume signal (debounce)"
        return 0
    fi
    [ "$reason" = "resume" ] && LAST_RESUME=$now

    log "Restarting wallpaper script (reason: $reason)"

    # Let the session settle (network, DBus, Plasma)
    sleep 2

    # Kill the main script
    if pkill -f -- "^${WALLPAPER_SCRIPT}$" 2>/dev/null; then
        log "Killed existing random_wallpaper.sh"
        sleep 1
    else
        log "No running random_wallpaper.sh instance found"
    fi

    # Kill orphan helpers that would conflict
    pkill -f "deviousq" 2>/dev/null && log "Killed orphan deviousq"
    pkill -f "wget.*wallpaper_" 2>/dev/null && log "Killed orphan wget"
    pkill -x "variety" 2>/dev/null && log "Killed stuck Variety"

    # Clear the lock file — otherwise the relaunch exits immediately
    if [ -e "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE" && log "Cleared stale lock file"
    fi

    if [ ! -x "$WALLPAPER_SCRIPT" ]; then
        log "ERROR: $WALLPAPER_SCRIPT is not executable"
        return 1
    fi

    # Relaunch fully detached
    nohup "$WALLPAPER_SCRIPT" \
        >> "$HOME/scriptlogs/wallpaper-stdout.log" 2>&1 \
        < /dev/null &
    local pid=$!
    disown 2>/dev/null || true
    log "Relaunched random_wallpaper.sh (PID $pid)"

    LAST_RESTART=$now
}

# ------------------------------------------------------------
# Watchdog: restart if the last log line stays identical
# for STUCK_THRESHOLD consecutive checks
# ------------------------------------------------------------
watchdog_loop() {
    # Give the freshly-started script a moment to write its first lines
    sleep 10

    local last_seen=""
    local identical_count=0

    while true; do
        sleep "$CHECK_INTERVAL"

        if [ ! -f "$WALLPAPER_LOG" ]; then
            continue
        fi

        # Skip if we just restarted — give the new instance time to work
        local since_restart=$(( $(date +%s) - LAST_RESTART ))
        if [ "$since_restart" -lt "$GRACE_AFTER_RESTART" ]; then
            last_seen=""
            identical_count=0
            continue
        fi

        local current_line
        current_line=$(tail -n 1 "$WALLPAPER_LOG" 2>/dev/null | tr -d '\r')

        if [ "$current_line" = "$last_seen" ]; then
            identical_count=$((identical_count + 1))
            log "Watchdog: last line unchanged for ${identical_count}/${STUCK_THRESHOLD} checks"
        else
            last_seen="$current_line"
            identical_count=1
        fi

        if [ "$identical_count" -ge "$STUCK_THRESHOLD" ]; then
            log "WATCHDOG: last line stuck for ~$((identical_count * CHECK_INTERVAL))s:"
            log "  -> $current_line"
            restart_wallpaper "watchdog-stuck-line"
            last_seen=""
            identical_count=0
        fi
    done
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
log "lid-wake-wallpaper.sh started (PID $$)"

if ! wallpaper_running; then
    log "Wallpaper script not running at monitor start — starting it"
    restart_wallpaper "initial-start"
fi

# Start watchdog in the background
watchdog_loop &
WATCHDOG_PID=$!
log "Watchdog started (PID $WATCHDOG_PID, interval=${CHECK_INTERVAL}s, threshold=${STUCK_THRESHOLD} checks)"

# Ensure watchdog dies with the monitor
trap 'log "Shutting down"; kill "$WATCHDOG_PID" 2>/dev/null; exit 0' INT TERM EXIT

# ------------------------------------------------------------
# Monitor PrepareForSleep via dbus-monitor
# ------------------------------------------------------------
stdbuf -oL dbus-monitor --system \
    "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" \
    2>/dev/null \
| while IFS= read -r line; do
    if [[ "$line" == *"boolean false"* ]]; then
        restart_wallpaper "resume"
    fi
done

log "dbus-monitor exited — monitor stopping"
