#!/usr/bin/env bash
# Multi-script monitor: ensures scripts in SCRIPTS array are running,
# kills extras, and notifies if missing.

# Base scripts (always run)
SCRIPTS=(
    "autosync"
    "autobrightness"
    "backlisten"
    "batteryAlertBashScript"
    "btrfs_balance_quarterly"
    "btrfs_scrub_monthly"
    "fortune4you"
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

# --- Main loop ---
while true; do
    # 1. Start with base scripts
    ACTIVE_SCRIPTS=("${SCRIPTS[@]}")
    
    # 2. Define scripts that REQUIRE an internet connection
    INTERNET_REQUIRED=("weather_alarm")

    # 3. Connectivity Logic
    if check_internet; then
        # Online: Add internet-dependent scripts to the active list
        for script in "${INTERNET_REQUIRED[@]}"; do
            ACTIVE_SCRIPTS+=("$script")
        done
    else
        # Offline: Filter out internet scripts and kill running instances
        for script in "${INTERNET_REQUIRED[@]}"; do
            # Remove from the array using pattern substitution
            ACTIVE_SCRIPTS=("${ACTIVE_SCRIPTS[@]/$script/}")
            
            # Identify and kill offline processes
            SCRIPT_FNAME="${script}.sh"
            PIDS=$(pgrep -f "$HOME/Documents/bin/$SCRIPT_FNAME")
            if [[ -n "$PIDS" ]]; then
                for pid in $PIDS; do
                    kill "$pid"
                    notify-send -t 5000 -u critical --app-name "💀 CheckServices" "$SCRIPT_FNAME killed: No internet connection." &
                done
            fi
        done
    fi

    # 4. Process Management Loop
    for SCRIPT_BASENAME in "${ACTIVE_SCRIPTS[@]}"; do
        # Clean up empty indices (from the removal logic above)
        [[ -z "$SCRIPT_BASENAME" ]] && continue
        
        SCRIPT_NAME="${SCRIPT_BASENAME}.sh"
        SCRIPT_PATH="$HOME/Documents/bin/$SCRIPT_NAME"

        # Check for existence
        if [ ! -x "$SCRIPT_PATH" ]; then
            notify-send --app-name "CheckServices" "$SCRIPT_NAME not found or not executable!" &
            continue
        fi

        # Process control
        PROCS=($(pgrep -f "bash $SCRIPT_PATH$"))
        NUM_RUNNING=${#PROCS[@]}

        if [ "$NUM_RUNNING" -gt "$MIN_INSTANCES" ]; then
            # Keep newest instance, kill oldest to ensure freshness
            PIDS_TO_KILL=$(ps -o pid= --sort=start_time -p "${PROCS[@]}" | head -n -$MIN_INSTANCES)
            for pid in $PIDS_TO_KILL; do
                kill "$pid"
                notify-send -t 5000 --app-name "💀 CheckServices" "Extra $SCRIPT_NAME killed: PID $pid" &
            done
        elif [ "$NUM_RUNNING" -lt "$MIN_INSTANCES" ]; then
            # Respawn missing services
            "$SCRIPT_PATH" &
            notify-send -t 5000 --app-name "✅ CheckServices" "$SCRIPT_NAME started."
            sleep 2
        fi
    done

    sleep "$COOLDOWN"
done
