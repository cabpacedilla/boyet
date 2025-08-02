#!/usr/bin/bash
while true; do

MIN_ID=1
NO_ID=0

SCRIPT_NAME="checkservices"
SCRIPT=$(command -v "${SCRIPT_NAME}.sh")
NUM_RUNNING_INSTANCES=$(pgrep -fc "$SCRIPT_NAME")
PROCS=$(pidof -x "$SCRIPT")

if [ "$NUM_RUNNING_INSTANCES" -gt "$MIN_ID" ]; then
   declare -a CHECK_SERVICES_PIDS
   IFS=' ' read -r -a CHECK_SERVICES_PIDS <<< "$PROCS"
   i=0
	last_index=$(( ${#CHECK_SERVICES_PIDS[@]} - 1 ))
	last_value="${CHECK_SERVICES_PIDS[$last_index]}"
		while [ "${CHECK_SERVICES_PIDS[$i]}" != "$last_value" ]; do
		echo "${CHECK_SERVICES_PIDS[$i]}"
		kill "${CHECK_SERVICES_PIDS[$i]}"
		notify-send -t 10000 --app-name "Check services:" "checkservices instance is already running."
		i=$((i + 1))
	done

#elif [ "$CHECK_SERVICES_IDS" -eq $NO_ID ] && [ -z "$CHECK_SERVICES_PROC" ]; then
elif [ "$NUM_RUNNING_INSTANCES" -eq "$NO_ID" ]; then
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

