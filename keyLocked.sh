# This script will notify when Caps Lock or Num Lock are on using the xset q command.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like keyLocked.sh
# 4. Make file executable with chmod +x keyLocked.sh command
# 5. Add the keyLocked.sh command in Startup applications
# 6. Reboot the laptop
# 7. Press the Caps Lock key
# 8. A Caps Lock key notification message will be displayed
# 9. Press the Num Lock key
# 10. A Num Lock key notification message will be displayed

#!/usr/bin/bash
while true
do
   # 1. Get LED mask value for key lock with xset command
   LEDmask="$( xset q | grep 'LED mask' | awk '{ print $NF }' )"
 
   # 2. If LED mask value is equal to Caps lock LED mask value, show Caps lock notification
   if [ "$LEDmask" = 00000001 ]
   then
      notify-send "Caps lock is on."
   
   # 2. If LED mask value is equal to Num lock LED mask value, show Num lock notification
   elif [ "$LEDmask" = 00000002 ]
   then 
      notify-send "Num lock is on."
       
   # 3. If LED mask value is equal to Caps lock and Num lock LED mask value, show Caps lock and Num lock notification
   elif  [ "$LEDmask" = 00000003 ]   
   then
      notify-send "Caps lock and Num lock are on."
      
   # 4. If LED mask value is equal to LED mask value of no keys being locked, do nothing.   
   elif  [ "$LEDmask" = 00000000 ]   
   then
      :
   
   fi

   sleep 10
done      
