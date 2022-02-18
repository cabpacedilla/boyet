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

#!/usr/bin/bash

notify()
{
   # Set Action to Plug if low
   if [ "$1" = 'low' ]; then
        ACTION="Plug"
   
   # Set Action to Unplug if full    
   elif [ "$1" = 'full' ]; then
        ACTION="Unplug"
   fi
    
   # Notify battery alert with battery level and Action
   notify-send -u normal -t 15000 "Battery reached ${2}%. ${ACTION} the power cable to optimize battery life!"
}

while true
do
   # 1. Get battery level and state
   BATT_LEVEL=$(acpi -b | grep -P -o '[0-9]+(?=%)')
   BATT_STATE=$(acpi -b | awk '{print $3}')   
 
   # 2. If battery battery level is 40 or less and discharging, notify low battery alert
   if [ "$BATT_LEVEL" -le 40 ] && [ "$BATT_STATE" = "Discharging," ]; then
      notify low "$BATT_LEVEL"
      
   # 3. If battery level is 40 or less and charging, do nothing
   elif { [ "$BATT_LEVEL" -le 40 ] && [ "$BATT_STATE" = "Charging," ]; } || { [ "$BATT_LEVEL" -le 40 ] && [ "$BATT_STATE" = "Unknown," ]; }; then
      :
   
   # 4. If battery level is 80 or more, notify full battery alert
   elif { [ "$BATT_LEVEL" -ge 80 ] && [ "$BATT_STATE" = "Charging," ]; } || { [ "$BATT_LEVEL" -eq 100 ] && [ "$BATT_STATE" = "Full," ]; } || { [ "$BATT_LEVEL" -gt 80 ] && [ "$BATT_STATE" = "Not" ]; } || { [ "$BATT_LEVEL" -ge 80 ] && [ "$BATT_STATE" = "Unknown," ]; } || { [ "$BATT_LEVEL" -eq 100 ] && [ "$BATT_STATE" = "Discharging," ]; }; then
       notify full "$BATT_LEVEL"
      
   # 5. If battery level is 80 and discharging, do nothing   
   elif [ "$BATT_LEVEL" -eq 80 ] &&  [ "$BATT_STATE" = 'Disharging,' ]; then
      :
   fi
   
   sleep 60
done

