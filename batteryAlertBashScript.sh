# This script will alert when battery level is below or equal 40% and will notify when battery level is above or equal 80% to optimize laptop battery life.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# Steps for the task:
# 1. Install acpi
# 2. Install vlc
# 3. Create a bin directory inside your home directory
# 4. Change directory to the bin directory
# 5. Create the bash script file below with nano or gedit and save it with a filename like battAlert.sh
# 6. Make file executable with chmod +x battAlert.sh command
# 7. Add the battAlert.sh command in Startup applications
# 8. Reboot and use the laptop until the battery drains to 40%
# 9. A notification message will be displayed to plug the power cable to opitimize the battery life. Then a low battery notification sound will be played.
# 10. Let the laptop charge until 80%
# 11. A notification message will be displayed to unplug the power cable to opitimize the battery life. Then a full battery notification sound will be played.

#!/usr/bin/bash

notify()
{
   # set plug or unplug 
   if [ "$1" = 'low' ]; then
        ACTION="Plug"
        
   elif [ "$1" = 'full' ]; then
        ACTION="Unplug"
   fi
    
   # notify to plug or unplug based on battery level
   notify-send -u normal -t 15000 "Battery reached ${2}%. ${ACTION} the power cable to optimize battery life!"
   
   # check if cvlc file program is existing then play low or full mp3
   if [ -f "$(which cvlc)" ]; then
      #cvlc --play-and-exit ~/Music/battery-"$1".mp3 2>/dev/null
      mpv ~/Music/battery-"$1".mp3 2>/dev/null
   fi
}

while true
do
   BATT_LEVEL=$(acpi -b | grep -P -o '[0-9]+(?=%)')
   BATT_STATE=$(acpi -b | awk '{print $3}')   
 
   if [ "$BATT_LEVEL" -le 40 ] && [ "$BATT_STATE" = 'Discharging,' ]; then
      # call notify function and pass low argument and battery level 
      # if battery level is 40 or less and discharging
      notify low ${BATT_LEVEL}
      
   elif [ "$BATT_LEVEL" -le 40 ] && [ "$BATT_STATE=" = 'Charging,' ]; then
      # do nothing if battery level is 40 or less and charging
      :
      
   elif [ "$BATT_LEVEL" -le 40 ] && [ "$BATT_STATE=" = 'Unknown,' ]; then
      # do nothing if battery level is 40 or less and charging
      :
    
   elif [ "$BATT_LEVEL" -ge 80 ] &&  [ "$BATT_STATE" = 'Charging,' ]; then
      # call notify function and pass full argument and battery level
      # if battery level is 80 or more and charging
      notify full ${BATT_LEVEL}
      
   elif [ "$BATT_LEVEL" -eq 80 ] &&  [ "$BATT_STATE" = 'Disharging,' ]; then
      # call notify function and pass full argument and battery level
      # if battery level is 80 or more and charging
      :
   
   elif [ "$BATT_LEVEL" -ge 80 ] &&  [ "$BATT_STATE" = 'Unknown,' ]; then
      # call notify function and pass full argument and battery level
      # if battery level is 80 or more and charging
      notify full ${BATT_LEVEL}
      
   elif [ "$BATT_LEVEL" -gt 80 ] && [ "$BATT_STATE" = 'Not' ]; then
      # call notify function and pass full argument and battery level
      # if battery level is 100 and not charging
      notify full ${BATT_LEVEL}
        
   elif [ "$BATT_LEVEL" -gt 80 ] && [ "$BATT_STATE" = 'Full,' ]; then
      # call notify function and pass full argument and battery level
      # if battery level is 100 and charging
      notify full ${BATT_LEVEL} 
   
   elif [ "$BATT_LEVEL" -eq 100 ] && [ "$BATT_STATE" = 'Discharging,' ]; then
      # call notify function and pass full argument and battery level
      # if battery level is 100 and charging
      notify full ${BATT_LEVEL} 
      
   fi
   
   sleep 60
done

