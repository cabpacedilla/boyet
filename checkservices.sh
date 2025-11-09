#!/usr/bin/env bash
# Multi-script monitor: ensures scripts in SCRIPTS array are running,
# kills extras, and notifies if missing.
# weather_alarm.sh runs only when wired or Wi-Fi connection is active

# Base scripts (always run)
SCRIPTS=(
    "autosync"
    "autobrightness"
    "backlisten"
    "batteryAlertBashScript"
    #~ "battery_usage"
    "btrfs_balance_quarterly"
    "btrfs_scrub_monthly"
    "fortune4you"
#     "hot_parts"
    "keyLocked"
    #~ "laptopLid_close"
    "login_monitor"
    "low_disk_space"
    "lowMemAlert"
    "power_usage"
    "runscreensaver"
    "security_check"
)

COOLDOWN=5   # seconds between checks
MIN_INSTANCES=1

# --- Function to check Internet connectivity ---
check_internet() {
    # Just use HTTP requests - these almost always work if internet is available
    if curl -s --connect-timeout 5 "https://www.google.com" >/dev/null 2>&1; then
        return 0
    fi
    
    if curl -s --connect-timeout 5 "https://www.cloudflare.com" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# --- Main loop ---
while true; do
    # Start with base scripts
    ACTIVE_SCRIPTS=("${SCRIPTS[@]}")

    # Include weather_alarm only if Internet is up
    if check_internet; then
        ACTIVE_SCRIPTS+=("weather_alarm")
        echo "DEBUG: Internet detected — weather_alarm included."
    else
        # Remove weather_alarm from ACTIVE_SCRIPTS to prevent restart
        ACTIVE_SCRIPTS=("${ACTIVE_SCRIPTS[@]/weather_alarm/}")

        # If weather_alarm is running while offline, kill it
        PIDS=$(pgrep -f "$HOME/Documents/bin/weather_alarm.sh")
        if [[ -n "$PIDS" ]]; then
            for pid in $PIDS; do
                kill "$pid"
                notify-send -t 5000 --app-name "💀 CheckServices" "weather_alarm killed: no internet (PID $pid)" &
            done
        fi
        echo "DEBUG: No internet — weather_alarm excluded."
    fi

    # Loop through all active scripts
    for SCRIPT_BASENAME in "${ACTIVE_SCRIPTS[@]}"; do
        SCRIPT_NAME="${SCRIPT_BASENAME}.sh"
        SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"

        # Skip if not found or not executable
        if [ ! -x "$SCRIPT_PATH" ]; then
            notify-send --app-name "CheckServices" "$SCRIPT_NAME not found or not executable!" &
            continue
        fi

        # Detect running processes by full path
        PROCS=($(pgrep -f "bash $SCRIPT_PATH$"))
        NUM_RUNNING=${#PROCS[@]}

        echo "DEBUG: Checking $SCRIPT_NAME → PIDs: ${PROCS[*]:-none}"

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            # Kill older ones, keep the newest
            PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -$MIN_INSTANCES)
            for pid in $PIDS_TO_KILL; do
                kill "$pid"
                notify-send -t 5000 --app-name "💀 CheckServices" "Extra $SCRIPT_NAME killed: PID $pid" &
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            "$SCRIPT_PATH" &
            notify-send -t 5000 --app-name "✅ CheckServices" "$SCRIPT_NAME started."
            sleep 5
        fi
    done

    sleep "$COOLDOWN"
done
