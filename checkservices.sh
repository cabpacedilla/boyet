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

# Network interfaces for Fedora/Nobara
WIRED_IFACE="enp3s0f3u2"
WIFI_IFACE="wlp1s0"

COOLDOWN=5   # seconds between checks
MIN_INSTANCES=1

# Function: check if either wired or wifi is connected
check_internet() {
    local CABLE_STAT WLAN_STAT

    [[ -f "/sys/class/net/$WIRED_IFACE/carrier" ]] && CABLE_STAT=$(cat "/sys/class/net/$WIRED_IFACE/carrier")
    [[ -f "/sys/class/net/$WIFI_IFACE/carrier" ]] && WLAN_STAT=$(cat "/sys/class/net/$WIFI_IFACE/carrier")

    [[ "$CABLE_STAT" == "1" || "$WLAN_STAT" == "1" ]]
}

while true; do
    # Start with base scripts
    ACTIVE_SCRIPTS=("${SCRIPTS[@]}")

    # Include weather_alarm only if internet is up
    # Include weather_alarm only if internet is up
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
