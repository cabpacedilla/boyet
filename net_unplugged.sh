#!/usr/bin/bash
while true
do

# Set connection status
CONNECTED=1

#CABLE_STAT=$(cat /sys/class/net/veth14a056a/carrier) 
WLAN_STAT=$(cat /sys/class/net/wlp1s0/carrier)

if [ "$WLAN_STAT" -eq "$CONNECTED" ]; then
	:
else
	notify-send --app-name "Network connection:" "Laptop is not connected to the network."
fi

sleep 10s
done
