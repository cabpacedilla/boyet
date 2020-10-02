# This script will activate screen lock when the laptop lid will be closed for auto lid close security in Ubuntu Unity
# This script was written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# Steps:
# 1. Install ligthdm display manager and set lightdm as a the default display manager
# 2. Create a bin directory inside your home directory
# 3. Change directory to the bin directory
# 4. Create the bash script file below with nano or gedit and save it with a filename like lid_closed.sh
# 5. Make file executable with chmod +x lid_closed.sh command
# 6. Add the lid_closed.sh command in Startup applications
# 7. Reboot the laptop
# 8. Close the laptop lid
# 9. Open the laptop lid
# 10. lightdm login screen will be displayed

#!/usr/bin/bash
while true
do
   lid_closed=`less /proc/acpi/button/lid/LID0/state | grep -P -o 'close'`
   lid_open=`less /proc/acpi/button/lid/LID0/state | grep -P -o 'open'`
   
   if [ "$lid_closed" = close ]
   then
      dm-tool switch-to-greeter
      
   elif [ "$lid_open" = open ]
   then
      :
      
   fi
   sleep 1
done
