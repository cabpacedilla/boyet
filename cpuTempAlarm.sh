# This script will alert when the CPU temperature equal or greater than 90 degree Celcius
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

#!/usr/bin/bash
while true
do

TEMPEST=$(sensors | sed '19q;d' | awk '{print $2}')
TEMPNUM="${TEMPEST:1:-4}"
HIGHTEMP=90

if [ "$TEMPNUM" -ge "$HIGHTEMP" ]; then
	notify-send "CPU temp is high. Please check application with high CPU usage."
	
else 
	:

fi

sleep 1 
done
