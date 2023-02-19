#!/usr/bin/bash
# This script will alert when the CPU temperature equal or greater than 90 degree Celcius
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

while true
do

TEMPEST=$(sensors | grep Tctl | awk '{print $2}')
TEMPEST=$(echo "$TEMPEST" | awk '{ print substr( $0, 2, length($0)-3 ) }')
HIGHTEMP=90

if [ -z "$TEMPEST" ]; then
	continue
elif (( $(echo "$TEMPEST > $HIGHTEMP" | bc -l) )); then
	notify-send "CPU temp alert!" "$HIGHTEMP degrees C temp is high. Please check application with high CPU usage."
else 
	:
fi

sleep 1 
done
