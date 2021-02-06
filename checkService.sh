# This script will check if a process is running. If the process is not running, it will run the process. 
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# December 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like checkService.sh
# 4. Make file executable with chmod +x checkService.sh command
# 5. Add the checkService.sh command in Startup applications
# 6. Reboot the laptop and login
# 7. The script will run the process if the process is not running

#!/usr/bin/bash

declare -a SERVICES=("blueman-applet" "nm-applet")
declare -a SCRIPTS=("keyLocked.sh" "lowMemAlert.sh" "powerAlert.sh" "laptopLidClosed.sh")

srvCtr=0   
while [ "$srvCtr" -le "${#SERVICES[@]}" ] ; do
   
   # check if service is running comparing array item with pgrep -x 
   if pgrep -x "${SERVICES[$srvCtr]}" >/dev/null; then
      :
   
   # else, run the service
   else   
      ${SERVICES[$srvCtr]} &
      
   fi
   
   srvCtr=$[$srvCtr + 1] 
done

scrCtr=0   
while [ "$scrCtr" -le "${#SCRIPTS[@]}" ] ; do
   
   # check if script is running comparing array item with pgrep -x 
   if pidof -x "${SCRIPTS[$scrCtr]}" >/dev/null; then
      :
   
   # else, run the script
   else   
      ${SCRIPTS[$scrCtr]} &
      
   fi
   
   scrCtr=$[$scrCtr + 1]  
done
