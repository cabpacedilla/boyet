#!/usr/bin/bash

WEATHER_FILE=~/bin/weather.txt
VERYHUMID=85
HIGHTEMP=33
STRONGWIND=50
HEAVYRAIN=4.0

curl wttr.in/Cebu?format="%l:+%h+%t+%w+%p" --silent --max-time 3 > $WEATHER_FILE

HUMID=$(cat $WEATHER_FILE | awk '{print $2}')
HUMID=${HUMID:0:-1}
if [ "$HUMID" -gt "$VERYHUMID" ]; then
   notify-send "It's very humid outside. Stay in an airy place."
else
   :
fi

TEMP=$(cat $WEATHER_FILE | awk '{print $3}')
TEMP=${TEMP:1:-2}
if [ "$TEMP" -gt "$HIGHTEMP" ]; then
	notify-send "It's very hot outside. Stay in a cooler place."
else
   :
fi

WIND=$(cat $WEATHER_FILE | awk '{print $4}')
#echo $WIND
WIND=${WIND:1:-4}
#echo $SPEED
if [ "$WIND" -gt "$STRONGWIND" ]; then
  notify-send "Winds outside are strong. Stay inside."
else
	:
fi

RAINFALL=$(cat $WEATHER_FILE | awk '{print $5}')
RAINFALL=${RAINFALL:0:-2}
COMPARE=`echo "$RAINFALL > $HEAVYRAIN" | bc`
if [ "$COMPARE" -eq 1 ]; then
   notify-send "It is raining heavily outside."
else
	:
fi

sleep 5m

