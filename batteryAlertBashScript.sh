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
while true
do
   battery_level=$(acpi -b | grep -P -o '[0-9]+(?=%)')
   battery_charge="$(acpi -b | grep -P -o 'Charging')"
   battery_discharge="$(acpi -b | grep -P -o 'Discharging')"

   if [ $battery_level -le 40 ] && [ "$battery_discharge" = Discharging ]
   then
      notify-send "Battery reached ${battery_level}%, plug the power cable to optimize battery life!"
      gnome-terminal -- nvlc --play-and-exit ~/Music/low_battery.mp3 
      
   elif [ $battery_level -le 40 ] && [ "$battery_charge" = Charging ]
   then
      :
    
   elif [ $battery_level -ge 80 ] && [ "$battery_charge" = Charging ]
   then
      notify-send "Battery reached ${battery_level}%, unplug the power cable to optimize battery life!" 
      gnome-terminal -- nvlc --play-and-exit ~/Music/glados_bat_full_2.mp3 
      
   fi
   
   sleep 60
done
