#!/usr/bin/bash
declare -a SCRIPTS=("alarmtemp" "autoupdate" "backlisten" "battalert" "brightness" "fortune" "keylocked" "lowmem" "screensavercheck" "weatheralarm")
MIN_ID=1
NO_ID=0

while true; do
SCRIPTS_CTR=0 
   		
while [ "$SCRIPTS_CTR" -lt "${#SCRIPTS[@]}" ] ; do
	# Count number of processes of the script and the process IDs of the scripts
	SCRIPT_NAME=$(basename "${SCRIPTS[$SCRIPTS_CTR]}")
	SCRIPT=$(command -v "${SCRIPT_NAME}.sh")	
	IDS=$(pgrep -c "$SCRIPT_NAME")	
	PROCS=$(pidof -x -z "$SCRIPT")
	  
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
	elif [ "$IDS" -eq "$NO_ID" ] && [ -z "$PROCS" ]; then
		notify-send --app-name "Check services:" "$SCRIPT_NAME is not running. Please check if $SCRIPT_NAME process is running" 	  
		if "$SCRIPT" & then
			notify-send --app-name "Check services:" "$SCRIPT_NAME is running"
		fi 
	else 
		:
	fi   
   SCRIPTS_CTR=$((SCRIPTS_CTR + 1))
done

sleep 1s
done
