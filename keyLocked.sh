# This script will notify when Caps Lock or Num Lock are on using the xset q command.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# This is based from taliezin answer in https://unix.stackexchange.com/questions/207754/how-to-identify-if-num-lock-or-caps-lock-is-turned-on-in-rhel-6-6 
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
   value="$(xset q | grep 'LED mask' | awk '{ print $NF }')"

   if [ "$value" = 00000001 ]
   then
      notify-send -t 10000 "Caps lock is on."
   
   elif [ "$value" = 00000002 ]
   then 
      notify-send -t 10000 "Num lock is on."
       
   elif  [ "$value" = 00000003 ]   
   then
      notify-send -t 10000 "Caps lock and Num lock are on."
   
   elif [ "$value" = 00000000 ] 
   then
      : 
   
   fi

sleep 15
done    



