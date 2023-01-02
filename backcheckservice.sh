#!/usr/bin/bash
while true
do

MIN_ID=1
NO_ID=0

CHECK_SERVICES_IDS=$(pgrep -c checkservices)
CHECK_SERVICES_PROC=$(pidof -x checkservices.sh)
if [ "$CHECK_SERVICES_IDS" -gt $MIN_ID ]; then
   declare -a CHECK_SERVICESARR
   IFS=' ' read -r -a CHECK_SERVICESARR <<< "$CHECK_SERVICES_PROC"   
   i=0
	while [ "${CHECK_SERVICESARR[$i]}" != "${CHECK_SERVICESARR[-1]}" ]; do
	   echo "${CHECK_SERVICESARR[$i]}"
		kill -9 "${CHECK_SERVICESARR[$i]}"
		notify-send "${CHECK_SERVICESARR[$i]} instance is already running."
		i=$((i + 1))
	done
fi

if [ "$CHECK_SERVICES_IDS" -eq $NO_ID ]; then
	notify-send "checkservices is not running. Please check if checkservices process is running" 
	if checkservices.sh & then
		notify-send "checkservices is running"
	fi		
else 
	:
fi

sleep 1s

done
