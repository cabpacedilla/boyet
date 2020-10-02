# This script will activate screen lock when the laptop lid will be closed for auto lid close security in Ubuntu Unity
# This script was written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# 1. Install first the ligthdm display manager and set lightdm as a the default display manager
# 2

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
