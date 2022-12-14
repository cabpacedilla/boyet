#!/usr/bin/bash
while true
do

LISTENSCRIPTS_ID=$(pgrep -f listenscripts.sh)
LISTENSCRIPTS_IDS=$(echo "$LISTENSCRIPTS_ID" | grep -o " " | wc -c)
if [ "$LISTENSCRIPTS_IDS" -gt 1 ]; then
  	declare -a LIDCLOSEDARR
  	IFS=' ' read -r -a LISTENSCRIPTSARR <<< "$LISTENSCRIPTS_ID"   
  	i=0
	while [ "${LISTENSCRIPTSARR[$i]}" != "${LISTENSCRIPTSARR[-1]}" ]; do
   	echo "${LISTENSCRIPTSARR[$i]}"
		kill -9 "${LISTENSCRIPTSARR[$i]}"
		notify-send "listenscripts ${LISTENSCRIPTSARR[$i]} process ID is killed."
		i=$[$i +1]
	done
fi

if [ -z "$LISTENSCRIPTS_ID" ]; then
   notify-send "listenscripts is not running. Please check if listenscripts process is running" 
   weatheralarm.sh &  
   if [ $? -eq 0 ]; then
		notify-send "listenscripts is running"
	fi
		
else 
	:
fi

sleep 1s

done
