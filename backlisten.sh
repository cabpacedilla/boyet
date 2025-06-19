#!/usr/bin/bash
while true; do

MIN_ID=1
NO_ID=0

CHECK_SERVICES_IDS=$(pgrep -fcx "checkservices")
CHECK_SERVICES_PROC=$(pgrep -fx "checkservices.sh")

if [ "$CHECK_SERVICES_IDS" -gt $MIN_ID ]; then
   declare -a CHECK_SERVICESARR
   IFS=' ' read -r -a CHECK_SERVICESARR <<< "$CHECK_SERVICES_PROC"
   i=0
	while [ "${CHECK_SERVICESARR[$i]}" != "${CHECK_SERVICESARR[-1]}" ]; do
	   echo "${CHECK_SERVICESARR[$i]}"
		kill "${CHECK_SERVICESARR[$i]}"
		notify-send -t 10000 --app-name "Check services:" "checkservices instance is already running."
		i=$((i + 1))
	done

#elif [ "$CHECK_SERVICES_IDS" -eq $NO_ID ] && [ -z "$CHECK_SERVICES_PROC" ]; then
elif [ "$CHECK_SERVICES_IDS" -eq $NO_ID ]; then
	notify-send --app-name "Check services:" "checkservices is not running. Please check if checkservices process is running"
	if ./checkservices.sh & then
		notify-send -t 10000 --app-name "Check idle:" "checkservices is running"
	fi
else
	:
fi

sleep 1s

done

