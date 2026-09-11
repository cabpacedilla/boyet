#!/usr/bin/env bash
# ============================================================
# lid-wake-wallpaper.sh
#
# Watches for system resume (PrepareForSleep=false) and
# restarts random_wallpaper.sh in the background.
#
# Intended to run as a systemd --user service.
# ============================================================
set -uo pipefail

WALLPAPER_SCRIPT="$HOME/Documents/bin/random_wallpaper.sh"
LOG="$HOME/scriptlogs/lid-wake.log"
mkdir -p "$(dirname "$LOG")"

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# ------------------------------------------------------------
# Restart the wallpaper script
# ------------------------------------------------------------
LAST_RESUME=0

restart_wallpaper() {
    local now
    now=$(date +%s)

    # Debounce: suspend-then-hibernate can emit false twice
    if [ $((now - LAST_RESUME)) -lt 10 ]; then
        log "Ignoring duplicate resume signal (debounce)"
        return 0
    fi
    LAST_RESUME=$now

    log "Resume detected — restarting wallpaper script"

    # Give the session a moment to settle (network, DBus, Plasma)
    sleep 2

    # Kill any running instance by exact path
    if pkill -f -- "^${WALLPAPER_SCRIPT}$" 2>/dev/null; then
        log "Killed existing random_wallpaper.sh"
        sleep 1
    else
        log "No running random_wallpaper.sh instance found"
    fi

    if [ ! -x "$WALLPAPER_SCRIPT" ]; then
        log "ERROR: $WALLPAPER_SCRIPT is not executable"
        return 1
    fi

    # Relaunch fully detached from this monitor
    nohup "$WALLPAPER_SCRIPT" \
        >> "$HOME/scriptlogs/wallpaper-stdout.log" 2>&1 \
        < /dev/null &
    disown 2>/dev/null || true
    log "Relaunched random_wallpaper.sh (PID $!)"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
log "lid-wake-wallpaper.sh started (PID $$)"

# Start wallpaper script if it isn't already running
if ! pgrep -f -- "^${WALLPAPER_SCRIPT}$" >/dev/null 2>&1; then
    log "Wallpaper script not running at monitor start — starting it"
    restart_wallpaper
fi

# Monitor PrepareForSleep via dbus-monitor (eavesdropping fallback as user)
# stdbuf -oL: line-buffered so we don't wait for the pipe buffer
# 2>/dev/null: suppress the "unable to enable new-style monitoring" warning
stdbuf -oL dbus-monitor --system \
    "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" \
    2>/dev/null \
| while IFS= read -r line; do
    if [[ "$line" == *"boolean false"* ]]; then
        restart_wallpaper
    fi
done

log "dbus-monitor exited — monitor stopping"
