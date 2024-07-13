#!/usr/bin/bash
# This script will alert when humidity, wind, rain and UV are above normal. Data will be taken from wttr.in
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2022

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like weatheralarm.sh
# 4. Make file executable with chmod +x weatheralarm.sh command
# 5. Add the weatheralarm.sh command in Startup applications
# 6. Reboot the laptop

#!/usr/bin/bash

notify-temp()
{
	case "$1" in 
		"humid")
			WARNING="Stay in an airy place."
			;;
			
		"hot")
			WARNING="Stay in a cooler place."
			;;
			
		"windy")
			WARNING="Stay inside."
			;;
		*)
			:
			;;
	esac        
    
	# Notify battery alert
	notify-send -u critical --app-name "Weather warning:    $TIME" "It's very $1 and $WEATHER outside. $WARNING" 
}

notify-rain()
{
	case "$1" in 
		"raining lightly")
			WARNING="Use an umbrella or wear a raincoat."
			;;
			
		"raining moderately")
			WARNING="Use an umbrella or wear a raincoat."
			;;
			
		"raining heavily")
			WARNING="Be warned for flooding and landslides. Stay in a safe place."
			;;
			
		"raining violently")
			WARNING="Be warned for flooding and landslides. Stay in a safe place."
			;;
		*)
			:
			;;
	esac 
   
    notify-send -u critical --app-name "Weather warning:    $TIME" "It's $1 outside. $WARNING"
}

notify-uv()
{
	case "$1" in 
		"mod-uv")
			WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses to protect from the sun."
			;;
			
		"high-uv")
			WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm to protect from the sun."
			;;
			
		"very-uv")
			WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the shade."
			;;
			
		"extreme-uv")
			WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the the building."
			;;
		*)
			:
			;;
	esac 
       
	notify-send -u critical --app-name "Weather warning:    $TIME" "It's $WEATHER outside and the ultraviolet is $UV. $WARNING"
}

while true; do
TIME=$(date +"%I:%M %p")

WEATHER_FILE=~/scriptlogs/weather.txt
VERY_HUMID=85
HIGH_TEMP=33
STRONG_WIND=50
NO_RAIN=0.0 
LIGHT_RAIN=2.5
HEAVY_RAIN=7.6
VIOLENT_RAIN=50
LOW_UV=2
MOD_UV=6
HIGH_UV=8
VERY_UV=11

curl wttr.in/Cebu?format="%l:+%h+%t+%w+%p+%u+%C" --silent --max-time 3 > $WEATHER_FILE

if [ $(echo $?) != "0" ]; then
	sleep 15m
fi

WEATHER=$(cut -d\  -f7- < $WEATHER_FILE)
WEATHER=$(echo "$WEATHER" | tr '[:upper:]' '[:lower:]') 

if [ -z "${WEATHER}" ]; then
	continue
else
	notify-send --app-name "Weather update:    $TIME" "The weather is $WEATHER."
fi

HUMID=$(awk '{print $2}' < $WEATHER_FILE)
HUMID=${HUMID:0:-1}
if [ "$HUMID" -ge "$VERY_HUMID" ]; then
   notify-temp humid 
else
   :
fi

TEMP=$(awk '{print $3}' < $WEATHER_FILE)
TEMP=${TEMP:1:-2}
if [ "$TEMP" -ge "$HIGH_TEMP" ]; then
	notify-temp hot
else
   :
fi

WIND=$(awk '{print $4}' < $WEATHER_FILE)
WIND=${WIND:1:-4}
if [ "$WIND" -ge "$STRONG_WIND" ]; then
  notify-temp windy
else
   :
fi

RAINFALL=$(awk '{print $5}' < $WEATHER_FILE)
RAINFALL=${RAINFALL:0:-2}

if [ "$RAINFALL" = "$NO_RAIN" ]; then
   :
fi

RAIN_IS_MORE_THAN_NO_RAIN=$(echo "$RAINFALL > $NO_RAIN" | bc)
RAIN_IS_LESS_THAN_LIGHT=$(echo "$RAINFALL < $LIGHT_RAIN" | bc)
if [ "$RAIN_IS_LESS_THAN_LIGHT" -eq 1 ] && [ "$RAIN_IS_MORE_THAN_NO_RAIN" -eq 1 ] ; then
   notify-rain "raining lightly"
fi

RAIN_IS_MORE_THAN_LIGHT=$(echo "$RAINFALL > $LIGHT_RAIN" | bc)
RAIN_IS_LESS_THAN_HEAVY=$(echo "$RAINFALL < $HEAVY_RAIN" | bc)  
if [ "$RAIN_IS_MORE_THAN_LIGHT" -eq 1 ] && [ "$RAIN_IS_LESS_THAN_HEAVY" -eq 1 ]; then
   notify-rain "raining moderately"
fi

RAIN_IS_MORE_THAN_HEAVY=$(echo "$RAINFALL > $HEAVY_RAIN" | bc)
RAIN_IS_LESS_THAN_VIOLENT=$(echo "$RAINFALL < $VIOLENT_RAIN" | bc)
if [ "$RAIN_IS_MORE_THAN_HEAVY" -eq 1 ]  && [ "$RAIN_IS_LESS_THAN_VIOLENT" -eq 1 ]; then
   notify-rain "raining heavily"
fi

RAIN_IS_MORE_VIOLENT=$(echo "$RAINFALL > $VIOLENT_RAIN" | bc)
if [ "$RAIN_IS_MORE_VIOLENT" -eq 1 ]; then
   notify-rain "raining violently"
fi

UV=$(awk '{print $6}' < $WEATHER_FILE)

if [ "$UV" -le "$LOW_UV" ]; then
	:
fi

UV_IS_MORE_THAN_LOW=$(echo "$UV > $LOW_UV" | bc)
UV_IS_LESS_THAN_MOD=$(echo "$UV < $MOD_UV" | bc)
if [ "$UV_IS_MORE_THAN_LOW" -eq 1 ] && [ "$UV_IS_LESS_THAN_MOD" -eq 1 ] ; then
   notify-uv mod-uv
fi
   
UV_IS_MORE_THAN_MOD=$(echo "$UV > $MOD_UV" | bc)
UV_IS_LESS_THAN_HIGH=$(echo "$UV < $HIGH_UV" | bc)
if [ "$UV_IS_MORE_THAN_MOD" -eq 1 ] && [ "$UV_IS_LESS_THAN_HIGH" -eq 1 ] ; then
   notify-uv high-uv
fi
   
UV_IS_MORE_THAN_HIGH=$(echo "$UV > $HIGH_UV" | bc)
UV_IS_LESS_THAN_VERY=$(echo "$UV < $VERY_UV" | bc)
if [ "$UV_IS_MORE_THAN_HIGH" -eq 1 ] && [ "$UV_IS_LESS_THAN_VERY" -eq 1 ] ; then
   notify-uv very-uv
fi
   
UV_IS_MORE_THAN_VERY=$(echo "$UV > $VERY_UV" | bc)
if [ "$UV_IS_MORE_THAN_VERY" -eq 1 ]; then
   notify-uv extreme-uv
fi

sleep 15m
done
