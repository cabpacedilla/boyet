#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

LOCK_FILE="/tmp/autosync_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

while inotifywait -r -e modify,create /home/claiveapa/Documents/; do
	BACKUP_TIME=$(date +"%I:%M %p")
	rsync -a --protect-args --delete \
      --backup --backup-dir="/run/media/claiveapa/Data/claive/Documents/nobara/kde42/backups/$(date +%F)" \
      --exclude='*.swp' --exclude='*.swo' --exclude='*.swx' --exclude='*~' \
      --exclude='*.tmp' --exclude='*.bak' --exclude='*.autosave' --exclude='*.part' --exclude='*.crdownload' \
      "/home/claiveapa/Documents/" "/run/media/claiveapa/Data/claive/Documents/nobara/kde42/main/"
    STATUS=$?

    if [[ $STATUS -eq 0 || $STATUS -eq 24 || $STATUS -eq 23 ]]; then
        notify-send --app-name "✅ Auto-backup: $BACKUP_TIME" "Backup sync was successful (code $STATUS)."
    else
        notify-send --app-name "⚠️ Auto-backup: $BACKUP_TIME" "Backup sync encountered errors (code $STATUS)."
    fi
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# ============================================================
# Auto Brightness (Event-Driven)
# ============================================================
# Watches the brightness file via inotifywait. When the
# brightness changes, it immediately corrects it to 100%.
# 
# Dependency: 
# Install inotifywait with sudo dnf install inotify-tools
# ============================================================

# --- Single-Instance Lock ---
LOCK_FILE="/tmp/autobrightness_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

# --- Cleanup ---
cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

trap cleanup EXIT

# --- Detect Backlight Device ---
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
if [ -z "$DEVICE" ]; then
    echo "No amdgpu backlight device found." >&2
    exit 1
fi

BRIGHTNESS_FILE="/sys/class/backlight/${DEVICE}/brightness"
MAX_BRIGHTNESS=$(cat "/sys/class/backlight/${DEVICE}/max_brightness" 2>/dev/null)
TARGET_PERCENT=90

if [ -z "$MAX_BRIGHTNESS" ]; then
    echo "Cannot read max brightness for $DEVICE" >&2
    exit 1
fi

# Calculate the target absolute brightness value
TARGET_VALUE=$(( MAX_BRIGHTNESS * TARGET_PERCENT / 100 ))

# --- Core Function ---
check_and_correct() {
    CURRENT_BRIGHTNESS=$(cat "$BRIGHTNESS_FILE" 2>/dev/null)
    if [[ -n "$CURRENT_BRIGHTNESS" && "$CURRENT_BRIGHTNESS" -ne "$TARGET_VALUE" ]]; then
        brightnessctl -d "$DEVICE" set "${TARGET_PERCENT}%"
    fi
}

# --- Initial check (catch current state) ---
check_and_correct

# --- Main Event Loop ---
# Wait for the brightness file to be modified.
# Every time it changes, run check_and_correct.
inotifywait -m -e modify "$BRIGHTNESS_FILE" 2>/dev/null | while read -r; do
    check_and_correct
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

LOCK_FILE="/tmp/backlisten_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

SCRIPT_NAME="checkservices.sh"
SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"
MIN_INSTANCES=1
COOLDOWN=5   # seconds between checks

while true; do
    # Find all running processes for the script with bash
    PROCS=($(pgrep -f "bash $SCRIPT_PATH$"))
    NUM_RUNNING=$(echo "$PROCS" | wc -w)

    if [ "$NUM_RUNNING" -ge "$MIN_INSTANCES" ]; then
        # More than one instance? Kill extras and notify
        PROC_ARRAY=($PROCS)
        LAST_INDEX=$(( ${#PROC_ARRAY[@]} - 1 ))
        for i in $(seq 0 $((LAST_INDEX - 1))); do
            kill "${PROC_ARRAY[$i]}"
            notify-send -t 10000 --app-name "💀 Check services" "Extra checkservices instance killed: PID ${PROC_ARRAY[$i]}" &
        done
    else
        # Script not running, start it
        if [ -x "$SCRIPT_PATH" ]; then
            "$SCRIPT_PATH" > /dev/null 2>&1 &
            notify-send -t 10000 --app-name "✅ Check services" "checkservices started." &
            sleep 5
        else
            notify-send --app-name "⚠️ Check services" "checkservices script not found or not executable!" &
        fi
    fi

    sleep "$COOLDOWN"
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# This script alerts when battery level is low or high and adjusts brightness for battery optimization.
# Written by Claive Alvin P. Acedilla. Modified for dynamic brightnessctl use.

LOCK_FILE="/tmp/batteryAlertBashScript_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

notify()
{
   if [ "$1" = 'low' ]; then
        ACTION="Plug"
   elif [ "$1" = 'high' ]; then
        ACTION="Unplug"
   fi

   notify-send -u critical --app-name "⚠️ Battery alert:" "Battery reached $2%. $ACTION the power cable to optimize battery life!"

   # Uncomment to play sound
   # if [ -f "$(which mpv)" ]; then
   #     mpv ~/Music/battery-"$1".mp3 2>/dev/null
   # fi
}

# Detect amdgpu_bl* device dynamically
DEVICE=$(brightnessctl -l | grep -o "amdgpu_bl[0-9]" | head -n1)
if [ -z "$DEVICE" ]; then
    echo "No AMD GPU backlight device found. Exiting."
    exit 1
fi

# Settings
LOW_BATT=20
HIGH_BATT=80
FULL_BATT=100
TARGET_BRIGHTNESS=90

while true; do

    # Get battery level and status
    BATT_LEVEL=$(acpi -b | grep -P -o '[0-9]+(?=%)')
    BATT_STATE=$(acpi -b | awk '{print $3}')

    # Get current brightness percentage
    CUR_BRIGHT=$(brightnessctl -d "$DEVICE" get)
    MAX_BRIGHT=$(brightnessctl -d "$DEVICE" max)
    CUR_PERCENT=$(( 100 * CUR_BRIGHT / MAX_BRIGHT ))

    # Function to adjust brightness if not 90%
    ensure_optimal_brightness() {
        if [ "$CUR_PERCENT" -ne "$TARGET_BRIGHTNESS" ]; then
            brightnessctl -d "$DEVICE" set "${TARGET_BRIGHTNESS}%"
        fi
    }

    # 1. Notify if battery is low and discharging
    if [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; then
        notify low "$BATT_LEVEL"

    # 2. If low but charging/unknown, adjust brightness
    elif { [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; }; then
        ensure_optimal_brightness

    # 3. Notify if battery is full or nearly full
    elif { [ "$BATT_LEVEL" -ge "$HIGH_BATT" ] && [[ "$BATT_STATE" == "Charging," || "$BATT_STATE" == "Unknown," ]]; } || \
         { [ "$BATT_LEVEL" -eq "$FULL_BATT" ] && [[ "$BATT_STATE" == "Full," || "$BATT_STATE" == "Discharging," ]]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Not" ]; }; then
        notify high "$BATT_LEVEL"

    # 4. If battery is discharging and < 80%, just adjust brightness
    elif { [ "$BATT_LEVEL" -le "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; } || \
         { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; }; then
        ensure_optimal_brightness
    fi

    sleep 5
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
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

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
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
                btrfs balance start -dusage="${DATA_USAGE_THRESHOLD}" "$MOUNTPOINT" \
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
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# Monthly Btrfs Scrub Script – Refined 2026 Edition (Final Stable)
# SSD/NVMe friendly with idle I/O priority and resume support.
set -euo pipefail

# --- Pre-Loop Initialization ---
: "${LOG_DIR:=$HOME/scriptlogs}"
: "${MOUNTPOINT:=/}"
: "${SCRUB_INTERVAL_DAYS:=30}"
: "${NOTIFICATIONS:=true}"
: "${SLEEP_HOURS:=1}"

# Validate configuration
if [[ ! "$SCRUB_INTERVAL_DAYS" =~ ^[0-9]+$ ]] || [[ "$SCRUB_INTERVAL_DAYS" -lt 1 ]]; then
    echo "ERROR: SCRUB_INTERVAL_DAYS must be a positive integer" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
LAST_RUN_FILE="$LOG_DIR/btrfs-scrub-last-run"
LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m).log"

# --- Locking Strategy (commented out) ---
LOCK_FILE="/tmp/btrfs_scrub_monthly_$(whoami).lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 1
fi

# --- Helper Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

notify() {
    [[ "${NOTIFICATIONS}" == "true" ]] || return 0
    command -v notify-send >/dev/null || return 0

    if [[ "$1" == "-u" ]]; then
        # Format: -u urgency title message
        notify-send -u "$2" -t 0 "$3" "$4"
    else
        # Format: title message
        notify-send -u normal -t 0 "$1" "$2"
    fi
}

cleanup() {
    log "Daemon exiting. Releasing lock."
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

# --- Trap Handling ---
trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT

# --- Main Daemon Loop ---
FIRST_RUN=1

while true; do
    LOGFILE="$LOG_DIR/btrfs-scrub-$(date +%Y-%m).log"
    
    if [[ $FIRST_RUN -eq 1 ]]; then
        log "Btrfs scrub daemon started (Interval: ${SCRUB_INTERVAL_DAYS} days)"
        log "Monitoring $MOUNTPOINT, notifications: $NOTIFICATIONS"
        FIRST_RUN=0
    fi

    if ! mountpoint -q "$MOUNTPOINT"; then
        log "$MOUNTPOINT not available, retrying in ${SLEEP_HOURS}h"
        sleep $((SLEEP_HOURS * 3600))
        continue
    fi

    NOW=$(date +%s)
    LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
    DIFF_DAYS=$(( (NOW - LAST_RUN) / 86400 ))

    if [[ "$DIFF_DAYS" -ge "$SCRUB_INTERVAL_DAYS" ]]; then
        
        # Use sudo for status check
        SCRUB_STATUS=$(sudo btrfs scrub status "$MOUNTPOINT" 2>/dev/null || echo "")
        
        if [[ "$SCRUB_STATUS" == *"running"* ]]; then
            log "Scrub already active in background. Waiting..."
            sleep $((SLEEP_HOURS * 3600))
            continue
        fi

        SCRUB_CMD="start"
        # Robust regex check for various interruption states
        if [[ "$SCRUB_STATUS" =~ (was aborted|cancelled|interrupted) ]]; then
            SCRUB_CMD="resume"
            log "Detected interrupted scrub, will resume"
        fi
        
        log "Action: Executing $SCRUB_CMD (Days since last: $DIFF_DAYS)"
        notify "Btrfs Maintenance" "Performing monthly $SCRUB_CMD..."

        # Execution with low I/O priority
        if ionice -c3 nice -n 19 sudo btrfs scrub "$SCRUB_CMD" -B "$MOUNTPOINT" >> "$LOGFILE" 2>&1; then
            
            FINAL_REPORT=$(sudo btrfs scrub status "$MOUNTPOINT" 2>/dev/null)
            if echo "$FINAL_REPORT" | grep -qiE "no errors found|0 errors"; then
                # Extract statistics for logging
                DATA_SCRUBBED=$(echo "$FINAL_REPORT" | grep "Total to scrub" | awk '{print $4}' || echo "unknown")
                log "Scrub completed successfully. Data scrubbed: $DATA_SCRUBBED"
                date +%s > "$LAST_RUN_FILE"
                notify "Btrfs Scrub Complete" "System integrity verified. No errors found."
            else
                ERROR_COUNT=$(echo "$FINAL_REPORT" | grep -i "error" | grep -v "0 errors" | awk '{print $2}' || echo "unknown")
                log "Scrub finished with errors (count: $ERROR_COUNT). Check $LOGFILE"
                notify -u critical "Btrfs Error" "Integrity issues found on $MOUNTPOINT"
            fi
        else
            exit_code=$?
            log "Scrub process failed with exit code $exit_code"
            if [[ $exit_code -eq 1 ]]; then
                notify -u critical "Btrfs Error" "Scrub failed to complete properly"
            fi
        fi
    fi

    sleep $((SLEEP_HOURS * 3600))
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

LOCK_FILE="/tmp/fortune4you_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

while true; do

# Alert the random quote
# notify-send -u critical --app-name "Fortune:" "$(fortune)"
kdialog --title "Fortune" --msgbox "$(fortune)" &
# kdialog --passivepopup "$(fortune)" --title "Fortune" &

# Sleep in random time
sleep "$(shuf -i1200-1500 -n1)"

done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# This script will notify when Caps Lock or Num Lock are on using the xset q command.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like keyLocked.sh
# 4. Make file executable with chmod +x keyLocked.sh command
# 5. Add the keyLocked.sh command in Startup applications
# 6. Reboot the laptop
# 7. Press the Caps Lock key
# 8. A Caps Lock key notification message will be displayed
# 9. Press the Num Lock key
# 10. A Num Lock key notification message will be displayed

LOCK_FILE="/tmp/keyLocked_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

# Define LED mask values for key locks
CAPS_LOCK="00000001"
NUM_LOCK="00000002"
CAPSNUM_LOCK="00000003"
NO_LOCK="00000000"

# Function to get LED mask value
get_led_mask() {
    xset q | grep 'LED mask' | awk '{ print $NF }'
}

# Main loop
while true; do
    LED_MASK=$(get_led_mask)

    # Check if the LED mask command was successful
    if [ $? -ne 0 ]; then
        sleep 10
        continue
    fi

    # Notify based on LED mask value
    case "$LED_MASK" in
        "$CAPS_LOCK")
            notify-send -t 9000 --app-name "⚠️ Key lock:" "Caps lock is on."
            ;;
        "$NUM_LOCK")
            notify-send -t 9000 --app-name "⚠️ Key lock:" "Num lock is on."
            ;;
        "$CAPSNUM_LOCK")
            notify-send -t 9000 --app-name "⚠️ Key lock:" "Caps lock and Num lock are on."
            ;;
        "$NO_LOCK")
            # Do nothing
            ;;
        *)
            # Handle unexpected values
            ;;
    esac

    sleep 10
done

#!/usr/bin/env bash
# ============================================================
# Locks session when lid closed AND no external display connected.
# Uses native systemd D-Bus and kernel DRM sysfs – works on Wayland & X11.
#
# IMPORTANT CONFIGURATION:
# To prevent systemd from suspending before this script evaluates:
# Set the following in /etc/systemd/logind.conf (or /etc/systemd/logind.conf.d/lid.conf):
#   HandleLidSwitch=ignore
#   HandleLidSwitchExternalPower=ignore
#   HandleLidSwitchDocked=ignore
# Then apply with: sudo systemctl restart systemd-logind
# ============================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
set -o pipefail

# ---------- Initialisation ----------
UDEV_PID=""
BUSCTL_PID=""

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Do not run this script as root." >&2
    exit 1
fi

# ---------- Single instance lock ----------
if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" ]]; then
    echo "ERROR: XDG_RUNTIME_DIR unavailable" >&2
    exit 1
fi

LOCK_FILE="$XDG_RUNTIME_DIR/$(basename "$0" .sh).lock"   # dynamic name
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "ERROR: Another instance is running." >&2
    exit 1
fi
printf '%s\n' "$$" >&9

cleanup() {
    # Kill the entire process group of each monitor (kills child processes too)
    [[ -n "$UDEV_PID" ]] && kill -TERM -"$UDEV_PID" 2>/dev/null || true
    [[ -n "$BUSCTL_PID" ]] && kill -TERM -"$BUSCTL_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ---------- Lid state: D-Bus (systemd-logind) with fallback ----------
get_lid_state() {
    local state
    if command -v busctl &>/dev/null; then
        state=$(busctl --system get-property org.freedesktop.login1 \
                      /org/freedesktop/login1 \
                      org.freedesktop.login1.Manager \
                      LidClosed 2>/dev/null | awk '{print $2}')
        [[ "$state" == "true" ]] && { echo "closed"; return; }
        [[ "$state" == "false" ]] && { echo "open"; return; }
    fi

    # Fallback (older systems)
    local proc_state
    proc_state=$(awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null)
    [[ -n "$proc_state" ]] && echo "$proc_state" || echo "open"
}

# ---------- External display detection via DRM sysfs (Wayland-safe) ----------
hdmi_connected() {
    for status_file in /sys/class/drm/card*-*/status; do
        [[ -f "$status_file" ]] || continue
        # Skip internal panels
        [[ "$status_file" =~ eDP|LVDS ]] && continue
        if grep -q "^connected$" "$status_file" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# ---------- Main lock logic ----------
check_and_lock() {
    local lid_state
    lid_state="$(get_lid_state)"
    [[ "$lid_state" != "closed" ]] && return

    # Retry to allow hotplug events to settle
    for ((i=0; i<5; i++)); do
        if hdmi_connected; then
            return
        fi
        sleep 0.5
    done

    # No external display – lock the session via systemd
    logger "laptopLid_close: Lid closed with no external display. Locking session."
    loginctl lock-session
}

# ---------- Initial check on script start ----------
check_and_lock

# ---------- Event monitors ----------
# 1. DRM hotplug events (external display plug/unplug)
(
    udevadm monitor --subsystem-match=drm --property 2>/dev/null | while read -r line; do
        if [[ "$line" == *"HOTPLUG=1"* ]]; then
            check_and_lock
        fi
    done
) &
UDEV_PID=$!

# 2. D-Bus lid events (native systemd signals)
(
    busctl monitor org.freedesktop.login1 2>/dev/null | while read -r line; do
        if [[ "$line" == *"LidClosed"* ]]; then
            check_and_lock
        fi
    done
) &
BUSCTL_PID=$!

# ---------- Wait for background processes ----------
wait
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & failure)
# Logs to ~/scriptlogs/login-monitor.log and sends desktop notifications
# Requires: libnotify (notify-send command)

LOCK_FILE="/tmp/login_monitor_$(whoami).lock"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

cleanup() {
    # Only remove if it's our PID
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi

    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Cooldown seconds for identical repeated messages
COOLDOWN=5

# Store last event timestamps
declare -A last_event

# Track processed events for periodic cleanup
EVENT_COUNTER=0

# Cleanup old cooldown entries (prevents unbounded memory growth)
cleanup_old_events() {
    local current
    current=$(date +%s)

    for key in "${!last_event[@]}"; do
        if (( current - last_event[$key] > 600 )); then
            unset 'last_event[$key]'
        fi
    done
}

# Function to send notifications and log them
send_alert() {
    local TITLE="$1"
    local MSG="$2"
    local URGENCY="$3"

    timeout 2 notify-send "$TITLE" "$MSG" -u "$URGENCY" 2>/dev/null &

    echo "[$(date '+%F %T')] [$TITLE] $MSG" >> "$LOGFILE"
}

echo "[$(date '+%F %T')] Starting login monitor..." | tee -a "$LOGFILE"

timeout 2 notify-send "Login Monitor" "Starting login monitor..." 2>/dev/null &

# Restart automatically if journalctl exits
while true; do
    journalctl -f -n0 -o short-iso --no-tail \
        _COMM=sshd \
        _COMM=sshd-session \
        _COMM=sudo \
        _COMM=su 2>/dev/null | \
    while IFS= read -r LINE; do

        NOW=$(date +%s)
        TS=$(date '+%F %T')

        # Periodic cleanup
        EVENT_COUNTER=$((EVENT_COUNTER + 1))

        if (( EVENT_COUNTER % 50 == 0 )); then
            cleanup_old_events
        fi

        # =========================================================
        # SSH EVENTS
        # =========================================================
        if [[ "$LINE" =~ "sshd" || "$LINE" =~ "sshd-session" ]]; then

            # SSH SUCCESS
            if [[ "$LINE" =~ "Accepted " ]]; then

                USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
                IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")

                EVENT_ID="ssh_success_${USER}_${IP}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                MSG="User: $USER | From: $IP | Time: $TS"

                echo -e "✅ ${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"

                send_alert "✅ SSH Login Success" "$MSG" critical

            # SSH FAILURE
            elif [[ "$LINE" =~ "Failed password" ]]; then

                USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
                IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")

                EVENT_ID="ssh_fail_${USER}_${IP}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                MSG="User: $USER | From: $IP | Time: $TS"

                echo -e "⚠️ ${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"

                send_alert "⚠️ SSH Login Failed" "$MSG" critical
            fi
        fi

        # =========================================================
        # SUDO EVENTS
        # =========================================================
        if [[ "$LINE" =~ "sudo" ]]; then

            # SUDO SUCCESS
            if [[ "$LINE" =~ "session opened" ]]; then

                USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")

                EVENT_ID="sudo_success_${USER}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)

                CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
                CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')

                MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"

                echo -e "✅ ${GREEN}[SUDO SUCCESS]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"

                send_alert "✅ Sudo Success" "$MSG" critical

            # PAM AUTH FAILURE
            elif [[ "$LINE" =~ "pam_unix(sudo:auth): authentication failure" ]]; then

                if [[ "$LINE" =~ user=([^[:space:]]+) ]]; then
                    USER="${BASH_REMATCH[1]}"
                else
                    USER="unknown"
                fi

                EVENT_ID="sudo_fail_${USER}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < 2 )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                PAM_DETAILS=$(echo "$LINE" | sed -n 's/.*authentication failure; \(.*\)/\1/p')

                MSG="User: $USER | Time: $TS\n$PAM_DETAILS\nCommand: (will be logged on final attempt)"

                echo -e "⚠️ ${RED}[SUDO FAILURE]${NC} $LINE | $PAM_DETAILS | Command: (will be logged on final attempt)" | tee -a "$LOGFILE"

                send_alert "⚠️ Sudo Failure" "$MSG" critical

            # SUDO FAILURE
            elif [[ "$LINE" =~ "incorrect password attempts" ]] ||
                 [[ "$LINE" =~ "sorry, try again" ]] ||
                 [[ "$LINE" =~ "password attempts" ]]; then

                USER=$(echo "$LINE" |
                    awk -F'sudo\\[[0-9]*\\]: *' '{print $2}' |
                    awk '{print $1}')

                if [[ -z "$USER" ]] || [[ "$USER" == ":" ]]; then
                    USER=$(echo "$LINE" |
                        sed -n 's/.*sudo\[[0-9]*\]: *\([^ ]*\).*/\1/p')
                fi

                if [[ -z "$USER" ]]; then
                    USER="unknown"
                fi

                EVENT_ID="sudo_fail_${USER}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < 2 )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                if [[ "$LINE" =~ COMMAND=(.+)$ ]]; then
                    CMD="${BASH_REMATCH[1]}"
                    CONTEXT=$(echo "$LINE" | sed -E 's/; COMMAND=.*//')
                else
                    RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)

                    CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
                    CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
                fi

                MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"

                echo -e "⚠️ ${RED}[SUDO FAILURE]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"

                send_alert "⚠️ Sudo Failure" "$MSG" critical
            fi
        fi

        # =========================================================
        # SU EVENTS
        # =========================================================
        if [[ "$LINE" =~ " su[" && "$LINE" =~ "session opened" ]]; then

            USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")

            EVENT_ID="su_success_${USER}"

            if [[ -n "${last_event[$EVENT_ID]}" ]] &&
               (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi

            last_event[$EVENT_ID]=$NOW

            MSG="User: $USER | Time: $TS"

            echo -e "✅ ${GREEN}[SU SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"

            send_alert "✅ su Login Success" "$MSG" critical

        elif [[ "$LINE" =~ " su[" && "$LINE" =~ "authentication failure" ]]; then

            # Source user
            if [[ "$LINE" =~ ruser=([^[:space:]]+) ]]; then
                SOURCE_USER="${BASH_REMATCH[1]}"
            elif [[ "$LINE" =~ logname=([^[:space:]]+) ]]; then
                SOURCE_USER="${BASH_REMATCH[1]}"
            else
                SOURCE_USER="unknown"
            fi

            # Target user
            if [[ "$LINE" =~ user=([^[:space:]]+)$ ]] ||
               [[ "$LINE" =~ user=([^[:space:]]+)[[:space:]] ]]; then
                TARGET_USER="${BASH_REMATCH[1]}"
            else
                TARGET_USER="unknown"
            fi

            EVENT_ID="su_fail_${SOURCE_USER}_${TARGET_USER}"

            if [[ -n "${last_event[$EVENT_ID]}" ]] &&
               (( NOW - last_event[$EVENT_ID] < 2 )); then
                continue
            fi

            last_event[$EVENT_ID]=$NOW

            MSG="Source User: $SOURCE_USER | Target User: $TARGET_USER | Time: $TS"

            echo -e "⚠️ ${RED}[SU FAILURE]${NC} $LINE" | tee -a "$LOGFILE"

            send_alert "⚠️ su Failure" "$MSG" critical
        fi
    done

    echo "[$(date '+%F %T')] journalctl disconnected, restarting..." | tee -a "$LOGFILE"

    sleep 2
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

LOCK_FILE="/tmp/low_disk_space_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

# Configuration
INTERVAL=120
LEVELS=$(seq 80 1 100)
LAST_ALERT=0
MOUNT_POINT="/"
LOG_FILE="$HOME/scriptlogs/disk_monitor.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))   # 50 MB
MAX_OLD_LOGS=5

# Dependencies
REQUIRED_CMDS=(df awk sed date stat notify-send find sort xargs)
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing dependency: $cmd" >&2
        exit 1
    }
done

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Log rotation
rotate_log() {
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt $MAX_LOG_SIZE ]; then
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="${LOG_FILE}.${TIMESTAMP}.old"
        mv "$LOG_FILE" "$BACKUP_FILE" 2>/dev/null || return
        touch "$LOG_FILE"
        log_message "LOG ROTATED: Previous log moved to $(basename "$BACKUP_FILE")"
        find "$(dirname "$LOG_FILE")" -maxdepth 1 -name "$(basename "$LOG_FILE")*.old" \
            -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | \
            awk "NR>$MAX_OLD_LOGS {print \$2}" | xargs -r rm -f --
    fi
}

# Safe notifications
safe_notify_send() {
    local urgency="$1"
    local app_name="$2"
    local message="$3"

    [ -z "$message" ] && return
    if [ ${#message} -gt 1000 ]; then
        message="${message:0:997}..."
    fi

    notify-send --urgency="$urgency" --app-name "$app_name" "$message" 2>/dev/null || \
        log_message "WARNING: notify-send failed (no session bus?)"
}

# Initial setup
rotate_log
log_message "=== Disk Monitoring Script Started ==="
log_message "Monitoring mount point: $MOUNT_POINT"
log_message "Check interval: $INTERVAL seconds"
log_message "Alert thresholds: 80% to 100%"
log_message "Max log size: $((MAX_LOG_SIZE / 1024 / 1024))MB"
log_message "Max old logs to keep: $MAX_OLD_LOGS"

# Main loop
while true; do
    rotate_log

    USED_PERCENT=$(df "$MOUNT_POINT" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    [[ "$USED_PERCENT" =~ ^[0-9]+$ ]] || USED_PERCENT=0

    for LEVEL in $LEVELS; do
        if [ "$USED_PERCENT" -ge "$LEVEL" ] && [ "$LAST_ALERT" -lt "$LEVEL" ]; then
            ALERT_MESSAGE="Disk usage has reached ${USED_PERCENT}%. Threshold: ${LEVEL}%."
            safe_notify_send "critical" "Low disk space" "$ALERT_MESSAGE"
            log_message "ALERT: Disk usage ${USED_PERCENT}% >= ${LEVEL}% threshold"
            LAST_ALERT=$LEVEL
        fi
    done

    if [ "$USED_PERCENT" -lt 80 ]; then
        if [ "$LAST_ALERT" -ne 0 ]; then
            RECOVERY_MESSAGE="Disk usage normalized to ${USED_PERCENT}%"
            safe_notify_send "normal" "Disk space normal" "$RECOVERY_MESSAGE"
            log_message "INFO: Disk usage normalized to ${USED_PERCENT}%"
        fi
        LAST_ALERT=0
    fi

    sleep $INTERVAL
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# Low Memory Alert Script (Robust + Diagnostic)
# Works on any Linux distro, detects swapping, tracks per-process memory growth

LOCK_FILE="/tmp/lowMemAlert_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

MEMFREE_LIMIT_PERCENT=5
CHECK_INTERVAL=5
MAX_PROCESSES=10
LOG_FILE="$HOME/lowmem_alert.log"
MAX_LOG_SIZE=$((50 * 1024 * 1024))   # 50 MB

# -----------------------------
# Core detection: Get memory stats robustly
# -----------------------------
get_memory_stats() {
    if command -v free >/dev/null 2>&1; then
        read TOTAL_MEM MEMFREE < <(free -m | awk 'NR==2 {print $2, $7}')
    elif [ -r /proc/meminfo ]; then
        TOTAL_MEM=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
        MEMFREE=$(awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
    else
        echo "Error: Cannot determine memory stats." >&2
        exit 1
    fi
}

# -----------------------------
# Diagnostics: Swap detection
# -----------------------------
detect_swap_activity() {
    SWAP_USED=$(awk '/SwapTotal:/ {total=$2} /SwapFree:/ {free=$2} END{print int((total-free)/1024)}' /proc/meminfo)
    SWAP_TOTAL=$(awk '/SwapTotal:/ {print int($2/1024)}' /proc/meminfo)
}

# -----------------------------
# Diagnostics: Per-process memory growth
# -----------------------------
track_process_memory_growth() {
    PROC_MEM_FILE="$HOME/.proc_mem_usage"
    ps -eo pid,comm,rss --no-headers | sort -k3 -nr > /tmp/current_mem_usage

    if [ -f "$PROC_MEM_FILE" ]; then
        echo "Memory growth since last check:"
        join -1 1 -2 1 <(sort /tmp/current_mem_usage) "$PROC_MEM_FILE" | \
            awk '{growth=$3-$4; if(growth>0) printf "%s (%s): +%.1f MB\n",$2,$1,growth/1024}'
    fi

    cp /tmp/current_mem_usage "$PROC_MEM_FILE"
}

# -----------------------------
# Top memory consumers
# -----------------------------
get_top_processes() {
    ps -eo pid,comm,%mem,rss --sort=-%mem --no-headers | head -n "$MAX_PROCESSES" | \
        awk '{size_mb=$4/1024; size_str=(size_mb>=1024)?sprintf("%.1f GB",size_mb/1024):sprintf("%.0f MB",size_mb);
              printf "PID %s (%s): %.2f%% (%s)\n",$1,$2,$3,size_str}'
}

# -----------------------------
# Log rotation
# -----------------------------
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(stat -c%s "$LOG_FILE")
        if [ "$LOG_SIZE" -ge "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d%H%M%S).bak"
            touch "$LOG_FILE"
        fi
    fi
}

# -----------------------------
# Notification
# -----------------------------
send_notification() {
    local msg="$1"
    notify-send -u critical "⚠ Low Memory Alert" "$msg"
}

# -----------------------------
# Main loop
# -----------------------------
while true; do
    get_memory_stats
    detect_swap_activity

    THRESHOLD=$(( TOTAL_MEM * MEMFREE_LIMIT_PERCENT / 100 ))

    if [[ "$MEMFREE" =~ ^[0-9]+$ ]] && [ "$MEMFREE" -le "$THRESHOLD" ]; then
        TOP_PROCESSES=$(get_top_processes)
        track_process_memory_growth

        NOTIF="$(date '+%H:%M:%S')
Total RAM: ${TOTAL_MEM} MB
Available: ${MEMFREE} MB (Threshold: ${THRESHOLD} MB)
Swap used: ${SWAP_USED} MB / ${SWAP_TOTAL} MB

Top memory consumers:
$TOP_PROCESSES"

        echo "[$(date)] $NOTIF" >> "$LOG_FILE"
        rotate_log
        send_notification "$NOTIF"
    fi

    sleep "$CHECK_INTERVAL"
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# -------------------------------------------------------------------------
# power_usage.sh — Enhanced GUI Battery & Process Monitor (kdialog Version)
# -------------------------------------------------------------------------

LOCK_FILE="/tmp/power_usage_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

echo $$ > "$LOCK_FILE"

# Clean up lock file and close any open kdialogs on exit
cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    pkill -f "kdialog --title Power" 2>/dev/null
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

LOG_FILE="$HOME/scriptlogs/power_usage.log"
INTERVAL=2700  # 45 Minutes

# Power estimation constants (Fallback if sysfs power_now is missing)
CPU_POWER_IDLE=2.0
CPU_POWER_PER_CORE=4.0
MEM_POWER_PER_GB=0.5

# Battery Thresholds
LOW_BATTERY=20
CRITICAL_BATTERY=10

CUMULATIVE_ENERGY_KWH=0

safe_bc() {
    echo "scale=6; $1" | bc -l 2>/dev/null || echo "0"
}

get_system_info() {
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(safe_bc "$TOTAL_RAM_KB / 1024 / 1024")
    
    # Init CPU tracking
    read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    PREV_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    PREV_IDLE=$idle
    PREV_TIMESTAMP=$(date +%s)
}

get_battery_info() {
    local bat
    bat=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
    [[ -z "$bat" ]] && { echo "No Battery Found"; return 1; }

    local cap=$(cat "$bat/capacity" 2>/dev/null || echo "0")
    local stat=$(cat "$bat/status" 2>/dev/null || echo "Unknown")

    local p_now_uw=$(cat "$bat/power_now" 2>/dev/null || echo "0")
    local v_now_uv=$(cat "$bat/voltage_now" 2>/dev/null || echo "0")
    local c_now_ua=$(cat "$bat/current_now" 2>/dev/null || echo "0")

    local real_watts=0
    if [[ "$p_now_uw" -gt 0 ]]; then
        real_watts=$(safe_bc "$p_now_uw / 1000000")
    elif [[ "$c_now_ua" -gt 0 && "$v_now_uv" -gt 0 ]]; then
        real_watts=$(safe_bc "($c_now_ua * $v_now_uv) / 1000000000000")
    fi

    local e_now_uwh=$(cat "$bat/energy_now" 2>/dev/null || echo "0")
    local c_now_uah=$(cat "$bat/charge_now" 2>/dev/null || echo "0")
    
    local Wh_remaining=0
    if [[ "$e_now_uwh" -gt 0 ]]; then
        Wh_remaining=$(safe_bc "$e_now_uwh / 1000000")
    else
        Wh_remaining=$(safe_bc "($c_now_uah * $v_now_uv) / 1000000000000")
    fi

    local time_str="N/A"
    if [[ $(echo "$real_watts > 0.5" | bc -l) -eq 1 && "$stat" == "Discharging" ]]; then
        local hours_left=$(safe_bc "$Wh_remaining / $real_watts")
        local h=$(echo "$hours_left / 1" | bc)
        local m=$(echo "($hours_left - $h) * 60 / 1" | bc)
        time_str=$(printf "%02dh %02dm" "$h" "$m")
    elif [[ "$stat" == "Charging" ]]; then
        time_str="Charging..."
    else
        time_str="Stationary"
    fi

    echo -e "State: $stat\nLevel: ${cap}%\nLive Draw: ${real_watts}W\nEst. Time: $time_str"
}

get_average_cpu_usage() {
    read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local diff_total=$((total - PREV_TOTAL))
    local diff_idle=$((idle - PREV_IDLE))
    local cpu_avg=$(safe_bc "100 * ($diff_total - $diff_idle) / $diff_total")
    PREV_TOTAL=$total; PREV_IDLE=$idle
    echo "$cpu_avg"
}

get_average_mem_usage() {
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    echo $(safe_bc "100 * ($mem_total - $mem_available) / $mem_total")
}

get_process_power_consumption() {
    local avg_cpu=$(get_average_cpu_usage)
    local avg_mem=$(get_average_mem_usage)
    local est_power=$(safe_bc "$CPU_POWER_IDLE + ($avg_cpu / 100) * $CPU_CORES * $CPU_POWER_PER_CORE + ($avg_mem / 100) * $TOTAL_RAM_GB * $MEM_POWER_PER_GB")
    local now=$(date +%s)
    local elapsed=$((now - PREV_TIMESTAMP))
    local energy_interval_kwh=$(safe_bc "$est_power * ($elapsed / 3600) / 1000")
    CUMULATIVE_ENERGY_KWH=$(safe_bc "$CUMULATIVE_ENERGY_KWH + $energy_interval_kwh")
    PREV_TIMESTAMP=$now
    echo "$avg_cpu|$avg_mem|$est_power|$energy_interval_kwh|$CUMULATIVE_ENERGY_KWH"
}

get_top_processes() {
    # Using Tabs (\t) for flexible alignment in kdialog variable-width fonts
    echo -e "PID\tCOMMAND\t%CPU\t%MEM"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6 | tail -n +2 | while read -r p c cpu mem; do
        # Truncate command to 15 chars to keep tabs predictable
        local short_c="${c:0:15}"
        echo -e "$p\t$short_c\t$cpu\t$mem"
    done
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    get_system_info
    sleep 2

    while true; do
        # 1. Close any previous Power Usage dialogs to prevent stacking
        pkill -f "kdialog --title Power" 2>/dev/null

        # 2. Gather Data
        bat_out=$(get_battery_info)
        current_cap=$(echo "$bat_out" | grep "Level:" | grep -oP '\d+' | head -1)
        
        power_data=$(get_process_power_consumption)
        IFS='|' read -r cpu mem pwr_w int_kwh cum_kwh <<< "$power_data"
        top_p=$(get_top_processes)

        # 3. Format Summary
        summary="==============================
  🔋 POWER STATUS: $(date '+%H:%M:%S')
==============================
$bat_out

💻 LOAD: CPU: $cpu% | MEM: $mem%
Est. Load Power: ${pwr_w}W
Interval Energy: ${int_kwh}kWh

🔝 TOP PROCESSES:
$top_p
=============================="

        # 4. Save to Log
        echo -e "$summary" >> "$LOG_FILE"

        # 5. Launch kdialog based on battery health
        if [ "$current_cap" -le "$CRITICAL_BATTERY" ]; then
            kdialog --title "Power: CRITICAL ${current_cap}%" --error "$summary\n\nPLUG IN NOW!" &
        elif [ "$current_cap" -le "$LOW_BATTERY" ]; then
            kdialog --title "Power: LOW ${current_cap}%" --sorry "$summary" &
        else
            kdialog --title "Power Usage Monitor" --msgbox "$summary" &
        fi

        # 6. Wait for next interval
        sleep "$INTERVAL"
    done
}

main
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
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

# --- Background Task: Swayidle (no longer called at startup; managed in loop) ---
# (start_swayidle function removed; swayidle is started/killed inside main loop)

# --- Execution ---
# Main loop: check video status at the start of every iteration
while true; do
    log_status

    # Re-check video playing status each loop
    video_status=$(is_video_playing)

    if [[ "$video_status" == "playing" ]]; then
        # Video is playing → disable idle detection
        pkill -f "swayidle" 2>/dev/null
        pkill -9 -f "randscreensavers.sh" 2>/dev/null
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

    sleep 10
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# fedora-proactive-sec.sh
# Version 1.3 - Added Gmail Alerts via msmtp

LOCK_FILE="/tmp/security_check_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    echo "Script is already running."
    exit 1
fi

echo $$ > "$LOCK_FILE"

cleanup() {
    log_info "Shutting down security monitor..."
    pkill -P $$ 
    [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]] && rm -f "$LOCK_FILE"
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

mkdir -p "$HOME/scriptlogs"
LOGFILE="$HOME/scriptlogs/fedora-sec-proactive.log"
# Your target email
ALERT_EMAIL="cabpacedilla@gmail.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== Utility Functions =====
notify() { notify-send "🛡️ Security Alert" "$1" & }

send_email() {
    # This sends the alert to your Gmail
    echo -e "Subject: 🛡️ Security Alert from $(hostname)\n\nEvent: $1\nTime: $(date)\nHost: $(hostname)" | msmtp "$ALERT_EMAIL"
}

log_info() { echo -e "${YELLOW}[INFO]${NC} $1" | tee -a "$LOGFILE"; }
log_success() { echo -e "${GREEN}[ OK ]${NC} $1" | tee -a "$LOGFILE"; }

log_warn() { 
    echo -e "${RED}[WARN]${NC} $1" | tee -a "$LOGFILE"
    notify "$1"
    # Send email in the background so the script doesn't lag
    send_email "$1" & 
}

# ===== Enable and Configure auditd =====
enable_auditd() {
    if ! systemctl is-active --quiet auditd; then
        sudo systemctl enable --now auditd
    fi
    AUDIT_RULES="/etc/audit/rules.d/proactive.rules"
    if [ ! -f "$AUDIT_RULES" ]; then
        sudo tee "$AUDIT_RULES" > /dev/null <<EOF
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /bin/su -p x -k su_exec
EOF
        sudo augenrules --load
    fi
}

# ===== New: USB Monitoring =====
monitor_usb() {
    log_info "Starting USB monitor..."
    udevadm monitor --subsystem-match=usb --property | while read -r line; do
        if echo "$line" | grep -q "ID_MODEL="; then
            device=$(echo "$line" | cut -d'=' -f2)
            log_warn "USB Device Detected: $device"
        fi
    done
}

# ===== New: Login Failure Monitoring =====
monitor_logins() {
    log_info "Starting Login monitor..."
    journalctl -f -t login -t gdm-password -t sshd | while read -r line; do
        if echo "$line" | grep -qiE "fail|unauthenticated|invalid user"; then
            log_warn "LOGIN FAILURE: Suspicious access attempt detected!"
        fi
    done
}

# ===== Existing Engines =====
monitor_logs_proactively() {
    log_info "Starting Journal monitoring..."
    journalctl -f -p err..emerg | while read -r line; do
        if echo "$line" | grep -qiE "unauthorized|denied|attack|exploit|rootkit|brute"; then
            log_warn "Threat Detected: $(echo "$line" | cut -c1-60)"
        fi
    done
}

real_time_audit_alerts() {
    log_info "Starting Auditd stream..."
    sudo tail -n0 -f /var/log/audit/audit.log | while read -r line; do
        if echo "$line" | grep -E "passwd_changes|shadow_changes|su_exec|sudoers_changes"; then
            event_type=$(echo "$line" | grep -oP "key=\"\K[^\"]+")
            log_warn "CRITICAL: Sensitive file access! ($event_type)"
        fi
    done
}

monitor_services_loop() {
    while true; do
        for service in auditd firewalld; do
            if ! systemctl is-active --quiet "$service"; then
                log_warn "SERVICE DOWN: $service"
            fi
        done
        sleep 60
    done
}

# ===== Main =====
clear
echo "-------------------------------------------"
echo "    Enhanced Fedora Security Monitor V1.3    "
echo "-------------------------------------------"

enable_auditd

monitor_logs_proactively &
real_time_audit_alerts &
monitor_services_loop &
monitor_usb &
monitor_logins &

log_success "All security engines active."
wait
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# ============================================================================
# Nobara Linux Auto-Update Daemon
# ============================================================================

set -uo pipefail

# ================= CONFIG =================
STATE_DIR="$HOME/.auto_update_state"
LOG_DIR="$HOME/scriptlogs"
LOGFILE="$LOG_DIR/nobara_update_log.txt"
HISTORY_LOG="$LOG_DIR/update_history.csv"
VERIFICATION_LOG_DIR="$STATE_DIR/verifications"
LOCK_FILE="$STATE_DIR/auto_update.lock"

DRY_RUN=false
ENABLE_AUTOREMOVE=false
TIMEOUT_SECONDS=3600
MIN_DISK_SPACE_GB=5
MIN_BATTERY_PCT=30
MAX_LOG_AGE_DAYS=30
MAX_VERIFICATION_AGE_DAYS=90
MAX_NOTIFICATION_ITEMS=30

readonly CRITICAL_SERVICES="NetworkManager.service|sshd.service|dbus.service|systemd-logind.service"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$VERIFICATION_LOG_DIR" "$LOG_DIR/archive" || {
    echo "FATAL: Cannot create directories" >&2
    exit 1
}

# Initialize CSV header for update_history.csv
if [[ ! -s "$HISTORY_LOG" ]]; then
    printf '%s\n' "DATE,STATUS,DNF_COUNT,FLATPAK_COUNT" > "$HISTORY_LOG"
fi

# Persist timestamps
SYSTEM_UPTODATE_LOG_FILE="$STATE_DIR/last_system_uptodate_log"
SYSTEM_UPTODATE_NOTIFY_FILE="$STATE_DIR/last_system_uptodate_notify"

# Pre-update state tracking
PRE_UPDATE_KERNEL_FILE="$STATE_DIR/pre_update_kernel"
PRE_UPDATE_TRANSACTION_FILE="$STATE_DIR/pre_update_transaction"
POST_UPDATE_KERNEL_FILE="$STATE_DIR/post_update_kernel"

# ================= MANUAL ROLLBACK INSTRUCTIONS =================
# If the system fails to boot after an update, you can manually roll back:
#
# 1. Roll back DNF transaction:
#    dnf history list
#    sudo dnf history rollback <TRANSACTION_ID>
#
# 2. Roll back to previous kernel (at GRUB boot menu):
#    Select "Advanced Options" → Previous kernel
#    Or make permanent: sudo grubby --set-default /boot/vmlinuz-<previous-version>
#
# 3. Check saved pre-update state:
#    cat ~/.auto_update_state/pre_update_kernel
#    cat ~/.auto_update_state/pre_update_transaction
#
# The script stores this information to assist with manual recovery.

# ================= ATOMIC FILE WRITES =================
safe_write_timestamp() {
    local target="$1"
    local tmp
    tmp=$(mktemp "$STATE_DIR/tmp.ts.XXXXXX") 2>/dev/null || return 1
    date +%s > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || return 1
}

safe_write_content() {
    local target="$1"
    local content="$2"
    local tmp
    tmp=$(mktemp "$STATE_DIR/tmp.content.XXXXXX") 2>/dev/null || return 1
    printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || return 1
}

mktemp_safe() {
    mktemp "$STATE_DIR/tmp.XXXXXX" 2>/dev/null || {
        echo "FATAL: mktemp failed" >> "$LOGFILE"
        return 1
    }
}

# ================= LOGGING =================
log() {
    printf '%s %s\n' "$(date '+%F %T')" "- $*" | tee -a "$LOGFILE"
}

log_raw() {
    printf '%s\n' "$*" | tee -a "$LOGFILE"
}

log_blank() {
    printf '\n' >> "$LOGFILE"
}

# ================= NOTIFICATION =================
LAST_SYSTEM_UP_TO_DATE_NOTIFY=0

notify() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    
    local message="$1"
    local urgency="${2:-normal}"
    local timeout="${3:-5000}"
    
    if [[ -n "${DISPLAY:-}" ]]; then
        DISPLAY="$DISPLAY" notify-send -u "$urgency" -t "$timeout" "Auto Update" "$message" 2>/dev/null && return 0
    fi
    DISPLAY=":0" notify-send -u "$urgency" -t "$timeout" "Auto Update" "$message" 2>/dev/null && return 0
    return 0
}

notify_with_list() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    
    local title="$1"
    local body="$2"
    local urgency="${3:-normal}"
    local timeout="${4:-0}"
    
    local plain_body="${body//<b>/}"
    plain_body="${plain_body//<\/b>/}"
    [[ ${#plain_body} -gt 3000 ]] && plain_body="${plain_body:0:3000}..."
    
    if [[ -n "${DISPLAY:-}" ]]; then
        DISPLAY="$DISPLAY" notify-send -u "$urgency" -t "$timeout" "Auto Update: $title" "$plain_body" 2>/dev/null && return 0
    fi
    DISPLAY=":0" notify-send -u "$urgency" -t "$timeout" "Auto Update: $title" "$plain_body" 2>/dev/null && return 0
    return 0
}

alert_failure() {
    log "ALERT: $1"
    notify "$1" critical
}

system_up_to_date() {
    local now=$(date +%s)
    local last_log=0
    if [[ -f "$SYSTEM_UPTODATE_LOG_FILE" ]]; then
        last_log=$(<"$SYSTEM_UPTODATE_LOG_FILE")
        [[ ! "$last_log" =~ ^[0-9]+$ ]] && last_log=0
    fi
    
    if [[ $((now - last_log)) -ge 86400 ]]; then
        log "System is up to date."
        safe_write_timestamp "$SYSTEM_UPTODATE_LOG_FILE"
    fi
    notify "System is up to date." normal 3000
}

# ================= INTERNET =================
check_internet() {
    local endpoints=(
        "https://www.google.com"
        "https://www.cloudflare.com"
        "https://www.microsoft.com"
        "https://mirrors.fedoraproject.org"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -fsI --connect-timeout 5 --max-time 10 "$endpoint" >/dev/null 2>&1; then
            return 0
        fi
    done
    
    sudo dnf makecache --timer -q 2>/dev/null && return 0
    return 1
}

# ================= LOCK HANDLING =================
KEEP_ALIVE_PID=""
LOCK_ACQUIRED=false

cleanup_keepalive() {
    if [[ -n "${KEEP_ALIVE_PID:-}" ]] && kill -0 "$KEEP_ALIVE_PID" 2>/dev/null; then
        kill "$KEEP_ALIVE_PID" 2>/dev/null || true
        wait "$KEEP_ALIVE_PID" 2>/dev/null || true
    fi
    KEEP_ALIVE_PID=""
}

cleanup_lock() {
    if [[ "${LOCK_ACQUIRED:-false}" == "true" ]]; then
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        rm -f "$LOCK_FILE" 2>/dev/null || true
        LOCK_ACQUIRED=false
    fi
}

# exec 9>"$LOCK_FILE"
# if ! flock -n 9; then
#     printf '%s - Already running\n' "$(date '+%F %T')" | tee -a "$LOGFILE"
#     exit 1
# fi
# LOCK_ACQUIRED=true
# trap 'cleanup_keepalive; cleanup_lock' EXIT INT TERM

# ================= SAFETY CHECKS =================
check_package_lock() {
    pgrep -x dnf >/dev/null 2>&1 && { log "DNF already running, skipping..."; return 1; }
    pgrep -x rpm >/dev/null 2>&1 && { log "RPM already running, skipping..."; return 1; }
    pgrep -x packagekitd >/dev/null 2>&1 && { log "PackageKit running, skipping..."; return 1; }
    return 0
}

check_disk() {
    local avail
    avail=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
    
    if [[ -z "$avail" || ! "$avail" =~ ^[0-9]+$ ]]; then
        log "Could not determine disk space (got: '$avail')"
        return 1
    fi
    
    if [[ "$avail" -lt "$MIN_DISK_SPACE_GB" ]]; then
        log "Low disk space: ${avail}GB available"
        return 1
    fi
    return 0
}

BATTERY_WARNING_LOGGED=false

check_battery() {
    shopt -s nullglob
    local bat_files=(/sys/class/power_supply/BAT* /sys/class/power_supply/BATT*)
    shopt -u nullglob
    
    local found=false
    local cap status
    
    for bat in "${bat_files[@]}"; do
        [[ -f "$bat/capacity" ]] || continue
        found=true
        cap=$(<"$bat/capacity")
        status=$(<"$bat/status")
        
        [[ "$cap" =~ ^[0-9]+$ ]] || { log "Invalid battery capacity"; return 1; }
        
        if [[ "$status" != "Charging" && "$status" != "Full" && "$cap" -lt "$MIN_BATTERY_PCT" ]]; then
            log "Low battery: ${cap}% ($status)"
            return 1
        fi
    done
    
    if ! $found && command -v upower >/dev/null 2>&1; then
        local dev=$(upower -e 2>/dev/null | grep -i BAT | head -1)
        if [[ -n "$dev" ]]; then
            cap=$(upower -i "$dev" 2>/dev/null | awk '/percentage/ {gsub(/%/,"",$2); print $2}')
            status=$(upower -i "$dev" 2>/dev/null | awk '/state/ {print $2}')
            if [[ -n "$cap" && "$cap" =~ ^[0-9]+$ ]] && \
               [[ "$status" != "charging" && "$status" != "fully-charged" && "$cap" -lt "$MIN_BATTERY_PCT" ]]; then
                log "Low battery: ${cap}%"
                return 1
            fi
            found=true
        fi
    fi
    
    if ! $found && ! $BATTERY_WARNING_LOGGED; then
        log "No battery detected (desktop mode)"
        BATTERY_WARNING_LOGGED=true
    fi
    return 0
}

# ================= COOLDOWN FUNCTIONS =================
can_notify_warning() {
    local last_warning_file="$STATE_DIR/last_warning_notify"
    [[ ! -f "$last_warning_file" ]] && return 0
    local last_time=$(<"$last_warning_file")
    [[ ! "$last_time" =~ ^[0-9]+$ ]] && last_time=0
    [[ $(( $(date +%s) - last_time )) -gt 86400 ]]
}

can_notify_restored() {
    local last_restored_file="$STATE_DIR/last_restored_notify"
    [[ ! -f "$last_restored_file" ]] && return 0
    local last_time=$(<"$last_restored_file")
    [[ ! "$last_time" =~ ^[0-9]+$ ]] && last_time=0
    [[ $(( $(date +%s) - last_time )) -gt 3600 ]]
}

update_warning_timestamp() { safe_write_timestamp "$STATE_DIR/last_warning_notify"; }
update_restored_timestamp() { safe_write_timestamp "$STATE_DIR/last_restored_notify"; }
update_success_timestamp() { safe_write_timestamp "$STATE_DIR/last_success"; }

# ================= PRE-UPDATE STATE TRACKING =================
track_pre_update_state() {
    local current_kernel=$(uname -r)
    echo "$current_kernel" > "$PRE_UPDATE_KERNEL_FILE"
    log "📝 Pre-update kernel saved for reference: $current_kernel"
    
    local trans_id=$(dnf history list 2>/dev/null | grep -v "^ID" | head -1 | awk '{print $1}')
    if [[ -n "$trans_id" && "$trans_id" =~ ^[0-9]+$ ]]; then
        echo "$trans_id" > "$PRE_UPDATE_TRANSACTION_FILE"
        log "📝 Pre-update transaction ID saved: $trans_id"
        log "   Manual rollback: sudo dnf history rollback $trans_id"
    else
        log "⚠️ Could not determine current DNF transaction ID"
    fi
}

# ================= POST-UPDATE VERIFICATION =================
verify_system_health() {
    local verification_log="$VERIFICATION_LOG_DIR/verification_$(date +%F-%H%M%S).log"
    local verification_failed=0
    local has_critical_failure=false
    local new_failures=""
    local update_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "Running post-update system verification..."
    
    local failed_services
    failed_services=$(systemctl --failed --no-legend 2>/dev/null | grep -v "drkonqi-coredump-processor" | awk '{print $1}' || true)
    
    if [[ -n "$failed_services" ]]; then
        log "WARNING: Failed services detected:"
        while IFS= read -r service; do
            log "  - $service"
        done <<< "$failed_services"
        
        while IFS= read -r service; do
            if [[ -n "$service" ]] && echo "$service" | grep -qiE "$CRITICAL_SERVICES"; then
                log "CRITICAL: Critical service failure: $service"
                has_critical_failure=true
                new_failures+="  • $service (CRITICAL)\n"
                verification_failed=1
            fi
        done <<< "$failed_services"
    else
        log "All services running normally."
    fi
    
    if findmnt -n -o OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
        log "ERROR: Root filesystem is mounted read-only!"
        verification_failed=1
    else
        log "Root filesystem writable."
    fi
    
    local critical_errors
    critical_errors=$(journalctl --since "$update_start_time" -p 2 --no-pager 2>/dev/null | \
        grep -v -E "drkonqi|coredump|wireplumber.*crashed" | \
        head -10 || true)
    if [[ -n "$critical_errors" ]]; then
        log "WARNING: Critical kernel errors detected since update start"
        verification_failed=1
    else
        log "No critical kernel errors found."
    fi
    
    {
        echo "=========================================="
        echo "Nobara Post-Update Verification Report"
        echo "=========================================="
        echo "Time: $(date '+%F %T')"
        echo "Host: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo ""
        echo "1. FAILED SERVICES:"
        echo "------------------"
        [[ -n "$failed_services" ]] && echo "$failed_services" || echo "None"
        echo ""
        echo "2. CRITICAL SERVICE FAILURES:"
        echo "----------------------------"
        [[ "$has_critical_failure" == "true" ]] && echo "YES - Manual intervention recommended" || echo "None"
        echo ""
        echo "3. FILESYSTEM STATUS:"
        echo "--------------------"
        if findmnt -n -o OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
            echo "READ-ONLY - CRITICAL"
        else
            echo "Writable - OK"
        fi
        echo ""
        echo "4. KERNEL ERRORS (since update start):"
        echo "--------------------------------------"
        echo "$critical_errors"
        echo ""
        echo "=========================================="
        [[ $verification_failed -eq 1 ]] && echo "STATUS: ISSUES DETECTED" || echo "STATUS: HEALTHY"
        echo "=========================================="
        
        if [[ $verification_failed -eq 1 ]]; then
            echo ""
            echo "MANUAL ROLLBACK INFO:"
            echo "--------------------"
            echo "To roll back this update:"
            echo "  sudo dnf history rollback $(cat "$PRE_UPDATE_TRANSACTION_FILE" 2>/dev/null || echo 'N/A')"
            echo "  Or select previous kernel at GRUB boot menu"
        fi
    } > "$verification_log" 2>&1
    
    cat "$verification_log" >> "$LOGFILE"
    
    if [[ $verification_failed -eq 1 ]]; then
        log "Post-update verification found issues - see $verification_log"
        if [[ "$has_critical_failure" == "true" ]]; then
            notify_with_list "⚠️ CRITICAL ISSUES DETECTED" "Critical services failed after update:\n\n$new_failures\n\nCheck log: $verification_log" "critical" 0
        else
            notify "Post-update issues detected - check verification log" normal
        fi
    else
        log "Post-update verification passed - system healthy"
    fi
    
    find "$VERIFICATION_LOG_DIR" -type f -name "verification_*.log" -mtime +"$MAX_VERIFICATION_AGE_DAYS" -delete 2>/dev/null || true
    return $verification_failed
}

# ================= SECURITY CHECKS =================
post_update_security_check() {
    log "Running post-update security checks..."

    if command -v aa-status >/dev/null 2>&1; then
        aa-status >> "$LOGFILE" 2>&1 || log "AppArmor check failed"
    fi

    for svc in NetworkManager sshd dbus systemd-logind firewalld auditd; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log "✅ $svc is active"
        else
            log "⚠️ WARNING: $svc is not active"
        fi
    done

    log "Listening ports (ss -tulpn):"
    ss -tulpn 2>/dev/null | head -50 | while read -r line; do
        log_raw "  $line"
    done

    local auth_failures
    auth_failures=$(journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep -c "Failed password" || echo 0)
    if [[ $auth_failures -gt 0 ]]; then
        log "⚠️ $auth_failures authentication failures detected in last hour"
        journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep "Failed password" | tail -10 >> "$LOGFILE"
    else
        log "✅ No authentication failures in last hour"
    fi

    log "Recent kernel errors (last 50 lines):"
    journalctl -b -p 3 --no-pager 2>/dev/null | tail -50 | while read -r line; do
        log_raw "  $line"
    done

    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null | grep -v "drkonqi-coredump-processor" | awk '{print $1}' || true)
    if [[ -n "$failed_units" ]]; then
        log "⚠️ Failed systemd units detected:"
        while IFS= read -r unit; do
            log "  - $unit"
        done <<< "$failed_units"
    else
        log "✅ No failed systemd units"
    fi

    log "Post-update security checks completed."
}

# ================= REBOOT TRACKING =================
REBOOT_NOTIFIED_FILE="$STATE_DIR/reboot_notified"

is_reboot_needed() {
    local installed_kernel
    local running_kernel
    
    installed_kernel=$(rpm -q kernel-core --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-core-//')
    [[ -z "$installed_kernel" ]] && installed_kernel=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-//')
    running_kernel=$(uname -r)
    
    [[ -n "$installed_kernel" && "$installed_kernel" != "$running_kernel" ]]
}

clear_reboot_notification_if_not_needed() {
    if is_reboot_needed; then
        log "DEBUG: reboot IS needed (kernel versions differ)"
    else
        log "DEBUG: reboot NOT needed (kernel versions match)"
    fi
    
    if ! is_reboot_needed; then
        if [[ -f "$REBOOT_NOTIFIED_FILE" ]]; then
			local content
            content=$(<"$REBOOT_NOTIFIED_FILE")
            if [[ "$(tr -d '[:space:]' <<< "$content")" == "true" ]]; then
                safe_write_content "$REBOOT_NOTIFIED_FILE" "false"
                log "Cleared reboot notification (kernel versions now match)"
            fi
        fi
        REBOOT_NOTIFIED=false
        return 0
    fi
    return 1
}

REBOOT_NOTIFIED=false
if [[ -f "$REBOOT_NOTIFIED_FILE" ]]; then
    content=$(<"$REBOOT_NOTIFIED_FILE")
    if [[ "$(tr -d '[:space:]' <<< "$content")" == "true" ]]; then
        REBOOT_NOTIFIED=true
        log "DEBUG: Loaded REBOOT_NOTIFIED=true from file"
    else
        log "DEBUG: Loaded REBOOT_NOTIFIED=false from file"
    fi
fi

quick_verify() {
    local issues_found=0
    
    clear_reboot_notification_if_not_needed
    
    if systemctl --failed --no-legend 2>/dev/null | grep -v "drkonqi-coredump-processor" | grep -q "."; then
        log "Quick check: Failed services detected"
        notify "System degraded - check 'systemctl --failed'" critical
        issues_found=1
    fi
    
    local installed_kernel
    local running_kernel
    installed_kernel=$(rpm -q kernel-core --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-core-//')
    [[ -z "$installed_kernel" ]] && installed_kernel=$(rpm -q kernel --last 2>/dev/null | head -n1 | awk '{print $1}' | sed 's/kernel-//')
    running_kernel=$(uname -r)
    
    log "DEBUG: Kernel check - installed: $installed_kernel, running: $running_kernel"
    
    if [[ -n "$installed_kernel" && "$installed_kernel" != "$running_kernel" ]]; then
        if [[ "$REBOOT_NOTIFIED" != "true" ]]; then
            log "Quick check: Reboot recommended - kernel updated to $installed_kernel (current: $running_kernel)"
            log "   Manual rollback if needed: sudo grubby --set-default /boot/vmlinuz-$running_kernel"
            notify "🔁 RESTART REQUIRED!\n\nKernel updated from $running_kernel to $installed_kernel\nPlease reboot your system." critical 0
            REBOOT_NOTIFIED=true
            safe_write_content "$REBOOT_NOTIFIED_FILE" "true"
            log "DEBUG: Set REBOOT_NOTIFIED=true, wrote to file"
        else
            log "DEBUG: Reboot needed but already notified (REBOOT_NOTIFIED=$REBOOT_NOTIFIED)"
        fi
    else
        if [[ "$REBOOT_NOTIFIED" == "true" ]]; then
            safe_write_content "$REBOOT_NOTIFIED_FILE" "false"
            REBOOT_NOTIFIED=false
            log "Reboot notification cleared (kernel versions now match)"
        else
            log "DEBUG: No reboot needed and REBOOT_NOTIFIED=$REBOOT_NOTIFIED (no action)"
        fi
    fi
    
    return $issues_found
}

# ================= FETCH UPDATES =================
fetch_pending_updates() {
    local tmp
    tmp=$(mktemp_safe) || return 1
    
    {
        sudo dnf makecache --timer -q >> "$LOGFILE" 2>&1 || true
        
        local dnf_rc=0
        sudo dnf check-update > "$tmp" 2>/dev/null || dnf_rc=$?
        
        if [[ $dnf_rc -eq 1 ]]; then
            log "DNF check-update encountered an error"
        elif [[ $dnf_rc -eq 100 ]]; then
            log "DNF updates available"
        fi
        
        grep -E '\.(x86_64|noarch|i686|aarch64)' "$tmp" 2>/dev/null \
            | awk '{print $1 " (" $2 ")"}' > "$STATE_DIR/dnf_list" || true
        
        if command -v flatpak >/dev/null 2>&1; then
            flatpak update --appstream --noninteractive >> "$LOGFILE" 2>&1 || true
            flatpak remote-ls --updates --columns=application,version 2>/dev/null \
                | tail -n +2 | awk '{if(NF>=2) print $1 " (" $2 ")"; else print $1}' \
                > "$STATE_DIR/flatpak_list" 2>/dev/null || true
        else
            > "$STATE_DIR/flatpak_list"
        fi
        
        rm -f "$tmp"
    } || {
        rm -f "$tmp"
        return 1
    }
}

updates_available() {
    [[ -s "$STATE_DIR/dnf_list" || -s "$STATE_DIR/flatpak_list" ]]
}

# ================= BUILD NOTIFICATION LISTS =================
build_update_list() {
    local dnf_list=""
    local flatpak_list=""
    local dnf_count=0
    local flatpak_count=0
    local max_items=$((MAX_NOTIFICATION_ITEMS > 0 ? MAX_NOTIFICATION_ITEMS : 1))
    
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        dnf_count=$(wc -l < "$STATE_DIR/dnf_list")
        dnf_list="📦 Packages ($dnf_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $max_items ]]; do
            dnf_list+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/dnf_list"
        [[ $dnf_count -gt $max_items ]] && dnf_list+="  ... and $((dnf_count - max_items)) more\n"
    fi
    
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
        flatpak_list="🟢 Flatpaks ($flatpak_count):\n"
        local i=0
        while IFS= read -r line && [[ $i -lt $max_items ]]; do
            flatpak_list+="  • $line\n"
            ((i++))
        done < "$STATE_DIR/flatpak_list"
        [[ $flatpak_count -gt $max_items ]] && flatpak_list+="  ... and $((flatpak_count - max_items)) more\n"
    fi
    
    local combined_list=""
    [[ -n "$dnf_list" ]] && combined_list="$dnf_list"
    if [[ -n "$flatpak_list" ]]; then
        [[ -n "$combined_list" ]] && combined_list+="\n"
        combined_list+="$flatpak_list"
    fi
    
    printf '%s\n' "$combined_list"
    printf '%d\n' "$((dnf_count + flatpak_count))" > "$STATE_DIR/update_count"
}

# ================= NOTIFICATIONS =================
notify_pending() {
    local update_list
    local total_count
    
    update_list=$(build_update_list)
    total_count=$(cat "$STATE_DIR/update_count" 2>/dev/null || echo 0)
    
    if [[ -n "$update_list" ]]; then
        notify_with_list "📦 Updates Detected" "Installing $total_count updates...\n\n$update_list" "normal" 0
    else
        notify "Found updates: $total_count items" normal
    fi
    
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        log_raw "Pending packages:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/dnf_list"
    fi
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        log_raw "Pending flatpaks:"
        while IFS= read -r line; do log_raw "  $line"; done < "$STATE_DIR/flatpak_list"
    fi
}

notify_complete() {
    local update_list
    local total_count
    
    update_list=$(build_update_list)
    total_count=$(cat "$STATE_DIR/update_count" 2>/dev/null || echo 0)
    
    if [[ -n "$update_list" ]]; then
        notify_with_list "✅ Updates Complete" "Successfully updated $total_count items!\n\n$update_list" "normal" 10000
    else
        notify "Updates completed successfully" normal
    fi
    
    > "$STATE_DIR/dnf_list" 2>/dev/null || true
    > "$STATE_DIR/flatpak_list" 2>/dev/null || true
}

# ================= LOG UPDATED PACKAGES (Direct to HISTORY_LOG) =================
log_updated_packages() {
    local date_str=$(date '+%Y-%m-%d')
    
    # Log DNF packages directly to HISTORY_LOG
    if [[ -s "$STATE_DIR/dnf_list" ]]; then
        while IFS= read -r line; do
            printf '%s %s\n' "$date_str" "DNF $line" >> "$HISTORY_LOG"
        done < "$STATE_DIR/dnf_list"
    fi
    
    # Log Flatpak packages directly to HISTORY_LOG
    if [[ -s "$STATE_DIR/flatpak_list" ]]; then
        while IFS= read -r line; do
            printf '%s %s\n' "$date_str" "Flatpak $line" >> "$HISTORY_LOG"
        done < "$STATE_DIR/flatpak_list"
    fi
}

# ================= RUN UPDATES =================
LAST_DNF_EXIT=""
LAST_FLATPAK_EXIT=""

run_updates() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY_RUN] Skipping actual updates."
        LAST_DNF_EXIT="dry-run"
        LAST_FLATPAK_EXIT="dry-run"
        return 0
    fi

    check_package_lock || { 
        LAST_DNF_EXIT="locked"
        LAST_FLATPAK_EXIT="skipped"
        return 1 
    }

    local DNF_EXIT=1 FLATPAK_EXIT=1
    local UPDATE_SUCCESS=1
    local TEMP_SYNC_LOG
    TEMP_SYNC_LOG=$(mktemp_safe) || return 1

    sudo -n true 2>/dev/null || {
        log "ERROR: Cannot obtain sudo privileges"
        LAST_DNF_EXIT="no-sudo"
        LAST_FLATPAK_EXIT="no-sudo"
        rm -f "$TEMP_SYNC_LOG"
        return 1
    }

    track_pre_update_state

    (
        while kill -0 "$PPID" 2>/dev/null; do
            sudo -n true 2>/dev/null
            sleep 60
        done
    ) &
    KEEP_ALIVE_PID=$!

    log_raw "=============================="
    log_raw "Starting Nobara System Update"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo nobara-sync all 2>&1 | tee -a "$LOGFILE" > "$TEMP_SYNC_LOG"
    DNF_EXIT=${PIPESTATUS[0]}
    log_raw "Nobara-sync exit code: $DNF_EXIT"
    
    [[ $DNF_EXIT -eq 124 ]] && log_raw "WARNING: nobara-sync timed out"
    [[ $DNF_EXIT -eq 137 ]] && log_raw "WARNING: nobara-sync was killed"

    log_blank
    log_raw "=============================="
    log_raw "Starting Flatpak Updates"
    log_raw "=============================="
    
    timeout "$TIMEOUT_SECONDS" sudo flatpak update -y --no-static-deltas 2>&1 | tee -a "$LOGFILE"
    FLATPAK_EXIT=${PIPESTATUS[0]}
    log_raw "Flatpak (system) exit code: $FLATPAK_EXIT"
    
    [[ $FLATPAK_EXIT -eq 124 ]] && log_raw "WARNING: flatpak (system) timed out"
    
    if [[ $FLATPAK_EXIT -ne 0 ]]; then
        log "Running flatpak repair..."
        sudo flatpak repair --system >> "$LOGFILE" 2>&1 || true
        flatpak repair --user >> "$LOGFILE" 2>&1 || true
    fi
    
    if [[ $FLATPAK_EXIT -eq 0 ]]; then
        timeout "$TIMEOUT_SECONDS" flatpak update --user -y 2>&1 | tee -a "$LOGFILE"
        FLATPAK_EXIT=${PIPESTATUS[0]}
        log_raw "Flatpak (user) exit code: $FLATPAK_EXIT"
    fi

    LAST_DNF_EXIT="$DNF_EXIT"
    LAST_FLATPAK_EXIT="$FLATPAK_EXIT"

    log_blank
    log_raw "=============================="
    log_raw "Update Summary"
    log_raw "=============================="
    
    if [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -eq 0 ]]; then
        UPDATE_SUCCESS=0
        log_raw "All updates completed successfully"
    elif [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -ne 0 ]]; then
        log_raw "DNF succeeded but Flatpak failed (exit: $FLATPAK_EXIT)"
        alert_failure "Flatpak updates failed"
        UPDATE_SUCCESS=1
    elif [[ $DNF_EXIT -ne 0 && $FLATPAK_EXIT -eq 0 ]]; then
        log_raw "DNF/Nobara-sync failed (exit: $DNF_EXIT)"
        alert_failure "System update failed"
        UPDATE_SUCCESS=1
    else
        log_raw "Both DNF and Flatpak updates failed"
        alert_failure "All updates failed"
        UPDATE_SUCCESS=1
    fi
    
    if [[ $UPDATE_SUCCESS -eq 0 ]]; then
        uname -r > "$POST_UPDATE_KERNEL_FILE" 2>/dev/null || true
        
        # Log individual packages directly to HISTORY_LOG
        log_updated_packages
        
        notify_complete
        
        if [[ "$ENABLE_AUTOREMOVE" == "true" ]]; then
            log "Running post-update cleanup with autoremove..."
            sudo dnf autoremove -y --setopt=clean_requirements_on_remove=False 2>&1 | tee -a "$LOGFILE" || true
        else
            log "Skipping autoremove (disabled)"
        fi
        sudo dnf clean packages 2>&1 | tee -a "$LOGFILE"
        sudo flatpak uninstall --unused -y 2>&1 | tee -a "$LOGFILE"
        flatpak uninstall --user --unused -y 2>&1 | tee -a "$LOGFILE"
        
        log_blank
        log_raw "=============================="
        log_raw "Post-Update Verification"
        log_raw "=============================="
        verify_system_health || true
        
        post_update_security_check
    fi

    rm -f "$TEMP_SYNC_LOG" 2>/dev/null || true
    cleanup_keepalive
    return "$UPDATE_SUCCESS"
}

# ================= ROTATE LOGS =================
rotate_logs() {
    find "$LOG_DIR" -type f -name "*.txt" -mtime +"$MAX_LOG_AGE_DAYS" -delete 2>/dev/null
}

# ================= SMART SLEEP =================
smart_sleep() {
    local duration=$1
    local interval=5
    local elapsed=0

    while (( elapsed < duration )); do
        local remaining=$(( duration - elapsed ))
        if (( remaining < interval )); then
            sleep "$remaining" 2>/dev/null || break
            break
        fi
        sleep "$interval" 2>/dev/null || break
        elapsed=$(( elapsed + interval ))
    done
}

# ================= MAIN LOOP =================
main() {
    trap 'log "Received termination signal, exiting..."; cleanup_keepalive; cleanup_lock; exit 0' SIGTERM SIGINT
    
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
        [[ "$arg" == "--enable-autoremove" ]] && ENABLE_AUTOREMOVE=true && log "AUTOREMOVE ENABLED"
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Auto-update service starting - DRY RUN MODE"
    else
        log "Auto-update service starting"
    fi
    
    if [[ "$ENABLE_AUTOREMOVE" == "true" ]]; then
        log "WARNING: autoremove is ENABLED (high-risk operation)"
    fi

    log "Manual rollback info stored in: $STATE_DIR/"
    log "  - Pre-update kernel: $PRE_UPDATE_KERNEL_FILE"
    log "  - Pre-update transaction: $PRE_UPDATE_TRANSACTION_FILE"

    local retry_delay=60
    local max_delay=3600
    local next_run=$(date +%s)

    while true; do
        if ! check_internet; then
            local offline_start=$(date +%s)
            local sleep_time=60
            local max_sleep=3600
            local notified_prolonged=false
            
            log "🌐 No internet connection detected"
            if can_notify_warning; then
                notify "🌐 No internet connection - updates postponed" "normal" 5000
                update_warning_timestamp
            fi
            
            while ! check_internet; do
                local offline_min=$(( ($(date +%s) - offline_start) / 60 ))
                log "Still offline after ${offline_min} minutes"
                if (( offline_min >= 30 )) && [[ "$notified_prolonged" == "false" ]]; then
                    if can_notify_warning; then
                        notify "Still offline after 30 minutes" "normal" 5000
                        update_warning_timestamp
                        notified_prolonged=true
                    fi
                fi
                smart_sleep "$sleep_time"
                sleep_time=$(( sleep_time * 2 > max_sleep ? max_sleep : sleep_time * 2 ))
            done
            
            log "🌐 Internet connection restored"
            if can_notify_restored; then
                notify "Internet connection restored" "normal" 5000
                update_restored_timestamp
            fi
        fi
        
        if ! check_disk; then 
            log "Disk check failed, retrying in ${retry_delay}s"
            smart_sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi
        
        if ! check_battery; then 
            log "Battery check failed, retrying in ${retry_delay}s"
            smart_sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 > max_delay ? max_delay : retry_delay * 2 ))
            continue
        fi

        retry_delay=60
        fetch_pending_updates

        if updates_available; then
            # Get counts BEFORE update
            local dnf_count=0
            local flatpak_count=0
            [[ -s "$STATE_DIR/dnf_list" ]] && dnf_count=$(wc -l < "$STATE_DIR/dnf_list")
            [[ -s "$STATE_DIR/flatpak_list" ]] && flatpak_count=$(wc -l < "$STATE_DIR/flatpak_list")
            
            # Log the pending summary: OK,DNF:X,FLATPAK:Y
            printf '%s,OK,DNF:%d,FLATPAK:%d\n' "$(date '+%F')" "$dnf_count" "$flatpak_count" >> "$HISTORY_LOG"
            
            notify_pending
            
            if run_updates; then
                # Individual packages are logged inside run_updates() by log_updated_packages()
                
                # Log final state after updates: OK,DNF:0,FLATPAK:0
                printf '%s,OK,DNF:0,FLATPAK:0\n' "$(date '+%F')" >> "$HISTORY_LOG"
                
                log "Update cycle completed successfully"
                update_success_timestamp
                system_up_to_date
                quick_verify
            else
                printf '%s,FAIL,DNF:%s,FLATPAK:%s\n' "$(date '+%F')" "${LAST_DNF_EXIT:-unknown}" "${LAST_FLATPAK_EXIT:-unknown}" >> "$HISTORY_LOG"
                log "Update cycle failed"
            fi
        else
            # No updates available
            printf '%s,OK,DNF:0,FLATPAK:0\n' "$(date '+%F')" >> "$HISTORY_LOG"
            system_up_to_date
            quick_verify
        fi

        rotate_logs
        
        local jitter=$((RANDOM % 120 - 60))
        local adjusted_interval=$((3600 + jitter))
        
        next_run=$((next_run + adjusted_interval))
        local now=$(date +%s)
        if (( next_run < now - adjusted_interval )); then
            log "WARNING: Scheduler falling behind, resetting"
            next_run=$((now + adjusted_interval))
        fi
        
        local sleep_time=$((next_run - now))
        [[ $sleep_time -gt 0 ]] && smart_sleep "$sleep_time"
    done
}

main "$@"
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# =============================================================================
# CAREER INTELLIGENCE ENGINE v12.8 – PIPE‑DELIMITED ACQUISITION
# Architecture: Acquire → Normalize → Observe → Resolve → Infer → Query → Notify
# =============================================================================
# FIXES in v12.8:
# - Acquisition now uses the Python scraper in its default pipe‑delimited mode.
# - No --json flag needed – avoids JSON parsing errors.
# - Each job line is converted to JSON inside the Bash script.
# - All previous classifier and database fixes retained.
# =============================================================================

set -Euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
CIE_DB_DIR="${HOME}/Documents/bin"
CIE_DB_NAME="cie.db"
CIE_DB_PATH="${CIE_DB_DIR}/${CIE_DB_NAME}"
CIE_LOG_DIR="${HOME}/scriptlogs/cie"
CIE_EMAIL_TO="cabpacedilla@gmail.com"
CIE_SMTP_ACCOUNT="default"
CIE_MAX_RECOMMENDATIONS=20
CIE_CUTOFF_MINUTES=1440
CIE_LOCK_FILE="${CIE_DB_DIR}/cie_engine.lock"
CIE_RETENTION_DAYS=365
CIE_LOG_RETENTION_DAYS=90
CIE_CLASSIFIER_NAME="domain_classifier"
CIE_CLASSIFIER_VERSION="1.0"
CIE_MAX_RETRIES=5
CIE_MIN_SQLITE_VERSION="3.35.0"
LOCK_HELD=false

# Python scraper location
CIE_SCRAPER="${CIE_DB_DIR}/find_jobs.py"

# -----------------------------------------------------------------------------
# KEYWORDS (copied from visa_job_search.sh)
# -----------------------------------------------------------------------------
readonly QA_KEYWORDS=(
    "QA" "Quality Assurance" "Quality Engineer" "Test Engineer" "Software Test"
    "SDET" "Automation Test" "Test Automation" "Quality Engineering"
    "Senior QA" "Senior Quality Engineer" "Senior SDET"
    "QA Lead" "Senior QA Lead" "Lead QA Engineer" "QA Manager" "Quality Assurance Manager"
    "Test Architect" "QA Architect" "Test Automation Architect" "Quality Engineering Architect"
    "Hardware QA" "Firmware Test" "Integration Test" "Embedded QA" "Systems QA"
    "AI QA" "ML Test Engineer" "Fintech QA" "Payments QA"
)

mkdir -p "${CIE_DB_DIR}" "${CIE_LOG_DIR}"

# -----------------------------------------------------------------------------
# DEPENDENCY CHECK
# -----------------------------------------------------------------------------
_check_dependencies() {
    local deps=("sqlite3" "jq" "perl" "flock" "msmtp" "gawk" "md5sum" "python3")
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required dependencies: ${missing[*]}" >&2
        exit 1
    fi
    if [[ ! -f "$CIE_SCRAPER" ]]; then
        echo "ERROR: Scraper script not found: $CIE_SCRAPER" >&2
        exit 1
    fi
    if ! python3 -c "import playwright" 2>/dev/null; then
        echo "ERROR: Playwright not installed. Run: pip install playwright && playwright install chromium" >&2
        exit 1
    fi
}

_check_dependencies

# -----------------------------------------------------------------------------
# SQLITE VERSION CHECK
# -----------------------------------------------------------------------------
_check_sqlite_version() {
    local version
    version=$(sqlite3 ":memory:" "SELECT sqlite_version();" 2>/dev/null)
    if [[ -z "$version" ]]; then
        echo "ERROR: Could not determine SQLite version." >&2
        exit 1
    fi
    local required="$CIE_MIN_SQLITE_VERSION"
    if ! awk -v req="$required" -v ver="$version" '
        BEGIN {
            split(ver,a,"."); split(req,b,".");
            for(i=1;i<=3;i++) {
                a[i]+=0; b[i]+=0;
                if(a[i] < b[i]) exit 1;
                if(a[i] > b[i]) exit 0;
            }
            exit 0;
        }'; then
        echo "ERROR: SQLite version $version is below required $required." >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >&2
    echo "$msg" >> "${CIE_LOG_DIR}/cie_$(date +%Y%m%d).log"
}

sql_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# -----------------------------------------------------------------------------
# LOCKING
# -----------------------------------------------------------------------------
_acquire_lock() {
    exec 200>"$CIE_LOCK_FILE"
    if ! flock -n 200; then
        log "ERROR: Another instance is running. Exiting."
        return 1
    fi
    LOCK_HELD=true
    log "Lock acquired."
    return 0
}

_release_lock() {
    if $LOCK_HELD; then
        flock -u 200 2>/dev/null || true
        exec 200>&- 2>/dev/null || true
        LOCK_HELD=false
        log "Lock released."
    fi
}
trap '_release_lock' EXIT INT TERM

# -----------------------------------------------------------------------------
# CACHED TAXONOMY & CLASSIFIERS
# -----------------------------------------------------------------------------
declare -A CIE_TAXONOMY
declare -A CIE_CLASSIFIERS

_cache_taxonomy() {
    while IFS='|' read -r id name; do
        CIE_TAXONOMY["$name"]="$id"
    done < <(sqlite3 "$CIE_DB_PATH" "SELECT id, name FROM taxonomy;")
}

_cache_classifiers() {
    while IFS='|' read -r id name version; do
        CIE_CLASSIFIERS["$name|$version"]="$id"
    done < <(sqlite3 "$CIE_DB_PATH" "SELECT id, name, version FROM classifiers;")
}

_get_concept_id() { echo "${CIE_TAXONOMY[$1]:-}"; }
_get_classifier_id() { echo "${CIE_CLASSIFIERS["$1|$2"]:-}"; }

# -----------------------------------------------------------------------------
# MIGRATION APPLICATION
# -----------------------------------------------------------------------------
_apply_migration() {
    local version="$1"
    local sql="$2"
    local applied
    applied=$(sqlite3 "$CIE_DB_PATH" "SELECT 1 FROM schema_version WHERE version='$version';" 2>/dev/null)
    if [[ -n "$applied" ]]; then
        return 0
    fi

    local cleaned_sql
    cleaned_sql=$(echo "$sql" | sed 's/--.*$//g' | perl -0777 -pe 's/\/\*.*?\*\///gs')

    if echo "$cleaned_sql" | grep -qiE '\<(BEGIN|COMMIT|ROLLBACK)\>'; then
        log "ERROR: Migration $version contains transaction control statements."
        exit 1
    fi

    log "Applying migration $version"
    if sqlite3 "$CIE_DB_PATH" <<EOF
BEGIN;
$sql;
INSERT INTO schema_version (version, applied_at) VALUES ('$version', datetime('now'));
COMMIT;
EOF
    then
        log "Migration $version applied."
    else
        log "ERROR: Migration $version failed."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# DATABASE
# -----------------------------------------------------------------------------
_db_init() {
    log "Initialising database..."
    _check_sqlite_version

    if sqlite3 "$CIE_DB_PATH" <<'EOF'
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS schema_version (version TEXT PRIMARY KEY, applied_at TEXT);
CREATE TABLE IF NOT EXISTS data_bootstrap (key TEXT PRIMARY KEY, value TEXT);
EOF
    then
        log "Base schema created."
    else
        log "ERROR: Failed to create base schema."
        exit 1
    fi

    sqlite3 "$CIE_DB_PATH" "PRAGMA wal_checkpoint(PASSIVE);" >/dev/null 2>&1
    local integrity
    integrity=$(sqlite3 "$CIE_DB_PATH" "PRAGMA integrity_check;" 2>/dev/null)
    if [[ "$integrity" != "ok" ]]; then
        log "ERROR: Database integrity check failed: $integrity"
        exit 1
    fi

    # ---- Migrations ----
    _apply_migration "001" "
CREATE TABLE IF NOT EXISTS taxonomy (id INTEGER PRIMARY KEY, concept_type TEXT NOT NULL, name TEXT NOT NULL UNIQUE);
CREATE TABLE IF NOT EXISTS classifiers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, version TEXT NOT NULL, rule_hash TEXT, description TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(name, version));
CREATE TABLE IF NOT EXISTS companies (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, website TEXT, first_seen TIMESTAMP, last_seen TIMESTAMP);
CREATE TABLE IF NOT EXISTS evidence (id INTEGER PRIMARY KEY, subject_type TEXT NOT NULL, subject_id INTEGER NOT NULL, source_system TEXT NOT NULL, source_type TEXT NOT NULL, source_url TEXT, captured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, raw_text TEXT NOT NULL, UNIQUE(subject_type, subject_id, source_url, raw_text));
CREATE TABLE IF NOT EXISTS observations (id INTEGER PRIMARY KEY, evidence_id INTEGER NOT NULL, classifier_id INTEGER NOT NULL, observation_type TEXT NOT NULL, matched_text TEXT NOT NULL, UNIQUE(evidence_id, classifier_id, observation_type, matched_text), FOREIGN KEY(evidence_id) REFERENCES evidence(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS resolutions (id INTEGER PRIMARY KEY, observation_id INTEGER NOT NULL, concept_id INTEGER NOT NULL, resolver_version TEXT NOT NULL, taxonomy_version TEXT NOT NULL, resolved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(observation_id, concept_id), FOREIGN KEY(observation_id) REFERENCES observations(id) ON DELETE CASCADE, FOREIGN KEY(concept_id) REFERENCES taxonomy(id));
CREATE TABLE IF NOT EXISTS career_phases (id INTEGER PRIMARY KEY, company TEXT, role TEXT, years TEXT, context TEXT, UNIQUE(company, role, years));
CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, evidence_id INTEGER NOT NULL, company_id INTEGER NOT NULL, posted_date TIMESTAMP, seen_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(evidence_id) REFERENCES evidence(id) ON DELETE CASCADE, FOREIGN KEY(company_id) REFERENCES companies(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, event_type TEXT NOT NULL, subject_type TEXT, subject_id TEXT, payload TEXT);
CREATE TABLE IF NOT EXISTS unknown_observations (id INTEGER PRIMARY KEY, observation_id INTEGER NOT NULL UNIQUE, matched_text TEXT, reason TEXT, seen_count INTEGER DEFAULT 1, last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(observation_id) REFERENCES observations(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS maintenance_state (key TEXT PRIMARY KEY, value TEXT);
"

    _apply_migration "002" "
INSERT INTO taxonomy (concept_type, name) VALUES
('industry','Medical Devices'),('industry','Consumer Electronics'),('industry','Industrial Automation'),('industry','Semiconductor'),('industry','FinTech'),('industry','Enterprise Software'),
('domain','Embedded'),('domain','Robotics'),('domain','Firmware'),('domain','Hardware-Integration'),('domain','AI'),('domain','Computer Vision'),('domain','IoT'),('domain','Cloud'),
('platform','Linux'),('platform','RTOS'),('platform','Android'),
('framework','ROS'),('framework','TensorFlow'),('framework','Qt'),
('technology','Python'),('technology','C++'),('technology','Java'),('technology','Bash'),('technology','SQL'),('technology','Selenium'),('technology','Cypress'),('technology','Docker'),
('capability','Root Cause Analysis'),('capability','Combinatorial Testing'),('capability','State Transition Testing'),('capability','Risk-Based Testing'),('capability','System Diagnostics'),('capability','Performance Testing'),('capability','Security Testing'),('capability','Hardware Diagnostics'),
('regulation','FDA'),('regulation','HIPAA'),('regulation','IEC62304')
ON CONFLICT(name) DO NOTHING;
"

    _apply_migration "003" "
INSERT INTO classifiers (name, version, rule_hash, description) VALUES
('domain_classifier','1.0','sha256-abc123','Pattern-based domain detection'),
('tech_classifier','1.0','sha256-def456','Pattern-based technology detection'),
('capability_classifier','1.0','sha256-ghi789','Pattern-based capability detection'),
('industry_classifier','1.0','sha256-jkl012','Pattern-based industry detection')
ON CONFLICT(name, version) DO NOTHING;
"

    _apply_migration "004" "
INSERT INTO career_phases (company, role, years, context) VALUES
('Lexmark','Software Systems Tester','2003-2006','Printer firmware testing, memory leak detection, combinatorial testing, requirements-based testing, embedded systems, C, USB'),
('NCR','Software Tester','2017-2018','POS hardware-software integration, scanners, touch-panels, payment logic, combinatorial test design, race conditions'),
('InspireX','Senior QA Engineer','2025-Present','AMX programming, audio/video device APIs, AI services, Bash/Python automation, system logs, hardware-software state transitions'),
('Evo Tech','Senior QA Engineer','2024-2025','API testing, SQL data validation, end-to-end testing, root cause analysis, Selenium, Cypress'),
('23point5','QA Engineer','2023-2024','E-commerce testing, cart and payment flows, risk-based testing, Selenium, Python'),
('Accenture','Test Engineering Analyst','2019-2020','Functional and performance testing, Salesforce, telecom enterprise, automation, JMeter'),
('SAAD Hospital','IT Help Desk','2007-2012','Tier 1/2 support, proactive monitoring, preventive maintenance, incident reduction')
ON CONFLICT(company, role, years) DO NOTHING;
"

    _apply_migration "005" "
CREATE INDEX IF NOT EXISTS idx_obs_evidence ON observations(evidence_id);
CREATE INDEX IF NOT EXISTS idx_obs_classifier ON observations(classifier_id);
CREATE INDEX IF NOT EXISTS idx_res_observation ON resolutions(observation_id);
CREATE INDEX IF NOT EXISTS idx_res_concept ON resolutions(concept_id);
CREATE INDEX IF NOT EXISTS idx_evidence_subject ON evidence(subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_jobs_company ON jobs(company_id);
CREATE INDEX IF NOT EXISTS idx_companies_name ON companies(name);
CREATE INDEX IF NOT EXISTS idx_taxonomy_name ON taxonomy(name);
CREATE INDEX IF NOT EXISTS idx_events_type_time ON events(event_type, timestamp);
"

    _apply_migration "006" "
CREATE VIEW IF NOT EXISTS company_knowledge AS
SELECT c.id AS company_id, c.name AS company_name, r.concept_id, t.name AS concept_name, t.concept_type,
       COUNT(DISTINCT o.id) AS observation_count, MAX(e.captured_at) AS last_seen,
       COUNT(DISTINCT o.classifier_id) AS classifier_count
FROM companies c
JOIN evidence e ON e.subject_type = 'company' AND e.subject_id = c.id
JOIN observations o ON o.evidence_id = e.id
JOIN resolutions r ON r.observation_id = o.id
JOIN taxonomy t ON t.id = r.concept_id
GROUP BY c.id, r.concept_id;

CREATE VIEW IF NOT EXISTS career_knowledge AS
SELECT cp.id AS phase_id, cp.company AS career_company, r.concept_id, t.name AS concept_name, t.concept_type,
       COUNT(DISTINCT o.id) AS observation_count, COUNT(DISTINCT o.classifier_id) AS classifier_count
FROM career_phases cp
JOIN evidence e ON e.subject_type = 'career_phase' AND e.subject_id = cp.id
JOIN observations o ON o.evidence_id = e.id
JOIN resolutions r ON r.observation_id = o.id
JOIN taxonomy t ON t.id = r.concept_id
GROUP BY cp.id, r.concept_id;
"

    _apply_migration "007" "
INSERT OR IGNORE INTO taxonomy (concept_type, name) VALUES
('domain','QA'),
('domain','Software Testing'),
('domain','Automation'),
('technology','API'),
('technology','Automation');"

    # ---- Caches + Career Import ----
    _cache_taxonomy
    _cache_classifiers

    if ! sqlite3 "$CIE_DB_PATH" "SELECT 1 FROM data_bootstrap WHERE key='career_imported';" | grep -q 1; then
        log "Importing career phases..."
        if sqlite3 "$CIE_DB_PATH" <<'EOFSQL'
BEGIN;
INSERT OR IGNORE INTO evidence (subject_type, subject_id, source_system, source_type, raw_text)
SELECT 'career_phase', id, 'manual', 'resume', context || ' ' || company || ' ' || role
FROM career_phases;
COMMIT;
EOFSQL
        then
            _classify_career_evidence_batch
            sqlite3 "$CIE_DB_PATH" "INSERT INTO data_bootstrap (key, value) VALUES ('career_imported', datetime('now'));"
        else
            log "ERROR: Failed to import career phases."
            exit 1
        fi
    fi

    log "Database ready."
}

# -----------------------------------------------------------------------------
# CLASSIFIER – Single-pass GAWK (unchanged)
# -----------------------------------------------------------------------------
_classify_text_awk() {
    local text="$1"
    gawk '
    BEGIN {
        regex[0] = "(embedded|firmware|driver|rtos|microcontroller|arm|spi|i2c|uart|can|bootloader)"; type[0] = "domain"; concept[0] = "Embedded"
        regex[1] = "(robot|robotic|motion control|autonomous|ros|computer vision|vision system|motor control|servo|actuator)"; type[1] = "domain"; concept[1] = "Robotics"
        regex[2] = "(firmware|driver|memory|register|bootloader)"; type[2] = "domain"; concept[2] = "Firmware"
        regex[3] = "(hardware integration|device api|system integration|hardware validation|hardware-software|hardware test|touch panel|scanner|printer|sensor)"; type[3] = "domain"; concept[3] = "Hardware-Integration"
        regex[4] = "(ai|machine learning|llm|computer vision|nlp|inference|model training|tensorflow|pytorch)"; type[4] = "domain"; concept[4] = "AI"
        regex[5] = "\\blinux\\b"; type[5] = "technology"; concept[5] = "Linux"
        regex[6] = "\\bpython\\b"; type[6] = "technology"; concept[6] = "Python"
        regex[7] = "\\bbash\\b"; type[7] = "technology"; concept[7] = "Bash"
        regex[8] = "\\bsql\\b"; type[8] = "technology"; concept[8] = "SQL"
        regex[9] = "\\bselenium\\b"; type[9] = "technology"; concept[9] = "Selenium"
        regex[10] = "\\bcypress\\b"; type[10] = "technology"; concept[10] = "Cypress"
        regex[11] = "\\bdocker\\b"; type[11] = "technology"; concept[11] = "Docker"
        regex[12] = "\\bc\\+\\+|cpp"; type[12] = "technology"; concept[12] = "C++"
        regex[13] = "\\bjava\\b"; type[13] = "technology"; concept[13] = "Java"
        regex[14] = "\\bros\\b"; type[14] = "technology"; concept[14] = "ROS"
        regex[15] = "(root cause analysis|root-cause|rca)"; type[15] = "capability"; concept[15] = "Root Cause Analysis"
        regex[16] = "(combinatorial testing|pairwise|pair-wise)"; type[16] = "capability"; concept[16] = "Combinatorial Testing"
        regex[17] = "(state transition|state-machine)"; type[17] = "capability"; concept[17] = "State Transition Testing"
        regex[18] = "(risk-based testing|risk based|risk-based)"; type[18] = "capability"; concept[18] = "Risk-Based Testing"
        regex[19] = "(diagnostics|system logs|log analysis)"; type[19] = "capability"; concept[19] = "System Diagnostics"
        regex[20] = "(performance testing|load testing|jmeter)"; type[20] = "capability"; concept[20] = "Performance Testing"
        regex[21] = "(security testing|penetration testing)"; type[21] = "capability"; concept[21] = "Security Testing"
        regex[22] = "(hardware diagnostics|hardware debug)"; type[22] = "capability"; concept[22] = "Hardware Diagnostics"
        regex[23] = "\\bpos\\b"; type[23] = "product"; concept[23] = "POS System"
        regex[24] = "(printer|printing)"; type[24] = "product"; concept[24] = "Printer"
        regex[25] = "(scanner|scanning)"; type[25] = "product"; concept[25] = "Scanner"
        regex[26] = "(payment|payments|payroll)"; type[26] = "product"; concept[26] = "Payment System"
        regex[27] = "(medical device|diagnostic|healthcare|clinical|radiology|patient)"; type[27] = "industry"; concept[27] = "Medical Devices"
        regex[28] = "(consumer electronics|appliance|gadget)"; type[28] = "industry"; concept[28] = "Consumer Electronics"
        regex[29] = "(industrial automation|manufacturing|factory|plc|scada)"; type[29] = "industry"; concept[29] = "Industrial Automation"
        regex[30] = "(semiconductor|chip|asic|fpga|silicon|wafer)"; type[30] = "industry"; concept[30] = "Semiconductor"
        regex[31] = "(payment|banking|financial|fintech|atm|wallet)"; type[31] = "industry"; concept[31] = "FinTech"
        regex[32] = "(enterprise|saas|erp|crm|salesforce|oracle|sap)"; type[32] = "industry"; concept[32] = "Enterprise Software"
        regex[33] = "\\bqa\\b"; type[33] = "domain"; concept[33] = "QA"
        regex[34] = "\\btest\\b"; type[34] = "domain"; concept[34] = "Software Testing"
        regex[35] = "\\bautomation\\b"; type[35] = "domain"; concept[35] = "Automation"
        regex[36] = "\\bapi\\b"; type[36] = "technology"; concept[36] = "API"
        total = 37
    }
    {
        delete seen
        txt = tolower($0)
        for (i = 0; i < total; i++) {
            if (match(txt, regex[i])) {
                key = type[i] "|" concept[i]
                if (!seen[key]) {
                    seen[key] = 1
                    print type[i] "|" concept[i]
                }
            }
        }
    }
    ' <<< "$text" 2>/dev/null
}

# -----------------------------------------------------------------------------
# BATCH CLASSIFIER FOR CAREER
# -----------------------------------------------------------------------------
_classify_career_evidence_batch() {
    local classifier_id
    classifier_id=$(_get_classifier_id "$CIE_CLASSIFIER_NAME" "$CIE_CLASSIFIER_VERSION")
    [[ -z "$classifier_id" ]] && return

    local sql_file
    sql_file=$(mktemp)

    sqlite3 "$CIE_DB_PATH" "SELECT id, raw_text FROM evidence WHERE subject_type='career_phase';" | while IFS='|' read -r eid raw; do
        local classes
        classes=$(_classify_text_awk "$raw")
        if [[ -n "$classes" ]]; then
            while IFS='|' read -r obs_type concept; do
                [[ -z "$concept" ]] && continue
                local concept_id
                concept_id=$(_get_concept_id "$concept")
                echo "INSERT INTO observations (evidence_id, classifier_id, observation_type, matched_text)" >> "$sql_file"
                echo "  VALUES ($eid, $classifier_id, '$obs_type', '$(sql_quote "$concept")')" >> "$sql_file"
                echo "  ON CONFLICT(evidence_id, classifier_id, observation_type, matched_text) DO NOTHING;" >> "$sql_file"

                if [[ -n "$concept_id" ]]; then
                    echo "INSERT INTO resolutions (observation_id, concept_id, resolver_version, taxonomy_version)" >> "$sql_file"
                    echo "  SELECT o.id, $concept_id, 'resolver_v1', 'taxonomy_v1'" >> "$sql_file"
                    echo "  FROM observations o" >> "$sql_file"
                    echo "  WHERE o.evidence_id = $eid AND o.classifier_id = $classifier_id" >> "$sql_file"
                    echo "    AND o.observation_type = '$obs_type' AND o.matched_text = '$(sql_quote "$concept")'" >> "$sql_file"
                    echo "  ON CONFLICT(observation_id, concept_id) DO NOTHING;" >> "$sql_file"
                else
                    echo "INSERT INTO unknown_observations (observation_id, matched_text, reason)" >> "$sql_file"
                    echo "  SELECT o.id, '$(sql_quote "$concept")', 'No matching taxonomy concept'" >> "$sql_file"
                    echo "  FROM observations o" >> "$sql_file"
                    echo "  WHERE o.evidence_id = $eid AND o.classifier_id = $classifier_id" >> "$sql_file"
                    echo "    AND o.observation_type = '$obs_type' AND o.matched_text = '$(sql_quote "$concept")'" >> "$sql_file"
                    echo "  ON CONFLICT(observation_id) DO UPDATE SET seen_count = seen_count + 1, last_seen = CURRENT_TIMESTAMP;" >> "$sql_file"
                    echo "INSERT INTO events (event_type, subject_type, subject_id, payload)" >> "$sql_file"
                    echo "  SELECT 'ObservationUnresolved', 'observation', o.id, json_object('payload_version', 1, 'matched_text', '$(sql_quote "$concept")', 'classifier', $classifier_id, 'taxonomy_version', '$(sql_quote "$CIE_CLASSIFIER_VERSION")')" >> "$sql_file"
                    echo "  FROM observations o" >> "$sql_file"
                    echo "  WHERE o.evidence_id = $eid AND o.classifier_id = $classifier_id" >> "$sql_file"
                    echo "    AND o.observation_type = '$obs_type' AND o.matched_text = '$(sql_quote "$concept")'" >> "$sql_file"
                    echo "    AND NOT EXISTS (SELECT 1 FROM events e2 WHERE e2.subject_type = 'observation' AND e2.subject_id = o.id AND e2.event_type = 'ObservationUnresolved');" >> "$sql_file"
                fi
            done <<< "$classes"
        fi
    done

    _execute_transaction "$sql_file" "career_import"
    rm -f "$sql_file"
}

# -----------------------------------------------------------------------------
# ACQUISITION – Using Pipe‑Delimited Scraper Output
# -----------------------------------------------------------------------------
_acquire_jobstreet() {
    local output_file="$1"
    > "$output_file"   # clear output file

    for query in "${QA_KEYWORDS[@]}"; do
        log "Fetching jobs for keyword: '$query'"
        local raw_output
        # Call the scraper without --json (default pipe-delimited output)
        raw_output=$(python3 "$CIE_SCRAPER" "$query" 2>/dev/null) || {
            log "WARNING: Scraper failed for '$query'"
            continue
        }

        # Process each line and convert to JSON (compact output)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # Split by '|'
            IFS='|' read -r id title company url <<< "$line"
            # Build JSON object using jq with -c for compact, single-line output
            jq -c -n \
                --arg id "$id" \
                --arg title "$title" \
                --arg company "$company" \
                --arg url "$url" \
                '{id: $id, title: $title, company: $company, url: $url, salary: null, location: "Philippines"}' \
                >> "$output_file"
        done <<< "$raw_output"
    done

    local total
    total=$(wc -l < "$output_file")
    log "Total jobs fetched across all keywords: $total"
}

# -----------------------------------------------------------------------------
# TRANSACTION EXECUTION
# -----------------------------------------------------------------------------
_execute_transaction() {
    local sql_file="$1"
    local job_id="$2"
    local attempt=1
    local max_attempts="$CIE_MAX_RETRIES"

    while [[ $attempt -le $max_attempts ]]; do
        local error_log
        error_log=$(mktemp)
        if sqlite3 "$CIE_DB_PATH" <<EOF 2> "$error_log"
BEGIN IMMEDIATE;
$(cat "$sql_file")
COMMIT;
EOF
        then
            rm -f "$error_log"
            return 0
        else
            local err_msg
            err_msg=$(cat "$error_log")
            if echo "$err_msg" | grep -qiE 'database is locked|database schema is locked|SQLITE_BUSY|SQLITE_LOCKED|SQLITE_IOERR_BLOCKED|IOERR_BLOCKED'; then
                log "Transient lock error (attempt $attempt/$max_attempts) for job $job_id: $err_msg"
                rm -f "$error_log"
                if [[ $attempt -lt $max_attempts ]]; then
                    local delay=$((1 << (attempt - 1)))
                    ((delay > 30)) && delay=30
                    local jitter=$((RANDOM % 3))
                    sleep "$((delay + jitter))"
                fi
                ((attempt++))
                continue
            else
                log "ERROR: Transaction failed for job $job_id (attempt $attempt): $err_msg"
                local failed_sql
                failed_sql="${CIE_LOG_DIR}/failed_transaction_${job_id}_$(date +%Y%m%d_%H%M%S).sql"
                cp "$sql_file" "$failed_sql"
                log "Failed SQL saved to $failed_sql"
                rm -f "$error_log"
                return 1
            fi
        fi
    done

    log "ERROR: Transaction failed for job $job_id after $max_attempts attempts (busy)."
    return 1
}

# -----------------------------------------------------------------------------
# JOB SQL BUILDING
# -----------------------------------------------------------------------------
_append_company_sql() {
    local company="$1"
    local sql_file="$2"
    cat <<EOF >> "$sql_file"
INSERT INTO companies (name, first_seen, last_seen)
VALUES ('$(sql_quote "$company")', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT(name) DO UPDATE SET last_seen = CURRENT_TIMESTAMP;
EOF
}

_append_evidence_sql() {
    local company="$1"
    local url="$2"
    local raw_text="$3"
    local sql_file="$4"
    cat <<EOF >> "$sql_file"
INSERT INTO evidence (subject_type, subject_id, source_system, source_type, source_url, raw_text)
SELECT 'company', c.id, 'JobStreet', 'job_description', '$(sql_quote "$url")', '$(sql_quote "$raw_text")'
FROM companies c
WHERE c.name = '$(sql_quote "$company")'
ON CONFLICT(subject_type, subject_id, source_url, raw_text) DO NOTHING;
EOF
}

_append_job_sql() {
    local job_id="$1"
    local company="$2"
    local url="$3"
    local sql_file="$4"
    cat <<EOF >> "$sql_file"
INSERT INTO jobs (id, evidence_id, company_id, posted_date)
SELECT '$(sql_quote "$job_id")', e.id, c.id, CURRENT_TIMESTAMP
FROM companies c, evidence e
WHERE c.name = '$(sql_quote "$company")'
  AND e.subject_type = 'company'
  AND e.subject_id = c.id
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
ON CONFLICT(id) DO NOTHING;
EOF
}

_append_classification_results_sql() {
    local company="$1"
    local url="$2"
    local classifier_id="$3"
    local obs_type="$4"
    local concept="$5"
    local sql_file="$6"
    local concept_id
    concept_id=$(_get_concept_id "$concept")

    cat <<EOF >> "$sql_file"
INSERT INTO observations (evidence_id, classifier_id, observation_type, matched_text)
SELECT e.id, $classifier_id, '$obs_type', '$(sql_quote "$concept")'
FROM companies c, evidence e
WHERE c.name = '$(sql_quote "$company")'
  AND e.subject_type = 'company'
  AND e.subject_id = c.id
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
ON CONFLICT(evidence_id, classifier_id, observation_type, matched_text) DO NOTHING;
EOF

    if [[ -n "$concept_id" ]]; then
        cat <<EOF >> "$sql_file"
INSERT INTO resolutions (observation_id, concept_id, resolver_version, taxonomy_version)
SELECT o.id, $concept_id, 'resolver_v1', 'taxonomy_v1'
FROM observations o
JOIN evidence e ON e.id = o.evidence_id
JOIN companies c ON c.id = e.subject_id
WHERE c.name = '$(sql_quote "$company")'
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
  AND o.classifier_id = $classifier_id
  AND o.observation_type = '$obs_type'
  AND o.matched_text = '$(sql_quote "$concept")'
ON CONFLICT(observation_id, concept_id) DO NOTHING;
EOF
    else
        cat <<EOF >> "$sql_file"
INSERT INTO unknown_observations (observation_id, matched_text, reason)
SELECT o.id, '$(sql_quote "$concept")', 'No matching taxonomy concept'
FROM observations o
JOIN evidence e ON e.id = o.evidence_id
JOIN companies c ON c.id = e.subject_id
WHERE c.name = '$(sql_quote "$company")'
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
  AND o.classifier_id = $classifier_id
  AND o.observation_type = '$obs_type'
  AND o.matched_text = '$(sql_quote "$concept")'
ON CONFLICT(observation_id) DO UPDATE SET seen_count = seen_count + 1, last_seen = CURRENT_TIMESTAMP;
EOF
        cat <<EOF >> "$sql_file"
INSERT INTO events (event_type, subject_type, subject_id, payload)
SELECT 'ObservationUnresolved', 'observation', o.id,
       json_object('payload_version', 1, 'matched_text', '$(sql_quote "$concept")', 'classifier', $classifier_id, 'taxonomy_version', '$(sql_quote "$CIE_CLASSIFIER_VERSION")')
FROM observations o
JOIN evidence e ON e.id = o.evidence_id
JOIN companies c ON c.id = e.subject_id
WHERE c.name = '$(sql_quote "$company")'
  AND e.source_url = '$(sql_quote "$url")'
  AND e.source_type = 'job_description'
  AND o.classifier_id = $classifier_id
  AND o.observation_type = '$obs_type'
  AND o.matched_text = '$(sql_quote "$concept")'
  AND NOT EXISTS (SELECT 1 FROM events e2
                  WHERE e2.subject_type = 'observation'
                    AND e2.subject_id = o.id
                    AND e2.event_type = 'ObservationUnresolved');
EOF
    fi
}

_append_job_event_sql() {
    local job_id="$1"
    local company="$2"
    local title="$3"
    local sql_file="$4"
    cat <<EOF >> "$sql_file"
INSERT INTO events (event_type, subject_type, subject_id, payload)
SELECT 'JobObserved', 'job', j.id,
       json_object('payload_version', 1, 'company', '$(sql_quote "$company")', 'title', '$(sql_quote "$title")')
FROM jobs j
WHERE j.id = '$(sql_quote "$job_id")'
  AND NOT EXISTS (SELECT 1 FROM events e2
                  WHERE e2.event_type = 'JobObserved'
                    AND e2.subject_type = 'job'
                    AND e2.subject_id = j.id);
EOF
}

# -----------------------------------------------------------------------------
# BUILD JOB SQL
# -----------------------------------------------------------------------------
_build_job_sql() {
    local job_json="$1"
    local title company url job_id salary location classifier_id raw_text classes

    local fields
    mapfile -t fields < <(
        jq -r '
            .title // "",
            .company // "",
            .url // "",
            .id // "",
            (.salary | tostring),
            .location // ""
        ' <<<"$job_json"
    )

    if [[ ${#fields[@]} -ne 6 ]]; then
        log "ERROR: jq extraction returned ${#fields[@]} fields, expected 6. Skipping job."
        return 1
    fi

    title="${fields[0]}"
    company="${fields[1]}"
    url="${fields[2]}"
    job_id="${fields[3]}"
    salary="${fields[4]}"
    location="${fields[5]}"

    [[ -z "$title" || -z "$company" ]] && return 1

    classifier_id=$(_get_classifier_id "$CIE_CLASSIFIER_NAME" "$CIE_CLASSIFIER_VERSION")
    [[ -z "$classifier_id" ]] && { log "ERROR: Classifier not found"; return 1; }

    raw_text="$title $company $location $salary"
    classes=$(_classify_text_awk "$raw_text")

    local sql_file
    sql_file=$(mktemp)

    _append_company_sql "$company" "$sql_file"
    _append_evidence_sql "$company" "$url" "$raw_text" "$sql_file"
    _append_job_sql "$job_id" "$company" "$url" "$sql_file"

    if [[ -n "$classes" ]]; then
        while IFS='|' read -r obs_type concept; do
            [[ -z "$concept" ]] && continue
            _append_classification_results_sql "$company" "$url" "$classifier_id" "$obs_type" "$concept" "$sql_file"
        done <<< "$classes"
    fi

    _append_job_event_sql "$job_id" "$company" "$title" "$sql_file"

    echo "$sql_file"
}

# -----------------------------------------------------------------------------
# PROCESS JOB
# -----------------------------------------------------------------------------
_process_job() {
    local job_json="$1"
    local sql_file
    sql_file=$(_build_job_sql "$job_json")
    if [[ -z "$sql_file" || ! -f "$sql_file" ]]; then
        log "ERROR: Failed to build SQL for job."
        return 1
    fi

    local job_id
    job_id=$(echo "$job_json" | jq -r '.id // "unknown"')
    if ! _execute_transaction "$sql_file" "$job_id"; then
        log "Failed to commit job $job_id after retries."
        sqlite3 "$CIE_DB_PATH" "INSERT INTO events (event_type, subject_type, subject_id, payload) VALUES ('JobFailed', 'job', '$(sql_quote "$job_id")', json_object('payload_version', 1, 'error', 'transaction failed after retries'));" 2>/dev/null || log "WARNING: Could not log JobFailed event."
        rm -f "$sql_file"
        return 1
    fi

    rm -f "$sql_file"
    return 0
}

# -----------------------------------------------------------------------------
# QUERY
# -----------------------------------------------------------------------------
_query_recommendations() {
    local cutoff="$1"
    sqlite3 "$CIE_DB_PATH" <<EOF
WITH recent_jobs AS (SELECT DISTINCT company_id FROM jobs WHERE seen_date > '$cutoff'),
company_concepts AS (
    SELECT c.id AS company_id, c.name AS company_name, r.concept_id,
           MAX(r.resolved_at) AS latest_resolution,
           COUNT(DISTINCT o.id) AS observation_count,
           COUNT(DISTINCT o.classifier_id) AS classifier_count,
           MAX(e.captured_at) AS last_evidence
    FROM companies c
    JOIN recent_jobs rj ON rj.company_id = c.id
    JOIN evidence e ON e.subject_type = 'company' AND e.subject_id = c.id
    JOIN observations o ON o.evidence_id = e.id
    JOIN resolutions r ON r.observation_id = o.id
    GROUP BY c.id, r.concept_id
),
career_concepts AS (SELECT concept_id FROM career_knowledge),
shared AS (
    SELECT cc.company_id, cc.company_name,
           COUNT(DISTINCT cc.concept_id) AS shared_count,
           MAX(cc.last_evidence) AS most_recent,
           SUM(cc.observation_count) AS total_evidence,
           SUM(cc.classifier_count) AS total_classifiers
    FROM company_concepts cc
    JOIN career_concepts ca ON ca.concept_id = cc.concept_id
    GROUP BY cc.company_id, cc.company_name
)
SELECT company_id, company_name, shared_count, most_recent, total_evidence, total_classifiers
FROM shared
ORDER BY shared_count DESC, most_recent DESC, total_classifiers DESC
LIMIT ${CIE_MAX_RECOMMENDATIONS};
EOF
}

# -----------------------------------------------------------------------------
# NOTIFY
# -----------------------------------------------------------------------------
_notify_email() {
    local recommendations="$1"
    [[ -z "$recommendations" ]] && { log "No recommendations."; return 0; }

    local count
    count=$(echo "$recommendations" | wc -l)
    local subject="Career Intelligence: $count matching companies with new QA roles"

    local body
    body=$(mktemp)
    {
        printf 'To: %s\n' "$CIE_EMAIL_TO"
        printf 'Subject: %s\n' "$subject"
        printf 'Content-Type: text/plain; charset=UTF-8\n\n'
        printf 'Hi Claive,\n\n'
        printf 'Career Intelligence Engine found %d companies with new QA opportunities.\n\n' "$count"
        printf 'Ranked by shared concepts, recency, and classifier agreement.\n\n'
    } >> "$body"

    echo "$recommendations" | while IFS='|' read -r _ name shared most_recent evidence classifiers; do
        local encoded_name
        encoded_name=$(jq -rn --arg s "$name" '$s|@uri')
        printf '---------------------------------------------------------------------\n' >> "$body"
        printf 'Company: %s\n' "$name" >> "$body"
        printf '   Shared concepts: %d\n' "$shared" >> "$body"
        printf '   Evidence count: %d\n' "$evidence" >> "$body"
        printf '   Last seen: %s\n' "$most_recent" >> "$body"
        printf '   Classifier agreement: %d classifiers\n' "$classifiers" >> "$body"
        echo "   https://ph.jobstreet.com/jobs?keywords=$encoded_name" >> "$body"
    done

    printf '\n---\nSource: JobStreet Philippines\n' >> "$body"
    printf 'Apply quickly – positions may close soon.\n' >> "$body"
    printf 'Generated: %s\n' "$(date)" >> "$body"

    if msmtp -a "$CIE_SMTP_ACCOUNT" "$CIE_EMAIL_TO" < "$body"; then
        log "Email sent."
        sqlite3 "$CIE_DB_PATH" "INSERT INTO events (event_type, subject_type, subject_id, payload) VALUES ('RecommendationDelivered', 'system', '0', json_object('payload_version', 1, 'count', $count));"
    else
        log "Failed to send email."
        sqlite3 "$CIE_DB_PATH" "INSERT INTO events (event_type, subject_type, subject_id, payload) VALUES ('NotificationFailed', 'system', '0', json_object('payload_version', 1, 'error', 'msmtp failed'));"
    fi
    rm -f "$body"
}

# -----------------------------------------------------------------------------
# LOG ROTATION & MAINTENANCE
# -----------------------------------------------------------------------------
_rotate_logs() {
    find "$CIE_LOG_DIR" -name "cie_*.log" -type f -mtime +"$CIE_LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    find "$CIE_LOG_DIR" -name "cie_search.jsonl" -type f -mtime +"$CIE_LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

_maintenance() {
    log "Running maintenance..."

    local sql_file
    sql_file=$(mktemp)
    cat <<EOF > "$sql_file"
DELETE FROM jobs WHERE seen_date < datetime('now', '-${CIE_RETENTION_DAYS} days');
DELETE FROM events WHERE timestamp < datetime('now', '-${CIE_RETENTION_DAYS} days');
EOF

    _execute_transaction "$sql_file" "maintenance"
    rm -f "$sql_file"

    local db_size
    db_size=$(stat -c%s "$CIE_DB_PATH" 2>/dev/null || echo 0)
    if [[ "$db_size" -gt 104857600 ]]; then
        log "VACUUMING database..."
        sqlite3 "$CIE_DB_PATH" "VACUUM;"
    fi

    log "Checkpointing WAL..."
    sqlite3 "$CIE_DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);"

    local unknowns
    unknowns=$(sqlite3 "$CIE_DB_PATH" "SELECT matched_text, COUNT(*) FROM unknown_observations GROUP BY matched_text ORDER BY COUNT(*) DESC LIMIT 10;")
    if [[ -n "$unknowns" ]]; then
        log "Unknown observations (consider adding to taxonomy):"
        echo "$unknowns" | while IFS='|' read -r text count; do
            log "   '$text' (seen $count times)"
        done
    fi

    sqlite3 "$CIE_DB_PATH" "PRAGMA optimize;"
    _rotate_logs
    sqlite3 "$CIE_DB_PATH" "INSERT OR REPLACE INTO maintenance_state (key, value) VALUES ('last_maintenance', datetime('now'));"
    log "Maintenance complete."
}

# -----------------------------------------------------------------------------
# MAIN CYCLE
# -----------------------------------------------------------------------------
_main_cycle() {
    log "Starting Career Intelligence Engine v12.8"

    _acquire_lock || exit 1

    _db_init

    local jobstream
    jobstream=$(mktemp)

    _acquire_jobstreet "$jobstream"

    local job_count=0
    while IFS= read -r job_json; do
        [[ -z "$job_json" ]] && continue
        if _process_job "$job_json"; then
            ((job_count++))
        fi
    done < "$jobstream"
    rm -f "$jobstream"

    log "Processed $job_count jobs."

    local cutoff
    cutoff=$(date -d "${CIE_CUTOFF_MINUTES} minutes ago" '+%Y-%m-%d %H:%M:%S')
    local recommendations
    recommendations=$(_query_recommendations "$cutoff")
    if [[ -n "$recommendations" ]]; then
        _notify_email "$recommendations"
    else
        log "No new recommendations."
    fi

    local last_maintenance
    last_maintenance=$(sqlite3 "$CIE_DB_PATH" "SELECT value FROM maintenance_state WHERE key='last_maintenance';" 2>/dev/null || echo "")
    if [[ -z "$last_maintenance" ]]; then
        _maintenance
    else
        local last_epoch
        last_epoch=$(date -d "$last_maintenance" +%s 2>/dev/null || echo 0)
        if [[ $(( ( $(date +%s) - last_epoch ) / 86400 )) -gt 7 ]]; then
            _maintenance
        fi
    fi

    _release_lock
    log "Cycle complete"
}

# -----------------------------------------------------------------------------
# ENTRY
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "--once" ]]; then
    _main_cycle
else
    while true; do
        _main_cycle
        sleep $(( (RANDOM % 21) + 55 ))m
    done
fi
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# monitor_system_failures.sh
# Monitors critical and serious system failures across popular Linux distros.

LOCK_FILE="/tmp/monfailures_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

ALERT_LOG="$HOME/scriptlogs/monitor_alerts.log"
PIDFILE="$HOME/scriptlogs/monitor.pid"
mkdir -p "$(dirname "$ALERT_LOG")"

SHOW_STOPPER="panic|kernel BUG|oops|machine check|MCE|thermal.*shutdown|plasmashell.*crashed|kwin_wayland.*crashed|kwin_x11.*crashed|Xorg.*crashed|wayland.*crashed|GDM.*crashed|SDDM.*crashed|emergency mode|rescue mode|out of memory|OOM killer|filesystem.*readonly|hardware error|fatal|segfault|login.*failed.*repeatedly|dracut.*failed|mount.*failed.*at boot|soft lockup|hard lockup|watchdog: BUG|page allocation failure|journal aborted"

SERIOUS_FAILURES="GPU hang|GPU fault|GPU reset|DRM error|i915.*error|amdgpu.*error|nouveau.*error|plasma.*segfault|plasma.*core dumped|compositor.*crashed|systemd.*failed|mount.*failed|disk.*error|I/O error|memory.*error|temperature.*critical|network.*unreachable|network.*down|link.*down|authentication.*failed.*repeatedly|swap.*exhausted|drkonqi|pulseaudio.*crashed|pipewire.*crashed|wireplumber.*crashed|dbus.*crash|journal.*disk.*full"

LOGFILES=(
    "/var/log/syslog"           # Debian-based
    "/var/log/messages"         # RHEL/Fedora/openSUSE
    "/var/log/secure"
    "/var/log/Xorg.0.log"
    "/var/log/audit/audit.log"
)

pids=()

send_notification() {
    local message="$1"
    local urgency="$2"
    local active_user=$(who | grep '(:0)' | awk '{print $1}' | head -n 1)
    if [ -n "$active_user" ]; then
        local user_display=$(who | grep "$active_user" | grep '(:0)' | awk '{print $5}' | tr -d '()')
        if [ -n "$user_display" ]; then
            sudo -u "$active_user" DISPLAY="$user_display" notify-send \
                --urgency="$urgency" --icon=dialog-error \
                --app-name="System Monitor" "System Alert" "$message" 2>/dev/null
        fi
    fi

    if [ "$USER" != "root" ]; then
        notify-send --urgency="$urgency" --icon=dialog-error \
            --app-name="System Monitor" "System Alert" "$message" 2>/dev/null
    fi
}

check_error_severity() {
    local line="$1"
    if echo "$line" | grep -Eqi "$SHOW_STOPPER"; then
        echo "CRITICAL"
    elif echo "$line" | grep -Eqi "$SERIOUS_FAILURES"; then
        echo "SERIOUS"
    else
        echo "IGNORE"
    fi
}

process_alert() {
    local source="$1"
    local line="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local severity
    severity=$(check_error_severity "$line")

    case "$severity" in
        "CRITICAL")
            if ! echo "$line" | grep -Eiq "screensaver"; then
                echo "$timestamp [CRITICAL] $source: $line" >> "$ALERT_LOG"
                send_notification "$line" "critical"
            fi
            ;;
        "SERIOUS")
            echo "$timestamp [SERIOUS] $source: $line" >> "$ALERT_LOG"
            ;;
    esac
}

monitor_log_file() {
    local logfile="$1"
    if [ ! -f "$logfile" ]; then
        echo "Log file '$logfile' not found. Skipping..."
        return
    fi

    echo "Monitoring $logfile..."
    (
        tail -n 0 -F "$logfile" 2>/dev/null | while IFS= read -r line; do
            local severity
            severity=$(check_error_severity "$line")
            if [ "$severity" != "IGNORE" ]; then
                process_alert "$logfile" "$line"
            fi
        done
    ) &
    pids+=($!)
}

for logfile in "${LOGFILES[@]}"; do
    monitor_log_file "$logfile"
done

if command -v journalctl > /dev/null; then
    echo "Monitoring systemd journal..."
    journalctl -f -p 3 --no-pager | while IFS= read -r line; do
        severity=$(check_error_severity "$line")
        if [ "$severity" != "IGNORE" ]; then
            process_alert "systemd-journal" "$line"
        fi
    done &
    pids+=($!)
fi

if command -v dmesg > /dev/null; then
    echo "Monitoring dmesg..."
    dmesg -w 2>/dev/null | while IFS= read -r line; do
        local severity
        severity=$(check_error_severity "$line")
        if [ "$severity" != "IGNORE" ]; then
            process_alert "kernel-dmesg" "$line"
        fi
    done &
    pids+=($!)
fi

cleanup() {
    echo "Stopping monitoring..."
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null
    done
    rm -f "$PIDFILE"
    echo "Clean exit."
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP EXIT

send_notification "System monitor started (CRITICAL notifications only)" "low"

echo "=== Linux System Monitor Running ==="
echo "Logging CRITICAL and SERIOUS issues, notifying only CRITICAL."

open_terminal_with_logs() {
    [ -f "$ALERT_LOG" ] || return
    local CRITICAL_LOGS
    CRITICAL_LOGS=$(grep "\[CRITICAL\]" "$ALERT_LOG")
    [ -z "$CRITICAL_LOGS" ] && return

    TERM_CMDS=(
        "konsole"
        "gnome-terminal"
        "xfce4-terminal"
        "tilix"
        "xterm"
        "lxterminal"
        "mate-terminal"
        "alacritty"
        "terminator"
        "urxvt"
        "kitty"
        "deepin-terminal"
        "qterminal"
    )

    for term in "${TERM_CMDS[@]}"; do
        if command -v "$term" > /dev/null; then
            "$term" -e bash -c "cat <<EOF
$CRITICAL_LOGS
EOF
read -p 'Press Enter to close...'" &
            return
        fi
    done

    echo "No compatible terminal found to display critical logs."
}

open_terminal_with_logs
wait
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# ============================================================
# RANDOM WALLPAPER SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Fetches random, unseen digital art from DeviantArt and
#   sets it as KDE Plasma desktop wallpaper.
#
# HOW IT WORKS:
#   1. Category Cycling - Shuffles art categories (e.g.,
#      "landscapes", "cyberpunk") for diverse styles.
#   2. API Fetch - Queries DeviantArt via 'deviousq' for up
#      to 100 image URLs per search term.
#   3. History Check - Uses ~/scriptlogs/wallpaper_history.txt
#      to avoid repeats (stores ~2.14M unique URLs).
#   4. Selection - Randomly samples up to 100 candidates. If
#      all seen, greps history for unseen; fallback to repeat.
#   5. Application - Downloads chosen image to /tmp and applies
#      via 'plasma-apply-wallpaperimage'.
#   6. Loop - Repeats every SLEEP_INTERVAL (default 60s).
#
# DISCLAIMER:
#   All rights belong to the respective DeviantArt artists.
#   This script fetches random images; content is unfiltered
#   beyond DeviantArt's "nonadult" rating. Viewer discretion
#   is advised. Usage is personal and non-commercial only.

# ============================================================
# CONFIGURATION
# ============================================================
HISTORY_SIZE=2140000         # Unique wallpapers URL history
SEARCH_LIMIT=100             # Fetch 100 results per search
SLEEP_INTERVAL=60            # Seconds between wallpaper changes
MAX_ATTEMPTS=100             # Try up to 100 random candidates before fallback

# ============================================================
# ALL CATEGORIES KEYWORD POOL
# ============================================================
CATEGORIES=(
    "3d art" "cgi" "blender" "maya"
    "abstract" "geometric" "minimalist"
    "animation" "gif" "motion graphics"
    "animals" "fantasy" "graffiti" "illustration"
    "landscapes" "scenery" "nature"
    "people" "portraits" "political"
    "pop art" "sci-fi" "space art"
    "still life" "surreal"
    "fractal" "mandelbrot"
    "mixed media" "digital collage"
    "photomanipulation" "photo manipulation"
    "pixel art" "8-bit" "16-bit"
    "vector" "vector art" "flat design"
    "body art" "face painting"
    "collage" "paper art"
    "pencil drawing" "charcoal" "ink sketch"
    "printmaking" "linocut" "etching"
    "architecture" "cityscape" "urban"
    "conceptual" "dark" "emotional"
    "seascape" "ocean" "beach"
    "macro" "monochrome" "black and white"
    "people" "street photography"
    "anime" "manga" "fanart anime" "kawaii"
    "cartoon" "comic" "webcomic"
    "fan art" "marvel fanart" "star wars fanart" "harry potter fanart"
    "jewelry" "woodwork" "sculpture" "glass art"
    "cyberpunk" "synthwave" "vaporwave"
    "nebula" "galaxy" "aurora"
    "dragon" "castle" "mythical" "magical"
    "forest" "mountain" "sunset" "sunrise"
    "cherry blossom" "autumn" "winter"
)

# ============================================================
# PATHS & SETUP
# ============================================================
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
LOGFILE="$HOME/scriptlogs/wallpaper.log"

mkdir -p "$HOME/scriptlogs"

echo "$(date) - Random Wallpaper Script Started (History size: $HISTORY_SIZE)" >> "$LOGFILE"

# ============================================================
# CATEGORY CYCLING (Random Permutation without replacement)
# ============================================================
shuffle_categories() {
    SHUFFLED_CATEGORIES=(
        $(printf "%s\n" "${CATEGORIES[@]}" | shuf)
    )

    CAT_INDEX=0
}

shuffle_categories

# ============================================================
# HISTORY FUNCTIONS
# ============================================================
touch "$HISTORY_FILE"

# Add URL to history and keep only the newest HISTORY_SIZE entries
add_to_history() {
    local url="$1"

    echo "$url" >> "$HISTORY_FILE"

    tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"

    mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# Check whether a URL is already in history
is_in_history() {
    local url="$1"

    grep -Fxq "$url" "$HISTORY_FILE" 2>/dev/null
}

# ============================================================
# MAIN LOOP
# ============================================================
while true; do

    # --------------------------------------------------------
    # 1. PICK NEXT CATEGORY
    # --------------------------------------------------------

    SEARCH_TERM="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    CAT_INDEX=$((CAT_INDEX + 1))

    # Finished a complete category cycle
    if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then

        echo "$(date) - Finished a full category cycle. Reshuffling..." \
            >> "$LOGFILE"

        shuffle_categories

        SEARCH_TERM="${SHUFFLED_CATEGORIES[0]}"
        CAT_INDEX=1
    fi

    echo "$(date) - Searching for: '$SEARCH_TERM'" >> "$LOGFILE"

    # --------------------------------------------------------
    # 2. FETCH SEARCH RESULTS
    # --------------------------------------------------------

    URL_LIST=$(
        deviousq \
            --medium image \
            --rating nonadult \
            --return-field content_url \
            --limit "$SEARCH_LIMIT" \
            "$SEARCH_TERM" \
            2>/dev/null
    )

    if [ -z "$URL_LIST" ]; then

        echo "$(date) - No results for '$SEARCH_TERM'. Retrying..." \
            >> "$LOGFILE"

        sleep "$SLEEP_INTERVAL"
        continue
    fi

    # --------------------------------------------------------
    # 3. RANDOMLY TRY UP TO MAX_ATTEMPTS CANDIDATES
    # --------------------------------------------------------

    RANDOM_URL=""

    for attempt in $(seq 1 "$MAX_ATTEMPTS"); do

        CANDIDATE=$(printf '%s\n' "$URL_LIST" | shuf -n 1)

        if [ -n "$CANDIDATE" ] && ! is_in_history "$CANDIDATE"; then

            RANDOM_URL="$CANDIDATE"

            echo "$(date) - Found unseen URL on attempt $attempt/$MAX_ATTEMPTS" \
                >> "$LOGFILE"

            break
        fi
    done

    # --------------------------------------------------------
    # 4. RANDOMIZED UNSEEN FALLBACK
    # --------------------------------------------------------
    #
    # If random sampling did not find an unseen URL, inspect
    # the remaining result pool and randomly select an unseen
    # URL.
    #
    # --------------------------------------------------------

    if [ -z "$RANDOM_URL" ]; then

        RANDOM_URL=$(
            printf '%s\n' "$URL_LIST" |
            grep -v -F -f "$HISTORY_FILE" |
            shuf -n 1
        )

        if [ -n "$RANDOM_URL" ]; then
            echo "$(date) - Random unseen fallback selected." \
                >> "$LOGFILE"
        fi
    fi

    # --------------------------------------------------------
    # 5. ULTIMATE FALLBACK
    # --------------------------------------------------------
    #
    # This only occurs when every returned URL is already in
    # the history file.
    #
    # Random selection is still used to distribute repeats.
    #
    # --------------------------------------------------------

    if [ -z "$RANDOM_URL" ]; then

        RANDOM_URL=$(printf '%s\n' "$URL_LIST" | shuf -n 1)

        echo "$(date) - WARNING: All results are already in history. Using random repeat." \
            >> "$LOGFILE"
    fi

    # --------------------------------------------------------
    # 6. DOWNLOAD AND SET WALLPAPER
    # --------------------------------------------------------

    if [ -n "$RANDOM_URL" ]; then

        TIMESTAMP=$(date +%s)
        WALLPAPER_FILE="/tmp/wallpaper_${TIMESTAMP}.jpg"

        if wget -q -O "$WALLPAPER_FILE" "$RANDOM_URL"; then

            if plasma-apply-wallpaperimage \
                "$WALLPAPER_FILE" >/dev/null 2>&1; then

                add_to_history "$RANDOM_URL"

                echo "$(date) - Wallpaper set from '$SEARCH_TERM' (file: $WALLPAPER_FILE)" \
                    >> "$LOGFILE"

            else

                echo "$(date) - ERROR: Failed to apply wallpaper from $RANDOM_URL" \
                    >> "$LOGFILE"

                rm -f "$WALLPAPER_FILE"
            fi

        else

            echo "$(date) - ERROR: Failed to download image from $RANDOM_URL" \
                >> "$LOGFILE"

            rm -f "$WALLPAPER_FILE"
        fi

    else

        echo "$(date) - No valid image found. Retrying..." \
            >> "$LOGFILE"
    fi

    # --------------------------------------------------------
    # 7. CLEAN UP OLD WALLPAPER FILES
    # --------------------------------------------------------

    find /tmp \
        -name "wallpaper_*.jpg" \
        -mtime +1 \
        -delete \
        2>/dev/null

    sleep "$SLEEP_INTERVAL"

done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

LOCK_FILE="/tmp/rss_news_filter_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Cleanup function
cleanup() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

# --- 1. CONFIGURATION ---
ALERT_EMAIL="cabpacedilla@gmail.com"
HISTORY_FILE="$HOME/.cache/practical_science_history.log"
LOGSEQ_JOURNAL="$HOME/Documents/Logseq/journals/$(date +%Y_%m_%d).md"
mkdir -p "$(dirname "$HISTORY_FILE")"
mkdir -p "$(dirname "$LOGSEQ_JOURNAL")"

# --- 2. THE FILTER ENGINE ---
SLOP_PAT="tiktok|lamborghini|supercar|gaming|celebrity|gossip|rumor|entertainment|fashion|luxury|brand|influencer|scandal"

# Breakthrough keywords
PRACTICAL="cured|eradicated|fda approved|fast-tracked|treatment|human trial|vaccine|sustainable|carbon-neutral"
THEORETICAL="breakthrough|revolutionary|milestone|first ever|world first|discovery|astonishing|self-replicate|high-efficiency|unprecedented|mystery solved|new class of|rethinking|paradigm shift"

# --- 3. THE FEED LIST ---
FEEDS=(
    "https://www.nature.com/nature/research-articles.rss"
    "https://phys.org/rss-feed/"
    "https://www.newscientist.com/section/news/feed/"
    "https://www.eurekalert.org/rss/breaking.xml"
    "https://www.quantamagazine.org/feed/"
    "https://www.sciencedaily.com/rss/top/science.xml"
    "https://www.sciencedaily.com/rss/top/health.xml"
    "https://www.sciencedaily.com/rss/top/environment.xml"
    "https://www.sciencedaily.com/rss/top/technology.xml"
    "https://www.sciencedaily.com/rss/mind_brain.xml"
    "https://www.sciencedaily.com/rss/health_medicine/nutrition.xml"
    "https://www.sciencedaily.com/rss/health_medicine/fitness.xml"
    "https://www.sciencedaily.com/rss/mind_brain/sleep.xml"
    "https://www.technologyreview.com/feed/"
    "https://newatlas.com/index.rss"
    "https://news.ycombinator.com/rss"
    "https://hnrss.org/best"
    "http://feeds.arstechnica.com/arstechnica/index"
    "https://news.mit.edu/rss/topic/computer-science-and-technology"
    "https://thehackernews.com/feeds/posts/default"
)

# --- 4. HELPERS ---
decode_html_entities() {
    echo "$1" | python3 -c "import sys, html, urllib.parse; print(html.unescape(urllib.parse.unquote(sys.stdin.read().strip())))"
}

# --- 5. MAIN LOOP ---
while true; do
    for URL in "${FEEDS[@]}"; do
        RAW_XML=$(curl -sL -A "Mozilla/5.0" --connect-timeout 15 "$URL") || continue
        ITEMS=$(echo "$RAW_XML" | sed -e 's/<\/item>/<\/item>\n/g' -e 's/<\/entry>/<\/entry>\n/g' | grep -E '<item|<entry')

        while IFS= read -r ITEM; do
            [[ -z "$ITEM" ]] && continue
            
            TITLE=$(echo "$ITEM" | sed -n 's/.*<title[^>]*>\(.*\)<\/title>.*/\1/p' | sed 's/<!\[CDATA\[//g;s/\]\]>//g' | head -n1 | xargs)
            LINK=$(echo "$ITEM" | sed -n 's/.*<link>\([^<]*\)<\/link>.*/\1/p' | head -n1)
            [[ -z "$LINK" ]] && LINK=$(echo "$ITEM" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | head -n1)
            DESC=$(echo "$ITEM" | sed -n 's/.*<description[^>]*>\(.*\)<\/description>.*/\1/p' | sed 's/<!\[CDATA\[//g;s/\]\]>//g' | head -n1 | xargs)

            TITLE=$(decode_html_entities "$TITLE")
            DESC=$(decode_html_entities "$DESC")

            [[ ${#TITLE} -lt 15 || -z "$LINK" ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" && continue

            if echo "$TITLE $DESC" | tr '[:upper:]' '[:lower:]' | grep -qiE "$SLOP_PAT"; then
                continue
            fi

            # --- LOGIC: BREAKTHROUGH OR NOTHING ---
            FINAL_TAG=""
            URGENCY="normal"

            if echo "$TITLE $DESC" | grep -qiE "$PRACTICAL|$THEORETICAL"; then
                FINAL_TAG="🔥 BREAKTHROUGH "
                URGENCY="critical"
            fi

            # --- NOTIFICATIONS ---
            (
                ACTION=$(notify-send -u "$URGENCY" -a "News Alert" \
                    -t 0 \
                    --hint=int:transient:0 \
                    --action="open=Read Article" \
                    "💡 $FINAL_TAG" "$TITLE")

                if [[ "$ACTION" == "open" ]]; then
                    xdg-open "$LINK" >/dev/null 2>&1
                fi
            ) &

            # --- EMAIL ---
            (
                # If no tag, the subject starts directly with the Title
                echo -e "Subject: ${FINAL_TAG}${TITLE}\n\nDate: $(date)\nLink: $LINK\n\nDescription: $DESC" | msmtp -t "$ALERT_EMAIL"
            ) &

            # --- LOGGING ---
            # Using empty string for tag column if it's not a breakthrough
            echo "$(date '+%Y-%m-%d %H:%M') | $FINAL_TAG | Feed | $TITLE | $LINK" >> "$HISTORY_FILE"
            echo "- ${TITLE} [Link](${LINK})" >> "$LOGSEQ_JOURNAL"

        done <<< "$ITEMS"
    done
    sleep 1800 
done
#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
# ============================================================
# Himalayas Job Search - Senior QA/SDET Roles (Semantic Mode)
# VERSION: 2.28 - Production final (frozen)
# ============================================================

# --- IMMUTABLE CONFIGURATION ---
readonly SCRIPT_VERSION="2.28"

set -Euo pipefail

# --- CLI ARGUMENTS ---
RUN_ONCE=false
SHOW_HELP=false
SHOW_VERSION=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--once)   RUN_ONCE=true ; shift ;;
        -h|--help)   SHOW_HELP=true ; shift ;;
        -v|--version) SHOW_VERSION=true ; shift ;;
        --daemon)    shift ;;
        *) echo "Unknown option: $1" >&2 ; exit 1 ;;
    esac
done

if $SHOW_HELP; then
    cat <<EOF
Usage: $0 [OPTION]

Options:
  -o, --once     Run a single search cycle and exit (useful for testing)
  -h, --help     Show this help message
  -v, --version  Show version information
  --daemon       Run as a daemon (default behavior)

Without any options, runs continuously with jittered sleep cycles.
EOF
    exit 0
fi

if $SHOW_VERSION; then
    echo "visa_job_search.sh version ${SCRIPT_VERSION}"
    echo "Himalayas Job Search - Senior QA/SDET Roles (Semantic Mode)"
    exit 0
fi

# --- CONFIGURATION ---
readonly BIN_DIR="$HOME/Documents/bin"
readonly SEEN_FILE="$BIN_DIR/jobs_seen.txt"
readonly LOG_DIR="$HOME/scriptlogs/job_search"
readonly JSON_LOG_FILE="$BIN_DIR/visa_job_search.jsonl"  
readonly HEARTBEAT_FILE="$BIN_DIR/visa_job_engine.heartbeat"
readonly EMAIL_TO="cabpacedilla@gmail.com"
readonly INCLUDE_WORLDWIDE=true

mkdir -p "$LOG_DIR" "$BIN_DIR"
touch "$SEEN_FILE" "$JSON_LOG_FILE"

# --- DEPENDENCY CHECK (only for packages not guaranteed to be present) ---
for cmd in jq curl msmtp flock md5sum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required dependency '$cmd' is not installed. Exiting." >&2
        exit 1
    fi
done

# --- PORTABILITY: Build curl retry arguments (detect --retry-all-errors) ---
CURL_RETRY_ARGS=(
    --retry 3
    --retry-delay 2
    --retry-connrefused
)

# Check both --help and --help all for maximum compatibility
if curl --help 2>/dev/null | grep -q -- '--retry-all-errors' ||
   curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
    CURL_RETRY_ARGS+=(--retry-all-errors)
fi
readonly CURL_RETRY_ARGS

# --- LOCKING ---
readonly LOCK_FILE="/tmp/visa_job_scraper_$(whoami).lock"
exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    echo "$(date): Another instance running, exiting." >&2
    exit 1
fi

printf '%d\n' "$$" > "$LOCK_FILE"

# --- CLEANUP ---
cleanup() {
    # Release the advisory lock first, then remove the informational PID file.
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    rm -f "$LOCK_FILE"
}

# --- TRAPS (signal handling for graceful shutdown) ---
trap 'visa_json_log "WARN" "SIGTERM received"; exit 143' TERM
trap 'visa_json_log "WARN" "SIGINT received"; exit 130' INT

# EXIT trap runs cleanup on any exit (normal or error)
trap '
    rc=$?
    if (( rc == 0 )); then
        visa_json_log "INFO" "Normal exit"
    else
        visa_json_log "ERROR" "Exit rc=$rc"
    fi
    cleanup
' EXIT

# ERR trap logs unexpected errors before the EXIT trap runs
trap '
    rc=$?
    visa_json_log "ERROR" "ERR trap rc=$rc line=$LINENO cmd=${BASH_COMMAND@Q}"
' ERR

# ============================================================
# KEYWORDS & CONFIG
# ============================================================
readonly QA_KEYWORDS=(
    "QA" "Quality Assurance" "Quality Engineer" "Test Engineer" "Software Test"
    "SDET" "Automation Test" "Test Automation" "Quality Engineering"
    "Senior QA" "Senior Quality Engineer" "Senior SDET"
    "QA Lead" "Senior QA Lead" "Lead QA Engineer" "QA Manager" "Quality Assurance Manager"
    "Test Architect" "QA Architect" "Test Automation Architect" "Quality Engineering Architect"
    "Hardware QA" "Firmware Test" "Integration Test" "Embedded QA" "Systems QA"
    "AI QA" "ML Test Engineer" "Fintech QA" "Payments QA"
)

readonly VISA_SENIORITY_LEVELS=( "Senior" )
readonly VISA_FRIENDLY_COUNTRIES=( "AU" "DE" "GB" "CA" "IE" "NL" "SG" "AE" )

# ============================================================
# HELPER FUNCTIONS
# ============================================================
visa_log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_DIR/job_search_$(date +%Y%m%d).log"
}

visa_json_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -Iseconds)
    local version="${SCRIPT_VERSION:-unknown}"
    jq -cn \
        --arg ts "$timestamp" \
        --arg ver "$version" \
        --arg lvl "$level" \
        --arg msg "$message" \
        '{timestamp:$ts, version:$ver, level:$lvl, message:$msg}' \
        >> "$JSON_LOG_FILE" 2>/dev/null || true

    # Rotate JSON log atomically if it grows too large
    if [[ $(stat -c%s "$JSON_LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        local dir tmp_rotate
        dir=$(dirname "$JSON_LOG_FILE")
        if tmp_rotate=$(mktemp -p "$dir" .json_log.XXXXXX 2>/dev/null); then
            tail -n 5000 "$JSON_LOG_FILE" > "$tmp_rotate" 2>/dev/null
            mv "$tmp_rotate" "$JSON_LOG_FILE"
        else
            # Fallback: direct write (less atomic but better than nothing)
            tail -n 5000 "$JSON_LOG_FILE" > "$JSON_LOG_FILE.tmp" 2>/dev/null
            mv "$JSON_LOG_FILE.tmp" "$JSON_LOG_FILE"
        fi
    fi
}

visa_update_heartbeat() {
    # Atomic update: write to temp in the same directory, then move.
    # If the temp file creation fails, fall back to direct write.
    local dir tmp_heartbeat
    dir=$(dirname "$HEARTBEAT_FILE")
    if tmp_heartbeat=$(mktemp -p "$dir" .heartbeat.XXXXXX 2>/dev/null); then
        printf '%s:%s\n' "$(date +%s)" "$1" > "$tmp_heartbeat"
        mv "$tmp_heartbeat" "$HEARTBEAT_FILE"
    else
        printf '%s:%s\n' "$(date +%s)" "$1" > "$HEARTBEAT_FILE"
    fi
}

visa_job_is_seen() {
    grep -Fxq "$1" "$SEEN_FILE" 2>/dev/null
}

visa_mark_job_seen() {
    printf '%s\n' "$1" >> "$SEEN_FILE"
}

visa_rotate_seen_file() {
    if [[ $(date +%d) == "01" ]]; then
        local sentinel="$BIN_DIR/.seen_rotated_$(date +%Y%m)"
        if [[ ! -f "$sentinel" ]]; then
            if [[ -f "$SEEN_FILE" ]]; then
                tail -n 5000 "$SEEN_FILE" > "$SEEN_FILE.tmp"
                mv "$SEEN_FILE.tmp" "$SEEN_FILE"
                visa_json_log "INFO" "Rotated seen_jobs.txt"
                touch "$sentinel"
            fi
        fi
    else
        local current_month=$(date +%Y%m)
        for old in "$BIN_DIR"/.seen_rotated_*; do
            [[ -f "$old" && "$old" != "$BIN_DIR/.seen_rotated_$current_month" ]] && rm -f "$old"
        done
    fi

    find "$LOG_DIR" -name "job_search_*.log*" -type f -mtime +30 -delete 2>/dev/null || true

    local main_log="$LOG_DIR/job_search_$(date +%Y%m%d).log"
    if [[ -f "$main_log" ]]; then
        local size
        size=$(stat -c%s "$main_log" 2>/dev/null || echo 0)
        if [[ "$size" -gt 52428800 ]]; then
            mv "$main_log" "$main_log.$(date +%Y%m%d-%H%M%S)"
            visa_log "Rotated oversized main log (>50MB)"
        fi
    fi
}

# ============================================================
# API SEARCH
# ============================================================
visa_search_himalayas() {
    local keyword="$1"
    local seniority="$2"
    local results_file="$3"
    local -n output_count_ref="$4"
    local count=0
    
    if [[ ! "$seniority" =~ ^(Senior|Lead|Manager)$ ]]; then
        visa_log "⚠️ Skipping invalid seniority: $seniority (not supported by API)"
        output_count_ref=0
        return 0
    fi
    
    visa_log "🌄 Searching Himalayas: keyword='$keyword' seniority='$seniority'"
    
    local encoded_keyword
    encoded_keyword=$(jq -rn --arg kw "$keyword" '$kw | @uri')
    
    local url
    if $INCLUDE_WORLDWIDE; then
        url="https://himalayas.app/jobs/api/search?q=${encoded_keyword}&seniority=${seniority}&worldwide=true&employment_type=Full%20Time"
    else
        local location_params=""
        for country in "${VISA_FRIENDLY_COUNTRIES[@]}"; do
            if [[ -z "$location_params" ]]; then
                location_params="locationRestrictions[]=${country}"
            else
                location_params="${location_params}&locationRestrictions[]=${country}"
            fi
        done
        url="https://himalayas.app/jobs/api/search?q=${encoded_keyword}&seniority=${seniority}&${location_params}&employment_type=Full%20Time"
    fi
    
    # --- Create temp file for curl stderr ---
    local curl_err
    if ! curl_err=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "   ⚠️ mktemp failed for curl_err"
        output_count_ref=0
        return 1
    fi
    
    local response
    local curl_rc
    # Use if/else to capture exit code without changing global shell options
    if response=$(curl -fsS \
        --connect-timeout 10 \
        --max-time 30 \
        "${CURL_RETRY_ARGS[@]}" \
        "$url" 2>"$curl_err"); then
        curl_rc=0
    else
        curl_rc=$?
    fi
    
    if (( curl_rc != 0 )); then
        local err_msg
        err_msg=$(<"$curl_err")
        visa_log "   ⚠️ curl failed (exit $curl_rc): ${err_msg:-no error message}"
        rm -f "$curl_err"
        output_count_ref=0
        return 0
    fi
    rm -f "$curl_err"   # curl_err is no longer needed
    
    # --- Validate JSON and ensure .jobs is an array ---
    if ! jq -e '.jobs | arrays' <<<"$response" >/dev/null 2>&1; then
        visa_log "   ⚠️ Invalid response: missing .jobs array"
        output_count_ref=0
        return 0
    fi
    
    local job_count
    job_count=$(jq -r '.jobs | length' <<<"$response" 2>/dev/null || echo 0)
    if (( job_count == 0 )); then
        visa_log "   No jobs found in response"
        output_count_ref=0
        return 0
    fi
    
    # --- Create temp file for jq extraction ---
    local jq_temp
    if ! jq_temp=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "   ⚠️ mktemp failed for jq_temp"
        output_count_ref=0
        return 1
    fi
    
    # --- Extract jobs; on failure, clean up and return ---
    if ! jq -r '.jobs[]? | 
        .title as $title | 
        .companyName as $company | 
        ((.locationRestrictions // ["Worldwide"])[0]) as $location | 
        .applicationLink as $url | 
        (.minSalary // "") as $salary_min | 
        (.maxSalary // "") as $salary_max | 
        (.currency // "") as $salary_currency | 
        "\($title)|\($company)|\($location)|\($url)|\($salary_min)|\($salary_max)|\($salary_currency)"' <<<"$response" > "$jq_temp" 2>/dev/null
    then
        visa_log "   ⚠️ jq extraction failed"
        rm -f "$jq_temp"
        output_count_ref=0
        return 0
    fi
    
    # --- Process extracted jobs ---
    while IFS='|' read -r title company location url salary_min salary_max salary_currency; do
        if [[ -z "$title" ]] || [[ -z "$company" ]]; then
            continue
        fi
        
        # Use md5sum for fast deterministic identifiers (not cryptographic)
        local job_hash
        job_hash=$(printf '%s' "$url" | md5sum)
        job_hash="${job_hash%% *}"
        local job_id="him-${job_hash:0:10}"
        
        if ! visa_job_is_seen "$job_id"; then
            local salary_text=""
            if [[ -n "$salary_min" && "$salary_min" != "null" && "$salary_min" != "" ]]; then
                salary_text=" (${salary_currency}${salary_min}-${salary_max})"
            fi
            
            printf '%s\n' "HIMALAYAS|$seniority|$title|$company|$location|$url|$salary_text" >> "$results_file"
            visa_mark_job_seen "$job_id"
            count=$((count + 1))
        fi
    done < "$jq_temp"
    
    rm -f "$jq_temp"
    
    visa_log "   ✓ Found $count new jobs"
    
    output_count_ref=$count
}

# ============================================================
# EMAIL FUNCTION
# ============================================================
visa_send_email() {
    local results_file="$1"
    local total_count="$2"
    local rc=0
    
    if (( total_count == 0 )); then
        visa_log "No new jobs found, skipping email"
        return 0
    fi
    
    local subject="🎯 Visa Sponsorships Job Alert: $total_count new QA/SDET positions (semantic search)"
    
    local email_body
    if ! email_body=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "Failed to create email temp file"
        return 1
    fi
    
    # Build email header (using printf for structured data)
    {
        printf 'To: %s\n' "$EMAIL_TO"
        printf 'Subject: %s\n' "$subject"
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf '\n'
        printf 'Hi Claive,\n'
        printf '\n'
        printf '🌍 Found %d new QA/SDET opportunities using semantic keyword search:\n' "$total_count"
        printf '\n'
        printf '============================================================\n'
        printf 'SEARCH METHOD:\n'
        printf '  Keywords: %s\n' "${QA_KEYWORDS[*]}"
        printf '  Seniorities: %s\n' "${VISA_SENIORITY_LEVELS[*]}"
        if ! $INCLUDE_WORLDWIDE; then
            printf '  Location: Visa-friendly countries only (%s)\n' "${VISA_FRIENDLY_COUNTRIES[*]}"
        else
            printf '  Location: Worldwide\n'
        fi
        printf '============================================================\n'
        printf '\n'
    } > "$email_body"

    # List jobs using process substitution – no temporary file needed
    {
        local first=1
        while IFS='|' read -r source seniority title company location url salary; do
            if (( first )); then
                printf '📌 NEW JOB POSTINGS:\n'
                printf '\n'
                first=0
            fi
            
            local salary_display=""
            if [[ -n "$salary" && "$salary" != "null" ]]; then
                salary_display=" - $salary"
            fi
            
            printf '📍 %s @ %s (%s)%s\n' "$title" "$company" "$location" "$salary_display"
            printf '   🔗 %s\n' "$url"
            printf '   🎓 Seniority: %s\n' "$seniority"
            printf '\n'
        done < <(grep '^HIMALAYAS|' "$results_file" 2>/dev/null)
    } >> "$email_body"

    # Summary
    {
        printf '\n---\n'
        printf '📊 SUMMARY\n'
        printf '   Total new jobs: %d\n' "$total_count"
        printf '\n'
        printf '📅 Search performed on: %s\n' "$(date)"
        printf '\n'
        printf '💡 Apply quickly – positions may close soon.\n'
        printf '\n'
        printf '---\n'
        printf '🔧 To modify search keywords or seniority levels, edit the script.\n'
    } >> "$email_body"

    if ! msmtp -a default "$EMAIL_TO" < "$email_body"; then
        visa_log "Failed to send email"
        rc=1
    else
        visa_log "Email sent with $total_count jobs (semantic mode)"
    fi
    
    rm -f "$email_body"
    return "$rc"
}

# ============================================================
# MAIN SEARCH CYCLE
# ============================================================
visa_main_cycle() {
    visa_rotate_seen_file
    visa_json_log "INFO" "Starting semantic job search cycle"
    
    visa_log "=========================================="
    visa_log "Semantic Job Search Started"
    visa_log "Keywords: ${QA_KEYWORDS[*]}"
    visa_log "Seniorities: ${VISA_SENIORITY_LEVELS[*]}"
    visa_log "=========================================="
    
    local temp_results
    if ! temp_results=$(mktemp -p "${TMPDIR:-/tmp}"); then
        visa_log "FATAL: Could not create temp results file"
        return 1
    fi
    
    local total_found=0
    
    for keyword in "${QA_KEYWORDS[@]}"; do
        for seniority in "${VISA_SENIORITY_LEVELS[@]}"; do
            local run_count=0
            visa_search_himalayas "$keyword" "$seniority" "$temp_results" run_count
            total_found=$((total_found + run_count))
        done
    done
    
    visa_log "=========================================="
    visa_log "Search Complete - Found $total_found new jobs"
    visa_log "=========================================="
    
    if (( total_found > 0 )); then
        visa_send_email "$temp_results" "$total_found"
        echo ""
        echo "📊 JOB SEARCH SUMMARY:"
        echo "   Total new jobs: $total_found"
        echo ""
        visa_json_log "SUCCESS" "Sent email with $total_found jobs (semantic search)"
    else
        visa_json_log "INFO" "No new jobs found"
    fi
    
    cat "$temp_results" >> "$LOG_DIR/job_search_$(date +%Y%m%d).log" 2>/dev/null || true
    
    # Explicit cleanup
    rm -f "$temp_results"
    
    visa_update_heartbeat "$total_found"
    visa_json_log "INFO" "Cycle complete"
    
    visa_log "Search complete!"
}

# ============================================================
# EXECUTION FLOW
# ============================================================
if $RUN_ONCE; then
    visa_log "Executing single test pass (--once matched)..."
    visa_main_cycle
    exit 0
fi

while true; do
    visa_main_cycle
    
    MINS=$(( (RANDOM % 21) + 55 ))
    echo "$(date): Cycle complete. Sleeping for $MINS minutes..." | tee -a "$LOG_DIR/job_search_$(date +%Y%m%d).log"
    visa_json_log "INFO" "Sleeping for $MINS minutes (jittered 55-75 min)"
    sleep "${MINS}m"
done
