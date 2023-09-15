#!/bin/bash
while true; do

LID_PATH=/proc/acpi/button/lid/LID0/state

## 1. Set for open state
OPEN_STATE="open"
   
## 2. Get laptop lid state
LID_STATE=$(cat $LID_PATH | awk '{print $2}')

## 3. Do nothing if lid is open
if [ "$LID_STATE" = "$OPEN_STATE" ]; then
	lxqt-config-monitor -l 	  
## 4. Suspend if lid is closed
else 
	lxqt-config-monitor -l 
	
fi

sleep 0.1s
done
