#!/usr/bin/bash
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

while true; do

declare -a SERVICES=("blueman-applet" "nm-applet")
declare -a APPS=("Skype" "Thunderbird")
declare -a SCRIPTS=("autosync" "autoupdate" "backlisten" "battalert" "battery_usage" "brightness" "checkmonitorfailures" "fortune" "keylocked" "lidclosed" "lowmembypercent" "runscreensaver" "weatheralarm")

MIN_ID=1
NO_ID=0

SERV_CTR=0   
while [ "$SERV_CTR" -lt "${#SERVICES[@]}" ]; do
   
   # check if service is running comparing array item with pgrep -x 
   if pidof -x "${SERVICES[$SERV_CTR]}"; then
      :
   
   # else, run the service
   else   
      ${SERVICES[$SERV_CTR]} &
      
   fi
   
   SERV_CTR=$((SERV_CTR + 1)) 
done
  
APP_CTR=0  
while [ "$APP_CTR" -lt "${#APPS[@]}" ]; do
	APP_WIN=$(wmctrl -lp | grep "${APPS[APP_CTR]}" | awk '{print $1}')	
	echo "$APP_WIN"
	declare -a APP_ARR
	IFS=' ' read -r -a APP_ARR <<< "$APP_WIN"  
	if wmctrl -lp | grep "${APPS[APP_CTR]}" | awk '{print $1}'; then
   	:
   fi
   
   if [ -z "$APP_WIN" ]; then
		notify-send --app-name "Check services:" "${APPS[APP_CTR]} is not running. Please check if ${APPS[APP_CTR]} process is running" &
		WIN_APP=${APPS[APP_CTR]}
		echo "$WIN_APP"
		WIN_APP=$(echo "$WIN_APP" | awk '{print tolower($0)}')
		echo "$WIN_APP"
		if [ "$WIN_APP" = "skype" ]; then
			WIN_APP=skypeforlinux
			if "$WIN_APP" & then
				notify-send --app-name "Check services:" "${APPS[APP_CTR]} is running"
			fi
		else		
			ARR_IDS=$(pgrep -c "${APP_ARR[ARR_CTR]}")
			if [ "$ARR_IDS" -gt "$MIN_ID" ]; then
				while [ "${APP_ARR[ARR_CTR]}" != "${APP_ARR[-1]}" ]; do
					kill -9 "${APP_ARR[ARR_CTR]}"
     				notify-send --app-name "Check services:" "${APP_ARR[ARR_CTR]} instance is already running."
     				ARR_CTR=$((ARR_CTR + 1))
     			done
	   		if "$WIN_APP" & then
					notify-send --app-name "Check services:" "${APPS[APP_CTR]} is running"
				fi
	      fi
	   fi	
	fi
	APP_CTR=$((APP_CTR + 1))
done
	
declare -a SCRIPTS=("autosync" "auto_update_nobara" "autobrightness" "backlisten" "batteryAlertBashScript" "battery_usage" "btrfs_balance_quarterly" "btrfs_scrub_monthly" "fortune4you" "keyLocked" "laptopLid_close" "lowMemAlert" "monitor_failures" "runscreensaver" "weather_alarm")

MIN_ID=1
NO_ID=0

while true; do
SCRIPTS_CTR=0

while [ "$SCRIPTS_CTR" -lt "${#SCRIPTS[@]}" ] ; do
	# Count number of processes of the script and the process IDs of the scripts
	SCRIPT_NAME=$(basename "${SCRIPTS[$SCRIPTS_CTR]}")
	SCRIPT=$(command -v "${SCRIPT_NAME}.sh")
	IDS=$(pgrep -fcx "$SCRIPT_NAME")
	PROCS=$(pgrep -fx "$SCRIPT")

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
