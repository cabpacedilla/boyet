#!/usr/bin/env bash
# ============================================================================
# Screensaver Manager for Wayland using swayidle
# ============================================================================
# This script detects system idleness in Wayland using swayidle and runs
# randomly selected screensaver programs during idle time.
#
# In KDE 6.3, run one screensaver application in your screensavers folder then 
# right click on the title bar then click configure special application settings 
# in More Actions with the following settings:
#   1. Window class (application) field = substring match for "screensaver-"
#   2. Match whole window class field = Yes
#   3. Window type field = All selected
#   4. Fullscreen Size & Position property = Force; Yes
# ============================================================================

# --- Process Lock (Prevent multiple instances) ---
LOCK_FILE="/tmp/runscreensaver_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 0  # Already running, exit silently
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
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
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 50MB
MAX_OLD_LOGS=3
IDLE_TIMEOUT=1                       # Minutes until idle
SCREENSAVER_SCRIPT="$HOME/Documents/bin/randscreensavers.sh"
RESUME_HANDLER_SCRIPT="$HOME/Documents/bin/resume_handler.sh"
IDLE_STATUS_FILE="/tmp/sway_idle_status"

# Ensure log directory exists and state is clean
mkdir -p "$(dirname "$LOGFILE")"

# --- Helper functions ---
rotate_log() {
    if [ -f "$LOGFILE" ] && [ "$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOGFILE" "${LOGFILE}.$(date '+%Y%m%d_%H%M%S').old"
        ls -t "${LOGFILE}".*.old 2>/dev/null | tail -n +$((MAX_OLD_LOGS + 1)) | xargs rm -f -- 2>/dev/null || true
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
        if (found)
            print "playing"
        else
            print "not playing"
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
            pkill -9 -f "randscreensavers.sh" 2>/dev/null
            pkill -9 -f "screensaver-" 2>/dev/null
            echo "$(date) - System active: All screensavers stopped." >> "$LOGFILE"
        fi
    fi
}

# --- Background Task: Swayidle ---
start_swayidle() {
    # Clean up any existing swayidle instances first
    pkill -f "swayidle" 2>/dev/null
    
    # Only run swayidle if no video is playing
    video_status=$(is_video_playing)
    if [ "$video_status" = "playing" ]; then
        echo "$(date) - Video playing, idle detection disabled" >> "$LOGFILE"
        pkill -9 -f "randscreensavers.sh" 2>/dev/null
        pkill -9 -f "screensaver-" 2>/dev/null
    elif [ "$video_status" = "not playing" ]; then
        swayidle -w \
            timeout $((IDLE_TIMEOUT * 60)) "echo idle > $IDLE_STATUS_FILE" \
            resume "echo active > $IDLE_STATUS_FILE && $RESUME_HANDLER_SCRIPT" 
        echo "$(date) - swayidle started with ${IDLE_TIMEOUT} minute timeout" >> "$LOGFILE"
    fi
}

# --- Execution ---
start_swayidle

# Main loop to continuously check idle status
while true; do
    log_status
    check_idle_status
    sleep 10
done
