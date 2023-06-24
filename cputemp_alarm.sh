#!/usr/bin/bash
# This script will alert when the CPU temperature equal or greater than 90 degree Celcius
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

while true
do

HIGHTEMP=90
#TEMPEST=$(sensors | grep Tctl | awk '{print $2}')
#TEMPEST=$(echo "$TEMPEST" | awk '{ print substr( $0, 2, length($0)-3 ) }')
TEMPEST=$(cat /sys/class/thermal/thermal_zone0/temp | awk '{ print ($1 / 1000) }'

if [ -z "$TEMPEST" ]; then
	continue
elif (( $(echo "$TEMPEST > $HIGHTEMP" | bc -l) )); then
	notify-send -u normal "CPU temp alert!" "$HIGHTEMP degrees C temp is high. Please check application with high CPU usage."
else 
	:
fi

sleep 1 
done
