#!/usr/bin/env bash
# Multi-script monitor: ensures scripts in SCRIPTS array are running,
# kills extras, and notifies if missing.

#~ LOCK_FILE="/tmp/checkservices_$(whoami).lock"
#~ exec 9>"${LOCK_FILE}"
#~ if ! flock -n 9; then
    #~ exit 1
#~ fi

#~ # Store our PID
#~ echo $$ > "$LOCK_FILE"

# Setup logging
LOG_FILE="$HOME/scriptlogs/checkservices.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

log_info() {
    local msg="[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

log_warn() {
    local msg="[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9 2>/dev/null
    exec 9>&-
}

trap cleanup EXIT

# Base scripts (always run)
SCRIPTS=(
    "autosync"
    "autobrightness"
    "backlisten"
    "batteryAlertBashScript"
    "btrfs_balance_quarterly"
    "btrfs_scrub_monthly"
    "fortune4you"
    "job_rotate"
    "keyLocked"
    "laptopLid_close"
    "login_monitor"
    "low_disk_space"
    "lowMemAlert"
    "power_usage"
    "runscreensaver"
    "security_check"
)

COOLDOWN=30   # seconds between checks
MIN_INSTANCES=1

# --- Function to check Internet connectivity ---
check_internet() {
    # Check Google and Cloudflare for high reliability
    if curl -s --connect-timeout 5 "https://www.google.com" >/dev/null 2>&1 || \
       curl -s --connect-timeout 5 "https://www.cloudflare.com" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# --- Special function for security_check which spawns child processes ---
check_security_monitor() {
    local SCRIPT_PATH="$HOME/Documents/bin/security_check.sh"
    local PID_FILE="/run/fedora-sec/monitor.lock"
    
    # Check using PID file first (most reliable)
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            # Main process is running, check if it's actually working
            local heartbeat_file="/run/fedora-sec/heartbeats/services"
            if [[ -f "$heartbeat_file" ]]; then
                local last_heartbeat=$(cat "$heartbeat_file" 2>/dev/null)
                local now=$(date +%s)
                # If heartbeat is older than 60 seconds, something is wrong
                if [[ -n "$last_heartbeat" ]] && (( now - last_heartbeat > 60 )); then
                    log_warn "Security monitor heartbeat stale - may need restart"
                    notify-send -t 5000 --app-name "⚠️ CheckServices" "Security monitor heartbeat stale - may need restart" &
                fi
            fi
            return 0  # Running
        fi
    fi
    
    # Fallback: check if any security_check process is running
    local main_pid=$(pgrep -f "security_check.sh" | head -1)
    if [[ -n "$main_pid" ]] && kill -0 "$main_pid" 2>/dev/null; then
        return 0  # Running
    fi
    
    # Not running, start it
    log_info "Security monitor not running, starting..."
    "$SCRIPT_PATH" &
    notify-send -t 5000 --app-name "✅ CheckServices" "Security monitor started."
    sleep 2
    return 1
}

# --- Function to remove a script from array properly ---
remove_from_array() {
    local target="$1"
    shift
    local result=()
    for item in "$@"; do
        if [[ "$item" != "$target" ]]; then
            result+=("$item")
        fi
    done
    printf '%s\n' "${result[@]}"
}

# --- Main loop ---
while true; do
    log_info "Checking services..."
    
    # 1. Start with base scripts
    ACTIVE_SCRIPTS=("${SCRIPTS[@]}")
    
    # 2. Define scripts that REQUIRE an internet connection
    INTERNET_REQUIRED=("weather_alarm")

    # 3. Connectivity Logic
    if check_internet; then
        log_info "Internet connected - adding internet-dependent scripts"
        # Online: Add internet-dependent scripts to the active list
        for script in "${INTERNET_REQUIRED[@]}"; do
            ACTIVE_SCRIPTS+=("$script")
        done
    else
        log_info "No internet connection - removing internet-dependent scripts"
        # Offline: Filter out internet scripts and kill running instances
        for script in "${INTERNET_REQUIRED[@]}"; do
            # Rebuild array without this script
            ACTIVE_SCRIPTS=($(remove_from_array "$script" "${ACTIVE_SCRIPTS[@]}"))
            
            # Identify and kill offline processes
            SCRIPT_FNAME="${script}.sh"
            PIDS=$(pgrep -f "$HOME/Documents/bin/$SCRIPT_FNAME")
            if [[ -n "$PIDS" ]]; then
                for pid in $PIDS; do
                    kill "$pid" 2>/dev/null
                    log_warn "Killed $SCRIPT_FNAME (PID $pid) - no internet"
                    notify-send -t 5000 -u critical --app-name "💀 CheckServices" "$SCRIPT_FNAME killed: No internet connection." &
                done
            fi
        done
    fi

    # 4. Process Management Loop
    for SCRIPT_BASENAME in "${ACTIVE_SCRIPTS[@]}"; do
        # Skip empty entries
        [[ -z "$SCRIPT_BASENAME" ]] && continue
        
        # ============================================
        # SPECIAL CASE: security_check
        # ============================================
        if [[ "$SCRIPT_BASENAME" == "security_check" ]]; then
            check_security_monitor
            continue
        fi
        
        # ============================================
        # NORMAL PROCESSING for all other scripts
        # ============================================
        SCRIPT_NAME="${SCRIPT_BASENAME}.sh"
        SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"

        # Check for existence
        if [ ! -x "$SCRIPT_PATH" ]; then
            log_warn "$SCRIPT_NAME not found or not executable"
            notify-send --app-name "CheckServices" "$SCRIPT_NAME not found or not executable!" &
            continue
        fi

        # Process control - find all matching processes
        PROCS=($(pgrep -f "$SCRIPT_PATH$"))
        NUM_RUNNING=${#PROCS[@]}

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            # Keep newest instance, kill oldest to ensure freshness
            PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" 2>/dev/null | head -n -$MIN_INSTANCES)
            for pid in $PIDS_TO_KILL; do
                kill "$pid" 2>/dev/null
                log_info "Killed extra $SCRIPT_NAME (PID $pid)"
                notify-send -t 5000 --app-name "💀 CheckServices" "Extra $SCRIPT_NAME killed: PID $pid" &
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            # Respawn missing services
            log_info "Starting missing $SCRIPT_NAME"
            "$SCRIPT_PATH" &
            notify-send -t 5000 --app-name "✅ CheckServices" "$SCRIPT_NAME started."
            sleep 2
        fi
    done

    sleep "$COOLDOWN"
done
