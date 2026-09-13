#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# ============================================================================
# Screensaver Manager for Wayland using swayidle
# ============================================================================
# Detects system idleness via swayidle and runs a random screensaver
# from ~/Documents/screensaver/ during idle time.
# ============================================================================

# --- Process Lock (Prevent multiple instances) ---
LOCK_FILE="/tmp/run-screensaver_$(whoami).lock"
IDLE_STATUS_FILE="/tmp/sway_idle_status"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 0  # Already running, exit silently
fi

echo $$ > "$LOCK_FILE"

# --- Cleanup on exit ---
# Removes lock file, kills swayidle, removes idle status file
cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi

    # Item 7: kill any swayidle we started
    pkill -f "swayidle" 2>/dev/null

    # Item 8: remove the idle status file
    rm -f "$IDLE_STATUS_FILE" 2>/dev/null

    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}
trap cleanup EXIT

# --- Environment Setup ---
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# --- Configuration ---
LOGFILE="$HOME/scriptlogs/screensaver_log.txt"
MAX_LOG_SIZE=$((50 * 1024 * 1024))   # 50 MB
MAX_OLD_LOGS=3
IDLE_TIMEOUT=1                        # Minutes until idle
SLEEP_TIMEOUT=10
SCREENSAVER_SCRIPT="$HOME/Documents/bin/random-screensaver.sh"
RESUME_HANDLER_SCRIPT="$HOME/Documents/bin/resume-handler.sh"

mkdir -p "$(dirname "$LOGFILE")"

# --- Helpers ---
rotate_log() {
    if [ -f "$LOGFILE" ] && [ "$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOGFILE" "${LOGFILE}.$(date '+%Y%m%d_%H%M%S').old"
        ls -t "${LOGFILE}".*.old 2>/dev/null \
            | tail -n +$((MAX_OLD_LOGS + 1)) \
            | xargs rm -f -- 2>/dev/null || true
    fi
}

# Initialize idle state as active (avoid stale "idle" leftover)
echo "active" > "$IDLE_STATUS_FILE"

log_status() {
    rotate_log
    echo "$(date) - Checking idle status" >> "$LOGFILE"
}

is_video_playing() {
    pactl list sink-inputs 2>/dev/null | awk -v RS="Sink Input #" '
    BEGIN { found = 0 }
    /Sink Input/ {next}
    {
        if (match($0, /application.name = "([^"]+)"/, arr)) {
            if (!/Corked: yes/ && !/pulse.corked = "true"/) {
                found = 1
            }
        }
    }
    END {
        if (found) print "playing"
        else       print "not playing"
        exit found ? 0 : 1
    }
    '
    return $?
}

# --- Core Logic: Idle Management ---
check_idle_status() {
    if [[ -f "$IDLE_STATUS_FILE" ]]; then
        local idle_status
        idle_status=$(<"$IDLE_STATUS_FILE")

        if [[ "$idle_status" == "idle" ]]; then
            # Start screensaver in background
            if [[ -f "$SCREENSAVER_SCRIPT" ]]; then
                "$SCREENSAVER_SCRIPT" &
            else
                echo "$(date) - ERROR: Screensaver script not found: $SCREENSAVER_SCRIPT" >> "$LOGFILE"
            fi

            # Handle overlapping screensavers
            local current_count
            current_count=$(pgrep -c -f "screensaver-" 2>/dev/null || echo 0)

            if [ "$current_count" -gt 1 ]; then
                pkill -o -f "screensaver-" 2>/dev/null
                echo "$(date) - Transition complete: New screensaver active, old one killed." >> "$LOGFILE"
            elif [ "$current_count" -eq 1 ]; then
                echo "$(date) - First run: Initial screensaver started." >> "$LOGFILE"
            fi
        else
            # System is ACTIVE: Stop all screensaver processes
            pkill -9 -f "random-screensaver.sh" 2>/dev/null
            pkill -9 -f "screensaver-" 2>/dev/null
            echo "$(date) - System active: All screensavers stopped." >> "$LOGFILE"
        fi
    fi
}

# --- Main Loop ---
while true; do
    log_status

    # Re-check video playing status each loop
    video_status=$(is_video_playing)

    if [[ "$video_status" == "playing" ]]; then
        # Video is playing → disable idle detection
        pkill -f "swayidle" 2>/dev/null
        pkill -9 -f "random-screensaver.sh" 2>/dev/null
        pkill -9 -f "screensaver-" 2>/dev/null
        echo "active" > "$IDLE_STATUS_FILE"
        echo "$(date) - Video playing, idle detection disabled" >> "$LOGFILE"
    else
        # No video playing → ensure swayidle is running
        if ! pgrep -f "swayidle" > /dev/null; then
            swayidle -w \
                timeout $((IDLE_TIMEOUT * 60)) "echo idle > $IDLE_STATUS_FILE" \
                resume "echo active > $IDLE_STATUS_FILE && $RESUME_HANDLER_SCRIPT" &
            echo "$(date) - swayidle started (video stopped)" >> "$LOGFILE"
        fi
        # Check idle status to start/stop screensavers
        check_idle_status
    fi

    sleep $SLEEP_TIMEOUT
done
