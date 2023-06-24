#!/usr/bin/bash

notify()
{
   # Set Action to Plug if low
   if [ "$1" = 'humid' ]; then
        WARNING="Stay in an airy place."
   
   # Set Action to Unplug if high    
   elif [ "$1" = 'hot' ]; then
        WARNING="Stay in a cooler place."
        
   elif [ "$1" = 'windy' ]; then
        WARNING="Stay inside."
  
   fi
    
   # Notify battery alert
   notify-send -u critical "Weather warning:" "It's very $1 and $WEATHER outside. $WARNING" 
}

notify-rain()
{

	if [ "$1" = 'raining lightly' ]; then
        WARNING="Use an umbrella or wear a raincoat."
   
   elif [ "$1" = 'raining moderately' ]; then
        WARNING="Use an umbrella or wear a raincoat."
   
   elif [ "$1" = 'raining heavily' ]; then
        WARNING="Be warned for flooding and landslides. Stay in a safe place."
        
   elif [ "$1" = 'raining violently' ]; then
        WARNING="Be warned for flooding and landslides. Stay in a safe place."
        
   fi
   
    notify-send -u critical "Weather warning:" "It's $1 outside. $WARNING"
}

notify-uv()
{
	if [ "$1" = 'mod-uv' ]; then
        WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses to protect from the sun."
   
   elif [ "$1" = 'high-uv' ]; then
        WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm to protect from the sun."
   
   elif [ "$1" = 'very-uv' ]; then
        WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the shade."
        
   elif [ "$1" = 'extreme-uv' ]; then
        WARNING="Use an umbrella and wear long-sleeved shirts, sunscreen, a wide brim hat, sunglasses and lip balm and stay in the the building."
   
   fi
       
   notify-send -u critical "Weather warning:" "It's $WEATHER outside and the ultraviolet is $UV. $WARNING"
}


while true
do

WEATHER_FILE=~/bin/weather.txt
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


curl wttr.in/Cebu?format="%l:+%h+%t+%w+%p+%u+%C" --silent --max-time 3 > $WEATHER_FILE

WEATHER=$(cut -d\  -f7- < $WEATHER_FILE)
WEATHER=$(echo "$WEATHER" | tr '[:upper:]' '[:lower:]') 

if [ -z "${WEATHER}" ]; then
	continue
else
	notify-send "Weather update: The weather is $WEATHER."
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
	:
fi

RAINFALL=$(awk '{print $5}' < $WEATHER_FILE)
RAINFALL=${RAINFALL:0:-2}

if [ "$RAINFALL" = "$NORAIN" ]; then
   :
fi

COMPARELIGHT=$(echo "$RAINFALL < $LIGHTRAIN" | bc)
MORETHANNO=$(echo "$RAINFALL > $NORAIN" | bc)
if [ "$COMPARELIGHT" -eq 1 ] && [ "$MORETHANNO" -eq 1 ] ; then
   notify-rain "raining lightly"
fi

COMPAREMODLIGTH=$(echo "$RAINFALL > $LIGHTRAIN" | bc)
COMPAREMODUPPER=$(echo "$RAINFALL < $HEAVYRAIN" | bc)  
if [ "$COMPAREMODLIGTH" -eq 1 ] && [ "$COMPAREMODUPPER" -eq 1 ]; then
   notify-rain "raining moderately"
fi

COMPAREHEAVY=$(echo "$RAINFALL > $HEAVYRAIN" | bc)
if [ "$COMPAREHEAVY" -eq 1 ]; then
   notify-rain "raining heavily"
fi

COMPAREVIOLENT=$(echo "$RAINFALL > $VIOLENTRAIN" | bc)
if [ "$COMPAREVIOLENT" -eq 1 ]; then
   notify-rain "raining violently"
fi

UV=$(awk '{print $6}' < $WEATHER_FILE)
COMPARELOWUV=$(echo "$UV > $LOWUV" | bc)
COMPAREMODUV=$(echo "$UV < $MODUV" | bc)
if [ "$COMPARELOWUV" -eq 1 ] && [ "$COMPAREMODUV" -eq 1 ] ; then
   notify-uv mod-uv
fi
   
COMPAREMODUV=$(echo "$UV > $MODUV" | bc)
COMPAREHIGHUV=$(echo "$UV < $HIGHUV" | bc)
if [ "$COMPAREMODUV" -eq 1 ] && [ "$COMPAREHIGHUV" -eq 1 ] ; then
   notify-uv high-uv
fi
   
COMPAREHIGHUV=$(echo "$UV > $HIGHUV" | bc)
COMPAREVERYUV=$(echo "$UV < $VERYUV" | bc)
if [ "$COMPAREHIGHUV" -eq 1 ] && [ "$COMPAREVERYUV" -eq 1 ] ; then
   notify-uv very-uv
fi
   
COMPAREEXTUV=$(echo "$UV > $VERYUV" | bc)
if [ "$COMPAREEXTUV" -eq 1 ]; then
   notify-uv extreme-uv

fi

sleep 15m
done
