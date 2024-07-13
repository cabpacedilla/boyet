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


while true
do
TIME=$(date +"%I:%M %p")

WEATHER_FILE=~/scriptlogs/weather.txt
VERYHUMID=85
HIGHTEMP=33
STRONGWIND=50
NORAIN=0.0 
LIGHTRAIN=2.5
HEAVYRAIN=7.6
VIOLENTRAIN=50
LOWUV=2
MODUV=6
HIGHUV=8
VERYUV=11

curl wttr.in/Banilad?format="%l:+%h+%t+%w+%p+%u+%C" --silent --max-time 3 > $WEATHER_FILE

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
if [ "$HUMID" -ge "$VERYHUMID" ]; then
   notify humid 
else
   :
fi

TEMP=$(awk '{print $3}' < $WEATHER_FILE)
TEMP=${TEMP:1:-2}
if [ "$TEMP" -ge "$HIGHTEMP" ]; then
	notify hot
else
   :
fi

WIND=$(awk '{print $4}' < $WEATHER_FILE)
WIND=${WIND:1:-4}
if [ "$WIND" -ge "$STRONGWIND" ]; then
  notify windy
else
   :
fi

RAINFALL=$(awk '{print $5}' < $WEATHER_FILE)
RAINFALL=${RAINFALL:0:-2}

if [ "$RAINFALL" = "$NORAIN" ]; then
   :
fi

ISREAINMORENO=$(echo "$RAINFALL > $NORAIN" | bc)
ISRAINLESSLIGHT=$(echo "$RAINFALL < $LIGHTRAIN" | bc)
if [ "$ISRAINLESSLIGHT" -eq 1 ] && [ "$ISREAINMORENO" -eq 1 ] ; then
   notify-rain "raining lightly"
fi

ISRAINMORELIGHT=$(echo "$RAINFALL > $LIGHTRAIN" | bc)
ISRAINLESSHEAVY=$(echo "$RAINFALL < $HEAVYRAIN" | bc)  
if [ "$ISRAINMORELIGHT" -eq 1 ] && [ "$ISRAINLESSHEAVY" -eq 1 ]; then
   notify-rain "raining moderately"
fi

ISRAINMOREHEAVY=$(echo "$RAINFALL > $HEAVYRAIN" | bc)
ISRAINLESSVIOLENT=$(echo "$RAINFALL < $VIOLENTRAIN" | bc)
if [ "$ISRAINMOREHEAVY" -eq 1 ]  && [ "$ISRAINLESSVIOLENT" -eq 1 ]; then
   notify-rain "raining heavily"
fi

ISRAINMOREVIOLENT=$(echo "$RAINFALL > $VIOLENTRAIN" | bc)
if [ "$ISRAINMOREVIOLENT" -eq 1 ]; then
   notify-rain "raining violently"
fi

UV=$(awk '{print $6}' < $WEATHER_FILE)

if [ "$UV" -le "$LOWUV" ]; then
	:
fi

ISUVMORELOW=$(echo "$UV > $LOWUV" | bc)
ISUVLESSMOD=$(echo "$UV < $MODUV" | bc)
if [ "$ISUVMORELOW" -eq 1 ] && [ "$ISUVLESSMOD" -eq 1 ] ; then
   notify-uv mod-uv
fi
   
ISUVMOREMOD=$(echo "$UV > $MODUV" | bc)
ISUVLESSHIGH=$(echo "$UV < $HIGHUV" | bc)
if [ "$ISUVMOREMOD" -eq 1 ] && [ "$ISUVLESSHIGH" -eq 1 ] ; then
   notify-uv high-uv
fi
   
ISUVMOREHIGH=$(echo "$UV > $HIGHUV" | bc)
ISUVLESSVERY=$(echo "$UV < $VERYUV" | bc)
if [ "$ISUVMOREHIGH" -eq 1 ] && [ "$ISUVLESSVERY" -eq 1 ] ; then
   notify-uv very-uv
fi
   
ISUVMOREVERY=$(echo "$UV > $VERYUV" | bc)
if [ "$ISUVMOREVERY" -eq 1 ]; then
   notify-uv extreme-uv

fi

sleep 15m
done
