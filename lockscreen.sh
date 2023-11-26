#!/usr/bin/bash

sudo echo 80 | sudo tee /sys/class/backlight/amdgpu_bl0/brightness &
xscreensaver-command -lock &

SECONDS_COMPARE()
{
	NEW_TIME=$(date +"%I:%M:%S")
	NEW_SECONDS=${NEW_TIME:6} 
	NEW_MINUTES=${NEW_TIME:3:2}
	NEW_HOURS=${NEW_TIME:0:2}
	NEW_TIME="$NEW_HOURS:$NEW_MINUTES:$NEW_SECONDS"
	while [ "$NEW_TIME" != "$1" ]; do
		NEW_TIME=$(date +"%I:%M:%S")
		NEW_SECONDS=${NEW_TIME:6} 
		NEW_MINUTES=${NEW_TIME:3:2}
		NEW_HOURS=${NEW_TIME:0:2}
		NEW_TIME="$NEW_HOURS:$NEW_MINUTES:$NEW_SECONDS"
		continue
	done
	if [ "$NEW_TIME" == "$1" ]; then
		systemctl suspend & 
	fi
}

TICK=60
TIME_INITIAL=$(date +"%I:%M:%S")
START_SECONDS=${TIME_INITIAL:6} 
START_MINUTES=${TIME_INITIAL:3:2}
START_HOURS=${TIME_INITIAL:0:2}
echo "start seconds " $START_SECONDS
echo "start minutes " $START_MINUTES
echo "start hours " $START_HOURS
TO_SUSPEND=$(($START_SECONDS + $TICK))
echo "to suspend " $TO_SUSPEND
if [ $TO_SUSPEND -eq $TICK ]; then
	START_MINUTES=$(($START_MINUTES + 6))
	START_SECONDS=0
	echo "start minustes " START_MINUTES
fi

if [ $TO_SUSPEND -gt $TICK ]; then
	TO_SUSPEND=$(($TO_SUSPEND - $TICK))
	echo "to suspend " $TO_SUSPEND
	START_SECONDS=$TO_SUSPEND
	START_MINUTES=$(($START_MINUTES + 6))
	echo "start minutes " $START_MINUTES
	if [ $START_MINUTES -eq $TICK ]; then
		START_HOURS=$((START_HOURS + 1))
		START_MINUTES=0
		echo "start hours " $START_HOURS	
	fi
else
	START_SECONDS=$TO_SUSPEND
fi

TIME_FINAL="$START_HOURS:$START_MINUTES:$START_SECONDS"
echo $TIME_FINAL
SECONDS_COMPARE $TIME_FINAL	


