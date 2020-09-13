# Battery alert script to optimize laptop battery life
# 1. Install acpi
# 2. Create a bin directory inside your home directory
# 3. Change directory to the bin directory
# 4. Create the bash script file below with nano or gedit and save it with a filename like batAlert.sh
# 5. Make file executable with chmod +x batAlert.sh
# 6. Add the batAlert.sh command in Startup applications
# 7. Reboot the laptop

# Battery alert script that notifies when battery is below or equal 40% and above or equal 80% to optimize laptop battery life 

#!/usr/bin/bash

while true
do
   battery_level=`acpi -b | grep -P -o '[0-9]+(?=%)'`
   battery_charge=`acpi -b | grep -P -o 'Charging'`
   battery_discharge=`acpi -b | grep -P -o 'Discharging'`
   
   if [ $battery_level -le 40 ] && [ "$battery_discharge" = Discharging ]
   then
      notify-send "Battery reached ${battery_level}, plug the power cable to optimize battery life!"
      
   elif [ $battery_level -le 40 ] && [ "$battery_charge" = Charging ]
   then
      :
      
   elif [ $battery_level -ge 80 ] && [ "$battery_charge" = Charging ]
   then
      notify-send "Battery reached ${battery_level}%, unplug the power cable to optimize battery life!"  
      
   fi
   
   sleep 60  
done
