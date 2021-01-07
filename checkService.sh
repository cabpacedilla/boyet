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

ctr=0   
while [ "$ctr" -le "${#SERVICES[@]}" ] ; do
   
   # check if process is running comparing array item with pgrep -x 
   if pgrep -x "${SERVICES[$ctr]}" >/dev/null; then
      :
   
   else   
      ${SERVICES[$ctr]} &
      
   fi
   
   ctr=$[$ctr + 1] 
done
