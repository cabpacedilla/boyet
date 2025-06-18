#!/usr/bin/bash
declare -a SCRIPTS=("autosync" "auto_update_nobara" "autobrightness" "backlisten" "batteryAlertBashScript" "battery_usage" "btrfs_balance_quarterly" "btrfs_scrub_monthly" "fortune4you" "keyLocked" "laptopLid_close" "lowMemAlert" "monitor_failures" "runscreensaver" "weather_alarm")

MIN_ID=1
NO_ID=0
SCRIPTS_CTR=0

while true; do
while [ "$SCRIPTS_CTR" -lt "${#SCRIPTS[@]}" ] ; do
	# Count number of processes of the script and the process IDs of the scripts
	SCRIPT_NAME=$(basename "${SCRIPTS[$SCRIPTS_CTR]}")
	SCRIPT=$(command -v "${SCRIPT_NAME}")
	IDS=$(pgrep -c "$SCRIPT_NAME")
	PROCS=$(pidof -x "$SCRIPT")

   # If number of processes is more than 1, leave only one and kill the rest
   if [ "$IDS" -gt "$MIN_ID" ]; then
		IFS=' ' read -r -a SCRIPTSARR <<< "$PROCS"
		i=0
  		while [ "${SCRIPTSARR[$i]}" != "${SCRIPTSARR[-1]}" ]; do
  	   	kill "${SCRIPTSARR[$i]}"
     		notify-send --app-name "Check services:" "$SCRIPT_NAME instance is already running."
			i=$((i + 1))
		done
   # If script is not running, run the script. Else, do nothing.
	elif [ "$IDS" -eq "$NO_ID" ]; then
		notify-send --app-name "Check services:" "$SCRIPT_NAME is not running. Please check if $SCRIPT_NAME process is running"
		SCRIPT_PATH="$HOME/Documents/bin/${SCRIPT_NAME}.sh"
		if [ -x "$SCRIPT_PATH" ]; then
			"$SCRIPT_PATH" &
			notify-send --app-name "Check services:" "$SCRIPT_NAME is running"
		fi
	else
		:
	fi
   SCRIPTS_CTR=$((SCRIPTS_CTR + 1))
done

sleep 1s
done

