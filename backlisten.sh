#!/usr/bin/bash
while true; do

MIN_ID=1
NO_ID=0

SCRIPT_NAME="checkservices"
SCRIPT=$(command -v "${SCRIPT_NAME}.sh")
IDS=$(pgrep -fc "$SCRIPT_NAME")
PROCS=$(pidof -x "$SCRIPT")

if [ "$IDS" -gt "$MIN_ID" ]; then
   declare -a CHECK_SERVICESARR
   IFS=' ' read -r -a CHECK_SERVICESARR <<< "$PROCS"
   i=0
	last_index=$(( ${#CHECK_SERVICESARR[@]} - 1 ))
	last_value="${CHECK_SERVICESARR[$last_index]}"
		while [ "${CHECK_SERVICESARR[$i]}" != "$last_value" ]; do
		echo "${CHECK_SERVICESARR[$i]}"
		kill "${CHECK_SERVICESARR[$i]}"
		notify-send -t 10000 --app-name "Check services:" "checkservices instance is already running."
		i=$((i + 1))
	done

#elif [ "$CHECK_SERVICES_IDS" -eq $NO_ID ] && [ -z "$CHECK_SERVICES_PROC" ]; then
elif [ "$IDS" -eq "$NO_ID" ]; then
	notify-send --app-name "Check services:" "checkservices is not running. Please check if checkservices process is running"
	SCRIPT_PATH="$HOME/Documents/bin/${SCRIPT_NAME}.sh"
	if [ -x "$SCRIPT_PATH" ]; then
		"$SCRIPT_PATH" &
		notify-send -t 10000 --app-name "Check services:" "checkservices is running"
	fi
else
	:
fi

sleep 1s

done

