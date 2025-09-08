#!/usr/bin/bash
# This script will alert when battery level is below or equal 40% and will notify when battery level is above or equal 80% to optimize laptop battery life.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# Steps for the task:
# 1. Install acpi
# 2. Create a bin directory inside your home directory
# 3. Change directory to the bin directory
# 4. Create the bash script file below with nano or gedit and save it with a filename like battAlert.sh
# 5. Make file executable with chmod +x battAlert.sh command
# 6. Add the battAlert.sh command in Startup applications
# 7. Reboot and use the laptop until the battery drains to 40%
# 8. A notification message will be displayed to plug the power cable to opitimize the battery life. Then a low battery notification sound will be played.
# 0. Let the laptop charge until 80%
# 10. A notification message will be displayed to unplug the power cable to opitimize the battery life. Then a full battery notification sound will be played.

notify()
{
   # Set Action to Plug if low
   if [ "$1" = 'low' ]; then
        ACTION="Plug"
   
   # Set Action to Unplug if high    
   elif [ "$1" = 'high' ]; then
        ACTION="Unplug"
   fi
    
   # Notify battery alert
   notify-send -u critical --app-name "⚠️ Battery alert:" "Battery reached $2%. $ACTION the power cable to optimize battery life!"
   
   # check if cvlc file program is existing then play low or high mp3
   #if [ -f "$(which mpv)" ]; then
      #cvlc --play-and-exit ~/Music/battery-"$1".mp3 2>/dev/null
    #  mpv ~/Music/battery-"$1".mp3 2>/dev/null
   #fi
}

while true
do

# 1. Set low.high and full battery levels
LOW_BATT=20
HIGH_BATT=80
FULL_BATT=100
BRIGHTNESS=$(cat /sys/class/backlight/amdgpu_bl1/brightness)
OPTIMAL_BRIGHTNESS=56206

#1. Get battery level and state
BATT_LEVEL=$(acpi -b | grep -P -o '[0-9]+(?=%)')
BATT_STATE=$(acpi -b | awk '{print $3}')  
   
#2. If battery battery level is 40 or less and discharging, notify low battery alert
if [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; then
   notify low "$BATT_LEVEL"
      
#3. If battery level is 40 or less and charging, do nothing
elif { [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [ "$BATT_STATE" = "Charging," ]; } || { [ "$BATT_LEVEL" -le "$LOW_BATT" ] && [ "$BATT_STATE" = "Unknown," ]; }; then
	if [ "$BRIGHTNESS" != "$OPTIMAL_BRIGHTNESS" ]; then
      brightnessctl --device=amdgpu_bl1 set 90%
	fi
	:
   
#4. If battery level is 80 or more, notify full battery alert
elif { [ "$BATT_LEVEL" -ge "$HIGH_BATT" ] && [ "$BATT_STATE" = "Charging," ]; } || { [ "$BATT_LEVEL" -eq "$FULL_BATT" ] && [ "$BATT_STATE" = "Full," ]; } || { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] && [ "$BATT_STATE" = "Not" ]; } || { [ "$BATT_LEVEL" -ge "$HIGH_BATT" ] && [ "$BATT_STATE" = "Unknown," ]; } || { [ "$BATT_LEVEL" -eq "$FULL_BATT" ] && [ "$BATT_STATE" = "Discharging," ]; }; then
   notify high "$BATT_LEVEL"
      
#5. If battery level is 80 or less and discharging, do nothing   
elif { [ "$BATT_LEVEL" -le "$HIGH_BATT" ] &&  [ "$BATT_STATE" = 'Discharging,' ]; } || { [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] &&  [ "$BATT_STATE" = 'Discharging,' ]; }; then
	if [ "$BRIGHTNESS" != "$OPTIMAL_BRIGHTNESS" ]; then
      brightnessctl --device=amdgpu_bl1 set 90%
	fi
	:
##5. If battery level is 80 or more and discharging, do nothing 
#elif [ "$BATT_LEVEL" -gt "$HIGH_BATT" ] &&  [ "$BATT_STATE" = 'Discharging,' ]; then
#   if [ "$BRIGHTNESS" != "$OPTIMAL_BRIGHTNESS" ]; then
#		echo $OPTIMAL_BRIGHTNESS | sudo tee /sys/class/backlight/amdgpu_bl1/brightness
#	fi

fi
   
sleep 5s
done


