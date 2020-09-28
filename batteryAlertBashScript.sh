# This script will notify when battery level is below or equal 40% and will notify when battery level is above or equal 80% to optimize laptop battery life.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# This is an improvisation of hdgarrood's script on his answer at https://unix.stackexchange.com/questions/60778/how-can-i-get-an-alert-when-my-battery-is-about-to-die-in-linux-mint
# and αғsнιη's answer in https://askubuntu.com/questions/518928/how-to-write-a-script-to-listen-to-battery-status-and-alert-me-when-its-above.
# I added discharging and charging variables and conditions to detect the discharging and charging state of the battery.

# 1. Install acpi
# 2. Create a bin directory inside your home directory
# 3. Change directory to the bin directory
# 4. Create the bash script file below with nano or gedit and save it with a filename like batAlert.sh
# 5. Make file executable with chmod +x battAlert.sh
# 6. Add the battAlert.sh command in Startup applications
# 7. Reboot the laptop

#!/usr/bin/bash

while true
do
   battery_level=`acpi -b | grep -P -o '[0-9]+(?=%)'`
   battery_charge=`acpi -b | grep -P -o 'Charging'`
   battery_discharge=`acpi -b | grep -P -o 'Discharging'`
   
   if [ $battery_level -le 40 ] && [ "$battery_discharge" = Discharging ]
   then
      notify-send "Battery reached ${battery_level}%, plug the power cable to optimize battery life!"
      gnome-terminal -x nvlc ~/Music/low_batt.mp3
      
   elif [ $battery_level -le 40 ] && [ "$battery_charge" = Charging ]
   then
      :
    
   elif [ $battery_level -ge 80 ] && [ "$battery_charge" = Charging ]
   then
      notify-send "Battery reached ${battery_level}%, unplug the power cable to optimize battery life!" 
      gnome-terminal -x nvlc ~/Music/full_batt.mp3
         
   fi
   
   sleep 60
done
