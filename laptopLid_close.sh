#!/usr/bin/bash

while true
do
   lid_closed=`cat /proc/acpi/button/lid/LID0/state | grep -P -o 'close'`
   lid_open=`cat /proc/acpi/button/lid/LID0/state | grep -P -o 'open'`

   if [ "$lid_closed" = close ]
   then
           xscreensaver-command -lock  

   elif [ "$lid_open" = open ]
   then
      :

   fi
done

