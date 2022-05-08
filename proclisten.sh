#!/usr/bin/bash
while true
do
	WEB_ID=$(pidof -s firefox)
	if [ -z "$SLACK_ID" ]; then
		firefox &  
	fi
	
	MAIL_WIN=$(wmctrl -lp | grep Thunderbird | awk '{print $1}')
	if [ -z "$MAIL_WIN" ]; then
		thunderbird &
	fi

	LOWMEM_ID=$(pidof -x lowmem.sh)
	if [ -z "$LOWMEM_ID" ]; then
		lowmem.sh &   
	fi

	sleep 3
done
