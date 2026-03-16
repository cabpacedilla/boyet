#!/usr/bin/env bash
# This script will check if a process is running. If the process is not running, it will run the process.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# December 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like checkService.sh
# 4. Make file executable with chmod +x checkService.sh command
# 5. Add the checkService.sh command in Startup applications
# 6. Reboot the laptop and login
# 7. The script will run the process if the process is not running

# declare -a SERVICES=("blueman-applet" "nm-appletbasha")
# declare -a APPS=("Skype" "Thunderbird")
declare -a SCRIPTS=(
    "monitor_system_failures"
    "secuirty_audit"
    "secuirty_check"
)

MIN_ID=1
NO_ID=0

while true; do
SCRIPTS_CTR=0

while [ "$SCRIPTS_CTR" -lt "${#SCRIPTS[@]}" ] ; do
	# Count number of processes of the script and the process IDs of the scripts
	SCRIPT_NAME="${SCRIPTS[$SCRIPTS_CTR]}"
# 	SCRIPT="/usr/usr/bin/bash /home/claiveapa/Documents/bin/${SCRIPT_NAME}.sh"
	SCRIPT=$(command -v "${SCRIPT_NAME}.sh")
	IDS=$(pgrep -fc "$SCRIPT_NAME")
	PROCS=$(pidof -x "$SCRIPT")

   # If number of processes is more than 1, leave only one and kill the rest
   if [ "$IDS" -gt "$MIN_ID" ]; then
		declare -a SCRIPTSARR
		IFS=' ' read -r -a SCRIPTSARR <<< "$PROCS"
		i=0
		last_index=$(( ${#SCRIPTSARR[@]} - 1 ))
		last_value="${SCRIPTSARR[$last_index]}"
		while [ "${SCRIPTSARR[$i]}" != "$last_value" ]; do
			echo "${SCRIPTSARR[$i]}"
			kill "${SCRIPTSARR[$i]}"
     		notify-send --app-name "Check monitoring:" "$SCRIPT_NAME instance is already running."
			i=$((i + 1))
		done
   # If script is not running, run the script. Else, do nothing.
	elif [ "$IDS" -eq "$NO_ID" ]; then
		notify-send --app-name "Check monitoring:" "$SCRIPT_NAME is not running. Please check if $SCRIPT_NAME process is running"
		SCRIPT_PATH="$HOME/Documents/bin/${SCRIPT_NAME}.sh"
		if [ -x "$SCRIPT_PATH" ]; then
			"$SCRIPT_PATH" &
			notify-send --app-name "Check monitoring:" "$SCRIPT_NAME is running"
		fi
	else
		:
	fi
   SCRIPTS_CTR=$((SCRIPTS_CTR + 1))
done

sleep 1s
done

