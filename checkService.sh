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

#!/usr/bin/bash
while true; do

declare -a SERVICES=("blueman-applet" "nm-applet")
declare -a SCRIPTS=("autoupdate" "backlisten" "battalert" "brightness" "cableunplugged" "keylocked" "lidclosed" "lowmem" "tempalarm" "weatheralarm")

MIN_ID=1
NO_ID=0

SERV_CTR=0   
while [ "$SERV_CTR" -lt "${#SERVICES[@]}" ] ; do
   
   # check if service is running comparing array item with pgrep -x 
   if pidof -x "${SERVICES[$SERV_CTR]}"; then
      :
   
   # else, run the service
   else   
      ${SERVICES[$SERV_CTR]} &
      
   fi
   
   SERV_CTR=$((SERV_CTR + 1)) 
done
  
SCRIPTS_CTR=0   
while [ "$SCRIPTS_CTR" -lt "${#SCRIPTS[@]}" ] ; do
   
   # Count number of processes of the script and the process IDs of the scripts
	IDS=$(pgrep -c "${SCRIPTS[$SCRIPTS_CTR]}")
	PROCS=$(pidof -x "${SCRIPTS[$SCRIPTS_CTR]}.sh")
   
   # If number of processes is more than 1, leave only one and kill the rest
   if [ "$IDS" -gt "$MIN_ID" ]; then
   	declare -a SCRIPTSARR
		IFS=' ' read -r -a SCRIPTSARR <<< "$PROCS"   
		PROCS_CTR=0
  		while [ "${SCRIPTSARR[$PROCS_CTR]}" != "${SCRIPTSARR[-1]}" ]; do
  	   	kill -9 "${SCRIPTSARR[$PROCS_CTR]}"
     		notify-send "${SCRIPTS[$SCRIPTS_CTR]} ${SCRIPTSARR[$PROCS_CTR]} process ID is killed."
			PROCS_CTR=$((PROCS_CTR + 1))
		done
	fi
  
   # If script is not running, run the script. Else, do nothing.
	if [ "$IDS" -eq "$NO_ID" ]; then
		notify-send "${SCRIPTS[$SCRIPTS_CTR]} is not running. Please check if ${SCRIPTS[$SCRIPTS_CTR]} process is running" 	  
		if ${SCRIPTS[$SCRIPTS_CTR]} & then
			notify-send "${SCRIPTS[SCRIPTS_CTR]} is running"
		fi 
	else 
		:
	fi
   
   SCRIPTS_CTR=$((SCRIPTS_CTR + 1))
done

sleep 1s
done
