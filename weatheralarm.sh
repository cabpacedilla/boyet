#!/usr/bin/bash
while true
do

WEATHER_FILE=~/bin/weather.txt
VERYHUMID=85
HIGHTEMP=33
STRONGWIND=50
LIGHTRAIN=2.5
MODRAINLOWER=2.5
HEAVYRAIN=7.6
VIOLENTRAIN=50

curl wttr.in/Maasin?format="%l:+%h+%t+%w+%p+%u+%C" --silent --max-time 3 > $WEATHER_FILE

WEATHER=$(cat $WEATHER_FILE | awk '{$1=$2=$3=$4=$5=$6=""; print $0}')
notify-send "Weather update:" "The weather is $WEATHER."

HUMID=$(cat $WEATHER_FILE | awk '{print $2}')
HUMID=${HUMID:0:-1}
if [ "$HUMID" -ge "$VERYHUMID" ]; then
   notify-send "It's very humid and $WEATHER outside. Stay in an airy place."
else
   :
fi

TEMP=$(cat $WEATHER_FILE | awk '{print $3}')
TEMP=${TEMP:1:-2}
if [ "$TEMP" -ge "$HIGHTEMP" ]; then
	notify-send "Weather warning:" "It's very hot and $WEATHER outside. Stay in a cooler place."
else
   :
fi

WIND=$(cat $WEATHER_FILE | awk '{print $4}')
WIND=${WIND:1:-4}
if [ "$WIND" -ge "$STRONGWIND" ]; then
  notify-send "Weather warning:" "It's very windy and $WEATHER outside. Stay inside."
else
	:
fi

RAINFALL=$(cat $WEATHER_FILE | awk '{print $5}')
RAINFALL=${RAINFALL:0:-2}
COMPARELIGHT=`echo "$RAINFALL < $LIGHTRAIN" | bc`
if [ "$COMPARELIGHT" -eq 1 ]; then
   notify-send "Weather warning:" "It's raining lightly outside. Use an umbrella or wear a raincoat."
fi

COMPAREMODLOWER=`echo "$RAINFALL > $MODRAINLOWER" | bc`  
COMPAREMODUPPER=`echo "$RAINFALL < $HEAVYRAIN" | bc`  
if [ "$COMPAREMODLOWER" -eq 1 ] && [ "$COMPAREMODUPPER" -eq 1 ]; then
   notify-send "Weather warning:" "It's raining moderately outside. Use an umbrella or wear a raincoat."
fi

COMPAREHEAVY=`echo "$RAINFALL > $HEAVYRAIN" | bc`
if [ "$COMPAREHEAVY" -eq 1 ]; then
   notify-send "Weather warning:" "It's raining heavily outside. Be warned for flooding and landslides. Stay in a safe place."
fi

COMPAREHEAVY=`echo "$RAINFALL > $VIOLENTRAIN" | bc`
if [ "$COMPAREHEAVY" -eq 1 ]; then
   notify-send "Weather warning:" "It's raining violently outside. Be warned for flooding and landslides. Stay in a safe place."
fi

UV=$(cat $WEATHER_FILE | awk '{print $6}')
if [ "$UV" -ge 3 ] && [ "$UV" -le 5 ]; then
   notify-send "Weather warning:" "It's $WEATHER outside and the ultraviolet is $UV. Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses to protect from the sun."
   
elif [ "$UV" -ge 6 ] && [ "$UV" -le 7 ]; then
   notify-send "Weather warning:" "It's $WEATHER outside and the ultraviolet is $UV. Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm to protect from the sun."
   
elif [ "$UV" -ge 8 ] && [ "$UV" -le 10 ]; then
   notify-send "Weather warning:" "It's $WEATHER outside and the ultraviolet is $UV. Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the shade."
   
elif [ "$UV" -gt 11 ]; then
   notify-send "Weather warning:" "It's $WEATHER outside and the ultraviolet is $UV. Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the the building."

fi

sleep 5m
done

