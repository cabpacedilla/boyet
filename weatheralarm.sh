#!/usr/bin/bash
while true
do

WEATHER_FILE=~/bin/weather.txt
VERYHUMID=85
HIGHTEMP=33
STRONGWIND=50
HEAVYRAIN=4.0

curl wttr.in/Cebu?format="%l:+%h+%t+%w+%p+%u" --silent --max-time 3 > $WEATHER_FILE

HUMID=$(cat $WEATHER_FILE | awk '{print $2}')
HUMID=${HUMID:0:-1}
if [ "$HUMID" -ge "$VERYHUMID" ]; then
   notify-send "It's very humid outside. Stay in an airy place."
else
   :
fi

TEMP=$(cat $WEATHER_FILE | awk '{print $3}')
TEMP=${TEMP:1:-2}
if [ "$TEMP" -ge "$HIGHTEMP" ]; then
	notify-send "It's very hot and outside. Stay in a cooler place."
else
   :
fi

WIND=$(cat $WEATHER_FILE | awk '{print $4}')
#echo $WIND
WIND=${WIND:1:-4}
#echo $SPEED
if [ "$WIND" -ge "$STRONGWIND" ]; then
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

UV=$(cat $WEATHER_FILE | awk '{print $6}')
echo $UV
if [ "$UV" -ge 3 ] || [ "$UV" -le 5 ]; then
   notify-send "Ultraviolet is $UV. Wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses to protect from the sun."
   
elif [ "$UV" -ge 6 ] || [ "$UV" -le 7 ]; then
   notify-send "Ultraviolet is $UV. Wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm to protect from the sun."
   
elif [ "$UV" -ge 8 ] || [ "$UV" -le 10 ]; then
   notify-send "Ultraviolet is $UV. Wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the shade."
   
elif [ "$UV" -gt 11 ]; then
   notify-send "Ultraviolet is $UV. Wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the the building."

fi

sleep 5m
done
